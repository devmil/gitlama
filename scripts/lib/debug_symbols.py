"""Private release diagnostics: native identities and exact-byte inventories."""
from __future__ import annotations

import hashlib
import json
import mmap
from pathlib import Path
import struct
import uuid


class SymbolError(ValueError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _pdb(data) -> dict:
    # MSF 7 stream directory; stream 1 is the PDB information stream.
    block, _, total, size, _, table = struct.unpack_from('<6I', data, 32)
    if block not in (512, 1024, 2048, 4096, 8192) or total * block > len(data):
        raise SymbolError('invalid_pdb_blocks')
    count = (size + block - 1) // block
    if count * 4 > block:
        raise SymbolError('pdb_directory_too_large')
    blocks = struct.unpack_from(f'<{count}I', data, table * block)
    directory = b''.join(data[n * block:(n + 1) * block] for n in blocks)[:size]
    streams, = struct.unpack_from('<I', directory)
    sizes = struct.unpack_from(f'<{streams}I', directory, 4)
    cursor = 4 + streams * 4
    for index, length in enumerate(sizes):
        count = 0 if length == 0xffffffff else (length + block - 1) // block
        blocks = struct.unpack_from(f'<{count}I', directory, cursor)
        cursor += count * 4
        if index == 1:
            info = b''.join(data[n * block:(n + 1) * block] for n in blocks)[:length]
            age, = struct.unpack_from('<I', info, 8)
            guid = str(uuid.UUID(bytes_le=info[12:28]))
            return {'format': 'pdb', 'ids': {'pdb': f'{guid}-{age}'}, 'debug': True}
    raise SymbolError('missing_pdb_information')


def _pe(data) -> dict:
    base, = struct.unpack_from('<I', data, 0x3c)
    if data[base:base + 4] != b'PE\0\0':
        raise SymbolError('invalid_pe_signature')
    machine, sections = struct.unpack_from('<HH', data, base + 4)
    optional_size, = struct.unpack_from('<H', data, base + 20)
    optional = base + 24
    magic, = struct.unpack_from('<H', data, optional)
    debug_rva, debug_size = struct.unpack_from('<II', data, optional + (112 if magic == 0x20b else 96) + 6 * 8)
    start = optional + optional_size
    def offset(rva):
        for index in range(sections):
            at = start + index * 40
            virtual_size, address, raw_size, raw = struct.unpack_from('<4I', data, at + 8)
            if address <= rva < address + max(virtual_size, raw_size):
                return raw + rva - address
        raise SymbolError('invalid_pe_debug_rva')
    arch = {0x8664: 'x86_64', 0xaa64: 'arm64'}.get(machine, hex(machine))
    if debug_rva == 0:
        stamp, = struct.unpack_from('<I', data, base + 8)
        size, = struct.unpack_from('<I', data, optional + 56)
        return {'format': 'pe', 'ids': {arch: f'code-{stamp:08x}-{size:x}'}, 'debug': False}
    for at in range(offset(debug_rva), offset(debug_rva) + debug_size, 28):
        kind, length, _, pointer = struct.unpack_from('<4I', data, at + 12)
        if kind == 2 and length >= 24 and data[pointer:pointer + 4] == b'RSDS':
            guid = str(uuid.UUID(bytes_le=data[pointer + 4:pointer + 20]))
            age, = struct.unpack_from('<I', data, pointer + 20)
            arch = {0x8664: 'x86_64', 0xaa64: 'arm64'}.get(machine, hex(machine))
            return {'format': 'pe', 'ids': {arch: f'{guid}-{age}'}, 'debug': False}
    raise SymbolError('missing_pe_codeview_identity')


def _macho(data, base=0) -> dict:
    magic = data[base:base + 4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        count, = struct.unpack_from('>I', data, base + 4)
        ids = {}
        debug = False
        for index in range(count):
            at = base + 8 + index * (32 if magic[-1] == 0xbf else 20)
            offset, = struct.unpack_from('>Q' if magic[-1] == 0xbf else '>I', data, at + 8)
            child = _macho(data, base + offset)
            ids.update(child['ids'])
            debug |= child['debug']
        return {'format': 'macho', 'ids': ids, 'debug': debug}
    endian = '<' if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe') else '>'
    cpu, _, _, count = struct.unpack_from(endian + '4I', data, base + 4)
    at = base + (32 if magic in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf') else 28)
    ids = {}
    debug = False
    for _ in range(count):
        command, size = struct.unpack_from(endian + '2I', data, at)
        if size < 8 or at + size > len(data):
            raise SymbolError('invalid_macho_command')
        if command == 0x1b:
            ids[{0x100000c: 'arm64', 0x1000007: 'x86_64'}.get(cpu, hex(cpu))] = str(uuid.UUID(bytes=data[at + 8:at + 24]))
        if command == 0x19 and data[at + 8:at + 24].rstrip(b'\0') == b'__DWARF':
            sections, = struct.unpack_from(endian + 'I', data, at + 64)
            for index in range(sections):
                section = at + 72 + index * 80
                length, = struct.unpack_from(endian + 'Q', data, section + 40)
                if data[section:section + 16].rstrip(b'\0') == b'__debug_info' and length:
                    debug = True
        at += size
    if not ids:
        raise SymbolError('missing_macho_uuid')
    return {'format': 'macho', 'ids': ids, 'debug': debug}


def _elf(data) -> dict:
    wide = data[4] == 2
    endian = '<' if data[5] == 1 else '>'
    machine, = struct.unpack_from(endian + 'H', data, 18)
    shoff, = struct.unpack_from(endian + ('Q' if wide else 'I'), data, 40 if wide else 32)
    entry, count, names_index = struct.unpack_from(endian + '3H', data, 58 if wide else 46)
    fmt = endian + ('IIQQQQIIQQ' if wide else '10I')
    def section(index):
        return struct.unpack_from(fmt, data, shoff + index * entry)
    strings = section(names_index)
    names = data[strings[4]:strings[4] + strings[5]]
    debug = False
    build = None
    for index in range(count):
        item = section(index)
        name = names[item[0]:].split(b'\0', 1)[0]
        debug |= name in (b'.debug_info', b'.zdebug_info') and item[5] > 0
        if item[1] != 7:
            continue
        at, end = item[4], item[4] + item[5]
        while at + 12 <= end:
            name_size, desc_size, kind = struct.unpack_from(endian + '3I', data, at)
            at += 12
            owner = data[at:at + name_size].rstrip(b'\0')
            at += (name_size + 3) & ~3
            desc = data[at:at + desc_size]
            at += (desc_size + 3) & ~3
            if owner == b'GNU' and kind == 3:
                build = desc.hex()
    if not build:
        raise SymbolError('missing_elf_build_id')
    return {'format': 'elf', 'ids': {{62: 'x86_64', 183: 'arm64'}.get(machine, str(machine)): build}, 'debug': bool(debug)}


def identity(path: Path) -> dict | None:
    if path.stat().st_size < 32:
        return None
    with path.open('rb') as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        head = data[:32]
        try:
            if head.startswith(b'\x7fELF'):
                return _elf(data)
            if head.startswith(b'MZ'):
                return _pe(data)
            if head[:4] in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
                return _macho(data)
            if head.startswith(b'Microsoft C/C++ MSF 7.00'):
                return _pdb(data)
        except (struct.error, IndexError, OverflowError) as error:
            raise SymbolError('malformed_native_identity') from error
    return None


def matches(binary: dict, symbols: dict) -> bool:
    if binary['format'] == 'pe' and symbols['format'] == 'pdb':
        return set(binary['ids'].values()) == set(symbols['ids'].values())
    return binary['format'] == symbols['format'] and all(
        symbols['ids'].get(arch) == value for arch, value in binary['ids'].items())


def file_record(path: Path, relative: str) -> dict:
    return {'file': relative, 'bytes': path.stat().st_size, 'sha256': sha256(path)}


def canonical(value: dict) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()

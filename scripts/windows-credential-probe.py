#!/usr/bin/env python3
"""Check WinCred write/delete capability using only a new synthetic entry."""
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import uuid


def check(api, last_error, persistence=2):
    if os.name != 'nt':
        raise SystemExit('windows_credential_probe_requires_windows')
    if persistence is None:
        return {'schema': 1, 'capability': 'windows_credential_manager', 'persistence': None,
                'acceptance': {'passed': False, 'failures': ['credential_persistence_unavailable']}}
    class Credential(ctypes.Structure):
        _fields_ = [('Flags', wintypes.DWORD), ('Type', wintypes.DWORD),
                    ('TargetName', wintypes.LPWSTR), ('Comment', wintypes.LPWSTR),
                    ('LastWritten', wintypes.FILETIME), ('CredentialBlobSize', wintypes.DWORD),
                    ('CredentialBlob', ctypes.POINTER(ctypes.c_ubyte)), ('Persist', wintypes.DWORD),
                    ('AttributeCount', wintypes.DWORD), ('Attributes', ctypes.c_void_p),
                    ('TargetAlias', wintypes.LPWSTR), ('UserName', wintypes.LPWSTR)]
    api.CredWriteW.argtypes = [ctypes.POINTER(Credential), wintypes.DWORD]
    api.CredWriteW.restype = wintypes.BOOL
    api.CredDeleteW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD]
    api.CredDeleteW.restype = wintypes.BOOL
    target = 'GitLama/qualification-capability/' + str(uuid.uuid4())
    blob = (ctypes.c_ubyte * 32)(*range(32))  # Public fixture, never a real credential.
    value = Credential(Type=1, TargetName=target, CredentialBlobSize=32,
                       CredentialBlob=blob, Persist=persistence)
    written = bool(api.CredWriteW(ctypes.byref(value), 0))
    result = {'persistence': persistence, 'credentialWrite': written, 'writeError': 0 if written else last_error()}
    if written:
        deleted = bool(api.CredDeleteW(target, 1, 0))
        result.update(credentialDeleted=deleted, deleteError=0 if deleted else last_error())
    result.update(schema=1, capability='windows_credential_manager')
    result['acceptance'] = {
        'passed': written and result.get('credentialDeleted', False),
        'failures': ([] if written and result.get('credentialDeleted', False) else
                     ['credential_write_unavailable' if not written else 'credential_cleanup_failed']),
    }
    return result


def logon_context():
    # Inspect only numeric token/session fields. Never read the session's user,
    # domain, authentication package strings, or any credential material.
    class Luid(ctypes.Structure):
        _fields_ = [('LowPart', wintypes.DWORD), ('HighPart', wintypes.LONG)]
    class Statistics(ctypes.Structure):
        _fields_ = [('TokenId', Luid), ('AuthenticationId', Luid)]
    class UnicodeString(ctypes.Structure):
        _fields_ = [('Length', wintypes.USHORT), ('MaximumLength', wintypes.USHORT),
                    ('Buffer', ctypes.c_void_p)]
    class Session(ctypes.Structure):
        _fields_ = [('Size', wintypes.ULONG), ('LogonId', Luid),
                    ('UserName', UnicodeString), ('LogonDomain', UnicodeString),
                    ('AuthenticationPackage', UnicodeString),
                    ('LogonType', wintypes.ULONG), ('Session', wintypes.ULONG)]
    credential_api = ctypes.WinDLL('Advapi32.dll', use_last_error=True)
    credential_api.CredGetSessionTypes.argtypes = [wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    credential_api.CredGetSessionTypes.restype = wintypes.BOOL
    persistence = (wintypes.DWORD * 7)()
    supported = bool(credential_api.CredGetSessionTypes(7, persistence))
    support = ({'genericMaximumPersistence': persistence[1]} if supported else
               {'sessionTypesError': ctypes.get_last_error()})
    kernel = ctypes.WinDLL('Kernel32.dll', use_last_error=True)
    advapi = ctypes.WinDLL('Advapi32.dll', use_last_error=True)
    security = ctypes.WinDLL('Secur32.dll', use_last_error=True)
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    advapi.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
    advapi.GetTokenInformation.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                          wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    security.LsaGetLogonSessionData.argtypes = [ctypes.POINTER(Luid), ctypes.POINTER(ctypes.c_void_p)]
    security.LsaGetLogonSessionData.restype = wintypes.LONG
    security.LsaFreeReturnBuffer.argtypes = [ctypes.c_void_p]
    handle = wintypes.HANDLE()
    if not advapi.OpenProcessToken(kernel.GetCurrentProcess(), 8, ctypes.byref(handle)):
        return {'logonQueryError': ctypes.get_last_error()}
    try:
        buffer = ctypes.create_string_buffer(256)
        length = wintypes.DWORD()
        if not advapi.GetTokenInformation(handle, 10, buffer, len(buffer), ctypes.byref(length)):
            return {'logonQueryError': ctypes.get_last_error()}
        stats = ctypes.cast(buffer, ctypes.POINTER(Statistics)).contents
        data = ctypes.c_void_p()
        status = security.LsaGetLogonSessionData(ctypes.byref(stats.AuthenticationId), ctypes.byref(data))
        if status or not data:
            return {'logonQueryStatus': f'0x{status & 0xffffffff:08X}'}
        try:
            value = ctypes.cast(data, ctypes.POINTER(Session)).contents
            return {**support, 'logonType': value.LogonType, 'logonSession': value.Session}
        finally:
            security.LsaFreeReturnBuffer(data)
    finally:
        kernel.CloseHandle(handle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require', action='store_true')
    parser.add_argument('--persistence', choices=['auto', 'session', 'machine'], default='auto')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if os.name != 'nt':
        raise SystemExit('windows_credential_probe_requires_windows')
    context = logon_context()
    persistence = ({1: 1, 2: 2, 3: 2}.get(context.get('genericMaximumPersistence'))
                   if args.persistence == 'auto' else 1 if args.persistence == 'session' else 2)
    result = check(ctypes.WinDLL('Advapi32.dll', use_last_error=True), ctypes.get_last_error, persistence)
    result.update(context)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result))
    return 1 if args.require and not result['acceptance']['passed'] else 0


if __name__ == '__main__':
    raise SystemExit(main())

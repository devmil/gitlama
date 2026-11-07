#!/usr/bin/env python3
"""Keep generated bridge imports confined to the native repository."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
errors = []
for path in (root / 'lib').rglob('*.dart'):
    rel = path.relative_to(root / 'lib').as_posix()
    if rel.startswith('rust/'):
        continue
    imports = re.findall(r"(?:import|export) ['\"]([^'\"]+)", path.read_text(encoding="utf-8"))
    if any('/rust/' in value or 'flutter_rust_bridge' in value for value in imports):
        if not (
            (
                rel.startswith('repositories/impl/native_')
                and rel.endswith('_repository.dart')
            )
            # The generated session call seam and the remote session calls
            # carry bridge value types; only the seam's FFI forwarder calls
            # the in-process library.
            or rel == 'repositories/impl/repository_session_calls.g.dart'
            # Generated name-based conversions between bridge and model enums.
            or rel == 'repositories/impl/native_enum_mappers.g.dart'
            # Mappers and the library loader the native implementations share,
            # so no implementation imports another.
            or rel == 'repositories/impl/native_mappers.dart'
            or rel == 'repositories/impl/remote/remote_session_calls.dart'
            # An inspector window's calls carry the same value types to the
            # main window, which reads its host for it.
            or rel == 'repositories/impl/remote/remote_inspection_calls.dart'
        ):
            errors.append(f'{rel}: native boundary import')
        if rel in (
            'repositories/impl/remote/remote_session_calls.dart',
            'repositories/impl/remote/remote_inspection_calls.dart',
        ) and (
            'RustLib' in path.read_text(encoding="utf-8")
            or any(v.endswith('/rust/api.dart') and ' as native' in v for v in imports)
        ):
            errors.append(f'{rel}: remote session calls must not reach the native library')
    if rel.startswith(('services/', 'models/')) and any('package:flutter/' in v for v in imports):
        errors.append(f'{rel}: presentation dependency')
    if rel.startswith('repositories/') and any('/services/' in v for v in imports):
        errors.append(f'{rel}: repository depends on service')
    if rel.startswith('services/') and any('/impl/' in v for v in imports):
        errors.append(f'{rel}: service depends on repository implementation')
    if rel.startswith(('app/', 'widgets/', 'screens/')) and any(
        '/repositories/impl/' in v or v.startswith('../repositories/impl/')
        for v in imports
    ):
        errors.append(f'{rel}: presentation depends on repository implementation')
    # Native implementations share impl/native_mappers.dart instead of
    # importing each other. Reviewed compositions: the remote session factory
    # builds the session adapter over the wire calls, and the SSH connection
    # starts its process through the native child-process launcher.
    if rel.startswith('repositories/impl/') and rel not in (
        'repositories/impl/remote/remote_session_factory.dart',
        'repositories/impl/remote/ssh_remote_connection_repository.dart',
    ) and any(
        re.search(r"(^|/)native_[a-z_]+_repository\.dart$", v) for v in imports
    ):
        errors.append(f'{rel}: imports another native repository implementation')
    # Enums never map by position: a variant added on one side would shift
    # every later value. Use the generated name-based mappers instead.
    if re.search(r"\.values\s*\[[^\]]*\.index\s*\]", path.read_text(encoding="utf-8")):
        errors.append(f'{rel}: enum mapped by position (.values[x.index])')

# Each repository contract has one owning service; other services go through
# that service. lib/di registers implementations and is not a consumer. The
# session backend is split into one contract per command family, each owned
# by its family service; the backend router is a repository implementation.
SHARED_REPOSITORIES: dict[str, set[str]] = {}
consumers: dict[str, set[str]] = {}
for path in (root / 'lib' / 'services').rglob('*.dart'):
    rel = path.relative_to(root / 'lib').as_posix()
    for value in re.findall(r"import ['\"]([^'\"]+)", path.read_text(encoding="utf-8")):
        name = value.rsplit('/', 1)[-1]
        if '/repositories/' in f'/{value}' and '/impl/' not in value and name.endswith('_repository.dart'):
            consumers.setdefault(name, set()).add(rel)
for name, users in sorted(consumers.items()):
    allowed = SHARED_REPOSITORIES.get(name)
    if len(users) > 1 and users != allowed:
        errors.append(
            f'repositories/{name}: one owning service expected, used by {", ".join(sorted(users))}'
        )
for path in (root / 'lib').rglob('*.dart'):
    rel = path.relative_to(root / 'lib').as_posix()
    if rel.startswith(('app/', 'widgets/', 'screens/')) and any(
        '/repositories/' in f'/{v}' for v in re.findall(r"import ['\"]([^'\"]+)", path.read_text(encoding="utf-8"))
    ):
        errors.append(f'{rel}: presentation depends on a repository')

# Rust layering (LAY-7). Three crates under rust-core, each a layer:
# - contract/ (gitlama_contract): the bridge types. Data only: flutter_rust_bridge reads it as a
#   third-party input and would turn every public function or method, and every `Default`
#   impl, into Dart API.
# - application/ (gitlama_application): the domain (domain/), the use cases (application/), the
#   feature modules and the remote wire adapter (wire/). The application layer depends on no
#   adapter; the domain depends on nothing above it.
# - src/ (gitlama_core): the FRB facade (api.rs with its generated bridge) and the desktop-only
#   services. Nothing else reaches into the facade.
# The remote helper builds on the application crate, never on the desktop library.
# Doc comments may name the layers.
RUST = root / 'rust-core'
CONTRACT_SRC = RUST / 'contract' / 'src'
APPLICATION_SRC = RUST / 'application' / 'src'
CORE_SRC = RUST / 'src'


def rust_code(path):
    """The Rust source without comments, so documentation may mention other layers."""
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def references(code, module):
    return re.search(rf"\bcrate::({module}\b|\{{[^}}]*\b{module}\b)|\bsuper::{module}\b", code)


def manifest_dependencies(path):
    """The dependency names a Cargo manifest declares, in any dependency table."""
    names, table = set(), None
    for line in path.read_text(encoding="utf-8").splitlines():
        header = re.match(r'\s*\[(.+)\]\s*$', line)
        if header:
            table = header.group(1)
            continue
        entry = re.match(r'([A-Za-z0-9_-]+)\s*=', line)
        if entry and table and table.split('.')[-1].endswith('dependencies'):
            names.add(entry.group(1))
    return names


INTERNAL = {'gitlama_contract', 'gitlama_application', 'gitlama_core', 'gitlama-remote-helper'}
for crate, allowed in (
    ('contract', set()),
    ('application', {'gitlama_contract'}),
    ('remote-helper', {'gitlama_application'}),
):
    for name in sorted((manifest_dependencies(RUST / crate / 'Cargo.toml') & INTERNAL) - allowed):
        errors.append(f'rust-core/{crate}/Cargo.toml: depends on {name}')
for crate, forbidden in (
    ('contract', ('gitlama_application', 'gitlama_core', 'devmil_git', 'flutter_rust_bridge')),
    ('application', ('gitlama_core', 'flutter_rust_bridge')),
    ('remote-helper', ('gitlama_core', 'flutter_rust_bridge')),
):
    for path in sorted((RUST / crate).glob('**/*.rs')):
        code = rust_code(path)
        for name in forbidden:
            if re.search(rf'\b{name}::', code):
                errors.append(f'{path.relative_to(root).as_posix()}: reaches {name}')

for path in sorted(CONTRACT_SRC.rglob('*.rs')):
    rel = path.relative_to(root).as_posix()
    text = path.read_text(encoding="utf-8")
    code = rust_code(path)
    if re.search(r'\bpub(\([^)]*\))?\s+(const\s+|async\s+|unsafe\s+)*fn\b', code):
        errors.append(f'{rel}: the bridge contract declares a public function or method')
    if re.search(r'^impl(<[^>]*>)?\s+[A-Z]\w*(<[^>]*>)?\s*\{', code, re.M):
        errors.append(f'{rel}: the bridge contract has an inherent impl; put behaviour in the application crate')
    if re.search(r'#\[derive\([^)]*\bDefault\b', code):
        errors.append(f'{rel}: derive(Default) in the bridge contract becomes Dart API; implement it with the ignore marker')
    for match in re.finditer(r'^impl Default for (\w+) \{\n(.*?)^\}', text, re.S | re.M):
        if '/// flutter_rust_bridge:ignore\n    fn default()' not in match.group(2):
            errors.append(f'{rel}: Default for {match.group(1)} lacks the flutter_rust_bridge:ignore marker')

for path in sorted(APPLICATION_SRC.rglob('*.rs')):
    rel = path.relative_to(APPLICATION_SRC).as_posix()
    code = rust_code(path)
    if rel.startswith('application/') and references(code, 'wire'):
        errors.append(f'rust-core/application/src/{rel}: the application layer depends on the wire adapter')
    if rel.startswith('domain/'):
        for match in re.finditer(r'\bcrate::(\w+)', code):
            if match.group(1) != 'domain':
                errors.append(f'rust-core/application/src/{rel}: the domain depends on crate::{match.group(1)}')

for path in sorted(CORE_SRC.rglob('*.rs')):
    rel = path.relative_to(CORE_SRC).as_posix()
    if rel not in ('api.rs', 'frb_generated.rs') and references(rust_code(path), 'api'):
        errors.append(f'rust-core/src/{rel}: depends on the FRB facade crate::api')
# FRB resolves the facade's types from its own imports: a bridge type imported through the
# application crate's re-exports would become an opaque Dart handle.
if re.search(r'\bgitlama_application::[\w:]*(\{[^}]*\bNative|\bNative)', rust_code(CORE_SRC / 'api.rs')):
    errors.append('rust-core/src/api.rs: names a bridge type through gitlama_application; import it from gitlama_contract')
# The cycles the 2026-10-11 review found stay broken: hosting renews credentials through a
# refresh the runtime injects, and the helper's policy module only names the domain policy.
for path, module in (
    (CORE_SRC / 'hosting.rs', 'hosting_runtime'),
    (APPLICATION_SRC / 'remote_session_policy.rs', 'application'),
):
    if references(rust_code(path), module):
        errors.append(f'{path.relative_to(root).as_posix()}: depends on crate::{module} (a broken cycle returned)')
assert not errors, '\n'.join(errors)

windows_forwarding = (root / 'rust-core/src/cli_forwarding/windows.rs').read_text(encoding="utf-8")
for contract in (
    'FILE_FLAG_FIRST_PIPE_INSTANCE',
    'PIPE_REJECT_REMOTE_CLIENTS',
    'ConvertStringSecurityDescriptorToSecurityDescriptorW',
    'ImpersonateNamedPipeClient',
    'GetNamedPipeServerProcessId',
    'OpenThreadToken',
    'OpenProcessToken',
    'CredReadW',
    'CredWriteW',
):
    if contract not in windows_forwarding:
        errors.append(f'Windows CLI forwarding lost {contract}')
for forbidden in ('TcpListener', 'TcpStream'):
    if forbidden in windows_forwarding:
        errors.append(f'Windows CLI forwarding uses forbidden {forbidden}')
serve_connection = windows_forwarding.split('fn serve_connection(', 1)[-1].split('\nfn ', 1)[0]
read_index = serve_connection.find('read_request_cancellable(&mut stream')
verify_index = serve_connection.find('verify_client_sid(&stream')
handle_index = serve_connection.find('handler(request.action)')
if not (0 <= read_index < verify_index < handle_index):
    errors.append('Windows CLI forwarding must read the request before peer impersonation and verify before dispatch')

clone_boundary = (root / 'rust-core/application/src/credentials.rs').read_text(encoding="utf-8")
for contract in (
    '#[cfg(windows)]\npub(crate) struct AskpassLease',
    'crate::windows_security::owner_only(&lease.directory)',
    'getrandom::fill(&mut entropy)',
    'file.write_all(value.as_bytes())',
    'file.write_all(&vec![0; length])',
):
    if contract not in clone_boundary:
        errors.append(f'Windows credential broker lost {contract}')
if '#[cfg(not(unix))]\npub(crate) struct AskpassLease' in clone_boundary:
    errors.append('Windows credential broker regressed to the unavailable fallback')

windows_security = (root / 'rust-core/application/src/windows_security.rs').read_text(encoding="utf-8")
for contract in (
    'PROTECTED_DACL_SECURITY_INFORMATION',
    'D:P(A;;GA;;;{sid})',
    'SetFileSecurityW',
):
    if contract not in windows_security:
        errors.append(f'Windows private-file security lost {contract}')

rebase_boundary = (root / 'rust-core/application/src/rebase_operation.rs').read_text(encoding="utf-8")
for contract in (
    '#[cfg(windows)]',
    'crate::private_store::PrivateDir::repository(&draft.facts.common_git_dir, &["rebase"])',
    '"sequence-editor.ps1"',
    '"message-editor.ps1"',
    'getrandom::fill(&mut entropy)',
):
    if contract not in rebase_boundary:
        errors.append(f'Windows interactive rebase runtime lost {contract}')
# The private store makes every directory and file owner-only on Windows.
private_store = (root / 'rust-core/application/src/private_store.rs').read_text(encoding="utf-8")
if private_store.count('crate::windows_security::owner_only(') < 2:
    errors.append('Windows private store lost its owner-only directories or files')
if '#[cfg(not(unix))]\n    {' in rebase_boundary:
    errors.append('Windows interactive rebase regressed to the unsupported fallback')

conflict_boundary = (root / 'rust-core/application/src/conflict.rs').read_text(encoding="utf-8")
for contract in (
    'use std::os::windows::fs::{symlink_dir, symlink_file};',
    'symlink_dir(&target, &native)',
    'symlink_file(&target, &native)',
):
    if contract not in conflict_boundary:
        errors.append(f'Windows conflict symlink handling lost {contract}')
if '#[cfg(not(unix))]\n        return Err(NativeConflictFailureKind::Unsupported);' in conflict_boundary:
    errors.append('Windows conflict symlinks regressed to the unsupported fallback')

# The core's sources, wherever a use case lives: the facade or the
# application modules behind it.
repository_api = '\n'.join(
    path.read_text(encoding="utf-8")
    for path in [root / 'rust-core/src/api.rs', *sorted((root / 'rust-core/application/src/application').glob('*.rs'))]
)
if not re.search(r'#\[cfg\(windows\)\]\n(pub\(crate\) )?fn native_identity_bytes\(identity: &NativePathIdentity\)', repository_api):
    errors.append('Windows discard and clean lost native path identity conversion')
if re.search(r'#\[cfg\(not\(unix\)\)\]\n(pub\(crate\) )?fn native_identity_bytes\(_identity: &NativePathIdentity\)', repository_api):
    errors.append('Windows discard and clean regressed to the unsupported path fallback')

hosting_api = (root / 'rust-core/src/api.rs').read_text(encoding="utf-8")
if 'devmil_git::hosting' in hosting_api:
    errors.append('FRB API exposes shared hosting types instead of product DTOs')
generated_hosting = '\n'.join(
    (root / path).read_text(encoding="utf-8")
    for path in (
        'lib/rust/third_party/gitlama_contract/hosting.dart',
        'lib/rust/third_party/gitlama_contract/hosting_runtime.dart',
    )
)
for forbidden in (
    'CredentialEnvelope',
    'accessToken',
    'refreshToken',
    'codeVerifier',
    'deviceCode',
):
    if forbidden in generated_hosting:
        errors.append(f'generated hosting bridge exposes secret field {forbidden}')

assert not errors, '\n'.join(errors)
print('Architecture boundaries passed')

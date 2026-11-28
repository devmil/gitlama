#!/usr/bin/env python3
"""Enforces GitLama's dependency directions.

Rust (Cargo dependencies and `use` paths):
- gitlama_contract (the wire and value types) depends on no GitLama crate.
- gitlama_application depends only on the contract; the remote helper runs it.
- gitlama-remote-helper depends only on the application crate.
- gitlama_core (the desktop's native runtime) never reaches the Qt layers.
- desktop/workbench (services and workflows) never reaches Qt.
- desktop/qt (the bridge objects) reaches the core only through the
  workbench and never runs Git itself.
- desktop/app is the composition root.

QML (qml/GitLama):
- The UI imports only Qt modules, Meridian, GitLama and its native items; it
  loads no code at run time and opens no Qt Quick Controls menu.
- No credential field reaches the bridge or the UI.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
errors = []
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
        # The workspace table pins versions for members; it is not a crate's own.
        if entry and table and table != 'workspace.dependencies' and table.split('.')[-1].endswith('dependencies'):
            names.add(entry.group(1))
    return names



INTERNAL = {
    'gitlama_contract', 'gitlama_application', 'gitlama_core', 'gitlama-remote-helper',
    'gitlama-workbench', 'gitlama-qt', 'qtbridge',
}
for crate, allowed in (
    ('contract', set()),
    ('application', {'gitlama_contract'}),
    ('remote-helper', {'gitlama_application'}),
    ('.', {'gitlama_contract', 'gitlama_application'}),
    ('desktop/workbench', {'gitlama_core', 'gitlama_contract', 'gitlama_application'}),
    ('desktop/qt', {'gitlama-workbench', 'gitlama_contract', 'qtbridge'}),
):
    for name in sorted((manifest_dependencies(RUST / crate / 'Cargo.toml') & INTERNAL) - allowed):
        errors.append(f'rust-core/{crate}/Cargo.toml: depends on {name}')
for crate, forbidden in (
    ('contract', ('gitlama_application', 'gitlama_core', 'devmil_git', 'qtbridge')),
    ('application', ('gitlama_core', 'gitlama_workbench', 'qtbridge')),
    ('remote-helper', ('gitlama_core', 'gitlama_workbench', 'qtbridge')),
    ('src', ('gitlama_workbench', 'gitlama_qt', 'qtbridge')),
    ('desktop/workbench/src', ('gitlama_qt', 'qtbridge')),
    ('desktop/qt/src', ('gitlama_core', 'gitlama_application', 'devmil_git')),
):
    for path in sorted((RUST / crate).glob('**/*.rs')):
        code = rust_code(path)
        for name in forbidden:
            if re.search(rf'\b{name}::', code):
                errors.append(f'{path.relative_to(root).as_posix()}: reaches {name}')
# The bridge objects never start a process: Git runs in the core.
for path in sorted((RUST / 'desktop/qt/src').glob('**/*.rs')):
    if re.search(r'\bstd::process\b|\bCommand::new\b', rust_code(path)):
        errors.append(f'{path.relative_to(root).as_posix()}: the Qt layer starts a process')

for path in sorted(CONTRACT_SRC.rglob('*.rs')):
    rel = path.relative_to(root).as_posix()
    code = rust_code(path)
    if re.search(r'\bpub(\([^)]*\))?\s+(const\s+|async\s+|unsafe\s+)*fn\b', code):
        errors.append(f'{rel}: the contract declares a public function or method')
    if re.search(r'^impl(<[^>]*>)?\s+[A-Z]\w*(<[^>]*>)?\s*\{', code, re.M):
        errors.append(f'{rel}: the contract has an inherent impl; put behaviour in the application crate')

for path in sorted(APPLICATION_SRC.rglob('*.rs')):
    rel = path.relative_to(APPLICATION_SRC).as_posix()
    code = rust_code(path)
    if rel.startswith('application/') and references(code, 'wire'):
        errors.append(f'rust-core/application/src/{rel}: the application layer depends on the wire adapter')
    if rel.startswith('domain/'):
        for match in re.finditer(r'\bcrate::(\w+)', code):
            if match.group(1) != 'domain':
                errors.append(f'rust-core/application/src/{rel}: the domain depends on crate::{match.group(1)}')

# The cycles the 2026-10-11 review found stay broken: hosting renews credentials through a
# refresh the runtime injects, and the helper's policy module only names the domain policy.
for path, module in (
    (CORE_SRC / 'hosting.rs', 'hosting_runtime'),
    (APPLICATION_SRC / 'remote_session_policy.rs', 'application'),
):
    if references(rust_code(path), module):
        errors.append(f'{path.relative_to(root).as_posix()}: depends on crate::{module} (a broken cycle returned)')

# QML.
QML_IMPORT = re.compile(r'^\s*import\s+([A-Za-z][\w.]*)', re.M)
QML_ALLOWED_IMPORTS = re.compile(r'^(Qt\w*(\.\w+)*|Meridian|GitLama|GitLamaNative)$')
for path in sorted((root / 'qml/GitLama').rglob('*.qml')):
    rel = path.relative_to(root).as_posix()
    text = path.read_text(encoding='utf-8')
    for uri in QML_IMPORT.findall(text):
        if not QML_ALLOWED_IMPORTS.match(uri):
            errors.append(f'{rel}: imports {uri}')
    if re.search(r'Qt\.createQmlObject|loadLibrary|Qt\.include\s*\(', text):
        errors.append(f'{rel}: loads code at run time')
    # Menus are the operating system's, through CommandMenu and the menu presenter.
    if path.name != 'CommandMenu.qml' and re.search(r'\b(C|T)\.(Menu|MenuItem|MenuBar|MenuSeparator)\b', text):
        errors.append(f'{rel}: opens a Qt Quick Controls menu; use CommandMenu')
    if re.search(r'^\s*import\s+Qt\.labs\.platform', text, re.M) and path.name != 'CommandMenu.qml':
        errors.append(f'{rel}: uses the native menu module outside CommandMenu')
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

# No credential field reaches the bridge objects or the UI.
for path in [*sorted((RUST / 'desktop/qt/src').rglob('*.rs')), *sorted((root / 'qml/GitLama').rglob('*.qml'))]:
    text = path.read_text(encoding='utf-8')
    for forbidden in ('CredentialEnvelope', 'accessToken', 'refreshToken', 'access_token', 'refresh_token',
                      'codeVerifier', 'code_verifier', 'deviceCode', 'device_code'):
        if forbidden in text:
            errors.append(f'{path.relative_to(root).as_posix()}: exposes secret field {forbidden}')

assert not errors, '\n'.join(errors)
print('Architecture boundaries passed')

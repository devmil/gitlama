#!/usr/bin/env python3
"""Cross-platform fast gate of the Rust/QML application.

Lanes:
  (none)      everything a change must pass on Linux
  --platform  the checks whose result depends on the operating system
  --source    the checks that need neither Rust nor Qt (website, docs, metadata)
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def admit_file_descriptors(minimum=4096):
    """Admit analysis/native tools without changing the host or hard limit."""
    if os.name != 'posix':
        return
    import resource
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    effective = soft
    if soft != resource.RLIM_INFINITY and soft < minimum:
        if hard != resource.RLIM_INFINITY and hard < minimum:
            raise SystemExit('verification_nofile_hard_limit_too_low')
        try:
            resource.setrlimit(resource.RLIMIT_NOFILE, (minimum, hard))
        except (OSError, ValueError):
            raise SystemExit('verification_nofile_adjustment_denied') from None
        effective, actual_hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        if effective != minimum or actual_hard != hard:
            raise SystemExit('verification_nofile_adjustment_unacknowledged')
    print(f'verification_nofile original={soft} effective={effective} hard={hard}', flush=True)


def admit_inotify_instances(minimum=16):
    """Distinguish Linux per-user watcher exhaustion from RLIMIT_NOFILE."""
    if not sys.platform.startswith('linux'):
        return
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    handles = []
    try:
        for _ in range(minimum):
            handle = libc.inotify_init1(os.O_CLOEXEC | os.O_NONBLOCK)
            if handle < 0:
                raise SystemExit(f'verification_inotify_unavailable errno={ctypes.get_errno()} admitted={len(handles)} required={minimum}')
            handles.append(handle)
    finally:
        for handle in handles:
            os.close(handle)
    print(f'verification_inotify available_at_least={minimum}', flush=True)


def run(*args, env=None):
    command = shutil.which(args[0]) or args[0]
    subprocess.run([command, *args[1:]], check=True, env=env)


def qt_tool(name):
    """A Qt 6 tool: the qmake6-reported bin directory first, then PATH."""
    qmake = shutil.which('qmake6') or shutil.which('qmake')
    if qmake:
        try:
            bins = subprocess.check_output([qmake, '-query', 'QT_INSTALL_BINS'], text=True).strip()
            candidate = Path(bins) / (name + ('.exe' if os.name == 'nt' else ''))
            if candidate.is_file():
                return str(candidate)
        except subprocess.CalledProcessError:
            pass
    for candidate in (name + '6', name, f'/usr/lib/qt6/bin/{name}'):
        found = shutil.which(candidate)
        if found:
            return found
    raise SystemExit(f'verification_missing_qt_tool {name}')


def isolated_git_environment():
    """Tests build their own repositories; the person's Git configuration
    (diff prefixes, pull defaults, signing) must not change their output."""
    environment = dict(os.environ)
    environment['GIT_CONFIG_GLOBAL'] = os.devnull
    environment['GIT_CONFIG_NOSYSTEM'] = '1'
    return environment


def source_checks():
    """The checks that need neither Rust nor Qt nor resolved packages."""
    run(sys.executable, '-m', 'unittest', 'discover', '-s', 'tests/package', '-v')
    run(sys.executable, 'scripts/check_architecture.py')
    run(sys.executable, 'scripts/check_helper_compatibility.py')


def qml_checks():
    """Lints every GitLama QML file with no warning allowed."""
    qmllint = qt_tool('qmllint')
    files = sorted((ROOT / 'qml/GitLama').glob('*.qml'))
    # Linted on its own, a singleton reports its own module's import as
    # unresolved; that category stays informational for singletons only.
    singletons = [str(path) for path in files if 'pragma Singleton' in path.read_text(encoding='utf-8')]
    others = [str(path) for path in files if str(path) not in singletons]
    run(qmllint, '-I', 'qml', '--max-warnings', '0', *others)
    if singletons:
        run(qmllint, '-I', 'qml', '--import', 'info', '--max-warnings', '0', *singletons)


def rust_checks():
    """Lints and tests of the Rust workspace; their results differ by platform."""
    manifest = ['--manifest-path', 'rust-core/Cargo.toml']
    # Cargo compiles the sibling devmil-git tree: it must be the pinned revision.
    run(sys.executable, 'scripts/shared_git_pin.py', '--check')
    run('cargo', 'clippy', *manifest, '--locked', '--workspace', '--all-targets', '--', '-D', 'warnings')
    # The remote helper builds the application crate without its image codecs.
    run('cargo', 'clippy', *manifest, '--locked', '-p', 'gitlama_application', '-p', 'gitlama-remote-helper',
        '--all-targets', '--no-default-features', '--', '-D', 'warnings')
    environment = isolated_git_environment()
    # The core's tests share process-wide session state.
    run('cargo', 'test', *manifest, '--locked', '-p', 'gitlama_contract', '-p', 'gitlama_application', '-p', 'gitlama_core',
        '--', '--test-threads=1', env=environment)
    run('cargo', 'test', *manifest, '--locked', '-p', 'gitlama-remote-helper', env=environment)
    run('cargo', 'test', *manifest, '--locked', '-p', 'gitlama-workbench', '-p', 'gitlama-qt', env=environment)


def main():
    os.chdir(ROOT)
    if '--source' in sys.argv:
        # The CI lane for website, documentation and release-metadata changes.
        source_checks()
        return
    admit_file_descriptors()
    admit_inotify_instances()
    if '--platform' in sys.argv:
        # The CI lane of the platforms besides Linux: only the checks whose
        # result depends on the operating system. Linux runs the full gate.
        rust_checks()
        return
    run(sys.executable, 'tooling/l10n/generate.py', '--check')
    run(sys.executable, 'scripts/check_l10n.py')
    qml_checks()
    run(sys.executable, 'tooling/remote_wire/generate.py', '--check')
    run(sys.executable, 'tooling/remote_wire/generate_calls.py', '--check')
    run(sys.executable, 'scripts/check_helper_compatibility.py')
    run('cargo', 'fmt', '--manifest-path', 'rust-core/Cargo.toml', '--all', '--check')
    rust_checks()
    run(sys.executable, '-m', 'unittest', 'discover', '-s', 'tests/package', '-v')
    run(sys.executable, 'scripts/check_architecture.py')
    run(sys.executable, 'scripts/check_dependencies.py')
    run(sys.executable, 'scripts/check_meridian_usage.py')
    run(sys.executable, 'scripts/check_design_contract.py')
    run(sys.executable, 'scripts/audit_command_inventory.py')


if __name__ == '__main__':
    main()

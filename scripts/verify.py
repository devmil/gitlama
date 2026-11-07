#!/usr/bin/env python3
"""Cross-platform fast gate. Native smoke is an explicit separate invocation."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
ROOT=Path(__file__).resolve().parent.parent

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

def run(*args):
    command = shutil.which(args[0]) or args[0]
    subprocess.run([command, *args[1:]], check=True)

# What the Flutter tool reports when the first request to a test file's
# harness port is not the test process's WebSocket. A local port scanner, such
# as an IDE's port auto-detection, can send that request first; the file then
# fails to load before any test in it runs.
HARNESS_CONNECTION_FAILURE = 'Unable to connect to flutter_tester process'
HARNESS_RETRIES = 5
# `flutter test` found no test that matches its tags. A rerun names only the
# files that failed to load, and those may hold none of the tagged tests.
NO_TESTS_RAN = 79

def harness_failures(report):
    """The test files of [report] that failed only to connect to their test
    process, or None when anything else failed."""
    suites, tests, errors, failed = {}, {}, {}, set()
    for line in report.read_text(encoding='utf-8').splitlines():
        event = json.loads(line)
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']['path']
        elif kind == 'testStart':
            tests[event['test']['id']] = event['test']['suiteID']
        elif kind == 'error':
            errors.setdefault(event['testID'], []).append(event.get('error', ''))
        elif kind == 'testDone' and event.get('result') != 'success':
            failed.add(event['testID'])
    files = set()
    for test in failed:
        messages = errors.get(test, [])
        if not messages or not all(HARNESS_CONNECTION_FAILURE in m for m in messages):
            return None
        files.add(suites[tests[test]])
    return sorted(files)

def flutter_test(*args):
    """Runs `flutter test`, and reruns only the files that failed to connect
    to their test process. Every other failure fails at once."""
    report = ROOT/'build'/'verify_flutter_test.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    files = []
    for attempt in range(HARNESS_RETRIES + 1):
        report.unlink(missing_ok=True)
        try:
            run('flutter', 'test', *args, f'--file-reporter=json:{report}', *files)
            return
        except subprocess.CalledProcessError as error:
            if files and error.returncode == NO_TESTS_RAN:
                return
            retry = harness_failures(report) if report.exists() else None
            if not retry or attempt == HARNESS_RETRIES:
                raise
        print(f'verification_flutter_tester_connection_retry files={len(retry)}', flush=True)
        files = [str(Path(path).relative_to(ROOT)) if Path(path).is_absolute() else path
                 for path in retry]

def source_checks():
    """The checks that need neither Flutter nor Rust nor resolved packages."""
    run(sys.executable,'-m','unittest','discover','-s','tests/package','-v')
    run(sys.executable,'scripts/check_architecture.py')
    run(sys.executable,'scripts/check_helper_compatibility.py')

def use_fvm_flutter():
    """Put FVM's copy of the pinned SDK first on PATH when FVM is installed.

    The pin check below still runs, so a missing FVM falls back to the
    Flutter on PATH and fails there if it is the wrong version.
    """
    fvm = shutil.which('fvm')
    if fvm is None:
        return
    version = json.loads((ROOT/'.fvmrc').read_text(encoding="utf-8"))['flutter']
    try:
        context = json.loads(subprocess.check_output([fvm, 'api', 'context'], text=True))
    except subprocess.CalledProcessError:
        # FVM 2 has no api command; use its cache layout and never install.
        home = os.environ.get('FVM_CACHE_PATH') or os.environ.get('FVM_HOME')
        sdk = Path(home or Path.home()/'fvm')/'versions'/version
        if (sdk/'bin').is_dir():
            os.environ['PATH'] = os.pathsep.join([str(sdk/'bin'), os.environ.get('PATH', '')])
        return
    sdk = Path(context['context']['versionsCachePath'])/version
    if not (sdk/'bin').is_dir():
        subprocess.run([fvm, 'install', version, '--skip-pub-get'], check=True)
    os.environ['PATH'] = os.pathsep.join([str(sdk/'bin'), os.environ.get('PATH', '')])

def main():
    os.chdir(ROOT)
    if '--source' in sys.argv:
        # The CI lane for website, documentation and release-metadata changes.
        source_checks()
        return
    admit_file_descriptors()
    admit_inotify_instances()
    use_fvm_flutter()
    actual=json.loads(subprocess.check_output([shutil.which('flutter'), '--version', '--machine'],text=True))['frameworkVersion']
    assert actual == json.loads((ROOT/'.fvmrc').read_text(encoding="utf-8"))['flutter'], 'Use the pinned Flutter SDK'
    if '--native' in sys.argv:
        run('flutter','test','test/native_bridge_test.dart')
    elif '--platform' in sys.argv:
        # The CI lane of the platforms besides Linux: only the checks whose
        # result depends on the operating system. Linux runs the full gate.
        rust_checks()
    else:
        # Flutter does not create the parent of untranslated-messages-file.
        # A clean release checkout therefore needs this before gen-l10n runs.
        (ROOT/'build').mkdir(parents=True, exist_ok=True)
        run('flutter','gen-l10n')
        run(sys.executable,'scripts/check_l10n.py')
        run('dart','format','--output=none','--set-exit-if-changed','lib','test','hook')
        run('flutter','analyze')
        flutter_test('--exclude-tags','native,visual,remote,ssh')
        run(sys.executable,'tooling/remote_wire/generate.py','--check')
        run(sys.executable,'scripts/check_helper_compatibility.py')
        run('cargo','fmt','--manifest-path','rust-core/Cargo.toml','--all','--check')
        rust_checks()
        if sys.platform != 'win32':
            # The client stack against the helper the previous step built.
            flutter_test('--tags','remote')
        run(sys.executable,'-m','unittest','discover','-s','tests/package','-v')
        run(sys.executable,'scripts/check_architecture.py')
        run(sys.executable,'scripts/check_dependencies.py')
        run(sys.executable,'scripts/generate_meridian_theme.py','--check')
        run(sys.executable,'scripts/check_meridian_usage.py')
        run(sys.executable,'scripts/check_design_contract.py')
        run(sys.executable,'scripts/audit_command_inventory.py')

def rust_checks():
    """Lints and tests of the Rust workspace; their results differ by platform."""
    # Cargo compiles the sibling devmil-git tree: it must be the pinned revision.
    run(sys.executable,'scripts/shared_git_pin.py','--check')
    run('cargo','clippy','--manifest-path','rust-core/Cargo.toml','--locked','--workspace','--all-targets','--','-D','warnings')
    # The remote helper builds the application crate without its image codecs.
    run('cargo','clippy','--manifest-path','rust-core/Cargo.toml','--locked','-p','gitlama_application','-p','gitlama-remote-helper','--all-targets','--no-default-features','--','-D','warnings')
    run('cargo','test','--manifest-path','rust-core/Cargo.toml','--locked','-p','gitlama_contract','-p','gitlama_application','-p','gitlama_core','--','--test-threads=1')
    run('cargo','test','--manifest-path','rust-core/Cargo.toml','--locked','-p','gitlama-remote-helper')

if __name__ == '__main__':
    main()

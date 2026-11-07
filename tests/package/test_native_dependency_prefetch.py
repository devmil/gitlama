"""Reproduce credential loss across a hook using an isolated real Cargo cache."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class NativeDependencyPrefetchTest(unittest.TestCase):
    def test_prefetch_allows_locked_graph_after_auth_environment_is_filtered(self):
        with tempfile.TemporaryDirectory(prefix='hook cache ') as directory:
            root = Path(directory)
            dependency = root / 'dependency'
            dependency.mkdir()
            (dependency / 'src').mkdir()
            (dependency / 'src/lib.rs').write_text('pub fn value() -> u8 { 1 }')
            (dependency / 'Cargo.toml').write_text('[package]\nname="probe-dependency"\nversion="0.1.0"\nedition="2021"\n')
            def run(*args, **kwargs):
                return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, encoding='utf-8', **kwargs)
            run('git', 'init', '--quiet', str(dependency))
            run('git', '-C', str(dependency), 'add', '.')
            run('git', '-C', str(dependency), '-c', 'user.name=Fixture',
                '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
            app = root / 'app'
            app.mkdir()
            (app / 'src').mkdir()
            (app / 'src/lib.rs').write_text('pub use probe_dependency::value;')
            (app / 'Cargo.toml').write_text('[package]\nname="probe-app"\nversion="0.1.0"\nedition="2021"\n[dependencies]\nprobe-dependency={git="ssh://unreachable.invalid/dependency"}\n')
            env = dict(os.environ, CARGO_HOME=str(root / 'cargo-cache'),
                       CARGO_NET_GIT_FETCH_WITH_CLI='true', GIT_CONFIG_COUNT='1',
                       GIT_CONFIG_KEY_0='url.' + dependency.as_uri() + '.insteadOf',
                       GIT_CONFIG_VALUE_0='ssh://unreachable.invalid/dependency')
            run(shutil.which('cargo'), 'generate-lockfile', cwd=app, env=env)
            run(shutil.which('cargo'), 'fetch', '--locked', cwd=app, env=env)
            filtered = {k: v for k, v in env.items() if not k.startswith('GIT_CONFIG_')}
            filtered['CARGO_NET_OFFLINE'] = 'true'
            result = run(shutil.which('cargo'), 'metadata', '--locked', '--format-version=1',
                         cwd=app, env=filtered)
            self.assertEqual({p['name'] for p in json.loads(result.stdout)['packages']},
                             {'probe-app', 'probe-dependency'})
            wrapper = Path('scripts/qualify-linux-local.sh').read_text()
            self.assertLess(wrapper.index('cargo fetch --manifest-path'), wrapper.index('export CARGO_GITLAMA_PREFETCHED=true'))
            self.assertLess(wrapper.index('export CARGO_GITLAMA_PREFETCHED=true'), wrapper.index('python3 scripts/package.py AppImage'))

    def test_offline_mode_is_confined_to_the_prefetched_hook_workspace(self):
        wrapper = Path('scripts/qualify-linux-local.sh').read_text()
        hook = Path('hook/build.dart').read_text()
        self.assertNotIn('export CARGO_NET_OFFLINE=true', wrapper)
        self.assertIn("if (environment['CARGO_GITLAMA_PREFETCHED'] == 'true')", hook)
        self.assertIn("environment['CARGO_NET_OFFLINE'] = 'true'", hook)

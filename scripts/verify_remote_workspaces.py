#!/usr/bin/env python3
"""Remote workspace verification lanes (docs/remote-workspaces/IMPLEMENTATION.md).

  --protocol          generated codec freshness, Rust wire runtime and Dart transport tests
  --helper            the helper's unit and real-Git integration tests
  --ssh-loopback      real OpenSSH to a loopback sshd fixture running the installed helper
  --disconnect-matrix helper and transport kills at protocol stages over the fixture
  --performance       loopback and delayed-transport latency samples
  --soak              30 minutes of read-only browsing, session replacement and reconnects,
                      tracking helper memory, descriptors and threads

Each lane exits non-zero on failure. A lane whose prerequisite is unavailable fails with a
"not run" explanation; it never counts as passed. The SSH fixture binds 127.0.0.1 on an
ephemeral port, accepts only a generated key, uses an isolated home and known-hosts file and
never reads or changes the user's SSH configuration. Cleanup removes only marked fixture roots
and terminates only processes this script started.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import signal
import socket
import statistics
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "rust-core"
HELPER = CORE / "target" / "debug" / "gitlama-remote-helper"
MARKER = ".gitlama-remote-fixture"
FLUTTER = ["flutter"]


class NotRun(Exception):
    """A prerequisite is unavailable; the lane did not run."""


def run(*arguments: str, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    command = shutil.which(arguments[0]) or arguments[0]
    subprocess.run([command, *arguments[1:]], cwd=cwd, env=env, check=True)


def use_pinned_flutter() -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    import verify  # noqa: PLC0415 - shares the verifier's SDK resolution

    verify.use_fvm_flutter()


def lane_protocol() -> None:
    run(sys.executable, "tooling/remote_wire/generate.py", "--check")
    run("cargo", "test", "--manifest-path", str(CORE / "Cargo.toml"), "--locked", "-p", "gitlama_application", "--lib", "wire::")
    run("cargo", "test", "--manifest-path", str(CORE / "Cargo.toml"), "--locked", "-p", "gitlama-remote-helper", "--bins")
    run("flutter", "test", "test/remote", "--exclude-tags", "remote,ssh")


def lane_helper() -> None:
    run("cargo", "test", "--manifest-path", str(CORE / "Cargo.toml"), "--locked", "-p", "gitlama-remote-helper")
    run("flutter", "test", "--tags", "remote")


# ------------------------------------------------------------------------------------------
# Loopback SSH fixture
# ------------------------------------------------------------------------------------------


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def git(directory: Path, *arguments: str) -> str:
    result = subprocess.run(
        [
            "git",
            "-c", "user.name=Fixture",
            "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false",
            "-c", "init.defaultBranch=main",
            *arguments,
        ],
        cwd=directory,
        capture_output=True,
        text=True,
        env={**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"},
    )
    if result.returncode != 0:
        raise RuntimeError(f"fixture git {arguments[0]} failed")
    return result.stdout.strip()


class Fixture:
    """A loopback sshd, an isolated remote home with the installed helper and a repository."""

    def __init__(self) -> None:
        sshd = shutil.which("sshd") or "/usr/sbin/sshd"
        for tool in ("ssh", "ssh-keygen", "git"):
            if shutil.which(tool) is None:
                raise NotRun(f"{tool} is not installed")
        if not Path(sshd).exists():
            raise NotRun("sshd is not installed")
        if not HELPER.exists():
            raise NotRun("the helper is not built; run cargo build -p gitlama-remote-helper")
        self.sshd = sshd
        self.root = Path(tempfile.mkdtemp(prefix="gitlama-remote-ssh-"))
        (self.root / MARKER).write_text("owned by verify_remote_workspaces.py\n", encoding="utf-8")
        self.home = self.root / "home"
        self.home.mkdir()
        self.port = free_port()
        self.process: subprocess.Popen[bytes] | None = None
        self.build_id = json.loads(
            subprocess.run([str(HELPER), "--version"], capture_output=True, check=True, text=True).stdout
        )["buildId"]

    def __enter__(self) -> "Fixture":
        try:
            self._start()
        except BaseException:
            self.close()
            raise
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def _start(self) -> None:
        keys = self.root / "keys"
        keys.mkdir(mode=0o700)
        for name in ("host", "client"):
            subprocess.run(
                ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(keys / name)],
                check=True,
            )
        (keys / "authorized_keys").write_bytes((keys / "client.pub").read_bytes())
        host_key = (keys / "host.pub").read_text(encoding="utf-8").split()[:2]
        self.known_hosts = self.root / "known_hosts"
        self.known_hosts.write_text(f"[127.0.0.1]:{self.port} {' '.join(host_key)}\n", encoding="utf-8")
        self.untrusted_hosts = self.root / "untrusted_known_hosts"
        self.untrusted_hosts.write_text("", encoding="utf-8")
        config = self.root / "sshd_config"
        config.write_text(
            "\n".join(
                [
                    f"Port {self.port}",
                    "ListenAddress 127.0.0.1",
                    f"HostKey {keys / 'host'}",
                    f"PidFile {self.root / 'sshd.pid'}",
                    f"AuthorizedKeysFile {keys / 'authorized_keys'}",
                    "PasswordAuthentication no",
                    "KbdInteractiveAuthentication no",
                    "PubkeyAuthentication yes",
                    "PermitRootLogin no",
                    "UsePAM no",
                    "StrictModes no",
                    "AllowAgentForwarding no",
                    "AllowTcpForwarding no",
                    "X11Forwarding no",
                    "PermitUserEnvironment no",
                    f"SetEnv HOME={self.home}",
                    "LogLevel ERROR",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        self.ssh_config = self.root / "ssh_config"
        user = os.environ.get("USER") or os.getlogin()
        entries = []
        aliases = [
            ("gitlama-loopback", self.known_hosts, None),
            ("gitlama-untrusted", self.untrusted_hosts, None),
            ("gitlama-rtt50", self.known_hosts, 50),
            ("gitlama-rtt150", self.known_hosts, 150),
        ]
        for alias, hosts, rtt in aliases:
            entries += [
                f"Host {alias}",
                "  HostName 127.0.0.1",
                f"  Port {self.port}",
                *(
                    [f"  ProxyCommand {sys.executable} {Path(__file__).resolve()} --proxy {self.port} {rtt} 20"]
                    if rtt is not None
                    else []
                ),
                f"  User {user}",
                f"  IdentityFile {keys / 'client'}",
                "  IdentitiesOnly yes",
                "  IdentityAgent none",
                f"  UserKnownHostsFile {hosts}",
                "  GlobalKnownHostsFile /dev/null",
                "  UpdateHostKeys no",
                "",
            ]
        self.ssh_config.write_text("\n".join(entries), encoding="utf-8")
        self.process = subprocess.Popen(
            [self.sshd, "-D", "-e", "-f", str(config)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            with socket.socket() as probe:
                if probe.connect_ex(("127.0.0.1", self.port)) == 0:
                    break
            if self.process.poll() is not None:
                raise NotRun("the loopback sshd did not start")
            time.sleep(0.05)
        else:
            raise NotRun("the loopback sshd did not listen")
        self.repository = self.home / "project"
        self.repository.mkdir()
        git(self.repository, "init", "-q")
        git(self.repository, "config", "user.name", "Loopback Person")
        git(self.repository, "config", "user.email", "loopback@example.invalid")
        git(self.repository, "config", "commit.gpgsign", "false")
        for index in range(40):
            (self.repository / f"file{index:02}.txt").write_text(f"line {index}\n" * 50, encoding="utf-8")
            git(self.repository, "add", ".")
            git(self.repository, "commit", "-qm", f"commit {index}")
        (self.repository / "file00.txt").write_text("changed\n", encoding="utf-8")

    def install_helper(self, build_id: str | None = None) -> Path:
        target = self.home / ".local" / "lib" / "gitlama" / "remote" / (build_id or self.build_id)
        target.mkdir(parents=True, exist_ok=True)
        installed = target / "gitlama-remote-helper"
        shutil.copy2(HELPER, installed)
        installed.chmod(0o755)
        return installed

    def ssh(self, alias: str = "gitlama-loopback", build_id: str | None = None) -> subprocess.Popen[bytes]:
        """The production argument array, with the fixture configuration."""
        launch = (
            f'h="$HOME/.local/lib/gitlama/remote/{build_id or self.build_id}/gitlama-remote-helper"; '
            'p="$(uname -s)/$(uname -m)"; '
            'case "$p" in Linux/x86_64|Linux/aarch64|Darwin/arm64|Darwin/x86_64) ;; '
            "*) printf 'GITLAMA-BOOTSTRAP 1 platform\\n'; exit 3;; esac; "
            'case "$p" in Darwin/*) for d in /usr/local/bin /opt/homebrew/bin; do '
            '[ ! -x "$d/git" ] || PATH="$d:$PATH"; done; export PATH;; esac; '
            '[ -x "$h" ] || '
            "{ printf 'GITLAMA-BOOTSTRAP 1 missing %s\\n' \"$p\"; exit 3; }; "
            'exec "$h" --stdio'
        )
        return subprocess.Popen(
            ["ssh", "-F", str(self.ssh_config), *FIXED_OPTIONS, "--", alias, launch],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )

    def close(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        if (self.root / MARKER).exists():
            shutil.rmtree(self.root, ignore_errors=True)


FIXED_OPTIONS = [
    "-T",
    "-o", "RequestTTY=no",
    "-o", "StdinNull=no",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "ForwardAgent=no",
    "-o", "ForwardX11=no",
    "-o", "ClearAllForwardings=yes",
    "-o", "GSSAPIDelegateCredentials=no",
    "-o", "ControlMaster=no",
    "-o", "ControlPath=none",
    "-o", "ForkAfterAuthentication=no",
    "-o", "RemoteCommand=none",
    "-o", "SessionType=default",
    "-o", "PermitLocalCommand=no",
    "-o", "ConnectTimeout=10",
    "-o", "ConnectionAttempts=1",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=3",
]


# ------------------------------------------------------------------------------------------
# A minimal protocol client (docs/remote-workspaces/PROTOCOL.md)
# ------------------------------------------------------------------------------------------


class Client:
    def __init__(self, process: subprocess.Popen[bytes]) -> None:
        self.process = process
        self.next_request = 0
        self.nonce = os.urandom(16).hex()
        self.hello: dict = {}
        self.publications = 0

    def read_frame(self) -> bytes | None:
        header = self.process.stdout.read(4)
        if len(header) < 4:
            return None
        (length,) = struct.unpack(">I", header)
        if not 0 < length <= 4 * 1024 * 1024:
            raise RuntimeError("invalid frame length")
        payload = self.process.stdout.read(length)
        if len(payload) != length:
            return None
        return payload

    def write(self, value: dict) -> None:
        payload = json.dumps(value, separators=(",", ":")).encode()
        self.process.stdin.write(struct.pack(">I", len(payload)) + payload)
        self.process.stdin.flush()

    def handshake(self, capabilities: list[str]) -> dict:
        frame = self.read_frame()
        if frame is None:
            raise RuntimeError("no hello")
        self.hello = json.loads(frame)
        self.write(
            {
                "kind": "helloAck",
                "protocolMajor": 1,
                "protocolMinor": 0,
                "buildId": self.hello["buildId"],
                "helperIncarnation": self.hello["helperIncarnation"],
                "connectionNonce": self.nonce,
                "capabilities": capabilities,
            }
        )
        return self.hello

    def envelope(self, kind: str, payload: dict) -> int:
        self.next_request += 1
        self.write(
            {
                "protocolMajor": 1,
                "connectionNonce": self.nonce,
                "helperIncarnation": self.hello["helperIncarnation"],
                "requestId": str(self.next_request),
                "kind": kind,
                "payload": payload,
            }
        )
        return self.next_request

    def next(self) -> dict | None:
        assembling: dict[str, bytearray] = {}
        while True:
            frame = self.read_frame()
            if frame is None:
                return None
            value = json.loads(frame)
            if value.get("kind") != "chunk":
                return value
            chunk = value["payload"]
            buffer = assembling.setdefault(chunk["transaction"], bytearray())
            buffer += base64.b64decode(chunk["data"])
            if int(chunk["index"]) + 1 == int(chunk["count"]):
                data = bytes(assembling.pop(chunk["transaction"]))
                if hashlib.sha256(data).hexdigest() != chunk["digest"]:
                    raise RuntimeError("transaction digest mismatch")
                return json.loads(data)

    def call(self, method: str, arguments: dict) -> dict:
        request = self.envelope("call", {"method": method, "args": arguments})
        while True:
            value = self.next()
            if value is None:
                raise ConnectionError("closed")
            if value["kind"] == "publication":
                self.publications += 1
            elif value["kind"] == "result" and value["requestId"] == str(request):
                return value["payload"]

    def ok(self, method: str, arguments: dict) -> dict:
        payload = self.call(method, arguments)
        if "ok" not in payload:
            raise RuntimeError(f"{method}: {payload}")
        return payload["ok"]

    def shutdown(self) -> None:
        try:
            self.envelope("shutdown", {})
            self.process.stdin.close()
        except (BrokenPipeError, OSError):
            pass
        try:
            self.process.wait(10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()


def open_repository(client: Client, path: Path, generation: int = 1) -> dict:
    return client.ok(
        "openRepository",
        {"path": base64.b64encode(os.fsencode(path)).decode(), "generation": str(generation), "expectedBinding": None},
    )


def history_arguments(opened: dict, generation: int = 1) -> dict:
    return {
        "sessionId": opened["open"]["session"]["sessionId"],
        "generation": str(generation),
        "complete": True,
        "maximumRows": 256,
        "otherRefs": False,
    }


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print(f"  ok  {message}")


def lane_ssh_loopback() -> None:
    with Fixture() as fixture:
        print("bootstrap before installation")
        missing = fixture.ssh()
        output, _ = missing.communicate(timeout=30)
        host = f"{os.uname().sysname}/{os.uname().machine}".encode()
        check(
            output == b"GITLAMA-BOOTSTRAP 1 missing " + host + b"\n",
            "missing helper reports the bootstrap sentinel with the host platform",
        )
        fixture.install_helper()

        print("strict host key policy")
        before = fixture.untrusted_hosts.read_bytes()
        untrusted = fixture.ssh("gitlama-untrusted")
        output, _ = untrusted.communicate(timeout=30)
        check(untrusted.returncode == 255 and output == b"", "unknown host key fails before any helper output")
        check(fixture.untrusted_hosts.read_bytes() == before, "the known-hosts file is not written")

        print("effective client options")
        effective = subprocess.run(
            ["ssh", "-F", str(fixture.ssh_config), *FIXED_OPTIONS, "-G", "gitlama-loopback"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.lower().splitlines()
        for expected in (
            "forwardagent no",
            "forwardx11 no",
            "clearallforwardings yes",
            "controlmaster false",
            "permitlocalcommand no",
            "batchmode yes",
            "stricthostkeychecking true",
            "requesttty false",
            "sessiontype default",
            "stdinnull no",
            "forkafterauthentication no",
        ):
            check(expected in effective, f"ssh -G reports {expected}")
        # ssh -G omits options that are `none`.
        for absent in ("controlpath", "remotecommand"):
            check(
                not any(line.startswith(f"{absent} ") for line in effective),
                f"ssh -G reports no {absent}",
            )

        print("protocol over SSH")
        client = Client(fixture.ssh())
        hello = client.handshake(["read", "listDirectory", "initialize"])
        check(hello["buildId"] == fixture.build_id, "the helper reports this build")
        check(hello["store"]["state"] == "ready", "the helper store is ready in the isolated home")
        listing = client.ok("listDirectory", {"directory": None, "cursor": None})
        check(base64.b64decode(listing["directory"]) == os.fsencode(fixture.home), "listing starts at the remote home")
        created = fixture.home / "initialized" / "project"
        arguments = {
            "path": base64.b64encode(os.fsencode(created)).decode(),
            "initialBranch": "main",
            "bare": False,
        }
        initialized = client.ok("initializeRepository", arguments)
        check(initialized["failure"] is None and (created / ".git").is_dir(), "a new repository is initialized over SSH")
        again = client.ok("initializeRepository", arguments)
        check(again["failure"] == "existingRepository", "asking again reports the repository that exists")
        check(len(open_repository(client, created)["binding"]) == 64, "the initialized repository opens")
        opened = open_repository(client, fixture.repository)
        check(len(opened["binding"]) == 64, "open reports a workspace binding")
        history = client.ok("repositorySessionHistoryLoad", history_arguments(opened))
        check(history["failure"] is None and int(history["page"]["totalRows"]) >= 40, "history pages arrive over SSH")
        denied = client.call("repositorySessionDiscardExecute", {"sessionId": "1", "generation": "1", "token": "1"})
        check(denied.get("error", {}).get("code") == "unsupportedCommand", "mutations outside the surface are refused")
        client.shutdown()
        check(client.process.returncode == 0, "shutdown ends ssh cleanly")

        print("noisy login shell")
        rc = fixture.home / ".bashrc"
        rc.write_text("echo welcome to the fixture\n", encoding="utf-8")
        noisy = fixture.ssh()
        output, _ = noisy.communicate(timeout=30)
        rc.unlink()
        check(
            not output.startswith(b"GITLAMA-BOOTSTRAP") and not output[:4] == b"\x00\x00",
            "shell output before the helper is not mistaken for a hello",
        )

        print("Dart client over the installed OpenSSH")
        # The client installs the helper itself before its first connection. On macOS and
        # Linux the core owns the SSH processes, so the test loads the core library.
        shutil.rmtree(fixture.home / ".local" / "lib" / "gitlama")
        run("cargo", "build", "--manifest-path", str(CORE / "Cargo.toml"), "--locked",
            "-p", "gitlama_core")
        library = CORE / "target" / "debug" / (
            "libgitlama_core.dylib" if sys.platform == "darwin" else "libgitlama_core.so"
        )
        environment = {
            **os.environ,
            "GITLAMA_NATIVE_LIBRARY": str(library),
            "GITLAMA_SSH_FIXTURE_HELPER": str(HELPER),
            "GITLAMA_SSH_FIXTURE_CONFIG": str(fixture.ssh_config),
            "GITLAMA_SSH_FIXTURE_BUILD_ID": fixture.build_id,
            "GITLAMA_SSH_FIXTURE_REPOSITORY": str(fixture.repository),
            "GITLAMA_SSH_FIXTURE_UNTRUSTED_HOSTS": str(fixture.untrusted_hosts),
        }
        run("flutter", "test", "--tags", "ssh", "test/remote/ssh_loopback_test.dart",
            "test/remote/native_remote_process_test.dart", env=environment)


def helper_processes(fixture: Fixture) -> list[int]:
    installed = str(fixture.home / ".local" / "lib")
    found = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            command = (entry / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if command and command[0].decode(errors="replace").startswith(installed):
            found.append(int(entry.name))
    return found


def lane_disconnect_matrix() -> None:
    if not sys.platform.startswith("linux"):
        raise NotRun("the disconnect matrix inspects /proc and runs on Linux")
    with Fixture() as fixture:
        fixture.install_helper()
        print("drop before hello")
        client = Client(fixture.ssh())
        client.process.stdin.close()
        client.process.wait(15)
        deadline = time.monotonic() + 15
        while helper_processes(fixture) and time.monotonic() < deadline:
            time.sleep(0.1)
        check(not helper_processes(fixture), "closing stdin before the acknowledgement ends the helper")

        print("drop after the hello, before the acknowledgement")
        client = Client(fixture.ssh())
        client.read_frame()
        client.process.kill()
        client.process.wait()
        deadline = time.monotonic() + 15
        while helper_processes(fixture) and time.monotonic() < deadline:
            time.sleep(0.1)
        check(not helper_processes(fixture), "the helper exits when its channel drops during the handshake")

        print("drop mid-session")
        client = Client(fixture.ssh())
        client.handshake(["read"])
        opened = open_repository(client, fixture.repository)
        client.envelope("call", {"method": "repositorySessionHistoryLoad", "args": history_arguments(opened)})
        client.process.kill()
        client.process.wait()
        deadline = time.monotonic() + 15
        while helper_processes(fixture) and time.monotonic() < deadline:
            time.sleep(0.1)
        check(not helper_processes(fixture), "the helper and its sessions end when the client drops mid-request")

        print("helper killed mid-session")
        client = Client(fixture.ssh())
        client.handshake(["read"])
        open_repository(client, fixture.repository)
        for pid in helper_processes(fixture):
            os.kill(pid, signal.SIGKILL)
        try:
            client.call("listDirectory", {"directory": None, "cursor": None})
            check(False, "a killed helper cannot answer")
        except ConnectionError:
            check(True, "a killed helper ends the channel; the client sees end of stream")
        client.process.wait(15)
        check(client.process.returncode is not None, "ssh exits after the helper died")

        print("partial frame from the client")
        client = Client(fixture.ssh())
        client.handshake(["read"])
        client.process.stdin.write(b"\x00\x00\x00\x10{")
        client.process.stdin.flush()
        started = time.monotonic()
        client.process.wait(30)
        elapsed = time.monotonic() - started
        check(14 <= elapsed <= 25, f"an incomplete frame ends the connection after its deadline ({elapsed:.1f}s)")

        print("one hundred connections")
        for _ in range(100):
            client = Client(fixture.ssh())
            client.handshake(["read"])
            open_repository(client, fixture.repository)
            client.shutdown()
        time.sleep(0.5)
        check(not helper_processes(fixture), "repeated open/close leaves no helper process")


def percentile(samples: list[float], fraction: float) -> float:
    ordered = sorted(samples)
    index = min(len(ordered) - 1, max(0, round(fraction * (len(ordered) - 1))))
    return ordered[index]


def lane_performance() -> None:
    with Fixture() as fixture:
        fixture.install_helper()
        report: dict[str, dict[str, float | int | str]] = {}

        def measure(name: str, action, samples: int = 30, warmups: int = 5) -> None:
            for _ in range(warmups):
                action()
            timings = []
            for _ in range(samples):
                started = time.perf_counter()
                action()
                timings.append((time.perf_counter() - started) * 1000)
            report[name] = {
                "samples": samples,
                "median_ms": round(statistics.median(timings), 2),
                "p95_ms": round(percentile(timings, 0.95), 2),
                "max_ms": round(max(timings), 2),
            }

        def connect_and_page() -> None:
            client = Client(fixture.ssh())
            client.handshake(["read"])
            opened = open_repository(client, fixture.repository)
            client.ok("repositorySessionHistoryLoad", history_arguments(opened))
            client.shutdown()

        for alias, label in (
            ("gitlama-loopback", "rtt0"),
            ("gitlama-rtt50", "rtt50"),
            ("gitlama-rtt150", "rtt150"),
        ):

            def connect_and_page(alias: str = alias) -> None:
                client = Client(fixture.ssh(alias))
                client.handshake(["read"])
                opened = open_repository(client, fixture.repository)
                client.ok("repositorySessionHistoryLoad", history_arguments(opened))
                client.shutdown()

            measure(f"{label}_connect_open_first_history_page", connect_and_page, samples=10, warmups=2)
            client = Client(fixture.ssh(alias))
            client.handshake(["read"])
            opened = open_repository(client, fixture.repository)
            session = opened["open"]["session"]["sessionId"]
            commits = git(fixture.repository, "rev-list", "HEAD").split()
            pairs = iter(zip(commits, commits[1:]))

            def uncached_diff() -> None:
                commit, parent = next(pairs)
                client.ok(
                    "repositorySessionCommitDiffLoad",
                    {
                        "sessionId": session,
                        "generation": "1",
                        "options": {
                            "commit": commit,
                            "firstParent": parent,
                            "oldPath": None,
                            "newPath": None,
                            "contextLines": 3,
                            "whitespace": "preserve",
                            "layout": "unified",
                            "maximumRows": 512,
                        },
                    },
                )

            measure(f"{label}_uncached_small_diff", uncached_diff, samples=30, warmups=5)
            head = commits[0]
            options = {
                "commit": head,
                "firstParent": commits[1],
                "oldPath": None,
                "newPath": None,
                "contextLines": 3,
                "whitespace": "preserve",
                "layout": "unified",
                "maximumRows": 512,
            }
            measure(
                f"{label}_cached_commit_diff",
                lambda: client.ok(
                    "repositorySessionCommitDiffLoad",
                    {"sessionId": session, "generation": "1", "options": options},
                ),
            )
            measure(f"{label}_history_page", lambda: client.ok("repositorySessionHistoryLoad", history_arguments(opened)))
            client.shutdown()
        report["environment"] = {
            "transport": "OpenSSH over loopback; rtt50/rtt150 through a userspace ProxyCommand delay proxy",
            "bandwidth": "20 Mbit/s paced by the proxy for rtt50/rtt150",
            "helper": "debug build of this checkout",
            "note": "artificial delay is a transport experiment, not internet-host acceptance",
        }
        output = ROOT / "build" / "evidence" / "remote-workspaces"
        output.mkdir(parents=True, exist_ok=True)
        (output / "performance.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))


def proxy(port: int, rtt_ms: int, megabits: int) -> int:
    """A ProxyCommand that forwards stdin/stdout to the loopback sshd with half the round-trip
    delay per direction and paced bandwidth. Chunks keep their order and overlap in flight."""
    import queue
    import threading

    connection = socket.create_connection(("127.0.0.1", port))
    one_way = rtt_ms / 2000
    bytes_per_second = megabits * 125_000

    def pump(read, write) -> None:
        pending: "queue.Queue[tuple[float, bytes] | None]" = queue.Queue()

        def deliver() -> None:
            next_free = 0.0
            while (item := pending.get()) is not None:
                due, data = item
                now = time.monotonic()
                start = max(due, next_free)
                if start > now:
                    time.sleep(start - now)
                next_free = max(start, time.monotonic()) + len(data) / bytes_per_second
                try:
                    write(data)
                except OSError:
                    return

        sender = threading.Thread(target=deliver, daemon=True)
        sender.start()
        while True:
            try:
                data = read(65536)
            except OSError:
                data = b""
            if not data:
                pending.put(None)
                sender.join()
                return
            pending.put((time.monotonic() + one_way, data))

    stdin = sys.stdin.buffer.raw
    stdout = sys.stdout.buffer.raw

    def write_out(data: bytes) -> None:
        view = memoryview(data)
        while view:
            written = stdout.write(view)
            view = view[written:]

    upstream = threading.Thread(target=pump, args=(stdin.read, connection.sendall), daemon=True)
    upstream.start()
    pump(connection.recv, write_out)
    return 0


def helper_resources(pid: int) -> tuple[int, int, int]:
    """Resident kibibytes, open descriptors and threads of a helper process."""
    status = Path(f"/proc/{pid}/status").read_text(encoding="utf-8")
    rss = int(next(line.split()[1] for line in status.splitlines() if line.startswith("VmRSS:")))
    threads = int(next(line.split()[1] for line in status.splitlines() if line.startswith("Threads:")))
    return rss, len(list(Path(f"/proc/{pid}/fd").iterdir())), threads


def lane_soak(seconds: int = 1800) -> None:
    if not sys.platform.startswith("linux"):
        raise NotRun("the soak inspects /proc and runs on Linux")
    with Fixture() as fixture:
        fixture.install_helper()
        started = time.monotonic()
        samples: list[tuple[float, int, int, int]] = []
        cycles = reconnects = 0
        commits = git(fixture.repository, "rev-list", "HEAD").split()
        # One long-lived connection: a helper process must stay bounded while sessions are
        # replaced for the whole run. Reconnect churn is covered by the disconnect matrix.
        client = Client(fixture.ssh())
        client.handshake(["read", "listDirectory"])
        pids = helper_processes(fixture)
        while time.monotonic() - started < seconds:
            generation = cycles + 1
            opened = open_repository(client, fixture.repository, generation)
            session = opened["open"]["session"]["sessionId"]
            client.ok("repositorySessionHistoryLoad", history_arguments(opened, generation))
            for index in range(5):
                position = (cycles + index) % (len(commits) - 1)
                client.ok(
                    "repositorySessionCommitDiffLoad",
                    {
                        "sessionId": session,
                        "generation": str(generation),
                        "options": {
                            "commit": commits[position], "firstParent": commits[position + 1],
                            "oldPath": None, "newPath": None, "contextLines": 3,
                            "whitespace": "preserve", "layout": "unified", "maximumRows": 512,
                        },
                    },
                )
            client.ok("listDirectory", {"directory": None, "cursor": None})
            client.ok("closeRepository", {"sessionId": session, "generation": str(generation)})
            cycles += 1
            if pids and cycles % 20 == 0:
                try:
                    samples.append((time.monotonic() - started, *helper_resources(pids[0])))
                except (OSError, StopIteration):
                    pass
        client.shutdown()
        reconnects += 1
        time.sleep(1)
        leftover = helper_processes(fixture)
        check(not leftover, "no helper process outlives the soak")
        check(len(samples) >= 10, f"resource samples were taken ({len(samples)})")
        # Compare per-connection behaviour: within each connection the helper must stabilize.
        warm = [sample for sample in samples if sample[0] > 120] or samples
        first, last = warm[: max(1, len(warm) // 5)], warm[-max(1, len(warm) // 5):]
        def mean(values: list[float]) -> float:
            return sum(values) / len(values)
        rss_growth = mean([s[1] for s in last]) - mean([s[1] for s in first])
        fd_peak = max(s[2] for s in samples)
        thread_peak = max(s[3] for s in samples)
        report = {
            "seconds": seconds,
            "session_cycles": cycles,
            "connections": reconnects,
            "samples": len(samples),
            "rss_kib_first_fifth_mean": round(mean([s[1] for s in first])),
            "rss_kib_last_fifth_mean": round(mean([s[1] for s in last])),
            "rss_kib_growth": round(rss_growth),
            "fd_peak": fd_peak,
            "thread_peak": thread_peak,
            "helper": "debug build of this checkout",
        }
        output = ROOT / "build" / "evidence" / "remote-workspaces"
        output.mkdir(parents=True, exist_ok=True)
        (output / "soak.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
        check(fd_peak < 256, f"descriptors stay bounded (peak {fd_peak})")
        check(rss_growth < 64 * 1024, f"resident memory does not trend upward (growth {round(rss_growth)} KiB)")


LANES = {
    "protocol": lane_protocol,
    "helper": lane_helper,
    "ssh_loopback": lane_ssh_loopback,
    "disconnect_matrix": lane_disconnect_matrix,
    "performance": lane_performance,
    "soak": lane_soak,
}


def main() -> int:
    if len(sys.argv) == 5 and sys.argv[1] == "--proxy":
        return proxy(int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in LANES:
        parser.add_argument(f"--{name.replace('_', '-')}", action="store_true")
    arguments = parser.parse_args()
    selected = [name for name in LANES if getattr(arguments, name)]
    if not selected:
        parser.error("choose at least one lane")
    os.chdir(ROOT)
    use_pinned_flutter()
    if any(name != "protocol" for name in selected):
        run("cargo", "build", "--manifest-path", str(CORE / "Cargo.toml"), "--locked", "-p", "gitlama-remote-helper")
    for name in selected:
        print(f"== {name}")
        try:
            LANES[name]()
        except NotRun as reason:
            print(f"NOT RUN: {name}: {reason}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

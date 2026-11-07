#!/usr/bin/env python3
"""Bounded installed-launch evidence for synthetic CI profiles, never raw output."""
import argparse
import json
import os
import re
from pathlib import Path
import subprocess
import threading
import time

# Only reviewed static categories cross the child-output boundary.
SIGNALS = {
    "invalid_inspection_window_request": b"invalid_inspection_window_request",
    "flutter_isolate_failed": b"Could not prepare isolate",
    "flutter_engine_failed": b"Could not launch engine",
    "flutter_view_failed": b"Unable to create a Flutter view",
    "flutter_controller_failed": b"Failed to create view controller",
    "graphics_context_failed": b"Failed to create OpenGL context",
}


def drain(stream, evidence):
    tail = b""
    try:
        while chunk := stream.read(4096):
            evidence["bytes"] += len(chunk)
            tail = (tail + chunk)[-8192:]
            # Preserve only reviewed enums/numeric codes, never raw output.
            for match in re.finditer(
                rb'gitlama_forwarding_failure=(unsupportedPlatform|invalidArguments|notRunning|authentication|versionSkew|invalidPath|notRepository|busy|precondition|transport)\b'
                rb'|gitlama_windows_ipc=(load_token|random_nonce|connect|encode_request|write_request|read_response):(io_[0-9]{1,10}|protocol_truncated|protocol_other|timeout|authentication|not_running|credential_missing|other)\b', tail
            ):
                code = match.group().decode('ascii')
                if code not in evidence["signals"] and len(evidence["signals"]) < 32:
                    evidence["signals"].append(code)
            for code, marker in SIGNALS.items():
                if marker.lower() in tail.lower() and code not in evidence["signals"]:
                    evidence["signals"].append(code)
    except OSError:
        evidence["readFailed"] = True
    finally:
        stream.close()


def crash_events(pid, started):
    if os.name != "nt":
        return {"status": "not-windows", "events": []}
    # Select by exact PID and timestamp, and project only numeric codes and a
    # constrained module basename. Never export Message, paths, or WER payloads.
    command = r'''
$ErrorActionPreference = 'Stop'
$events = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=[DateTime]::Parse($env:GITLAMA_PROBE_STARTED)} -MaxEvents 64 -ErrorAction SilentlyContinue)
$result = @()
foreach ($event in $events) {
  [xml]$xml = $event.ToXml()
  $data = @{}
  foreach ($entry in $xml.Event.EventData.Data) { $data[[string]$entry.Name] = [string]$entry.'#text' }
  $processId = $data['ProcessId']
  if ($processId -match '^0x[0-9a-fA-F]+$') { $processId = [Convert]::ToInt64($processId.Substring(2), 16) }
  if ([string]$processId -ne $env:GITLAMA_PROBE_PID) { continue }
  $module = $data['ModuleName']
  if ($module -notmatch '^[a-zA-Z0-9_.-]{1,100}$') { $module = 'unavailable' }
  $code = $data['ExceptionCode']
  if ($code -notmatch '^(0x)?[0-9a-fA-F]{8}$') { $code = 'unavailable' }
  $offset = $data['FaultingOffset']
  if ($offset -notmatch '^(0x)?[0-9a-fA-F]{1,16}$') { $offset = 'unavailable' }
  $result += @{eventId=1000; module=$module; exceptionCode=$code; faultOffset=$offset}
  if ($result.Count -ge 8) { break }
}
ConvertTo-Json -InputObject @($result) -Compress
'''
    env = dict(os.environ, GITLAMA_PROBE_PID=str(pid), GITLAMA_PROBE_STARTED=started)
    try:
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
            env=env, capture_output=True, timeout=10, encoding="utf-8", errors="replace",
        )
        if result.returncode:
            return {"status": "query-failed", "events": []}
        return {"status": "queried", "events": json.loads(result.stdout)}
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return {"status": "query-unavailable", "events": []}


def probe(command, env, settings, output, name, survival=5, readiness=30):
    report = {"schema": 1, "probe": name, "result": "failed", "stage": "start",
              "stdout": {"bytes": 0, "signals": []}, "stderr": {"bytes": 0, "signals": []}}
    process = None
    readers = []
    began = time.monotonic()
    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    try:
        process = subprocess.Popen(command, env=env, cwd=Path(command[0]).parent,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        report["pid"] = process.pid
        for stream, key in [(process.stdout, "stdout"), (process.stderr, "stderr")]:
            reader = threading.Thread(target=drain, args=(stream, report[key]), daemon=True)
            reader.start()
            readers.append(reader)
        report["stage"] = "survival"
        deadline = began + survival
        while time.monotonic() < deadline and process.poll() is None:
            time.sleep(0.05)
        if process.poll() is not None:
            report["failure"] = "early_exit"
        elif settings:
            report["stage"] = "settings"
            deadline = time.monotonic() + readiness
            while not settings.is_file():
                if process.poll() is not None:
                    report["failure"] = "exit_before_settings"
                    break
                if time.monotonic() >= deadline:
                    report["failure"] = "settings_timeout"
                    break
                time.sleep(0.05)
        if "failure" not in report:
            if process.poll() is not None:
                report["failure"] = "early_exit"
            else:
                report.update(result="passed", stage="ready")
    except OSError as error:
        report.update(failure="process_start_failed", osError=error.errno,
                      winError=getattr(error, "winerror", None))
    finally:
        report["elapsedMs"] = round((time.monotonic() - began) * 1000)
        if process:
            code = process.poll()
            report["exitCode"] = code
            report["exitCodeHex"] = None if code is None else f"0x{code & 0xffffffff:08X}"
            report["terminatedByProbe"] = code is None
            try:
                if code is None:
                    process.kill()
                process.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                report["cleanupFailure"] = "termination_failed"
                report["result"] = "failed"
            for reader in readers:
                reader.join(timeout=1)
            # Readers may still belong to inherited child pipes. Snapshot only
            # bounded safe counters, without blocking the qualification job.
            report["outputDrainComplete"] = all(not r.is_alive() for r in readers)
            if report["result"] == "failed":
                report["crashEvents"] = crash_events(process.pid, started)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps(report), flush=True)
    return report["result"] == "passed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--repository", type=Path)
    parser.add_argument("--name", choices=["cold-profile-one", "cold-profile-two", "missing-git"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.profile.mkdir(parents=True, exist_ok=True)
    # Isolate product state without relocating the Windows account namespaces
    # used by Credential Manager, DPAPI and native plugins.
    env = dict(os.environ, GITLAMA_PROFILE_ROOT=str(args.profile.resolve()),
               GITLAMA_FORWARDING_DIAGNOSTICS="1")
    command = [str(args.executable.resolve())]
    settings = None
    if args.repository:
        command.append(str(args.repository.resolve()))
        settings = args.profile / "settings.json"
    else:
        env["PATH"] = str(args.profile)
    return 0 if probe(command, env, settings, args.output, args.name) else 1


if __name__ == "__main__":
    raise SystemExit(main())

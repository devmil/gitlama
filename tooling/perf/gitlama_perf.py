#!/usr/bin/env python3
"""Scripted UI performance checks for the Qt Quick build on Hyprland.

Drives a running development build through `GITLAMA_DEV_CONTROL` (see
qml/GitLama/DevControl.qml) and reads Qt's render-loop timing, the GUI-thread
lag probe and the development spans from its log. See
docs/qml-port/performance.md for the setup and what the numbers mean.

  gitlama_perf.py launch <work-dir> [repository...]
      Starts the optimized build with a private profile in <work-dir> and
      moves its window to the headless output's workspace (`--workspace`).
  gitlama_perf.py steps <work-dir> <wait-seconds> <label>=<step>[;<step>...]...
      Runs each scenario (e.g. `to-big=tab:2`) after a timing mark and
      reports frames, settle time, render time and GUI-thread blocking.
  gitlama_perf.py resize <work-dir> [cycles]
      Resizes the floating window like a drag (75 requests a second) and
      reports presented frames, distinct sizes a second and GUI CPU time.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "rust-core/target/dev-opt/gitlama"
FRAME = re.compile(r"^\s*([\d.]+) .*frame rendered in (\d+)ms, polish=(\d+), sync=(\d+), render=(\d+), swap=(\d+), perWindowFrameDelta=(\d+)")
LAG = re.compile(r"^\s*([\d.]+) .*gitlama-dev-lag (\d+)")
SIZE = re.compile(r"^\s*([\d.]+) .*gitlama-dev-frame (\d+) (\d+)")
MARK = re.compile(r"^\s*([\d.]+) .*gitlama-dev-mark (\S+)")


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def dispatch(lua):
    hyprctl("eval", f"hl.dispatch({lua})")


def gitlama_windows():
    return [c for c in json.loads(hyprctl("clients", "-j")) if c["class"] == "de.devmil.gitlama"]


def launch(work, repositories, workspace):
    work.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["GITLAMA_PROFILE_ROOT"] = str(work / "profile")
    # Short: the instance socket inside must fit a Unix socket address.
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / f"gitlama-perf-{os.getpid()}"
    runtime.mkdir(mode=0o700, exist_ok=True)
    env["GITLAMA_RUNTIME_DIR"] = str(runtime)
    env["GITLAMA_QML_DIR"] = str(ROOT / "qml")
    env["GITLAMA_DEV_CONTROL"] = str(work / "control")
    env["GITLAMA_DEV_SPANS"] = env.get("GITLAMA_DEV_SPANS", "4")
    env["QT_FORCE_STDERR_LOGGING"] = "1"
    env["QT_LOGGING_RULES"] = "qt.scenegraph.time.renderloop=true"
    env["QT_MESSAGE_PATTERN"] = "%{time process} %{category}: %{message}"
    (work / "control").write_text("")
    before = {c["pid"] for c in gitlama_windows()}
    with open(work / "log", "w") as log:
        subprocess.Popen([str(BINARY), *repositories], env=env, stdout=log, stderr=subprocess.STDOUT)
    for _ in range(200):
        fresh = [c for c in gitlama_windows() if c["pid"] not in before]
        if fresh:
            pid = fresh[0]["pid"]
            dispatch(f'hl.dsp.window.move({{ workspace = {workspace}, window = "pid:{pid}", follow = false }})')
            (work / "pid").write_text(str(pid))
            print(pid)
            return
        time.sleep(0.2)
    sys.exit("the window did not appear")


def send(work, *steps):
    with open(work / "control", "a") as control:
        control.write("".join(step + "\n" for step in steps))


def entries(work, pattern, after_mark):
    start, found = None, []
    for line in open(work / "log", errors="replace"):
        if start is None:
            mark = MARK.match(line)
            if mark and mark.group(2) == after_mark:
                start = float(mark.group(1))
            continue
        match = pattern.match(line)
        if match:
            found.append(tuple(float(value) for value in match.groups()))
    return start, found


def steps(work, wait, scenarios, repeat):
    results = {}
    for _ in range(repeat):
        for label, scenario in scenarios:
            tag = f"{label}-{time.monotonic_ns()}"
            send(work, "lagProbe:on", f"mark:{tag}", *scenario)
            time.sleep(wait)
            start, frames = entries(work, FRAME, tag)
            _, lags = entries(work, LAG, tag)
            burst, last = [], start
            for frame in frames:
                if frame[0] - last > 0.4 and burst:
                    break
                burst.append(frame)
                last = frame[0]
            end = burst[-1][0] + 0.5 if burst else start + wait
            blocks = [lag for at, lag in lags if start <= at <= end]
            results.setdefault(label, []).append({
                "frames": len(burst),
                "settle_ms": round((burst[-1][0] - start) * 1000) if burst else 0,
                "render_ms": int(sum(frame[1] for frame in burst)),
                "blocked_ms": int(sum(blocks)),
                "worst_block_ms": int(max(blocks, default=0)),
            })
    for label, runs in results.items():
        median = {key: sorted(run[key] for run in runs)[len(runs) // 2] for key in runs[0]}
        print(f"{label:20s} " + " ".join(f"{key}={value}" for key, value in median.items()) + f"  (median of {len(runs)})")


def resize(work, cycles):
    pid = int((work / "pid").read_text())
    window = f'window = "pid:{pid}"'
    if not [c for c in gitlama_windows() if c["pid"] == pid][0]["floating"]:
        dispatch(f'hl.dsp.window.float({{ {window}, action = "enable" }})')
    large, small = (1500, 940), (900, 600)
    dispatch(f"hl.dsp.window.resize({{ x = {large[0]}, y = {large[1]}, relative = false, {window} }})")
    time.sleep(1.5)
    tag = f"resize-{time.monotonic_ns()}"
    send(work, "lagProbe:on", f"mark:{tag}")
    time.sleep(0.3)

    def gui_ticks():
        fields = Path(f"/proc/{pid}/task/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return int(fields[11]) + int(fields[12])

    ticks = gui_ticks()
    began = time.time()
    requests = 0
    for _ in range(cycles):
        for step in list(range(21)) + list(range(20, -1, -1)):
            fraction = step / 20
            width = int(large[0] + (small[0] - large[0]) * fraction)
            height = int(large[1] + (small[1] - large[1]) * fraction)
            dispatch(f"hl.dsp.window.resize({{ x = {width}, y = {height}, relative = false, {window} }})")
            requests += 1
            time.sleep(0.008)
    elapsed = time.time() - began
    gui_ms = (gui_ticks() - ticks) * 1000 // os.sysconf("SC_CLK_TCK")
    time.sleep(1.0)
    start, sizes = entries(work, SIZE, tag)
    sizes = [size for size in sizes if start + 0.3 <= size[0] <= start + 0.3 + elapsed]
    changes = sum(1 for a, b in zip(sizes, sizes[1:]) if a[1:] != b[1:])
    print(f"requests={requests} ({requests / elapsed:.0f}/s) presented={len(sizes)} ({len(sizes) / elapsed:.0f} fps) "
          f"sizes={changes} ({changes / elapsed:.0f}/s) gui_cpu={gui_ms}ms ({100 * gui_ms / 1000 / elapsed:.0f}%)")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    one = sub.add_parser("launch")
    one.add_argument("work", type=Path)
    one.add_argument("repositories", nargs="*")
    one.add_argument("--workspace", type=int, default=31)
    two = sub.add_parser("steps")
    two.add_argument("work", type=Path)
    two.add_argument("wait", type=float)
    two.add_argument("scenarios", nargs="+")
    two.add_argument("--repeat", type=int, default=3)
    three = sub.add_parser("resize")
    three.add_argument("work", type=Path)
    three.add_argument("cycles", type=int, nargs="?", default=3)
    arguments = parser.parse_args()
    if arguments.command == "launch":
        launch(arguments.work, arguments.repositories, arguments.workspace)
    elif arguments.command == "steps":
        scenarios = [(label, value.split(";")) for label, value in (item.split("=", 1) for item in arguments.scenarios)]
        steps(arguments.work, arguments.wait, scenarios, arguments.repeat)
    else:
        resize(arguments.work, arguments.cycles)


if __name__ == "__main__":
    main()

# Measuring UI performance

How the Qt Quick build's interface performance is measured on a Linux desktop,
and what was found with it. Numbers are from one machine (Omarchy, Hyprland
0.56, Qt 6.12, Mesa) and describe populations, not budgets.

## Setup

`tooling/perf/gitlama_perf.py` drives an optimized development build
(`cargo build -p gitlama --profile dev-opt`) through two development hooks:

- `GITLAMA_DEV_CONTROL=<file>`: the window runs the lines written to the file
  (`qml/GitLama/DevControl.qml`): every screenshot step (`tab:<n>`, `open:<path>`,
  `appearance:<json>`, ...), `shot:<png>` (saves the window without quitting),
  `mark:<label>` (a timestamped marker), `lagProbe:on` (logs how late a 10 ms
  timer fires, i.e. how long the GUI thread was blocked, and the size of every
  presented frame), `dump:<depth>` (the item tree) and `hide:`/`show:` an item
  by object name or index path, to bisect.
- `GITLAMA_DEV_SPANS=<ms>`: the pump logs its commands, tasks and projections
  (`driver.rs`, `trace.rs`) when they take at least that long. Qt property
  signals run QML bindings synchronously, so a projection's span includes the
  QML it triggers.

The tool also enables Qt's `qt.scenegraph.time.renderloop` timing and a
`QT_MESSAGE_PATTERN` with process time, so marks, spans, lag and frames share
one clock in the log.

Frames need a visible output: with the laptop panel off (DPMS) Hyprland sends
no frame callbacks. A headless output keeps the user's screen untouched:

```sh
hyprctl output create headless glperf
hyprctl eval 'hl.monitor({ output = "glperf", mode = "1920x1200@60", position = "5000x0", scale = 1.25 })'
python3 tooling/perf/gitlama_perf.py launch /tmp/perf ~/repositories/a ~/repositories/b   # moves to workspace 31
python3 tooling/perf/gitlama_perf.py steps /tmp/perf 2 to-a=tab:0 to-b=tab:1
python3 tooling/perf/gitlama_perf.py resize /tmp/perf
hyprctl output remove glperf
```

`grim` captures stay black on a headless output; use `shot:` instead. Frame
gaps include idle time, so GUI blocking comes from the lag probe and GUI-thread
CPU time, not from `perWindowFrameDelta`.

For native stacks, `perf record -e cycles:u --call-graph dwarf --user-callchains`
works without privileges when it starts the process (`-D -1 --control
fifo:...` records only the interesting window). `qmlprofiler` needs QML
debugging compiled in and was not used.

## Findings (2026-11-28)

Repositories: GitLama itself (950 commits), a 2,700-commit repository and
fdroiddata (123,000 commits, 75,000 files, 70,000 directories).

| | Before | After |
| --- | --- | --- |
| Idle, fdroiddata open (any tab) | 1.9 cores (GitLama 105%, Git 84%), 28 repaints/s | 0.1 core, no repaints |
| Interactive resize, sizes shown per second (75 requested) | 29 | 55-68 |
| Tab switch, settle (small/medium repository) | 0.9-1.4 s | 0.4-0.6 s |
| Tab switch, longest GUI stall | 100-380 ms | 40-60 ms |
| First repository open from the welcome screen, longest GUI stall | 920 ms | 70-80 ms |

- **Polling watcher on large trees.** A worktree with more than 50,000
  directories exceeds devmil-git's native watch limit and falls back to
  polling. The repository worker asked the poller for events every 25 ms and
  each call rescanned up to 50,000 paths; the truncated scan reported an
  overflow every time, so every scan also ran a full `git status`. devmil-git
  now scans at most once per poll interval (longer when a scan is expensive)
  and asks a truncated tree for a full refresh when it first stops short and
  then every 30 s.
- **Resize at half rate.** Qt 6's ListView requests one more frame after every
  height change (also in a minimal scene, not GitLama-specific); with the
  basic render loop's blocking swap each resize step waited a vsync for it.
  The main window presents with swap interval 0 on Wayland; animation frames
  stay paced by frame callbacks. The threaded render loop was worse (21
  sizes/s). Interactive resize now renders about 110 fps at 80-90% of a core
  while the pointer moves.
- **Workspace construction.** The first open built the whole workspace in
  the signal that announced the first tab; it now loads asynchronously while
  the welcome screen stays.
- **Whole-list rebuilds.** The inspector's file lists were arrays inside the
  inspector state, so every state change rebuilt them; they are keyed row
  models now. The closed repository details panel re-evaluated its content on
  every workspace change (about 10 ms each).
- **Remaining tab-switch cost** is spread over three pump passes (workspace
  and History projection, inspector state, diff document) of 10-35 ms each,
  plus one 20-50 ms polish frame that creates the new diff and History rows.
  Each state object is one JSON value, so any change re-evaluates every
  binding that reads it; splitting the larger states (inspector, workspace
  `active`) into narrower properties is the next step if switching should get
  faster.

Not measured: macOS, Windows, X11, physical pointer drags (the compositor's
configure rate may differ from scripted requests), multi-monitor moves.

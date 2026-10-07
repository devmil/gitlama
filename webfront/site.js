// Page behaviour for the landing page: the lane field behind the hero, the
// Lama on its merge, the Compass scroll rule, reveals, and the two small
// models. Nothing here loads
// data; releases.js owns the release index.
(function () {
  "use strict";

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  const dark = window.matchMedia("(prefers-color-scheme: dark)");

  // A generated history that grows at the top and drifts down. Geometry
  // follows the Meridian graph: a lane changes column on a cubic S-curve that
  // leaves and lands vertically, commits are rings cut out of the ground, and
  // focusing a commit lights its ancestry while everything else steps back.
  function laneField(canvas) {
    const hero = canvas.parentElement;
    const context = canvas.getContext("2d");
    const PITCH = 28, ROW = 40, SPEED = 7, REACH = 44;
    const REST = 0.55, UNLIT = 0.22, FLOW = 26;
    const COMMIT = 0.45, FORK = 0.16, DENSITY = 0.5;

    let width = 0, height = 0, ratio = 1, columns = 0, origin = 0;
    let lanes = [], nodes = [], top = 0, scroll = 0;
    let palette = [], ground = "#000";
    let focus = null, focusAt = 0, stamp = 0, dim = 0;
    let pointer = null, nextAuto = 1800, releaseAuto = 0;
    let visible = true, frame = 0, last = 0;

    // The stage scopes its own lane colours and ground.
    function readColours() {
      const style = getComputedStyle(canvas);
      palette = [];
      for (let lane = 1; lane <= 8; lane++) palette.push(style.getPropertyValue(`--lane-${lane}`).trim());
      ground = style.getPropertyValue("--ground").trim();
    }

    function add(row, column, made) {
      const node = { row, column, edges: [], merge: false, glow: 0, mark: 0 };
      nodes.push(node);
      if (made) made.set(column, node);
      return node;
    }

    function step() {
      const row = ++top;
      const made = new Map();
      const freed = new Set();
      // A side branch that has lived long enough merges into a neighbour.
      for (let column = 0; column < columns; column++) {
        const lane = lanes[column];
        if (!lane || lane.trunk || lane.age < lane.life || made.has(column)) continue;
        const target = [lane.from, column - 1, column + 1].find((other) =>
          Math.abs(other - column) === 1 && lanes[other] && !made.has(other));
        if (target === undefined) continue;
        const node = add(row, target, made);
        node.merge = true;
        node.edges.push({ parent: lanes[target].last, kind: 0 }, { parent: lane.last, kind: 2 });
        lanes[target].last = node;
        lanes[column] = null;
        freed.add(column);
      }
      // A lane whose newest commit is one row back may fork into a free column.
      let active = lanes.filter(Boolean).length;
      for (let column = 0; column < columns; column++) {
        const lane = lanes[column];
        if (!lane || lane.last.row !== row - 1 || active >= columns * DENSITY || Math.random() > FORK) continue;
        const free = (other) => other >= 0 && other < columns && !lanes[other] && !freed.has(other);
        const side = Math.random() < 0.5 ? -1 : 1;
        const target = free(column + side) ? column + side : free(column - side) ? column - side : -1;
        if (target < 0) continue;
        const node = add(row, target, made);
        node.edges.push({ parent: lane.last, kind: 1 });
        lanes[target] = { last: node, age: 0, life: 3 + Math.floor(Math.random() * 11), from: column, trunk: false };
        active++;
      }
      for (let column = 0; column < columns; column++) {
        const lane = lanes[column];
        if (!lane) continue;
        lane.age++;
        if (made.has(column) || Math.random() > COMMIT) continue;
        const node = add(row, column, made);
        node.edges.push({ parent: lane.last, kind: 0 });
        lane.last = node;
      }
      const oldest = top - Math.ceil(height / ROW) - 18;
      while (nodes.length && nodes[0].row < oldest) nodes.shift();
    }

    function seed() {
      lanes = new Array(columns).fill(null);
      nodes = [];
      top = 0;
      scroll = 0;
      focus = null;
      for (let column = 1 + Math.floor(Math.random() * 3); column < columns; column += 3 + Math.floor(Math.random() * 4)) {
        lanes[column] = { last: add(0, column), age: 0, life: 0, from: column, trunk: true };
      }
      for (let row = Math.ceil(height / ROW) + 2; row > 0; row--) step();
    }

    function resize() {
      const box = canvas.getBoundingClientRect();
      if (!box.width || !box.height) return;
      ratio = Math.min(window.devicePixelRatio || 1, 2);
      const nextColumns = Math.ceil(box.width / PITCH) + 1;
      const reseed = nextColumns !== columns || Math.abs(box.height - height) > ROW;
      width = box.width;
      height = box.height;
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      columns = nextColumns;
      origin = (width - (columns - 1) * PITCH) / 2;
      if (reseed) seed();
      render(performance.now(), 0);
    }

    const x = (column) => origin + column * PITCH;
    const y = (row) => (top - row) * ROW + scroll - ROW / 2;

    function light(node, instant) {
      focus = node;
      stamp++;
      // Moving along the lit path keeps its state instead of replaying the flow.
      focusAt = instant || (node && node.glow > 0.5) ? -1e9 : performance.now();
      const queue = node ? [node] : [];
      while (queue.length) {
        const next = queue.pop();
        if (next.mark === stamp) continue;
        next.mark = stamp;
        next.edges.forEach((edge) => queue.push(edge.parent));
      }
    }

    function nearest(point, reach) {
      let best = null, distance = reach * reach;
      for (const node of nodes) {
        const dx = x(node.column) - point.x, dy = y(node.row) - point.y;
        const d = dx * dx + dy * dy;
        if (d < distance) { best = node; distance = d; }
      }
      return best;
    }

    function curve(x1, y1, x2, y2) {
      const middle = (y1 + y2) / 2;
      context.bezierCurveTo(x1, middle, x2, middle, x2, y2);
    }

    function stroke(edge, child, rest) {
      const parent = edge.parent;
      if (y(child.row) > height + ROW) return;
      const glow = Math.min(child.glow, parent.glow);
      context.globalAlpha = rest + (1 - rest) * glow;
      context.lineWidth = 2 + 0.5 * glow;
      context.strokeStyle = palette[(edge.kind === 2 ? parent.column : child.column) % 8];
      context.beginPath();
      context.moveTo(x(parent.column), y(parent.row));
      if (edge.kind === 1) curve(x(parent.column), y(parent.row), x(child.column), y(parent.row + 1));
      if (edge.kind === 2) {
        context.lineTo(x(parent.column), y(child.row - 1));
        curve(x(parent.column), y(child.row - 1), x(child.column), y(child.row));
      }
      context.lineTo(x(child.column), y(child.row));
      context.stroke();
    }

    function render(now, elapsed) {
      const still = reduced.matches;
      const ease = still ? 1 : 1 - Math.exp(-elapsed / 70);
      dim += ((focus ? 1 : 0) - dim) * ease;
      const rest = REST + (UNLIT - REST) * dim;
      for (const node of nodes) {
        const lit = focus && node.mark === stamp
          && (still || now - focusAt >= (focus.row - node.row) * FLOW);
        node.glow += ((lit ? 1 : 0) - node.glow) * ease;
      }

      context.setTransform(ratio, 0, 0, ratio, 0, 0);
      context.clearRect(0, 0, width, height);
      context.lineCap = "round";
      // Straight segments first, then curves, then the rings that cut them.
      for (const curved of [false, true]) {
        for (const node of nodes) {
          for (const edge of node.edges) if ((edge.kind !== 0) === curved) stroke(edge, node, rest);
        }
      }
      context.globalAlpha = rest;
      context.lineWidth = 2;
      lanes.forEach((lane, column) => {
        if (!lane) return;
        context.strokeStyle = palette[column % 8];
        context.beginPath();
        context.moveTo(x(column), y(lane.last.row));
        context.lineTo(x(column), -ROW);
        context.stroke();
      });
      for (const node of nodes) {
        const cx = x(node.column), cy = y(node.row);
        if (cy > height + ROW || cy < -ROW) continue;
        const colour = palette[node.column % 8];
        context.globalAlpha = 1;
        context.fillStyle = ground;
        context.beginPath();
        context.arc(cx, cy, node === focus ? 8 : 5.5, 0, Math.PI * 2);
        context.fill();
        context.globalAlpha = rest + (1 - rest) * node.glow;
        context.strokeStyle = colour;
        context.fillStyle = colour;
        if (node === focus) {
          // The focused commit takes the HEAD shape: a dot, a gap, a ring.
          context.beginPath();
          context.arc(cx, cy, 4, 0, Math.PI * 2);
          context.fill();
          context.lineWidth = 1.5;
          context.beginPath();
          context.arc(cx, cy, 7, 0, Math.PI * 2);
          context.stroke();
          continue;
        }
        context.lineWidth = 2;
        context.beginPath();
        context.arc(cx, cy, 4.5, 0, Math.PI * 2);
        context.stroke();
        if (node.merge) {
          context.beginPath();
          context.arc(cx, cy, 1.75, 0, Math.PI * 2);
          context.fill();
        }
      }
      context.globalAlpha = 1;
    }

    function tick(now) {
      frame = 0;
      const elapsed = Math.min(now - last, 64);
      last = now;
      if (!reduced.matches) {
        scroll += SPEED * elapsed / 1000;
        while (scroll >= ROW) { scroll -= ROW; step(); }
      }
      if (pointer) {
        const node = nearest(pointer, REACH);
        if (node !== focus) light(node, false);
      } else if (!reduced.matches) {
        // Left alone, the field focuses a commit near the top now and then.
        if (focus && now > releaseAuto) { light(null, false); nextAuto = now + 1800; }
        if (!focus && now > nextAuto) {
          const node = nearest({ x: width * (0.08 + Math.random() * 0.84), y: height * 0.12 }, width);
          light(node, false);
          releaseAuto = now + 3600;
        }
      }
      if (focus && focus.row < top - Math.ceil(height / ROW) - 2) light(null, false);
      render(now, elapsed);
      schedule();
    }

    function schedule() {
      if (frame || !visible || document.hidden) return;
      if (reduced.matches && !pointer && !focus) return;
      last = last || performance.now();
      frame = requestAnimationFrame(tick);
    }

    function wake() {
      last = performance.now();
      schedule();
    }

    hero.addEventListener("pointermove", (event) => {
      const box = canvas.getBoundingClientRect();
      pointer = { x: event.clientX - box.left, y: event.clientY - box.top };
      wake();
    });
    hero.addEventListener("pointerleave", () => {
      pointer = null;
      light(null, false);
      nextAuto = performance.now() + 2400;
      render(performance.now(), 0);
      wake();
    });
    new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      wake();
    }).observe(hero);
    document.addEventListener("visibilitychange", wake);
    dark.addEventListener("change", () => { readColours(); render(performance.now(), 0); });
    reduced.addEventListener("change", wake);
    new ResizeObserver(resize).observe(canvas);

    readColours();
    resize();
    wake();
  }

  // The Lama on the merge: it greets with a nod, then stands proud. Every few
  // seconds a commit runs into the merge: along the branch, under the
  // Lama's belly, or along the trunk, right under its feet, so it jumps.
  // Now and then both arrive at once and the merge is celebrated. Hovering
  // the scene nods again. Reduced motion keeps the still pose.
  function heroLama(scene) {
    const lama = document.getElementById("hero-lama");
    const branch = document.getElementById("merge-branch");
    const runner = document.getElementById("commit-runner");
    const head = document.getElementById("merge-head");
    if (!lama || !branch || !runner || !head) return;
    const RUN = 1400, PAUSE = 4200;
    const length = branch.getTotalLength();
    // A second commit for the trunk.
    const trunkRunner = runner.cloneNode(false);
    trunkRunner.removeAttribute("id");
    runner.after(trunkRunner);
    // The trunk, in scene units: the commit's radius, the speed of a trunk
    // commit, and where the Lama's legs are (lama-antics.js, FEET).
    const R = 4, TRUNK_FROM = 24, TRUNK_TO = 180, TRUNK_MS = 1750;
    const SPEED = (TRUNK_TO - TRUNK_FROM) / TRUNK_MS;
    const FEET = [98 + 72 * 0.23, 98 + 72 * 0.87];
    let hovering = false, visible = true, sending = false, timer = 0, antics = null;

    function pose(hello) { lama.classList.toggle("is-hello", hello); }
    setTimeout(() => { if (!hovering) pose(false); }, 1600);
    scene.addEventListener("pointerenter", () => { hovering = true; pose(true); });
    scene.addEventListener("pointerleave", () => { hovering = false; pose(false); });

    function replay(node, name) {
      node.classList.remove(name);
      void node.getBBox();
      node.classList.add(name);
    }

    const frames = (duration, step) => new Promise((resolve) => {
      const begin = performance.now();
      const tick = (now) => {
        const t = Math.min((now - begin) / duration, 1);
        step(t);
        if (t < 1) requestAnimationFrame(tick); else resolve();
      };
      requestAnimationFrame(tick);
    });
    const show = (node, x, y, t) => {
      node.setAttribute("cx", x.toFixed(2));
      node.setAttribute("cy", y.toFixed(2));
      node.style.opacity = String(Math.min(1, t * 8, (1 - t) * 8));
    };
    // Ease in and out so the commit leaves and lands gently.
    const alongBranch = () => frames(RUN, (t) => {
      const eased = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      const point = branch.getPointAtLength(eased * length);
      show(runner, point.x, point.y, t);
    });
    // The trunk commit keeps a steady pace, so the Lama can time its jump.
    const alongTrunk = () => frames(TRUNK_MS, (t) => show(trunkRunner, TRUNK_FROM + (TRUNK_TO - TRUNK_FROM) * t, 87, t));

    const JUMPS = ["hop", "tuck", "kick", "hop", "spin", "flip", "twist"];
    let jumps = [];
    const nextJump = () => {
      if (!jumps.length) jumps = JUMPS.slice().sort(() => Math.random() - 0.5);
      return jumps.shift();
    };
    const free = () => antics && antics.busy() !== "tap";

    function land() {
      replay(head, "landed");
      if (!antics) replay(lama, "is-hopping");
    }

    async function send(kind) {
      if (sending) return;
      sending = true;
      clearTimeout(timer);
      const trunk = kind === "trunk" || kind === "both";
      const viaBranch = kind === "branch" || kind === "both";
      if (free()) {
        antics.react(async (a) => {
          if (trunk) {
            // From the time the commit touches the front feet until it
            // has left the back feet.
            const touch = (FEET[0] - (TRUNK_FROM + R)) / SPEED;
            const clear = (FEET[1] - (TRUNK_FROM - R)) / SPEED;
            a.pose("hello");
            await a.wait(touch - 300);
            a.pose(null);
            await a.jump({ lead: 220, air: clear - touch + 160, style: kind === "both" ? "spin" : nextJump() });
          } else {
            // It watches the commit pass under its belly.
            a.pose("hello");
            await a.wait(RUN * 0.72);
            a.pose("standing");
          }
          // Then it turns to see it land on the merge behind it.
          a.face("right");
          await a.wait(trunk ? 260 : RUN * 0.28 + 160);
          if (kind === "both") {
            a.bits("confetti", 16, [0.9, 0.5], { angle: -Math.PI / 2, spread: 1.1, reach: 64, fall: 50, turn: 480, duration: 1400 });
            a.pose("hello");
            await a.move("doubleHop");
          } else {
            await a.move("hop");
          }
          a.face(null);
          a.pose(null);
        }, "commit").finally(() => antics.face(null));
      }
      const runs = [];
      if (trunk) runs.push(alongTrunk());
      // Both commits reach the merge together.
      if (viaBranch) runs.push(new Promise((resolve) => setTimeout(resolve, trunk ? TRUNK_MS - RUN : 0)).then(alongBranch));
      await Promise.all(runs);
      runner.style.opacity = "0";
      trunkRunner.style.opacity = "0";
      land();
      sending = false;
      queue(PAUSE);
    }

    const KINDS = ["branch", "trunk", "branch", "trunk", "both", "trunk", "branch"];
    let kinds = [];
    const nextKind = () => {
      if (!antics) return "branch";
      if (!kinds.length) kinds = KINDS.slice().sort(() => Math.random() - 0.5);
      return kinds.shift();
    };

    function queue(delay) {
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (sending || reduced.matches || !visible || document.hidden) { queue(PAUSE); return; }
        send(nextKind());
      }, delay);
    }

    lama.addEventListener("animationend", () => lama.classList.remove("is-hopping"));
    new IntersectionObserver((entries) => { visible = entries[0].isIntersecting; }).observe(scene);
    queue(2600);

    // Between commits the Lama gets up to things of its own (lama-antics.js,
    // from the brand repository). Tapping it plays a gag; one of them is a
    // big hop that pushes a commit along the merge branch.
    if (window.LamaAntics) {
      antics = LamaAntics.attach(lama, {
        base: "assets/lama/",
        colors: ["#5BB1FE", "#056CB3", "#FFF8EB"],
        taps: {
          commit: async (antic) => {
            if (!antic.reduced()) send("branch");
            await antic.move("bigHop");
          },
        },
      });
    }
  }

  // The Compass rule follows scroll progress; the product shot settles flat.
  function scrollEffects() {
    const compass = document.querySelector(".compass");
    const shot = document.getElementById("window");
    let queued = false;
    function apply() {
      queued = false;
      const range = document.documentElement.scrollHeight - window.innerHeight;
      if (compass) compass.style.setProperty("--progress", range > 0 ? Math.min(window.scrollY / range, 1) : 0);
      if (shot && !reduced.matches) {
        const start = shot.getBoundingClientRect().top / window.innerHeight;
        shot.style.setProperty("--tilt", (Math.max(0, Math.min((start - 0.25) / 0.6, 1)) * 7).toFixed(2));
      }
    }
    function queue() {
      if (!queued) { queued = true; requestAnimationFrame(apply); }
    }
    window.addEventListener("scroll", queue, { passive: true });
    window.addEventListener("resize", queue);
    apply();
  }

  function reveals() {
    const targets = document.querySelectorAll(".reveal, .section");
    if (!("IntersectionObserver" in window)) {
      targets.forEach((target) => target.classList.add("in"));
      return;
    }
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("in");
        observer.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -8% 0px" });
    targets.forEach((target) => observer.observe(target));
  }

  function shotTheme() {
    const shot = document.getElementById("window");
    const image = document.getElementById("shot");
    if (!shot || !image) return;
    const buttons = shot.querySelectorAll("[data-shot]");
    let chosen = false;
    function show(theme) {
      shot.dataset.theme = theme;
      buttons.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.shot === theme)));
    }
    buttons.forEach((button) => button.addEventListener("click", () => {
      chosen = true;
      image.parentElement.querySelectorAll("source").forEach((source) => source.remove());
      image.src = `assets/workspace-${button.dataset.shot}.png`;
      show(button.dataset.shot);
    }));
    dark.addEventListener("change", () => { if (!chosen) show(dark.matches ? "dark" : "light"); });
    show(dark.matches ? "dark" : "light");
  }

  // Graph model: selecting a commit lights its ancestry; hovering previews it.
  function graphModel() {
    const model = document.getElementById("graph-demo");
    if (!model) return;
    const rows = Array.from(model.querySelectorAll(".row"));
    const parents = new Map(rows.map((row) => [row.dataset.commit, row.dataset.parents.split(" ").filter(Boolean)]));
    let selected = rows.find((row) => row.getAttribute("aria-pressed") === "true") || rows[0];

    function ancestry(commit) {
      const seen = new Set();
      const queue = [commit];
      while (queue.length) {
        const next = queue.pop();
        if (seen.has(next)) continue;
        seen.add(next);
        queue.push(...parents.get(next));
      }
      return seen;
    }

    function paint(commit) {
      const lit = ancestry(commit);
      rows.forEach((row) => row.classList.toggle("unlit", !lit.has(row.dataset.commit)));
      model.querySelectorAll("[data-node]").forEach((node) => {
        node.classList.toggle("unlit", !lit.has(node.dataset.node));
        node.classList.toggle("on", node.dataset.node === selected.dataset.commit);
      });
      model.querySelectorAll("[data-edge]").forEach((edge) => {
        const on = edge.dataset.edge.split(" ").every((end) => lit.has(end));
        edge.classList.toggle("lit", on);
        edge.classList.toggle("unlit", !on);
      });
    }

    rows.forEach((row) => {
      row.addEventListener("click", () => {
        selected.setAttribute("aria-pressed", "false");
        selected = row;
        row.setAttribute("aria-pressed", "true");
        paint(row.dataset.commit);
      });
      row.addEventListener("pointerenter", () => paint(row.dataset.commit));
      row.addEventListener("pointerleave", () => paint(selected.dataset.commit));
    });
    paint(selected.dataset.commit);
  }

  // Diff model: an unstaged hunk like the app's. A line-number click selects
  // a changed line; Stage (or S) and Stage hunk move the selected changes to
  // the index. A staged addition turns into context, a staged deletion leaves
  // the unstaged diff, and line numbers follow.
  function diffModel() {
    const model = document.getElementById("diff-demo");
    const view = document.getElementById("diff-lines");
    const count = document.getElementById("diff-count");
    const range = document.getElementById("hunk-range");
    const stageHunk = document.getElementById("stage-hunk");
    const clean = document.getElementById("diff-clean");
    if (!model || !view || !count || !range || !stageHunk || !clean) return;
    const initial = Array.from(view.querySelectorAll(".dl")).map((row) => ({
      kind: row.classList.contains("add") ? "add" : row.classList.contains("del") ? "del" : "ctx",
      code: row.querySelector("code").textContent,
    }));
    let lines = [], selected = new Set(), staged = 0;
    const floating = document.createElement("button");
    floating.type = "button";
    floating.className = "button small secondary floating-stage";
    floating.append(stageHunk.querySelector(".icon").cloneNode(), "Stage");

    function reset() {
      lines = initial.map((line, index) => ({ ...line, id: index }));
      // Start with one selected addition so the floating action is visible.
      selected = new Set([lines.find((line) => line.kind === "add").id]);
      staged = 0;
      render();
    }

    function stage(ids) {
      const changed = lines.filter((line) => ids.has(line.id) && line.kind !== "ctx");
      if (!changed.length) return;
      changed.forEach((line) => { line.washed = true; });
      staged += changed.length;
      render();
      setTimeout(() => {
        lines = lines.filter((line) => !(line.washed && line.kind === "del"));
        lines.forEach((line) => { if (line.washed) { line.kind = "ctx"; line.washed = false; } });
        selected.clear();
        render();
      }, reduced.matches ? 0 : 240);
    }

    function render() {
      const focusedId = document.activeElement && document.activeElement.dataset.line;
      view.textContent = "";
      const changes = lines.filter((line) => line.kind !== "ctx").length;
      let old = 41, current = 41, oldCount = 0, newCount = 0;
      lines.forEach((line, index) => {
        const row = document.createElement("div");
        row.className = `dl ${line.kind === "ctx" ? "" : line.kind}`;
        const isSelected = selected.has(line.id);
        if (isSelected) {
          row.classList.add("selected");
          if (!lines[index - 1] || !selected.has(lines[index - 1].id)) row.classList.add("run-start");
          if (!lines[index + 1] || !selected.has(lines[index + 1].id)) row.classList.add("run-end");
        }
        if (line.washed) row.classList.add("wash");
        const numbers = [line.kind === "add" ? "" : old, line.kind === "del" ? "" : current];
        if (line.kind !== "add") { old++; oldCount++; }
        if (line.kind !== "del") { current++; newCount++; }
        const gutter = document.createElement(line.kind === "ctx" ? "span" : "button");
        gutter.className = "gutter";
        numbers.forEach((number) => {
          const cell = document.createElement("span");
          cell.className = "ln";
          cell.textContent = number;
          gutter.append(cell);
        });
        if (line.kind !== "ctx") {
          gutter.type = "button";
          gutter.dataset.line = line.id;
          gutter.setAttribute("aria-pressed", String(isSelected));
          gutter.setAttribute("aria-label", `Select ${line.kind === "add" ? "added" : "removed"} line: ${line.code.trim()}`);
          gutter.addEventListener("click", () => {
            if (selected.has(line.id)) selected.delete(line.id); else selected.add(line.id);
            render();
          });
        }
        const sign = document.createElement("span");
        sign.className = "sign";
        sign.textContent = line.kind === "add" ? "+" : line.kind === "del" ? "-" : " ";
        const code = document.createElement("code");
        code.textContent = line.code;
        row.append(gutter, sign, code);
        view.append(row);
      });
      range.textContent = `@@ -41,${oldCount} +41,${newCount} @@`;
      stageHunk.disabled = changes === 0;
      count.textContent = staged ? `${staged} staged · ${changes} unstaged` : `${changes} unstaged`;
      if (changes === 0) {
        // Everything is staged: the app's resting Lama takes the empty side.
        view.textContent = "";
        const empty = clean.content.firstElementChild.cloneNode(true);
        const again = document.createElement("button");
        again.type = "button";
        again.className = "button small secondary";
        again.textContent = "Start over";
        again.addEventListener("click", reset);
        empty.append(again);
        view.append(empty);
        return;
      }
      const first = view.querySelector(".dl.selected:not(.wash)");
      const actionable = lines.some((line) => selected.has(line.id) && line.kind !== "ctx" && !line.washed);
      if (first && actionable) {
        floating.style.top = `${Math.max(0, first.offsetTop - 28)}px`;
        view.append(floating);
      }
      const refocus = focusedId && view.querySelector(`[data-line="${focusedId}"]`);
      if (refocus) refocus.focus();
    }

    floating.addEventListener("click", () => stage(new Set(selected)));
    stageHunk.addEventListener("click", () => stage(new Set(lines.map((line) => line.id))));
    model.addEventListener("keydown", (event) => {
      if (event.key.toLowerCase() === "s" && !event.metaKey && !event.ctrlKey && selected.size) {
        event.preventDefault();
        stage(new Set(selected));
      }
      if (event.key === "Escape" && selected.size) { selected.clear(); render(); }
    });
    reset();
  }

  const field = document.getElementById("lane-field");
  if (field && field.getContext) laneField(field);
  const scene = document.getElementById("hero-scene");
  if (scene) heroLama(scene);
  scrollEffects();
  reveals();
  shotTheme();
  graphModel();
  diffModel();
})();

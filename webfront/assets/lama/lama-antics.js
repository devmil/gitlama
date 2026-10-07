/* Lama antics: idle tricks, tap gags and scene reactions for the hero Lama
   on Devmil app websites. Vendored unchanged by each site from the brand
   repository (assets/web); pair it with lama-antics.css.

   The character rules hold (guidelines/character.md): the Lama never speaks
   and is never redrawn. Antics move the whole Lama, turn it around, swap
   between the constructed poses and their shades-up variants, and scatter
   small shapes around it. Everything here is decoration: the hero must read
   the same without it.

     const antics = LamaAntics.attach(lamaElement, {
       base: "assets/lama/",        // folder holding the pose SVGs
       colors: ["#24C27D", ...],    // confetti, hearts and butterflies
       idle: { name: (api) => ... },// optional site antics
       taps: { name: (api) => ... },
       exclude: ["zoomies"],        // shared antics that do not suit the scene
       watch: true,                 // turn to look at a pointer behind it
     });

   lamaElement holds the existing pose images (class "pose", one also
   "proud"). It may be an HTML element or an SVG group. The site keeps its
   own hop and hello classes on that element; the antics animate an inner
   rig that wraps the poses, so both compose. Pose swaps under the antics
   are quick fades (lama-antics.css), whatever the site's own transition.

   Scenes react through the returned controller: react(antic) runs a site
   antic now (an api.jump timed to clear an obstacle, say), busy() reports
   what is running, face() turns the Lama, freeze() holds it still for a
   moment and snapshot() copies its current frame into a cloned Lama. */
(() => {
  "use strict";

  const SVG = "http://www.w3.org/2000/svg";
  const POSES = {
    proud: "lama-proud.svg",
    hello: "lama-standing-nod.svg",
    standing: "lama-standing.svg",
    resting: "lama-resting.svg",
    restingNod: "lama-nod.svg",
    shadesUp: "lama-proud-shades-up.svg",
  };
  /* Points on the 120-unit artwork (proud pose, facing left), as fractions,
     from assets/lama/lama-geometry.json. */
  const HEAD = [0.27, 0.2];
  const SHADES = [0.26, 0.25];
  const MUZZLE = [0.1, 0.35];
  const NOSE_TOP = [0.15, 0.27];
  const BODY = [0.6, 0.55];
  const FEET = [0.55, 0.92];
  const FRONT_FOOT = [0.28, 0.92];
  const BACK_FOOT = [0.79, 0.92];
  /* The rig turns about 50% 92% (lama-antics.css). Pivots for rotations
     about other points, as percentages of the Lama's box from there. */
  const PIVOT = {
    feet: [0, 0],
    body: [3, -32],
    front: [-22, 0],
    back: [29, 0],
  };

  const SHAPES = {
    confetti: '<rect x="2" y="5" width="8" height="4" rx="1"/>',
    heart: '<path d="M6 10.6 1.7 6.4A2.7 2.7 0 0 1 6 3a2.7 2.7 0 0 1 4.3 3.4Z"/>',
    spark: '<path d="M6 0Q6.8 5.2 12 6 6.8 6.8 6 12 5.2 6.8 0 6 5.2 5.2 6 0Z"/>',
    star: '<path d="M6 .5l1.6 3.6 3.9.4-2.9 2.6.8 3.9L6 9 2.6 11l.8-3.9L.5 4.5l3.9-.4Z"/>',
    puff: '<circle cx="6" cy="6" r="5"/>',
    bubble: '<circle cx="6" cy="6" r="4.2" fill="none" stroke="currentColor" stroke-width="1.4"/>',
    line: '<rect x="0" y="5" width="12" height="2" rx="1"/>',
    note: '<circle cx="4.4" cy="9.2" r="2.4"/><rect x="5.6" y="1.2" width="1.4" height="8.2" rx=".7"/><path d="M6.6 1.2q4.2.9 3.8 5-1.2-2-3.8-2.4Z"/>',
    butterfly: '<g class="lama-antics-wings"><circle cx="3.4" cy="4.6" r="3.1"/><circle cx="8.6" cy="4.6" r="3.1"/><circle cx="4.1" cy="8.7" r="2.1" fill="var(--lama-antics-tint)"/><circle cx="7.9" cy="8.7" r="2.1" fill="var(--lama-antics-tint)"/></g><rect x="5.4" y="2.6" width="1.2" height="7.6" rx=".6" opacity=".55" fill="#17171E"/>',
    bang: '<rect x="5.2" y="0" width="1.6" height="7" rx=".8"/>',
  };

  const rand = (low, high) => low + Math.random() * (high - low);
  const pick = (list) => list[Math.floor(Math.random() * list.length)];
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
  const round = (value) => Math.round(value * 100) / 100;

  /* One transform with the same function list every time, so keyframes
     interpolate part by part. x and y are percentages of the Lama's box;
     the rotation and scale act about a pivot from PIVOT. */
  function pose3({ x = 0, y = 0, r = 0, sx = 1, sy = 1, pivot = PIVOT.feet } = {}) {
    const [px, py] = pivot;
    return `translate(${round(x)}%, ${round(y)}%) translate(${px}%, ${py}%) rotate(${round(r)}deg) scale(${round(sx)}, ${round(sy)}) translate(${-px}%, ${-py}%)`;
  }

  /* Shuffled bags, so neither the idle loop nor tapping repeats itself. */
  function bag(names) {
    let queue = [];
    let last = null;
    return () => {
      if (!queue.length) {
        queue = names.slice().sort(() => Math.random() - 0.5);
        if (queue.length > 1 && queue[0] === last) queue.push(queue.shift());
      }
      last = queue.shift();
      return last;
    };
  }

  /* Shapes live on a fixed layer, so nothing clips them and nothing scrolls
     because of them. The layer's world moves with the page, so a shape
     stays where it was thrown when the visitor scrolls. */
  let layer = null;
  let world = null;
  function bitsLayer() {
    if (!layer || !layer.isConnected) {
      layer = document.createElement("div");
      layer.className = "lama-antics-layer";
      layer.setAttribute("aria-hidden", "true");
      world = document.createElement("div");
      world.className = "lama-antics-world";
      layer.appendChild(world);
      document.body.appendChild(layer);
      const sync = () => { world.style.transform = `translate(${-window.scrollX}px, ${-window.scrollY}px)`; };
      window.addEventListener("scroll", sync, { passive: true });
      sync();
    }
    return world;
  }

  function attach(lama, options = {}) {
    if (!lama || lama.lamaAntics) return lama && lama.lamaAntics;
    const base = options.base || "assets/lama/";
    const colors = options.colors && options.colors.length ? options.colors : ["#FFF8EB"];
    const exclude = new Set(options.exclude || []);
    const reduced = matchMedia("(prefers-reduced-motion: reduce)");
    const isSvg = lama instanceof SVGElement;
    const template = lama.querySelector(".pose.proud") || lama.querySelector(".pose");
    if (!template) return null;

    /* The rig wraps the poses so antics compose with the site's own hop on
       the outer element. Inside it, the turn mirrors the Lama when it faces
       right. */
    const make = (name) => {
      const node = isSvg ? document.createElementNS(SVG, "g") : document.createElement("div");
      node.setAttribute("class", name);
      return node;
    };
    const rig = make("lama-antics-rig");
    const turn = make("lama-antics-turn");
    while (lama.firstChild) turn.appendChild(lama.firstChild);
    rig.appendChild(turn);
    lama.appendChild(rig);
    lama.classList.add("lama-antics");

    /* Extra poses are clones of the proud image, shown only while posing. */
    const poses = {};
    function poseNode(name) {
      if (poses[name]) return poses[name];
      const node = template.cloneNode(false);
      node.setAttribute("class", "pose antic-pose");
      const url = base + POSES[name];
      if (isSvg) node.setAttribute("href", url); else node.setAttribute("src", url);
      node.setAttribute("alt", "");
      turn.appendChild(node);
      poses[name] = node;
      return node;
    }
    ["standing", "resting", "shadesUp"].forEach(poseNode);

    let current = null;
    function pose(name) {
      if (current) current.classList.remove("is-current");
      current = null;
      if (!name || name === "proud") {
        lama.classList.remove("is-posing");
        return;
      }
      current = poseNode(name);
      current.classList.add("is-current");
      lama.classList.add("is-posing");
    }

    /* Facing. The site's choice wins over curiosity about the pointer. */
    let siteFacing = null;
    let curious = null;
    let facing = "left";
    function applyFacing() {
      const side = siteFacing || curious || "left";
      if (side === facing) return;
      const from = facing === "right" ? -1 : 1;
      const to = side === "right" ? -1 : 1;
      facing = side;
      turn.style.transform = to < 0 ? "scaleX(-1)" : "";
      /* A little hop as it turns. */
      if (!reduced.matches) {
        turn.animate([
          { transform: `scaleX(${from})` },
          { transform: `translateY(-7%) scaleX(${from * 0.12})`, offset: 0.5 },
          { transform: `scaleX(${to})` },
        ], { duration: 320, easing: "ease-in-out" });
      }
      lama.classList.toggle("is-facing-right", side === "right");
    }
    function face(side) {
      siteFacing = side === "left" || side === "right" ? side : null;
      applyFacing();
    }

    function box() {
      return rig.getBoundingClientRect();
    }

    /* A point on the Lama in viewport coordinates. Fractions may go past
       0 and 1 for points beside it; they follow the way it faces. */
    function at(point, rect = box()) {
      const x = facing === "right" ? 1 - point[0] : point[0];
      return [rect.left + rect.width * x, rect.top + rect.height * point[1]];
    }

    /* Shapes thrown by this Lama, for freeze() and snapshot(). */
    const mine = new Set();
    function sprite(kind, size, color) {
      const bit = document.createElement("span");
      bit.className = `lama-antics-bit is-${kind}`;
      bit.style.cssText = `left:0;top:0;width:${size}px;height:${size}px;color:${color}`;
      bit.innerHTML = `<svg viewBox="0 0 12 12" fill="currentColor">${SHAPES[kind]}</svg>`;
      bitsLayer().appendChild(bit);
      mine.add(bit);
      return bit;
    }
    function drop(bit) {
      mine.delete(bit);
      bit.remove();
    }
    function placeAt(bit, x, y) {
      bit.style.left = `${x + window.scrollX}px`;
      bit.style.top = `${y + window.scrollY}px`;
    }

    /* A burst of small shapes from a point on the Lama. */
    function bits(kind, count, point, spec = {}) {
      if (reduced.matches) return;
      const rect = box();
      if (!rect.width) return;
      const unit = rect.width / 120;
      const [x, y] = Array.isArray(point) ? at(point, rect) : at(BODY, rect);
      const mirror = facing === "right" ? -1 : 1;
      for (let i = 0; i < count; i += 1) {
        const size = (spec.size || 7) * unit * rand(0.8, 1.25);
        const bit = sprite(kind, size, spec.color || pick(colors));
        placeAt(bit, x, y);
        const angle = spec.angle !== undefined
          ? spec.angle + rand(-spec.spread || 0, spec.spread || 0)
          : (i / count) * Math.PI * 2 + rand(-0.3, 0.3);
        const reach = (spec.reach || 40) * unit * rand(0.6, 1.2);
        const dx = Math.cos(angle) * reach * mirror;
        const dy = Math.sin(angle) * reach;
        const fall = (spec.fall || 0) * unit;
        const spin = spec.turn ? rand(-spec.turn, spec.turn) : 0;
        const duration = (spec.duration || 900) * rand(0.85, 1.2);
        const frames = spec.frames
          ? spec.frames(dx, dy, unit, i)
          : [
            { transform: "translate(-50%, -50%) scale(0.3)", opacity: 0 },
            { transform: `translate(calc(-50% + ${dx * 0.7}px), calc(-50% + ${dy * 0.7}px)) scale(1) rotate(${spin * 0.5}deg)`, opacity: 1, offset: 0.35 },
            { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy + fall}px)) scale(0.7) rotate(${spin}deg)`, opacity: 0 },
          ];
        bit.animate(frames, { duration, delay: (spec.stagger || 0) * i, easing: "cubic-bezier(.2,.7,.3,1)", fill: "backwards" })
          .finished.catch(() => {}).then(() => drop(bit));
      }
    }

    /* A single shape along a path of viewport points [x, y, scale?],
       evenly spaced in time. Resolves when it arrives; keep() leaves it in
       place for the next leg. */
    function fly(bit, points, duration, spec = {}) {
      const [x0, y0] = points[0];
      placeAt(bit, x0, y0);
      const frames = points.map(([x, y, scale = 1, spin = 0], index) => ({
        transform: `translate(calc(-50% + ${round(x - x0)}px), calc(-50% + ${round(y - y0)}px)) rotate(${round(spin)}deg) scale(${round(scale)})`,
        opacity: spec.fade && index === points.length - 1 ? 0 : 1,
      }));
      if (spec.appear) frames[0].opacity = 0;
      return bit.animate(frames, { duration, easing: spec.easing || "linear", fill: "forwards" }).finished.catch(() => {});
    }

    /* A shape leaves from wherever it is, up and away, and is gone. */
    function shoo(bit) {
      const rect = bit.getBoundingClientRect();
      const x = rect.left + rect.width / 2;
      const y = rect.top + rect.height / 2;
      bit.getAnimations().forEach((animation) => animation.cancel());
      bit.classList.remove("is-resting");
      const points = [];
      for (let i = 0; i <= 8; i += 1) points.push([x + i * 14 + Math.sin(i * 1.4) * 6, y - i * 16, 1, Math.sin(i) * 10]);
      fly(bit, points, 1400, { fade: true }).then(() => drop(bit));
    }

    /* Moves of the whole Lama. Percent translations are of the Lama's box;
       the origin sits between its front and back feet. */
    const MOVES = {
      hop: [[0, "none"], [0.18, "scale(1.03, .96)"], [0.45, "translateY(-9%) scale(.98, 1.03)"], [0.78, "scale(1.02, .98)"], [1, "none"], 560],
      bigHop: [[0, "none"], [0.15, "scale(1.08, .9)"], [0.45, "translateY(-26%) scale(.96, 1.05)"], [0.8, "scale(1.06, .93)"], [1, "none"], 820],
      doubleHop: [[0, "none"], [0.1, "scale(1.03, .96)"], [0.24, "translateY(-8%)"], [0.4, "scale(1.03, .96)"], [0.56, "translateY(-12%)"], [0.76, "scale(1.04, .95)"], [1, "none"], 980],
      backflip: [[0, "none"], [0.14, "scale(1.1, .86)"], [0.3, "translateY(-30%) rotate(70deg)"], [0.5, "translateY(-46%) rotate(180deg)"], [0.72, "translateY(-24%) rotate(300deg)"], [0.86, "translateY(0) rotate(360deg) scale(1.08, .9)"], [1, "rotate(360deg)"], 1150],
      shimmy: [[0, "none"], [0.12, "rotate(-6deg) translateX(-2%)"], [0.25, "rotate(6deg) translateX(2%)"], [0.38, "rotate(-6deg) translateX(-2%)"], [0.5, "rotate(6deg) translateX(2%)"], [0.62, "rotate(-5deg) translateX(-2%)"], [0.75, "rotate(5deg) translateX(2%)"], [0.88, "rotate(-2deg)"], [1, "none"], 1300],
      spin: [[0, "none"], [0.12, "translateY(-6%) scaleX(.2)"], [0.25, "translateY(-10%) scaleX(-1)"], [0.38, "translateY(-12%) scaleX(.2)"], [0.5, "translateY(-12%) scaleX(1)"], [0.62, "translateY(-10%) scaleX(-.2)"], [0.75, "translateY(-6%) scaleX(-1)"], [0.88, "scaleX(-.2)"], [1, "none"], 1100],
      boing: [[0, "none"], [0.18, "scale(1.18, .72)"], [0.26, "scale(1.2, .7)"], [0.5, "translateY(-55%) scale(.84, 1.22)"], [0.72, "scale(1.22, .78)"], [0.82, "scale(.92, 1.08)"], [0.9, "scale(1.04, .97)"], [1, "none"], 1400],
      lookBack: [[0, "none"], [0.08, "scaleX(-1)"], [0.88, "scaleX(-1)"], [1, "none"], 2000],
      stretch: [[0, "none"], [0.35, "scale(.97, 1.08)"], [0.6, "scale(.97, 1.08)"], [0.8, "scale(1.03, .97)"], [1, "none"], 1500],
      scoot: [[0, "none"], [0.2, "translateX(-14%) rotate(-4deg)"], [0.35, "translateX(-14%)"], [0.6, "translateX(10%) scaleX(-1) rotate(4deg)"], [0.75, "translateX(10%) scaleX(-1)"], [1, "none"], 1200],
      dizzy: [[0, "none"], [0.1, "rotate(-12deg)"], [0.22, "rotate(10deg) translateX(3%)"], [0.34, "rotate(-9deg) translateX(-3%)"], [0.48, "rotate(7deg)"], [0.62, "rotate(-5deg)"], [0.76, "rotate(3deg)"], [0.88, "rotate(-1deg)"], [1, "none"], 2200],
      cool: [[0, "none"], [0.3, "rotate(-7deg) scale(1.03)"], [0.75, "rotate(-7deg) scale(1.03)"], [1, "none"], 1200],
      dip: [[0, "none"], [0.3, "rotate(4deg) translateY(2%)"], [0.6, "rotate(-1deg)"], [1, "none"], 700],
      plop: [[0, "none"], [0.3, "translateY(-14%)"], [0.7, "scale(1.1, .9)"], [1, "none"], 520],
      bob: [[0, pose3()], [0.25, pose3({ y: 1.5, r: 3, sx: 1.02, sy: 0.97 })], [0.5, pose3()], [0.75, pose3({ y: 1.5, r: -3, sx: 1.02, sy: 0.97 })], [1, pose3()], 640],
      sneeze: [[0, pose3()], [0.42, pose3({ r: 8, sx: 0.98, sy: 1.04 })], [0.5, pose3({ r: 9, sx: 0.98, sy: 1.05 })], [0.58, pose3({ x: 5, r: -7, sx: 1.05, sy: 0.95 })], [0.7, pose3({ x: 4, r: 2 })], [0.84, pose3({ x: 1, r: -1 })], [1, pose3()], 1500],
      startle: [[0, pose3()], [0.12, pose3({ y: -16, r: 6, sx: 0.94, sy: 1.1 })], [0.3, pose3({ x: 6, y: -8, r: 3 })], [0.5, pose3({ x: 7, sx: 1.06, sy: 0.94 })], [0.7, pose3({ x: 5, r: -2 })], [1, pose3()], 1100],
      trip: [[0, pose3()], [0.1, pose3({ y: -10, r: -14, pivot: PIVOT.front })], [0.3, pose3({ x: 6, y: -12, r: 10, pivot: PIVOT.front })], [0.5, pose3({ x: 8, r: -4, sx: 1.08, sy: 0.92, pivot: PIVOT.front })], [0.62, pose3({ x: 7, r: 3, pivot: PIVOT.front })], [0.78, pose3({ x: 4, r: -2, pivot: PIVOT.front })], [1, pose3({ pivot: PIVOT.front })], 1300],
      zoomies: [
        [0, pose3()], [0.08, pose3({ x: -10, y: -4, r: -4 })], [0.14, pose3({ x: -16, sx: 1.04, sy: 0.96 })],
        [0.17, pose3({ x: -16, sx: -1 })], [0.27, pose3({ x: -2, y: -5, r: -4, sx: -1 })], [0.36, pose3({ x: 14, sx: -1.04, sy: 0.96 })],
        [0.39, pose3({ x: 14 })], [0.48, pose3({ x: 2, y: -5, r: -4 })], [0.57, pose3({ x: -12, sx: 1.04, sy: 0.96 })],
        [0.6, pose3({ x: -12, sx: -1 })], [0.7, pose3({ x: 0, y: -4, r: -3, sx: -1 })], [0.79, pose3({ x: 8, sx: -1.03, sy: 0.97 })],
        [0.82, pose3({ x: 8 })], [0.92, pose3({ x: 1, y: -2 })], [1, pose3()], 2400,
      ],
      moonwalk: [
        [0, pose3()], [0.12, pose3({ x: 4, y: 1, r: -2 })], [0.2, pose3({ x: 5, y: -1 })], [0.32, pose3({ x: 10, y: 1, r: -2 })], [0.4, pose3({ x: 11, y: -1 })],
        [0.52, pose3({ x: 16, y: 1, r: -2 })], [0.6, pose3({ x: 17, y: -1 })], [0.7, pose3({ x: 17, y: -6, r: 6, sx: 0.96, sy: 1.05 })], [0.78, pose3({ x: 17, sx: 1.04, sy: 0.96 })],
        [1, pose3()], 2600,
      ],
    };

    function animateRig(frames, duration, easing = "cubic-bezier(.3,.7,.4,1)", fill = "none") {
      if (reduced.matches) return Promise.resolve();
      releaseHold();
      const animation = rig.animate(frames, { duration, easing, fill });
      return animation.finished.catch(() => {});
    }

    function move(name, speed = 1) {
      const spec = MOVES[name];
      const duration = spec[spec.length - 1] / speed;
      const frames = spec.slice(0, -1).map(([offset, transform]) => ({ offset, transform }));
      return animateRig(frames, duration);
    }

    /* A held lean: the Lama moves into a transform and stays there until
       the next move or unlean(). */
    let held = null;
    function releaseHold() {
      if (held) held.cancel();
      held = null;
    }
    function lean(transform, ms = 260) {
      if (reduced.matches) return Promise.resolve();
      releaseHold();
      held = rig.animate([{ transform: "none" }, { transform }], { duration: ms, easing: "cubic-bezier(.3,.7,.4,1)", fill: "forwards" });
      return held.finished.catch(() => {});
    }
    function unlean(ms = 300) {
      if (!held) return Promise.resolve();
      const transform = getComputedStyle(rig).transform;
      releaseHold();
      return animateRig([{ transform }, { transform: "none" }], ms);
    }

    /* A jump, timed for the scene: the Lama waits lead ms, takes off and
       stays in the air for air ms, then lands. The height follows the time
       in the air unless given (a fraction of the Lama's height). Styles:
       hop, tuck, flip, frontflip, spin, kick, twist. With chain, it takes
       off from wherever the antic it interrupted left it, mid-air even. */
    function jump(spec = {}) {
      const chained = spec.chain && carry && carry !== "none";
      /* A chained jump leaves at once, from the height it was caught at. */
      let lifted = 0;
      if (chained) {
        const tall = isSvg ? rig.getBBox().height : box().height;
        lifted = clamp((-new DOMMatrix(carry).f / (tall || 1)) * 100, 0, 60);
      }
      const lead = chained ? 0 : Math.max(0, spec.lead || 0);
      const air = Math.max(240, (spec.air || 520) + (chained ? Math.max(0, spec.lead || 0) : 0));
      const land = spec.land || 260;
      const crouch = chained ? 0 : Math.min(lead, spec.crouch === undefined ? 200 : spec.crouch);
      const style = spec.style || "hop";
      const height = 100 * (spec.height || clamp(0.13 * Math.pow(air / 560, 1.6), 0.1, 0.42));
      const total = lead + air + land;
      const frames = [];
      const add = (time, values) => frames.push({ offset: time / total, transform: pose3(values) });
      const pivot = style === "flip" || style === "frontflip" || style === "spin" ? PIVOT.body : style === "kick" ? PIVOT.front : PIVOT.feet;
      add(0, { pivot });
      if (chained) frames[0].transform = carry;
      if (lead > crouch) add(lead - crouch, { pivot });
      if (crouch > 0) add(lead, { sx: 1.08, sy: 0.9, pivot });
      const steps = 14;
      for (let i = 1; i < steps; i += 1) {
        const u = i / steps;
        const rise = 1 - 2 * u;
        const values = {
          y: -(lifted * (1 - u) + height * 4 * u * (1 - u)),
          sx: 1 - 0.04 * Math.abs(rise),
          sy: 1 + 0.06 * Math.abs(rise),
          r: 9 * rise,
          pivot,
        };
        if (style === "tuck") {
          values.sx += 0.08 * Math.sin(Math.PI * u);
          values.sy -= 0.16 * Math.sin(Math.PI * u);
        } else if (style === "flip" || style === "frontflip") {
          const turned = u < 0.12 ? 0 : u > 0.88 ? 1 : (u - 0.12) / 0.76;
          values.r = (style === "flip" ? 360 : -360) * (turned * turned * (3 - 2 * turned));
        } else if (style === "spin") {
          values.sx = Math.cos(2 * Math.PI * u);
          values.r = 0;
        } else if (style === "kick") {
          values.r = -16 * Math.sin(Math.PI * u);
        } else if (style === "twist") {
          values.r = 12 * Math.sin(2 * Math.PI * u);
        }
        add(lead + air * u, values);
      }
      add(lead + air, { sx: 1.1, sy: 0.88, r: style === "flip" ? 360 : style === "frontflip" ? -360 : 0, pivot });
      add(lead + air + land * 0.5, { sx: 0.98, sy: 1.03, r: style === "flip" ? 360 : style === "frontflip" ? -360 : 0, pivot });
      add(total, { r: style === "flip" ? 360 : style === "frontflip" ? -360 : 0, pivot });
      return animateRig(frames, total, "linear");
    }

    /* A hurdle: the Lama rears its front legs over an obstacle passing
       under them, then kicks its back legs up as it passes those. Times are
       [start, end] in ms from now for each pair of legs. */
    function hurdle(spec) {
      const lift = spec.lift || 10;
      const ease = 140;
      const [f0, f1] = spec.front;
      const [b0, b1] = spec.back;
      const keys = [[0, { pivot: PIVOT.back }]];
      const push = (time, values) => {
        const last = keys[keys.length - 1][0];
        keys.push([Math.max(time, last + 1), values]);
      };
      push(Math.max(1, f0 - ease), { pivot: PIVOT.back });
      push(f0, { r: lift, y: -2, pivot: PIVOT.back });
      push(f1, { r: lift * 0.9, y: -2, pivot: PIVOT.back });
      const switchAt = Math.max(f1 + ease * 0.6, Math.min((f1 + b0) / 2, b0 - ease * 0.6));
      push(switchAt, { pivot: PIVOT.back });
      push(switchAt + 1, { pivot: PIVOT.front });
      push(b0, { r: -lift, y: -2, pivot: PIVOT.front });
      push(b1, { r: -lift * 0.8, y: -1, pivot: PIVOT.front });
      push(b1 + ease, { r: 2, pivot: PIVOT.front });
      push(b1 + ease * 2, { pivot: PIVOT.front });
      const end = keys[keys.length - 1][0];
      const frames = keys.map(([time, values]) => ({ offset: time / end, transform: pose3(values) }));
      return animateRig(frames, end, "ease-in-out");
    }

    function still() {
      releaseHold();
      rig.getAnimations().forEach((animation) => animation.cancel());
      pose(null);
    }

    /* Each antic receives this API. Calls become no-ops once a newer antic
       has interrupted it, so antics can simply await their steps. */
    let token = 0;
    let kind = null;
    let running = null;
    let carry = null;
    function api(id) {
      const live = () => id === token;
      const guard = (fn) => (...args) => (live() ? fn(...args) : Promise.resolve());
      return {
        live,
        box,
        at,
        HEAD, SHADES, MUZZLE, NOSE_TOP, BODY, FEET, FRONT_FOOT, BACK_FOOT,
        colors,
        facing: () => facing,
        reduced: () => reduced.matches,
        pose: (name) => { if (live()) pose(name); },
        face: (side) => { if (live()) face(side); },
        move: guard(move),
        jump: guard(jump),
        hurdle: guard(hurdle),
        lean: guard(lean),
        unlean: guard(unlean),
        bits: (...args) => { if (live()) bits(...args); },
        sprite: (kind, size, color) => sprite(kind, size, color || pick(colors)),
        fly,
        drop,
        wait: (ms) => sleep(reduced.matches ? Math.min(ms, 1600) : ms),
      };
    }

    /* Idle tricks: one every few seconds while the Lama is on screen. */
    const IDLE = {
      hop: (a) => a.move("hop"),
      doubleHop: (a) => a.move("doubleHop"),
      shimmy: async (a) => {
        a.bits("spark", 3, a.HEAD, { reach: 22, size: 6, duration: 700 });
        await a.move("shimmy");
      },
      lookBack: async (a) => {
        a.pose("standing");
        await a.move("lookBack");
        a.pose(null);
      },
      shadesPeek: async (a) => {
        a.pose("shadesUp");
        await a.move("cool");
        a.pose(null);
        a.bits("spark", 2, a.SHADES, { reach: 10, size: 9, duration: 600, color: "#FFF8EB" });
      },
      nap: async (a) => {
        a.pose("resting");
        await a.move("dip");
        for (let i = 0; i < 4 && a.live(); i += 1) {
          a.bits("bubble", 1, [0.2, 0.42], { angle: -Math.PI / 2 - 0.5, spread: 0.3, reach: 50, size: 6 + i * 2, duration: 1500, color: "#FFF8EB" });
          await a.wait(650);
        }
        a.pose("standing");
        await a.move("stretch");
        a.pose(null);
      },
      stretch: async (a) => {
        a.pose("standing");
        await a.move("stretch");
        a.pose(null);
      },
      nod: async (a) => {
        a.pose("hello");
        await a.move("dip");
        await a.move("dip");
        a.pose(null);
      },
      /* A head-bob to a tune only the Lama can hear. */
      groove: async (a) => {
        a.pose("hello");
        for (let i = 0; i < 5 && a.live(); i += 1) {
          a.bits("note", 1, [0.36, 0.06], { angle: -Math.PI / 2 + (i % 2 ? 0.6 : -0.6), spread: 0.2, reach: 46, size: 9, duration: 1500 });
          await a.move("bob");
        }
        a.pose(null);
      },
      /* Something tickles: a wind-up, a sneeze, a puff from the muzzle. */
      sneeze: async (a) => {
        a.pose("standing");
        const sneeze = a.move("sneeze");
        await a.wait(840);
        a.bits("puff", 7, a.MUZZLE, { angle: Math.PI, spread: 0.5, reach: 36, size: 6, duration: 700, color: "#FFF8EB" });
        await sneeze;
        a.pose(null);
      },
      /* A butterfly flutters in, circles the Lama's head and lands on its
         nose. The Lama peeks over its shades, the butterfly tickles, and
         the sneeze sends it off; the Lama turns to watch it go. */
      butterfly: async (a) => {
        const rect = a.box();
        if (!rect.width) return;
        const unit = rect.width / 120;
        /* Ivory like the Lama, so it shows on every ground, with a tint. */
        const bug = a.sprite("butterfly", 11 * unit, "#FFF8EB");
        bug.style.setProperty("--lama-antics-tint", colors[0]);
        const p = (point) => a.at(point, rect);
        const path = (points, wobble) => {
          const out = [];
          for (let i = 0; i < points.length - 1; i += 1) {
            const [x0, y0] = p(points[i]);
            const [x1, y1] = p(points[i + 1]);
            for (let s = 0; s < 6; s += 1) {
              const u = s / 6;
              const flutter = Math.sin((i * 6 + s) * 1.3) * wobble * unit;
              out.push([x0 + (x1 - x0) * u, y0 + (y1 - y0) * u + flutter, 1, flutter * 1.4]);
            }
          }
          out.push([...p(points[points.length - 1]), 1, 0]);
          return out;
        };
        let away = null;
        try {
          await fly(bug, path([[-1.3, -0.25], [-0.85, 0.05], [-0.45, -0.18], [0.0, -0.06], [0.35, -0.22], [0.55, -0.02], [0.25, 0.1], NOSE_TOP], 5), 4200, { appear: true });
          if (!a.live()) return;
          bug.classList.add("is-resting");
          a.pose("shadesUp");
          await a.wait(1500);
          if (!a.live()) return;
          a.pose("standing");
          const sneeze = a.move("sneeze");
          await a.wait(760);
          if (!a.live()) return;
          bug.classList.remove("is-resting");
          a.bits("puff", 6, a.MUZZLE, { angle: Math.PI, spread: 0.5, reach: 34, size: 6, duration: 700, color: "#FFF8EB" });
          away = fly(bug, path([NOSE_TOP, [0.1, -0.3], [0.6, -0.65], [1.3, -0.5], [2.2, -0.95]], 6), 2600, { fade: true });
          await sneeze;
          a.pose("standing");
          await a.move("lookBack");
          a.pose(null);
          await away;
        } finally {
          /* Interrupted, it flutters off instead of vanishing. */
          if (away || !bug.isConnected) drop(bug);
          else shoo(bug);
        }
      },
      zoomies: async (a) => {
        a.pose("standing");
        const run = a.move("zoomies");
        for (let i = 0; i < 4 && a.live(); i += 1) {
          await a.wait(i ? 560 : 300);
          a.bits("puff", 3, a.FEET, { angle: i % 2 ? 0 : Math.PI, spread: 0.4, reach: 26, size: 6, duration: 600, color: "#FFF8EB" });
        }
        await run;
        a.pose("hello");
        await a.move("dip");
        a.pose(null);
      },
      ...(options.idle || {}),
    };

    /* Tap gags: every tap plays the next one; a flurry of taps makes the
       Lama dizzy, and a long flurry brings the herd. */
    const TAPS = {
      backflip: async (a) => {
        const flip = a.move("backflip");
        await sleep(950);
        a.bits("confetti", 18, a.FEET, { angle: -Math.PI / 2, spread: 1.1, reach: 70, fall: 60, turn: 540, duration: 1400 });
        await flip;
      },
      boing: async (a) => {
        const jump = a.move("boing");
        await sleep(360);
        a.bits("line", 3, a.FEET, { angle: Math.PI / 2, spread: 0.4, reach: 24, size: 8, duration: 500, color: "#FFF8EB" });
        await jump;
      },
      spin: async (a) => {
        const spin = a.move("spin");
        a.bits("spark", 6, a.BODY, { reach: 60, size: 7 });
        await spin;
      },
      dealWithIt: async (a) => {
        a.pose("shadesUp");
        await a.wait(650);
        a.pose(null);
        a.bits("spark", 5, a.SHADES, { reach: 28, size: 9, duration: 800, color: "#FFF8EB" });
        await a.move("cool");
      },
      hearts: async (a) => {
        a.pose("hello");
        a.bits("heart", 6, a.HEAD, { angle: -Math.PI / 2, spread: 0.8, reach: 55, size: 9, duration: 1500, stagger: 90 });
        await a.move("dip");
        await a.move("dip");
        a.pose(null);
      },
      flop: async (a) => {
        await a.move("plop");
        a.pose("restingNod");
        a.bits("puff", 6, a.FEET, { angle: Math.PI, spread: Math.PI, reach: 30, size: 8, duration: 700, color: "#FFF8EB" });
        await a.wait(1500);
        a.pose(null);
        await a.move("bigHop");
      },
      scoot: async (a) => {
        a.bits("line", 3, [0.95, 0.6], { angle: 0, spread: 0.2, reach: 30, size: 10, duration: 450, color: "#FFF8EB" });
        await a.move("scoot");
      },
      frontflip: async (a) => {
        await a.jump({ lead: 220, air: 760, style: "frontflip", height: 0.4 });
        a.bits("star", 5, a.FEET, { angle: -Math.PI / 2, spread: 1.2, reach: 44, size: 8, duration: 900 });
      },
      moonwalk: async (a) => {
        a.pose("shadesUp");
        const glide = a.move("moonwalk");
        for (let i = 0; i < 3 && a.live(); i += 1) {
          await a.wait(i ? 520 : 260);
          a.bits("line", 2, a.FRONT_FOOT, { angle: Math.PI, spread: 0.15, reach: 22, size: 8, duration: 420, color: "#FFF8EB" });
        }
        await a.wait(400);
        a.pose(null);
        a.bits("spark", 4, a.SHADES, { reach: 26, size: 8, duration: 700, color: "#FFF8EB" });
        await glide;
      },
      ...(options.taps || {}),
    };
    exclude.forEach((name) => { delete IDLE[name]; delete TAPS[name]; });

    const nextIdle = bag(Object.keys(IDLE));
    const nextTap = bag(Object.keys(TAPS));

    /* token is odd while an antic runs and even when the Lama is idle. */
    const busy = () => (token % 2 === 1 ? kind : null);
    async function run(antic, as = "tap", name = null) {
      if (token % 2 === 0) token += 1; else token += 2;
      const id = token;
      kind = as;
      running = name;
      carry = getComputedStyle(rig).transform;
      still();
      try {
        await antic(api(id));
      } catch (_) {
        /* An antic that fails just ends. */
      }
      if (id === token) {
        releaseHold();
        pose(null);
        token += 1;
        kind = null;
        running = null;
      }
    }

    /* Idle loop. */
    let visible = true;
    let hovering = false;
    let idleTimer = 0;
    function scheduleIdle(delay = rand(6000, 11000)) {
      clearTimeout(idleTimer);
      idleTimer = setTimeout(() => {
        if (visible && !hovering && !document.hidden && !reduced.matches && !busy()) {
          const name = nextIdle();
          run(IDLE[name], "idle", name);
        }
        scheduleIdle();
      }, delay);
    }
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; }).observe(lama);
    }
    lama.addEventListener("pointerenter", () => { hovering = true; });
    lama.addEventListener("pointerleave", () => { hovering = false; });
    scheduleIdle(options.firstIdle || rand(4500, 7000));

    /* Taps. */
    let flurry = [];
    let herdAt = 0;
    function tap(event) {
      event.preventDefault();
      const now = performance.now();
      flurry = flurry.filter((time) => now - time < 2400).concat(now);
      if (reduced.matches) {
        /* No movement: each tap just changes the pose. */
        const cycle = ["shadesUp", "hello", "resting", "standing", null];
        const shown = Object.keys(poses).find((key) => poses[key] === current) || null;
        pose(cycle[(cycle.indexOf(shown) + 1) % cycle.length]);
        return;
      }
      if (flurry.length >= 10 && now - herdAt > 8000) {
        herdAt = now;
        flurry = [];
        run(herd, "tap", "herd");
      } else if (flurry.length === 5) {
        run(dizzy, "tap", "dizzy");
      } else if (running === "nap") {
        /* Woken from a nap. */
        run(startle, "tap", "startle");
      } else if (!busy() || flurry.length < 5) {
        const name = nextTap();
        run(TAPS[name], "tap", name);
      }
      scheduleIdle();
    }
    lama.addEventListener("click", tap);

    async function startle(a) {
      a.pose("standing");
      a.bits("bang", 3, [0.3, 0.02], { angle: -Math.PI / 2, spread: 0.7, reach: 18, size: 8, duration: 520, color: "#FFF8EB", frames: (dx, dy) => {
        const angle = Math.atan2(dy, dx) * 180 / Math.PI + 90;
        return [
          { transform: `translate(-50%, -50%) rotate(${angle}deg) scale(0.4)`, opacity: 0 },
          { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) rotate(${angle}deg) scale(1)`, opacity: 1, offset: 0.4 },
          { transform: `translate(calc(-50% + ${dx * 1.2}px), calc(-50% + ${dy * 1.2}px)) rotate(${angle}deg) scale(0.9)`, opacity: 0 },
        ];
      } });
      await a.move("startle");
      a.pose("hello");
      await a.move("dip");
    }

    async function dizzy(a) {
      a.pose("standing");
      const wobble = a.move("dizzy");
      const rect = a.box();
      const [cx, cy] = a.at([0.28, 0.06], rect);
      const unit = rect.width / 120;
      for (let i = 0; i < 3; i += 1) {
        const star = sprite("star", 9 * unit, colors[i % colors.length]);
        placeAt(star, cx, cy);
        const frames = [];
        for (let step = 0; step <= 24; step += 1) {
          const angle = (step / 24) * Math.PI * 4 + (i * Math.PI * 2) / 3;
          const x = Math.cos(angle) * 20 * unit;
          const y = Math.sin(angle) * 6 * unit;
          frames.push({ transform: `translate(calc(-50% + ${x}px), calc(-50% + ${y}px)) scale(${0.75 + 0.25 * Math.sin(angle)})`, opacity: step === 24 ? 0 : 1 });
        }
        star.animate(frames, { duration: 2200, easing: "linear" }).finished.catch(() => {}).then(() => drop(star));
      }
      await wobble;
      a.pose(null);
    }

    /* The herd: a line of small Lamas hops across the screen at the big
       one's feet, and it turns to watch them go. */
    async function herd(a) {
      a.pose("hello");
      const rect = a.box();
      const size = Math.max(28, rect.width * 0.32);
      const floor = rect.top + rect.height * FEET[1] - size * 0.92;
      const span = window.innerWidth + size * 2;
      const runs = [];
      for (let i = 0; i < 5; i += 1) {
        const mini = document.createElement("img");
        mini.className = "lama-antics-bit is-mini";
        mini.src = base + POSES.proud;
        mini.alt = "";
        mini.style.cssText = `width:${size}px;height:${size}px`;
        placeAt(mini, window.innerWidth + size, floor);
        bitsLayer().appendChild(mini);
        mine.add(mini);
        const frames = [];
        const hops = 9;
        for (let step = 0; step <= hops * 2; step += 1) {
          const up = step % 2 === 1;
          frames.push({ transform: `translate(${-(step / (hops * 2)) * span}px, ${up ? -size * 0.35 : 0}px)`, easing: up ? "ease-in" : "ease-out" });
        }
        runs.push(mini.animate(frames, { duration: 3600, delay: i * 260, easing: "linear", fill: "backwards" })
          .finished.catch(() => {}).then(() => drop(mini)));
      }
      await sleep(900);
      a.pose("standing");
      await a.move("lookBack");
      a.pose("hello");
      await a.move("doubleHop");
      a.bits("confetti", 14, a.HEAD, { angle: -Math.PI / 2, spread: 1, reach: 60, fall: 50, turn: 400, duration: 1300 });
      await Promise.all(runs);
    }

    /* Petting: stroking back and forth across the Lama with a mouse or pen
       earns hearts. */
    let strokes = [];
    let lastX = null;
    let lastDir = 0;
    let pettedAt = 0;
    async function petted(a) {
      a.pose("hello");
      a.bits("heart", 4, a.HEAD, { angle: -Math.PI / 2, spread: 0.7, reach: 44, size: 8, duration: 1300, stagger: 120 });
      await a.move("bob");
      await a.move("bob");
      a.pose(null);
    }
    lama.addEventListener("pointermove", (event) => {
      if (event.pointerType === "touch" || reduced.matches) return;
      if (lastX !== null) {
        const dx = event.clientX - lastX;
        if (Math.abs(dx) > 3) {
          const dir = Math.sign(dx);
          const now = performance.now();
          if (lastDir && dir !== lastDir) strokes = strokes.filter((time) => now - time < 1500).concat(now);
          lastDir = dir;
          if (strokes.length >= 4 && now - pettedAt > 3500 && (!busy() || busy() === "idle")) {
            pettedAt = now;
            strokes = [];
            run(petted, "idle", "petted");
          }
        }
      }
      lastX = event.clientX;
    });
    lama.addEventListener("pointerleave", () => { lastX = null; lastDir = 0; });

    /* Curiosity: a pointer that lingers behind the Lama makes it turn
       around to look; it turns back when the pointer moves on. */
    if (options.watch !== false && matchMedia("(hover: hover)").matches) {
      let since = 0;
      let leftAt = 0;
      let queued = false;
      let pointer = null;
      const check = () => {
        queued = false;
        if (!pointer || reduced.matches) return;
        const rect = box();
        const now = performance.now();
        const near = pointer.y > rect.top - rect.height && pointer.y < rect.bottom + rect.height * 0.6;
        const behind = near && pointer.x > rect.left + rect.width * 0.95 && pointer.x < rect.right + rect.width * 2.5;
        const ahead = pointer.x < rect.left + rect.width * 0.45 || !near;
        if (behind) {
          if (!since) since = now;
          leftAt = 0;
          if (now - since > 650 && curious !== "right") { curious = "right"; applyFacing(); }
        } else {
          since = 0;
          if (ahead && curious) {
            if (!leftAt) leftAt = now;
            if (now - leftAt > 300) { curious = null; applyFacing(); }
          }
        }
        if ((since && curious !== "right") || (leftAt && curious)) setTimeout(() => { if (!queued) { queued = true; requestAnimationFrame(check); } }, 120);
      };
      document.addEventListener("pointermove", (event) => {
        if (event.pointerType !== "mouse") return;
        pointer = { x: event.clientX, y: event.clientY };
        if (!queued) { queued = true; requestAnimationFrame(check); }
      }, { passive: true });
      document.documentElement.addEventListener("pointerleave", () => {
        pointer = null;
        since = 0;
        setTimeout(() => { if (!pointer && curious) { curious = null; applyFacing(); } }, 900);
      });
    }

    /* Freeze: everything about this Lama, and the shapes it threw, holds
       still for a moment, then carries on. */
    function freeze(ms = 400) {
      const animations = [
        ...lama.getAnimations({ subtree: true }),
        ...[...mine].flatMap((bit) => bit.getAnimations({ subtree: true })),
      ].filter((animation) => animation.playState === "running");
      animations.forEach((animation) => animation.pause());
      return sleep(ms).then(() => animations.forEach((animation) => {
        if (animation.playState === "paused") animation.play();
      }));
    }

    /* Snapshot: copy the current frame onto a clone of the Lama element
       (made with cloneNode(true) after attach), and return clones of the
       shapes in flight, positioned relative to origin (a viewport rect). */
    function snapshot(copy, origin) {
      if (copy) {
        const source = [lama, ...lama.querySelectorAll("*")];
        const target = [copy, ...copy.querySelectorAll("*")];
        if (source.length === target.length) {
          source.forEach((node, index) => {
            const style = getComputedStyle(node);
            const out = target[index].style;
            out.setProperty("transform", style.transform, "important");
            out.setProperty("opacity", style.opacity, "important");
            out.setProperty("animation", "none", "important");
            out.setProperty("transition", "none", "important");
          });
        }
      }
      const shapes = [];
      if (!origin) return shapes;
      for (const bit of mine) {
        const rect = bit.getBoundingClientRect();
        if (rect.right < origin.left || rect.left > origin.right || rect.bottom < origin.top || rect.top > origin.bottom) continue;
        const style = getComputedStyle(bit);
        const clone = bit.cloneNode(true);
        clone.style.left = `${parseFloat(bit.style.left) - window.scrollX - origin.left}px`;
        clone.style.top = `${parseFloat(bit.style.top) - window.scrollY - origin.top}px`;
        clone.style.transform = style.transform;
        clone.style.opacity = style.opacity;
        clone.style.animation = "none";
        shapes.push(clone);
      }
      return shapes;
    }

    /* Hold the idle loop while the Lama is away. */
    document.addEventListener("visibilitychange", () => { if (document.hidden) still(); });

    const named = (name) => IDLE[name] || TAPS[name] || { dizzy, herd, startle }[name] || null;
    const controller = {
      /* Plays a named antic, or a site antic (api) => ..., interrupting
         whatever runs. */
      play: (antic, as = "tap") => (typeof antic === "function"
        ? run(antic, as)
        : run(named(antic) || (() => {}), as, antic)),
      /* A scene reaction: the same, but marked so the scene can tell its
         own reactions apart in busy(). */
      react: (antic, name = null) => run(antic, "react", name),
      /* null, or "idle", "tap" or "react" while an antic runs. */
      busy,
      running: () => (busy() ? running : null),
      pose,
      face,
      facing: () => facing,
      freeze,
      snapshot,
      box,
      at,
    };
    lama.lamaAntics = controller;
    return controller;
  }

  window.LamaAntics = { attach };
})();

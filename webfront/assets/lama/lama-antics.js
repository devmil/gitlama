/* Lama antics: idle tricks and tap gags for the hero Lama on Devmil app
   websites. Vendored unchanged by each site from the brand repository
   (assets/web); pair it with lama-antics.css.

   The character rules hold (guidelines/character.md): the Lama never speaks
   and is never redrawn. Antics move the whole Lama, swap between the
   constructed poses and their shades-up variants, and scatter small shapes
   around it. Everything here is decoration: the hero must read the same
   without it.

     const antics = LamaAntics.attach(lamaElement, {
       base: "assets/lama/",        // folder holding the pose SVGs
       colors: ["#4C82FB", ...],    // confetti and hearts
       idle: { name: (api) => ... },// optional site antics
       taps: { name: (api) => ... },
     });

   lamaElement holds the existing pose images (class "pose", one also
   "proud"). It may be an HTML element or an SVG group. The site keeps its
   own hop and hello classes on that element; the antics animate an inner
   rig that wraps the poses, so both compose. */
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
  /* Points on the 120-unit artwork (proud pose, facing left), as fractions. */
  const HEAD = [0.27, 0.2];
  const SHADES = [0.26, 0.25];
  const BODY = [0.6, 0.55];
  const FEET = [0.55, 0.92];

  const SHAPES = {
    confetti: '<rect x="2" y="5" width="8" height="4" rx="1"/>',
    heart: '<path d="M6 10.6 1.7 6.4A2.7 2.7 0 0 1 6 3a2.7 2.7 0 0 1 4.3 3.4Z"/>',
    spark: '<path d="M6 0Q6.8 5.2 12 6 6.8 6.8 6 12 5.2 6.8 0 6 5.2 5.2 6 0Z"/>',
    star: '<path d="M6 .5l1.6 3.6 3.9.4-2.9 2.6.8 3.9L6 9 2.6 11l.8-3.9L.5 4.5l3.9-.4Z"/>',
    puff: '<circle cx="6" cy="6" r="5"/>',
    bubble: '<circle cx="6" cy="6" r="4.2" fill="none" stroke="currentColor" stroke-width="1.4"/>',
    line: '<rect x="0" y="5" width="12" height="2" rx="1"/>',
  };

  const rand = (low, high) => low + Math.random() * (high - low);
  const pick = (list) => list[Math.floor(Math.random() * list.length)];
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

  let layer = null;
  function bitsLayer() {
    if (!layer || !layer.isConnected) {
      layer = document.createElement("div");
      layer.className = "lama-antics-layer";
      layer.setAttribute("aria-hidden", "true");
      document.body.appendChild(layer);
    }
    return layer;
  }

  function attach(lama, options = {}) {
    if (!lama || lama.lamaAntics) return lama && lama.lamaAntics;
    const base = options.base || "assets/lama/";
    const colors = options.colors && options.colors.length ? options.colors : ["#FFF8EB"];
    const reduced = matchMedia("(prefers-reduced-motion: reduce)");
    const isSvg = lama instanceof SVGElement;
    const template = lama.querySelector(".pose.proud") || lama.querySelector(".pose");
    if (!template) return null;

    /* The rig: wraps the existing poses so antics compose with the site's
       own hop on the outer element. */
    const rig = isSvg ? document.createElementNS(SVG, "g") : document.createElement("div");
    rig.setAttribute("class", "lama-antics-rig");
    while (lama.firstChild) rig.appendChild(lama.firstChild);
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
      rig.appendChild(node);
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

    function box() {
      return rig.getBoundingClientRect();
    }

    function at(point, rect = box()) {
      return [rect.left + rect.width * point[0], rect.top + rect.height * point[1]];
    }

    /* A burst of small shapes from a point on the Lama, in viewport
       coordinates on a fixed layer, so nothing clips them and nothing
       scrolls because of them. */
    function bits(kind, count, point, spec = {}) {
      if (reduced.matches) return;
      const rect = box();
      if (!rect.width) return;
      const unit = rect.width / 120;
      const [x, y] = Array.isArray(point) ? at(point, rect) : at(BODY, rect);
      const host = bitsLayer();
      for (let i = 0; i < count; i += 1) {
        const bit = document.createElement("span");
        bit.className = `lama-antics-bit is-${kind}`;
        const size = (spec.size || 7) * unit * rand(0.8, 1.25);
        const color = spec.color || pick(colors);
        bit.style.cssText = `left:${x}px;top:${y}px;width:${size}px;height:${size}px;color:${color}`;
        bit.innerHTML = `<svg viewBox="0 0 12 12" fill="currentColor">${SHAPES[kind]}</svg>`;
        host.appendChild(bit);
        const angle = spec.angle !== undefined
          ? spec.angle + rand(-spec.spread || 0, spec.spread || 0)
          : (i / count) * Math.PI * 2 + rand(-0.3, 0.3);
        const reach = (spec.reach || 40) * unit * rand(0.6, 1.2);
        const dx = Math.cos(angle) * reach;
        const dy = Math.sin(angle) * reach;
        const fall = (spec.fall || 0) * unit;
        const turn = spec.turn ? rand(-spec.turn, spec.turn) : 0;
        const duration = (spec.duration || 900) * rand(0.85, 1.2);
        const frames = spec.frames
          ? spec.frames(dx, dy, unit, i)
          : [
            { transform: "translate(-50%, -50%) scale(0.3)", opacity: 0 },
            { transform: `translate(calc(-50% + ${dx * 0.7}px), calc(-50% + ${dy * 0.7}px)) scale(1) rotate(${turn * 0.5}deg)`, opacity: 1, offset: 0.35 },
            { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy + fall}px)) scale(0.7) rotate(${turn}deg)`, opacity: 0 },
          ];
        bit.animate(frames, { duration, delay: (spec.stagger || 0) * i, easing: "cubic-bezier(.2,.7,.3,1)", fill: "backwards" })
          .finished.catch(() => {}).then(() => bit.remove());
      }
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
    };

    function move(name, speed = 1) {
      if (reduced.matches) return Promise.resolve();
      const spec = MOVES[name];
      const duration = spec[spec.length - 1] / speed;
      const frames = spec.slice(0, -1).map(([offset, transform]) => ({ offset, transform }));
      const animation = rig.animate(frames, { duration, easing: "cubic-bezier(.3,.7,.4,1)" });
      return animation.finished.catch(() => {});
    }

    function still() {
      rig.getAnimations().forEach((animation) => animation.cancel());
      pose(null);
    }

    /* Each antic receives this API. Calls become no-ops once a newer antic
       has interrupted it, so antics can simply await their steps. */
    let token = 0;
    function api(id) {
      const live = () => id === token;
      return {
        live,
        box,
        at,
        HEAD, SHADES, BODY, FEET,
        colors,
        reduced: () => reduced.matches,
        pose: (name) => { if (live()) pose(name); },
        move: (name, speed) => (live() ? move(name, speed) : Promise.resolve()),
        bits: (...args) => { if (live()) bits(...args); },
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
      ...(options.taps || {}),
    };

    const nextIdle = bag(Object.keys(IDLE));
    const nextTap = bag(Object.keys(TAPS));

    /* token is odd while an antic runs and even when the Lama is idle. */
    const busy = () => token % 2 === 1;
    async function run(antic) {
      if (token % 2 === 0) token += 1; else token += 2;
      const id = token;
      still();
      try {
        await antic(api(id));
      } catch (_) {
        /* An antic that fails just ends. */
      }
      if (id === token) {
        pose(null);
        token += 1;
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
          run(IDLE[nextIdle()]);
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
        run(herd);
      } else if (flurry.length === 5) {
        run(dizzy);
      } else if (!busy() || flurry.length < 5) {
        run(TAPS[nextTap()]);
      }
      scheduleIdle();
    }
    lama.addEventListener("click", tap);

    async function dizzy(a) {
      a.pose("standing");
      const wobble = a.move("dizzy");
      const rect = a.box();
      const [cx, cy] = a.at([0.28, 0.06], rect);
      const unit = rect.width / 120;
      const host = bitsLayer();
      for (let i = 0; i < 3; i += 1) {
        const star = document.createElement("span");
        star.className = "lama-antics-bit is-star";
        const size = 9 * unit;
        star.style.cssText = `left:${cx}px;top:${cy}px;width:${size}px;height:${size}px;color:${colors[i % colors.length]}`;
        star.innerHTML = `<svg viewBox="0 0 12 12" fill="currentColor">${SHAPES.star}</svg>`;
        host.appendChild(star);
        const frames = [];
        for (let step = 0; step <= 24; step += 1) {
          const angle = (step / 24) * Math.PI * 4 + (i * Math.PI * 2) / 3;
          const x = Math.cos(angle) * 20 * unit;
          const y = Math.sin(angle) * 6 * unit;
          frames.push({ transform: `translate(calc(-50% + ${x}px), calc(-50% + ${y}px)) scale(${0.75 + 0.25 * Math.sin(angle)})`, opacity: step === 24 ? 0 : 1 });
        }
        star.animate(frames, { duration: 2200, easing: "linear" }).finished.catch(() => {}).then(() => star.remove());
      }
      await wobble;
      a.pose(null);
    }

    /* The herd: a line of small Lamas hops across the screen at the big
       one's feet, and it turns to watch them go. */
    async function herd(a) {
      a.pose("hello");
      const rect = a.box();
      const host = bitsLayer();
      const size = Math.max(28, rect.width * 0.32);
      const floor = rect.top + rect.height * FEET[1] - size * 0.92;
      const span = window.innerWidth + size * 2;
      const runs = [];
      for (let i = 0; i < 5; i += 1) {
        const mini = document.createElement("img");
        mini.className = "lama-antics-bit is-mini";
        mini.src = base + POSES.proud;
        mini.alt = "";
        mini.style.cssText = `left:${window.innerWidth + size}px;top:${floor}px;width:${size}px;height:${size}px`;
        host.appendChild(mini);
        const frames = [];
        const hops = 9;
        for (let step = 0; step <= hops * 2; step += 1) {
          const up = step % 2 === 1;
          frames.push({ transform: `translate(${-(step / (hops * 2)) * span}px, ${up ? -size * 0.35 : 0}px)`, easing: up ? "ease-in" : "ease-out" });
        }
        runs.push(mini.animate(frames, { duration: 3600, delay: i * 260, easing: "linear", fill: "backwards" })
          .finished.catch(() => {}).then(() => mini.remove()));
      }
      await sleep(900);
      a.pose("standing");
      await a.move("lookBack");
      a.pose("hello");
      await a.move("doubleHop");
      a.bits("confetti", 14, a.HEAD, { angle: -Math.PI / 2, spread: 1, reach: 60, fall: 50, turn: 400, duration: 1300 });
      await Promise.all(runs);
    }

    /* Hold the idle loop while the Lama is away. */
    document.addEventListener("visibilitychange", () => { if (document.hidden) still(); });

    const controller = {
      play: (name) => run(IDLE[name] || TAPS[name] || (name === "dizzy" ? dizzy : name === "herd" ? herd : null) || (() => {})),
      pose,
    };
    lama.lamaAntics = controller;
    return controller;
  }

  window.LamaAntics = { attach };
})();

/* ============================================================
   surface-scene.jsx — 3D viewport mock with animated agents.
   Canvas-based particle field. Glow, motion vectors, attractors.
   ============================================================ */

function SurfaceScene({ projection, onSelect, selected }) {
  const canvasRef = React.useRef(null);
  const stateRef = React.useRef(null);

  // Build initial state once
  React.useEffect(() => {
    const state = {
      agents: [],
      swarms: [
        { id: "drum",   voice: 1, cx: 0.30, cy: 0.45, r: 0.10, members: 22, cohere: 0.6 },
        { id: "pad",    voice: 2, cx: 0.62, cy: 0.55, r: 0.13, members: 18, cohere: 0.45 },
        { id: "sparks", voice: 3, cx: 0.78, cy: 0.30, r: 0.07, members: 14, cohere: 0.8 },
      ],
      attractors: [
        { cx: 0.45, cy: 0.75, r: 0.10, label: "vol·A" },
      ],
      time: 0,
    };
    // seed agents per swarm
    state.swarms.forEach((s) => {
      for (let i = 0; i < s.members; i++) {
        const a = Math.random() * Math.PI * 2;
        const rr = Math.sqrt(Math.random()) * s.r;
        state.agents.push({
          swarm: s.id, voice: s.voice,
          x: s.cx + Math.cos(a) * rr,
          y: s.cy + Math.sin(a) * rr,
          vx: (Math.random() - 0.5) * 0.0006,
          vy: (Math.random() - 0.5) * 0.0006,
          size: 1 + Math.random() * 2.4,
          glow: 6 + Math.random() * 10,
          phase: Math.random() * Math.PI * 2,
        });
      }
    });
    stateRef.current = state;
  }, []);

  // Animation loop
  React.useEffect(() => {
    let raf;
    const cv = canvasRef.current;
    if (!cv) return;
    const ctx = cv.getContext("2d");

    const resize = () => {
      const dpr = window.devicePixelRatio || 1;
      const r = cv.getBoundingClientRect();
      cv.width = r.width * dpr;
      cv.height = r.height * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(cv);

    const tick = () => {
      const r = cv.getBoundingClientRect();
      const W = r.width, H = r.height;
      const state = stateRef.current;
      if (!state) { raf = requestAnimationFrame(tick); return; }
      state.time += 1 / 60;

      // trail effect
      ctx.fillStyle = "rgba(6, 8, 10, 0.22)";
      ctx.fillRect(0, 0, W, H);

      // grid
      ctx.save();
      const cell = 32;
      ctx.strokeStyle = "rgba(255,255,255,0.025)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (let x = 0; x < W; x += cell) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
      for (let y = 0; y < H; y += cell) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
      ctx.stroke();
      ctx.restore();

      // attractors
      state.attractors.forEach((a) => {
        const cx = a.cx * W, cy = a.cy * H;
        ctx.strokeStyle = "rgba(255,255,255,0.18)";
        ctx.setLineDash([3, 4]);
        for (let k = 0; k < 3; k++) {
          ctx.beginPath();
          ctx.arc(cx, cy, a.r * W * (0.4 + k * 0.3), 0, Math.PI * 2);
          ctx.stroke();
        }
        ctx.setLineDash([]);
        ctx.fillStyle = "#f2f4f6";
        ctx.beginPath();
        ctx.arc(cx, cy, 3, 0, Math.PI * 2);
        ctx.fill();
        ctx.font = "10px 'JetBrains Mono', monospace";
        ctx.fillStyle = "rgba(242, 244, 246, 0.7)";
        ctx.fillText(a.label, cx + 8, cy - 8);
      });

      // agents: integrate light flocking toward swarm center
      const swarmsById = Object.fromEntries(state.swarms.map((s) => [s.id, s]));
      state.agents.forEach((ag) => {
        const s = swarmsById[ag.swarm];
        const dx = s.cx - ag.x, dy = s.cy - ag.y;
        ag.vx += dx * 0.00005 * s.cohere;
        ag.vy += dy * 0.00005 * s.cohere;
        ag.vx *= 0.98;
        ag.vy *= 0.98;
        // slight wander
        ag.vx += (Math.random() - 0.5) * 0.00012;
        ag.vy += (Math.random() - 0.5) * 0.00012;
        ag.x += ag.vx;
        ag.y += ag.vy;
        ag.phase += 0.04;
      });

      // draw agents with bloom
      state.agents.forEach((ag) => {
        const c = voice(ag.voice);
        const x = ag.x * W, y = ag.y * H;
        const a = 0.7 + 0.3 * Math.sin(ag.phase);
        // halo
        const grad = ctx.createRadialGradient(x, y, 0, x, y, ag.glow);
        grad.addColorStop(0, c.hex + "cc");
        grad.addColorStop(0.4, c.hex + "55");
        grad.addColorStop(1, c.hex + "00");
        ctx.fillStyle = grad;
        ctx.globalAlpha = a;
        ctx.beginPath();
        ctx.arc(x, y, ag.glow, 0, Math.PI * 2);
        ctx.fill();
        // core
        ctx.globalAlpha = 1;
        ctx.fillStyle = "#ffffff";
        ctx.beginPath();
        ctx.arc(x, y, ag.size * 0.7, 0, Math.PI * 2);
        ctx.fill();
      });
      ctx.globalAlpha = 1;

      // swarm labels
      state.swarms.forEach((s) => {
        const c = voice(s.voice);
        ctx.font = "10px 'JetBrains Mono', monospace";
        ctx.fillStyle = c.hex;
        ctx.shadowColor = c.soft; ctx.shadowBlur = 6;
        ctx.fillText(s.id.toUpperCase(), s.cx * W - 14, s.cy * H - s.r * W - 4);
        ctx.shadowBlur = 0;
      });

      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => { cancelAnimationFrame(raf); ro.disconnect(); };
  }, []);

  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: 12, gap: 8, minHeight: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--fg-2)" }}>scene · 3d viewport</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>054 obj · 3 swarms · 1 attractor</span>
        <div style={{ flex: 1 }} />
        <Capsule kind="live">render · 60.0 fps</Capsule>
        <Capsule>orbit · pan · zoom</Capsule>
      </div>

      <div style={{
        flex: 1, minHeight: 0, position: "relative",
        background: "var(--void)", border: "1px solid var(--line-1)", borderRadius: 4,
        overflow: "hidden",
      }}>
        <canvas ref={canvasRef} style={{ width: "100%", height: "100%", display: "block" }} />

        {/* axes hint */}
        <div style={{ position: "absolute", left: 12, bottom: 12, fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)", display: "flex", flexDirection: "column", gap: 2 }}>
          <span>x  +0.000</span>
          <span>y  +0.000</span>
          <span>z  +0.000</span>
        </div>

        {/* projection overlay corner mark */}
        {projection && (
          <div style={{ position: "absolute", right: 12, top: 12, display: "flex", alignItems: "center", gap: 6, fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--voice-1)" }}>
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--voice-1)", boxShadow: "0 0 8px var(--voice-1-soft)" }} />
            projecting · 1920×1080
          </div>
        )}

        {/* protection gradient bottom */}
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 60, background: "linear-gradient(to top, rgba(6,8,10,0.7), transparent)", pointerEvents: "none" }} />
      </div>

      {/* selector strip */}
      <div style={{ display: "flex", gap: 6 }}>
        {[
          { name: "drum",   voice: 1, kind: "swarm · 22 agents", status: "live",
            position: [0.30, 0.45, 0.0],
            props: [
              { k: "cohesion",  v: "0.600", voice: 1 },
              { k: "alignment", v: "0.420", voice: 1 },
              { k: "separation",v: "0.180" },
            ],
            subscriptions: [{ name: "domain · drum", voice: 1, weight: 1.0 }],
          },
          { name: "pad",    voice: 2, kind: "swarm · 18 agents",
            position: [0.62, 0.55, 0.0],
            props: [
              { k: "cohesion",  v: "0.450", voice: 2 },
              { k: "target",    v: "vol·A" },
            ],
            subscriptions: [{ name: "domain · pad", voice: 2, weight: 0.7 }, { name: "domain · drum", voice: 1, weight: 0.3 }],
          },
          { name: "sparks", voice: 3, kind: "swarm · 14 agents",
            position: [0.78, 0.30, 0.0],
            props: [
              { k: "cohesion",  v: "0.800", voice: 3 },
              { k: "vel·mean",  v: "0.024" },
            ],
            subscriptions: [{ name: "event · onset", voice: 3, weight: 1.0 }],
          },
        ].map((s) => (
          <button
            key={s.name}
            onClick={() => onSelect(s)}
            style={{
              display: "flex", alignItems: "center", gap: 6,
              padding: "6px 10px", height: 28,
              background: selected && selected.name === s.name ? "var(--bg-2)" : "var(--bg-1)",
              border: selected && selected.name === s.name ? "1px solid var(--line-hot)" : "1px solid var(--line-1)",
              borderRadius: 2, cursor: "pointer",
              boxShadow: selected && selected.name === s.name ? "0 0 12px var(--voice-1-soft)" : "none",
              color: "var(--fg-1)",
            }}
          >
            <VoiceDot v={s.voice} size={6} />
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 11 }}>{s.name}</span>
          </button>
        ))}
        <div style={{ flex: 1 }} />
        <Button variant="ghost" style={{ height: 28 }}>+ add agent</Button>
        <Button variant="ghost" style={{ height: 28 }}>+ attractor</Button>
        <Button variant="ghost" style={{ height: 28 }}>+ volume</Button>
      </div>
    </div>
  );
}

window.SurfaceScene = SurfaceScene;

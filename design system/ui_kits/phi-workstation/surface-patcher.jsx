/* ============================================================
   surface-patcher.jsx — node-and-cable DSP graph
   ============================================================ */

function SurfacePatcher() {
  const [nodes] = React.useState([
    { id: "osc",     x: 60,  y: 70,  w: 130, title: "osc · saw",       voice: 1, body: [["freq", "220 hz"], ["det", "0.02"], ["mix", "0.6"]], outs: [{ y: 38, v: 1 }, { y: 64, v: 3 }] },
    { id: "noise",   x: 60,  y: 250, w: 130, title: "noise",            voice: 3, body: [["color", "pink"], ["amp",  "−24 dB"]], outs: [{ y: 38, v: 3 }] },
    { id: "filter",  x: 280, y: 140, w: 150, title: "filter · lp",      voice: 1, armed: true, body: [["cutoff", "1.24 kHz", 1], ["q", "0.62"], ["← cohesion", "swarm.drum", 1]], ins: [{ y: 38, v: 1 }, { y: 64, v: 3 }], outs: [{ y: 38, v: 1 }] },
    { id: "delay",   x: 480, y: 80,  w: 140, title: "delay · stereo",   voice: 2, body: [["time", "3/16"], ["fb", "0.52"], ["dom", "drum", 2]], ins: [{ y: 38, v: 1 }], outs: [{ y: 38, v: 2 }] },
    { id: "reverb",  x: 480, y: 240, w: 140, title: "reverb · hall",    voice: 5, body: [["size", "0.84"], ["mix", "0.32"]], ins: [{ y: 38, v: 1 }], outs: [{ y: 38, v: 5 }] },
    { id: "out",     x: 680, y: 160, w: 100, title: "out · L/R",        voice: 2, body: [["gain", "−6.2 dB"]], ins: [{ y: 38, v: 2 }, { y: 64, v: 5 }] },
  ]);

  const cables = [
    { from: { node: "osc",    out: 0 }, to: { node: "filter", in: 0 }, v: 1, rate: "audio" },
    { from: { node: "osc",    out: 1 }, to: { node: "filter", in: 1 }, v: 3, rate: "audio" },
    { from: { node: "noise",  out: 0 }, to: { node: "filter", in: 1 }, v: 3, rate: "audio" },
    { from: { node: "filter", out: 0 }, to: { node: "delay",  in: 0 }, v: 1, rate: "audio" },
    { from: { node: "filter", out: 0 }, to: { node: "reverb", in: 0 }, v: 1, rate: "audio" },
    { from: { node: "delay",  out: 0 }, to: { node: "out",    in: 0 }, v: 2, rate: "audio" },
    { from: { node: "reverb", out: 0 }, to: { node: "out",    in: 1 }, v: 5, rate: "audio" },
  ];

  const nodeById = Object.fromEntries(nodes.map((n) => [n.id, n]));
  const portPos = (node, side, idx) => {
    const port = (side === "out" ? node.outs : node.ins)[idx];
    return {
      x: node.x + (side === "out" ? node.w : 0),
      y: node.y + (port ? port.y : 38),
    };
  };

  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: 12, gap: 8, minHeight: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--fg-2)" }}>patcher · drum bus</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>6 nodes · 7 cables</span>
        <div style={{ flex: 1 }} />
        <Capsule>audio · 48k</Capsule>
        <Capsule kind="hold">control · 1k</Capsule>
      </div>

      <div style={{
        flex: 1, minHeight: 0, position: "relative",
        background: "var(--bg-0)", border: "1px solid var(--line-1)", borderRadius: 4,
        overflow: "auto",
        backgroundImage: "radial-gradient(circle at 1px 1px, var(--grid-color) 1px, transparent 0)",
        backgroundSize: "16px 16px",
      }}>
        {/* SVG for cables */}
        <svg style={{ position: "absolute", inset: 0, width: 880, height: 480, pointerEvents: "none" }}>
          <defs>
            <filter id="cable-glow" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation="2" />
            </filter>
          </defs>
          {cables.map((c, i) => {
            const a = portPos(nodeById[c.from.node], "out", c.from.out);
            const b = portPos(nodeById[c.to.node],   "in",  c.to.in);
            const cx1 = a.x + 60, cy1 = a.y;
            const cx2 = b.x - 60, cy2 = b.y;
            const path = `M ${a.x} ${a.y} C ${cx1} ${cy1}, ${cx2} ${cy2}, ${b.x} ${b.y}`;
            const v = voice(c.v);
            return (
              <g key={i}>
                <path d={path} fill="none" stroke={v.hex} strokeOpacity="0.5" strokeWidth="2" filter="url(#cable-glow)" />
                <path d={path} fill="none" stroke={v.hex} strokeWidth="1.2" strokeDasharray={c.rate === "control" ? "4 3" : ""} />
              </g>
            );
          })}
        </svg>

        {/* Nodes */}
        {nodes.map((n) => <PatcherNode key={n.id} n={n} />)}
      </div>
    </div>
  );
}

function PatcherNode({ n }) {
  const c = voice(n.voice);
  return (
    <div style={{
      position: "absolute", left: n.x, top: n.y, width: n.w,
      background: "var(--bg-1)",
      border: n.armed ? `1px solid ${c.hex}aa` : "1px solid var(--line-1)",
      borderRadius: 4,
      boxShadow: n.armed ? `0 0 16px ${c.soft}` : "var(--elev-1)",
    }}>
      <div style={{
        height: 22, padding: "0 8px",
        display: "flex", alignItems: "center",
        background: "var(--bg-2)", borderBottom: "1px solid var(--line-1)",
      }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 500,
          letterSpacing: "0.08em", textTransform: "uppercase",
          color: n.armed ? c.hex : "var(--fg-2)",
          textShadow: n.armed ? `0 0 8px ${c.soft}` : "none",
        }}>{n.title}</span>
      </div>
      <div style={{ padding: 8, display: "flex", flexDirection: "column", gap: 4 }}>
        {n.body.map((row, i) => (
          <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", fontFamily: "var(--font-mono)", fontSize: 11 }}>
            <span style={{ color: row[0].startsWith("←") ? "var(--fg-3)" : "var(--fg-2)" }}>{row[0]}</span>
            <span style={{
              color: row[2] ? voice(row[2]).hex : "var(--fg-0)",
              textShadow: row[2] ? `0 0 8px ${voice(row[2]).soft}` : "none",
            }}>{row[1]}</span>
          </div>
        ))}
      </div>
      {/* in ports */}
      {(n.ins || []).map((p, i) => (
        <span key={"in" + i} style={{
          position: "absolute", left: -5, top: p.y - 4, width: 8, height: 8,
          background: voice(p.v).hex, borderRadius: "50%", boxShadow: `0 0 8px ${voice(p.v).soft}`,
        }} />
      ))}
      {/* out ports */}
      {(n.outs || []).map((p, i) => (
        <span key={"out" + i} style={{
          position: "absolute", right: -5, top: p.y - 4, width: 8, height: 8,
          background: voice(p.v).hex, borderRadius: "50%", boxShadow: `0 0 8px ${voice(p.v).soft}`,
        }} />
      ))}
    </div>
  );
}

window.SurfacePatcher = SurfacePatcher;

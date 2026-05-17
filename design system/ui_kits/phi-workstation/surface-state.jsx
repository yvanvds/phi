/* ============================================================
   surface-state.jsx — performance state graph
   "Arm transition" triggers a 4-bar countdown that morphs to next state.
   ============================================================ */

function SurfaceState({ activeState, onActivate }) {
  const nodes = [
    { id: "intro",  x: 80,  y: 80,  label: "intro",  visited: true },
    { id: "verse",  x: 260, y: 80,  label: "verse",  voice: 1 },
    { id: "break",  x: 460, y: 120, label: "break",  voice: 4 },
    { id: "drone",  x: 200, y: 240, label: "drone",  voice: 5 },
    { id: "lift",   x: 460, y: 260, label: "lift",   voice: 6 },
    { id: "out",    x: 660, y: 180, label: "out",    voice: 3, terminal: true },
  ];
  const edges = [
    { from: "intro", to: "verse", traversed: true, kind: "manual" },
    { from: "verse", to: "break", kind: "manual" },
    { from: "verse", to: "drone", kind: "cond", cond: "audio < −18 dB · 8 bars" },
    { from: "break", to: "lift",  kind: "morph", bars: 4 },
    { from: "lift",  to: "out",   kind: "manual" },
    { from: "drone", to: "out",   kind: "manual" },
    { from: "break", to: "verse", kind: "manual" },
  ];

  const [armed, setArmed] = React.useState(null);
  const [countdown, setCountdown] = React.useState(null);

  React.useEffect(() => {
    if (!armed) return;
    let bars = 4.0;
    setCountdown(bars);
    const iv = setInterval(() => {
      bars -= 0.05;
      if (bars <= 0) {
        clearInterval(iv);
        onActivate(armed);
        setArmed(null);
        setCountdown(null);
      } else {
        setCountdown(bars);
      }
    }, 70);
    return () => clearInterval(iv);
  }, [armed]);

  const nodeById = Object.fromEntries(nodes.map((n) => [n.id, n]));

  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: 12, gap: 8, minHeight: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--fg-2)" }}>state · performance graph</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>{nodes.length} states · {edges.length} transitions</span>
        <div style={{ flex: 1 }} />
        {countdown !== null && (
          <Capsule kind="hold">
            arm · {armed} · <span style={{ color: "var(--voice-3)", fontWeight: 600 }}>{countdown.toFixed(2)} bars</span>
          </Capsule>
        )}
        <Capsule kind="live">{activeState}</Capsule>
      </div>

      <div style={{
        flex: 1, minHeight: 0, position: "relative",
        background: "var(--bg-0)", border: "1px solid var(--line-1)", borderRadius: 4,
        overflow: "auto",
        backgroundImage: "radial-gradient(circle at 1px 1px, var(--grid-color) 1px, transparent 0)",
        backgroundSize: "16px 16px",
      }}>
        <svg style={{ position: "absolute", inset: 0, width: 820, height: 380, pointerEvents: "none" }}>
          <defs>
            <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
              <path d="M 0 0 L 10 5 L 0 10 z" fill="#7a838d"/>
            </marker>
            <marker id="arrow-hot" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
              <path d="M 0 0 L 10 5 L 0 10 z" fill="#ff3dcb"/>
            </marker>
            <marker id="arrow-warm" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
              <path d="M 0 0 L 10 5 L 0 10 z" fill="#ffb454"/>
            </marker>
          </defs>
          {edges.map((e, i) => {
            const a = nodeById[e.from], b = nodeById[e.to];
            const x1 = a.x + 80, y1 = a.y + 22;
            const x2 = b.x,      y2 = b.y + 22;
            const dx = x2 - x1;
            const cx1 = x1 + dx * 0.4, cx2 = x2 - dx * 0.4;
            const path = `M ${x1} ${y1} C ${cx1} ${y1}, ${cx2} ${y2}, ${x2} ${y2}`;
            const arming = armed && e.from === activeState && e.to === armed;
            const stroke = arming ? "#ffb454" : e.traversed ? "#ff3dcb" : "#7a838d";
            const marker = arming ? "url(#arrow-warm)" : e.traversed ? "url(#arrow-hot)" : "url(#arrow)";
            const dash = e.kind === "cond" ? "4 3" : "";
            return (
              <g key={i}>
                {arming && <path d={path} fill="none" stroke="#ffb454" strokeWidth="3" opacity="0.35" />}
                <path d={path} fill="none"
                      stroke={stroke}
                      strokeWidth={arming ? "1.6" : "1.2"}
                      strokeDasharray={dash}
                      markerEnd={marker} />
              </g>
            );
          })}
        </svg>

        {nodes.map((n) => {
          const active = n.id === activeState;
          const armedHere = n.id === armed;
          const v = active ? voice(1) : armedHere ? voice(3) : n.voice ? voice(n.voice) : null;
          return (
            <button
              key={n.id}
              onClick={() => {
                if (n.id === activeState) return;
                setArmed(n.id);
              }}
              style={{
                position: "absolute", left: n.x, top: n.y, width: 80,
                padding: "10px 12px",
                background: "var(--bg-1)",
                border: active
                  ? "1px solid var(--line-hot)"
                  : armedHere
                    ? "1px solid rgba(255,180,84,0.55)"
                    : v
                      ? `1px solid ${v.hex}44`
                      : "1px solid var(--line-1)",
                borderRadius: 4,
                boxShadow: active
                  ? "0 0 18px var(--voice-1-soft)"
                  : armedHere
                    ? "0 0 18px var(--voice-3-soft)"
                    : v
                      ? `0 0 10px ${v.soft}`
                      : "var(--elev-1)",
                cursor: "pointer",
                textAlign: "left",
              }}
            >
              <div style={{
                fontFamily: "var(--font-mono)", fontSize: 9,
                letterSpacing: "0.08em", textTransform: "uppercase",
                color: active ? "var(--voice-1)" : armedHere ? "var(--voice-3)" : "var(--fg-3)",
                marginBottom: 2,
              }}>
                {active ? "● live"
                 : armedHere ? "▲ armed · 4b"
                 : n.terminal ? "terminal"
                 : n.visited ? "visited" : "available"}
              </div>
              <div style={{
                fontFamily: "var(--font-mono)", fontSize: 13,
                color: active ? "var(--fg-0)" : "var(--fg-1)",
              }}>{n.label}</div>
            </button>
          );
        })}
      </div>

      <div style={{ display: "flex", gap: 6, fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>
        <span>tap a state to arm transition.</span>
        <span style={{ color: "var(--fg-4)" }}>·</span>
        <span>solid arrow = traversed.</span>
        <span style={{ color: "var(--fg-4)" }}>·</span>
        <span>dashed = conditional.</span>
      </div>
    </div>
  );
}

window.SurfaceState = SurfaceState;

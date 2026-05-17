/* ============================================================
   surface-midi.jsx — MIDI clip + transformation chain
   ============================================================ */

function SurfaceMidi() {
  // Generate a small phrase as visible notes
  const notes = [
    { p: 60, t: 0.00, d: 0.25, v: 0.7 },
    { p: 63, t: 0.25, d: 0.25, v: 0.6 },
    { p: 67, t: 0.50, d: 0.50, v: 0.8 },
    { p: 70, t: 1.00, d: 0.25, v: 0.5 },
    { p: 67, t: 1.25, d: 0.25, v: 0.6 },
    { p: 65, t: 1.50, d: 0.50, v: 0.7 },
    { p: 63, t: 2.00, d: 0.25, v: 0.5 },
    { p: 67, t: 2.25, d: 0.75, v: 0.9 },
    { p: 70, t: 3.00, d: 0.50, v: 0.7 },
    { p: 72, t: 3.50, d: 0.50, v: 0.8 },
  ];
  const transforms = [
    { kind: "pitch",  label: "scale · dorian D",     active: true, voice: 1 },
    { kind: "pitch",  label: "transpose · +3 st",    active: true, voice: 1 },
    { kind: "time",   label: "domain · drum @ 124",  active: true, voice: 2 },
    { kind: "time",   label: "quantize · gravity 0.6", active: true, voice: 2 },
    { kind: "voice",  label: "route · osc.saw",      active: true, voice: 3 },
    { kind: "voice",  label: "spawn · agent @ p,v",  active: true, voice: 3 },
    { kind: "struct", label: "loop · 4 bars",        active: false, voice: 4 },
    { kind: "struct", label: "branch · state.break", active: false, voice: 4 },
  ];

  const W = 660, H = 200;
  const minP = 55, maxP = 76;
  const beats = 4;

  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: 12, gap: 8, minHeight: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--fg-2)" }}>midi · phrase A</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>{notes.length} notes · 4 bars · interpreted, not played</span>
        <div style={{ flex: 1 }} />
        <Capsule>D dorian</Capsule>
        <Capsule kind="cool">domain · drum</Capsule>
      </div>

      <div style={{ flex: 1, display: "flex", gap: 8, minHeight: 0 }}>
        {/* clip viewer */}
        <div style={{
          flex: 1, minWidth: 0, position: "relative",
          background: "var(--bg-0)", border: "1px solid var(--line-1)", borderRadius: 4,
          overflow: "hidden",
        }}>
          <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ width: "100%", height: "100%", display: "block" }}>
            {/* horizontal pitch lanes */}
            {Array.from({ length: maxP - minP + 1 }, (_, i) => {
              const y = (H / (maxP - minP)) * i;
              const isKey = (maxP - i) % 12 === 0 || (maxP - i) % 12 === 7;
              return <line key={i} x1="0" y1={y} x2={W} y2={y} stroke={isKey ? "rgba(255,255,255,0.08)" : "rgba(255,255,255,0.025)"} strokeWidth="1" />;
            })}
            {/* beat lines */}
            {Array.from({ length: beats + 1 }, (_, i) => {
              const x = (W / beats) * i;
              return <line key={i} x1={x} y1="0" x2={x} y2={H} stroke="rgba(255,255,255,0.08)" strokeWidth="1" />;
            })}
            {/* sub-beats */}
            {Array.from({ length: beats * 4 + 1 }, (_, i) => {
              const x = (W / (beats * 4)) * i;
              return <line key={i} x1={x} y1="0" x2={x} y2={H} stroke="rgba(255,255,255,0.025)" strokeWidth="1" />;
            })}
            {/* notes */}
            {notes.map((n, i) => {
              const y = ((maxP - n.p) / (maxP - minP)) * H;
              const x = (n.t / beats) * W;
              const w = (n.d / beats) * W;
              return (
                <g key={i}>
                  <rect x={x} y={y - 4} width={w} height={8} fill="#ff3dcb" opacity={0.4 + n.v * 0.4} filter="url(#midi-glow)" />
                  <rect x={x} y={y - 3} width={w} height={6} fill="#ff3dcb" opacity={0.6 + n.v * 0.4} />
                  <rect x={x} y={y - 1} width={2} height={2} fill="#ffffff" />
                </g>
              );
            })}
            <defs>
              <filter id="midi-glow" x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur stdDeviation="1.2" />
              </filter>
            </defs>
            {/* playhead */}
            <line x1={W * 0.42} y1="0" x2={W * 0.42} y2={H} stroke="#ff3dcb" strokeWidth="1" opacity="0.7" />
          </svg>
          <div style={{ position: "absolute", left: 10, top: 8, fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)", letterSpacing: "0.06em", textTransform: "uppercase" }}>p55–76 · 4 bars</div>
        </div>

        {/* transform chain */}
        <div style={{
          width: 250, background: "var(--bg-1)", border: "1px solid var(--line-1)", borderRadius: 4,
          display: "flex", flexDirection: "column",
        }}>
          <div style={{ padding: "8px 10px", borderBottom: "1px solid var(--line-1)", display: "flex", alignItems: "center", gap: 8 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--fg-1)" }}>transform chain</span>
            <div style={{ flex: 1 }} />
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)", cursor: "pointer" }}>+</span>
          </div>
          <div style={{ padding: 6, display: "flex", flexDirection: "column", gap: 4 }}>
            {transforms.map((t, i) => (
              <div key={i} style={{
                display: "flex", alignItems: "center", gap: 8,
                padding: "5px 8px", borderRadius: 2,
                background: t.active ? "var(--bg-2)" : "transparent",
                opacity: t.active ? 1 : 0.5,
                fontFamily: "var(--font-mono)", fontSize: 11,
              }}>
                <span style={{
                  width: 36, fontSize: 8, letterSpacing: "0.08em", textTransform: "uppercase",
                  color: t.active ? voice(t.voice).hex : "var(--fg-3)",
                }}>{t.kind}</span>
                <span style={{ color: t.active ? "var(--fg-0)" : "var(--fg-3)", flex: 1 }}>{t.label}</span>
                <div style={{
                  width: 20, height: 10, borderRadius: 999,
                  background: t.active ? voice(t.voice).hex : "var(--fg-4)",
                  position: "relative",
                  boxShadow: t.active ? `0 0 6px ${voice(t.voice).soft}` : "none",
                }}>
                  <div style={{
                    position: "absolute", top: 1, bottom: 1, width: 8,
                    left: t.active ? 11 : 1,
                    background: "var(--bg-0)", borderRadius: 999,
                  }} />
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

window.SurfaceMidi = SurfaceMidi;

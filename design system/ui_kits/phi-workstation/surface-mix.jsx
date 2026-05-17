/* ============================================================
   surface-mix.jsx — channel strips
   ============================================================ */

function SurfaceMix() {
  const channels = [
    { name: "drum",   voice: 1, peak: 0.78, fader: 0.62, pan: 0,     dom: "drum",  sends: [["rev", 0.18], ["dly", 0.10]] },
    { name: "pad",    voice: 2, peak: 0.45, fader: 0.55, pan: -0.2,  dom: "pad",   sends: [["rev", 0.40]] },
    { name: "sparks", voice: 3, peak: 0.62, fader: 0.50, pan: 0.3,   dom: "grain", sends: [["rev", 0.55], ["dly", 0.20]] },
    { name: "drone",  voice: 5, peak: 0.30, fader: 0.42, pan: 0,     dom: "cont",  sends: [["rev", 0.65]] },
    { name: "voice",  voice: 4, peak: 0.0,  fader: 0.0,  pan: 0,     dom: "ext",   sends: [], muted: true },
    { name: "rev",    voice: 6, peak: 0.40, fader: 0.55, pan: 0,     bus: true,    sends: [] },
    { name: "dly",    voice: 6, peak: 0.25, fader: 0.50, pan: 0,     bus: true,    sends: [] },
    { name: "master", voice: 1, peak: 0.82, fader: 0.62, pan: 0,     master: true, sends: [] },
  ];

  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: 12, gap: 8, minHeight: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--fg-2)" }}>mix · {channels.length} channels</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>5 source · 2 bus · 1 master</span>
        <div style={{ flex: 1 }} />
        <Capsule kind="live">peak −4.8</Capsule>
      </div>

      <div style={{
        flex: 1, minHeight: 0,
        background: "var(--bg-0)", border: "1px solid var(--line-1)", borderRadius: 4,
        padding: 12,
        display: "flex", gap: 8, alignItems: "stretch",
      }}>
        {channels.map((c) => <ChannelStrip key={c.name} c={c} />)}
      </div>
    </div>
  );
}

function ChannelStrip({ c }) {
  const v = voice(c.voice);
  return (
    <div style={{
      width: 86, display: "flex", flexDirection: "column", gap: 6,
      background: "var(--bg-1)", border: c.master ? `1px solid ${v.hex}55` : "1px solid var(--line-1)",
      borderRadius: 3, padding: 8,
      boxShadow: c.master ? `0 0 16px ${v.soft}` : "var(--elev-1)",
    }}>
      {/* header */}
      <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
        <VoiceDot v={c.voice} size={6} />
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 500,
          color: c.muted ? "var(--fg-3)" : "var(--fg-0)",
          flex: 1,
        }}>{c.name}</span>
      </div>
      <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--fg-3)" }}>
        {c.master ? "out" : c.bus ? "bus" : c.dom}
      </span>

      {/* pan */}
      <div style={{ position: "relative", height: 6, background: "var(--bg-0)", border: "1px solid var(--line-1)", borderRadius: 999 }}>
        <div style={{
          position: "absolute", top: -1, bottom: -1,
          width: 4, left: `calc(${(c.pan + 1) * 50}% - 2px)`,
          background: v.hex, borderRadius: 999, boxShadow: `0 0 6px ${v.soft}`,
        }} />
      </div>

      {/* fader */}
      <div style={{ flex: 1, position: "relative", display: "flex", justifyContent: "center", padding: "6px 0" }}>
        <div style={{
          width: 14, height: "100%", background: "var(--bg-0)",
          border: "1px solid var(--line-1)", borderRadius: 2, position: "relative",
        }}>
          {/* scale */}
          <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", justifyContent: "space-between", padding: 4 }}>
            {[0, 1, 2, 3].map((i) => <div key={i} style={{ height: 1, background: "var(--fg-4)" }} />)}
          </div>
          {/* peak meter — audio convention: green at low, amber mid, red at clip.
              gradient stops are calibrated to the FULL meter (peak=1 = clip), then
              mapped into the visible fill so absolute levels keep their color. */}
          <div style={{
            position: "absolute", left: 0, right: 0, bottom: 0,
            height: `${c.peak * 100}%`,
            background: c.peak <= 0 ? "transparent" : (() => {
              const greenEnd = Math.min(0.60 / c.peak, 1);
              const amberEnd = Math.min(0.85 / c.peak, 1);
              return `linear-gradient(to top,
                var(--voice-4) 0%, var(--voice-4) ${greenEnd * 100}%,
                var(--voice-3) ${greenEnd * 100}%, var(--voice-3) ${amberEnd * 100}%,
                var(--hot) ${amberEnd * 100}%, var(--hot) 100%)`;
            })(),
            boxShadow: c.peak > 0 ? (
              c.peak > 0.85
                ? "0 0 8px rgba(255, 77, 77, 0.5)"
                : c.peak > 0.60
                  ? "0 0 8px var(--voice-3-soft)"
                  : "0 0 8px var(--voice-4-soft)"
            ) : "none",
            opacity: c.muted ? 0 : 1,
          }} />
          {/* fader handle */}
          <div style={{
            position: "absolute", left: -4, right: -4,
            bottom: `calc(${c.fader * 100}% - 6px)`,
            height: 12, background: "var(--bg-3)",
            border: c.master ? "1px solid var(--line-hot)" : "1px solid var(--line-2)",
            borderRadius: 2,
            boxShadow: c.master ? `0 0 8px ${v.soft}` : "none",
          }} />
        </div>
      </div>

      {/* peak value — numeric color follows the meter level convention */}
      <span style={{
        textAlign: "center", fontFamily: "var(--font-mono)", fontSize: 10,
        color: c.muted
          ? "var(--fg-3)"
          : c.peak > 0.85 ? "var(--hot)"
          : c.peak > 0.60 ? "var(--voice-3)"
          : "var(--voice-4)",
        textShadow: c.muted ? "none" : (
          c.peak > 0.85 ? "0 0 6px rgba(255,77,77,0.5)"
          : c.peak > 0.60 ? "0 0 6px var(--voice-3-soft)"
          : "0 0 6px var(--voice-4-soft)"
        ),
      }}>
        {c.muted ? "muted" : `−${(20 - c.peak * 20).toFixed(1)}`}
      </span>

      {/* sends */}
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        {c.sends.map(([nm, amt], i) => (
          <div key={i} style={{ display: "flex", alignItems: "center", gap: 4, fontFamily: "var(--font-mono)", fontSize: 9 }}>
            <span style={{ color: "var(--fg-3)", flex: 1 }}>{nm}</span>
            <span style={{ color: voice(6).hex }}>{(amt * 100).toFixed(0)}</span>
          </div>
        ))}
      </div>

      {/* MS/A buttons */}
      <div style={{ display: "flex", gap: 2 }}>
        {["M", "S", "A"].map((l, i) => (
          <button key={l} style={{
            flex: 1, height: 18, padding: 0, borderRadius: 2,
            background: l === "M" && c.muted
              ? "var(--bg-3)"
              : l === "A" && !c.muted
                ? "var(--bg-2)"
                : "var(--bg-0)",
            border: l === "A" && !c.muted ? "1px solid var(--line-hot)" : "1px solid var(--line-1)",
            color: l === "M" && c.muted
              ? "var(--hot)"
              : l === "A" && !c.muted
                ? "var(--voice-1)"
                : "var(--fg-2)",
            fontFamily: "var(--font-mono)", fontSize: 9,
            cursor: "pointer",
            boxShadow: l === "A" && !c.muted ? "0 0 8px var(--voice-1-soft)" : "none",
          }}>{l}</button>
        ))}
      </div>
    </div>
  );
}

window.SurfaceMix = SurfaceMix;

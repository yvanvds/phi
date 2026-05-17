/* ============================================================
   chrome.jsx — Toolbar, Rail, StatusStrip, Inspector
   ============================================================ */

function Toolbar({ tempo, meter, playing, onPlay, onArm, projection, onProjection, sceneName }) {
  return (
    <div style={{
      display: "flex", alignItems: "center",
      height: 36, padding: "0 12px", gap: 12, flexShrink: 0,
      background: "var(--bg-1)",
      borderBottom: "1px solid var(--line-1)",
    }}>
      <IconPhiMark size={18} color="var(--voice-1)" />
      <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-1)" }}>{sceneName}</span>
      <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-3)" }}>·</span>
      <span style={{
        fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em",
        textTransform: "uppercase", color: "var(--fg-2)",
      }}>untitled</span>

      <div style={{ flex: 1 }} />

      {/* transport */}
      <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
        <button onClick={() => {}} title="prev" style={txButtonStyle()}>
          <svg width="11" height="11" viewBox="0 0 12 12"><polygon points="2,1 2,11 11,6" fill="currentColor" transform="rotate(180 6 6)" /></svg>
        </button>
        <button onClick={onPlay} title={playing ? "pause" : "play"} style={txButtonStyle(playing)}>
          {playing
            ? <svg width="10" height="10" viewBox="0 0 12 12"><rect x="2" y="2" width="3" height="8" fill="currentColor"/><rect x="7" y="2" width="3" height="8" fill="currentColor"/></svg>
            : <svg width="11" height="11" viewBox="0 0 12 12"><polygon points="3,1 3,11 11,6" fill="currentColor" /></svg>}
        </button>
        <button onClick={() => {}} title="record" style={txButtonStyle()}>
          <svg width="11" height="11" viewBox="0 0 12 12"><circle cx="6" cy="6" r="3.4" fill="currentColor" /></svg>
        </button>
      </div>

      <div style={{ width: 1, height: 18, background: "var(--line-1)" }} />

      <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--voice-1)", textShadow: "0 0 8px var(--voice-1-soft)" }}>{tempo.toFixed(1)}</span>
      <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>bpm · drum</span>

      <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--voice-2)", textShadow: "0 0 8px var(--voice-2-soft)" }}>{meter}</span>
      <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>pad</span>

      <div style={{ width: 1, height: 18, background: "var(--line-1)" }} />

      <Button variant="hot" onClick={onArm} style={{ height: 24 }}>kill</Button>

      <Capsule
        kind={projection ? "live" : "default"}
        style={{ cursor: "pointer" }}
      >
        <span onClick={onProjection} style={{ display: "contents" }}>project · {projection ? "on" : "off"}</span>
      </Capsule>
    </div>
  );
}

function txButtonStyle(active) {
  return {
    width: 28, height: 24,
    background: active ? "var(--bg-2)" : "var(--bg-2)",
    border: active ? "1px solid var(--line-hot)" : "1px solid var(--line-1)",
    borderRadius: 2,
    color: active ? "var(--voice-1)" : "var(--fg-1)",
    boxShadow: active ? "0 0 12px var(--voice-1-soft)" : "none",
    cursor: "pointer",
    display: "flex", alignItems: "center", justifyContent: "center",
    padding: 0,
  };
}

/* ---------------- Rail ---------------- */
function Rail({ surface, onSurface }) {
  const items = [
    { id: "scene",   icon: IconScene,   label: "scene" },
    { id: "patcher", icon: IconPatcher, label: "patch" },
    { id: "code",    icon: IconCode,    label: "code" },
    { id: "state",   icon: IconState,   label: "state" },
    { id: "midi",    icon: IconMidi,    label: "midi" },
    { id: "mix",     icon: IconMix,     label: "mix" },
  ];
  return (
    <div style={{
      width: 48, flexShrink: 0,
      background: "var(--bg-1)", borderRight: "1px solid var(--line-1)",
      display: "flex", flexDirection: "column", alignItems: "center",
      padding: "8px 0", gap: 2,
    }}>
      {items.map(({ id, icon: Icon, label }) => {
        const active = surface === id;
        return (
          <button
            key={id}
            onClick={() => onSurface(id)}
            title={label}
            style={{
              width: 36, height: 40, border: "none",
              background: active ? "var(--bg-2)" : "transparent",
              borderRadius: 3,
              display: "flex", flexDirection: "column",
              alignItems: "center", justifyContent: "center",
              gap: 3, position: "relative", cursor: "pointer",
              color: active ? "var(--voice-1)" : "var(--fg-2)",
              boxShadow: active ? "0 0 14px var(--voice-1-soft) inset" : "none",
              transition: "color var(--dur-1) var(--ease-out), background var(--dur-1) var(--ease-out)",
            }}
            onMouseEnter={(e) => { if (!active) e.currentTarget.style.color = "var(--fg-0)"; }}
            onMouseLeave={(e) => { if (!active) e.currentTarget.style.color = "var(--fg-2)"; }}
          >
            {active && (
              <span style={{
                position: "absolute", left: -7, top: "50%", width: 2, height: 20,
                background: "var(--voice-1)", boxShadow: "0 0 6px var(--voice-1-soft)",
                transform: "translateY(-50%)",
              }} />
            )}
            <Icon size={18} />
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 8,
              letterSpacing: "0.1em", textTransform: "uppercase",
              color: active ? "var(--voice-1)" : "var(--fg-3)",
            }}>{label}</span>
          </button>
        );
      })}
      <div style={{ flex: 1 }} />
      <button title="settings" style={{
        width: 36, height: 36, border: "none", background: "transparent",
        color: "var(--fg-3)", cursor: "pointer", borderRadius: 3,
        display: "flex", alignItems: "center", justifyContent: "center",
      }}>
        <IconSettings size={18} />
      </button>
    </div>
  );
}

/* ---------------- Status Strip ---------------- */
function StatusStrip({ cpu, latency, midiActivity, objCount, peers }) {
  return (
    <div style={{
      display: "flex", alignItems: "center",
      height: 26, padding: "0 12px", gap: 16, flexShrink: 0,
      background: "var(--bg-1)", borderTop: "1px solid var(--line-1)",
      fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.04em",
    }}>
      <span style={{ display: "flex", alignItems: "center", gap: 6, color: "var(--fg-2)" }}>
        <span style={{ color: "var(--voice-1)", textShadow: "0 0 6px var(--voice-1-soft)" }}>●</span>audio
      </span>
      <span style={{ color: "var(--fg-1)" }}>cpu <span style={{ color: "var(--fg-0)" }}>{cpu.toFixed(0)}%</span></span>
      <span style={{ color: "var(--fg-1)" }}>buf <span style={{ color: "var(--fg-0)" }}>128 / 48k</span></span>
      <span style={{ color: "var(--fg-1)" }}>latency <span style={{ color: "var(--fg-0)" }}>{latency.toFixed(1)} ms</span></span>
      <div style={{ flex: 1 }} />
      <span style={{ color: "var(--fg-1)" }}>
        midi <span style={{ color: midiActivity ? "var(--voice-3)" : "var(--fg-3)" }}>▲ in</span>
        <span style={{ color: "var(--fg-3)", marginLeft: 4 }}>▼ out</span>
      </span>
      <span style={{ color: "var(--fg-1)" }}>link <span style={{ color: "var(--voice-2)" }}>●</span> <span style={{ color: "var(--fg-2)" }}>{peers} peers</span></span>
      <span style={{ color: "var(--fg-1)" }}>scene <span style={{ color: "var(--fg-0)" }}>{objCount} obj</span></span>
    </div>
  );
}

/* ---------------- Inspector (right column) ---------------- */
function Inspector({ selected }) {
  if (!selected) {
    return (
      <div style={{
        flex: 1, padding: 14,
        display: "flex", flexDirection: "column", gap: 10, color: "var(--fg-3)",
      }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 10,
          letterSpacing: "0.1em", textTransform: "uppercase",
        }}>nothing selected</span>
        <span style={{ fontFamily: "var(--font-ui)", fontSize: 13, color: "var(--fg-3)", lineHeight: 1.5 }}>
          Select an agent, swarm, domain, code block, or state node to inspect.
        </span>
      </div>
    );
  }
  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "auto" }}>
      <div style={{ padding: 14, display: "flex", flexDirection: "column", gap: 14 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <VoiceDot v={selected.voice} size={10} />
          <span style={{ fontFamily: "var(--font-display)", fontWeight: 600, fontSize: 18, color: "var(--fg-0)", letterSpacing: "-0.02em" }}>{selected.name}</span>
          <div style={{ flex: 1 }} />
          <Capsule kind="live">{selected.status || "live"}</Capsule>
        </div>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)", letterSpacing: "0.08em", textTransform: "uppercase" }}>{selected.kind}</span>

        <div style={{ height: 1, background: "var(--line-1)" }} />

        <SectionLabel>properties</SectionLabel>
        {selected.props && selected.props.map((p, i) => (
          <div key={i} style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-2)", width: 80 }}>{p.k}</span>
            <Field value={p.v} suffix={p.unit} voice={p.voice} style={{ flex: 1 }} />
          </div>
        ))}

        {selected.subscriptions && (
          <React.Fragment>
            <div style={{ height: 1, background: "var(--line-1)" }} />
            <SectionLabel>subscriptions · {selected.subscriptions.length}</SectionLabel>
            {selected.subscriptions.map((s, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <VoiceDot v={s.voice} size={6} />
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-1)", flex: 1 }}>{s.name}</span>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: voice(s.voice).hex }}>w {s.weight.toFixed(2)}</span>
              </div>
            ))}
          </React.Fragment>
        )}

        {selected.position && (
          <React.Fragment>
            <div style={{ height: 1, background: "var(--line-1)" }} />
            <SectionLabel>position</SectionLabel>
            <div style={{ display: "flex", gap: 6 }}>
              <Field label="x" value={selected.position[0].toFixed(2)} style={{ flex: 1 }} />
              <Field label="y" value={selected.position[1].toFixed(2)} style={{ flex: 1 }} />
              <Field label="z" value={selected.position[2].toFixed(2)} style={{ flex: 1 }} />
            </div>
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

function SectionLabel({ children }) {
  return <span style={{
    fontFamily: "var(--font-mono)", fontSize: 10,
    letterSpacing: "0.1em", textTransform: "uppercase",
    color: "var(--fg-2)",
  }}>{children}</span>;
}

Object.assign(window, { Toolbar, Rail, StatusStrip, Inspector, SectionLabel });

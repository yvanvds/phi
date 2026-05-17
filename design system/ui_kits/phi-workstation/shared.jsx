/* ============================================================
   shared.jsx — voice helpers, icon glyphs, small atoms.
   All components exported via window for cross-file scope.
   ============================================================ */

const VOICES = [
  { id: 1, name: "fuchsia",  hex: "#ff3dcb", soft: "rgba(255,  61, 203, 0.32)" },
  { id: 2, name: "cyan",     hex: "#6fd5ff", soft: "rgba(111, 213, 255, 0.28)" },
  { id: 3, name: "amber",    hex: "#ffb454", soft: "rgba(255, 180,  84, 0.28)" },
  { id: 4, name: "phosphor", hex: "#a8fc5c", soft: "rgba(168, 252,  92, 0.28)" },
  { id: 5, name: "violet",   hex: "#b58dff", soft: "rgba(181, 141, 255, 0.28)" },
  { id: 6, name: "yellow",   hex: "#ffe066", soft: "rgba(255, 224, 102, 0.28)" },
];

const voice = (i) => VOICES[(i - 1) % VOICES.length];

/* --- Capsule --- */
function Capsule({ children, voice: vNum, kind = "default", style }) {
  const v = vNum ? voice(vNum) : null;
  const palette = {
    default: { color: "var(--fg-1)", border: "var(--line-1)", glow: "none" },
    live:    { color: "var(--voice-1)", border: "var(--line-hot)", glow: "0 0 12px var(--voice-1-soft)" },
    hold:    { color: "var(--voice-3)", border: "rgba(255,180,84,0.4)", glow: "0 0 12px var(--voice-3-soft)" },
    cool:    { color: "var(--voice-2)", border: "rgba(111,213,255,0.4)", glow: "0 0 12px var(--voice-2-soft)" },
    hot:     { color: "var(--hot)", border: "rgba(255,77,77,0.4)", glow: "0 0 12px rgba(255,77,77,0.3)" },
  };
  const p = v
    ? { color: v.hex, border: `rgba(${hexToRgb(v.hex)},0.4)`, glow: `0 0 12px ${v.soft}` }
    : palette[kind] || palette.default;
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 6,
      height: 22, padding: "0 10px", borderRadius: 999,
      fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
      letterSpacing: "0.08em", textTransform: "uppercase",
      background: "var(--bg-1)", border: `1px solid ${p.border}`,
      color: p.color, boxShadow: p.glow, whiteSpace: "nowrap",
      ...style,
    }}>
      <span style={{ width: 6, height: 6, borderRadius: "50%", background: p.color, boxShadow: `0 0 8px ${p.color}` }} />
      {children}
    </span>
  );
}

function hexToRgb(hex) {
  const m = hex.replace("#", "").match(/.{2}/g);
  return m.map((h) => parseInt(h, 16)).join(",");
}

/* --- Button --- */
function Button({ children, variant = "secondary", icon, onClick, style, active }) {
  const variants = {
    primary: {
      background: "var(--bg-1)", border: "1px solid var(--line-hot)",
      color: "var(--voice-1)",
      boxShadow: "0 0 12px var(--voice-1-soft) inset, 0 0 18px var(--voice-1-soft)",
    },
    secondary: {
      background: "var(--bg-2)", border: "1px solid var(--line-1)",
      color: "var(--fg-0)",
    },
    ghost: {
      background: "transparent", border: "1px solid var(--line-1)",
      color: "var(--fg-1)",
    },
    hot: {
      background: "var(--bg-1)", border: "1px solid rgba(255,77,77,0.45)",
      color: "var(--hot)", boxShadow: "0 0 14px rgba(255,77,77,0.2)",
    },
  };
  return (
    <button onClick={onClick} style={{
      display: "inline-flex", alignItems: "center", gap: 6,
      height: 26, padding: "0 12px",
      borderRadius: 4, fontFamily: "var(--font-ui)", fontSize: 12, fontWeight: 500,
      cursor: "pointer", userSelect: "none",
      transition: "background var(--dur-1) var(--ease-out), transform var(--dur-1) var(--ease-out)",
      ...variants[variant],
      ...(active ? { transform: "translateY(1px)" } : {}),
      ...style,
    }}>
      {icon && <span style={{ display: "inline-flex" }}>{icon}</span>}
      {children}
    </button>
  );
}

/* --- Field --- */
function Field({ label, value, voice: vNum, suffix, mono = true, style }) {
  const v = vNum ? voice(vNum) : null;
  return (
    <div style={{
      display: "flex", alignItems: "center",
      height: 24, padding: "0 8px",
      background: "var(--bg-1)", border: "1px solid var(--line-1)",
      borderRadius: 2,
      fontFamily: mono ? "var(--font-mono)" : "var(--font-ui)",
      fontSize: 12, color: "var(--fg-0)",
      minWidth: 0, ...style,
    }}>
      {label && <span style={{ color: "var(--fg-2)", marginRight: 8 }}>{label}</span>}
      <span style={v ? { color: v.hex, textShadow: `0 0 8px ${v.soft}` } : {}}>{value}</span>
      {suffix && <span style={{ color: "var(--fg-3)", marginLeft: 4 }}>{suffix}</span>}
    </div>
  );
}

/* --- Panel --- */
function Panel({ title, subtitle, right, children, style, glow, padded = true }) {
  return (
    <div style={{
      background: "var(--bg-1)",
      border: glow ? "1px solid var(--line-hot)" : "1px solid var(--line-1)",
      borderRadius: 4,
      boxShadow: glow ? "0 0 16px var(--voice-1-soft)" : "var(--elev-1)",
      display: "flex", flexDirection: "column",
      overflow: "hidden", minHeight: 0,
      ...style,
    }}>
      {title && (
        <div style={{
          display: "flex", alignItems: "center", height: 28, padding: "0 10px",
          borderBottom: "1px solid var(--line-1)", background: "var(--bg-2)", gap: 10,
        }}>
          <span style={{
            fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
            letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--fg-1)",
          }}>{title}</span>
          {subtitle && <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>{subtitle}</span>}
          <div style={{ flex: 1 }} />
          {right}
        </div>
      )}
      <div style={{ flex: 1, padding: padded ? 10 : 0, minHeight: 0, display: "flex", flexDirection: "column", gap: 6 }}>
        {children}
      </div>
    </div>
  );
}

/* --- VoiceDot --- */
function VoiceDot({ v, size = 8, style }) {
  const c = voice(v);
  return <span style={{
    display: "inline-block", width: size, height: size,
    background: c.hex, boxShadow: `0 0 8px ${c.soft}`,
    flexShrink: 0, ...style,
  }} />;
}

/* --- Bespoke icon primitives --- */
function IconPhiMark({ size = 16, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" fill="none">
      <g stroke={color} strokeWidth="4" strokeLinecap="round" fill="none">
        <line x1="32" y1="6" x2="32" y2="58" />
        <ellipse cx="32" cy="32" rx="13" ry="10" />
      </g>
    </svg>
  );
}

function IconScene({ size = 18, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 2 L22 8 L22 16 L12 22 L2 16 L2 8 Z" />
      <path d="M12 2 L12 22 M2 8 L22 16 M22 8 L2 16" opacity="0.5" />
    </svg>
  );
}

function IconPatcher({ size = 18, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.5">
      <rect x="3" y="4" width="6" height="6" />
      <rect x="15" y="4" width="6" height="6" />
      <rect x="9" y="14" width="6" height="6" />
      <path d="M6 10 L6 14 L12 14 M18 10 L18 14 L12 14" />
    </svg>
  );
}

function IconCode({ size = 18, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="8 7 3 12 8 17" />
      <polyline points="16 7 21 12 16 17" />
    </svg>
  );
}

function IconState({ size = 18, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.5">
      <circle cx="6" cy="6" r="3" />
      <circle cx="18" cy="18" r="3" />
      <circle cx="18" cy="6" r="3" />
      <line x1="8.5" y1="8.5" x2="15.5" y2="15.5" />
      <line x1="9" y1="6" x2="15" y2="6" />
    </svg>
  );
}

function IconMidi({ size = 18, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round">
      <path d="M9 17V5l11-2v12" />
      <circle cx="6" cy="17" r="3" />
      <circle cx="17" cy="15" r="3" />
    </svg>
  );
}

function IconMix({ size = 18, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round">
      <line x1="4" y1="6" x2="20" y2="6" />
      <line x1="4" y1="12" x2="20" y2="12" />
      <line x1="4" y1="18" x2="20" y2="18" />
      <circle cx="9"  cy="6"  r="2" fill="currentColor" />
      <circle cx="15" cy="12" r="2" fill="currentColor" />
      <circle cx="7"  cy="18" r="2" fill="currentColor" />
    </svg>
  );
}

function IconSettings({ size = 18, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.5">
      <circle cx="12" cy="12" r="3" />
      <path d="M12 1v3 M12 20v3 M4.2 4.2l2.1 2.1 M17.7 17.7l2.1 2.1 M1 12h3 M20 12h3 M4.2 19.8l2.1-2.1 M17.7 6.3l2.1-2.1" strokeLinecap="round" />
    </svg>
  );
}

/* Export everything to window so the other Babel scripts can see them */
Object.assign(window, {
  VOICES, voice, hexToRgb,
  Capsule, Button, Field, Panel, VoiceDot,
  IconPhiMark, IconScene, IconPatcher, IconCode, IconState, IconMidi, IconMix, IconSettings,
});

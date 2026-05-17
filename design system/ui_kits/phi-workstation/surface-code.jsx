/* ============================================================
   surface-code.jsx — Python live-coding editor
   Click any line and "evaluate" to flash + re-execute.
   ============================================================ */

function SurfaceCode({ projection }) {
  const initial = [
    { t: "# warm up — domain definitions", c: "co" },
    { t: 'domain("drum").metric(124).meter(4, 4)', c: "df" },
    { t: 'domain("pad").phase(7).rate(0.84)', c: "df" },
    { t: 'domain("grain").event()', c: "df" },
    { t: "", c: "" },
    { t: "# the swarms", c: "co" },
    { t: 'sparks = swarm("sparks", n=14)', c: "as" },
    { t: '  .voice(3)', c: "ch" },
    { t: '  .cohere(0.6)', c: "ch" },
    { t: '  .subscribe("drum", w=0.7)', c: "ch" },
    { t: '  .subscribe("grain", w=0.3)', c: "ch" },
    { t: "", c: "" },
    { t: "# trigger break on entry to volume A", c: "co" },
    { t: 'on agent.enters(volume.A):', c: "kw" },
    { t: '    state.arm("break", bars=4)', c: "in" },
    { t: '    sparks.scatter(0.4)', c: "in" },
  ];
  const [lines, setLines] = React.useState(initial);
  const [evald, setEvald] = React.useState(new Set([1, 2, 3, 6, 7, 8, 9, 10]));
  const [recent, setRecent] = React.useState(null);
  const [selectedLine, setSelectedLine] = React.useState(13);

  const handleEval = (i) => {
    setEvald((s) => new Set([...s, i]));
    setRecent(i);
    setTimeout(() => setRecent(null), 1100);
  };

  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: 12, gap: 8, minHeight: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--fg-2)" }}>code · main.py</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)" }}>python · {lines.length} lines · {evald.size} evaluated</span>
        <div style={{ flex: 1 }} />
        <Capsule kind={projection ? "live" : "default"}>{projection ? "projected" : "working"} register</Capsule>
        <Button variant="primary" onClick={() => handleEval(selectedLine)}>eval line ⏎</Button>
      </div>

      <div style={{
        flex: 1, minHeight: 0,
        background: "var(--bg-0)", border: "1px solid var(--line-1)", borderRadius: 4,
        overflow: "auto",
        position: "relative",
      }}>
        {/* gutter + lines */}
        {lines.map((ln, i) => (
          <CodeLine
            key={i}
            i={i}
            ln={ln}
            evaluated={evald.has(i)}
            recent={recent === i}
            selected={selectedLine === i}
            projection={projection}
            onClick={() => setSelectedLine(i)}
            onEval={() => handleEval(i)}
          />
        ))}

        {/* projected legibility halo */}
        {projection && (
          <div style={{ position: "absolute", inset: 0, pointerEvents: "none", boxShadow: "inset 0 0 80px var(--voice-1-soft)" }} />
        )}
      </div>

      {/* repl-style trace */}
      <div style={{
        height: 80, background: "var(--bg-0)", border: "1px solid var(--line-1)", borderRadius: 4,
        padding: "8px 12px", overflow: "auto",
        fontFamily: "var(--font-mono)", fontSize: 11, lineHeight: 1.55,
      }}>
        <div style={{ color: "var(--fg-3)" }}>&gt; eval line 7</div>
        <div style={{ color: "var(--voice-1)", textShadow: "0 0 6px var(--voice-1-soft)" }}>  ok · sparks → swarm[14] voice=3 cohere=0.6</div>
        <div style={{ color: "var(--fg-3)" }}>&gt; eval line 14</div>
        <div style={{ color: "var(--voice-3)", textShadow: "0 0 6px var(--voice-3-soft)" }}>  pending · event "agent.enters(volume.A)"</div>
      </div>
    </div>
  );
}

function CodeLine({ i, ln, evaluated, recent, selected, projection, onClick, onEval }) {
  const tokens = tokenize(ln.t);
  return (
    <div
      onClick={onClick}
      onDoubleClick={onEval}
      style={{
        display: "flex", gap: 10, padding: "1px 0",
        background: recent ? "rgba(168, 252, 92, 0.10)" : selected ? "rgba(255, 255, 255, 0.025)" : "transparent",
        boxShadow: recent ? "inset 2px 0 0 var(--voice-1), 0 0 16px var(--voice-1-soft) inset" : selected ? "inset 2px 0 0 var(--fg-3)" : "none",
        cursor: "pointer",
        transition: "background var(--dur-3) var(--ease-out)",
      }}
    >
      <span style={{
        width: 36, textAlign: "right",
        fontFamily: "var(--font-mono)", fontSize: 11,
        color: evaluated ? "var(--voice-1)" : "var(--fg-4)",
        flexShrink: 0,
        textShadow: evaluated ? "0 0 6px var(--voice-1-soft)" : "none",
      }}>
        {String(i + 1).padStart(2, "0")}
      </span>
      <pre style={{
        margin: 0, fontFamily: "var(--font-mono)",
        fontSize: projection ? 15 : 13,
        lineHeight: 1.55, color: "var(--fg-0)", whiteSpace: "pre",
      }}>
        {tokens.map((tok, j) => <span key={j} style={{ color: tok.color }}>{tok.t}</span>)}
      </pre>
    </div>
  );
}

function tokenize(text) {
  if (text.trim().startsWith("#")) return [{ t: text, color: "var(--fg-3)" }];
  if (!text.trim()) return [{ t: text, color: "var(--fg-3)" }];
  const tokens = [];
  const re = /(\s+|[a-zA-Z_][a-zA-Z0-9_]*|"[^"]*"|[0-9]+\.?[0-9]*|[(),.:=]|.)/g;
  const kws = new Set(["domain", "swarm", "state", "agent", "on", "volume", "sparks", "wave"]);
  const verbs = new Set(["metric", "phase", "rate", "meter", "event", "cohere", "subscribe", "voice", "arm", "scatter", "enters"]);
  let m;
  while ((m = re.exec(text)) !== null) {
    const t = m[0];
    let color = "var(--fg-0)";
    if (kws.has(t)) color = "var(--voice-2)";
    else if (verbs.has(t)) color = "var(--voice-1)";
    else if (/^"/.test(t)) color = "var(--voice-6)";
    else if (/^[0-9]/.test(t)) color = "var(--voice-3)";
    else if (/^[(),.:=]$/.test(t)) color = "var(--fg-2)";
    tokens.push({ t, color });
  }
  return tokens;
}

window.SurfaceCode = SurfaceCode;

import { useState, useEffect, useCallback } from "react";

const PSTATE_INFO = {
  P0: { label: "MAX BOOST", color: "#00ff88", glow: "0 0 20px #00ff8855" },
  P1: { label: "High Perf", color: "#44dd66", glow: "0 0 15px #44dd6644" },
  P2: { label: "Medium", color: "#aacc33", glow: "0 0 10px #aacc3333" },
  P3: { label: "Med-Low", color: "#ddaa22", glow: "0 0 10px #ddaa2233" },
  P5: { label: "Low", color: "#ff8833", glow: "0 0 10px #ff883333" },
  P8: { label: "IDLE", color: "#ff3344", glow: "0 0 20px #ff334455" },
};

const MOCK_HISTORY_LENGTH = 60;

function generateMockState(boosted) {
  if (boosted) {
    return {
      pstate: "P0",
      gpuClock: 1185 + Math.floor(Math.random() * 30),
      memClock: 6144,
      maxGpuClock: 1200,
      maxMemClock: 6144,
      gpuUtil: 45 + Math.floor(Math.random() * 50),
      memUtil: 30 + Math.floor(Math.random() * 40),
      tempC: 55 + Math.floor(Math.random() * 15),
      powerDraw: 55 + Math.floor(Math.random() * 15),
      powerLimit: 70,
      memUsedMB: 4200 + Math.floor(Math.random() * 1500),
      memTotalMB: 6144,
      persistence: true,
      name: "NVIDIA RTX A2000",
    };
  }
  return {
    pstate: "P8",
    gpuClock: 210 + Math.floor(Math.random() * 40),
    memClock: 405,
    maxGpuClock: 1200,
    maxMemClock: 6144,
    gpuUtil: Math.floor(Math.random() * 5),
    memUtil: Math.floor(Math.random() * 8),
    tempC: 32 + Math.floor(Math.random() * 5),
    powerDraw: 8 + Math.floor(Math.random() * 4),
    powerLimit: 70,
    memUsedMB: 280 + Math.floor(Math.random() * 200),
    memTotalMB: 6144,
    persistence: false,
    name: "NVIDIA RTX A2000",
  };
}

function ArcGauge({ value, max, label, unit, color, size = 120 }) {
  const pct = Math.min(value / max, 1);
  const r = size / 2 - 12;
  const cx = size / 2;
  const cy = size / 2;
  const startAngle = -220;
  const endAngle = 40;
  const totalArc = endAngle - startAngle;
  const filledAngle = startAngle + totalArc * pct;

  function polarToCartesian(angle) {
    const rad = (angle * Math.PI) / 180;
    return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
  }

  const bgStart = polarToCartesian(startAngle);
  const bgEnd = polarToCartesian(endAngle);
  const fillEnd = polarToCartesian(filledAngle);
  const largeArcBg = totalArc > 180 ? 1 : 0;
  const largeArcFill = filledAngle - startAngle > 180 ? 1 : 0;

  return (
    <div style={{ textAlign: "center" }}>
      <svg width={size} height={size * 0.75} viewBox={`0 0 ${size} ${size * 0.85}`}>
        <path
          d={`M ${bgStart.x} ${bgStart.y} A ${r} ${r} 0 ${largeArcBg} 1 ${bgEnd.x} ${bgEnd.y}`}
          fill="none"
          stroke="#1a2a3a"
          strokeWidth="8"
          strokeLinecap="round"
        />
        {pct > 0.005 && (
          <path
            d={`M ${bgStart.x} ${bgStart.y} A ${r} ${r} 0 ${largeArcFill} 1 ${fillEnd.x} ${fillEnd.y}`}
            fill="none"
            stroke={color}
            strokeWidth="8"
            strokeLinecap="round"
            style={{ filter: `drop-shadow(0 0 6px ${color}66)` }}
          />
        )}
        <text x={cx} y={cy - 2} textAnchor="middle" fill="#e0e8f0" fontSize="22" fontWeight="700" fontFamily="'JetBrains Mono', 'Fira Code', monospace">
          {typeof value === "number" ? Math.round(value) : value}
        </text>
        <text x={cx} y={cy + 16} textAnchor="middle" fill="#5a7a9a" fontSize="10" fontFamily="'JetBrains Mono', monospace">
          {unit}
        </text>
      </svg>
      <div style={{ color: "#6a8aaa", fontSize: 11, marginTop: -8, fontFamily: "'JetBrains Mono', monospace", letterSpacing: "0.5px" }}>{label}</div>
    </div>
  );
}

function MiniChart({ data, color, height = 40, width = 200, max }) {
  if (!data.length) return null;
  const chartMax = max || Math.max(...data, 1);
  const points = data.map((v, i) => {
    const x = (i / (MOCK_HISTORY_LENGTH - 1)) * width;
    const y = height - (v / chartMax) * (height - 4) - 2;
    return `${x},${y}`;
  }).join(" ");

  const areaPoints = `0,${height} ${points} ${width},${height}`;

  return (
    <svg width={width} height={height} style={{ display: "block" }}>
      <defs>
        <linearGradient id={`grad-${color.replace("#", "")}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.3" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon points={areaPoints} fill={`url(#grad-${color.replace("#", "")})`} />
      <polyline points={points} fill="none" stroke={color} strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}

function StatusBadge({ active, label }) {
  return (
    <div style={{
      display: "inline-flex", alignItems: "center", gap: 6,
      padding: "4px 12px", borderRadius: 20,
      background: active ? "#00ff8815" : "#ff334415",
      border: `1px solid ${active ? "#00ff8833" : "#ff334433"}`,
    }}>
      <div style={{
        width: 8, height: 8, borderRadius: "50%",
        background: active ? "#00ff88" : "#ff3344",
        boxShadow: active ? "0 0 8px #00ff8888" : "0 0 8px #ff334488",
        animation: active ? "pulse 2s infinite" : "none",
      }} />
      <span style={{ fontSize: 11, color: active ? "#00ff88" : "#ff3344", fontFamily: "'JetBrains Mono', monospace", fontWeight: 600 }}>
        {label}
      </span>
    </div>
  );
}

export default function GpuDashboard() {
  const [boosted, setBoosted] = useState(false);
  const [state, setState] = useState(generateMockState(false));
  const [history, setHistory] = useState({ gpu: [], mem: [], temp: [], power: [] });
  const [transitioning, setTransitioning] = useState(false);
  const [autoMode, setAutoMode] = useState(false);
  const [lmStudioDetected, setLmStudioDetected] = useState(false);
  const [logs, setLogs] = useState([
    { time: "00:00:00", msg: "GPU Force Boost initialized", type: "info" },
    { time: "00:00:01", msg: "Found NVIDIA RTX A2000 at index 0", type: "info" },
    { time: "00:00:01", msg: "Current state: P8 (IDLE)", type: "warn" },
  ]);

  const addLog = useCallback((msg, type = "info") => {
    const now = new Date();
    const time = now.toTimeString().slice(0, 8);
    setLogs(prev => [...prev.slice(-20), { time, msg, type }]);
  }, []);

  const handleBoost = () => {
    setTransitioning(true);
    addLog("Enabling persistence mode...", "info");
    setTimeout(() => addLog("Locking GPU clock to 1200 MHz...", "info"), 300);
    setTimeout(() => addLog("Locking memory clock to 6144 MHz...", "info"), 600);
    setTimeout(() => {
      addLog("GPU locked to P0 — MAX BOOST", "success");
      setBoosted(true);
      setTransitioning(false);
    }, 1000);
  };

  const handleReset = () => {
    setTransitioning(true);
    addLog("Resetting GPU clocks...", "info");
    setTimeout(() => addLog("Resetting memory clocks...", "info"), 200);
    setTimeout(() => addLog("Disabling persistence mode...", "info"), 400);
    setTimeout(() => {
      addLog("GPU returned to default power management", "warn");
      setBoosted(false);
      setTransitioning(false);
    }, 700);
  };

  const toggleAuto = () => {
    setAutoMode(prev => {
      const next = !prev;
      addLog(next ? "Auto mode ON — watching for LM Studio" : "Auto mode OFF", next ? "success" : "warn");
      return next;
    });
  };

  // Simulate LM Studio detection in auto mode
  useEffect(() => {
    if (!autoMode) return;
    const interval = setInterval(() => {
      setLmStudioDetected(prev => {
        const next = Math.random() > 0.7 ? !prev : prev;
        if (next && !prev) {
          addLog("LM Studio detected — forcing P0!", "success");
          setBoosted(true);
        } else if (!next && prev) {
          addLog("LM Studio exited — resetting GPU", "warn");
          setBoosted(false);
        }
        return next;
      });
    }, 5000);
    return () => clearInterval(interval);
  }, [autoMode, addLog]);

  // Update state periodically
  useEffect(() => {
    const interval = setInterval(() => {
      const s = generateMockState(boosted);
      setState(s);
      setHistory(prev => ({
        gpu: [...prev.gpu.slice(-(MOCK_HISTORY_LENGTH - 1)), s.gpuUtil],
        mem: [...prev.mem.slice(-(MOCK_HISTORY_LENGTH - 1)), parseFloat(((s.memUsedMB / s.memTotalMB) * 100).toFixed(1))],
        temp: [...prev.temp.slice(-(MOCK_HISTORY_LENGTH - 1)), s.tempC],
        power: [...prev.power.slice(-(MOCK_HISTORY_LENGTH - 1)), s.powerDraw],
      }));
    }, 1000);
    return () => clearInterval(interval);
  }, [boosted]);

  const ps = PSTATE_INFO[state.pstate] || PSTATE_INFO.P8;

  return (
    <div style={{
      minHeight: "100vh",
      background: "#0a0e14",
      color: "#c0d0e0",
      fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace",
      padding: 24,
    }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;600;700&display=swap');
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
        @keyframes scan { 0% { transform: translateY(-100%); } 100% { transform: translateY(100%); } }
        * { box-sizing: border-box; }
      `}</style>

      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 24 }}>
        <div>
          <h1 style={{
            margin: 0, fontSize: 18, fontWeight: 700, color: "#e0e8f0",
            letterSpacing: "2px", textTransform: "uppercase",
          }}>
            <span style={{ color: ps.color }}>◆</span> GPU Force Boost
          </h1>
          <div style={{ fontSize: 11, color: "#4a6a8a", marginTop: 4 }}>{state.name} • nvidia-smi controller</div>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <StatusBadge active={state.persistence} label={state.persistence ? "PERSIST ON" : "PERSIST OFF"} />
          <StatusBadge active={boosted} label={boosted ? "BOOSTED" : "DEFAULT"} />
        </div>
      </div>

      {/* P-State Hero */}
      <div style={{
        background: "#0d1520",
        border: `1px solid ${ps.color}22`,
        borderRadius: 12,
        padding: 24,
        marginBottom: 20,
        textAlign: "center",
        position: "relative",
        overflow: "hidden",
      }}>
        <div style={{
          position: "absolute", top: 0, left: 0, right: 0, bottom: 0,
          background: `radial-gradient(ellipse at center, ${ps.color}08 0%, transparent 70%)`,
        }} />
        <div style={{ position: "relative" }}>
          <div style={{
            fontSize: 56, fontWeight: 700, color: ps.color,
            textShadow: ps.glow, lineHeight: 1,
          }}>
            {state.pstate}
          </div>
          <div style={{ fontSize: 13, color: ps.color, opacity: 0.8, marginTop: 4, letterSpacing: "3px" }}>
            {ps.label}
          </div>
          <div style={{ fontSize: 11, color: "#4a6a8a", marginTop: 8 }}>
            {state.gpuClock} MHz / {state.maxGpuClock} MHz
          </div>
        </div>
      </div>

      {/* Gauges Row */}
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 16,
        marginBottom: 20,
      }}>
        <div style={{ background: "#0d1520", borderRadius: 10, padding: 16, border: "1px solid #1a2a3a" }}>
          <ArcGauge value={state.gpuUtil} max={100} label="GPU LOAD" unit="%" color="#00ccff" />
        </div>
        <div style={{ background: "#0d1520", borderRadius: 10, padding: 16, border: "1px solid #1a2a3a" }}>
          <ArcGauge value={state.memUsedMB} max={state.memTotalMB} label="VRAM" unit="MB" color="#aa66ff" />
        </div>
        <div style={{ background: "#0d1520", borderRadius: 10, padding: 16, border: "1px solid #1a2a3a" }}>
          <ArcGauge value={state.tempC} max={95} label="TEMP" unit="°C" color={state.tempC > 75 ? "#ff4444" : state.tempC > 60 ? "#ffaa22" : "#00ff88"} />
        </div>
        <div style={{ background: "#0d1520", borderRadius: 10, padding: 16, border: "1px solid #1a2a3a" }}>
          <ArcGauge value={state.powerDraw} max={state.powerLimit} label="POWER" unit="W" color="#ff8844" />
        </div>
      </div>

      {/* Charts Row */}
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 16,
        marginBottom: 20,
      }}>
        {[
          { data: history.gpu, color: "#00ccff", label: "GPU Utilization", max: 100, suffix: "%" },
          { data: history.temp, color: "#ff8844", label: "Temperature", max: 95, suffix: "°C" },
        ].map((ch, i) => (
          <div key={i} style={{ background: "#0d1520", borderRadius: 10, padding: 16, border: "1px solid #1a2a3a" }}>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
              <span style={{ fontSize: 11, color: "#5a7a9a", letterSpacing: "0.5px" }}>{ch.label}</span>
              <span style={{ fontSize: 11, color: ch.color }}>{ch.data.length ? ch.data[ch.data.length - 1] : 0}{ch.suffix}</span>
            </div>
            <MiniChart data={ch.data} color={ch.color} height={50} width={340} max={ch.max} />
          </div>
        ))}
      </div>

      {/* Controls + Log */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        {/* Controls */}
        <div style={{ background: "#0d1520", borderRadius: 10, padding: 20, border: "1px solid #1a2a3a" }}>
          <div style={{ fontSize: 12, color: "#5a7a9a", marginBottom: 16, letterSpacing: "1px" }}>CONTROLS</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <button
              onClick={handleBoost}
              disabled={boosted || transitioning}
              style={{
                padding: "12px 20px", border: "1px solid #00ff8844", borderRadius: 8,
                background: boosted ? "#00ff8811" : "#00ff8822",
                color: boosted ? "#00ff8866" : "#00ff88",
                fontSize: 13, fontWeight: 600, cursor: boosted ? "default" : "pointer",
                fontFamily: "inherit", letterSpacing: "1px",
                transition: "all 0.2s",
                opacity: boosted || transitioning ? 0.5 : 1,
              }}
            >
              ▲ FORCE P0 BOOST
            </button>
            <button
              onClick={handleReset}
              disabled={!boosted || transitioning}
              style={{
                padding: "12px 20px", border: "1px solid #ff884444", borderRadius: 8,
                background: !boosted ? "#ff884411" : "#ff884422",
                color: !boosted ? "#ff884466" : "#ff8844",
                fontSize: 13, fontWeight: 600, cursor: !boosted ? "default" : "pointer",
                fontFamily: "inherit", letterSpacing: "1px",
                transition: "all 0.2s",
                opacity: !boosted || transitioning ? 0.5 : 1,
              }}
            >
              ▼ RESET TO DEFAULT
            </button>
            <button
              onClick={toggleAuto}
              style={{
                padding: "12px 20px",
                border: `1px solid ${autoMode ? "#aa66ff44" : "#4a6a8a44"}`,
                borderRadius: 8,
                background: autoMode ? "#aa66ff22" : "#1a2a3a",
                color: autoMode ? "#aa66ff" : "#6a8aaa",
                fontSize: 13, fontWeight: 600, cursor: "pointer",
                fontFamily: "inherit", letterSpacing: "1px",
                transition: "all 0.2s",
              }}
            >
              {autoMode ? "◉ AUTO MODE ON" : "○ AUTO MODE OFF"}
            </button>
            {autoMode && (
              <div style={{
                fontSize: 10, color: lmStudioDetected ? "#00ff88" : "#5a7a9a",
                padding: "6px 12px", background: "#0a0e14", borderRadius: 6,
                textAlign: "center",
              }}>
                {lmStudioDetected ? "● LM Studio detected" : "○ Watching for LM Studio..."}
              </div>
            )}
          </div>

          {/* Command reference */}
          <div style={{ marginTop: 20, fontSize: 10, color: "#3a5a7a" }}>
            <div style={{ marginBottom: 6, color: "#5a7a9a", letterSpacing: "0.5px" }}>POWERSHELL COMMANDS</div>
            <div style={{ fontFamily: "inherit", lineHeight: 1.8 }}>
              <div><span style={{ color: "#6a8aaa" }}>.\gpu-force-boost.ps1</span> <span style={{ color: "#00ccff" }}>-Mode boost</span></div>
              <div><span style={{ color: "#6a8aaa" }}>.\gpu-force-boost.ps1</span> <span style={{ color: "#ff8844" }}>-Mode reset</span></div>
              <div><span style={{ color: "#6a8aaa" }}>.\gpu-force-boost.ps1</span> <span style={{ color: "#aa66ff" }}>-Mode auto</span></div>
              <div><span style={{ color: "#6a8aaa" }}>.\gpu-force-boost.ps1</span> <span style={{ color: "#00ff88" }}>-Mode monitor</span></div>
            </div>
          </div>
        </div>

        {/* Log */}
        <div style={{ background: "#0d1520", borderRadius: 10, padding: 20, border: "1px solid #1a2a3a" }}>
          <div style={{ fontSize: 12, color: "#5a7a9a", marginBottom: 12, letterSpacing: "1px" }}>EVENT LOG</div>
          <div style={{
            maxHeight: 280, overflowY: "auto", fontSize: 11, lineHeight: 1.8,
          }}>
            {logs.map((log, i) => (
              <div key={i} style={{ display: "flex", gap: 8 }}>
                <span style={{ color: "#3a5a7a", flexShrink: 0 }}>{log.time}</span>
                <span style={{
                  color: log.type === "success" ? "#00ff88"
                    : log.type === "warn" ? "#ff8844"
                    : log.type === "error" ? "#ff3344"
                    : "#6a8aaa",
                }}>
                  {log.msg}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Footer */}
      <div style={{
        marginTop: 20, textAlign: "center",
        fontSize: 10, color: "#2a3a4a", letterSpacing: "1px",
      }}>
        GPU FORCE BOOST • SIMULATED DASHBOARD • USE POWERSHELL SCRIPT FOR REAL CONTROL
      </div>
    </div>
  );
}

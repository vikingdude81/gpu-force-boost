# GPU Force Boost

Force your NVIDIA RTX A2000 (or any NVIDIA GPU) to maximum performance state (P0) for LLM inference with LM Studio.

## Files

| File | Purpose |
|------|---------|
| `gpu-force-boost.ps1` | CLI script — boost, reset, monitor, auto-watch modes |
| `api-server.ps1` | HTTP server (port 3001) — serves the dashboard and wraps nvidia-smi |
| `index.html` | React dashboard — live GPU stats, boost/reset buttons, auto mode |
| `gpu-force-boost-dashboard.jsx` | React component source (reference / dev use) |

## Requirements

- Windows 10/11
- NVIDIA GPU with drivers installed (`nvidia-smi` must be accessible)
- Administrator rights (scripts auto-elevate via UAC)

## Usage

### CLI

```powershell
# Check current GPU state
.\gpu-force-boost.ps1 -Mode status

# Force P0 max boost immediately
.\gpu-force-boost.ps1 -Mode boost

# Live terminal monitor
.\gpu-force-boost.ps1 -Mode monitor

# Auto-watch: boost when LM Studio opens, reset when it closes
.\gpu-force-boost.ps1 -Mode auto -WatchProcess "LM Studio"

# Reset clocks back to default
.\gpu-force-boost.ps1 -Mode reset
```

### Dashboard (browser UI)

```powershell
.\api-server.ps1
```

Opens `http://localhost:3001` automatically — live gauges, boost/reset buttons, event log, auto mode.

## How it works

- **Clock locking** — uses `nvidia-smi -lgc` / `-lmc` to pin GPU and memory clocks to maximum
- **Persistence mode** — keeps the driver loaded so there's no spin-up lag
- **Auto-boost off** — disables NVIDIA's auto-boost so clocks don't drift down
- **P-state** — P0 activates automatically once the GPU has a workload (LM Studio loading a model). Locked clocks mean it stays at max the entire time.

## Notes

RTX A2000 Desktop: Boost 1200 MHz / Memory 6144 MHz (GDDR6)  
RTX A2000 Laptop: Boost 1552 MHz / Memory 6001 MHz (GDDR6)

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

- **TCC mode** — for GPUs not driving a display (like a dedicated compute card), switching from WDDM to TCC gives full control over P-states, clock locks, and persistence mode. Without TCC, Windows WDDM overrides nvidia-smi clock commands.
- **Clock locking** — uses `nvidia-smi -lgc` / `-lmc` to pin GPU and memory clocks to maximum
- **Persistence mode** — keeps the driver loaded so there's no spin-up lag (TCC only)
- **P-state** — P0 activates when the GPU has a workload. Locked clocks mean it stays at max the entire time.

## TCC Mode (recommended for compute-only GPUs)

If your GPU is **not driving a display** (headless server, remote desktop, dedicated inference card), switch to TCC for proper clock control:

```powershell
# Switch to TCC (admin required, reboot required)
nvidia-smi -i 0 -dm 1

# Switch back to WDDM if needed
nvidia-smi -i 0 -dm 0
```

**Why TCC?** On WDDM (Windows Display Driver Model), Windows controls GPU power states and ignores `nvidia-smi -lgc` lock commands. TCC removes this layer, giving nvidia-smi full authority over clock speeds, persistence mode, and P-state transitions.

## Notes

RTX A2000 12GB Desktop: Max Boost 2100 MHz / Memory 6001 MHz (GDDR6)

**Supported GPUs:** Any NVIDIA GPU with `nvidia-smi` support. TCC mode is available on Quadro, RTX A-series, Tesla, and some GeForce cards (check `nvidia-smi -q` for `TCC Supported`).

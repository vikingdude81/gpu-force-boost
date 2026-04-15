# GPU Force Boost

Tune your NVIDIA RTX A2000 (or any NVIDIA GPU) for high sustained performance during LLM inference with LM Studio.

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

# Apply boost profile immediately
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
- **Clock locking** — uses `nvidia-smi -lgc` / `-lmc` to request high sustained clocks
- **Persistence mode** — keeps the driver loaded so there's no spin-up lag (TCC only)
- **P-state** — idle can still show P8/P5. Under real compute load, healthy sustained performance is typically P0/P1/P2 depending on power/thermal limits.

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

## Known Good Config (March 2026)

- GPU: NVIDIA RTX A2000 12GB (device id `10DE-2571`)
- OS: Windows 11 Pro
- Driver: NVIDIA Production Branch / Studio `595.97` (**minimum required**)
- Driver model: `TCC`
- Board power limit: `70W`
- Registry: `EnableDriverControlledPMM = 0`, no PowerMizer override keys
- Typical sustained load behavior: `P2`, memory around `5701 MHz`, core around `1050-1200 MHz`, SW power cap active near `68-70W`

This behavior is normal for sustained inference on a 70W board. Idle may still show low clocks (P8/P5).

## Troubleshooting: GPU stuck at P8/420MHz under load (2 tok/s)

**Symptom:** GPU shows 100% utilization but clocks stay at 420 MHz / 405 MHz memory and draws only ~19W. Tokens per second at ~2.

**Root cause:** Driver 595.79 and earlier have a regression that breaks P-state transitions in TCC mode. Even with `nvidia-smi -lgc/-lmc` or NVML clock lock calls returning "success", clocks do not change. The GPU computes at idle-speed clocks.

**Fix:**
1. Update to driver **595.97 or newer** from [nvidia.com/drivers](https://www.nvidia.com/drivers) (select RTX A-Series → A2000 12GB → Windows 11 → Studio/Data Center)
2. After install + reboot, verify driver with `nvidia-smi --query-gpu=driver_version --format=csv,noheader`
3. Then run `.\gpu-force-boost.ps1 -Mode fix` to restore registry and lock clocks

**Registry state for TCC mode:**
- `EnableDriverControlledPMM = 0` — lets TCC subsystem manage P-states natively. Setting this to `1` enables the driver's conservative PMM which applies SW_POWER_CAP at ~20W, preventing clock boost.
- All PowerMizer keys (`PerfLevelSrc`, `PowerMizerEnable`, etc.) must be **absent** in TCC mode.
- Run `.\gpu-force-boost.ps1 -Mode fix` (uses `-RegProfile tcc` by default) to apply this.

## Troubleshooting: PCIe Link Stuck at Gen1 (April 2026)

**Symptom:** GPU at P8/420MHz under 100% compute load, 25W draw with 70W limit, zero throttle reasons active, clock locks accepted but ignored. NVML shows `PCIe: Gen1 x16` instead of `Gen3 x16` under load.

**Diagnosis:** Run `python nvml-deep-diag.py` (or `post-reboot-diag.cmd` as admin) and check:
- `PCIe: Gen1 x16 (max: Gen3 x16)` = PCIe link not negotiating up under load
- This correlates with the GPU refusing to transition out of P8

**Root cause:** BIOS PCIe slot speed set to Auto with broken negotiation, or chipset power management overriding link speed.

**Fix (Gigabyte B550 GAMING X V2):**
1. Enter BIOS (press DEL at boot)
2. Settings → IO Ports → PCIEX16 Slot Speed → change from Auto to **Gen3**
3. Also check: AMD CBS → NBIO Common Options → PCIe Link Speed → **Gen3**
4. Save and reboot

**Diagnostic files:**
- `nvml-deep-diag.py` — comprehensive NVML diagnostic (clocks, PCIe, power, throttle reasons)
- `post-reboot-diag.cmd` — run as admin after reboot: applies clocks, runs load, checks PCIe
- `pcie-diag-result.txt` — detailed findings from April 13, 2026

## Throughput Snapshot (Before vs After)

- Qwen 9B: about `2 tok/s` to about `14 tok/s`
- Small 0.8B model: about `8 tok/s` to about `142 tok/s`

These gains came from restoring proper compute boost behavior (TCC mode + driver 595.97+ + correct registry), not from forcing permanent P0 at idle.

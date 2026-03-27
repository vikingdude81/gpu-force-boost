"""Direct NVML test - bypass nvidia-smi to force GPU performance state"""
try:
    import pynvml
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pynvml", "-q"])
    import pynvml

pynvml.nvmlInit()
print(f"NVML version: {pynvml.nvmlSystemGetDriverVersion()}")
print(f"GPU count: {pynvml.nvmlDeviceGetCount()}")

handle = pynvml.nvmlDeviceGetHandleByIndex(0)
name = pynvml.nvmlDeviceGetName(handle)
print(f"GPU 0: {name}")

# Current clocks
info = pynvml.nvmlDeviceGetClockInfo(handle, pynvml.NVML_CLOCK_GRAPHICS)
mem = pynvml.nvmlDeviceGetClockInfo(handle, pynvml.NVML_CLOCK_MEM)
print(f"Current clocks: GPU={info} MHz, Mem={mem} MHz")

# Max clocks
max_gr = pynvml.nvmlDeviceGetMaxClockInfo(handle, pynvml.NVML_CLOCK_GRAPHICS)
max_mem = pynvml.nvmlDeviceGetMaxClockInfo(handle, pynvml.NVML_CLOCK_MEM)
print(f"Max clocks: GPU={max_gr} MHz, Mem={max_mem} MHz")

# Performance state
pstate = pynvml.nvmlDeviceGetPerformanceState(handle)
print(f"Performance state: P{pstate}")

# Power state
power = pynvml.nvmlDeviceGetPowerUsage(handle)
print(f"Power draw: {power/1000:.1f}W")

# Try to get supported clocks
print("\nSupported memory clocks:")
try:
    mem_clocks = pynvml.nvmlDeviceGetSupportedMemoryClocks(handle)
    for mc in list(mem_clocks)[:5]:
        print(f"  {mc} MHz")
        try:
            gr_clocks = pynvml.nvmlDeviceGetSupportedGraphicsClocks(handle, mc)
            print(f"    Graphics clocks: {list(gr_clocks)[:5]}...")
        except:
            pass
except Exception as e:
    print(f"  Error: {e}")

# Try setting application clocks via NVML
print("\nAttempting to set GPU clocks via NVML...")
try:
    pynvml.nvmlDeviceSetApplicationsClocks(handle, max_mem, max_gr)
    print(f"  Set application clocks to GPU={max_gr}, Mem={max_mem}")
except Exception as e:
    print(f"  SetApplicationsClocks failed: {e}")

try:
    pynvml.nvmlDeviceSetGpuLockedClocks(handle, max_gr, max_gr)
    print(f"  Set locked GPU clocks to {max_gr}-{max_gr}")
except Exception as e:
    print(f"  SetGpuLockedClocks failed: {e}")

try:
    pynvml.nvmlDeviceSetMemoryLockedClocks(handle, max_mem, max_mem)
    print(f"  Set locked mem clocks to {max_mem}-{max_mem}")
except Exception as e:
    print(f"  SetMemoryLockedClocks failed: {e}")

# Check power management mode
try:
    pm = pynvml.nvmlDeviceGetPowerManagementMode(handle)
    print(f"\nPower management mode: {pm}")
except Exception as e:
    print(f"\nPower management mode: {e}")

# Try setting persistence mode
try:
    pynvml.nvmlDeviceSetPersistenceMode(handle, 1)
    print("Persistence mode: SET to ENABLED")
except Exception as e:
    print(f"Persistence mode set failed: {e}")

# Check GPU operation mode  
try:
    current, pending = pynvml.nvmlDeviceGetGpuOperationMode(handle)
    modes = {0: "ALL_ON", 1: "COMPUTE", 2: "LOW_DP"}
    print(f"GPU Operation Mode: current={modes.get(current, current)}, pending={modes.get(pending, pending)}")
except Exception as e:
    print(f"GPU Operation Mode: {e}")

# Final state check
info2 = pynvml.nvmlDeviceGetClockInfo(handle, pynvml.NVML_CLOCK_GRAPHICS)
mem2 = pynvml.nvmlDeviceGetClockInfo(handle, pynvml.NVML_CLOCK_MEM)
pstate2 = pynvml.nvmlDeviceGetPerformanceState(handle)
print(f"\nFinal state: GPU={info2}MHz, Mem={mem2}MHz, P{pstate2}")

pynvml.nvmlShutdown()

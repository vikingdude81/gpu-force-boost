"""
Force GPU clocks via NVML API directly (bypassing nvidia-smi).
Also reports throttle reasons and lock state.
"""
import ctypes
import sys

try:
    from pynvml import *
except ImportError:
    print("Installing pynvml...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pynvml", "-q"])
    from pynvml import *

def main():
    nvmlInit()
    count = nvmlDeviceGetCount()
    print(f"GPU count: {count}")

    handle = nvmlDeviceGetHandleByIndex(0)
    name = nvmlDeviceGetName(handle)
    print(f"GPU 0: {name}")

    # Current clocks
    gpu_clk = nvmlDeviceGetClockInfo(handle, NVML_CLOCK_GRAPHICS)
    mem_clk = nvmlDeviceGetClockInfo(handle, NVML_CLOCK_MEM)
    max_gpu = nvmlDeviceGetMaxClockInfo(handle, NVML_CLOCK_GRAPHICS)
    max_mem = nvmlDeviceGetMaxClockInfo(handle, NVML_CLOCK_MEM)
    print(f"\nCurrent clocks:  GPU={gpu_clk} MHz  MEM={mem_clk} MHz")
    print(f"Max clocks:      GPU={max_gpu} MHz  MEM={max_mem} MHz")

    # Performance state
    pstate = nvmlDeviceGetPerformanceState(handle)
    print(f"Performance state: P{pstate}")

    # Power info
    try:
        power = nvmlDeviceGetPowerUsage(handle) / 1000.0
        power_limit = nvmlDeviceGetPowerManagementLimit(handle) / 1000.0
        power_default = nvmlDeviceGetPowerManagementLimitConstraints(handle)
        print(f"Power: {power:.1f}W / {power_limit:.0f}W (min={power_default[0]/1000:.0f}W max={power_default[1]/1000:.0f}W)")
    except NVMLError as e:
        print(f"Power query: {e}")

    # Throttle reasons
    try:
        reasons = nvmlDeviceGetCurrentClocksThrottleReasons(handle)
        print(f"\nThrottle reasons bitmask: 0x{reasons:016x}")
        flags = {
            0x0000000000000001: "GPU_IDLE",
            0x0000000000000002: "APPLICATIONS_CLOCKS_SETTING",
            0x0000000000000004: "SW_POWER_CAP",
            0x0000000000000008: "HW_SLOWDOWN",
            0x0000000000000010: "SYNC_BOOST",
            0x0000000000000020: "SW_THERMAL_SLOWDOWN",
            0x0000000000000040: "HW_THERMAL_SLOWDOWN",
            0x0000000000000080: "HW_POWER_BRAKE_SLOWDOWN",
            0x0000000000000100: "DISPLAY_CLOCK_SETTING",
        }
        active = []
        for bit, label in flags.items():
            if reasons & bit:
                active.append(label)
        if active:
            print(f"Active: {', '.join(active)}")
        else:
            print("No throttle reasons active")
    except NVMLError as e:
        print(f"Throttle query: {e}")

    # Supported clocks
    print("\n--- Supported memory clocks ---")
    try:
        mem_clocks = nvmlDeviceGetSupportedMemoryClocks(handle)
        print(f"Supported mem clocks: {list(mem_clocks)}")
    except NVMLError as e:
        print(f"  Error: {e}")

    # Try getting supported GPU clocks for current and max memory
    for mc in [405, 6001]:
        try:
            gpu_clocks = nvmlDeviceGetSupportedGraphicsClocks(handle, mc)
            gpu_list = list(gpu_clocks)
            print(f"GPU clocks at mem={mc}MHz: [{gpu_list[0]}..{gpu_list[-1]}] ({len(gpu_list)} levels)")
        except NVMLError as e:
            print(f"GPU clocks at mem={mc}MHz: {e}")

    # ---- TRY TO FORCE CLOCKS VIA NVML ----
    print("\n=== ATTEMPTING NVML CLOCK FORCE ===")

    # 1. Try setting GPU clock range
    print("\n1. Setting GPU clock range to max...")
    try:
        nvmlDeviceSetGpuLockedClocks(handle, max_gpu, max_gpu)
        print(f"   SUCCESS: GPU locked to {max_gpu} MHz")
    except NVMLError as e:
        print(f"   FAILED: {e}")

    # 2. Try setting memory clock range  
    print("2. Setting MEM clock range to max...")
    try:
        nvmlDeviceSetMemoryLockedClocks(handle, max_mem, max_mem)
        print(f"   SUCCESS: MEM locked to {max_mem} MHz")
    except NVMLError as e:
        print(f"   FAILED: {e}")

    # 3. Try setting power limit
    print("3. Setting power limit to max...")
    try:
        constraints = nvmlDeviceGetPowerManagementLimitConstraints(handle)
        max_power = constraints[1]
        nvmlDeviceSetPowerManagementLimit(handle, max_power)
        print(f"   SUCCESS: Power limit set to {max_power/1000:.0f}W")
    except NVMLError as e:
        print(f"   FAILED: {e}")

    # 4. Try application clocks
    print("4. Setting application clocks...")
    try:
        nvmlDeviceSetApplicationsClocks(handle, max_mem, max_gpu)
        print(f"   SUCCESS: App clocks set to mem={max_mem} gpu={max_gpu}")
    except NVMLError as e:
        print(f"   FAILED: {e}")

    # 5. Try persistence mode
    print("5. Setting persistence mode...")
    try:
        nvmlDeviceSetPersistenceMode(handle, 1)
        print("   SUCCESS: Persistence mode ON")
    except NVMLError as e:
        print(f"   FAILED: {e}")

    # 6. Try setting power state (P0)
    print("6. Trying to query/set auto boosted clocks...")
    try:
        auto_boost = nvmlDeviceGetAutoBoostedClocksEnabled(handle)
        print(f"   Auto boost: isEnabled={auto_boost[0]}, defaultEnabled={auto_boost[1]}")
    except NVMLError as e:
        print(f"   Auto boost query: {e}")
    try:
        nvmlDeviceSetAutoBoostedClocksEnabled(handle, 1)
        print("   Auto boost SET to enabled")
    except NVMLError as e:
        print(f"   Auto boost set: {e}")

    # Wait and re-check
    import time
    print("\nWaiting 2 seconds for state transition...")
    time.sleep(2)

    gpu_clk2 = nvmlDeviceGetClockInfo(handle, NVML_CLOCK_GRAPHICS)
    mem_clk2 = nvmlDeviceGetClockInfo(handle, NVML_CLOCK_MEM)
    pstate2 = nvmlDeviceGetPerformanceState(handle)
    try:
        power2 = nvmlDeviceGetPowerUsage(handle) / 1000.0
    except:
        power2 = 0
    try:
        reasons2 = nvmlDeviceGetCurrentClocksThrottleReasons(handle)
    except:
        reasons2 = -1

    print(f"\n=== AFTER LOCK ===")
    print(f"Clocks: GPU={gpu_clk2} MHz  MEM={mem_clk2} MHz")
    print(f"PState: P{pstate2}")
    print(f"Power: {power2:.1f}W")
    print(f"Throttle reasons: 0x{reasons2:016x}")

    if gpu_clk2 > gpu_clk or mem_clk2 > mem_clk:
        print(">>> CLOCKS IMPROVED! <<<")
    else:
        print(">>> CLOCKS UNCHANGED - hardware is not responding to lock commands <<<")

    nvmlShutdown()

if __name__ == "__main__":
    main()

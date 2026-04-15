"""Deep NVML diagnostic - query all power/clock state and attempt direct clock control"""
import pynvml as nvml

nvml.nvmlInit()
handle = nvml.nvmlDeviceGetHandleByIndex(0)
name = nvml.nvmlDeviceGetName(handle)
print(f"GPU: {name}")

# Performance state
pstate = nvml.nvmlDeviceGetPerformanceState(handle)
print(f"P-State: P{pstate}")

# Power management mode
try:
    pm_mode = nvml.nvmlDeviceGetPowerManagementMode(handle)
    print(f"Power Management Mode: {'Enabled' if pm_mode == 1 else 'Disabled'}")
except Exception as e:
    print(f"Power Management Mode: {e}")

# Power management limit
try:
    pl = nvml.nvmlDeviceGetPowerManagementLimit(handle)
    print(f"Power Limit: {pl/1000:.0f}W")
except Exception as e:
    print(f"Power Limit: {e}")

# Enforced power limit
try:
    epl = nvml.nvmlDeviceGetEnforcedPowerLimit(handle)
    print(f"Enforced Power Limit: {epl/1000:.0f}W")
except Exception as e:
    print(f"Enforced Power Limit: {e}")

# Current clocks
for ct in [nvml.NVML_CLOCK_GRAPHICS, nvml.NVML_CLOCK_SM, nvml.NVML_CLOCK_MEM, nvml.NVML_CLOCK_VIDEO]:
    names = {0:'Graphics', 1:'SM', 2:'Memory', 3:'Video'}
    try:
        cur = nvml.nvmlDeviceGetClockInfo(handle, ct)
        mx = nvml.nvmlDeviceGetMaxClockInfo(handle, ct)
        print(f"Clock {names[ct]}: current={cur}MHz, max={mx}MHz")
    except Exception as e:
        print(f"Clock {names[ct]}: {e}")

# Application clocks
try:
    app_gr = nvml.nvmlDeviceGetApplicationsClock(handle, nvml.NVML_CLOCK_GRAPHICS)
    app_mem = nvml.nvmlDeviceGetApplicationsClock(handle, nvml.NVML_CLOCK_MEM)
    print(f"Applications Clocks: Graphics={app_gr}MHz, Memory={app_mem}MHz")
except Exception as e:
    print(f"Applications Clocks: {e}")

# GPU Operation Mode
try:
    current_gom, pending_gom = nvml.nvmlDeviceGetGpuOperationMode(handle)
    gom_names = {0:'All On', 1:'Compute', 2:'Low DP'}
    print(f"GPU Operation Mode: current={gom_names.get(current_gom, current_gom)}, pending={gom_names.get(pending_gom, pending_gom)}")
except Exception as e:
    print(f"GPU Operation Mode: {e}")

# Compute mode
try:
    cm = nvml.nvmlDeviceGetComputeMode(handle)
    cm_names = {0:'Default', 1:'Exclusive Thread', 2:'Prohibited', 3:'Exclusive Process'}
    print(f"Compute Mode: {cm_names.get(cm, cm)}")
except Exception as e:
    print(f"Compute Mode: {e}")

# Driver model
try:
    current_dm, pending_dm = nvml.nvmlDeviceGetDriverModel(handle)
    dm_names = {0:'WDDM', 1:'TCC'}
    print(f"Driver Model: current={dm_names.get(current_dm, current_dm)}, pending={dm_names.get(pending_dm, pending_dm)}")
except Exception as e:
    print(f"Driver Model: {e}")

# Utilization
try:
    util = nvml.nvmlDeviceGetUtilizationRates(handle)
    print(f"Utilization: GPU={util.gpu}%, Memory={util.memory}%")
except Exception as e:
    print(f"Utilization: {e}")

# Power draw
try:
    pw = nvml.nvmlDeviceGetPowerUsage(handle)
    print(f"Power Draw: {pw/1000:.1f}W")
except Exception as e:
    print(f"Power Draw: {e}")

# Throttle reasons
try:
    throttle = nvml.nvmlDeviceGetCurrentClocksThrottleReasons(handle)
    print(f"Throttle Reasons (raw): 0x{throttle:016x}")
    reasons = {
        0x0000000000000001: "GpuIdle",
        0x0000000000000002: "ApplicationsClocksSetting",
        0x0000000000000004: "SwPowerCap",
        0x0000000000000008: "HwSlowdown",
        0x0000000000000010: "SyncBoost",
        0x0000000000000020: "SwThermalSlowdown",
        0x0000000000000040: "HwThermalSlowdown",
        0x0000000000000080: "HwPowerBrakeSlowdown",
        0x0000000000000100: "DisplayClockSetting",
    }
    for mask, name in reasons.items():
        if throttle & mask:
            print(f"  ACTIVE: {name}")
    if throttle == 0:
        print("  No throttle reasons active")
except Exception as e:
    print(f"Throttle Reasons: {e}")

# Supported throttle reasons
try:
    supported = nvml.nvmlDeviceGetSupportedClocksThrottleReasons(handle)
    print(f"Supported Throttle Reasons: 0x{supported:016x}")
except Exception as e:
    print(f"Supported Throttle Reasons: {e}")

# Try to set GPU locked clocks via NVML
print("\n--- Attempting NVML clock control ---")
try:
    nvml.nvmlDeviceSetGpuLockedClocks(handle, 210, 2100)
    print("nvmlDeviceSetGpuLockedClocks(210, 2100): SUCCESS")
except Exception as e:
    print(f"nvmlDeviceSetGpuLockedClocks: {e}")

try:
    nvml.nvmlDeviceSetMemoryLockedClocks(handle, 6001, 6001)
    print("nvmlDeviceSetMemoryLockedClocks(6001, 6001): SUCCESS")
except Exception as e:
    print(f"nvmlDeviceSetMemoryLockedClocks: {e}")

# Try setting applications clocks
try:
    nvml.nvmlDeviceSetApplicationsClocks(handle, 6001, 2100)
    print("nvmlDeviceSetApplicationsClocks(6001, 2100): SUCCESS")
except Exception as e:
    print(f"nvmlDeviceSetApplicationsClocks: {e}")

# Try setting power management limit to max
try:
    nvml.nvmlDeviceSetPowerManagementLimit(handle, 70000)
    print("nvmlDeviceSetPowerManagementLimit(70000): SUCCESS")
except Exception as e:
    print(f"nvmlDeviceSetPowerManagementLimit: {e}")

# Try setting compute mode to exclusive process (sometimes forces higher perf)
try:
    nvml.nvmlDeviceSetComputeMode(handle, nvml.NVML_COMPUTEMODE_EXCLUSIVE_PROCESS)
    print("nvmlDeviceSetComputeMode(EXCLUSIVE_PROCESS): SUCCESS")
except Exception as e:
    print(f"nvmlDeviceSetComputeMode(EXCLUSIVE_PROCESS): {e}")

# Check supported/available memory clocks
print("\n--- Supported Memory Clocks ---")
try:
    mem_clocks = nvml.nvmlDeviceGetSupportedMemoryClocks(handle)
    for mc in mem_clocks[:5]:
        print(f"  Memory: {mc} MHz")
        try:
            gr_clocks = nvml.nvmlDeviceGetSupportedGraphicsClocks(handle, mc)
            print(f"    Graphics range: {gr_clocks[-1]}-{gr_clocks[0]} MHz ({len(gr_clocks)} steps)")
        except Exception as e:
            print(f"    Graphics: {e}")
except Exception as e:
    print(f"Supported Memory Clocks: {e}")

# Check PCIe link info
print("\n--- PCIe Info ---")
try:
    gen = nvml.nvmlDeviceGetCurrPcieLinkGeneration(handle)
    width = nvml.nvmlDeviceGetCurrPcieLinkWidth(handle)
    max_gen = nvml.nvmlDeviceGetMaxPcieLinkGeneration(handle)
    max_width = nvml.nvmlDeviceGetMaxPcieLinkWidth(handle)
    print(f"PCIe: Gen{gen} x{width} (max: Gen{max_gen} x{max_width})")
except Exception as e:
    print(f"PCIe: {e}")

# Persistence mode
try:
    pm = nvml.nvmlDeviceGetPersistenceMode(handle)
    print(f"Persistence Mode: {'Enabled' if pm == 1 else 'Disabled'}")
except Exception as e:
    print(f"Persistence Mode: {e}")

nvml.nvmlShutdown()

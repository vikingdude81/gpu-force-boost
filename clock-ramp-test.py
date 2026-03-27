"""
Test if GPU can naturally boost under compute load WITHOUT any clock locks.
This checks if the GPU hardware itself is capable of ramping clocks.
"""
import time
import sys
import subprocess

try:
    import torch
except ImportError:
    print("PyTorch not available")
    sys.exit(1)

try:
    from pynvml import *
    nvmlInit()
    handle = nvmlDeviceGetHandleByIndex(0)
    has_nvml = True
except:
    has_nvml = False

def gpu_stats():
    if not has_nvml:
        return "N/A"
    gpu_clk = nvmlDeviceGetClockInfo(handle, NVML_CLOCK_GRAPHICS)
    mem_clk = nvmlDeviceGetClockInfo(handle, NVML_CLOCK_MEM)
    pstate = nvmlDeviceGetPerformanceState(handle)
    try:
        power = nvmlDeviceGetPowerUsage(handle) / 1000.0
    except:
        power = 0
    try:
        reasons = nvmlDeviceGetCurrentClocksThrottleReasons(handle)
    except:
        reasons = -1
    return f"GPU={gpu_clk}MHz MEM={mem_clk}MHz P{pstate} {power:.1f}W throttle=0x{reasons:04x}"

# First reset all locks
print("=== RESETTING ALL LOCKS ===")
subprocess.run(["nvidia-smi", "-i", "0", "-rgc"], capture_output=True)
subprocess.run(["nvidia-smi", "-i", "0", "-rmc"], capture_output=True)
subprocess.run(["nvidia-smi", "-i", "0", "-rac"], capture_output=True)
time.sleep(1)

print(f"Before load: {gpu_stats()}")
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"CUDA device: {torch.cuda.get_device_name(0)}")

# Create a sustained compute workload
print("\n=== STARTING COMPUTE LOAD ===")
device = torch.device("cuda:0")

# Warm up
torch.cuda.synchronize()
a = torch.randn(4096, 4096, device=device)
b = torch.randn(4096, 4096, device=device)
torch.cuda.synchronize()

print(f"After alloc:    {gpu_stats()}")

# Run matmuls and monitor clocks every second
for i in range(10):
    start = time.time()
    for _ in range(5):
        c = torch.mm(a, b)
    torch.cuda.synchronize()
    elapsed = time.time() - start
    stats = gpu_stats()
    print(f"Iteration {i+1:2d}: {stats}  (5x matmul in {elapsed:.2f}s)")

# Try a MUCH bigger workload
print("\n=== HEAVY LOAD (8192x8192) ===")
a2 = torch.randn(8192, 8192, device=device)
b2 = torch.randn(8192, 8192, device=device)
torch.cuda.synchronize()
print(f"After big alloc: {gpu_stats()}")

for i in range(5):
    start = time.time()
    c2 = torch.mm(a2, b2)
    torch.cuda.synchronize()
    elapsed = time.time() - start
    stats = gpu_stats()
    print(f"Heavy {i+1}: {stats}  (1x 8k matmul in {elapsed:.2f}s)")

# Now try WITH locks set
print("\n=== NOW APPLYING LOCKS DURING LOAD ===")
subprocess.run(["nvidia-smi", "-i", "0", "-lmc", "6001,6001"], capture_output=True)
time.sleep(0.5)
subprocess.run(["nvidia-smi", "-i", "0", "-lgc", "2100,2100"], capture_output=True)
time.sleep(0.5)
print(f"Locks set: {gpu_stats()}")

for i in range(5):
    start = time.time()
    c2 = torch.mm(a2, b2)
    torch.cuda.synchronize()
    elapsed = time.time() - start
    stats = gpu_stats()
    print(f"Locked heavy {i+1}: {stats}  (1x 8k matmul in {elapsed:.2f}s)")

if has_nvml:
    nvmlShutdown()
print("\nDone.")

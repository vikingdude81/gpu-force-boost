python -c "
import torch, time, subprocess, sys
from pynvml import *

nvmlInit()
h = nvmlDeviceGetHandleByIndex(0)

def stats():
    g = nvmlDeviceGetClockInfo(h, NVML_CLOCK_GRAPHICS)
    m = nvmlDeviceGetClockInfo(h, NVML_CLOCK_MEM)
    p = nvmlDeviceGetPerformanceState(h)
    pw = nvmlDeviceGetPowerUsage(h)/1000
    r = nvmlDeviceGetCurrentClocksThrottleReasons(h)
    return f'GPU={g}MHz MEM={m}MHz P{p} {pw:.1f}W throttle=0x{r:04x}'

print('Before load:', stats())
a = torch.randn(4096,4096,device='cuda')
b = torch.randn(4096,4096,device='cuda')
torch.cuda.synchronize()
print('After alloc:', stats())
for i in range(8):
    t=time.time()
    for _ in range(3): c=torch.mm(a,b)
    torch.cuda.synchronize()
    print(f'It {i+1}: {stats()}  ({time.time()-t:.2f}s)')
nvmlShutdown()
" 2>&1 | Out-File C:\Users\akbon\Downloads\files\clock-ramp-result.txt -Encoding utf8

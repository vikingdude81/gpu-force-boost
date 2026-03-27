import torch, time

d = torch.device('cuda')
print(f"GPU: {torch.cuda.get_device_name(0)}")

# Warm up
a = torch.randn(4096, 4096, device=d)
torch.mm(a, a)
torch.cuda.synchronize()

# Benchmark single matmul
times = []
for _ in range(10):
    torch.cuda.synchronize()
    t0 = time.time()
    b = torch.mm(a, a)
    torch.cuda.synchronize()
    t1 = time.time()
    times.append((t1 - t0) * 1000)

avg = sum(times) / len(times)
print(f"4096x4096 matmul avg: {avg:.1f}ms (over 10 runs)")
print(f"At 420MHz this would be ~5x slower than at 2100MHz")

# Sustained benchmark
a2 = torch.randn(8192, 8192, device=d)
torch.cuda.synchronize()
t0 = time.time()
for i in range(100):
    torch.mm(a2, a2)
torch.cuda.synchronize()
t1 = time.time()
print(f"100x 8192x8192 matmul: {(t1-t0)*1000:.0f}ms total, {(t1-t0)*10:.1f}ms avg")

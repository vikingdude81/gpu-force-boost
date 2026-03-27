import torch, time
d = torch.device('cuda')
print(f"Device: {torch.cuda.get_device_name(0)}")
print("Allocating 8192x8192 matrix...")
a = torch.randn(8192, 8192, device=d)
print("Running 5000 matmuls (this will take ~30s)...")
start = time.time()
for i in range(5000):
    torch.mm(a, a)
    if i % 500 == 0:
        torch.cuda.synchronize()
        print(f"  iteration {i}/5000")
torch.cuda.synchronize()
elapsed = time.time() - start
print(f"Done in {elapsed:.1f}s")

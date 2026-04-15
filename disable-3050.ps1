$out = @()

# 1. Disable the RTX 3050 (it's in error state anyway)
$out += "=== Disabling RTX 3050 ==="
$dev3050 = Get-PnpDevice | Where-Object { $_.FriendlyName -match "3050" } | Select-Object -First 1
if ($dev3050) {
    Disable-PnpDevice -InstanceId $dev3050.InstanceId -Confirm:$false -EA SilentlyContinue
    $out += "RTX 3050 disabled: $($dev3050.InstanceId)"
} else {
    $out += "RTX 3050 not found"
}

Start-Sleep -Seconds 2

# 2. Check A2000 status
$out += "=== A2000 status after 3050 disable ==="
$out += (nvidia-smi --query-gpu=driver_version,driver_model.current,pstate,clocks.gr,clocks.mem,power.draw --format=csv,noheader 2>&1 | Out-String)

# 3. Re-apply locks
$out += "=== Applying locks ==="
$out += (nvidia-smi -i 0 -lmc 6001,6001 2>&1 | Out-String)
$out += (nvidia-smi -i 0 -lgc 2100,2100 2>&1 | Out-String)

$out | Set-Content C:\Users\akbon\Downloads\files\dev-status.txt

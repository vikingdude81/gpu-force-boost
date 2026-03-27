$out = @()
# Find A2000 device
$dev = Get-PnpDevice | Where-Object { $_.FriendlyName -match 'A2000' }
if ($dev) {
    $out += "Found: $($dev.FriendlyName) - Status: $($dev.Status) - InstanceId: $($dev.InstanceId)"
    $out += "Disabling..."
    Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
    Start-Sleep 3
    $out += "Re-enabling..."
    Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false
    Start-Sleep 3
    $out += "Done. Checking nvidia-smi..."
    $smi = nvidia-smi -i 0 --query-gpu=pstate,clocks.gr,clocks.mem,power.draw --format=csv,noheader 2>&1
    $out += "Result: $smi"
} else {
    $out += "A2000 not found in PnP devices"
}
$out | Out-File C:\Users\akbon\Downloads\files\restart-gpu-result.txt -Encoding utf8

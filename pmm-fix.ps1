$out = @()
# Set EnableDriverControlledPMM=1
$base = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$regBase = $null
Get-ChildItem $base | Where-Object { $_.PSChildName -match "^\d{4}$" } | ForEach-Object {
    $d = (Get-ItemProperty $_.PSPath -Name DriverDesc -EA SilentlyContinue).DriverDesc
    if ($d -match "A2000") { $regBase = $_.PSPath }
}
$pmm = (Get-ItemProperty $regBase -Name EnableDriverControlledPMM -EA SilentlyContinue).EnableDriverControlledPMM
$out += "Before: PMM=$pmm"
Set-ItemProperty -Path $regBase -Name "EnableDriverControlledPMM" -Value 1 -Type DWord
$pmm2 = (Get-ItemProperty $regBase -Name EnableDriverControlledPMM).EnableDriverControlledPMM
$out += "After: PMM=$pmm2"
# PnP bounce
$dev = Get-PnpDevice | Where-Object { $_.FriendlyName -match "A2000" } | Select-Object -First 1
$out += "Disabling $($dev.InstanceId)..."
Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -EA SilentlyContinue
Start-Sleep -Seconds 4
$out += "Re-enabling..."
Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -EA SilentlyContinue
Start-Sleep -Seconds 5
$out += (nvidia-smi --query-gpu=driver_version,pstate,clocks.gr,clocks.mem,power.draw --format=csv,noheader 2>&1 | Out-String)
# Apply locks
$out += (nvidia-smi -i 0 -lmc 6001,6001 2>&1 | Out-String)
$out += (nvidia-smi -i 0 -lgc 2100,2100 2>&1 | Out-String)
$out += (nvidia-smi --query-gpu=pstate,clocks.gr,clocks.mem --format=csv,noheader 2>&1 | Out-String)
$out | Set-Content C:\Users\akbon\Downloads\files\dev-status.txt

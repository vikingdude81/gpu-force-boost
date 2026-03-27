$out = @()
$out += "Reinstalling active NVIDIA display INF (oem27.inf)..."
$infPath = "$env:windir\INF\oem27.inf"
if (Test-Path $infPath) {
    $res = pnputil /add-driver $infPath /install 2>&1 | Out-String
    $out += $res
} else {
    $out += "INF not found: $infPath"
}
Start-Sleep 5
$out += ""
$out += "nvidia-smi after reinstall:"
$out += (nvidia-smi 2>&1 | Out-String)
$out | Out-File C:\Users\akbon\Downloads\files\dev-status.txt -Encoding utf8

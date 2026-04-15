Set-Location "C:\Users\akbon\Downloads\files"
$out = @()
$out += "=== START $(Get-Date) ==="
$out += "Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))"
$out += ""
$out += ">>> Set power limit to 68W"
$out += (nvidia-smi -i 0 -pl 68 2>&1 | Out-String)
$out += (nvidia-smi -i 0 --query-gpu=pstate,clocks.gr,clocks.mem,power.draw,power.limit --format=csv,noheader 2>&1 | Out-String)
$out += ""
$out += ">>> 20s load sample at 68W"
$p = Start-Process python -ArgumentList '.\gpu-load-test.py' -PassThru
for($i=1; $i -le 20; $i++){
  $line = nvidia-smi -i 0 --query-gpu=pstate,clocks.gr,clocks.mem,utilization.gpu,power.draw,power.limit,clocks_throttle_reasons.active --format=csv,noheader
  $out += ("[{0:00}] " -f $i) + $line
  Start-Sleep -Seconds 1
}
if(-not $p.HasExited){ Stop-Process -Id $p.Id -Force }
$out += ""
$out += ">>> Restore power limit to 70W"
$out += (nvidia-smi -i 0 -pl 70 2>&1 | Out-String)
$out += (nvidia-smi -i 0 --query-gpu=pstate,clocks.gr,clocks.mem,power.draw,power.limit --format=csv,noheader 2>&1 | Out-String)
$out += "=== END $(Get-Date) ==="
$out | Out-File .\powerlimit-68-result.txt -Encoding utf8

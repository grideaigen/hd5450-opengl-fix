# === fix_ogl.ps1: прямой ICD + регистрации + перезапуск драйвера ===
$class = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
foreach ($k in "0000","0003","0001","0002") {
  if (Test-Path "$class\$k") {
    Set-ItemProperty "$class\$k" -Name OpenGLDriverName    -Value "atio6axx.dll" -ErrorAction SilentlyContinue
    Set-ItemProperty "$class\$k" -Name OpenGLDriverNameWoW -Value "atioglxx.dll" -ErrorAction SilentlyContinue
  }
}
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Video" -ErrorAction SilentlyContinue | ForEach-Object {
  Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    if ($p.DriverDesc -match "Radeon|AMD") {
      foreach ($n in "OpenGLVersion","OpenGLVersionWoW") {
        if (-not $p.PSObject.Properties[$n]) { Set-ItemProperty $_.PSPath -Name $n -Value 1 }
      }
    }
  }
}
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers" -Name atio6axx -Value "atio6axx.dll"
Set-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers" -Name atioglxx -Value "atioglxx.dll"
if (Test-Path "C:\Windows\System32\nvoglv64.dll") {
  Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers" -Name nvoglv64 -Value "nvoglv64.dll"
}
# перезапуск всех найденных AMD-адаптеров
$adapters = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
  Where-Object { $_.FriendlyName -match "Radeon|AMD" -and $_.Status -eq "OK" }
if ($adapters) {
  foreach ($a in $adapters) {
    "Перезапуск: $($a.FriendlyName) [$($a.InstanceId)]"
    pnputil /restart-device "$($a.InstanceId)" | Out-Null
  }
} else {
  "ВНИМАНИЕ: AMD-адаптер не найден — перезапускать нечего."
}
"Готово: ICD прописан, регистрации восстановлены, драйвер перезапущен."

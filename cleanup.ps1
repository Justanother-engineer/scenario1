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
    "C:\ProgramData\config.inf",
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

# 8. Delete self
$selfPath = $MyInvocation.MyCommand.Path
if ($selfPath -and (Test-Path $selfPath)) {
    Remove-Item -Path $selfPath -Force
}

Write-Host "[+] Cleanup complete."

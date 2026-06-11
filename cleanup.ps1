param()

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
    "C:\ProgramData\Microsoft\Network\~clip.tmp"
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

# 4. Delete SecHealthSvc2 scheduled task
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

# 7. Remove HKLM Explorer\Advanced App value
$advKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Remove-ItemProperty -Path $advKey -Name "App" -Force -ErrorAction SilentlyContinue
Write-Host "  [-] Removed registry: Explorer\Advanced\App"

# 8. Delete self
$selfPath = $MyInvocation.MyCommand.Path
if ($selfPath -and (Test-Path $selfPath)) {
    Remove-Item -Path $selfPath -Force
}

Write-Host "[+] Cleanup complete."

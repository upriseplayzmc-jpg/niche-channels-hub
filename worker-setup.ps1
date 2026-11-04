# One-time setup for the second PC ("render worker"). Run ONCE in PowerShell *as Administrator* on that PC.
# What it does: turns on the built-in OpenSSH server (headless; nothing ever pops up), trusts the main PC's
# key so no password is stored anywhere, stops the PC from sleeping, and prints a summary to paste back.
# It installs nothing else; the tools go into one folder later (easy to delete).
$ErrorActionPreference = "Stop"
$pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAm4K1NoGyMbYjGcceuYtffrpHujNsTnutW+ojidtJc0 ytgs-overseer"

Write-Host "1/5 OpenSSH server..."
$cap = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"
if ($cap.State -ne "Installed") { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
Set-Service sshd -StartupType Automatic
Start-Service sshd
if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Write-Host "2/5 trusting the main PC's key..."
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators")
$keyFile = if ($isAdmin) { "$env:ProgramData\ssh\administrators_authorized_keys" } else { "$env:USERPROFILE\.ssh\authorized_keys" }
New-Item -ItemType Directory -Force (Split-Path $keyFile) | Out-Null
if (-not (Test-Path $keyFile) -or -not (Select-String -Path $keyFile -SimpleMatch "ytgs-overseer" -Quiet)) { Add-Content -Path $keyFile -Value $pub -Encoding ascii }
if ($isAdmin) { icacls $keyFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null }

Write-Host "3/5 default shell = PowerShell, keep the PC awake..."
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
Restart-Service sshd

Write-Host "4/5 hardware check..."
$gpu = try { (& nvidia-smi --query-gpu=name,memory.total --format=csv,noheader) -join "; " } catch { "nvidia-smi not found" }
$drives = (Get-PSDrive -PSProvider FileSystem | Where-Object Free | ForEach-Object { "$($_.Name): $([math]::Round($_.Free/1GB)) GB free" }) -join ", "
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" } | Select-Object -First 1).IPAddress
$py = try { (& py -0p 2>$null) -join " | " } catch { "no py launcher" }

Write-Host "5/5 done. Paste this whole block back into the chat:"
Write-Host "----------------------------------------------------------------"
Write-Host "WORKER host=$env:COMPUTERNAME ip=$ip user=$env:USERNAME admin=$isAdmin"
Write-Host "GPU: $gpu"
Write-Host "Drives: $drives"
Write-Host "Python: $py"
Write-Host "----------------------------------------------------------------"

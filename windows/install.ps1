$ErrorActionPreference = "Stop"

Write-Host "⚡ Installing Universal AI Quota Hub for Windows..." -ForegroundColor Cyan

$TargetDir = Join-Path $env:LOCALAPPDATA "UniversalAIQuota"
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

Copy-Item -Path (Join-Path $RepoDir "core") -Destination $TargetDir -Recurse -Force
Copy-Item -Path (Join-Path $ScriptDir "*") -Destination $TargetDir -Recurse -Force

# Create Start Menu Shortcut
$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$ShortcutPath = Join-Path $StartMenuDir "Universal AI Quota Hub.lnk"

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "wscript.exe"
$Shortcut.Arguments = "`"$TargetDir\AntigravityQuotaHub.vbs`""
$Shortcut.WorkingDirectory = $TargetDir
$Shortcut.Description = "Universal AI Quota Hub - Multi-Provider AI Monitor"
$Shortcut.Save()

Write-Host "✅ Installed successfully in $TargetDir" -ForegroundColor Green
Write-Host "👉 Shortcut created in your Start Menu: 'Universal AI Quota Hub'" -ForegroundColor Yellow

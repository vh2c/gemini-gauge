# Gemini Gauge Windows Installer
# Developed by VH2C • https://vh2c.com.br

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " ⚡ Gemini Gauge - Instalador Windows (VH2C)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

# Target Directory: %LOCALAPPDATA%\GeminiGauge
$TargetDir = Join-Path $env:LOCALAPPDATA "GeminiGauge"
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

# Check Node.js
$NodeCmd = Get-Command "node.exe" -ErrorAction SilentlyContinue
if (-not $NodeCmd) {
    Write-Host "⚠️  Node.js (v18+) não foi detectado no sistema." -ForegroundColor Yellow
    Write-Host "   O Gemini Gauge precisa do Node.js para agregar as cotas." -ForegroundColor Yellow
    Write-Host "   Baixe e instale gratuitamente em: https://nodejs.org" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "✅ Node.js detectado: $(& node -v)" -ForegroundColor Green
}

# Copy core engine and files
Write-Host "📦 Instalando arquivos em $TargetDir..." -ForegroundColor Gray
Copy-Item -Path (Join-Path $RepoDir "core") -Destination $TargetDir -Recurse -Force
Copy-Item -Path (Join-Path $ScriptDir "*") -Destination $TargetDir -Recurse -Force

if (Test-Path (Join-Path $RepoDir "assets\icon.ico")) {
    Copy-Item -Path (Join-Path $RepoDir "assets\icon.ico") -Destination (Join-Path $TargetDir "icon.ico") -Force
}

$WshShell = New-Object -ComObject WScript.Shell
$IconPath = Join-Path $TargetDir "icon.ico"

# 1. Desktop Shortcut
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$DesktopShortcut = $WshShell.CreateShortcut((Join-Path $DesktopDir "Gemini Gauge.lnk"))
$DesktopShortcut.TargetPath = "wscript.exe"
$DesktopShortcut.Arguments = "`"$TargetDir\GeminiGauge.vbs`""
$DesktopShortcut.WorkingDirectory = $TargetDir
$DesktopShortcut.IconLocation = "$IconPath,0"
$DesktopShortcut.Description = "Gemini Gauge - AI Quota & Rate Limit Monitor (VH2C)"
$DesktopShortcut.Save()

# 2. Start Menu Shortcut
$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$StartShortcut = $WshShell.CreateShortcut((Join-Path $StartMenuDir "Gemini Gauge.lnk"))
$StartShortcut.TargetPath = "wscript.exe"
$StartShortcut.Arguments = "`"$TargetDir\GeminiGauge.vbs`""
$StartShortcut.WorkingDirectory = $TargetDir
$StartShortcut.IconLocation = "$IconPath,0"
$StartShortcut.Description = "Gemini Gauge - AI Quota & Rate Limit Monitor (VH2C)"
$StartShortcut.Save()

Write-Host "✅ Atalhos criados com sucesso na Área de Trabalho e no Menu Iniciar!" -ForegroundColor Green
Write-Host "🚀 Iniciando o Gemini Gauge..." -ForegroundColor Cyan

Start-Process "wscript.exe" -ArgumentList "`"$TargetDir\GeminiGauge.vbs`""

Write-Host ""
Write-Host "🎉 Instalação concluída com sucesso!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

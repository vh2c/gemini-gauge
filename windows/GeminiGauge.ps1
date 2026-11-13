<#
.SYNOPSIS
    Gemini Gauge - Windows Edition (PowerShell + WPF)
    Developed by VH2C • https://vh2c.com.br
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$EngineScript = Join-Path $ScriptDir "core\engine.js"
if (-not (Test-Path $EngineScript)) {
    $EngineScript = Join-Path $RepoDir "core\engine.js"
}

$ConfigDir = Join-Path $env:USERPROFILE ".config\UniversalAIQuota"
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}
$ConfigFile = Join-Path $ConfigDir "config.json"
$DeviceIdFile = Join-Path $ConfigDir "device_id"

# 1. Telemetry Heartbeat (Async Background Job)
function Send-TelemetryHeartbeat {
    try {
        $machineId = ""
        if (Test-Path $DeviceIdFile) {
            $machineId = (Get-Content $DeviceIdFile -Raw).Trim()
        }
        if (-not $machineId) {
            $machineId = [guid]::NewGuid().ToString("N")
            Set-Content -Path $DeviceIdFile -Value $machineId -Encoding UTF8
        }

        $payload = @{
            app = "gemini-gauge"
            version = "1.0.0"
            os = "Windows"
            arch = $env:PROCESSOR_ARCHITECTURE
            machine_id = $machineId
            timestamp = [int][double]::Parse((Get-Date -UFormat %s))
        } | ConvertTo-Json

        Start-Job -ScriptBlock {
            param($body)
            try {
                $endpoint = "https://api.vh2c.com.br/v1/geminigauje"
                Invoke-RestMethod -Uri $endpoint -Method Post -Body $body -ContentType "application/json" -TimeoutSec 3 -ErrorAction SilentlyContinue
            } catch {}
        } -ArgumentList $payload | Out-Null
    } catch {}
}

Send-TelemetryHeartbeat

# 2. Find Node binary
function Find-NodeBinary {
    $cmd = Get-Command "node.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $localNode = Join-Path $ScriptDir "bin\node.exe"
    if (Test-Path $localNode) { return $localNode }
    return "node"
}

$NodeExe = Find-NodeBinary

function Get-QuotaData ($force = $false) {
    try {
        $argsList = @($EngineScript)
        if ($force) { $argsList += "--force" }
        $json = & $NodeExe $argsList 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            return ($json | ConvertFrom-Json)
        }
    } catch {}
    return $null
}

# 3. Main WPF Window XAML
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Gemini Gauge - AI Quota Monitor" Height="640" Width="470"
        WindowStartupLocation="CenterScreen" Background="#181818" ResizeMode="CanMinimize">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="0,0,0,14">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="⚡ Gemini Gauge" Foreground="#00E699" FontSize="15" FontWeight="Bold"/>
                <TextBlock Text=" • AI Quota Monitor" Foreground="#EEEEEE" FontSize="14" FontWeight="SemiBold"/>
            </StackPanel>
            <TextBlock Name="TxtAccount" Text="Carregando cotas..." Foreground="#888888" FontSize="11" Margin="0,4,0,0"/>
        </StackPanel>
        
        <!-- Cards List -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel Name="CardsPanel" Margin="0,0,6,0"/>
        </ScrollViewer>
        
        <!-- Footer -->
        <StackPanel Grid.Row="2" Margin="0,14,0,0">
            <!-- Row 1: Action Buttons -->
            <Grid>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                    <Button Name="BtnRefresh" Content="↻ Atualizar" Width="88" Height="28" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Margin="0,0,8,0" Cursor="Hand"/>
                    <Button Name="BtnSettings" Content="⚙️ Configurar" Width="96" Height="28" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Cursor="Hand"/>
                </StackPanel>
                
                <Button Name="BtnClose" Content="✕ Fechar" Width="68" Height="28" HorizontalAlignment="Right" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Cursor="Hand"/>
            </Grid>
            
            <!-- Row 2: Brand Link -->
            <TextBlock Name="TxtBrand" Text="⚡ Gemini Gauge  •  Desenvolvido por vh2c.com.br"
                       Foreground="#38BDF8" FontSize="10.5" FontWeight="SemiBold"
                       HorizontalAlignment="Center" Margin="0,10,0,0" Cursor="Hand"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Set Window Icon
$iconFile = Join-Path $ScriptDir "icon.ico"
if (-not (Test-Path $iconFile)) {
    $iconFile = Join-Path $RepoDir "assets\icon.ico"
}
if (Test-Path $iconFile) {
    try {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconFile)
    } catch {}
}

$txtAcc = $window.FindName("TxtAccount")
$cardsPanel = $window.FindName("CardsPanel")
$btnRefresh = $window.FindName("BtnRefresh")
$btnSettings = $window.FindName("BtnSettings")
$btnClose = $window.FindName("BtnClose")
$txtBrand = $window.FindName("TxtBrand")

function Get-ColorBrush ($pct) {
    if ($pct -ge 50) { return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99))) }
    if ($pct -ge 20) { return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF5, 0xA6, 0x23))) }
    return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xFF, 0x4D, 0x4F)))
}

function Render-UI ($data) {
    if (-not $data) {
        $txtAcc.Text = "Nenhum provedor ativo ou conectado. Clique em Configurar."
        return
    }
    
    $cacheInfo = if ($data.from_cache) { " (Cache)" } else { " (Tempo real)" }
    $txtAcc.Text = "$($data.account) • Plano $($data.plan) • Atualizado às $($data.updated_at)$cacheInfo"
    $cardsPanel.Children.Clear()
    
    foreach ($g in $data.groups) {
        $gbTitle = New-Object System.Windows.Controls.TextBlock
        $prov = if ($g.provider) { " [$($g.provider)]" } else { "" }
        $gbTitle.Text = ($g.name + $prov).ToUpper()
        $gbTitle.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x88, 0x88, 0x88))
        $gbTitle.FontSize = 10
        $gbTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $gbTitle.Margin = New-Object System.Windows.Thickness(0, 8, 0, 4)
        $cardsPanel.Children.Add($gbTitle) | Out-Null
        
        $card = New-Object System.Windows.Controls.Border
        $card.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1F, 0x1F, 0x1F))
        $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2C, 0x2C, 0x2C))
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $card.Padding = New-Object System.Windows.Thickness(14, 10, 14, 10)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
        
        $cardStack = New-Object System.Windows.Controls.StackPanel
        
        $idx = 0
        foreach ($b in $g.buckets) {
            if ($idx -gt 0) {
                $sep = New-Object System.Windows.Controls.Separator
                $sep.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x28))
                $sep.Margin = New-Object System.Windows.Thickness(0, 6, 0, 6)
                $cardStack.Children.Add($sep) | Out-Null
            }
            
            $row = New-Object System.Windows.Controls.Grid
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
            $row.ColumnDefinitions.Add($c1)
            $row.ColumnDefinitions.Add($c2)
            
            $tbName = New-Object System.Windows.Controls.TextBlock
            $tbName.Text = $b.name
            $tbName.Foreground = [System.Windows.Media.Brushes]::White
            $tbName.FontSize = 11.5
            [System.Windows.Controls.Grid]::SetColumn($tbName, 0)
            $row.Children.Add($tbName) | Out-Null
            
            $pct = [int]$b.remaining_pct
            $resetStr = if ($b.reset_in) { " • $($b.reset_in)" } else { "" }
            $tbVal = New-Object System.Windows.Controls.TextBlock
            $tbVal.Text = "$pct%$resetStr"
            $tbVal.Foreground = Get-ColorBrush($pct)
            $tbVal.FontWeight = [System.Windows.FontWeights]::Bold
            $tbVal.FontSize = 11.5
            [System.Windows.Controls.Grid]::SetColumn($tbVal, 1)
            $row.Children.Add($tbVal) | Out-Null
            
            $cardStack.Children.Add($row) | Out-Null
            
            # Progress Bar
            $pbarBg = New-Object System.Windows.Controls.Border
            $pbarBg.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2D, 0x2D, 0x2D))
            $pbarBg.Height = 6
            $pbarBg.CornerRadius = New-Object System.Windows.CornerRadius(3)
            $pbarBg.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
            
            $pbarFill = New-Object System.Windows.Controls.Border
            $pbarFill.Background = Get-ColorBrush($pct)
            $pbarFill.Height = 6
            $pbarFill.CornerRadius = New-Object System.Windows.CornerRadius(3)
            $pbarFill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
            $pbarFill.Width = [Math]::Max(6, (380 * ($pct / 100.0)))
            
            $pbarBg.Child = $pbarFill
            $cardStack.Children.Add($pbarBg) | Out-Null
            
            $idx++
        }
        
        $card.Child = $cardStack
        $cardsPanel.Children.Add($card) | Out-Null
    }
}

# 4. Settings Dialog
function Show-SettingsDialog {
    [xml]$cfgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Configurações - Gemini Gauge" Height="460" Width="420"
        WindowStartupLocation="CenterOwner" Background="#181818" ResizeMode="NoResize">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <StackPanel Grid.Row="0" Margin="0,0,0,14">
            <TextBlock Text="⚙️ Configurar Provedores de IA" Foreground="#FFFFFF" FontSize="14" FontWeight="Bold"/>
            <TextBlock Text="Marque os provedores e insira suas chaves de API:" Foreground="#888888" FontSize="10.5" Margin="0,3,0,0"/>
        </StackPanel>
        
        <StackPanel Grid.Row="1">
            <CheckBox Name="ChkGemini" Content="Google Gemini API (Google AI Studio)" Foreground="#FFFFFF" Margin="0,6,0,2"/>
            <TextBox Name="TxtGeminiKey" Height="24" Background="#1F1F1F" Foreground="#FFFFFF" BorderBrush="#333333" Margin="0,0,0,4"/>
            <TextBlock Name="LinkAiStudio" Text="Obter chave gratuita no Google AI Studio ↗" Foreground="#38BDF8" FontSize="9.5" Margin="0,0,0,12" Cursor="Hand"/>
            
            <CheckBox Name="ChkAnti" Content="Antigravity IDE (Live &amp; Headless)" Foreground="#FFFFFF" Margin="0,0,0,14"/>
            
            <CheckBox Name="ChkOpenAI" Content="OpenAI API (GPT-4o, o1)" Foreground="#FFFFFF" Margin="0,0,0,2"/>
            <TextBox Name="TxtOpenAIKey" Height="24" Background="#1F1F1F" Foreground="#FFFFFF" BorderBrush="#333333" Margin="0,0,0,14"/>
            
            <CheckBox Name="ChkClaude" Content="Anthropic Claude API" Foreground="#FFFFFF" Margin="0,0,0,2"/>
            <TextBox Name="TxtClaudeKey" Height="24" Background="#1F1F1F" Foreground="#FFFFFF" BorderBrush="#333333" Margin="0,0,0,4"/>
        </StackPanel>
        
        <Grid Grid.Row="2" Margin="0,14,0,0">
            <Button Name="BtnSave" Content="Salvar e Atualizar" Width="130" Height="28" HorizontalAlignment="Left" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Cursor="Hand"/>
            <Button Name="BtnCancel" Content="Cancelar" Width="80" Height="28" HorizontalAlignment="Right" Background="#333333" Foreground="#FFFFFF" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@
    $cfgReader = (New-Object System.Xml.XmlNodeReader $cfgXaml)
    $cfgWin = [System.Windows.Markup.XamlReader]::Load($cfgReader)
    $cfgWin.Owner = $window
    
    $chkGemini = $cfgWin.FindName("ChkGemini")
    $txtGemini = $cfgWin.FindName("TxtGeminiKey")
    $linkAiStudio = $cfgWin.FindName("LinkAiStudio")
    $chkAnti = $cfgWin.FindName("ChkAnti")
    $chkOpenAI = $cfgWin.FindName("ChkOpenAI")
    $txtOpenAI = $cfgWin.FindName("TxtOpenAIKey")
    $chkClaude = $cfgWin.FindName("ChkClaude")
    $txtClaude = $cfgWin.FindName("TxtClaudeKey")
    $btnSave = $cfgWin.FindName("BtnSave")
    $btnCancel = $cfgWin.FindName("BtnCancel")
    
    # Load current config
    $currentCfg = $null
    if (Test-Path $ConfigFile) {
        try { $currentCfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json } catch {}
    }
    
    if ($currentCfg -and $currentCfg.providers) {
        $chkGemini.IsChecked = [bool]($currentCfg.providers.gemini.enabled)
        $txtGemini.Text = "$($currentCfg.providers.gemini.api_key)"
        $chkAnti.IsChecked = ($currentCfg.providers.antigravity.enabled -ne $false)
        $chkOpenAI.IsChecked = [bool]($currentCfg.providers.openai.enabled)
        $txtOpenAI.Text = "$($currentCfg.providers.openai.api_key)"
        $chkClaude.IsChecked = [bool]($currentCfg.providers.anthropic.enabled)
        $txtClaude.Text = "$($currentCfg.providers.anthropic.api_key)"
    } else {
        $chkAnti.IsChecked = $true
    }
    
    $linkAiStudio.Add_MouseDown({
        [System.Diagnostics.Process]::Start("https://aistudio.google.com/app/apikey")
    })
    
    $btnSave.Add_Click({
        $newCfg = @{
            providers = @{
                gemini = @{
                    enabled = [bool]$chkGemini.IsChecked
                    api_key = $txtGemini.Text.Trim()
                }
                antigravity = @{
                    enabled = [bool]$chkAnti.IsChecked
                }
                openai = @{
                    enabled = [bool]$chkOpenAI.IsChecked
                    api_key = $txtOpenAI.Text.Trim()
                }
                anthropic = @{
                    enabled = [bool]$chkClaude.IsChecked
                    api_key = $txtClaude.Text.Trim()
                }
            }
            refresh_interval_seconds = 30
        }
        $newCfg | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigFile -Encoding UTF8
        $cfgWin.Close()
        Refresh-Data
    })
    
    $btnCancel.Add_Click({
        $cfgWin.Close()
    })
    
    $cfgWin.ShowDialog() | Out-Null
}

function Refresh-Data {
    $btnRefresh.Content = "Atualizando..."
    $btnRefresh.IsEnabled = $false
    $window.Dispatcher.Invoke([Action]{}, "Background")
    
    $newData = Get-QuotaData -force $true
    if ($newData) {
        Render-UI $newData
    }
    $btnRefresh.Content = "↻ Atualizar"
    $btnRefresh.IsEnabled = $true
}

# Event Listeners
$btnRefresh.Add_Click({ Refresh-Data })
$btnSettings.Add_Click({ Show-SettingsDialog })
$btnClose.Add_Click({ $window.Close() })
$txtBrand.Add_MouseDown({
    [System.Diagnostics.Process]::Start("https://vh2c.com.br")
})

# Initial Load
$quota = Get-QuotaData
if ($quota) {
    Render-UI $quota
    if ($quota.needs_setup -or -not $quota.groups) {
        Show-SettingsDialog
    }
} else {
    Show-SettingsDialog
}

# Auto-refresh Timer (30s)
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
$timer.Add_Tick({ Refresh-Data })
$timer.Start()

$window.ShowDialog() | Out-Null

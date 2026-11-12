<#
.SYNOPSIS
    Universal AI Quota Hub - Windows Edition (PowerShell + WPF)
    Developed by VH2C • https://vh2c.com.br
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EngineScript = Join-Path (Split-Path -Parent $ScriptDir) "core\engine.js"

function Get-QuotaData {
    try {
        $json = & node $EngineScript 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            return ($json | ConvertFrom-Json)
        }
    } catch {}
    return $null
}

$quota = Get-QuotaData

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Universal AI Quota Hub" Height="600" Width="480"
        WindowStartupLocation="CenterScreen" Background="#181818" ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <StackPanel Grid.Row="0" Margin="0,0,0,15">
            <TextBlock Text="Universal AI Quota Hub" Foreground="#FFFFFF" FontSize="14" FontWeight="Bold"/>
            <TextBlock Name="TxtAccount" Text="Multi-Provider AI" Foreground="#888888" FontSize="11" Margin="0,4,0,0"/>
        </StackPanel>
        
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel Name="CardsPanel"/>
        </ScrollViewer>
        
        <Grid Grid.Row="2" Margin="0,15,0,0">
            <Button Name="BtnRefresh" Content="Atualizar" Width="90" Height="30" HorizontalAlignment="Left" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold"/>
            <TextBlock Text="vh2c.com.br" Foreground="#555555" FontSize="10" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Button Name="BtnClose" Content="Fechar" Width="80" Height="30" HorizontalAlignment="Right" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$txtAcc = $window.FindName("TxtAccount")
$cardsPanel = $window.FindName("CardsPanel")
$btnRefresh = $window.FindName("BtnRefresh")
$btnClose = $window.FindName("BtnClose")

function Render-UI ($data) {
    if (-not $data) { return }
    $txtAcc.Text = "$($data.account) • Plano $($data.plan) • Atualizado às $($data.updated_at)"
    $cardsPanel.Children.Clear()
    
    foreach ($g in $data.groups) {
        $gbTitle = New-Object System.Windows.Controls.TextBlock
        $gbTitle.Text = ($g.name).ToUpper()
        $gbTitle.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#888888")
        $gbTitle.FontSize = 10
        $gbTitle.FontWeight = "Bold"
        $gbTitle.Margin = "0,10,0,4"
        $cardsPanel.Children.Add($gbTitle) | Out-Null
        
        $border = New-Object System.Windows.Controls.Border
        $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1F1F1F")
        $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2C2C2C")
        $border.BorderThickness = "1"
        $border.CornerRadius = "8"
        $border.Padding = "12"
        $border.Margin = "0,0,0,10"
        
        $sp = New-Object System.Windows.Controls.StackPanel
        
        foreach ($b in $g.buckets) {
            $row = New-Object System.Windows.Controls.Grid
            $c1 = New-Object System.Windows.Controls.ColumnDefinition
            $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition
            $c2.Width = [System.Windows.GridLength]::Auto
            $row.ColumnDefinitions.Add($c1)
            $row.ColumnDefinitions.Add($c2)
            
            $lbl = New-Object System.Windows.Controls.TextBlock
            $lbl.Text = $b.name
            $lbl.Foreground = [System.Windows.Media.Brushes]::White
            $lbl.FontSize = 11
            [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
            $row.Children.Add($lbl) | Out-Null
            
            $val = New-Object System.Windows.Controls.TextBlock
            $val.Text = "$($b.remaining_pct)% • $($b.reset_in)"
            $valCol = if ($b.remaining_pct -gt 50) { "#22921E" } elseif ($b.remaining_pct -gt 20) { "#C86402" } else { "#C62828" }
            $val.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($valCol)
            $val.FontWeight = "Bold"
            $val.FontSize = 11
            [System.Windows.Controls.Grid]::SetColumn($val, 1)
            $row.Children.Add($val) | Out-Null
            
            $sp.Children.Add($row) | Out-Null
            
            $pb = New-Object System.Windows.Controls.ProgressBar
            $pb.Height = 6
            $pb.Minimum = 0
            $pb.Maximum = 100
            $pb.Value = $b.remaining_pct
            $pb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($valCol)
            $pb.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D2D2D")
            $pb.BorderThickness = "0"
            $pb.Margin = "0,4,0,10"
            $sp.Children.Add($pb) | Out-Null
        }
        $border.Child = $sp
        $cardsPanel.Children.Add($border) | Out-Null
    }
}

Render-UI $quota

$btnClose.Add_Click({ $window.Close() })
$btnRefresh.Add_Click({
    $btnRefresh.Content = "Atualizando..."
    $newData = Get-QuotaData
    Render-UI $newData
    $btnRefresh.Content = "Atualizar"
})

$window.ShowDialog() | Out-Null

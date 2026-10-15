function New-WinUtilZSToolsDialog {
    param([string[]]$Roots = @())
    $dialog = New-Object Windows.Window
    $dialog.Title = 'ZSTools — escolher ação'
    $dialog.Width = 740; $dialog.Height = 440; $dialog.MinWidth = 640; $dialog.MinHeight = 400
    $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.ShowInTaskbar = $false
    $dialog.Background = [Windows.Media.Brushes]::WhiteSmoke; $dialog.Foreground = [Windows.Media.Brushes]::Black
    $dialog.FontFamily = 'Segoe UI'; $dialog.FontSize = 14
    if ($sync.Form) {
        if ($sync.Form.IsVisible) { $dialog.Owner = $sync.Form }
        $background = $sync.Form.TryFindResource('MainBackgroundColor'); $foreground = $sync.Form.TryFindResource('MainForegroundColor')
        if ($background) { $dialog.Background = $background }; if ($foreground) { $dialog.Foreground = $foreground }
    }
    $layout = New-Object Windows.Controls.DockPanel; $layout.Margin = New-Object Windows.Thickness(20); $layout.Background = $dialog.Background
    $dialog.Content = $layout
    $actions = New-Object Windows.Controls.WrapPanel; $actions.HorizontalAlignment = 'Right'; $actions.Margin = New-Object Windows.Thickness(0,18,0,0)
    [Windows.Controls.DockPanel]::SetDock($actions,'Bottom'); [void]$layout.Children.Add($actions)
    $body = New-Object Windows.Controls.StackPanel; [void]$layout.Children.Add($body)
    $heading = New-Object Windows.Controls.TextBlock; $heading.Text = 'O download do ZSTools terminou.'; $heading.FontSize = 20; $heading.FontWeight = 'SemiBold'; $heading.TextWrapping = 'Wrap'; $heading.Margin = New-Object Windows.Thickness(0,0,0,14); [void]$body.Children.Add($heading)
    $text = New-Object Windows.Controls.TextBlock; $text.Text = "Só descarregar: conserva o ZIP em Downloads, sem extrair nem abrir.`n`nCopiar para ZSRest: extrai os ficheiros, guarda uma cópia dos que forem substituídos, copia para a raiz da instalação e abre o ZSTools como administrador.`n`nFeche o ZSRest e o ZSTools antes de copiar. O pacote pode não ter assinatura digital; avance apenas se confia na origem oficial."; $text.TextWrapping = 'Wrap'; $text.Margin = New-Object Windows.Thickness(0,0,0,16); [void]$body.Children.Add($text)
    $rootLabel = New-Object Windows.Controls.TextBlock; $rootLabel.Text = if ($Roots.Count -eq 0) { 'Não foi encontrada uma instalação em <disco>:\Zone Soft\ZSRest.' } else { 'Instalação ZSRest detetada (destino da cópia):' }; $rootLabel.TextWrapping = 'Wrap'; $rootLabel.Margin = New-Object Windows.Thickness(0,0,0,6); [void]$body.Children.Add($rootLabel)
    $selector = New-Object Windows.Controls.ComboBox; $selector.MinHeight = 30
    foreach ($root in $Roots) { [void]$selector.Items.Add($root) }
    if ($Roots.Count -eq 1) { $selector.SelectedIndex = 0 }; [void]$body.Children.Add($selector)
    $state = @{Choice=[pscustomobject]@{Mode='Cancel';Root=$null};Selector=$selector}
    $dialog.Tag = $state
    foreach ($spec in @(@{Label='Só descarregar';Mode='DownloadOnly';Width=160},@{Label='Copiar para ZSRest e abrir';Mode='Deploy';Width=250},@{Label='Cancelar';Mode='Cancel';Width=100})) {
        $button = New-Object Windows.Controls.Button; $button.Content=$spec.Label; $button.Width=$spec.Width; $button.Height=36; $button.Margin=New-Object Windows.Thickness(6,0,0,6)
        $button.Tag=[pscustomobject]@{Mode=$spec.Mode;Dialog=$dialog}
        if ($spec.Mode -eq 'DownloadOnly') { $button.IsDefault=$true; $state.DownloadButton=$button }
        if ($spec.Mode -eq 'Cancel') { $button.IsCancel=$true; $state.CancelButton=$button }
        if ($spec.Mode -eq 'Deploy') { $button.IsEnabled=$selector.SelectedIndex -ge 0; $state.DeployButton=$button }
        $button.Add_Click({
            $window=$this.Tag.Dialog; $mode=$this.Tag.Mode
            $root=if($mode -eq 'Deploy'){[string]$window.Tag.Selector.SelectedItem}else{$null}
            if ($mode -eq 'Deploy' -and [string]::IsNullOrWhiteSpace($root)) { return }
            $window.Tag.Choice=[pscustomobject]@{Mode=$mode;Root=$root}; $window.Close()
        })
        [void]$actions.Children.Add($button)
    }
    $selector.Tag=$state.DeployButton
    $selector.Add_SelectionChanged({$this.Tag.IsEnabled=$this.SelectedIndex -ge 0})
    return $dialog
}

function Show-WinUtilZSToolsChoice {
    param([string[]]$Roots = @())
    # A missing/closed window must never count as permission to overwrite an installation.
    if (-not (Test-WinUtilUIAlive)) { return [pscustomobject]@{Mode='DownloadOnly';Root=$null} }
    $choice = Invoke-WPFUIThread -PassThru -Parameters @{Roots=$Roots} -ScriptBlock {
        param($Roots)
        $dialog = New-WinUtilZSToolsDialog -Roots $Roots
        $null = $dialog.ShowDialog()
        return $dialog.Tag.Choice
    }
    if ($null -eq $choice) { return [pscustomobject]@{Mode='DownloadOnly';Root=$null} }
    return $choice
}

function Initialize-InstallAppEntry {
    <#
        .SYNOPSIS
            Creates the app entry to be placed on the install tab for a given app
            Used to as part of the Install Tab UI generation
        .PARAMETER TargetElement
            The Element into which the Apps should be placed
        .PARAMETER appKey
            The Key of the app inside the $sync.configs.applicationsHashtable
    #>
        param(
            [Windows.Controls.WrapPanel]$TargetElement,
            $appKey
        )

        $app = $sync.configs.applicationsHashtable[$appKey]
        $handlers = Get-WinUtilAppEntryHandlers

        # Create the outer Border for the application type
        $border = New-Object Windows.Controls.Border
        $border.Style = $sync.Form.Resources.AppEntryBorderStyle
        $border.Tag = $appKey
        $border.ToolTip = Get-WinUtilEntryToolTip -Description $app.description -Key $appKey
        $border.Add_MouseLeftButtonUp($handlers.BorderClick)
        $border.Add_MouseEnter($handlers.MouseEnter)
        $border.Add_MouseLeave($handlers.MouseLeave)
        $border.Add_MouseRightButtonUp($handlers.RightClick)

        $checkBox = New-Object Windows.Controls.CheckBox
        # Sanitize the name for WPF
        $checkBox.Name = $appKey -replace '-', '_'
        # Store the original appKey in Tag
        $checkBox.Tag = $appKey
        $checkbox.Style = $sync.Form.Resources.AppEntryCheckboxStyle
        $checkbox.Add_Checked($handlers.Checked)
        $checkbox.Add_Unchecked($handlers.Unchecked)

        # Constrain the name to the remaining card width. A horizontal
        # StackPanel measures text at infinite width and clips long labels.
        $contentPanel = New-Object Windows.Controls.Grid
        $iconColumn = New-Object Windows.Controls.ColumnDefinition
        $iconColumn.Width = [Windows.GridLength]::Auto
        [void]$contentPanel.ColumnDefinitions.Add($iconColumn)
        [void]$contentPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
        $contentPanel.VerticalAlignment = [Windows.VerticalAlignment]::Center

        $icon = New-Object Windows.Controls.Grid
        $icon.SetResourceReference([Windows.FrameworkElement]::WidthProperty, "AppEntryIconSize")
        $icon.SetResourceReference([Windows.FrameworkElement]::HeightProperty, "AppEntryIconSize")
        $icon.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
        $fallback = New-Object Windows.Controls.TextBlock
        $fallback.Text = $app.content.TrimStart(".").Substring(0, 1).ToUpper()
        $fallback.FontWeight = "Bold"; $fallback.HorizontalAlignment = "Center"; $fallback.VerticalAlignment = "Center"
        $fallback.SetResourceReference([Windows.Controls.TextBlock]::FontSizeProperty, "AppEntryFontSize")
        $fallback.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, "ToggleButtonOnColor")
        [void]$icon.Children.Add($fallback)
        $appBitmap = Get-WinUtilAppIcon -AppKey $appKey
        if ($null -ne $appBitmap) {
            $fallback.Visibility = "Collapsed"
            $logo = New-Object Windows.Controls.Image
            $logo.Stretch = [Windows.Media.Stretch]::Uniform
            $logo.Source = $appBitmap
            $logo.Add_ImageFailed($handlers.ImageFailed)

            [void]$icon.Children.Add($logo)
        }
        [void]$contentPanel.Children.Add($icon)

        # Create the TextBlock for the application name
        $appName = New-Object Windows.Controls.TextBlock
        $appName.Style = $sync.Form.Resources.AppEntryNameStyle
        $appName.Text = $app.content
        [Windows.Controls.Grid]::SetColumn($appName, 1)

        # Add FOSS label after the name if FOSS
        [void]$contentPanel.Children.Add($appName)
        $checkBox.Content = $contentPanel

        # Add accessibility properties to make the elements screen reader friendly
        $checkBox.SetValue([Windows.Automation.AutomationProperties]::NameProperty, $app.content)
        $border.SetValue([Windows.Automation.AutomationProperties]::NameProperty, $app.content)

        # Keep the same layout for every entry so the checkbox handlers can reach the border
        $entryLayout = New-Object Windows.Controls.Grid
        [void]$entryLayout.Children.Add($checkBox)

        # Mark FOSS apps with a corner badge, bled into the border padding so it sits on the edge
        if ($app.foss -eq $true) {
            $fossBadge = New-WinUtilFossBadge
            $fossBadge.HorizontalAlignment = "Right"
            $fossBadge.VerticalAlignment = "Top"
            $fossBadge.Margin = New-Object Windows.Thickness(0, -4, -6, 0)

            [void]$entryLayout.Children.Add($fossBadge)
        }

        if ($app.unsupported -eq $true) {
            $checkBox.IsEnabled = $false
            $border.IsEnabled = $false
            $border.Opacity = 0.55
        }
        $border.Child = $entryLayout
        if ($sync.selectedApps -contains $appKey) {
            $checkBox.IsChecked = $true
        }
        # Add the border to the corresponding Category
        $TargetElement.Children.Add($border) | Out-Null
        return $checkbox
    }

function Invoke-WPFAppxInstall {
    if ($null -eq $sync.selectedAppx -or $sync.selectedAppx.Count -eq 0) {
        Show-WinUtilMessage -Message "Selecione uma aplicação AppX." -Title "Windows Utilities" -Button "OK" -Icon "Warning"
        return
    }

    Start-WinUtilJob -Name "Instalação AppX" -Description "Instalar aplicações AppX" -Parameters @{
        Selected = @($sync.selectedAppx)
        Apps = $sync.configs.appxHashtable
    } -ScriptBlock {
        param($Selected, $Apps)

        $totalPackages = @($Selected).Count
        $results = @()
        Write-WinUtilLog -Component "AppX" -Message "Starting AppX install for $totalPackages selected package(s)."

        for ($index = 0; $index -lt $totalPackages; $index++) {
            $app = $Apps[$Selected[$index]]
            $position = $index + 1

            Step-WinUtilJob -Status "A instalar $($app.Content) ($position/$totalPackages)" -Percent ([int](($index / $totalPackages) * 100))
            Write-Host "Installing $($app.Content)"
            $appResults = @(Install-WinUtilAPPX -Name $app.PackageId -StoreId $app.StoreId)
            $results += $appResults
            $status = if (@($appResults | Where-Object Outcome -EQ "Failed").Count -gt 0) {
                "Falhou:"
            } elseif (@($appResults | Where-Object Outcome -EQ "Skipped").Count -gt 0) {
                "Não realizada:"
            } else {
                "Instalada:"
            }
            Step-WinUtilJob -Status "$status $($app.Content) ($position/$totalPackages)" -Percent ([int](($position / $totalPackages) * 100))
        }

        Complete-WinUtilPackageRun -Action "Install" -Results $results
    }
}

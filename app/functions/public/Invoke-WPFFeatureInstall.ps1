function Invoke-WPFFeatureInstall {
    <#

    .SYNOPSIS
        Installs selected Windows Features

    #>

    if ($null -eq $sync.selectedFeatures -or $sync.selectedFeatures.Count -eq 0) {
        Show-WinUtilMessage -Message "Selecione uma funcionalidade do Windows." -Title "Windows Utilities" -Button "OK" -Icon "Warning"
        return
    }

    Start-WinUtilJob -Name "Funcionalidades" -Description "Aplicar funcionalidades do Windows" -Parameters @{
        Features = @($sync.selectedFeatures)
    } -ScriptBlock {
        param($Features)

        $total = @($Features).Count
        $completed = 0

        foreach ($feature in $Features) {
            $completed++
            Step-WinUtilJob -Status "A aplicar $($sync.configs.feature.$feature.Content) ($completed/$total)" -Percent ([int]((($completed - 1) / $total) * 100))
            Measure-WinUtilStep -Scope "Features" -Name $feature -ScriptBlock {
                Invoke-WinUtilFeatureInstall $feature
            }
            Step-WinUtilJob -Status "Funcionalidade processada ($completed/$total)" -Percent ([int](($completed / $total) * 100))
        }

        Write-Host "Pode ser necessário reiniciar o computador."
    }
}

function Invoke-WPFundoall {
    <#

    .SYNOPSIS
        Undoes every selected tweak

    #>

    $tweaks = $sync.selectedTweaks

    if ($tweaks.count -eq 0) {
        Show-WinUtilMessage -Message "Selecione as otimizações que pretende reverter. A reversão aplica os valores definidos no catálogo e não substitui uma cópia de segurança do estado anterior." -Title "Windows Utilities" -Button "OK" -Icon "Warning"
        return
    }

    Start-WinUtilJob -Name "Reversão" -Description "Reverter otimizações" -Parameters @{
        Tweaks = @($tweaks)
    } -ScriptBlock {
        param($Tweaks)

        $total = @($Tweaks).Count
        Write-WinUtilLog -Component "Tweaks" -Message "Undo tweaks requested: $total selected tweak(s)."

        for ($i = 0; $i -lt $total; $i++) {
            Step-WinUtilJob -Status "A reverter $($sync.configs.tweaks.($Tweaks[$i]).Content) ($($i + 1)/$total)" -Percent ([int](($i / $total) * 100))
            Measure-WinUtilStep -Scope "Undo tweaks" -Name $Tweaks[$i] -ScriptBlock {
                Invoke-WinUtiltweaks $Tweaks[$i] -undo $true
            }
            Step-WinUtilJob -Percent ([int]((($i + 1) / $total) * 100))
        }
    }
}

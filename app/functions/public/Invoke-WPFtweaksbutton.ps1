function Invoke-WPFtweaksbutton {
  <#

    .SYNOPSIS
        Invokes the functions associated with each group of checkboxes

  #>

  $Tweaks = $sync.selectedTweaks
  $dnsProvider = if ($sync['WPFchangedns'].SelectedItem) { $sync['WPFchangedns'].SelectedItem.Tag } else { $sync['WPFchangedns'].Text }
  if (-not ($dnsProvider)) {
    $dnsProvider = "Default"
  }

  if ($Tweaks.count -eq 0 -and $dnsProvider -eq "Default") {
    Show-WinUtilMessage -Message "Selecione as otimizações que pretende aplicar." -Title "Windows Utilities" -Button "OK" -Icon "Warning"
    return
  }

  Write-WinUtilLog -Component "Tweaks" -Message "Tweaks requested: $(@($Tweaks).Count) selected tweak(s), DNS provider: $dnsProvider"

  Start-WinUtilJob -Name "Otimizações" -Description "Aplicar otimizações" -Parameters @{
    Tweaks = @($Tweaks)
    DnsProvider = $dnsProvider
  } -ScriptBlock {
    param($Tweaks, $DnsProvider)

    # The restore point has to be taken before anything else changes
    $restorePointTweak = "WPFTweaksRestorePoint"
    $tweaksToRun = @($Tweaks | Where-Object { $_ -ne $restorePointTweak })
    $totalSteps = [Math]::Max(@($Tweaks).Count, 1)
    $completedSteps = 0

    if ($Tweaks -contains $restorePointTweak) {
      $restoreErrorsBefore = [int]$global:WinUtilJobErrorCount
      Step-WinUtilJob -Status "A criar ponto de restauro" -Percent 0
      Write-WinUtilLog -Component "Tweaks" -Message "Creating restore point before applying selected tweaks."
      Measure-WinUtilStep -Scope "Tweaks" -Name $restorePointTweak -ScriptBlock {
        Invoke-WinUtilTweaks $restorePointTweak
      }
      if ([int]$global:WinUtilJobErrorCount -gt $restoreErrorsBefore) {
        $restoreFailure = [InvalidOperationException]::new('Não foi possível criar o ponto de restauro. As restantes otimizações não foram aplicadas.')
        $restoreFailure.Data['WinUtilErrorReported'] = $true
        throw $restoreFailure
      }
      $completedSteps = 1
    }

    if ($DnsProvider -ne "Default") {
      $dnsResult = Measure-WinUtilStep -Scope "Tweaks" -Name "Set DNS to $DnsProvider" -ScriptBlock {
        @(Set-WinUtilDNS -DNSProvider $DnsProvider)
      }

      # Carrying on after the DNS change failed leaves the machine half configured, so the run
      # ends here and the job layer reports it
      if (@($dnsResult)[-1] -ne $true) {
        throw "The DNS change to $DnsProvider failed, so the remaining tweaks were not applied."
      }
    }

    foreach ($tweak in $tweaksToRun) {
      Step-WinUtilJob -Status "A aplicar $($sync.configs.tweaks.$tweak.Content) ($($completedSteps + 1)/$totalSteps)" -Percent ([int](($completedSteps / $totalSteps) * 100))
      Measure-WinUtilStep -Scope "Tweaks" -Name $tweak -ScriptBlock {
        Invoke-WinUtilTweaks $tweak
      }
      $completedSteps++
      Step-WinUtilJob -Percent ([int](($completedSteps / $totalSteps) * 100))
    }
  }
}

function Invoke-WPFInstall {
    <#
    .SYNOPSIS
        Installs the selected programs using winget, if one or more of the selected programs are already installed on the system, winget will try and perform an upgrade if there's a newer version to install.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [PSObject[]]$PackagesToInstall = $($sync.selectedApps | Foreach-Object { $sync.configs.applicationsHashtable.$_ })
    )

    if ($PackagesToInstall.Count -eq 0) {
        $WarningMsg = "Selecione as aplicações que pretende instalar ou atualizar."
        Show-WinUtilMessage -Message $WarningMsg -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    $ManagerPreference = $sync.preferences.packagemanager
    Write-WinUtilLog -Component "Install" -Message "Install requested for $(@($PackagesToInstall).Count) selected package(s) using preference: $ManagerPreference"
    $packageSummary = Get-WinUtilPackageLogSummary -Packages $PackagesToInstall -Preference $ManagerPreference
    Write-WinUtilLog -Component "Install" -Message "Install selected package(s): $($packageSummary -join '; ')"

    $manualCount = @($PackagesToInstall | Where-Object { $_.custom -in @('XD','ZoneSoft','ZSTools') }).Count
    $jobDescription = if ($manualCount -eq $PackagesToInstall.Count) {
        'Preparar software de faturação'
    } elseif ($manualCount -gt 0) {
        'Instalar aplicações e preparar software de faturação'
    } else {
        'Instalar aplicações'
    }
    Start-WinUtilJob -Name "Instalação" -Description $jobDescription -DisableAppList -Parameters @{
        PackagesToInstall = $PackagesToInstall
        ManagerPreference = $ManagerPreference
    } -ScriptBlock {
        param($PackagesToInstall, $ManagerPreference)

        $packagesSorted = Get-WinUtilSelectedPackages -PackageList $PackagesToInstall -Preference $ManagerPreference
        $packagesWinget = $packagesSorted['Winget']
        $packagesChoco = $packagesSorted['Choco']
        $packagesCustom = @($PackagesToInstall | Where-Object { $_.custom -eq 'PdfCraft' })
        $packagesZoneSoft = @($PackagesToInstall | Where-Object { $_.custom -eq 'ZoneSoft' })
        $packagesXD = @($PackagesToInstall | Where-Object { $_.custom -eq 'XD' })
        $packagesZSTools = @($PackagesToInstall | Where-Object { $_.custom -eq 'ZSTools' })
        $totalPackages = @($packagesWinget).Count + @($packagesChoco).Count + @($packagesCustom).Count + $packagesZoneSoft.Count + $packagesXD.Count + $packagesZSTools.Count
        $completedPackages = 0
        Write-WinUtilLog -Component "Install" -Message "Install package manager split: winget=$(@($packagesWinget).Count), choco=$(@($packagesChoco).Count)"

        $results = @()

        if ($packagesWinget.Count -gt 0 -and $packagesWinget -ne "0") {
            Install-WinUtilWinget
            foreach ($program in $packagesWinget) {
                $position = $completedPackages + 1
                Step-WinUtilJob -Status "A instalar $program ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

                $results += Measure-WinUtilStep -Scope "Install" -Name "winget $program" -ScriptBlock {
                    Install-WinUtilProgramWinget -Action Install -Programs @($program)
                }
                $completedPackages++
                Step-WinUtilJob -Status "$program processado ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
            }
        }

        if ($packagesChoco.Count -gt 0) {
            $position = $completedPackages + 1
            Step-WinUtilJob -Status "A instalar aplicações com Chocolatey ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

            Install-WinUtilChoco
            $chocoBase = [int](($completedPackages / $totalPackages) * 100)
            $chocoSpan = [int]((@($packagesChoco).Count / $totalPackages) * 100)
            $results += Measure-WinUtilStep -Scope "Install" -Name "choco $($packagesChoco -join ', ')" -ScriptBlock {
                Install-WinUtilProgramChoco -Action Install -Programs $packagesChoco -ProgressBase $chocoBase -ProgressSpan $chocoSpan
            }
            $completedPackages += @($packagesChoco).Count
            Step-WinUtilJob -Status "Aplicações Chocolatey processadas ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        foreach ($customPackage in $packagesCustom) {
            $completedPackages++
            Step-WinUtilJob -Status "A instalar PdfCraft ($completedPackages/$totalPackages)" -Percent ([int]((($completedPackages - 1) / $totalPackages) * 100))
            $results += Measure-WinUtilStep -Scope "Install" -Name "PdfCraft ArtCraft" -ScriptBlock {
                Install-WinUtilPdfCraft -Action Install
            }
            Step-WinUtilJob -Status "PdfCraft processado ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        foreach ($xdPackage in $packagesXD) {
            try {
                Install-WinUtilXD -DestinationPath (Get-WinUtilXDDownloadPath)
                $results += [pscustomobject]@{Package='XD';Manager='XD';Action='Download';ExitCode=0;Outcome='Succeeded';Detail='Instalador transferido e aberto; instalação manual.';Path=$sync.LastXDInstallerPath}
            } catch {
                Write-WinUtilLog -Component 'XD' -Level ERROR -Message $_.Exception.Message
                $results += [pscustomobject]@{Package='XD';Manager='XD';Action='Download';ExitCode=1;Outcome='Failed';Detail=$_.Exception.Message}
            }
            $completedPackages++
            Step-WinUtilJob -Status "XD processado ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        foreach ($toolsPackage in $packagesZSTools) {
            try { $results += Install-WinUtilZSTools }
            catch {
                Write-WinUtilLog -Component 'ZSTools' -Level ERROR -Message $_.Exception.Message
                $results += [pscustomobject]@{Package='ZSTools';Manager='ZSTools';Action='Download / Copy';ExitCode=1;Outcome='Failed';Detail=$_.Exception.Message}
            }
            $completedPackages++
            Step-WinUtilJob -Status "ZSTools processado ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        if ($packagesZoneSoft.Count -gt 0) {
            Step-WinUtilJob -Status 'A procurar as últimas versões do ZoneSoft...' -State Indeterminate
            $zoneSoftCatalog = @(Get-WinUtilZoneSoftCatalog)
            foreach ($zoneSoftPackage in $packagesZoneSoft) {
                try {
                    $results += Install-WinUtilZoneSoft -Variant $zoneSoftPackage.variant -Catalog $zoneSoftCatalog
                } catch {
                    Write-WinUtilLog -Component 'ZoneSoft' -Level ERROR -Message "$($zoneSoftPackage.content): $($_.Exception.Message)"
                    $results += [pscustomobject]@{Package=$zoneSoftPackage.content;Manager='ZoneSoft';Action='Download';ExitCode=1;Outcome='Failed';Detail=$_.Exception.Message}
                }
                $completedPackages++
                Step-WinUtilJob -Status "ZoneSoft processado ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
            }
        }

        Complete-WinUtilPackageRun -Action "Install / Download" -Results $results
    }
}

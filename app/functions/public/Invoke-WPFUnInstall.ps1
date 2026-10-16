function Invoke-WPFUnInstall {
    param(
        [Parameter(Mandatory=$false)]
        [PSObject[]]$PackagesToUninstall = $($sync.selectedApps | Foreach-Object { $sync.configs.applicationsHashtable.$_ })
    )
    <#

    .SYNOPSIS
        Uninstalls the selected programs
    #>

    if ($PackagesToUninstall.Count -eq 0) {
        $WarningMsg = "Selecione as aplicações que pretende desinstalar."
        Show-WinUtilMessage -Message $WarningMsg -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    if (@($PackagesToUninstall | Where-Object custom -eq 'Portable').Count -gt 0) {
        Show-WinUtilMessage -Message 'Os portáteis temporários não são instalados. Feche a ferramenta para limpar a cópia; desmarque os portáteis para desinstalar outras aplicações.' -Title 'Portáteis temporários' -Button OK -Icon Information | Out-Null
        return
    }

    if (@($PackagesToUninstall | Where-Object custom -eq 'RemoteAgent').Count -gt 0) {
        Show-WinUtilMessage -Message 'A remoção do agente de acesso remoto não é feita por esta aplicação. Utilize as Definições do Windows ou o procedimento da sua equipa. Desmarque Acesso remoto para desinstalar outras aplicações.' -Title 'Acesso remoto' -Button OK -Icon Information | Out-Null
        return
    }
    if (@($PackagesToUninstall | Where-Object { $_.custom -in @('XD','ZoneSoft') -or $_.uninstallSupported -eq $false }).Count -gt 0) {
        Show-WinUtilMessage -Message 'A remoção automática do XD, ZoneSoft e ZSTools não está disponível. Desmarque-os para desinstalar outras aplicações; utilize as Definições do Windows ou as instruções do fabricante para os remover.' -Title 'Softwares de faturação' -Button OK -Icon Information | Out-Null
        return
    }
    $ButtonType = "YesNo"
    $MessageboxTitle = "Confirmar desinstalação"
    $Messageboxbody = "Pretende desinstalar as seguintes aplicações?`n`n" + (($PackagesToUninstall | ForEach-Object { $_.content }) -join "`n")
    $MessageIcon = "Information"

    $confirm = Show-WinUtilMessage -Message $Messageboxbody -Title $MessageboxTitle -Button $ButtonType -Icon $MessageIcon

    if ($confirm -ne "Yes") { return }

    $ManagerPreference = $sync.preferences.packagemanager
    Write-WinUtilLog -Component "Uninstall" -Message "Uninstall requested for $(@($PackagesToUninstall).Count) selected package(s) using preference: $ManagerPreference"
    $packageSummary = Get-WinUtilPackageLogSummary -Packages $PackagesToUninstall -Preference $ManagerPreference
    Write-WinUtilLog -Component "Uninstall" -Message "Uninstall selected package(s): $($packageSummary -join '; ')"

    Start-WinUtilJob -Name "Desinstalação" -Description "Desinstalar aplicações" -DisableAppList -Parameters @{
        PackagesToUninstall = $PackagesToUninstall
        ManagerPreference = $ManagerPreference
    } -ScriptBlock {
        param($PackagesToUninstall, $ManagerPreference)

        $packagesSorted = Get-WinUtilSelectedPackages -PackageList $PackagesToUninstall -Preference $ManagerPreference
        $packagesWinget = $packagesSorted['Winget']
        $packagesChoco = $packagesSorted['Choco']
        $packagesCustom = @($PackagesToUninstall | Where-Object custom -eq 'PdfCraft')
        $totalPackages = @($packagesWinget).Count + @($packagesChoco).Count + $packagesCustom.Count
        $completedPackages = 0
        Write-WinUtilLog -Component "Uninstall" -Message "Uninstall package manager split: winget=$(@($packagesWinget).Count), choco=$(@($packagesChoco).Count)"

        if ($packagesWinget -contains "Microsoft.Edge") {
            New-Item -Path "$Env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe" -Force | Out-Null
        }

        $results = @()

        if ($packagesWinget.Count -gt 0) {
            foreach ($program in $packagesWinget) {
                $position = $completedPackages + 1
                Step-WinUtilJob -Status "A desinstalar $program ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

                $results += Measure-WinUtilStep -Scope "Uninstall" -Name "winget $program" -ScriptBlock {
                    Install-WinUtilProgramWinget -Action Uninstall -Programs @($program)
                }
                $completedPackages++
                Step-WinUtilJob -Status "$program processado ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
            }
        }

        if ($packagesChoco.Count -gt 0) {
            $position = $completedPackages + 1
            Step-WinUtilJob -Status "A desinstalar aplicações com Chocolatey ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

            $chocoBase = [int](($completedPackages / $totalPackages) * 100)
            $chocoSpan = [int]((@($packagesChoco).Count / $totalPackages) * 100)
            $results += Measure-WinUtilStep -Scope "Uninstall" -Name "choco $($packagesChoco -join ', ')" -ScriptBlock {
                Install-WinUtilProgramChoco -Action Uninstall -Programs $packagesChoco -ProgressBase $chocoBase -ProgressSpan $chocoSpan
            }
            $completedPackages += @($packagesChoco).Count
            Step-WinUtilJob -Status "Aplicações Chocolatey processadas ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        foreach ($customPackage in $packagesCustom) {
            Step-WinUtilJob -Status 'A desinstalar o PdfCraft...' -State Indeterminate
            $results += Install-WinUtilPdfCraft -Action Uninstall
            $completedPackages++
        }
        Complete-WinUtilPackageRun -Action "Uninstall" -Results $results
    }
}

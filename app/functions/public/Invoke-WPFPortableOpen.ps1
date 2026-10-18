function Invoke-WPFPortableOpen {
    $selected = @($sync.selectedApps | ForEach-Object { $sync.configs.applicationsHashtable.$_ } | Where-Object { $_.custom -in @('Portable','SafePortable') })
    if ($selected.Count -eq 0) {
        Show-WinUtilMessage -Title 'Portáteis' -Message 'Selecione uma ou mais ferramentas na secção Portáteis.' -Button OK -Icon Information | Out-Null
        return
    }
    Invoke-WPFInstall -PackagesToInstall $selected
}

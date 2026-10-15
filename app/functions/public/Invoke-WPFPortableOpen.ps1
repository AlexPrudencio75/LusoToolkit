function Invoke-WPFPortableOpen {
    $selected = @($sync.selectedApps | ForEach-Object { $sync.configs.applicationsHashtable.$_ } | Where-Object custom -eq 'Portable')
    if ($selected.Count -eq 0) {
        Show-WinUtilMessage -Title 'Portateis temporarios' -Message 'Selecione uma ou mais ferramentas na seccao Portateis temporarios.' -Button OK -Icon Information | Out-Null
        return
    }
    Invoke-WPFInstall -PackagesToInstall $selected
}

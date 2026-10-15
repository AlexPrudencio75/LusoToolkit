function Invoke-WPFXDInstall {
    if ($sync.ActiveJob) {
        Show-WinUtilMessage -Message 'Aguarde que a tarefa atual termine antes de transferir o XD.' -Title 'XD' -Button OK -Icon Information | Out-Null
        return
    }

    $destination = Get-WinUtilXDDownloadPath

    Start-WinUtilJob -Name 'XD' -Description 'Transferência e abertura do instalador do XD' -DisableAppList -Parameters @{
        DestinationPath = $destination
    } -ScriptBlock {
        param($DestinationPath)
        Install-WinUtilXD -DestinationPath $DestinationPath
    }
}

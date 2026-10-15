function Get-WinUtilDownloadsFolder {
    # This known-folder value follows Downloads when the user redirects or moves it.
    $configuredPath = $null
    try {
        $configuredPath = Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name '{374DE290-123F-4565-9164-39C4925E467B}' -ErrorAction Stop
    } catch { }
    if ([string]::IsNullOrWhiteSpace($configuredPath)) {
        $configuredPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    }
    $folder = [Environment]::ExpandEnvironmentVariables([string]$configuredPath)
    if (-not [IO.Path]::IsPathRooted($folder)) { throw 'Não foi possível localizar a pasta Transferências do Windows.' }
    $folder = [IO.Path]::GetFullPath($folder)
    [void][IO.Directory]::CreateDirectory($folder)
    return $folder
}

function Get-WinUtilXDDownloadPath {
    param([string]$Folder = (Get-WinUtilDownloadsFolder))
    for ($index = 0; $index -lt 10000; $index++) {
        $name = if ($index -eq 0) { 'XDSoftware.exe' } else { "XDSoftware ($index).exe" }
        $candidate = Join-Path $Folder $name
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw 'Não foi possível obter um nome livre para o instalador do XD em Transferências.'
}

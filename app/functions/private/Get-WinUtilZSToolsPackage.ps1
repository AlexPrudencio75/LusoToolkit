function Get-WinUtilZSToolsPackage {
    $prefix = 'PT/Utilitários/'
    $endpoint = 'https://api-zslicweb.zonesoft.org/v1/manuals/'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try { $listing = Invoke-RestMethod -Uri ($endpoint + 'list?prefix=' + [uri]::EscapeDataString($prefix)) -Method Get -MaximumRedirection 0 -TimeoutSec 30 -ErrorAction Stop }
    catch { throw 'Não foi possível consultar o ZSTools na página oficial. Nenhuma credencial foi utilizada; tente mais tarde.' }
    if ($listing.status -ne 'ok' -or $null -eq $listing.data) { throw 'A listagem oficial do ZSTools mudou de formato.' }
    $candidates = foreach ($file in @($listing.data)) {
        if ($file.isFolder -ne $false) { continue }
        $match = [regex]::Match([string]$file.name, '^ZSTools_(?<version>\d+(?:\.\d+){0,3})\.zip$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { continue }
        if ([string]$file.id -cne ($prefix + [string]$file.name)) { throw 'A listagem ZSTools contém um caminho inesperado.' }
        $size = 0L
        if (-not [long]::TryParse([string]$file.size, [ref]$size) -or $size -le 0) { throw 'O tamanho publicado do ZSTools não é válido.' }
        $versionText = $match.Groups['version'].Value
        if (-not $versionText.Contains('.')) { $versionText += '.0' }
        [pscustomobject]@{FileName=[string]$file.name;Version=[version]$versionText;Size=$size;DownloadUri=($endpoint + 'download?key=' + [uri]::EscapeDataString([string]$file.id))}
    }
    $latest = @($candidates | Sort-Object Version -Descending | Select-Object -First 1)
    if ($latest.Count -ne 1) { throw 'O ZIP ZSTools não foi encontrado na pasta oficial PT > Utilitários.' }
    return $latest[0]
}

function Get-WinUtilLocalDiskRoots {
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        if ($drive.IsReady -and $drive.DriveType -in @([IO.DriveType]::Fixed,[IO.DriveType]::Removable)) { $drive.RootDirectory.FullName }
    }
}

function Get-WinUtilZSRestRoots {
    foreach ($diskRoot in @(Get-WinUtilLocalDiskRoots)) {
        $vendorFolder = Join-Path $diskRoot 'Zone Soft'
        $root = Join-Path $vendorFolder 'ZSRest'
        $marker = Join-Path $root 'ZSRest.exe'
        if (-not (Test-Path -LiteralPath $root -PathType Container) -or -not (Test-Path -LiteralPath $marker -PathType Leaf)) { continue }
        $linked = $false
        foreach ($path in @($vendorFolder,$root,$marker)) {
            if (((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $linked = $true }
        }
        if (-not $linked) { [IO.Path]::GetFullPath($root).TrimEnd('\') }
    }
}

function Assert-WinUtilZSRestRoot {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (@(Get-WinUtilZSRestRoots) -notcontains $fullPath) { throw 'O destino já não é uma instalação válida em <disco>:\Zone Soft\ZSRest. Nenhum ficheiro foi copiado.' }
    return $fullPath
}

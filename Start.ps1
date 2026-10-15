#requires -Version 5.1
<#
LusoToolkit: descarrega e abre a versao publicada neste repositorio.
Leia o codigo antes de executar. Nao altera a politica de execucao permanente.
O SHA-256 deteta corrupcao/trocas de pacote; nao substitui a confianca no repositorio.
#>
[CmdletBinding()]
param(
    [switch]$DownloadOnly,
    [string]$DestinationRoot
)

function Receive-LusoToolkitFile {
    param([Parameter(Mandatory)][uri]$Uri, [Parameter(Mandatory)][string]$OutFile)
    if ($Uri.Scheme -ne 'https' -or $Uri.Host -ne 'raw.githubusercontent.com' -or
        -not $Uri.AbsolutePath.StartsWith('/AlexPrudencio75/LusoToolkit/main/', [StringComparison]::Ordinal)) {
        throw 'Origem de transferencia nao autorizada.'
    }
    Invoke-WebRequest -Uri $Uri.AbsoluteUri -UseBasicParsing -OutFile $OutFile -TimeoutSec 120 `
        -MaximumRedirection 3 -Headers @{ 'User-Agent' = 'LusoToolkit-Bootstrap/1.0'; 'Cache-Control' = 'no-cache' } -ErrorAction Stop | Out-Null
}

function Read-LusoToolkitManifest {
    param([Parameter(Mandatory)][string]$Path)
    if ((Get-Item -LiteralPath $Path -ErrorAction Stop).Length -gt 16384) { throw 'Manifesto demasiado grande.' }
    $manifest = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.schemaVersion -ne 1 -or [string]$manifest.version -notmatch '^\d+\.\d+\.\d+$' -or
        [string]$manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        $manifest.size -isnot [ValueType] -or $manifest.size -le 0 -or $manifest.size -gt 52428800) {
        throw 'Manifesto de publicacao invalido.'
    }
    return $manifest
}

function Expand-LusoToolkitPackage {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Version
    )
    if (Test-Path -LiteralPath $Destination) { throw 'A pasta de extracao ja existe; nada foi substituido.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $expectedFolder = 'WindowsUtilities_PTPT_v' + $Version
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -eq 0 -or $archive.Entries.Count -gt 5000) { throw 'Numero de entradas ZIP invalido.' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $planned = [Collections.Generic.List[object]]::new()
        [long]$total = 0
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            $isDirectory = $name.EndsWith('/')
            $parts = $name.TrimEnd('/').Split('/')
            if ($parts.Count -eq 0 -or $parts[0] -cne $expectedFolder) { throw 'Pasta raiz inesperada no ZIP.' }
            foreach ($part in $parts) {
                if ([string]::IsNullOrWhiteSpace($part) -or $part -in @('.', '..') -or
                    $part -match '[<>:"|?*\x00-\x1f]' -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
                    $part -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') { throw 'Caminho inseguro no ZIP.' }
            }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination ($parts -join '\')))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($target)) {
                throw 'Caminho repetido ou fora da pasta de extracao.'
            }
            if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Links simbolicos nao sao permitidos no ZIP.' }
            $total += $entry.Length
            if ($total -gt 268435456) { throw 'Pacote descomprimido demasiado grande.' }
            $planned.Add([pscustomobject]@{ Entry = $entry; Path = $target; Directory = $isDirectory })
        }
        # Valida todas as entradas antes de criar qualquer ficheiro.
        [void][IO.Directory]::CreateDirectory($Destination)
        foreach ($item in $planned) {
            if ($item.Directory) { [void][IO.Directory]::CreateDirectory($item.Path); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Path))
            $inputStream = $item.Entry.Open()
            $outputStream = $null
            try {
                $outputStream = [IO.File]::Open($item.Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $inputStream.CopyTo($outputStream)
            } finally {
                if ($null -ne $outputStream) { $outputStream.Dispose() }
                $inputStream.Dispose()
            }
        }
    } finally { $archive.Dispose() }

    $appRoot = Join-Path $Destination $expectedFolder
    foreach ($required in @('VERSION', 'Compile.ps1', 'INICIAR-DIAGNOSTICO.ps1', 'INICIAR.cmd', 'LICENSE',
            'assets\logo.png', 'scripts\start.ps1', 'scripts\main.ps1', 'xaml\inputXML.xaml', 'config\applications.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $appRoot $required) -PathType Leaf)) { throw ('Pacote incompleto: ' + $required) }
    }
    if ([IO.File]::ReadAllText((Join-Path $appRoot 'VERSION')).Trim() -cne $Version) { throw 'A versao extraida nao corresponde ao manifesto.' }
    return $appRoot
}

function Start-LusoToolkit {
    [CmdletBinding()]
    param([switch]$DownloadOnly, [string]$DestinationRoot)
    $ErrorActionPreference = 'Stop'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'O LusoToolkit requer Windows.' }
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { throw 'A politica deste computador restringe a execucao. Contacte o administrador.' }
    if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
        $localData = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Nao foi encontrada a pasta de dados locais do Windows.' }
        $DestinationRoot = Join-Path $localData 'LusoToolkit'
    }
    $DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot)
    if (Test-Path -LiteralPath $DestinationRoot) {
        $rootItem = Get-Item -LiteralPath $DestinationRoot -Force
        if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'A pasta de destino nao e uma pasta local normal.' }
    } else { [void][IO.Directory]::CreateDirectory($DestinationRoot) }
    $runFolder = Join-Path $DestinationRoot ('run-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $runFolder) { throw 'A pasta desta execucao ja existe.' }
    [void][IO.Directory]::CreateDirectory($runFolder)
    $oldTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $oldTls -bor [Net.SecurityProtocolType]::Tls12
        Write-Host 'LusoToolkit - a procurar a versao publicada...' -ForegroundColor Cyan
        $manifestPath = Join-Path $runFolder 'release.json'
        $manifestUrl = 'https://raw.githubusercontent.com/AlexPrudencio75/LusoToolkit/main/release.json?run=' + [guid]::NewGuid().ToString('N')
        Receive-LusoToolkitFile -Uri $manifestUrl -OutFile $manifestPath
        $manifest = Read-LusoToolkitManifest -Path $manifestPath
        $packageName = 'LusoToolkit-' + $manifest.version + '.zip'
        $packagePath = Join-Path $runFolder $packageName
        $packageUrl = 'https://raw.githubusercontent.com/AlexPrudencio75/LusoToolkit/main/packages/' + $packageName
        Write-Host ('A transferir LusoToolkit ' + $manifest.version + '...') -ForegroundColor Cyan
        Receive-LusoToolkitFile -Uri $packageUrl -OutFile $packagePath
        if ((Get-Item -LiteralPath $packagePath).Length -ne $manifest.size) { throw 'O tamanho do pacote nao corresponde ao publicado.' }
        if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -ine $manifest.sha256) { throw 'O SHA-256 do pacote nao corresponde ao publicado. Abertura cancelada.' }
        Write-Host 'Pacote verificado. A extrair...' -ForegroundColor Cyan
        $appRoot = Expand-LusoToolkitPackage -ArchivePath $packagePath -Destination (Join-Path $runFolder 'app') -Version $manifest.version
        if ($DownloadOnly) { return [pscustomobject]@{ Version = $manifest.version; AppRoot = $appRoot; Package = $packagePath } }
        $windowsPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # Um anfitriao PowerShell de 32 bits deve abrir o Windows PowerShell de 64 bits.
        if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
            $windowsPS = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        }
        if (-not (Test-Path -LiteralPath $windowsPS -PathType Leaf)) { throw 'Windows PowerShell 5.1 nao encontrado.' }
        $launcher = Join-Path $appRoot 'INICIAR-DIAGNOSTICO.ps1'
        Write-Host 'A abrir a aplicacao. Confirme o pedido de administrador do Windows.' -ForegroundColor Cyan
        # O processo e interativo: mostra a interface e os erros de arranque.
        # Bypass aplica-se apenas a este processo; nao usa Set-ExecutionPolicy.
        Start-Process -FilePath $windowsPS -WorkingDirectory $appRoot -WindowStyle Normal `
            -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "' + $launcher + '"') -ErrorAction Stop
    } catch {
        throw ('Nao foi possivel abrir o LusoToolkit: ' + $_.Exception.Message)
    } finally { [Net.ServicePointManager]::SecurityProtocol = $oldTls }
}

Start-LusoToolkit -DownloadOnly:$DownloadOnly -DestinationRoot $DestinationRoot

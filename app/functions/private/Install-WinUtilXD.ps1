function Install-WinUtilXD {
    <# Transfers the vendor's Windows installer and hands its wizard to the user. #>
    param([Parameter(Mandatory)][string]$DestinationPath)

    $officialPage = 'https://www.site.xd.pt/demostrativos/downloads'
    $installerUri = 'https://f003.backblazeb2.com/file/xdfiles/XDSoftware.exe'
    $destination = [IO.Path]::GetFullPath($DestinationPath)
    if ([IO.Path]::GetExtension($destination) -ine '.exe') { throw 'Escolha um ficheiro com extensão .exe para guardar o instalador do XD.' }
    $folder = [IO.Path]::GetDirectoryName($destination)
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw 'A pasta escolhida para o instalador não existe.' }
    $partial = Join-Path $folder ('XDSoftware-' + [guid]::NewGuid().ToString('N') + '.partial')

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Step-WinUtilJob -Status 'A confirmar a origem oficial do XD...' -State Indeterminate
        $page = Invoke-WebRequest -Uri $officialPage -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $html = if ($page.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($page.Content) } else { [string]$page.Content }
        $officialLink = 'href\s*=\s*["'']' + [regex]::Escape($installerUri) + '["'']'
        if ($html -notmatch $officialLink) {
            throw 'O endereço do instalador mudou na página oficial do XD. A transferência foi interrompida; consulte a página de transferências do fabricante.'
        }

        Write-WinUtilLog -Component XD -Message "A transferir o instalador publicado em $officialPage para $destination"
        Step-WinUtilJob -Status 'A transferir o XD (0%)...' -Percent 0 -State Normal
        Save-WinUtilFile -Uri $installerUri -DestinationPath $partial -AllowedHosts @('f003.backblazeb2.com') -ProgressCallback {
            param($percent)
            Step-WinUtilJob -Status "A transferir o XD ($percent%)..." -Percent $percent
        }

        $stream = [IO.File]::OpenRead($partial)
        try {
            if ($stream.Length -lt 1024 -or $stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) {
                throw 'O ficheiro recebido não é um executável Windows válido.'
            }
        } finally { $stream.Dispose() }

        # Authenticode needs the executable extension; no existing destination is replaced yet.
        $verifiedPath = [IO.Path]::ChangeExtension($partial, '.exe')
        Move-Item -LiteralPath $partial -Destination $verifiedPath -ErrorAction Stop
        $partial = $verifiedPath
        Step-WinUtilJob -Status 'A verificar o instalador do XD...' -State Indeterminate
        $signature = Get-AuthenticodeSignature -LiteralPath $partial -ErrorAction Stop
        if ($signature.Status -eq 'NotSigned') {
            Write-WinUtilLog -Component XD -Message 'O instalador publicado pelo fabricante não contém assinatura digital. Abertura automática solicitada pelo utilizador.'
        } elseif ($signature.Status -ne 'Valid') {
            throw "A assinatura digital do instalador XD não é válida ($($signature.Status)). O ficheiro não foi aberto."
        }

        if (Test-Path -LiteralPath $destination) { $destination = Get-WinUtilXDDownloadPath -Folder $folder }
        Move-Item -LiteralPath $partial -Destination $destination -ErrorAction Stop
        $sync.LastXDInstallerPath = $destination
        Step-WinUtilJob -Status 'A abrir o instalador do XD...' -Percent 100 -State Normal
        Open-WinUtilXDInstaller -Path $destination
        Write-WinUtilLog -Component XD -Message "Instalador aberto: $destination. A instalacao fica a cargo do utilizador."
        Step-WinUtilJob -Status 'Instalador do XD aberto. Conclua a instalação no assistente.' -Percent 100 -State Normal
    } finally {
        if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Open-WinUtilXDInstaller {
    param([Parameter(Mandatory)][string]$Path)
    $openInstaller = {
        param($InstallerPath)
        # The Windows shell opens the visible wizard on the STA interface thread.
        # No silent arguments and no -Wait: installation remains manual.
        Start-Process -FilePath $InstallerPath -WorkingDirectory ([IO.Path]::GetDirectoryName($InstallerPath)) -Verb Open -WindowStyle Normal -ErrorAction Stop | Out-Null
        return $true
    }
    $opened = $false
    if (Test-WinUtilUIAlive) {
        $opened = Invoke-WPFUIThread -PassThru -ScriptBlock $openInstaller -Parameters @{InstallerPath=$Path}
    }
    if (-not $opened) { & $openInstaller -InstallerPath $Path | Out-Null }
}

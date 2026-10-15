function Get-WinUtilDownloadPath {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$Folder = (Get-WinUtilDownloadsFolder)
    )
    if ([string]::IsNullOrWhiteSpace($FileName) -or $FileName -in @('.','..') -or $FileName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or [IO.Path]::GetFileName($FileName) -cne $FileName) {
        throw 'O nome do ficheiro de transferência não é válido.'
    }
    $stem = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [IO.Path]::GetExtension($FileName)
    for ($index = 0; $index -lt 10000; $index++) {
        $name = if ($index -eq 0) { $FileName } else { "$stem ($index)$extension" }
        $candidate = Join-Path $Folder $name
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw 'Não foi possível obter um nome livre na pasta Transferências.'
}

function Install-WinUtilZoneSoft {
    <# Downloads, extracts the complete package and opens only its signed Setup.exe elevated. #>
    param(
        [Parameter(Mandatory)][ValidateSet('Posto','SemSQL','Completo')][string]$Variant,
        [object[]]$Catalog = @(Get-WinUtilZoneSoftCatalog)
    )
    $packages = @($Catalog | Where-Object Variant -eq $Variant)
    if ($packages.Count -ne 1) { throw "Não foi encontrada uma versão inequívoca da edição ZoneSoft $Variant na pasta oficial. Nenhuma edição alternativa foi escolhida." }
    $package = $packages[0]
    $uri = [uri]$package.DownloadUri
    if ($uri.Scheme -ne 'https' -or $uri.DnsSafeHost -ne 'api-zslicweb.zonesoft.org' -or $uri.AbsolutePath -ne '/v1/manuals/download' -or $uri.UserInfo -or -not $uri.IsDefaultPort) {
        throw 'A origem da transferência ZoneSoft não é autorizada.'
    }
    if ([IO.Path]::GetExtension($package.FileName) -ine '.zip') { throw 'A transferência ZoneSoft não é um ZIP.' }
    $folder = Get-WinUtilDownloadsFolder
    $destination = Get-WinUtilDownloadPath -FileName $package.FileName -Folder $folder
    $partial = Join-Path $folder ('ZoneSoft-' + [guid]::NewGuid().ToString('N') + '.partial')
    $label = if ($Variant -eq 'SemSQL') { 'Sem SQL' } else { $Variant }
    try {
        Write-WinUtilLog -Component ZoneSoft -Message "A transferir a edição $label, versão $($package.Version), da pasta oficial ZS_POS_ZS_REST."
        Step-WinUtilJob -Status "A transferir ZoneSoft $label (0%)..." -Percent 0 -State Normal
        Save-WinUtilFile -Uri $uri -DestinationPath $partial -AllowedHosts @('api-zslicweb.zonesoft.org') -ProgressCallback {
            param($percent)
            Step-WinUtilJob -Status "A transferir ZoneSoft $label ($percent%)..." -Percent $percent -State Normal
        }
        $stream = [IO.File]::OpenRead($partial)
        try {
            if ($stream.Length -ne $package.Size -or $stream.Length -lt 4 -or $stream.ReadByte() -ne 80 -or $stream.ReadByte() -ne 75 -or $stream.ReadByte() -ne 3 -or $stream.ReadByte() -ne 4) {
                throw 'O ZIP ZoneSoft recebido está incompleto, não é válido ou mudou durante a transferência. Tente novamente.'
            }
        } finally { $stream.Dispose() }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = $null
        try {
            $archive = [IO.Compression.ZipFile]::OpenRead($partial)
            if ($archive.Entries.Count -eq 0) { throw 'O ZIP ZoneSoft recebido está vazio.' }
        } finally { if ($archive) { $archive.Dispose() } }

        # File.Move never overwrites. Re-resolve a name if another process creates it meanwhile.
        $moved = $false
        for ($attempt = 0; $attempt -lt 100 -and -not $moved; $attempt++) {
            try { [IO.File]::Move($partial, $destination); $moved = $true }
            catch [IO.IOException] {
                if (-not (Test-Path -LiteralPath $destination)) { throw }
                $destination = Get-WinUtilDownloadPath -FileName $package.FileName -Folder $folder
            }
        }
        if (-not $moved) { throw 'Não foi possível guardar o ZIP ZoneSoft sem substituir ficheiros existentes.' }
        $sync.LastZoneSoftArchivePath = $destination
        Step-WinUtilJob -Status "A extrair ZoneSoft $label..." -Percent 0 -State Normal
        $extracted = Expand-WinUtilZoneSoftArchive -Path $destination
        $sync.LastZoneSoftExtractedPath = $extracted.Directory
        Step-WinUtilJob -Status "A verificar e abrir o Setup do ZoneSoft $label como administrador..." -State Indeterminate
        Open-WinUtilZoneSoftSetup -Path $extracted.SetupPath
        $sync.LastZoneSoftSetupPath = $extracted.SetupPath
        Write-WinUtilLog -Component ZoneSoft -Message "Pacote extraído: $($extracted.Directory). Setup.exe aberto como administrador; a instalação fica a cargo do utilizador."
        Step-WinUtilJob -Status "Setup do ZoneSoft $label aberto. Conclua a instalação no assistente." -Percent 100 -State Normal
        [pscustomobject]@{Package="ZoneSoft $label";Manager='ZoneSoft';Action='Download';ExitCode=0;Outcome='Succeeded';Detail='ZIP transferido e extraído; Setup.exe aberto como administrador. Instalação manual.';Path=$destination;ExtractedPath=$extracted.Directory;SetupPath=$extracted.SetupPath;Version=$package.Version}
    } finally {
        if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Open-WinUtilZoneSoftSetup {
    param([Parameter(Mandatory)][string]$Path)
    $setupPath = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetFileName($setupPath) -ine 'Setup.exe' -or -not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        throw 'Não foi encontrado o Setup.exe esperado do ZoneSoft. Nenhum outro executável foi escolhido.'
    }
    if (((Get-Item -LiteralPath $setupPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'O Setup.exe não pode ser uma ligação para outro ficheiro.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $setupPath -ErrorAction Stop
    $expectedSigner = 'ZONE SOFT - FABRICO DE PRODUTOS SOFTWARE, UNIPESSOAL, LDA'
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ine $expectedSigner) {
        throw 'O Setup.exe não tem uma assinatura digital válida do fabricante ZoneSoft. A abertura como administrador foi bloqueada; o ZIP e a pasta extraída foram preservados.'
    }
    $openSetup = {
        param($SetupPath)
        # No silent switches or -Wait. RunAs uses the normal Windows elevation prompt.
        Start-Process -FilePath $SetupPath -WorkingDirectory ([IO.Path]::GetDirectoryName($SetupPath)) -Verb RunAs -WindowStyle Normal -ErrorAction Stop | Out-Null
        return $true
    }
    $opened = $false
    if (Test-WinUtilUIAlive) { $opened = Invoke-WPFUIThread -PassThru -ScriptBlock $openSetup -Parameters @{SetupPath=$setupPath} }
    if (-not $opened) { & $openSetup -SetupPath $setupPath | Out-Null }
}

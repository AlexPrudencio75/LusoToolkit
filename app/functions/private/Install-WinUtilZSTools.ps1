function Install-WinUtilZSTools {
    $package = Get-WinUtilZSToolsPackage
    $uri = [uri]$package.DownloadUri
    if ($uri.Scheme -ne 'https' -or $uri.DnsSafeHost -ne 'api-zslicweb.zonesoft.org' -or $uri.AbsolutePath -ne '/v1/manuals/download' -or $uri.UserInfo -or -not $uri.IsDefaultPort) { throw 'A origem da transferência ZSTools não é autorizada.' }
    $folder = Get-WinUtilDownloadsFolder
    $destination = Get-WinUtilDownloadPath -FileName $package.FileName -Folder $folder
    $partial = Join-Path $folder ('ZSTools-' + [guid]::NewGuid().ToString('N') + '.partial')
    try {
        Step-WinUtilJob -Status 'A transferir o ZSTools...' -Percent 0 -State Normal
        Save-WinUtilFile -Uri $uri -DestinationPath $partial -AllowedHosts @('api-zslicweb.zonesoft.org') -ProgressCallback { param($percent) Step-WinUtilJob -Status "A transferir ZSTools ($percent%)..." -Percent $percent -State Normal }
        $stream = [IO.File]::OpenRead($partial)
        try { if ($stream.Length -ne $package.Size -or $stream.Length -lt 4 -or $stream.ReadByte() -ne 80 -or $stream.ReadByte() -ne 75 -or $stream.ReadByte() -ne 3 -or $stream.ReadByte() -ne 4) { throw 'O ZIP ZSTools recebido não é válido ou está incompleto.' } }
        finally { $stream.Dispose() }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($partial)
        try { if ($archive.Entries.Count -eq 0) { throw 'O ZIP ZSTools recebido está vazio.' } } finally { $archive.Dispose() }
        $moved = $false
        for ($attempt=0; $attempt -lt 100 -and -not $moved; $attempt++) {
            try { [IO.File]::Move($partial,$destination); $moved=$true }
            catch [IO.IOException] { if (-not(Test-Path -LiteralPath $destination)) { throw }; $destination=Get-WinUtilDownloadPath -FileName $package.FileName -Folder $folder }
        }
        if (-not $moved) { throw 'Não foi possível guardar o ZIP ZSTools sem substituir downloads anteriores.' }
        $sync.LastZSToolsArchivePath = $destination
        $roots = @(Get-WinUtilZSRestRoots)
        $choice = Show-WinUtilZSToolsChoice -Roots $roots
        if ($choice.Mode -ne 'Deploy') {
            $outcome = if ($choice.Mode -eq 'Cancel') { 'Skipped' } else { 'Succeeded' }
            Write-WinUtilLog -Component ZSTools -Message "ZIP guardado em $destination. Modo: $($choice.Mode); não foi extraído, copiado ou executado."
            return [pscustomobject]@{Package='ZSTools';Manager='ZSTools';Action='Download';Outcome=$outcome;ExitCode=0;Detail='ZIP guardado; nenhuma instalação foi alterada e a ferramenta não foi aberta.';Path=$destination;Mode=$choice.Mode}
        }
        $root = Assert-WinUtilZSRestRoot -Path $choice.Root
        Step-WinUtilJob -Status 'A extrair o ZSTools...' -Percent 0 -State Normal
        $extracted = Expand-WinUtilZoneSoftArchive -Path $destination -RequiredExecutable 'ZSTools.exe'
        $deployed = Copy-WinUtilZSToolsToZSRest -SourceDirectory $extracted.Directory -Root $root
        Open-WinUtilZSTools -Root $root -ExpectedHash $deployed.ExecutableHash
        Write-WinUtilLog -Component ZSTools -Message "ZSTools copiado para $root e aberto. Cópia de segurança: $($deployed.BackupPath)"
        return [pscustomobject]@{Package='ZSTools';Manager='ZSTools';Action='Download / Copy';Outcome='Succeeded';ExitCode=0;Detail='Pacote extraído, copiado para a raiz ZSRest e ZSTools aberto.';Path=$destination;Mode='Deploy';Root=$root;BackupPath=$deployed.BackupPath}
    } finally {
        if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Get-WinUtilZSRestRunningApps {
    param([string]$Root)
    $blocked = @('ZSRest.exe','ZSPos.exe','ZSTools.exe') | ForEach-Object { Join-Path $Root $_ }
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try { $processPath = $process.Path } catch { continue }
        if ($processPath -and $blocked -contains $processPath) { $process.ProcessName }
    }
}

function Get-WinUtilZSToolsPayload {
    param([Parameter(Mandatory)][string]$Directory)
    if (((Get-Item -LiteralPath $Directory -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'A pasta extraída não pode ser uma ligação.' }
    $allowed = @('EN_ZSTOOLS.lng','ES_ZSTOOLS.lng','libeay32.dll','ssleay32.dll','ZSTools.exe')
    $items = @(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop)
    if ($items.Count -ne $allowed.Count) { throw 'O conteúdo do pacote ZSTools mudou. O ZIP foi preservado; nenhum ficheiro foi copiado para o ZSRest.' }
    $files = foreach ($item in $items) {
        if ($item.PSIsContainer -or $item.Name -notin $allowed -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'O pacote ZSTools contém pastas, ligações ou ficheiros inesperados. Nenhum ficheiro foi copiado.' }
        [pscustomobject]@{Name=$item.Name;Source=$item.FullName;Hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash}
    }
    $exe = Join-Path $Directory 'ZSTools.exe'
    $stream = [IO.File]::OpenRead($exe)
    try { if ($stream.Length -lt 1024 -or $stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) { throw 'O ZSTools.exe recebido não é um executável Windows válido.' } } finally { $stream.Dispose() }
    $signature = Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction Stop
    if ($signature.Status -eq 'NotSigned') {
        Write-WinUtilLog -Component ZSTools -Level INFO -Message 'O ZSTools publicado pelo fabricante não tem assinatura digital. A cópia e abertura foram escolhidas pelo utilizador após o download HTTPS oficial.'
    } elseif ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -ine 'ZONE SOFT - FABRICO DE PRODUTOS SOFTWARE, UNIPESSOAL, LDA') {
        throw 'A assinatura do ZSTools não é válida ou pertence a outro fabricante. A cópia foi bloqueada.'
    }
    return [pscustomobject]@{Files=@($files);ExecutableHash=($files|Where-Object Name -eq 'ZSTools.exe').Hash}
}

function Move-WinUtilZSToolsFile {
    param([string]$Source,[string]$Destination)
    if (Test-Path -LiteralPath $Destination) { [IO.File]::Replace($Source,$Destination,[NullString]::Value) }
    else { [IO.File]::Move($Source,$Destination) }
}

function Copy-WinUtilZSToolsToZSRest {
    param([Parameter(Mandatory)][string]$SourceDirectory,[Parameter(Mandatory)][string]$Root)
    $rootPath = Assert-WinUtilZSRestRoot -Path $Root
    if (@(Get-WinUtilZSRestRunningApps -Root $rootPath).Count -gt 0) { throw 'Feche o ZSRest, ZSPos e ZSTools desta instalação antes de copiar. Nenhum processo foi terminado e nenhum ficheiro foi substituído.' }
    $payload = Get-WinUtilZSToolsPayload -Directory $SourceDirectory
    $backupContainer = Join-Path $rootPath 'WinUtil-ZSTools-Backups'
    if (Test-Path -LiteralPath $backupContainer) {
        $existing = Get-Item -LiteralPath $backupContainer -Force
        if (-not $existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'A pasta de cópias de segurança não é uma pasta normal.' }
    }
    [void][IO.Directory]::CreateDirectory($backupContainer)
    $backup = Join-Path $backupContainer ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($backup)
    $sync.LastZSToolsBackupPath = $backup
    $stage = Join-Path $rootPath ('.winutil-zstools-stage-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $stage) { throw 'A pasta temporária de cópia já existe.' }
    [void][IO.Directory]::CreateDirectory($stage)
    $plan = [Collections.Generic.List[object]]::new()
    $changed = [Collections.Generic.List[object]]::new()
    $manifest = $null
    try {
        # Prepare every new file and every backup before replacing the first installed file.
        foreach ($file in $payload.Files) {
            $target = Join-Path $rootPath $file.Name
            $staged = Join-Path $stage $file.Name
            $backupFile = Join-Path $backup $file.Name
            $existed = Test-Path -LiteralPath $target
            $oldHash = $null
            if ($existed) {
                $old = Get-Item -LiteralPath $target -Force
                if ($old.PSIsContainer -or ($old.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Um destino ZSTools é uma pasta ou ligação; a cópia foi bloqueada.' }
                $probe = [IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $probe.Dispose()
                $oldHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                [IO.File]::Copy($target,$backupFile,$false)
                if ((Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash -ne $oldHash) { throw 'A cópia de segurança não corresponde ao ficheiro original.' }
            }
            [IO.File]::Copy($file.Source,$staged,$false)
            if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ne $file.Hash) { throw 'Um ficheiro mudou durante a preparação da cópia.' }
            $plan.Add([pscustomobject]@{Name=$file.Name;Target=$target;Staged=$staged;Backup=$backupFile;Existed=$existed;OldHash=$oldHash;NewHash=$file.Hash})
        }
        $manifest = [pscustomobject]@{Root=$rootPath;CreatedUtc=[DateTime]::UtcNow.ToString('o');Files=@($plan);State='Prepared'}
        [IO.File]::WriteAllText((Join-Path $backup 'manifest.json'),($manifest|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
        foreach ($item in $plan) {
            $null = Assert-WinUtilZSRestRoot -Path $rootPath
            $currentExists=Test-Path -LiteralPath $item.Target
            if ($currentExists -ne $item.Existed) { throw 'Um destino foi criado ou removido por outro processo durante a preparação.' }
            if ($currentExists) {
                $current=Get-Item -LiteralPath $item.Target -Force
                if ($current.PSIsContainer -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Um destino mudou para uma pasta ou ligação durante a cópia.' }
                if ((Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -ne $item.OldHash) { throw 'Um ficheiro instalado foi modificado por outro processo durante a preparação.' }
            }
            $changed.Add($item)
            Move-WinUtilZSToolsFile -Source $item.Staged -Destination $item.Target
            if ((Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -ne $item.NewHash) { throw 'A verificação do ficheiro copiado falhou.' }
        }
        $manifest.State='Completed'
        [IO.File]::WriteAllText((Join-Path $backup 'manifest.json'),($manifest|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
        return [pscustomobject]@{Root=$rootPath;BackupPath=$backup;Files=$plan.Count;ExecutableHash=$payload.ExecutableHash}
    } catch {
        $failure=$_.Exception.Message; $rollbackFailed=$false
        # Roll back only these five files, never the installation directory or its database.
        for ($index=$changed.Count-1; $index -ge 0; $index--) {
            $item=$changed[$index]
            try {
                $null=Assert-WinUtilZSRestRoot -Path $rootPath
                if (Test-Path -LiteralPath $item.Target) {
                    $current=Get-Item -LiteralPath $item.Target -Force
                    if ($current.PSIsContainer -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Destino inseguro na reversão.' }
                }
                if ($item.Existed) {
                    if ((Test-Path -LiteralPath $item.Target) -and (Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -eq $item.OldHash) { continue }
                    $restore=Join-Path $stage ('restore-'+$item.Name)
                    [IO.File]::Copy($item.Backup,$restore,$false)
                    Move-WinUtilZSToolsFile -Source $restore -Destination $item.Target
                    if ((Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -ne $item.OldHash) { throw 'Reversão incompleta.' }
                } elseif (Test-Path -LiteralPath $item.Target -PathType Leaf) {
                    if ((Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -ne $item.NewHash) { throw 'O ficheiro novo foi modificado por outro processo.' }
                    Remove-Item -LiteralPath $item.Target -Force -ErrorAction Stop
                }
            } catch { $rollbackFailed=$true }
        }
        if ($manifest) {
            $manifest.State=if($rollbackFailed){'RollbackIncomplete'}else{'RolledBack'}
            [IO.File]::WriteAllText((Join-Path $backup 'manifest.json'),($manifest|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
        }
        if ($rollbackFailed) { throw "A cópia ZSTools falhou e a reposição não ficou completa. Não abra o ZSTools; recupere os ficheiros da cópia de segurança: $backup. Motivo: $failure" }
        throw "A cópia ZSTools não foi concluída; os ficheiros substituídos foram repostos. Cópia de segurança: $backup. Motivo: $failure"
    } finally {
        # The only recursive cleanup target is the immediate GUID child created by this call.
        $stageFull=[IO.Path]::GetFullPath($stage).TrimEnd('\')
        if ([IO.Path]::GetDirectoryName($stageFull) -ieq $rootPath -and [IO.Path]::GetFileName($stageFull) -match '^\.winutil-zstools-stage-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $stageFull -PathType Container)) {
            $stageItem=Get-Item -LiteralPath $stageFull -Force
            if (($stageItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { Remove-Item -LiteralPath $stageFull -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Open-WinUtilZSTools {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedHash)
    $rootPath=Assert-WinUtilZSRestRoot -Path $Root
    $path=Join-Path $rootPath 'ZSTools.exe'
    if (-not(Test-Path -LiteralPath $path -PathType Leaf) -or ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'O ZSTools na instalação não corresponde ao ficheiro transferido. A abertura foi bloqueada.' }
    $openTool={param($ToolPath,$WorkingDirectory) Start-Process -FilePath $ToolPath -WorkingDirectory $WorkingDirectory -Verb RunAs -WindowStyle Normal -ErrorAction Stop|Out-Null;return $true}
    $opened=$false
    if(Test-WinUtilUIAlive){$opened=Invoke-WPFUIThread -PassThru -ScriptBlock $openTool -Parameters @{ToolPath=$path;WorkingDirectory=$rootPath}}
    if(-not $opened){& $openTool -ToolPath $path -WorkingDirectory $rootPath|Out-Null}
}

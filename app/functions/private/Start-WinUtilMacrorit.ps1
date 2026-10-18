function Get-WinUtilMacroritPackage {
    # The official rolling URL is deliberately pinned. A vendor update must be
    # inspected and republished here; changed bytes must never execute silently.
    [pscustomobject]@{
        Version='8.9.2'; Uri='https://disk-tool.com/download/mde/mde-free-portable.zip'
        Size=16773930L; Sha256='DD7738FCD346A0E8745DE9D96F4E0E1DA1F1D7C57F18386CA1CDB3749AE73B52'
        Publisher='Panzhihua Bada Technology Co., Ltd.'
        Executables=@{
            x64='B02A5F8A34F946FE4D1F8DB6EF9D524C5F2EA0CAF731D114A0B496366A112876'
            x86='864E499FFDAE25390094C9604B9A49B21F8DC0570205949EAA9DA348DB9F2ABE'
        }
        ApiHashes=@{
            x64='302CF9AE5F45621AECDFD74A1825B296509FC3073663903D1C87C82EB8FDA1E5'
            x86='0B72D321BFC9323C7681310D5545A2A169FC3F3EDE9DC0D055A51CB7A4F435CC'
        }
    }
}

function Get-WinUtilMacroritArchitecture {
    $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    if ($os.InstallationType -ne 'Client') { throw 'A edição Free integrada não se destina a Windows Server. Utilize uma edição/licença adequada do fabricante.' }
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture) {
        'AMD64' { return 'x64' }
        'x86' { return 'x86' }
        default { throw 'Este pacote Macrorit apenas foi validado para Windows x86/x64. A abertura em ARM64 não é disponibilizada.' }
    }
}

function Expand-WinUtilMacroritArchive {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Destination)
    # Destination must be a new directory inside the invocation's fresh folder.
    # Validate every entry before writing any payload. No generic EXE discovery.
    if (Test-Path -LiteralPath $Destination) { throw 'A pasta de extração Macrorit já existe; não será substituída.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        if ($archive.Entries.Count -eq 0 -or $archive.Entries.Count -gt 200) { throw 'Número de ficheiros inesperado no pacote Macrorit.' }
        $prefix = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $plan = [Collections.Generic.List[object]]::new(); $total=0L
        foreach ($entry in $archive.Entries) {
            $relative=$entry.FullName.Replace('/','\'); $directory=$relative.EndsWith('\')
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')) { throw 'Caminho inválido no pacote Macrorit.' }
            foreach ($part in $relative.TrimEnd('\').Split('\')) {
                if ([string]::IsNullOrWhiteSpace($part) -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') { throw 'Nome inválido no pacote Macrorit.' }
            }
            if ($relative -notmatch '^mde-free-portable\\' -or ($entry.ExternalAttributes -band 0x400) -ne 0 -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Estrutura ou ligação não permitida no pacote Macrorit.' }
            $target=[IO.Path]::GetFullPath((Join-Path $Destination $relative))
            if (-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($target.TrimEnd('\'))) { throw 'Caminho duplicado ou fora da pasta Macrorit.' }
            if (-not $directory) {
                if ($entry.Length -lt 0 -or $entry.Length -gt 64MB -or $total -gt (64MB - $entry.Length)) { throw 'O pacote Macrorit excede o limite descomprimido.' }
                $total += $entry.Length
            }
            $plan.Add([pscustomobject]@{Entry=$entry;Target=$target;Directory=$directory})
        }
        foreach ($architecture in @('x86','x64')) {
            foreach ($name in @('dm.exe','dm.api','core.dll','core2.dll','languages\PTG.lng')) {
                if (-not $seen.Contains((Join-Path $Destination "mde-free-portable\$architecture\$name"))) { throw "Falta $name ($architecture) no pacote Macrorit." }
            }
        }
        [void][IO.Directory]::CreateDirectory($Destination)
        foreach ($item in $plan) {
            if ($item.Directory) { [void][IO.Directory]::CreateDirectory($item.Target); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Target))
            $source=$null; $output=$null
            try {
                $source=$item.Entry.Open()
                $output=[IO.File]::Open($item.Target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                $source.CopyTo($output)
                if ($output.Length -ne $item.Entry.Length) { throw 'Extração incompleta do pacote Macrorit.' }
            } finally { if ($output) { $output.Dispose() }; if ($source) { $source.Dispose() } }
        }
    } finally { $archive.Dispose() }
}

function Start-WinUtilMacrorit {
    # Disk operations must outlive the UI. NEVER register this program in the
    # temporary-portable kill/cleanup system, a job object or an owner watchdog.
    $result=[pscustomobject]@{Package='Macrorit Partition Expert Portable';Manager='SafePortable';Action='Open';ExitCode=0;Outcome='Skipped';Detail='Abertura cancelada.';Path=$null}
    if (-not (Test-WinUtilUIAlive) -or $sync.PortableStopping) { throw 'É necessária uma interface aberta para abrir o Macrorit.' }
    $architecture=Get-WinUtilMacroritArchitecture
    # The selection + Open/Install action is the request to launch. Keep the
    # licence/safety notes in the card and docs, not an additional modal prompt.
    $package=Get-WinUtilMacroritPackage
    $base=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'LusoToolkit\PortableTools'))
    # Do not write through any redirected application directory.
    $ancestor=$base
    while ($ancestor) {
        if ((Test-Path -LiteralPath $ancestor) -and ([IO.File]::GetAttributes($ancestor) -band [IO.FileAttributes]::ReparsePoint)) { throw 'A pasta dos portáteis foi redirecionada; abertura cancelada.' }
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
    [void][IO.Directory]::CreateDirectory($base)
    $session=Join-Path $base ('Macrorit-' + $package.Version + '-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $session) { throw 'A pasta desta abertura Macrorit já existe.' }
    [void][IO.Directory]::CreateDirectory($session)
    $partial=Join-Path $session 'official.zip'; $locks=[Collections.Generic.List[IDisposable]]::new()
    try {
        Step-WinUtilJob -Status 'A transferir Macrorit Portable do fabricante...' -State Indeterminate
        $oldTls=[Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol=$oldTls -bor [Net.SecurityProtocolType]::Tls12
            Save-WinUtilFile -Uri $package.Uri -DestinationPath $partial -AllowedHosts @('disk-tool.com') -ProgressCallback { param($percent) Step-WinUtilJob -Status "A transferir Macrorit ($percent%)..." -Percent $percent }
        } finally { [Net.ServicePointManager]::SecurityProtocol=$oldTls }
        $zipLock=[IO.File]::Open($partial,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $locks.Add($zipLock)
        if ($zipLock.Length -ne $package.Size -or (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ine $package.Sha256) { throw 'O pacote Macrorit mudou ou ficou incompleto. Nada foi aberto; é necessária uma atualização verificada do LusoToolkit.' }
        Step-WinUtilJob -Status 'A extrair e verificar Macrorit Portable...' -State Indeterminate
        $destination=Join-Path $session 'app'
        Expand-WinUtilMacroritArchive -Path $partial -Destination $destination
        $directory=Join-Path $destination "mde-free-portable\$architecture"
        $executable=Join-Path $directory 'dm.exe'
        # Retain layout and all resources, not just dm.exe. Lock payload files
        # during verification/handoff so a concurrent write cannot swap them.
        foreach ($file in Get-ChildItem -LiteralPath $destination -Recurse -File) {
            $locks.Add([IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
        }
        foreach ($name in @('dm.exe','dm.api')) {
            $path=Join-Path $directory $name
            $hash=if ($name -eq 'dm.exe') { $package.Executables[$architecture] } else { $package.ApiHashes[$architecture] }
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $hash) { throw 'Integridade do executável Macrorit inválida.' }
            $signature=Get-AuthenticodeSignature -LiteralPath $path
            if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo('SimpleName',$false) -ne $package.Publisher) { throw 'Assinatura digital Macrorit inválida ou de outro fabricante; nada foi aberto.' }
        }
        $result.Path=$directory; $sync.LastMacroritPortablePath=$directory
        if (-not (Test-WinUtilUIAlive) -or $sync.PortableStopping) { throw 'A interface foi fechada. O pacote verificado foi preservado mas não foi aberto.' }
        $opened=Invoke-WPFUIThread -PassThru -Parameters @{Executable=$executable;Directory=$directory} -ScriptBlock {
            param($Executable,$Directory)
            if (-not (Test-WinUtilUIAlive) -or $sync.PortableStopping) { return $false }
            # Independent visible GUI. No operation arguments, no -Wait, no
            # process teardown on close and no automatic folder deletion.
            Start-Process -FilePath $Executable -WorkingDirectory $Directory -Verb RunAs -WindowStyle Normal -ErrorAction Stop | Out-Null
            return $true
        }
        if (-not $opened) { throw 'Não foi possível abrir o Macrorit.' }
        $result.Outcome='Succeeded'; $result.Detail='Macrorit aberto como administrador, sem instalador. Continua aberto ao fechar o PowerShell; pasta mantida por segurança.'
        Write-WinUtilLog -Component Macrorit -Message ($result.Detail + ' Pasta: ' + $directory)
        Step-WinUtilJob -Status 'Macrorit aberto; conclua as operações e feche-o manualmente.' -Percent 100
        return $result
    } finally {
        foreach ($lock in $locks) { $lock.Dispose() }
        # Never remove program resources here: shell handoff can succeed even
        # if the caller subsequently fails, and reboot operations may need them.
        if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

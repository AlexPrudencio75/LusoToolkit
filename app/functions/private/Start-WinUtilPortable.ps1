function Start-WinUtilPortable {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-WinUtilUIAlive) -or $sync.PortableStopping) { throw 'A abertura de portateis requer a interface aberta.' }
    $entry = @(Get-WinUtilPortableCatalog | Where-Object Id -eq $Id)
    if ($entry.Count -ne 1) { throw 'Portatil nao reconhecido.' }; $entry = $entry[0]
    . (Join-Path $sync.projectRoot 'scripts\portable-storage.ps1')
    $base = Get-LusoPortableBase
    if (Test-Path -LiteralPath $base) {
        if ([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) { throw 'A pasta temporaria de portateis foi redirecionada.' }
    } else { [void][IO.Directory]::CreateDirectory($base) }
    $token = [guid]::NewGuid().ToString('N')
    $sessionPath = Join-Path $base $token
    if (Test-Path -LiteralPath $sessionPath) { throw 'A pasta desta sessao ja existe.' }
    [void][IO.Directory]::CreateDirectory($sessionPath)
    $ownerProcess = [Diagnostics.Process]::GetCurrentProcess()
    try { $ownerTicks = $ownerProcess.StartTime.ToUniversalTime().Ticks }
    finally { $ownerProcess.Dispose() }
    $marker = [ordered]@{ Schema=1; Token=$token; AppId=$Id; OwnerId=$PID; OwnerTicks=$ownerTicks }
    [IO.File]::WriteAllText((Join-Path $sessionPath '.session.json'), ($marker | ConvertTo-Json -Compress), [Text.Encoding]::UTF8)
    $lock = $null; $hostProcess = $null; $handedOff = $false
    try {
        $lock = [IO.File]::Open((Join-Path $sessionPath '.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        $appDirectory = Join-Path $sessionPath 'app'
        [void][IO.Directory]::CreateDirectory($appDirectory)
        $target = Join-Path $appDirectory $entry.File
        $uri = [uri]$entry.Url
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'raw.githubusercontent.com' -or
            -not $uri.AbsolutePath.StartsWith('/AlexPrudencio75/LusoToolkit/main/portables/', [StringComparison]::Ordinal)) { throw 'Origem do portatil nao autorizada.' }
        Step-WinUtilJob -Status ('A transferir ' + $entry.Name + ' para uso temporario...') -State Indeterminate
        $oldTls = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $oldTls -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $entry.Url -OutFile $target -UseBasicParsing -TimeoutSec 180 -MaximumRedirection 3 -ErrorAction Stop | Out-Null
        } finally { [Net.ServicePointManager]::SecurityProtocol = $oldTls }
        if ((Get-Item -LiteralPath $target).Length -ne $entry.Size -or
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $entry.Sha256) { throw 'Integridade do portatil invalida; abertura cancelada.' }
        $stream = [IO.File]::OpenRead($target)
        try { if ($stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) { throw 'O ficheiro nao e um executavel Windows.' } }
        finally { $stream.Dispose() }
        $signature = Get-AuthenticodeSignature -LiteralPath $target
        if ($signature.Status -notin @('NotSigned','Valid')) { throw ('Assinatura do portatil invalida: ' + $signature.Status) }
        if ($signature.Status -eq 'NotSigned') { Write-WinUtilLog -Component Portable -Message ($entry.Name + ': ficheiro fornecido sem assinatura digital; SHA-256 confirmado.') }
        if ($sync.PortableStopping -or -not (Test-WinUtilUIAlive)) { throw 'Abertura cancelada: a interface foi encerrada.' }
        $record = [pscustomobject]@{ Path=$sessionPath; Name=$entry.Name; HostProcess=$null }
        [Threading.Monitor]::Enter($sync.SyncRoot)
        try {
            if ($null -eq $sync.PortableSessions) { $sync.PortableSessions = [Collections.ArrayList]::Synchronized([Collections.ArrayList]::new()) }
            [void]$sync.PortableSessions.Add($record)
        } finally { [Threading.Monitor]::Exit($sync.SyncRoot) }
        $lock.Dispose(); $lock = $null
        $windowsPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $hostScript = Join-Path $sync.projectRoot 'scripts\portable-host.ps1'
        $hostProcess = Start-Process -FilePath $windowsPS -WindowStyle Hidden -WorkingDirectory $sync.projectRoot -PassThru -ErrorAction Stop `
            -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $hostScript + '" -SessionPath "' + $sessionPath + '"')
        $record.HostProcess = $hostProcess
        $handedOff = $true
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while ($clock.Elapsed.TotalSeconds -lt 30) {
            if ($sync.PortableStopping -and (Test-Path -LiteralPath $sessionPath)) {
                try { [IO.File]::WriteAllText((Join-Path $sessionPath '.stop'), 'close') } catch { }
            }
            if (Test-Path -LiteralPath (Join-Path $sessionPath '.ready.json')) {
                Write-WinUtilLog -Component Portable -Message ($entry.Name + ' aberto em modo temporario; o anfitriao acompanha a limpeza.')
                return [pscustomobject]@{ Package=$entry.Name; Manager='Portable'; Action='Open'; ExitCode=0; Outcome='Succeeded'; Detail='Portatil temporario aberto; nao instalado.' }
            }
            if ($hostProcess.HasExited) {
                if ($hostProcess.ExitCode -eq 0) { return [pscustomobject]@{Package=$entry.Name;Manager='Portable';Action='Open';ExitCode=0;Outcome='Succeeded';Detail='Portatil encerrado e limpeza solicitada.'} }
                throw 'O portatil nao abriu. Pode necessitar de dependencias que nao acompanham este executavel; consulte o fabricante.'
            }
            Start-Sleep -Milliseconds 100
        }
        if (Test-Path -LiteralPath $sessionPath) { [IO.File]::WriteAllText((Join-Path $sessionPath '.stop'), 'startup-timeout') }
        throw 'A abertura do portatil excedeu o tempo de espera e foi cancelada.'
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
        if (-not $handedOff) { try { $null = Remove-LusoPortableSession $sessionPath -Completed } catch { Write-WinUtilLog -Component Portable -Level WARN -Message 'A limpeza de uma copia temporaria ficou pendente para o proximo arranque.' } }
    }
}

function Get-WinUtilPortableSessions {
    if ($null -eq $sync.PortableSessions) { return @() }
    [Threading.Monitor]::Enter($sync.PortableSessions.SyncRoot)
    try { return @($sync.PortableSessions.ToArray() | Where-Object { Test-Path -LiteralPath $_.Path }) }
    finally { [Threading.Monitor]::Exit($sync.PortableSessions.SyncRoot) }
}

function Stop-WinUtilPortableSessions {
    param([switch]$NoWait)
    $sync.PortableStopping = $true
    . (Join-Path $sync.projectRoot 'scripts\portable-storage.ps1')
    $records = @(Get-WinUtilPortableSessions)
    foreach ($record in $records) {
        try {
            $info = Read-LusoPortableSession $record.Path
            if ([int]$info.OwnerId -eq $PID) { [IO.File]::WriteAllText((Join-Path $record.Path '.stop'), 'owner-closed') }
        } catch { Write-WinUtilLog -Component Portable -Level WARN -Message ('Nao foi possivel sinalizar a limpeza de ' + $record.Name) }
    }
    if ($NoWait) { return }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt 8 -and @(Get-WinUtilPortableSessions).Count -gt 0) { Start-Sleep -Milliseconds 100 }
}

function Clear-WinUtilAbandonedPortables {
    . (Join-Path $sync.projectRoot 'scripts\portable-storage.ps1')
    $base = Get-LusoPortableBase
    if (-not (Test-Path -LiteralPath $base)) { return }
    if ([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) { return }
    foreach ($directory in Get-ChildItem -LiteralPath $base -Directory -Force) {
        if ($directory.Name -notmatch '^[a-f0-9]{32}$') { continue }
        try { $null = Remove-LusoPortableSession $directory.FullName } catch { Write-WinUtilLog -Component Portable -Level WARN -Message 'Uma pasta temporaria nao reconhecida foi preservada por seguranca.' }
    }
}

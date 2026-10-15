param([Parameter(Mandatory)][string]$SessionPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'portable-storage.ps1')
. (Join-Path $PSScriptRoot '..\functions\private\Get-WinUtilPortableCatalog.ps1')
$lock = $null; $portable = $null; $ownerProcess = $null; $exitCode = 1
try {
    $info = Read-LusoPortableSession $SessionPath
    if (-not (Test-LusoPortableOwnerAlive $info)) { throw 'A aplicacao principal ja terminou.' }
    $lock = [IO.File]::Open((Join-Path $SessionPath '.lock'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
    $ownerProcess = [Diagnostics.Process]::GetProcessById([int]$info.OwnerId)
    if ($ownerProcess.StartTime.ToUniversalTime().Ticks -ne [long]$info.OwnerTicks) { throw 'A sessao principal mudou.' }
    $entry = @(Get-WinUtilPortableCatalog | Where-Object Id -eq $info.AppId)
    if ($entry.Count -ne 1) { throw 'Portatil desconhecido.' }; $entry = $entry[0]
    Test-LusoPortablePlainTree $SessionPath
    $executable = Join-Path (Join-Path $SessionPath 'app') $entry.File
    if ((Get-Item -LiteralPath $executable).Length -ne $entry.Size -or
        (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash -ine $entry.Sha256) { throw 'Integridade do executavel invalida.' }
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PortableProcess.cs'))) -Language CSharp
    $temporary = Join-Path $SessionPath 'data'
    [void][IO.Directory]::CreateDirectory($temporary)
    # Never execute a download if the owner closed while verification was in progress.
    if ($ownerProcess.HasExited -or (Test-Path -LiteralPath (Join-Path $SessionPath '.stop'))) { throw 'Abertura cancelada: aplicacao principal encerrada.' }
    $portable = [LusoToolkit.PortableProcess]::new($executable, [IO.Path]::GetDirectoryName($executable), $temporary)
    [IO.File]::WriteAllText((Join-Path $SessionPath '.ready.json'), ('{"ProcessId":' + $portable.ProcessId + '}'))
    while ($portable.ActiveProcesses -gt 0) {
        if ($ownerProcess.HasExited -or (Test-Path -LiteralPath (Join-Path $SessionPath '.stop'))) {
            $portable.RequestClose()
            $grace = [Diagnostics.Stopwatch]::StartNew()
            while ($portable.ActiveProcesses -gt 0 -and $grace.Elapsed.TotalSeconds -lt 3) { Start-Sleep -Milliseconds 100 }
            if ($portable.ActiveProcesses -gt 0) { $portable.Stop() }
            break
        }
        Start-Sleep -Milliseconds 300
    }
    $exitCode = 0
} catch {
    try { [IO.File]::WriteAllText((Join-Path $SessionPath '.error.txt'), $_.Exception.Message) } catch { }
} finally {
    if ($null -ne $portable) { $portable.Dispose() }
    if ($null -ne $ownerProcess) { $ownerProcess.Dispose() }
    if ($null -ne $lock) { $lock.Dispose() }
    # Retry boundedly for Windows releasing image handles / antivirus scanning.
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        try { if (Remove-LusoPortableSession $SessionPath -Completed) { break } } catch { break }
        Start-Sleep -Milliseconds 300
    }
}
exit $exitCode

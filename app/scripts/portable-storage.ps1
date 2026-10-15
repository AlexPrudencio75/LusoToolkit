# Shared by the interface and isolated portable host. No executable is run here.
function Get-LusoPortableBase {
    [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'LusoToolkit-Portables')).TrimEnd('\')
}

function Test-LusoPortablePlainTree {
    param([string]$Path)
    $queue = [Collections.Generic.Stack[string]]::new()
    $queue.Push($Path)
    while ($queue.Count -gt 0) {
        $current = $queue.Pop()
        $attributes = [IO.File]::GetAttributes($current)
        if ($attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links e junctions nao sao permitidos nas pastas temporarias.' }
        if ($attributes -band [IO.FileAttributes]::Directory) {
            foreach ($child in [IO.Directory]::EnumerateFileSystemEntries($current)) { $queue.Push($child) }
        }
    }
}

function Read-LusoPortableSession {
    param([Parameter(Mandatory)][string]$SessionPath)
    $base = Get-LusoPortableBase
    $full = [IO.Path]::GetFullPath($SessionPath).TrimEnd('\')
    $name = [IO.Path]::GetFileName($full)
    if ([IO.Path]::GetDirectoryName($full) -ine $base -or $name -notmatch '^[a-f0-9]{32}$') { throw 'Destino fora da area temporaria de portateis.' }
    if (([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) -or
        ([IO.File]::GetAttributes($full) -band [IO.FileAttributes]::ReparsePoint)) { throw 'Destino temporario redirecionado.' }
    $marker = Join-Path $full '.session.json'
    if (([IO.File]::GetAttributes($marker) -band [IO.FileAttributes]::ReparsePoint) -or (Get-Item -LiteralPath $marker).Length -gt 8192) { throw 'Marcador temporario invalido.' }
    $info = [IO.File]::ReadAllText($marker, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    if ($info.Schema -ne 1 -or $info.Token -cne $name -or $info.AppId -notin @('zonesoft_converter','auditor_rede','ligabd','netscan') -or
        $info.OwnerId -le 0 -or $info.OwnerTicks -le 0) { throw 'Marcador de sessao nao reconhecido.' }
    return $info
}

function Test-LusoPortableOwnerAlive {
    param($Info)
    $ownerProcess = $null
    try {
        $ownerProcess = [Diagnostics.Process]::GetProcessById([int]$Info.OwnerId)
        return (-not $ownerProcess.HasExited -and $ownerProcess.StartTime.ToUniversalTime().Ticks -eq [long]$Info.OwnerTicks)
    } catch { return $false }
    finally { if ($null -ne $ownerProcess) { $ownerProcess.Dispose() } }
}

function Remove-LusoPortableSession {
    param([Parameter(Mandatory)][string]$SessionPath, [switch]$Completed)
    if (-not (Test-Path -LiteralPath $SessionPath)) { return $true }
    $null = Read-LusoPortableSession $SessionPath
    $info = Read-LusoPortableSession $SessionPath
    # Recovery never races a preparing/running session owned by another live instance.
    if (-not $Completed -and (Test-LusoPortableOwnerAlive $info)) { return $false }
    $lockPath = Join-Path $SessionPath '.lock'
    $probe = $null
    try { $probe = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { return $false }
    finally { if ($null -ne $probe) { $probe.Dispose() } }
    Test-LusoPortablePlainTree $SessionPath
    # Only this GUID session is eligible. Never a recursive delete of TEMP, a drive or the base.
    # Remove leaves first; do not follow any reparse point, even if introduced during cleanup.
    $files = [Collections.Generic.List[string]]::new()
    $directories = [Collections.Generic.List[string]]::new()
    $queue = [Collections.Generic.Stack[string]]::new(); $queue.Push($SessionPath)
    while ($queue.Count -gt 0) {
        $current = $queue.Pop()
        foreach ($child in [IO.Directory]::EnumerateFileSystemEntries($current)) {
            $attr = [IO.File]::GetAttributes($child)
            if ($attr -band [IO.FileAttributes]::ReparsePoint) { throw 'Limpeza recusada: link inesperado.' }
            if ($attr -band [IO.FileAttributes]::Directory) { $directories.Add($child); $queue.Push($child) }
            elseif ($child -ine (Join-Path $SessionPath '.session.json')) { $files.Add($child) }
        }
    }
    try {
        foreach ($file in $files) {
            if ([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) { throw 'Link inesperado durante a limpeza.' }
            [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal); [IO.File]::Delete($file)
        }
        foreach ($directory in @($directories | Sort-Object Length -Descending)) {
            if ([IO.File]::GetAttributes($directory) -band [IO.FileAttributes]::ReparsePoint) { throw 'Link inesperado durante a limpeza.' }
            [IO.Directory]::Delete($directory, $false)
        }
        [IO.File]::Delete((Join-Path $SessionPath '.session.json'))
        [IO.Directory]::Delete($SessionPath, $false)
        return $true
    } catch { return $false }
}

function Expand-WinUtilZoneSoftArchive {
    <#
        Extracts every file beside the downloaded ZIP, retaining the vendor layout.
        Only a root-level Setup.exe is accepted; redistributables are never selected.
        All paths are validated before extraction and no existing directory is reused.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Setup.exe','ZSTools.exe')][string]$RequiredExecutable = 'Setup.exe'
    )
    $zipPath = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($zipPath) -ine '.zip' -or -not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw 'O arquivo ZIP ZoneSoft não foi encontrado.' }
    $parent = [IO.Path]::GetDirectoryName($zipPath)
    $folderName = [IO.Path]::GetFileNameWithoutExtension($zipPath)
    $staging = Join-Path $parent ('.ZoneSoft-' + [guid]::NewGuid().ToString('N') + '.extracting')
    $archive = $null
    $ownsStaging = $false
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        if ($archive.Entries.Count -eq 0 -or $archive.Entries.Count -gt 100000) { throw 'O ZIP ZoneSoft está vazio ou contém demasiadas entradas.' }
        $targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $plan = [Collections.Generic.List[object]]::new()
        $totalBytes = 0L
        $setupCount = 0
        $stagingPrefix = [IO.Path]::GetFullPath($staging).TrimEnd('\') + '\'
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('/', '\')
            $isDirectory = $relative.EndsWith('\')
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')) { throw 'O ZIP ZoneSoft contém um caminho absoluto ou inválido.' }
            $segments = $relative.TrimEnd('\').Split('\')
            foreach ($segment in $segments) {
                if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.','..') -or $segment.EndsWith('.') -or $segment.EndsWith(' ') -or $segment.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
                    throw 'O ZIP ZoneSoft contém um nome de ficheiro ou pasta não permitido.'
                }
            }
            if (($entry.ExternalAttributes -band 0x400) -ne 0 -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'O ZIP ZoneSoft contém uma ligação simbólica não permitida.' }
            $target = [IO.Path]::GetFullPath((Join-Path $staging $relative))
            if (-not $target.StartsWith($stagingPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not $targets.Add($target.TrimEnd('\'))) { throw 'O ZIP ZoneSoft contém caminhos repetidos ou fora da pasta de extração.' }
            if (-not $isDirectory) {
                if ($entry.Length -lt 0 -or $entry.Length -gt ([long]::MaxValue - $totalBytes)) { throw 'O tamanho descomprimido do ZIP não é válido.' }
                $totalBytes += $entry.Length
                if ($relative -ieq $RequiredExecutable) { $setupCount++ }
            }
            $plan.Add([pscustomobject]@{Entry=$entry;Target=$target;IsDirectory=$isDirectory})
        }
        if ($setupCount -ne 1) { throw "O ZIP não contém um único $RequiredExecutable na raiz. Nenhum outro executável foi escolhido." }
        $driveRoot = [IO.Path]::GetPathRoot($parent)
        if ($driveRoot -match '^[A-Za-z]:\\$') {
            $drive = [IO.DriveInfo]::new($driveRoot)
            if ($drive.IsReady -and $drive.AvailableFreeSpace -lt ($totalBytes + 10MB)) { throw 'Não existe espaço livre suficiente para extrair o ZoneSoft. O ZIP foi preservado.' }
        }
        if (Test-Path -LiteralPath $staging) { throw 'A pasta temporária de extração já existe.' }
        [void][IO.Directory]::CreateDirectory($staging)
        $ownsStaging = $true
        $buffer = New-Object byte[] 1048576
        $extractedBytes = 0L
        $lastPercent = -1
        foreach ($item in $plan) {
            if ($item.IsDirectory) { [void][IO.Directory]::CreateDirectory($item.Target); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Target))
            $source = $null; $destination = $null; $entryBytes = 0L
            try {
                $source = $item.Entry.Open()
                $destination = [IO.File]::Open($item.Target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $destination.Write($buffer, 0, $read)
                    $entryBytes += $read; $extractedBytes += $read
                    $percent = if ($totalBytes -gt 0) { [Math]::Min(100, [int](100.0 * $extractedBytes / $totalBytes)) } else { 100 }
                    if ($percent -ne $lastPercent) { Step-WinUtilJob -Status "A extrair o pacote ZoneSoft ($percent%)..." -Percent $percent -State Normal; $lastPercent = $percent }
                }
                if ($entryBytes -ne $item.Entry.Length) { throw 'Um ficheiro do ZIP ZoneSoft ficou incompleto durante a extração.' }
            } finally {
                if ($destination) { $destination.Dispose() }
                if ($source) { $source.Dispose() }
            }
        }
        $archive.Dispose(); $archive = $null
        $finalDirectory = $null
        for ($index = 0; $index -lt 10000; $index++) {
            $name = if ($index -eq 0) { $folderName } else { "$folderName ($index)" }
            $candidate = Join-Path $parent $name
            if (Test-Path -LiteralPath $candidate) { continue }
            try { [IO.Directory]::Move($staging, $candidate); $finalDirectory = $candidate; $ownsStaging = $false; break }
            catch [IO.IOException] { if (-not (Test-Path -LiteralPath $candidate)) { throw } }
        }
        if (-not $finalDirectory) { throw 'Não foi possível criar uma pasta nova para o ZoneSoft sem substituir ficheiros.' }
        [pscustomobject]@{Directory=$finalDirectory;SetupPath=(Join-Path $finalDirectory 'Setup.exe');ExecutablePath=(Join-Path $finalDirectory $RequiredExecutable);ExtractedBytes=$extractedBytes;Files=@($plan | Where-Object { -not $_.IsDirectory }).Count}
    } finally {
        if ($archive) { $archive.Dispose() }
        if ($ownsStaging -and (Test-Path -LiteralPath $staging -PathType Container)) {
            # This cleanup is restricted to the new, immediate GUID child created above.
            $cleanupPath = [IO.Path]::GetFullPath($staging).TrimEnd('\')
            $cleanupName = [IO.Path]::GetFileName($cleanupPath)
            $cleanupItem = Get-Item -LiteralPath $cleanupPath -Force
            if ([IO.Path]::GetDirectoryName($cleanupPath) -ieq $parent -and $cleanupName -match '^\.ZoneSoft-[0-9a-f]{32}\.extracting$' -and ($cleanupItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

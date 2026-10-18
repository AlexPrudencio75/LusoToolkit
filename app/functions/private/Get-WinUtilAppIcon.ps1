function Get-WinUtilAppIcon {
    <# Load bundled application artwork synchronously; never contact a favicon service. #>
    param([Parameter(Mandatory)][string]$AppKey)

    $app = $sync.configs.applicationsHashtable[$AppKey]
    $relative = [string]$app.icon
    if (-not $sync.projectRoot -or $relative -cnotmatch '^assets/app-icons/[a-z0-9_-]+\.png$') { return $null }
    $path = Join-Path $sync.projectRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if ($null -eq $script:WinUtilAppIconCache) { $script:WinUtilAppIconCache = @{} }
    if ($script:WinUtilAppIconCache.ContainsKey($path)) { return $script:WinUtilAppIconCache[$path] }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $bitmap = New-Object Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.CreateOptions = [Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
        $bitmap.UriSource = [uri]::new([IO.Path]::GetFullPath($path), [UriKind]::Absolute)
        $bitmap.EndInit()
        if ($bitmap.PixelWidth -lt 1 -or $bitmap.PixelHeight -lt 1) { return $null }
        $bitmap.Freeze()
        $script:WinUtilAppIconCache[$path] = $bitmap
        return $bitmap
    } catch {
        # A damaged/missing asset must not hide the card or prevent selecting it.
        return $null
    }
}

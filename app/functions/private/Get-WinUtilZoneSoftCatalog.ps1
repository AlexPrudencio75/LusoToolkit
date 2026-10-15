function Get-WinUtilZoneSoftCatalog {
    <#
        Uses the same public listing as the official Setups & Manuais page.
        No browser session, credentials or undocumented authentication workaround.
        Only the three requested editions in the exact product folder are accepted.
    #>
    $prefix = 'PT/Ultimas Versões/ZS_POS_ZS_REST/'
    $endpoint = 'https://api-zslicweb.zonesoft.org/v1/manuals/'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
        $listing = Invoke-RestMethod -Uri ($endpoint + 'list?prefix=' + [uri]::EscapeDataString($prefix)) -Method Get -TimeoutSec 30 -MaximumRedirection 0 -ErrorAction Stop
    } catch {
        # Do not retry with guessed credentials, scrape an existing browser session or log bodies.
        throw 'Não foi possível consultar as transferências oficiais do ZoneSoft. O portal pode estar indisponível ou passar a exigir autenticação. Nenhuma credencial foi utilizada; tente mais tarde ou consulte o portal.'
    }
    if ($listing.status -ne 'ok' -or $null -eq $listing.data) { throw 'A listagem oficial do ZoneSoft tem um formato inesperado. Nenhum ficheiro foi transferido.' }

    $candidates = foreach ($file in @($listing.data)) {
        if ($file.isFolder -ne $false) { continue }
        $match = [regex]::Match([string]$file.name, '^ZSSetup (?<version>\d+(?:\.\d+){1,3})(?<edition>-Posto|-Sem SQL)?\.zip$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { continue }
        # Reject nested paths or a file key that does not match its displayed name.
        if ([string]$file.id -cne ($prefix + [string]$file.name)) { throw 'A listagem ZoneSoft contém um caminho inesperado. A transferência foi interrompida.' }
        $size = 0L
        if (-not [long]::TryParse([string]$file.size, [ref]$size) -or $size -le 0) { throw 'O tamanho publicado para um ZIP ZoneSoft não é válido.' }
        $variant = switch ($match.Groups['edition'].Value.ToLowerInvariant()) {
            '-posto' { 'Posto' }
            '-sem sql' { 'SemSQL' }
            default { 'Completo' }
        }
        [pscustomobject]@{
            Variant = $variant
            Version = [version]$match.Groups['version'].Value
            FileName = [string]$file.name
            Size = $size
            DownloadUri = $endpoint + 'download?key=' + [uri]::EscapeDataString([string]$file.id)
        }
    }
    foreach ($variant in @('Posto','SemSQL','Completo')) {
        $latest = @($candidates | Where-Object Variant -eq $variant | Sort-Object Version -Descending | Select-Object -First 1)
        if ($latest.Count -gt 0) { $latest[0] }
    }
}

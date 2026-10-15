function Get-WinUtilInstallerArchitecture {
    $nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($nativeArchitecture -eq 'ARM64') { return 'arm64' }
    if ([Environment]::Is64BitOperatingSystem) { return 'x64' }
    return 'x86'
}

function Get-WinUtilPdfCraftProducts {
    # Reading uninstall records avoids Win32_Product, which can trigger MSI repairs.
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $seen = @{}
    foreach ($root in $roots) {
        foreach ($entry in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
            $productCode = [guid]::Empty
            if ($entry.DisplayName -ieq 'PdfCraft' -and [guid]::TryParse([string]$entry.PSChildName, [ref]$productCode)) {
                $code = $productCode.ToString('B')
                if (-not $seen.ContainsKey($code)) { $seen[$code] = $true; $code }
            }
        }
    }
}

function Install-WinUtilPdfCraft {
    param([ValidateSet('Install','Uninstall')][string]$Action = 'Install')

    if ($Action -eq 'Uninstall') {
        $products = @(Get-WinUtilPdfCraftProducts)
        if ($products.Count -eq 0) {
            return [pscustomobject]@{Package='PdfCraft';Manager='MSI';Action=$Action;ExitCode=1605;Outcome='Skipped';Detail='Não foi encontrada uma instalação MSI do PdfCraft. Verifique as Aplicações instaladas do Windows.'}
        }
        foreach ($code in $products) {
            $process = Start-Process -FilePath msiexec.exe -ArgumentList @('/x', $code, '/qn', '/norestart') -Wait -PassThru -ErrorAction Stop
            $outcome = if ($process.ExitCode -in @(0,3010)) { 'Succeeded' } elseif ($process.ExitCode -eq 1605) { 'Skipped' } else { 'Failed' }
            if ($outcome -eq 'Failed') { Write-WinUtilLog -Level ERROR -Component Package -Message "Falha ao desinstalar PdfCraft. Código MSI: $($process.ExitCode)" }
            [pscustomobject]@{Package='PdfCraft';Manager='MSI';Action=$Action;ExitCode=$process.ExitCode;Outcome=$outcome;Detail="Codigo MSI: $($process.ExitCode)"}
        }
        return
    }

    $architecture = Get-WinUtilInstallerArchitecture
    $base = 'https://github.com/storytold/pdfcraft/releases/download/v0.6.0/'
    $filename = "pdfcraft-0.6.0-windows-$architecture.msi"
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('PdfCraft-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -ErrorAction Stop | Out-Null
    $msiPath = Join-Path $tempDir $filename
    $sumPath = Join-Path $tempDir 'SHA256SUMS.txt'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Save-WinUtilFile -Uri ($base + $filename) -DestinationPath $msiPath -ProgressCallback {
            param($percent)
            Step-WinUtilJob -Status "A transferir o PdfCraft ($percent%)..." -Percent $percent
        }
        Invoke-WebRequest -Uri ($base + 'SHA256SUMS.txt') -OutFile $sumPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $sumLine = Get-Content -LiteralPath $sumPath | Where-Object { $_ -match ([regex]::Escape($filename) + '$') } | Select-Object -First 1
        if (-not $sumLine -or $sumLine -notmatch '^([0-9a-fA-F]{64})\s+\*?') { throw 'O checksum oficial do PdfCraft não está disponível.' }
        $expected = $Matches[1]
        if ((Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash -ine $expected) { throw 'A verificação SHA-256 do instalador PdfCraft falhou.' }
        $process = Start-Process -FilePath msiexec.exe -ArgumentList @('/i', ('"' + $msiPath + '"'), '/qn', '/norestart') -Wait -PassThru -ErrorAction Stop
        $outcome = if ($process.ExitCode -in @(0,3010)) { 'Succeeded' } else { 'Failed' }
        if ($outcome -eq 'Failed') { Write-WinUtilLog -Level ERROR -Component Package -Message "Falha ao instalar PdfCraft. Código MSI: $($process.ExitCode)" }
        [pscustomobject]@{Package='PdfCraft';Manager='MSI';Action=$Action;ExitCode=$process.ExitCode;Outcome=$outcome;Detail="Codigo MSI: $($process.ExitCode)"}
    } finally {
        foreach ($file in @($msiPath,$sumPath)) { if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue } }
        Remove-Item -LiteralPath $tempDir -ErrorAction SilentlyContinue
    }
}

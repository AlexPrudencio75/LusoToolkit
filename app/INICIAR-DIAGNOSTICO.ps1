$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$log = Join-Path $PSScriptRoot 'ERRO-ARRANQUE.txt'
$success = $false
try {
    ('Data: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Set-Content -LiteralPath $log -Encoding UTF8
    ('PowerShell: ' + $PSVersionTable.PSVersion.ToString()) | Add-Content -LiteralPath $log -Encoding UTF8
    ('Pasta: ' + $PSScriptRoot) | Add-Content -LiteralPath $log -Encoding UTF8
    Write-Host 'A compilar Windows Utilities...' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'Compile.ps1')
    if (-not $?) { throw 'A compilacao devolveu um erro.' }
    $compiled = Join-Path $PSScriptRoot 'winutil.ps1'
    if (-not (Test-Path -LiteralPath $compiled)) { throw 'Nao foi gerado winutil.ps1' }
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($compiled, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $parseErrors | Out-String -Width 240 | Add-Content -LiteralPath $log -Encoding UTF8
        throw ('Foram encontrados ' + $parseErrors.Count + ' erros de sintaxe no script compilado.')
    }
    Write-Host 'A abrir a interface...' -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & $compiled
    $invocationSucceeded = $?
    if (-not $invocationSucceeded -or $global:LASTEXITCODE -ne 0) { throw ('A aplicacao terminou com erro. Codigo: ' + $global:LASTEXITCODE) }
    $success = $true
} catch {
    Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Red
    ('ERRO: ' + $_.Exception.Message) | Add-Content -LiteralPath $log -Encoding UTF8
    ($_ | Format-List * -Force | Out-String -Width 240) | Add-Content -LiteralPath $log -Encoding UTF8
    if ($_.ScriptStackTrace) { $_.ScriptStackTrace | Add-Content -LiteralPath $log -Encoding UTF8 }
} finally {
    if (-not $success) {
        Write-Host ('O erro ficou guardado em: ' + $log) -ForegroundColor Yellow
        exit 1
    }
}
exit 0

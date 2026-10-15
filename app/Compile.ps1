param (
    [switch]$Run
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$OFS = "`r`n"

# Variable to sync between runspaces
$sync = [Hashtable]::Synchronized(@{})
$sync.configs = @{}

$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw -Encoding UTF8).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Numero de versao invalido no ficheiro VERSION.' }
$script = (Get-Content -Path scripts\start.ps1 -Raw -Encoding UTF8) -replace '#{replaceme}', $version
$isLocalCompile = -not [string]::Equals($env:GITHUB_ACTIONS, "true", [StringComparison]::OrdinalIgnoreCase)
$script = $script -replace '#{islocalcompile}', $isLocalCompile.ToString().ToLowerInvariant()

$script += "`r`n"
$script += (Get-ChildItem -Path functions -Recurse -File -Filter '*.ps1' | Sort-Object FullName | ForEach-Object {
    (Get-Content -Path $_.FullName -Raw -Encoding UTF8) + "`r`n"
}) -join "`r`n"

$localization = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config\localization.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Get-ChildItem config -File -Filter '*.json' | Sort-Object Name | ForEach-Object {
    $obj = Get-Content -Path $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $configName = $_.BaseName
    foreach ($entry in @($obj.PSObject.Properties)) {
        $translation = $localization.$configName.$($entry.Name)
        if ($null -eq $translation) { continue }
        foreach ($field in $translation.PSObject.Properties) {
            if ($field.Name -notin @('Content','Description')) { throw 'A traducao apenas pode alterar Content e Description.' }
            $entry.Value | Add-Member -NotePropertyName $field.Name -NotePropertyValue $field.Value -Force
        }
    }

    if ($_.Name -eq "applications.json") {
        $fixed = [ordered]@{}
        foreach ($p in $obj.PSObject.Properties) {
            $fixed["WPFInstall$($p.Name)"] = $p.Value
        }
        $obj = [pscustomobject]$fixed
    }

    $json = $obj | ConvertTo-Json -Depth 10

    $sync.configs[$_.BaseName] = $obj
    $script += "`r`n`$sync.configs.$($_.BaseName) = @'`r`n$json`r`n'@ | ConvertFrom-Json`r`n"
}

$xaml = Get-Content -Path xaml\inputXML.xaml -Raw -Encoding UTF8
$script += "`r`n`$inputXML = @'`r`n$xaml`r`n'@`r`n"

$autounattendXml = Get-Content -Path tools\autounattend.xml -Raw -Encoding UTF8
$script += "`r`n`$WinUtilAutounattendXml = @'`r`n$autounattendXml`r`n'@`r`n"

$script += "`r`n" + (Get-Content -Path scripts\main.ps1 -Raw -Encoding UTF8)

# Prevent broken Portuguese characters from reaching the interface.
if ($script.Contains('OtimizaÃ') -or $script.Contains('ConfiguraÃ') -or $script.Contains('PadrÃ')) {
    throw 'Erro de codificacao: o texto foi lido incorretamente. Compilacao interrompida.'
}

[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "winutil.ps1"), $script, (New-Object System.Text.UTF8Encoding($true)))
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'winutil.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String -Width 200) }

if ($Run) {
    .\Winutil.ps1
}

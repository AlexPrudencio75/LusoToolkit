function Get-WinUtilCategoryLabel {
    param([string]$Category)
    $label = $sync.configs.localization.categories.$Category
    if ($label) { return [string]$label }
    return ($Category -replace '.*__', '')
}

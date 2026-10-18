function Set-WinUtilTaskbarIdentity {
    param([Parameter(Mandatory)][Windows.Window]$Window, [switch]$Clear)
    $Window.VerifyAccess()
    if (-not ('LusoToolkit.TaskbarIdentity' -as [type])) {
        $source=Join-Path $sync.projectRoot 'scripts\TaskbarIdentity.cs'
        Add-Type -TypeDefinition ([IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)) -Language CSharp -ErrorAction Stop
    }
    $helper=New-Object Windows.Interop.WindowInteropHelper $Window
    if ($helper.Handle -eq [IntPtr]::Zero) { throw 'A janela ainda não tem um identificador nativo.' }
    if ($Clear) { [LusoToolkit.TaskbarIdentity]::Clear($helper.Handle) }
    else { [LusoToolkit.TaskbarIdentity]::Apply($helper.Handle) }
}

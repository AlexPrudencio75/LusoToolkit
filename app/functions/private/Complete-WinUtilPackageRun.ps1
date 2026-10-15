function Complete-WinUtilPackageRun {
    <#
        .SYNOPSIS
            Reports what a package run actually did and fails the job on unexpected errors

        .DESCRIPTION
            Package managers report failure through an exit code, which is easy to walk past.
            Without this the job layer would show a green checkmark for a run in which nothing
            changed. Unexpected failures terminate the job; expected elevated-context skips
            raise a warning so the job cannot claim that every requested action completed.

        .PARAMETER Action
            Install or Uninstall, used in the summary text.

    #>
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [object[]]$Results = @()
    )

    if (@($Results).Count -eq 0) { throw 'Nenhuma aplicação foi processada. Verifique o catálogo e o gestor de pacotes selecionado.' }
    $succeeded = @($Results | Where-Object { $_.Outcome -eq "Succeeded" })
    $skipped = @($Results | Where-Object { $_.Outcome -eq "Skipped" })
    $failed = @($Results | Where-Object { $_.Outcome -eq "Failed" })

    $summary = "$($succeeded.Count) concluída(s), $($skipped.Count) não realizada(s), $($failed.Count) falhada(s)"
    Write-WinUtilLog -Component "Package" -Message "$Action summary: $summary"
    Write-Host "Resultado: $summary"

    foreach ($result in $skipped) {
        Write-Host "  Não realizada: $($result.Package) - $($result.Detail)"
    }
    foreach ($result in $failed) {
        Write-Host "  Falhou: $($result.Package) - $($result.Detail)" -ForegroundColor Red
    }

    if ($skipped.Count -gt 0) { Write-Warning "$($skipped.Count) operação(ões) não foram realizadas. Consulte os motivos no registo." }
    $adminContextSkipped = @($skipped | Where-Object { $_.ExitCode -eq -1978335107 })
    if ($adminContextSkipped.Count -gt 0) {
        Write-Warning 'Algumas aplicações estão instaladas apenas para o utilizador e não podem ser alteradas neste contexto de administrador.'
    }

    if ($failed.Count -gt 0) {
        $names = ($failed | ForEach-Object { $_.Package }) -join ', '
        $reasons = @($failed | ForEach-Object { $_.Detail } | Sort-Object -Unique)

        $message = if ($reasons.Count -eq 1) {
            "Falharam $($failed.Count) de $($Results.Count) operações: $names. $($reasons[0])"
        } else {
            "Falharam $($failed.Count) de $($Results.Count) operações: $names. Consulte os motivos no registo."
        }
        # Each failed package was already logged by its package-manager adapter. Carry that fact
        # with the summary exception so the job wrapper adds context without another error count.
        $exception = [System.InvalidOperationException]::new($message)
        $exception.Data["WinUtilErrorReported"] = $true
        throw $exception
    }
}

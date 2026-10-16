function Get-WinUtilRemoteAgent {
    # Pinned user-provided installer. Change the URL here when migrating hosting;
    # update size/hash together only when the approved binary also changes.
    [pscustomobject]@{
        Uri = 'https://raw.githubusercontent.com/AlexPrudencio75/LusoToolkit/main/installers/2b4baf5c6737/BAManagement-7.70.01.exe'
        AllowedHosts = @('raw.githubusercontent.com')
        FileName = 'AcessoRemoto-TakeControl-7.70.01.exe'
        Size = 40345168L
        Sha256 = '2B4BAF5C67373E604E3CB5361397B7433C90027697D70FE5B789CB3A3D963840'
        Publisher = 'N-ABLE TECHNOLOGIES LTD'
    }
}

function Install-WinUtilRemoteAgent {
    # This is a persistent installer, NEVER a temporary portable/job member.
    $result = [pscustomobject]@{Package='Acesso remoto';Manager='RemoteAgent';Action='Open installer';ExitCode=0;Outcome='Skipped';Detail='Instalação não iniciada.';Path=$null}
    if (-not (Test-WinUtilUIAlive) -or $sync.PortableStopping) { throw 'É necessária uma interface aberta para confirmar a instalação do acesso remoto.' }
    $answer = Show-WinUtilMessage -Title 'Instalar acesso remoto permanente' -Button YesNo -Icon Warning -Message 'Pretende abrir o instalador N-able Take Control neste computador? Instale apenas em computadores que esteja autorizado a gerir. O agente permite acesso remoto pela equipa associada ao instalador e permanece instalado após fechar o Windows Utilities. A instalação será concluída por si no assistente, com autorização de administrador.'
    if ("$answer" -ne 'Yes') { $result.Detail='Instalação cancelada antes da transferência.'; return $result }

    $agent = Get-WinUtilRemoteAgent
    $folder = Get-WinUtilDownloadsFolder
    $partial = Join-Path $folder ('LusoToolkit-RemoteAgent-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Step-WinUtilJob -Status 'A transferir o agente de acesso remoto...' -Percent 0 -State Normal
        Save-WinUtilFile -Uri $agent.Uri -DestinationPath $partial -AllowedHosts $agent.AllowedHosts -ProgressCallback {
            param($percent)
            Step-WinUtilJob -Status "A transferir o acesso remoto ($percent%)..." -Percent $percent
        }
        Step-WinUtilJob -Status 'A verificar o agente de acesso remoto...' -State Indeterminate
        if ((Get-Item -LiteralPath $partial -ErrorAction Stop).Length -ne $agent.Size) { throw 'Tamanho incorreto do instalador de acesso remoto. O ficheiro não foi aberto.' }
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256 -ErrorAction Stop).Hash -ne $agent.Sha256) { throw 'SHA-256 incorreto do instalador de acesso remoto. O ficheiro não foi aberto.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $partial -ErrorAction Stop
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo('SimpleName', $false) -ne $agent.Publisher) {
            throw 'A assinatura digital do agente de acesso remoto não é válida ou não pertence à N-able. O ficheiro não foi aberto.'
        }
        # File.Move does not overwrite. Retry only a destination-name collision.
        $baseName = [IO.Path]::GetFileNameWithoutExtension($agent.FileName)
        $destination = Join-Path $folder $agent.FileName
        $number = 0
        while ($true) {
            if (Test-Path -LiteralPath $destination) { $number++; $destination=Join-Path $folder ("$baseName ($number).exe"); continue }
            try { [IO.File]::Move($partial, $destination); break }
            catch [IO.IOException] { if (-not (Test-Path -LiteralPath $destination)) { throw } }
        }
        $result.Path = $destination
        $sync.LastRemoteAgentInstallerPath = $destination
        if (-not (Test-WinUtilUIAlive) -or $sync.PortableStopping) { throw 'A interface foi fechada. O instalador verificado ficou em Downloads e não foi aberto.' }
        $opened = Invoke-WPFUIThread -PassThru -Parameters @{InstallerPath=$destination} -ScriptBlock {
            param($InstallerPath)
            # PortableStopping is also set by the UI Closed event. It only guards
            # this handoff; the installer is not registered in any portable job.
            if (-not (Test-WinUtilUIAlive) -or $sync.PortableStopping) { return $false }
            # Visible wizard, no silent arguments, no -Wait, no portable containment.
            Start-Process -FilePath $InstallerPath -WorkingDirectory ([IO.Path]::GetDirectoryName($InstallerPath)) -Verb RunAs -WindowStyle Normal -ErrorAction Stop | Out-Null
            return $true
        }
        if (-not $opened) { throw 'Não foi possível abrir o instalador de acesso remoto.' }
        $result.Outcome='Succeeded'
        $result.Detail='Instalador aberto como administrador. Conclua a instalação no assistente; instalação do agente não confirmada.'
        Write-WinUtilLog -Component RemoteAgent -Message $result.Detail
        Step-WinUtilJob -Status 'Instalador de acesso remoto aberto. Conclua no assistente.' -Percent 100 -State Normal
        return $result
    } finally {
        # Only this invocation's incomplete/invalid download, never installed files.
        if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

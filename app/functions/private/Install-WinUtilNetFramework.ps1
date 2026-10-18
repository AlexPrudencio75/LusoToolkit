function Get-WinUtilNetFrameworkPlatform {
    $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build = 0
    if (-not [int]::TryParse([string]$os.CurrentBuildNumber, [ref]$build)) { throw 'Não foi possível identificar a versão do Windows.' }
    $kind = [string]$os.InstallationType
    if ($kind -notin @('Client','Server','Server Core')) { throw 'Este ambiente Windows não é suportado pela instalação automática do Framework.' }
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    [pscustomobject]@{Build=$build;IsServer=($kind -ne 'Client');Architecture=$arch.ToUpperInvariant()}
}

function Get-WinUtilNetFrameworkState {
    # Read both registry views: the GUI may have been started from 32-bit PowerShell.
    $release = 0; $legacyInstalled = $false
    $views = if ([Environment]::Is64BitOperatingSystem) { @('Registry64','Registry32') } else { @('Registry32') }
    foreach ($view in $views) {
        $base = $null; $four = $null; $legacy = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]$view)
            $four = $base.OpenSubKey('SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full',$false)
            $legacy = $base.OpenSubKey('SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5',$false)
            if ($four) { $release = [Math]::Max($release,[int]$four.GetValue('Release',0)) }
            if ($legacy -and [int]$legacy.GetValue('Install',0) -eq 1) { $legacyInstalled = $true }
        } finally {
            if ($four) { $four.Dispose() }; if ($legacy) { $legacy.Dispose() }; if ($base) { $base.Dispose() }
        }
    }
    [pscustomobject]@{FourRelease=$release;LegacyInstalled=$legacyInstalled}
}

function Get-WinUtilNetFrameworkPlan {
    param([Parameter(Mandatory)][ValidateSet('Legacy35','Latest4')][string]$Variant,
          [Parameter(Mandatory)]$Platform)
    if ($Platform.Architecture -notin @('X86','AMD64','ARM64')) { throw 'Arquitetura não suportada para a instalação do .NET Framework.' }
    if ($Platform.Build -lt 10240) { throw 'A instalação automática do Framework requer Windows 10/11 ou Windows Server 2016 e posteriores.' }
    if ($Variant -eq 'Legacy35') {
        if (-not $Platform.IsServer -and $Platform.Build -ge 28000) {
            if ($Platform.Architecture -eq 'X86') { throw 'Windows 11 26H1 não suporta sistemas x86 de 32 bits.' }
            return [pscustomobject]@{Variant=$Variant;Name='.NET Framework 3.5 (inclui 2.0 e 3.0)';Mode='Standalone';Source='Net35';MinimumRelease=0}
        }
        return [pscustomobject]@{Variant=$Variant;Name='.NET Framework 3.5 (inclui 2.0 e 3.0)';Mode='OptionalFeature';Source=$null;MinimumRelease=0}
    }
    if ($Platform.Build -lt 14393) { throw 'A instalação automática do Framework 4.x requer Windows 10 1607 ou Windows Server 2016, ou posteriores. Atualize este Windows antigo.' }
    $use481 = if ($Platform.IsServer) { $Platform.Build -ge 20348 } else { $Platform.Build -ge 19042 }
    if ($use481) { return [pscustomobject]@{Variant=$Variant;Name='.NET Framework 4.8.1';Mode='Standalone';Source='Net481';MinimumRelease=533320} }
    [pscustomobject]@{Variant=$Variant;Name='.NET Framework 4.8';Mode='Standalone';Source='Net48';MinimumRelease=528040}
}

function Get-WinUtilNetFrameworkSource {
    param([Parameter(Mandatory)][ValidateSet('Net35','Net481','Net48')][string]$Id)
    # Microsoft runtime installers, NOT developer packs. Pinned bytes fail closed
    # if the vendor replaces an installer; never redistribute these in our repo.
    $catalog = @{
        Net35 = @{Uri='https://download.microsoft.com/download/298af580-974e-4001-a07d-bb200d7c5792/DotNet35Setup.exe';FileName='DotNet35Setup-Win11-26H1.exe';Size=105310344L;Sha256='B969D1D0A662BDFD20F42AED9F0EDE21122723FBBCEE545F16DA7150FF01926D'}
        Net481 = @{Uri='https://download.microsoft.com/download/4/b/2/cd00d4ed-ebdd-49ee-8a33-eabc3d1030e3/NDP481-x86-x64-AllOS-ENU.exe';FileName='NDP481-x86-x64-AllOS-ENU.exe';Size=77688504L;Sha256='C0CA2E0C9CD18A24A0A77369A13FAE2C2C4E8BC83355DD24E5DDC00F9D791FE3'}
        Net48 = @{Uri='https://download.microsoft.com/download/f/3/a/f3a6af84-da23-40a5-8d1c-49cc10c8e76f/NDP48-x86-x64-AllOS-ENU.exe';FileName='NDP48-x86-x64-AllOS-ENU.exe';Size=121346568L;Sha256='0A3A390C47E639D0F7FC65B21195FEE6B7F65B066F80F70C60FAB191D14B7E40'}
    }
    [pscustomobject]$catalog[$Id]
}

function Test-WinUtilNetFrameworkAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Save-WinUtilNetFrameworkInstaller {
    param([Parameter(Mandatory)][ValidateSet('Net35','Net481','Net48')][string]$Id)
    $source = Get-WinUtilNetFrameworkSource -Id $Id
    $folder = Get-WinUtilDownloadsFolder
    $partial = Join-Path $folder ('LusoToolkit-Framework-' + [guid]::NewGuid().ToString('N') + '.exe')
    $tls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $tls -bor [Net.SecurityProtocolType]::Tls12
        Step-WinUtilJob -Status "A transferir o .NET Framework ($Id)..." -State Indeterminate
        Save-WinUtilFile -Uri $source.Uri -DestinationPath $partial -AllowedHosts @('download.microsoft.com') -ProgressCallback {
            param($percent)
            # Keep the surrounding batch progress, which counts packages, consistent.
            Step-WinUtilJob -Status "A transferir o .NET Framework ($percent%)..." -State Indeterminate
        }
        if ((Get-Item -LiteralPath $partial -ErrorAction Stop).Length -ne $source.Size) { throw 'O tamanho do instalador Framework não corresponde ao esperado.' }
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256 -ErrorAction Stop).Hash -ne $source.Sha256) { throw 'O SHA-256 do instalador Framework não corresponde ao esperado.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $partial -ErrorAction Stop
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo('SimpleName',$false) -ne 'Microsoft Corporation') {
            throw 'O instalador Framework não possui uma assinatura Microsoft válida. Não foi executado.'
        }
        $stem = [IO.Path]::GetFileNameWithoutExtension($source.FileName)
        for ($index=0; $index -lt 10000; $index++) {
            $fileName = if ($index -eq 0) { $source.FileName } else { "$stem ($index).exe" }
            $destination = Join-Path $folder $fileName
            if (Test-Path -LiteralPath $destination) { continue }
            try { [IO.File]::Move($partial,$destination); return $destination }
            catch [IO.IOException] { if (-not (Test-Path -LiteralPath $destination)) { throw } }
        }
        throw 'Não foi possível reservar um nome livre para o instalador Framework.'
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $tls
        if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Install-WinUtilNetFramework {
    param([Parameter(Mandatory)][ValidateSet('Legacy35','Latest4')][string]$Variant)
    $platform = Get-WinUtilNetFrameworkPlatform
    $plan = Get-WinUtilNetFrameworkPlan -Variant $Variant -Platform $platform
    $state = Get-WinUtilNetFrameworkState
    $result = [pscustomobject]@{Package=$plan.Name;Manager='NetFramework';Action='Install';ExitCode=0;Outcome='Succeeded';Detail='';RestartNeeded=$false;AlreadyInstalled=$false;Path=$null}
    if ($Variant -eq 'Latest4' -and $state.FourRelease -ge $plan.MinimumRelease) {
        $result.AlreadyInstalled=$true;$result.Detail='Esta versão ou uma versão mais recente já está instalada; não foi alterada.'
        Write-WinUtilLog -Component NetFramework -Message "$($plan.Name): $($result.Detail)"
        return $result
    }
    if ($Variant -eq 'Legacy35' -and $plan.Mode -eq 'Standalone' -and $state.LegacyInstalled) {
        $result.AlreadyInstalled=$true;$result.Detail='Framework 3.5 já instalado; inclui os componentes 2.0 e 3.0.'
        Write-WinUtilLog -Component NetFramework -Message $result.Detail
        return $result
    }
    if (-not (Test-WinUtilNetFrameworkAdmin)) { throw 'Execute o Windows Utilities como administrador para instalar ou ativar o .NET Framework.' }
    if ($plan.Mode -eq 'OptionalFeature') {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
        if ("$($feature.State)" -eq 'Enabled') {
            $result.AlreadyInstalled=$true;$result.Detail='Framework 3.5 já ativo; inclui os componentes 2.0 e 3.0.'
        } elseif ("$($feature.State)" -eq 'EnablePending') {
            $result.RestartNeeded=$true;$result.Detail='A ativação do Framework 3.5 já está pendente de reinício.'
        } elseif ("$($feature.State)" -eq 'DisablePending') {
            throw 'O Framework 3.5 tem uma desativação pendente. Reinicie o Windows antes de voltar a instalar.'
        } else {
            Step-WinUtilJob -Status 'A ativar o Framework 3.5 (inclui 3.0) pelo Windows Update...' -State Indeterminate
            try { $enabled = Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction Stop }
            catch { throw "Não foi possível ativar o Framework 3.5. Verifique o acesso ao Windows Update e as políticas da organização, ou use uma origem de instalação da mesma versão do Windows. Não foram alteradas políticas. Detalhe: $($_.Exception.Message)" }
            $after = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
            if ("$($after.State)" -notin @('Enabled','EnablePending')) { throw 'O Windows não confirmou a ativação do Framework 3.5.' }
            $result.RestartNeeded = [bool]$enabled.RestartNeeded -or "$($after.State)" -eq 'EnablePending'
            $result.Detail='Framework 3.5 ativado, incluindo os componentes 2.0 e 3.0.'
        }
    } else {
        if ($platform.Architecture -eq 'ARM64' -and ($plan.Source -eq 'Net48' -or ($plan.Source -eq 'Net481' -and $platform.Build -lt 22000))) {
            throw 'Neste Windows ARM64, utilize o Framework incluído no sistema e as atualizações do Windows; este instalador não é aplicado automaticamente.'
        }
        $path = Save-WinUtilNetFrameworkInstaller -Id $plan.Source
        $result.Path = $path
        Step-WinUtilJob -Status "A instalar $($plan.Name), sem reinício automático..." -State Indeterminate
        # Downloads is user-writable. Recheck under a read-only execution lock so
        # the verified executable cannot be replaced between verification/start.
        $executionLock = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            $source = Get-WinUtilNetFrameworkSource -Id $plan.Source
            if ($executionLock.Length -ne $source.Size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ne $source.Sha256) { throw 'O instalador Framework foi alterado antes da execução. Não foi iniciado.' }
            $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
            if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.GetNameInfo('SimpleName',$false) -ne 'Microsoft Corporation') { throw 'A assinatura do instalador Framework não foi confirmada antes da execução.' }
            $process = Start-Process -FilePath $path -WorkingDirectory ([IO.Path]::GetDirectoryName($path)) -ArgumentList @('/quiet','/norestart') -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
        } finally { $executionLock.Dispose() }
        if ($null -eq $process -or $null -eq $process.ExitCode) { throw 'O instalador Framework não devolveu um resultado de instalação.' }
        $result.ExitCode = [int]$process.ExitCode
        if ($result.ExitCode -notin @(0,3010,1641)) { throw "O instalador de $($plan.Name) falhou (código $($result.ExitCode)). O ficheiro ficou em Downloads. Não foi iniciada uma instalação de outra versão como alternativa." }
        $result.RestartNeeded = $result.ExitCode -in @(3010,1641)
        if (-not $result.RestartNeeded) {
            $after = Get-WinUtilNetFrameworkState
            if (($Variant -eq 'Legacy35' -and -not $after.LegacyInstalled) -or ($Variant -eq 'Latest4' -and $after.FourRelease -lt $plan.MinimumRelease)) {
                throw 'O instalador terminou, mas a presença do Framework ainda não foi confirmada. Consulte o registo do instalador; não foi comunicado sucesso.'
            }
        }
        $result.Detail = "$($plan.Name) instalado."
    }
    if ($result.RestartNeeded) {
        if ($result.ExitCode -eq 1641) {
            $result.Detail += ' O instalador reportou reinício iniciado (1641), apesar do pedido /norestart.'
            Write-Warning "$($plan.Name): o instalador reportou reinício iniciado (1641). Não foi enviado nenhum comando de reinício pela aplicação."
        } else {
            $result.Detail += ' É necessário reiniciar manualmente para concluir.'
            Write-Warning "$($plan.Name): é necessário reiniciar o Windows manualmente. A aplicação não reinicia o computador."
        }
    }
    Write-WinUtilLog -Component NetFramework -Message "$($plan.Name): $($result.Detail)"
    return $result
}

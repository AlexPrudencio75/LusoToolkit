function Get-WinUtilPortableCatalog {
    # Exact files supplied by the project owner, who authorized public distribution.
    # No guessing download URLs, automatic version substitution or executable cache.
    @(
        [pscustomobject]@{ Id='zonesoft_converter'; Name='ZoneSoft Converter 2.3.8'; File='ZoneSoft Converter.exe'; Size=696832; Sha256='4BE3679C32593012704AF4D78B13B25E628016EC7F9255791D6A3E086463F7E8'; Url='https://raw.githubusercontent.com/AlexPrudencio75/LusoToolkit/main/portables/4be3679c3259/zonesoft-converter-2.3.8.exe' },
        [pscustomobject]@{ Id='auditor_rede'; Name='Auditor de Rede 2.1'; File='AuditorDeRede.exe'; Size=13639440; Sha256='0F6E6F87A002443D04403B6186279BD1DE4C0AB5EF0212508FFFCEB2ACA1944C'; Url='https://raw.githubusercontent.com/AlexPrudencio75/LusoToolkit/main/portables/0f6e6f87a002/auditor-rede-2.1.exe' },
        [pscustomobject]@{ Id='ligabd'; Name='LigaBD'; File='LigaBD.exe'; Size=37376; Sha256='8DF02146F867ECE6CACB8831522D860FE67A8EDA88274ACE042BC71A120DE688'; Url='https://raw.githubusercontent.com/AlexPrudencio75/LusoToolkit/main/portables/8df02146f867/ligabd-1.0.exe' },
        [pscustomobject]@{ Id='netscan'; Name='Network Scanner 5.1.3'; File='netscan.exe'; Size=740352; Sha256='5F8A02624E1731B97697FF7D3D98949E991D1AA3EE83E096037C0E56DEFAE657'; Url='https://raw.githubusercontent.com/AlexPrudencio75/LusoToolkit/main/portables/5f8a02624e17/netscan-5.1.3.exe' }
    )
}

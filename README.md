# LusoToolkit

Utilitarios Windows com interface em portugues de Portugal, adaptados por Alex Prudencio a partir do WinUtil de Chris Titus Tech. A aplicacao mantem o nome **Windows Utilities PT-PT** na interface.

## Abrir com uma linha

No PowerShell do Windows, cole:

```powershell
irm https://raw.githubusercontent.com/AlexPrudencio75/LusoToolkit/main/Start.ps1 | iex
```

O comando descarrega e executa o lancador deste repositorio. Leia primeiro o [codigo do lancador](Start.ps1) e execute apenas se confiar neste projeto.

O lancador consulta `release.json`, descarrega o pacote completo da versao publicada, verifica o tamanho e o SHA-256, extrai numa pasta nova em `%LOCALAPPDATA%\LusoToolkit` e abre a interface. O Windows pede autorizacao de administrador quando necessario. Nenhuma opcao da interface e aplicada automaticamente so por abrir a aplicacao.

Requer Windows e Windows PowerShell 5.1. Pode invocar o comando a partir do PowerShell 7: a interface abre no Windows PowerShell. Nao altera a politica de execucao permanente, nao desativa o UAC e nao contorna politicas impostas pelo administrador. Uma politica de organizacao pode impedir a execucao.

O SHA-256 verifica a integridade do ZIP face ao manifesto no mesmo repositorio; nao e uma assinatura digital nem protege contra o comprometimento da conta do repositorio.

## Transferencia manual

Descarregue [LusoToolkit 0.3.14](packages/LusoToolkit-0.3.14.zip), extraia a pasta completa e execute `INICIAR.cmd`.

```text
SHA-256: 38F2181EBA71AFCE09EECE50B926FD840A321000D21A6B68FE1E79E8070A8E12
```

Nao apague os restantes ficheiros da pasta: a aplicacao necessita dos recursos, configuracoes e fontes para compilar no arranque. Cada execucao do lancador utiliza uma pasta nova; nao substitui nem elimina execucoes anteriores.

## Funcionalidades

- Instalacao e atualizacao de aplicacoes, ajustes e ferramentas de manutencao Windows.
- XD e ZoneSoft: transferencia a partir das origens oficiais e abertura do assistente para continuar manualmente.
- ZoneSoft Posto, Sem SQL e Completo: procura a versao numerica mais recente disponivel no catalogo oficial em cada transferencia, extrai e abre `Setup.exe` como administrador.
- ZSTools: apenas descarregar ou copiar os cinco ficheiros para uma instalacao detetada em `\Zone Soft\ZSRest`, com copia de seguranca antes de substituir, e abrir o ZSTools.

Os instaladores XD/ZoneSoft nao estao incluidos neste repositorio. Sao obtidos diretamente dos respetivos fabricantes quando selecionados. A disponibilidade dos portais e as condicoes de utilizacao pertencem aos fabricantes. O ZSTools oficial pode nao ter assinatura digital; a aplicacao informa esse estado no registo. Os instaladores ZoneSoft Setup continuam sujeitos a verificacao estrita da assinatura.

As ferramentas de sistema podem alterar o Windows. Reveja as opcoes antes de as aplicar e mantenha copias de seguranca. Sem afiliacao oficial com XD ou ZoneSoft.

## Codigo e novas publicacoes

O codigo da aplicacao esta em [`app/`](app/); o ZIP contem a mesma versao completa, incluindo o script compilado. `Compile.ps1` recompila a aplicacao a partir das fontes. `VERSION` identifica a versao da aplicacao.

Para publicar uma nova versao, teste a aplicacao, adicione um novo `packages/LusoToolkit-<versao>.zip` e atualize `release.json` com a versao, tamanho em bytes e SHA-256 correspondentes, no mesmo commit. O ZIP deve conter a pasta `WindowsUtilities_PTPT_v<versao>/`. Nao substitua pacotes antigos. O comando acima continua igual e usa a versao indicada no manifesto publicado na branch `main`.

Licenca [MIT](LICENSE). Mantidos os creditos e direitos de autor originais de CT Tech Group LLC. Projeto de origem: [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil).

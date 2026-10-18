# LusoToolkit

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

Descarregue [LusoToolkit 0.3.19](packages/LusoToolkit-0.3.19.zip), extraia a pasta completa e execute `INICIAR.cmd`.

```text
SHA-256: 83BB653ADBC65CEC0E6D6C8437DCDF0DB3D8B4A642CF0049744A7755DBF61669
```

Nao apague os restantes ficheiros da pasta: a aplicacao necessita dos recursos, configuracoes e fontes para compilar no arranque. Cada execucao do lancador utiliza uma pasta nova; nao substitui nem elimina execucoes anteriores.

## Funcionalidades

- Icones dos 33 cartoes incluidos no pacote: aparecem imediatamente e sem Internet. A janela tambem usa o logotipo local da aplicacao.
- .NET Framework desde o 3.0: dois cartoes em **Ferramentas Microsoft**, **.NET Framework 3.0/3.5** e **.NET Framework 4.x**. O 3.5 inclui 2.0 e 3.0; usa Windows Update/componentes nas versoes anteriores ao Windows 11 26H1 e o novo instalador autonomo Microsoft no Windows 11 26H1 (build 28000) e posteriores. O cartao 4.x garante 4.8.1 onde compativel ou 4.8 em Windows anteriores compativeis, sem reinstalar/despromover versoes presentes. Instaladores oficiais verificados por tamanho, SHA-256 e assinatura, guardados em Downloads. Usa /quiet /norestart e verifica o resultado; nao reinicia automaticamente. O metodo automatico 4.x requer Windows 10 1607/Server 2016 ou posterior. Tambem disponivel em Configuracao; distinto dos .NET Desktop Runtime. [Regras Microsoft](https://learn.microsoft.com/en-us/dotnet/framework/install/dotnet-35-windows-11), [compatibilidade 4.x](https://learn.microsoft.com/en-us/dotnet/framework/get-started/system-requirements).
- Instalacao e atualizacao de aplicacoes, ajustes e ferramentas de manutencao Windows.
- XD e ZoneSoft: transferencia a partir das origens oficiais e abertura do assistente para continuar manualmente.
- ZoneSoft Posto, Sem SQL e Completo: procura a versao numerica mais recente disponivel no catalogo oficial em cada transferencia, extrai e abre `Setup.exe` como administrador.
- ZSTools: apenas descarregar ou copiar os cinco ficheiros para uma instalacao detetada em `\Zone Soft\ZSRest`, com copia de seguranca antes de substituir, e abrir o ZSTools.
- Acesso remoto: instalador N-able Take Control fornecido pelo mantenedor, alojado publicamente com a sua autorizacao. Marque o cartao na seccao **Acesso remoto** e clique em **Instalar / transferir selecao**. Pede confirmacao, transfere para Downloads, verifica tamanho, SHA-256 e assinatura N-able e abre o assistente como administrador. Conclua a instalacao manualmente, apenas em computadores autorizados. O agente permite acesso remoto pela equipa associada ao instalador e permanece instalado ao fechar a aplicacao; nao e um portatil temporario. Abrir o assistente nao confirma a instalacao. A validade de inscricao/licenca e o funcionamento do servico dependem do fornecedor, nao do alojamento do ficheiro.
- Na seccao **Portateis**, selecione as ferramentas e clique em **Abrir portateis** ou **Instalar / transferir selecao**. ZoneSoft Converter 2.3.8, Auditor de Rede 2.1, LigaBD e Network Scanner 5.1.3 mantem o modo temporario anterior. Macrorit tem a excecao de seguranca descrita abaixo.

### Macrorit Partition Expert Portable

Edicao **Free 8.9.2**, destinada a uso domestico segundo o [fabricante](https://macrorit.com/partition-magic-manager/free-edition.html). Para uso profissional/assistencia a clientes obtenha uma licenca adequada; esta integracao nao inclui licenca comercial nem versoes pagas. Windows x86/x64 cliente; ARM64 e Windows Server nao sao disponibilizados por este adaptador.

O ZIP e obtido diretamente de `https://disk-tool.com/download/mde/mde-free-portable.zip`, indicado na [pagina oficial de downloads](https://macrorit.com/download.html). Nenhum executavel Macrorit e redistribuido no GitHub. Verifica tamanho e SHA-256 fixos do ZIP, extrai todos os recursos numa pasta nova e confirma SHA-256 e assinatura digital do executavel/API da arquitetura escolhida. Se o fabricante alterar o ZIP, recusa abrir ate atualizacao revista do LusoToolkit; nao substitui silenciosamente pela versao mais recente.

Depois de uma confirmacao especifica, abre apenas a interface grafica como administrador, sem argumentos de operacoes de disco. **Faca copias de seguranca antes de alterar particoes.** Abrir o programa nao executa alteracoes automaticamente.

**Excecao de seguranca:** nao pertence ao grupo de processos dos portateis temporarios, nao e terminado ao fechar o Windows Utilities/PowerShell e a sua pasta nunca e apagada automaticamente. Fica em `%LOCALAPPDATA%\LusoToolkit\PortableTools\Macrorit-8.9.2-<GUID>`. Remova-a manualmente apenas depois de concluir todas as operacoes e eventuais reinicios. Nao se garante ausencia de registos, preferencias ou outros vestigios criados pelo Windows/fabricante. A integracao foi testada com aberturas simuladas, sem executar Macrorit nem alterar discos/particoes.

### Quatro portateis temporarios: usar sem manter a copia no computador

Os quatro executaveis fornecidos pelo mantenedor ficam separados do pacote principal e so sao descarregados quando selecionados, para uma sessao exclusiva em `%TEMP%\LusoToolkit-Portables\<GUID>`. O tamanho e SHA-256 sao verificados antes da abertura. Nao existe instalacao nem cache permanente desses quatro executaveis no LusoToolkit. Estas regras nao se aplicam ao Macrorit.

Ao fechar a ferramenta, o anfitriao remove a copia e os restantes ficheiros dessa pasta. Ao fechar o Windows Utilities, ou se o respetivo PowerShell terminar, o anfitriao fecha apenas o grupo de processos criado para a ferramenta e limpa a sessao. Nao termina outras instancias do mesmo programa. Fechar a interface com portateis abertos pede confirmacao; guarde primeiro o seu trabalho. Se o anfitriao tambem for terminado, ou a limpeza ficar bloqueada, o arranque seguinte tenta limpar sessoes antigas identificadas, sem tocar em instancias ainda vivas ou seguir junctions.

TEMP/TMP e APPDATA/LOCALAPPDATA sao redirecionados apenas no ambiente dos processos portateis. Isto **nao e uma sandbox e nao garante zero vestigios**: a propria ferramenta ou o Windows pode gravar preferencias, registos, dados ou alteracoes fora dessa pasta. Nao se revertem operacoes sobre redes ou bases de dados. Guarde documentos fora da pasta temporaria. Os originais fornecidos no Ambiente de Trabalho nao sao alterados. Os portateis usam as permissoes da aplicacao principal; so os execute se confiar neles.

Os quatro ficheiros fornecidos nao tem assinatura digital. A verificacao SHA-256 confirma os bytes fornecidos, nao a ausencia de malware. Dependencias em falta nao sao instaladas automaticamente. A gestao de processos e limpeza foi testada com executaveis de teste; estas quatro ferramentas nao foram executadas durante a integracao nem foram realizados acessos a redes ou bases de dados.

Os instaladores XD/ZoneSoft nao estao incluidos neste repositorio. Sao obtidos diretamente dos respetivos fabricantes quando selecionados. A disponibilidade dos portais e as condicoes de utilizacao pertencem aos fabricantes. O ZSTools oficial pode nao ter assinatura digital; a aplicacao informa esse estado no registo. Os instaladores ZoneSoft Setup continuam sujeitos a verificacao estrita da assinatura.

As ferramentas de sistema podem alterar o Windows. Reveja as opcoes antes de as aplicar e mantenha copias de seguranca. Sem afiliacao oficial com XD ou ZoneSoft.

## Codigo e novas publicacoes

O codigo da aplicacao esta em [`app/`](app/); o ZIP contem a mesma versao completa, incluindo o script compilado. `Compile.ps1` recompila a aplicacao a partir das fontes. `VERSION` identifica a versao da aplicacao.

Para publicar uma nova versao, teste a aplicacao, adicione um novo `packages/LusoToolkit-<versao>.zip` e atualize `release.json` com a versao, tamanho em bytes e SHA-256 correspondentes, no mesmo commit. O ZIP deve conter a pasta `WindowsUtilities_PTPT_v<versao>/`. Nao substitua pacotes antigos. O comando acima continua igual e usa a versao indicada no manifesto publicado na branch `main`.


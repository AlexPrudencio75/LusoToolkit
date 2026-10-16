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

Descarregue [LusoToolkit 0.3.16](packages/LusoToolkit-0.3.16.zip), extraia a pasta completa e execute `INICIAR.cmd`.

```text
SHA-256: 6F4D8A396FC1EF9C53F536F97CD0D59A2CBE32E0C59BF5931F38ADDB3829D9D8
```

Nao apague os restantes ficheiros da pasta: a aplicacao necessita dos recursos, configuracoes e fontes para compilar no arranque. Cada execucao do lancador utiliza uma pasta nova; nao substitui nem elimina execucoes anteriores.

## Funcionalidades

- Instalacao e atualizacao de aplicacoes, ajustes e ferramentas de manutencao Windows.
- XD e ZoneSoft: transferencia a partir das origens oficiais e abertura do assistente para continuar manualmente.
- ZoneSoft Posto, Sem SQL e Completo: procura a versao numerica mais recente disponivel no catalogo oficial em cada transferencia, extrai e abre `Setup.exe` como administrador.
- ZSTools: apenas descarregar ou copiar os cinco ficheiros para uma instalacao detetada em `\Zone Soft\ZSRest`, com copia de seguranca antes de substituir, e abrir o ZSTools.
- Acesso remoto: instalador N-able Take Control fornecido pelo mantenedor, alojado publicamente com a sua autorizacao. Marque o cartao na seccao **Acesso remoto** e clique em **Instalar / transferir selecao**. Pede confirmacao, transfere para Downloads, verifica tamanho, SHA-256 e assinatura N-able e abre o assistente como administrador. Conclua a instalacao manualmente, apenas em computadores autorizados. O agente permite acesso remoto pela equipa associada ao instalador e permanece instalado ao fechar a aplicacao; nao e um portatil temporario. Abrir o assistente nao confirma a instalacao. A validade de inscricao/licenca e o funcionamento do servico dependem do fornecedor, nao do alojamento do ficheiro.
- Portateis temporarios: ZoneSoft Converter 2.3.8, Auditor de Rede 2.1, LigaBD e Network Scanner 5.1.3, exatamente nas versoes fornecidas pelo mantenedor. Selecione os cartoes e clique em **Abrir portateis temporarios**.

### Portateis: usar sem manter a copia no computador

Os executaveis ficam separados do pacote principal e so sao descarregados quando selecionados, para uma sessao exclusiva em `%TEMP%\LusoToolkit-Portables\<GUID>`. O tamanho e SHA-256 sao verificados antes da abertura. Nao existe instalacao nem cache permanente desses executaveis no LusoToolkit.

Ao fechar a ferramenta, o anfitriao remove a copia e os restantes ficheiros dessa pasta. Ao fechar o Windows Utilities, ou se o respetivo PowerShell terminar, o anfitriao fecha apenas o grupo de processos criado para a ferramenta e limpa a sessao. Nao termina outras instancias do mesmo programa. Fechar a interface com portateis abertos pede confirmacao; guarde primeiro o seu trabalho. Se o anfitriao tambem for terminado, ou a limpeza ficar bloqueada, o arranque seguinte tenta limpar sessoes antigas identificadas, sem tocar em instancias ainda vivas ou seguir junctions.

TEMP/TMP e APPDATA/LOCALAPPDATA sao redirecionados apenas no ambiente dos processos portateis. Isto **nao e uma sandbox e nao garante zero vestigios**: a propria ferramenta ou o Windows pode gravar preferencias, registos, dados ou alteracoes fora dessa pasta. Nao se revertem operacoes sobre redes ou bases de dados. Guarde documentos fora da pasta temporaria. Os originais fornecidos no Ambiente de Trabalho nao sao alterados. Os portateis usam as permissoes da aplicacao principal; so os execute se confiar neles.

Os quatro ficheiros fornecidos nao tem assinatura digital. A verificacao SHA-256 confirma os bytes fornecidos, nao a ausencia de malware. Dependencias em falta nao sao instaladas automaticamente. A gestao de processos e limpeza foi testada com executaveis de teste; estas quatro ferramentas nao foram executadas durante a integracao nem foram realizados acessos a redes ou bases de dados.

Os instaladores XD/ZoneSoft nao estao incluidos neste repositorio. Sao obtidos diretamente dos respetivos fabricantes quando selecionados. A disponibilidade dos portais e as condicoes de utilizacao pertencem aos fabricantes. O ZSTools oficial pode nao ter assinatura digital; a aplicacao informa esse estado no registo. Os instaladores ZoneSoft Setup continuam sujeitos a verificacao estrita da assinatura.

As ferramentas de sistema podem alterar o Windows. Reveja as opcoes antes de as aplicar e mantenha copias de seguranca. Sem afiliacao oficial com XD ou ZoneSoft.

## Codigo e novas publicacoes

O codigo da aplicacao esta em [`app/`](app/); o ZIP contem a mesma versao completa, incluindo o script compilado. `Compile.ps1` recompila a aplicacao a partir das fontes. `VERSION` identifica a versao da aplicacao.

Para publicar uma nova versao, teste a aplicacao, adicione um novo `packages/LusoToolkit-<versao>.zip` e atualize `release.json` com a versao, tamanho em bytes e SHA-256 correspondentes, no mesmo commit. O ZIP deve conter a pasta `WindowsUtilities_PTPT_v<versao>/`. Nao substitua pacotes antigos. O comando acima continua igual e usa a versao indicada no manifesto publicado na branch `main`.


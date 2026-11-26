# Homologação Windows da MonitorIA VIP Mosaico

O workflow **MonitorIA VIP Mosaico Windows unsigned internal preview** compila a prévia de captura e prepara um ZIP **não assinado**, reservado à homologação interna pelo proprietário. O pacote contém o executável de prévia, o simulador com editor offline e as instruções. Não inclui o instalador oficial.

O Downloads usa somente `MONITORIA_PRIVATE_SOURCE_TOKEN` para ler o commit privado fixado. O `GITHUB_TOKEN` da execução escreve o Draft no Downloads. O eSigner, a chave de manifestos e `MONITORIA_DOWNLOADS_PUBLISH_TOKEN` são usados no MonitorIA, na etapa posterior de assinatura oficial e distribuição.

## Disparo

A conta `BigCorps` pode executar a correção na branch revisada abaixo, antes do merge. Após a integração, use `--ref main`.

```powershell
$repo = 'BigCorps/MonitorIA-Downloads'
$workflow = 'build-monitoria-vip-mosaic-beta.yml'
$ref = 'codex/vip-mosaic-unsigned-homologation'
gh workflow run $workflow --repo $repo --ref $ref -f preflight_only=false
gh run list --repo $repo --workflow $workflow --branch $ref --limit 1
```

A execução manual verifica os formatos HTTP e a disponibilidade da tag Beta.2 no runner Linux antes de iniciar a compilação no Windows. A opção `preflight_only=true` encerra o workflow depois dessas verificações. A entrega cria um Draft exclusivo para a Beta.2, vinculado ao commit público da execução. O Draft Beta.1 `458853594` permanece como referência.

## Download e teste

Uma execução concluída deixa o Draft com a tag `vip-mosaic-windows-unsigned-v1.0.0-beta.2-e447eaeddc64`. Em Releases, autentique-se com a conta do proprietário para baixar o ZIP, `RELEASE-MANIFEST.json` e `SHA256SUMS.txt`. A etapa confere o Draft vazio e o bloqueio anônimo antes do envio. Em seguida, verifica o hash e o bloqueio do acesso anônimo de cada arquivo. O Draft permanece restrito a colaboradores com escrita. Não publique o Draft nem redistribua a prévia.

```powershell
$archive = 'MonitorIA-VIP-Mosaico-1.0.0-beta.2-Homologacao-NAO-ASSINADO.zip'
$manifest = Get-Content -Raw RELEASE-MANIFEST.json | ConvertFrom-Json
if ($manifest.version -cne '1.0.0-beta.2' -or
    $manifest.sourceCommit -cne 'e447eaeddc642192fedaed5900fe5f2a944c1e0c' -or
    $manifest.authenticode.status -cne 'NotSigned' -or $manifest.manifestSigned -ne $false -or
    (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.sha256) {
    throw 'O pacote baixado não corresponde à prévia interna.'
}
Expand-Archive $archive -DestinationPath MonitorIA-VIP-Homologacao
Get-AuthenticodeSignature ./MonitorIA-VIP-Homologacao/MonitorIA-VIP-CapturePreview.exe
```

O status esperado é `NotSigned`. O SHA-256 permite conferir a integridade do arquivo baixado da sessão autenticada. Se a política do Windows bloquear o executável, aguarde a edição assinada. Siga o `LEIA-ME.txt` para abrir o simulador, autorizar a janela e testar o editor sem instalar SDK ou compilador.

## Se a compilação falhar

Procure as linhas `VIP native:` no job. O workflow primeiro compila e vincula uma verificação de compatibilidade C++20 com as mesmas conversões COM e WinRT e as mesmas bibliotecas da prévia. As linhas distinguem a verificação da compilação e do link do aplicativo. Também exibem as versões do SDK e do MSVC, dependências conhecidas ausentes e códigos do compilador e da STL, como `STL1011`. A verificação não executa a captura no runner. A linha `first_error` mostra o primeiro erro reconhecido, a severidade e a categoria. Para origens conhecidas, exibe a categoria do arquivo e a linha. Em ambiguidades, só identifica símbolos públicos do SDK de uma lista permitida. Os caminhos, mensagens brutas do compilador e trechos de fonte ficam no log temporário do runner. O script remove esse log ao final.

## Se a distribuição falhar

Procure no log a linha `VIP distribution: failed phase=`. O workflow verifica o token do job e a disponibilidade da tag antes de compilar. Na distribuição, os diagnósticos distinguem a validação do manifesto Windows, os hashes, a criação e verificação do Draft, o envio, os digests e o bloqueio de acesso anônimo. Falhas HTTP mostram o status quando disponível. Cabeçalhos, credenciais e corpos de resposta ficam fora do log.

O preflight interrompe a execução antes de compilar se já existir um Draft ou uma tag para a Beta.2 nesse SHA. Consulte o Draft autenticado no Downloads e confira os três arquivos esperados. O workflow preserva resultados anteriores. Em caso de falha no envio, a limpeza fica limitada aos arquivos criados pela própria execução no Draft confirmado.

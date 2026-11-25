# Homologação Windows da MonitorIA VIP Mosaico

O workflow **MonitorIA VIP Mosaico Windows unsigned internal preview** compila a prévia de captura e prepara um ZIP **não assinado**, reservado à homologação interna pelo proprietário. O pacote contém o executável de prévia, o simulador com editor offline e as instruções. Não inclui o instalador oficial.

O Downloads usa somente `MONITORIA_PRIVATE_SOURCE_TOKEN` para ler o commit privado fixado. O `GITHUB_TOKEN` da execução escreve o Draft no Downloads. O eSigner, a chave de manifestos e `MONITORIA_DOWNLOADS_PUBLISH_TOKEN` são usados no MonitorIA, na etapa posterior de assinatura oficial e distribuição.

## Disparo

A conta `BigCorps` pode executar a correção na branch revisada abaixo, antes do merge. Após a integração, use `--ref main`.

```powershell
$repo = 'BigCorps/MonitorIA-Downloads'
$workflow = 'build-monitoria-vip-mosaic-beta.yml'
$ref = 'codex/vip-mosaic-unsigned-homologation'
gh workflow run $workflow --repo $repo --ref $ref
gh run list --repo $repo --workflow $workflow --branch $ref --limit 1
```

## Download e teste

Uma execução concluída deixa o Draft com a tag `vip-mosaic-windows-unsigned-v1.0.0-beta.1-9866b862c259`. Em Releases, autentique-se com a conta do proprietário para baixar o ZIP, `RELEASE-MANIFEST.json` e `SHA256SUMS.txt`. A etapa confere o Draft vazio e o bloqueio anônimo antes do envio. Em seguida, verifica o hash e o bloqueio do acesso anônimo de cada arquivo. O Draft permanece restrito a colaboradores com escrita. Não publique o Draft nem redistribua a prévia.

```powershell
$archive = 'MonitorIA-VIP-Mosaico-1.0.0-beta.1-Homologacao-NAO-ASSINADO.zip'
$manifest = Get-Content -Raw RELEASE-MANIFEST.json | ConvertFrom-Json
if ($manifest.sourceCommit -cne '9866b862c25955fe70ba5d38dae316d935e0ceed' -or
    $manifest.authenticode.status -cne 'NotSigned' -or $manifest.manifestSigned -ne $false -or
    (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.sha256) {
    throw 'O pacote baixado não corresponde à prévia interna.'
}
Expand-Archive $archive -DestinationPath MonitorIA-VIP-Homologacao
Get-AuthenticodeSignature ./MonitorIA-VIP-Homologacao/MonitorIA-VIP-CapturePreview.exe
```

O status esperado é `NotSigned`. O SHA-256 permite conferir a integridade do arquivo baixado da sessão autenticada. Se a política do Windows bloquear o executável, aguarde a edição assinada. Siga o `LEIA-ME.txt` para abrir o simulador, autorizar a janela e testar o editor sem instalar SDK ou compilador.

## Se a compilação falhar

Procure as linhas `VIP native:` no job. Elas identificam a fase, as versões do SDK e do MSVC, dependências conhecidas ausentes e códigos de compilação ou link. Os caminhos, mensagens brutas do compilador e trechos de fonte ficam no log temporário do runner. O script remove esse log ao final.

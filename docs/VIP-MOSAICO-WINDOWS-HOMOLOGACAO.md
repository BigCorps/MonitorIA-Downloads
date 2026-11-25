# Homologação Windows da MonitorIA VIP Mosaico

O workflow **MonitorIA VIP Mosaico Windows homologation draft** compila a prévia de captura, prepara o simulador para uso offline e coloca o pacote assinado em um rascunho. O instalador operacional da Beta ainda é uma etapa posterior.

## Disparo

Assim que o workflow estiver disponível na branch padrão do Downloads, use uma conta autorizada a executar Actions e acessar rascunhos desse repositório.

```powershell
$repo = 'BigCorps/MonitorIA-Downloads'
$workflow = 'build-monitoria-vip-mosaic-beta.yml'
gh workflow run $workflow --repo $repo --ref main
gh run list --repo $repo --workflow $workflow --branch main --limit 1
```

A execução usa um commit fixo e revisado de BigCorps/MonitorIA. O token `MONITORIA_PRIVATE_SOURCE_TOKEN` precisa de acesso de leitura ao conteúdo do repositório privado. Ela usa `ESIGNER_USERNAME`, `ESIGNER_PASSWORD`, `ESIGNER_CREDENTIAL_ID`, `ESIGNER_TOTP_SECRET` e `MONITORIA_AGENT_RELEASE_SIGNING_KEY_B64` como secrets. A variável `MONITORIA_AGENT_RELEASE_KEY_SHA256` contém a impressão digital esperada da chave pública Ed25519.

## Acesso ao pacote

Uma execução concluída deixa um rascunho com a tag `vip-mosaic-windows-homologacao-v1.0.0-beta.1-<SHA abreviado>`. Acesse Releases autenticado com uma conta que tenha escrita no repositório. Baixe o ZIP, o manifesto e os arquivos de verificação. Antes do envio, o workflow confirma por ID que o rascunho está vazio e que o acesso anônimo é recusado. Depois do envio, confere o hash e a recusa de acesso anônimo de cada arquivo. Se houver falha, preserva o rascunho e tenta retirar somente os arquivos cujo envio teve ID confirmado nessa execução. Para um participante externo, transfira o ZIP por um canal de acesso privado autorizado.

```powershell
$archive = 'MonitorIA-VIP-Mosaico-1.0.0-beta.1-Homologacao.zip'
$manifest = Get-Content -Raw RELEASE-MANIFEST.json | ConvertFrom-Json
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.sha256) {
    throw 'O arquivo não corresponde ao manifesto.'
}
Expand-Archive $archive -DestinationPath MonitorIA-VIP-Homologacao
Get-AuthenticodeSignature ./MonitorIA-VIP-Homologacao/MonitorIA-VIP-CapturePreview.exe
```

A assinatura precisa ter status `Valid` e carimbo de tempo. Siga o `LEIA-ME.txt` extraído. O manifesto também registra o commit privado, o hash do executável e o estado da homologação interativa. `SHA256SUMS.sig` é a assinatura Ed25519 do arquivo `SHA256SUMS.txt`.

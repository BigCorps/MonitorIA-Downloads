# MonitorIA Windows 24/7 1.0.7 — rascunho de homologação

O workflow manual usa o runner padrão `windows-latest` do Downloads e a revisão privada `3bdbfe15253a26fb27b15ff018566caff130265c` da branch `codex/agent-multiplatform-consolidation`. Ele gera apenas o instalador Windows 24/7. O checkout, as saídas de diagnóstico e os binários intermediários ficam no runner descartável.

## Permissões e configuração

No repositório Downloads, confirme os seguintes nomes em **Settings → Secrets and variables → Actions**.

| Tipo | Nome | Uso |
| --- | --- | --- |
| Secret | `MONITORIA_PRIVATE_SOURCE_TOKEN` | Token fine-grained restrito a `BigCorps/MonitorIA`, com **Contents: Read-only** e expiração curta. Lê o commit e o FFmpeg assinado em `agent-deps-v1`. |
| Secret | `ESIGNER_USERNAME` | Conta SSL.com/eSigner existente. |
| Secret | `ESIGNER_PASSWORD` | Conta SSL.com/eSigner existente. |
| Secret | `ESIGNER_CREDENTIAL_ID` | Credencial do mesmo publicador da 1.0.6. |
| Secret | `ESIGNER_TOTP_SECRET` | TOTP da credencial existente. |
| Secret | `MONITORIA_AGENT_RELEASE_SIGNING_KEY_B64` | Chave PEM Ed25519 existente, codificada em Base64. |
| Variável | `MONITORIA_AGENT_RELEASE_KEY_SHA256` | SHA-256 da chave pública em DER, obtido da fingerprint confiável usada pela campanha privada. |

O job usa seu `GITHUB_TOKEN` automático com `contents: write` no Downloads para verificar a disponibilidade da tag e gravar o rascunho. A conta que inicia o workflow precisa de permissão de escrita em Actions no Downloads. A configuração de Actions do repositório deve permitir os três actions fixados no workflow e o token automático com escrita de conteúdo. Para reduzir a exposição dos segredos do repositório, mantenha alterações de workflows sob revisão de mantenedores com acesso de escrita controlado.

## Executar manualmente pelo PowerShell

Após revisão e merge desta PR na `main` do **Downloads**, execute com o GitHub CLI autenticado:

```powershell
$repo = 'BigCorps/MonitorIA-Downloads'
$workflow = 'build-monitoria-v107-windows-draft.yml'
gh workflow run $workflow --repo $repo --ref main
gh run list --repo $repo --workflow $workflow --event workflow_dispatch --limit 3
```

Acompanhe o ID da execução disparada com `gh run watch <ID> --repo $repo --exit-status`. Uma execução bem-sucedida deixa o rascunho `windows-247-v1.0.7-rc-3bdbfe15253a` em **Releases** para usuários autorizados. O rascunho contém:

- `MonitorIA-Setup.exe`
- `RELEASE-MANIFEST.json`
- `SHA256SUMS.txt`
- `SHA256SUMS.sig`
- `RELEASE-PUBLIC-KEY.pem`

O manifesto identifica a fonte privada em `sourceCommit` e a revisão do workflow público em `workflowCommit`. O workflow valida a fingerprint antes da compilação, assina os hashes e confere cada digest devolvido pelo GitHub. Um rascunho ou tag existente com o mesmo nome bloqueia um novo build. Uma falha durante o envio pode deixar um rascunho parcial para inspeção pelo mantenedor.

## Homologação e rollback

O gate nativo verifica a assinatura e o timestamp do instalador, componentes e desinstalador, atualiza a 1.0.6 compat1 real, confere pareamento, câmera e fila sintéticos e exercita o serviço Windows com Bun e Node. A seleção automática numa máquina sem AVX e o DVR Intelbras físico exigem teste em equipamento compatível. Num Windows de homologação, confirme que o upgrade preserva o pareamento e que canais ativos distintos do DVR aparecem individualmente, inclusive após uma nova busca.

Mantenha o rascunho até a aprovação de publicação. Para rollback, preserve uma cópia protegida de `%ProgramData%\MonitorIA` e reinstale a 1.0.6 compat1 por cima. O desinstalador remove o estado local.

- SHA-256 de rollback: `6cd19ac020c4978b397b5dd8b28424994a0df3be0e76b9a96131b03adc045191`. [Instalador oficial 1.0.6 compat1](https://github.com/BigCorps/MonitorIA-Downloads/releases/download/agent-v1.0.6-windows-compat1/MonitorIA-Setup.exe)

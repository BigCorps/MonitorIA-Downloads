# Rascunho de homologação Windows 24/7 1.0.8

Use este workflow manual do Downloads se a campanha do repositório privado estiver indisponível. A fonte é verificada no commit privado `94897150c138169a1f6f3e7392124037afa4ce48`. Mantenha o repositório de origem privado.

O runner exige os mesmos secrets e a mesma fingerprint documentados para a 1.0.7. O token de leitura da fonte fica separado do token automático do Downloads, que lê o rascunho assinado 1.0.7 para o teste de upgrade e grava exclusivamente o novo Draft. [Configurações exigidas](BUILD-AGENT-1.0.7-WINDOWS.md)

Após aprovação e merge desta alteração no **Downloads**, use PowerShell autenticado no GitHub CLI.

```powershell
$repo = 'BigCorps/MonitorIA-Downloads'
$workflow = 'build-monitoria-v108-windows-draft.yml'
gh workflow run $workflow --repo $repo --ref main
gh run list --repo $repo --workflow $workflow --event workflow_dispatch --limit 3
```

Use somente uma campanha de assinatura. O rascunho `rc-v108-94897150c138-windows-247` deve conter o instalador, o manifesto, os hashes, a assinatura Ed25519 e a chave pública. A autenticação, os upgrades e a instalação limpa são executados no runner. O teste físico da Intelbras Mibo e a aprovação da publicação ocorrem depois.

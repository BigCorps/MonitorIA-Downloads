# Build manual 1.0.6 — Windows piloto

A 1.0.6 fica em código-fonte **privado** no repositório `BigCorps/MonitorIA`, PR #109, commit fixo `7928e32ef4255512ebd104bed6673a597641d592`. O repositório público `MonitorIA-Downloads` executa um runner Windows gratuito (GitHub Actions padrão em repositórios públicos) sem fazer commit, cache ou upload do código-fonte privado.

## Primeiro uso

1. Gere um **fine-grained personal access token** em https://github.com/settings/personal-access-tokens/new, proprietário BigCorps, acesso somente a **BigCorps/MonitorIA**, permissão **Contents: Read-only** e prazo de expiração curto.
2. Cadastre-o em **Settings → Secrets and variables → Actions → New repository secret**, no **repositório público MonitorIA-Downloads**, com o nome `MONITORIA_PRIVATE_SOURCE_TOKEN`. Não envie o valor em conversas.
3. O build **assinado** exige neste repositório público os seguintes secrets SSL.com eSigner, já usados pelo pipeline privado: `ESIGNER_USERNAME`, `ESIGNER_PASSWORD`, `ESIGNER_CREDENTIAL_ID`, `ESIGNER_TOTP_SECRET`. Eles não são copiados automaticamente entre repositórios. Reobtenha-os da fonte segura original; o GitHub não permite ler segredos existentes em texto claro. **Não copie credenciais em arquivos do repositório**. Verifique quem tem acesso de escrita ao repositório público antes de acrescentar segredos de assinatura. Alternativa mais restrita: usar runner Windows **self-hosted no repositório privado**, sem cobrança de minutos do GitHub.
4. Acesse https://github.com/BigCorps/MonitorIA-Downloads/actions/workflows/build-monitoria-v106-windows-pilot.yml e clique em **Run workflow** na branch `main`.
5. Após o job em estado success, na execução procure **Artifacts → MonitorIA-Agent-1.0.6-Windows-PILOTO**. O download do artifact deste repositório público **não é privado** e fica disponível durante 2 dias; contém **somente** `MonitorIA-Setup.exe`, `SHA256SUMS.txt` e `pilot-manifest.json`, nunca código-fonte nem chaves.
6. O workflow exige assinatura Authenticode e carimbo de tempo, valida o SHA256, instala a 1.0.5 verdadeira no Windows de testes, atualiza para a 1.0.6 e verifica preservação do estado, funcionamento do serviço e desinstalação do tray antigo. **Só depois** teste a Jortan física e registre o resultado.

## Atenção

- Esta release é **PILOTO**: não altera os downloads oficiais, não afeta Linux e não publica na Microsoft Store.
- O código-fonte fica em checkout temporário no runner; **logs de compilação podem ser públicos**, por isso os secrets do build devem ter acesso restrito e nenhum log deve imprimir tokens, senhas ou código confidencial.
- Se o novo build revelar erro de código, corrija primeiro o PR privado, fixe outro commit SHA revisto neste workflow e rode novamente, sem builds contínuos.
- Se o GitHub bloquear também os runners grátis em repositório público por uma restrição de conta, use self-hosted em Windows no repositório privado e mantenha esse mesmo contrato de assinatura.

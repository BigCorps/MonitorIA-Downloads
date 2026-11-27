#!/usr/bin/env bash
set -euo pipefail
[[ "$GITHUB_REPOSITORY" == BigCorps/MonitorIA-Downloads && "$GITHUB_REF" == refs/heads/ci/agent-v109-native-qualification ]]
[[ "$GITHUB_EVENT_NAME" == push || "$GITHUB_EVENT_NAME" == workflow_dispatch ]]
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" && "$(git -C private-src rev-parse HEAD)" == "$MONITORIA_SOURCE_SHA" ]]
[[ "$MONITORIA_SOURCE_SHA" == 339046a946a884d898fb9120c7e109b4c5798c35 ]]
channel="$1"; dir="$2"
case "$channel" in
  windows) assets=(windows-components-1.0.9.tar.gz); gate=compiled_components_only ;;
  linux-x64|linux-arm64) assets=("monitoria-agent-$channel-1.0.9.tar.gz"); gate=native_upgrade_verified ;;
  android-pdv) assets=(MonitorIA-Android-PDV-0.2.22-private.apk VERIFIED-RELEASE.json); gate=certificate_and_upgrade_verified ;;
  android-conventional) assets=(MonitorIA-Android-0.3.1.apk VERIFIED-RELEASE.json); gate=certificate_and_install_verified ;;
  *) exit 2 ;;
esac
tag="qual-v109-339046a946a8-$channel"
[[ "$(gh api "repos/$GITHUB_REPOSITORY" --jq .private)" == false ]]
existing="$(gh api --method GET "repos/$GITHUB_REPOSITORY/releases" -f per_page=100 --paginate --jq ".[] | select(.tag_name == \"$tag\") | .id")"
[[ -z "$existing" ]] || { echo 'Qualification draft already exists; preserve original inputs.'; exit 1; }
cd "$dir"
for asset in "${assets[@]}"; do test -s "$asset"; done
jq -n --arg channel "$channel" --arg gate "$gate" --arg source "$MONITORIA_SOURCE_SHA" --arg workflow "$GITHUB_SHA" --arg run "$GITHUB_RUN_ID" '{version:"1.0.9",channel:$channel,qualification:$gate,sourceCommit:$source,workflowCommit:$workflow,workflowRun:$run,distribution:"qualification-only",manifestSignature:"pending",physicalValidation:"pending"}' > QUALIFICATION.json
assets+=(QUALIFICATION.json)
sha256sum "${assets[@]}" > SHA256SUMS.txt
assets+=(SHA256SUMS.txt)
gh release create "$tag" "${assets[@]}" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" --draft --prerelease --title "QUALIFICATION ONLY — MonitorIA 1.0.9 $channel" --notes "Restrito a mantenedores. Não distribuir. Assinatura final do manifesto e homologação física pendentes." >/dev/null
record="$(gh api --method GET "repos/$GITHUB_REPOSITORY/releases" -f per_page=100 --paginate --jq ".[] | select(.tag_name == \"$tag\")")"
jq -e --arg target "$GITHUB_SHA" --argjson count "${#assets[@]}" '.draft == true and .prerelease == true and .published_at == null and .target_commitish==$target and (.assets|length)==$count' <<< "$record" >/dev/null
for asset in "${assets[@]}"; do
  digest="$(sha256sum "$asset" | cut -d' ' -f1)"
  jq -e --arg file "$asset" --arg digest "sha256:$digest" 'any(.assets[];.name==$file and .digest==$digest and .state=="uploaded")' <<< "$record" >/dev/null
done
echo "Verified unpublished qualification draft: $tag"

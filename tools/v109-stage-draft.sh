#!/usr/bin/env bash
set -euo pipefail
[[ "$GITHUB_REPOSITORY" == BigCorps/MonitorIA-Downloads && "$GITHUB_REF" == refs/heads/main && "$GITHUB_EVENT_NAME" == workflow_dispatch ]]
[[ "$GITHUB_SHA" =~ ^[a-f0-9]{40}$ && "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
[[ "$MONITORIA_SOURCE_SHA" =~ ^[a-f0-9]{40}$ && "$(git -C private-src rev-parse HEAD)" == "$MONITORIA_SOURCE_SHA" ]]
channel="$1"
dir="$2"
case "$channel" in
  windows) assets=(MonitorIA-Setup.exe MonitorIA-Store-Setup.exe) ;;
  linux-x64|linux-arm64) assets=("monitoria-agent-$channel-1.0.9.tar.gz") ;;
  android-pdv) assets=(MonitorIA-Android-PDV-0.2.22-private.apk VERIFIED-RELEASE.json) ;;
  android-conventional) assets=(MonitorIA-Android-0.3.1.apk VERIFIED-RELEASE.json) ;;
  *) exit 2 ;;
esac
tag="rc-v109-$MONITORIA_SOURCE_SHA-$channel"
tag="rc-v109-$(printf '%.12s' "$MONITORIA_SOURCE_SHA")-$channel"
existing="$(gh api --method GET "repos/$GITHUB_REPOSITORY/releases" -f per_page=100 --paginate --jq ".[] | select(.tag_name == \"$tag\") | .id")"
[[ -z "$existing" ]] || { echo 'Immutable draft already exists'; exit 1; }
[[ "$(gh api "repos/$GITHUB_REPOSITORY" --jq .private)" == false ]]
[[ "$TRUSTED_RELEASE_FINGERPRINT" =~ ^[a-f0-9]{64}$ && -n "$MANIFEST_SIGNING_KEY_B64" ]]
umask 077
key="$(mktemp)"
trap 'rm -f -- "$key"' EXIT
printf '%s' "$MANIFEST_SIGNING_KEY_B64" | base64 --decode > "$key"
[[ "$(openssl pkey -in "$key" -pubout -outform DER | sha256sum | cut -d' ' -f1)" == "$TRUSTED_RELEASE_FINGERPRINT" ]]
cd "$dir"
for asset in "${assets[@]}"; do test -s "$asset"; done
jq -n --arg channel "$channel" --arg source "$MONITORIA_SOURCE_SHA" --arg workflow "$GITHUB_SHA" '{version:"1.0.9",channel:$channel,sourceRepository:"BigCorps/MonitorIA",sourceCommit:$source,workflowCommit:$workflow,distribution:"draft",physicalValidation:"pending"}' > RELEASE-MANIFEST.json
assets+=(RELEASE-MANIFEST.json)
sha256sum "${assets[@]}" > SHA256SUMS.txt
openssl pkey -in "$key" -pubout -out RELEASE-PUBLIC-KEY.pem
openssl pkeyutl -sign -rawin -inkey "$key" -in SHA256SUMS.txt -out SHA256SUMS.sig
test "$(wc -c < SHA256SUMS.sig | tr -d '[:space:]')" -eq 64
openssl pkeyutl -verify -rawin -pubin -inkey RELEASE-PUBLIC-KEY.pem -in SHA256SUMS.txt -sigfile SHA256SUMS.sig
assets+=(SHA256SUMS.txt SHA256SUMS.sig RELEASE-PUBLIC-KEY.pem)
gh release create "$tag" "${assets[@]}" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" --draft --prerelease --title "MonitorIA 1.0.9 RC — $channel" --notes "Candidato não publicado. Homologação física pendente. Fonte privada fixada em $MONITORIA_SOURCE_SHA." >/dev/null
record="$(gh api --method GET "repos/$GITHUB_REPOSITORY/releases" -f per_page=100 --paginate --jq ".[] | select(.tag_name == \"$tag\")")"
jq -e --arg target "$GITHUB_SHA" --argjson count "${#assets[@]}" '.draft == true and .prerelease == true and .published_at == null and .target_commitish == $target and (.assets|length)==$count' <<< "$record" >/dev/null
for asset in "${assets[@]}"; do
  digest="$(sha256sum "$asset" | cut -d' ' -f1)"
  jq -e --arg file "$asset" --arg digest "sha256:$digest" 'any(.assets[];.name==$file and .digest==$digest and .state=="uploaded")' <<< "$record" >/dev/null
done
echo "Verified unpublished draft: $tag"

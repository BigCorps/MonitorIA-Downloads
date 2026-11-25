#!/usr/bin/env bash
set -euo pipefail

[[ "${GITHUB_REPOSITORY:-}" == BigCorps/MonitorIA-Downloads ]]
[[ "${GITHUB_REF:-}" == refs/heads/main && "${GITHUB_EVENT_NAME:-}" == workflow_dispatch ]]
[[ "$GITHUB_SHA" =~ ^[a-f0-9]{40}$ && "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
[[ "$MONITORIA_SOURCE_SHA" =~ ^[a-f0-9]{40}$ ]]
version="${MONITORIA_RELEASE_VERSION:-1.0.7}"
case "$version" in
  1.0.7) tag="windows-247-v1.0.7-rc-${MONITORIA_SOURCE_SHA:0:12}"; source_branch="codex/agent-multiplatform-consolidation" ;;
  1.0.8) tag="rc-v108-${MONITORIA_SOURCE_SHA:0:12}-windows-247"; source_branch="codex/agent-v108-rtmp-local" ;;
  *) exit 2 ;;
esac

check_tag() {
  local matches refs
  matches="$(gh api --method GET "repos/$GITHUB_REPOSITORY/releases" -f per_page=100 --paginate     --jq ".[] | select(.tag_name == \"$tag\") | .id")"
  refs="$(gh api "repos/$GITHUB_REPOSITORY/git/matching-refs/tags/$tag"     --jq ".[] | select(.ref == \"refs/tags/$tag\") | .ref")"
  [[ -z "$matches" && -z "$refs" ]] || { echo 'The candidate release or tag already exists.' >&2; exit 1; }
}

mode="${1:-}"
case "$mode" in
  check)
    for tool in gh jq openssl sha256sum base64; do command -v "$tool" >/dev/null; done
    check_tag
    exit
    ;;
  verify-key|stage) ;;
  *) exit 2 ;;
esac

[[ "$MONITORIA_AGENT_RELEASE_KEY_SHA256" =~ ^[a-f0-9]{64}$ ]]
umask 077
key_dir="$(mktemp -d)"
trap 'rm -- "$key_dir"/{key.pem,RELEASE-PUBLIC-KEY.pem,probe,probe.sig} 2>/dev/null || true; rmdir -- "$key_dir"' EXIT
key="$key_dir/key.pem"
public_key="$key_dir/RELEASE-PUBLIC-KEY.pem"
printf '%s' "$MONITORIA_AGENT_RELEASE_SIGNING_KEY_B64" | base64 --decode > "$key"
openssl pkey -in "$key" -passin pass: -pubout -out "$public_key" 2>/dev/null
openssl pkey -pubin -in "$public_key" -text_pub -noout | grep -qx 'ED25519 Public-Key:'
fingerprint="$(openssl pkey -pubin -in "$public_key" -outform DER | sha256sum | cut -d' ' -f1)"
[[ "$fingerprint" == "$MONITORIA_AGENT_RELEASE_KEY_SHA256" ]] || { echo 'Manifest signing key fingerprint mismatch.' >&2; exit 1; }
# Exercise the exact signing operation and reject keys without Ed25519 signatures.
printf 'MonitorIA Windows 24/7 manifest key check\n' > "$key_dir/probe"
openssl pkeyutl -sign -rawin -inkey "$key" -passin pass: -in "$key_dir/probe" -out "$key_dir/probe.sig" 2>/dev/null
[[ "$(wc -c < "$key_dir/probe.sig" | tr -d '[:space:]')" == 64 ]]
[[ "$mode" == verify-key ]] && exit 0

check_tag
[[ "$(git -C private-src rev-parse HEAD)" == "$MONITORIA_SOURCE_SHA" ]]
[[ "$2" == private-src/release-windows ]]
cd "$2"
test -s MonitorIA-Setup.exe
setup_digest="$(sha256sum MonitorIA-Setup.exe | cut -d' ' -f1)"
jq -n --arg source "$MONITORIA_SOURCE_SHA" --arg workflow "$GITHUB_SHA" --arg version "$version" --arg branch "$source_branch"   --arg digest "$setup_digest" --arg key "$fingerprint" '{
  version: $version, channel: "windows-247", sourceRepository: "BigCorps/MonitorIA",
  sourceBranch: $branch, sourceCommit: $source,
  workflowCommit: $workflow, sha256: $digest, manifestSigningKeySha256: $key,
  distribution: "draft", physicalValidation: "pending"
}' > RELEASE-MANIFEST.json
sha256sum MonitorIA-Setup.exe RELEASE-MANIFEST.json > SHA256SUMS.txt
cp "$public_key" RELEASE-PUBLIC-KEY.pem
openssl pkeyutl -sign -rawin -inkey "$key" -passin pass: -in SHA256SUMS.txt -out SHA256SUMS.sig 2>/dev/null
openssl pkeyutl -verify -rawin -pubin -inkey RELEASE-PUBLIC-KEY.pem -in SHA256SUMS.txt -sigfile SHA256SUMS.sig
sha256sum --check SHA256SUMS.txt

assets=(MonitorIA-Setup.exe RELEASE-MANIFEST.json SHA256SUMS.txt SHA256SUMS.sig RELEASE-PUBLIC-KEY.pem)
# The tag targets the public repository commit. Only the manifest identifies the private source.
gh release create "$tag" "${assets[@]}" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA"   --draft --prerelease --title "MonitorIA Windows 24/7 $version RC"   --notes 'Rascunho para homologação Windows. Validação física pendente.' >/dev/null

record="$(gh api --method GET "repos/$GITHUB_REPOSITORY/releases" -f per_page=100 --paginate   --jq ".[] | select(.tag_name == \"$tag\")")"
jq -e --arg target "$GITHUB_SHA" --argjson count "${#assets[@]}"   '.draft == true and .prerelease == true and .published_at == null and
   .target_commitish == $target and (.assets | length) == $count' <<< "$record" >/dev/null
for file in "${assets[@]}"; do
  digest="sha256:$(sha256sum "$file" | cut -d' ' -f1)"
  jq -e --arg file "$file" --arg digest "$digest"     'any(.assets[]; .name == $file and .digest == $digest and .state == "uploaded")'     <<< "$record" >/dev/null
done
echo 'Draft, uploaded asset digests and unpublished state verified.'

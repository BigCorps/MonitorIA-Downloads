#!/usr/bin/env bash
set -euo pipefail

[[ "${GITHUB_REPOSITORY:-}" == BigCorps/MonitorIA-Downloads ]]
[[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch ]]
case "${GITHUB_REF:-}" in
  refs/heads/main) ;;
  refs/heads/codex/vip-mosaic-unsigned-homologation) [[ "${GITHUB_ACTOR:-}" == BigCorps && "${GITHUB_TRIGGERING_ACTOR:-}" == BigCorps ]] ;;
  *) exit 2 ;;
esac
[[ "${GITHUB_SHA:-}" =~ ^[a-f0-9]{40}$ && "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
[[ "${MONITORIA_SOURCE_SHA:-}" =~ ^[a-f0-9]{40}$ ]]

tag="vip-mosaic-windows-unsigned-v1.0.0-beta.1-${MONITORIA_SOURCE_SHA:0:12}"
bundle="MonitorIA-VIP-Mosaico-1.0.0-beta.1-Homologacao-NAO-ASSINADO.zip"
release_endpoint="repos/$GITHUB_REPOSITORY/releases"
asset_api="https://api.github.com/$release_endpoint/assets"
release_id=""
declare -a uploaded=()

read_draft() {
  gh api --method GET "$release_endpoint" -f per_page=100 --paginate \
    --jq ".[] | select(.tag_name == \"$tag\")$1"
}

check_tag() {
  local matches refs
  matches="$(read_draft ' | .id')"
  refs="$(gh api "repos/$GITHUB_REPOSITORY/git/matching-refs/tags/$tag" \
    --jq ".[] | select(.ref == \"refs/tags/$tag\") | .ref")"
  [[ -z "$matches" && -z "$refs" ]] || { echo 'The homologation draft or tag already exists.' >&2; exit 1; }
}


is_expected_draft() {
  jq -e --arg id "$release_id" --arg tag "$tag" --arg target "$GITHUB_SHA" \
    '(.id | tostring) == $id and .tag_name == $tag and
     .draft == true and .prerelease == true and .published_at == null and .target_commitish == $target' >/dev/null
}

check_anonymous_denial() {
  local status
  # Never pass credentials or read a user config in this anonymous request.
  status="$(curl -q --silent --show-error --max-time 20 --output /dev/null --write-out '%{http_code}' \
    --header 'Accept: application/octet-stream' "$1")"
  [[ "$status" == 404 ]] || { echo 'Anonymous GitHub access was not rejected as expected.' >&2; exit 1; }
}

cleanup_uploaded_assets() {
  local asset current name id
  for asset in "${uploaded[@]}"; do
    name="${asset%:*}"
    id="${asset##*:}"
    # Check the draft ID and membership again before each deletion. Preserve
    # the draft itself and ignore assets for which this run has no upload ID.
    if current="$(gh api "$release_endpoint/$release_id")" && is_expected_draft <<< "$current" &&
         jq -e --arg name "$name" --arg id "$id" \
           'any(.assets[]; .name == $name and (.id | tostring) == $id)' <<< "$current" >/dev/null; then
      gh api --method DELETE "$release_endpoint/assets/$id" --silent ||
        echo 'A staged asset could not be removed after verification failed.' >&2
    else
      echo 'Draft identity or staged asset could not be confirmed during cleanup.' >&2
    fi
  done
}

mode="${1:-}"
case "$mode" in
  check)
    for tool in git gh jq sha256sum curl; do command -v "$tool" >/dev/null; done
    check_tag
    exit
    ;;
  stage) ;;
  *) exit 2 ;;
esac

cleanup() {
  local exit_status=$?
  trap - EXIT
  if (( exit_status != 0 )) && [[ -n "$release_id" ]]; then
    cleanup_uploaded_assets
  fi
  exit "$exit_status"
}
trap cleanup EXIT

check_tag
[[ "$(git -C private-src rev-parse HEAD)" == "$MONITORIA_SOURCE_SHA" ]]
cd release-vip
[[ -f "$bundle" && ! -L "$bundle" && -s "$bundle" ]]
bundle_digest="$(sha256sum "$bundle" | cut -d' ' -f1)"
jq -e \
  '(.files | keys == ["LEIA-ME.txt", "MonitorIA-VIP-CapturePreview.exe", "MonitorIA-VIP-Simulador.html"]) and
   (.files | all(.[]; test("^[a-f0-9]{64}$"))) and
   (.authenticode.file == "MonitorIA-VIP-CapturePreview.exe") and
   (.authenticode.status == "NotSigned") and (.authenticode.timestampVerified == false)' \
  WINDOWS-VERIFICATION.json >/dev/null
jq --arg source "$MONITORIA_SOURCE_SHA" --arg workflow "$GITHUB_SHA" --arg bundle "$bundle" \
  --arg digest "$bundle_digest" '{
  version: "1.0.0-beta.1", artifactType: "unsigned-internal-homologation-preview", channel: "vip-mosaic-windows",
  sourceRepository: "BigCorps/MonitorIA", sourceBranch: "feature/vip-agent-mosaic-1.0.0",
  sourceCommit: $source, workflowCommit: $workflow, archive: $bundle, sha256: $digest,
  distribution: "draft", manifestSigned: false, windowsInteractiveValidation: "pending",
  files: .files, authenticode: {
    file: .authenticode.file, status: .authenticode.status,
    timestampVerified: .authenticode.timestampVerified
  }
}' WINDOWS-VERIFICATION.json > RELEASE-MANIFEST.json
sha256sum "$bundle" RELEASE-MANIFEST.json > SHA256SUMS.txt
sha256sum --check SHA256SUMS.txt >/dev/null

assets=("$bundle" RELEASE-MANIFEST.json SHA256SUMS.txt)
[[ "${GH_TOKEN:-}" =~ ^[A-Za-z0-9_]+$ ]]
record="$(gh api --method POST "$release_endpoint" -f tag_name="$tag" -f target_commitish="$GITHUB_SHA" \
  -F draft=true -F prerelease=true -f name='MonitorIA VIP Mosaico 1.0.0-beta.1 — homologação Windows NÃO ASSINADA' \
  -f body='Prévia NÃO ASSINADA para homologação interna exclusiva do proprietário. Acesso restrito a colaboradores com escrita. Não publicar nem redistribuir.')"
release_id="$(jq -er '.id | numbers' <<< "$record")"
[[ "$release_id" =~ ^[0-9]+$ ]]
is_expected_draft <<< "$record"
jq -e '.assets | length == 0' <<< "$record" >/dev/null
record="$(gh api "$release_endpoint/$release_id")"
is_expected_draft <<< "$record"
jq -e '.assets | length == 0' <<< "$record" >/dev/null
check_anonymous_denial "https://api.github.com/$release_endpoint/$release_id"

for file in "${assets[@]}"; do
  # The write token goes directly to curl's stdin. The endpoint is fixed to the
  # public Downloads repository and the verified draft ID. Forbid redirects.
  response="$(printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN" |
    curl -q --config - --silent --show-error --fail --max-time 180 \
      --header 'Accept: application/vnd.github+json' --header 'Content-Type: application/octet-stream' \
      --data-binary "@$file" "https://uploads.github.com/$release_endpoint/$release_id/assets?name=$file")"
  id="$(jq -er '.id | numbers' <<< "$response")"
  [[ "$id" =~ ^[0-9]+$ ]]
  uploaded+=("$file:$id")
done

record="$(gh api "$release_endpoint/$release_id")"
is_expected_draft <<< "$record"
jq -e --argjson count "${#assets[@]}" '.assets | length == $count' <<< "$record" >/dev/null
for asset in "${uploaded[@]}"; do
  file="${asset%:*}"
  id="${asset##*:}"
  digest="sha256:$(sha256sum "$file" | cut -d' ' -f1)"
  jq -e --arg id "$id" --arg file "$file" --arg digest "$digest" \
    'any(.assets[]; (.id | tostring) == $id and .name == $file and .digest == $digest and .state == "uploaded")' \
    <<< "$record" >/dev/null
  check_anonymous_denial "$asset_api/$id"
done
echo 'Unpublished draft, uploaded asset digests, and anonymous access denial verified.'

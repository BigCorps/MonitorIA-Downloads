#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

phase=workflow-scope
scratch=
release_id=
draft_target=
declare -a uploaded=()

fail() {
  printf 'VIP distribution: %s\n' "$1" >&2
  exit 1
}

start_phase() {
  phase=$1
  printf 'VIP distribution: phase=%s\n' "$phase"
}

cleanup() {
  local exit_status=$?
  trap - EXIT
  if (( exit_status != 0 )); then
    printf 'VIP distribution: failed phase=%s exit=%s\n' "$phase" "$exit_status" >&2
    if [[ "$release_id" =~ ^[0-9]+$ && "${#uploaded[@]}" -gt 0 ]]; then
      cleanup_uploaded_assets
    fi
  fi
  if [[ -n "$scratch" ]]; then
    rm -f -- "$scratch/api-error" "$scratch/public-release.json" && rmdir -- "$scratch" || true
  fi
  exit "$exit_status"
}
trap cleanup EXIT

[[ "${GITHUB_REPOSITORY:-}" == BigCorps/MonitorIA-Downloads ]]
[[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch ]]
case "${GITHUB_REF:-}" in
  refs/heads/main) ;;
  refs/heads/codex/vip-mosaic-unsigned-homologation) [[ "${GITHUB_ACTOR:-}" == BigCorps && "${GITHUB_TRIGGERING_ACTOR:-}" == BigCorps ]] ;;
  *) exit 2 ;;
esac
[[ "${GITHUB_SHA:-}" =~ ^[a-f0-9]{40}$ && "$(git rev-parse HEAD 2>/dev/null)" == "$GITHUB_SHA" ]]
[[ "${MONITORIA_SOURCE_SHA:-}" =~ ^[a-f0-9]{40}$ ]]

tag="vip-mosaic-windows-unsigned-v1.0.0-beta.2-${MONITORIA_SOURCE_SHA:0:12}"
bundle="MonitorIA-VIP-Mosaico-1.0.0-beta.2-Homologacao-NAO-ASSINADO.zip"
release_endpoint="repos/$GITHUB_REPOSITORY/releases"
asset_api="https://api.github.com/$release_endpoint/assets"
json_media=application/vnd.github+json
binary_media=application/octet-stream
draft_name='MonitorIA VIP Mosaico 1.0.0-beta.2 — homologação Windows NÃO ASSINADA'
draft_notes='Prévia NÃO ASSINADA para homologação interna exclusiva do proprietário. Acesso restrito a colaboradores com escrita. Não publicar nem redistribuir.'
draft_target=$GITHUB_SHA
start_phase dependencies
for tool in git gh jq sha256sum curl; do
  command -v "$tool" >/dev/null || fail "missing_tool=$tool"
done
scratch="$(mktemp -d)"

start_phase token-binding
# GitHub tokens are opaque. Accept valid bearer-header characters including
# stateless ghs tokens with JWT separators. Reject curl config delimiters.
[[ "${GH_TOKEN:-}" =~ ^[-A-Za-z0-9._~+/]+=*$ ]] || fail 'missing or unsafe GH_TOKEN value'

github_api() {
  local status rc
  if gh api "$@" 2>"$scratch/api-error"; then return 0; else rc=$?; fi
  status="$(sed -nE 's/.*\(HTTP ([45][0-9]{2})\).*/\1/p' "$scratch/api-error" | head -n 1)"
  printf 'VIP distribution: phase=%s api_exit=%s http=%s\n' "$phase" "$rc" "${status:-unknown}" >&2
  return "$rc"
}

hash_file() {
  local entry
  entry="$(sha256sum --binary -- "$1" 2>/dev/null)" || return
  [[ "${entry%% *}" =~ ^[a-f0-9]{64}$ ]] || return 1
  printf '%s\n' "${entry%% *}"
}

read_draft() {
  github_api --method GET "$release_endpoint" -f per_page=100 --paginate \
    --jq ".[] | select(.tag_name == \"$tag\")$1"
}

check_tag() {
  local matches refs
  matches="$(read_draft ' | .id')"
  refs="$(github_api "repos/$GITHUB_REPOSITORY/git/matching-refs/tags/$tag" \
    --jq ".[] | select(.ref == \"refs/tags/$tag\") | .ref")"
  [[ -z "$matches" && -z "$refs" ]] || fail "the exact VIP draft or tag already exists and was left intact"
}

is_expected_draft() {
  jq -e --arg id "$release_id" --arg tag "$tag" --arg target "$draft_target" \
    --arg name "$draft_name" --arg body "$draft_notes" \
    '(.id | tostring) == $id and .tag_name == $tag and
     .draft == true and .prerelease == true and .published_at == null and
     .target_commitish == $target and .name == $name and .body == $body' >/dev/null 2>&1
}

require_empty_draft() {
  is_expected_draft <<< "$1" || fail "draft identity, origin or visibility did not match"
  jq -e '.assets | type == "array" and length == 0' <<< "$1" >/dev/null 2>&1 ||
    fail "draft does not have an empty asset list"
}

anonymous_status() {
  local status
  # No curlrc, authorization header, or redirect. Record the endpoint response.
  status="$(curl -q --silent --show-error --max-time 20 --output "${3:-/dev/null}" --write-out '%{http_code}' \
    --header "Accept: $2" "$1" 2>/dev/null)" || fail "anonymous access check transport failed"
  [[ "$status" =~ ^[0-9]{3}$ ]] || fail "invalid anonymous HTTP status"
  printf '%s\n' "$status"
}

check_anonymous_denial() {
  local status
  status="$(anonymous_status "$1" "$2")"
  printf 'VIP distribution: phase=%s accept=%s http=%s\n' "$phase" "$2" "$status"
  [[ "$status" == 404 ]] || fail "Anonymous GitHub access was not rejected as expected (HTTP $status)"
}

check_public_controls() {
  local status id endpoint
  start_phase anonymous-public-controls
  # Use a stable public release and its small checksums asset as controls.
  endpoint=https://api.github.com/repos/cli/cli/releases
  status="$(anonymous_status "$endpoint/tags/v2.65.0" "$json_media" "$scratch/public-release.json")"
  printf 'VIP distribution: control=release-json http=%s\n' "$status"
  [[ "$status" == 200 ]] || fail "public release JSON control failed"
  id="$(jq -er '.assets[] | select(.name == "gh_2.65.0_checksums.txt") | .id | numbers' "$scratch/public-release.json" 2>/dev/null)" ||
    fail "public release control checksums asset not found"
  [[ "$id" =~ ^[0-9]+$ ]] || fail "invalid public control asset ID"
  status="$(anonymous_status "$endpoint/assets/$id" "$json_media")"
  printf 'VIP distribution: control=asset-json http=%s\n' "$status"
  [[ "$status" == 200 ]] || fail "public asset JSON control failed"
  status="$(anonymous_status "$endpoint/assets/$id" "$binary_media")"
  printf 'VIP distribution: control=asset-binary http=%s\n' "$status"
  [[ "$status" == 200 || "$status" == 302 ]] || fail "public asset binary control failed"
}

cleanup_uploaded_assets() {
  local asset current name id
  for asset in "${uploaded[@]}"; do
    name="${asset%:*}"
    id="${asset##*:}"
    # Check the draft ID and membership again before each deletion. Preserve
    # the draft itself and ignore assets for which this run has no upload ID.
    if current="$(github_api "$release_endpoint/$release_id")" && is_expected_draft <<< "$current" &&
         jq -e --arg name "$name" --arg id "$id" \
           'any(.assets[]; .name == $name and (.id | tostring) == $id)' <<< "$current" >/dev/null 2>&1; then
      github_api --method DELETE "$release_endpoint/assets/$id" --silent ||
        echo 'A staged asset could not be removed after verification failed.' >&2
    else
      echo 'Draft identity or staged asset could not be confirmed during cleanup.' >&2
    fi
  done
}

if [[ "${1:-}" == preflight ]]; then
  check_public_controls
fi
start_phase draft-availability
check_tag
case "${1:-}" in
  preflight|check) exit 0 ;;
  stage) ;;
  *) fail "unsupported release command" ;;
esac

start_phase source-and-package
[[ "$(git -C private-src rev-parse HEAD 2>/dev/null)" == "$MONITORIA_SOURCE_SHA" ]] || fail "private source revision mismatch"
cd release-vip 2>/dev/null || fail "missing package directory"
[[ -f "$bundle" && ! -L "$bundle" && -s "$bundle" ]] || fail "missing or empty unsigned ZIP"
bundle_digest="$(hash_file "$bundle")" || fail "cannot calculate ZIP SHA-256"
start_phase windows-manifest
jq -e \
  '(.files | keys == ["LEIA-ME.txt", "MonitorIA-VIP-CapturePreview.exe", "MonitorIA-VIP-Simulador.html"]) and
   (.files | all(.[]; test("^[a-f0-9]{64}$"))) and
   (.authenticode.file == "MonitorIA-VIP-CapturePreview.exe") and
   (.authenticode.status == "NotSigned") and (.authenticode.timestampVerified == false)' \
  WINDOWS-VERIFICATION.json >/dev/null 2>&1 || fail "invalid Windows package verification manifest"
jq --arg source "$MONITORIA_SOURCE_SHA" --arg workflow "$GITHUB_SHA" --arg bundle "$bundle" \
  --arg digest "$bundle_digest" --arg draftTarget "$draft_target" '{
  version: "1.0.0-beta.2", artifactType: "unsigned-internal-homologation-preview", channel: "vip-mosaic-windows",
  sourceRepository: "BigCorps/MonitorIA", sourceBranch: "feature/vip-agent-mosaic-1.0.0",
  sourceCommit: $source, workflowCommit: $workflow, draftTargetCommit: $draftTarget, archive: $bundle, sha256: $digest,
  distribution: "draft", manifestSigned: false, windowsInteractiveValidation: "pending",
  files: .files, authenticode: {
    file: .authenticode.file, status: .authenticode.status,
    timestampVerified: .authenticode.timestampVerified
  }
}' WINDOWS-VERIFICATION.json > RELEASE-MANIFEST.json 2>/dev/null || fail "cannot generate release manifest"
start_phase checksums
sha256sum --binary -- "$bundle" RELEASE-MANIFEST.json > SHA256SUMS.txt 2>/dev/null || fail "cannot generate SHA256SUMS"
sha256sum --check SHA256SUMS.txt >/dev/null 2>&1 || fail "ZIP or release manifest checksum mismatch"

assets=("$bundle" RELEASE-MANIFEST.json SHA256SUMS.txt)
start_phase create-draft
record="$(github_api --method POST "$release_endpoint" -f tag_name="$tag" -f target_commitish="$draft_target" \
  -F draft=true -F prerelease=true -f name="$draft_name" -f body="$draft_notes")"
release_id="$(jq -er '.id | numbers' <<< "$record" 2>/dev/null)" || fail "missing numeric draft ID"
[[ "$release_id" =~ ^[0-9]+$ ]] || fail "invalid draft ID"
require_empty_draft "$record"
start_phase verify-empty-draft
record="$(github_api "$release_endpoint/$release_id")"
require_empty_draft "$record"
start_phase anonymous-draft
check_anonymous_denial "https://api.github.com/$release_endpoint/$release_id" "$json_media"

start_phase upload-assets
for file in "${assets[@]}"; do
  # The write token goes directly to curl's stdin. The endpoint is fixed to the
  # public Downloads repository and the verified draft ID. Forbid redirects.
  response="$(printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN" |
    curl -q --config - --silent --show-error --max-time 180 --write-out '\n%{http_code}' \
      --header 'Accept: application/vnd.github+json' --header 'Content-Type: application/octet-stream' \
      --data-binary "@$file" "https://uploads.github.com/$release_endpoint/$release_id/assets?name=$file" 2>/dev/null)" || fail "upload transport failed asset=$file"
  status="${response##*$'\n'}"
  [[ "$status" =~ ^[0-9]{3}$ ]] || fail "invalid upload HTTP status asset=$file"
  [[ "$status" == 201 ]] || fail "upload rejected asset=$file HTTP $status"
  response="${response%$'\n'*}"
  id="$(jq -er '.id | numbers' <<< "$response" 2>/dev/null)" || fail "missing numeric upload ID asset=$file"
  [[ "$id" =~ ^[0-9]+$ ]] || fail "invalid upload ID asset=$file"
  uploaded+=("$file:$id")
done

start_phase verify-digests
record="$(github_api "$release_endpoint/$release_id")"
is_expected_draft <<< "$record" || fail "draft identity or visibility changed"
jq -e --argjson count "${#assets[@]}" '.assets | type == "array" and length == $count' <<< "$record" >/dev/null 2>&1 || fail "unexpected draft asset count"
for asset in "${uploaded[@]}"; do
  file="${asset%:*}"
  id="${asset##*:}"
  digest="sha256:$(hash_file "$file")" || fail "cannot calculate SHA-256 asset=$file"
  jq -e --arg id "$id" --arg file "$file" --arg digest "$digest" \
    'any(.assets[]; (.id | tostring) == $id and .name == $file and .digest == $digest and .state == "uploaded")' \
    <<< "$record" >/dev/null 2>&1 || fail "draft asset digest or upload state mismatch asset=$file"
done
start_phase anonymous-assets
for asset in "${uploaded[@]}"; do
  check_anonymous_denial "$asset_api/${asset##*:}" "$json_media"
  check_anonymous_denial "$asset_api/${asset##*:}" "$binary_media"
done
printf 'VIP distribution: verified unpublished draft id=%s, SHA-256 digests and anonymous access denial.\n' "$release_id"

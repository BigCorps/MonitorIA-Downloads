#!/usr/bin/env bash
set -euo pipefail
umask 077
destination=${1:?Provide an empty destination}
repo=BigCorps/MonitorIA-Downloads
run=46102279685
artifact=15245519083
source_sha=ddfbe813e9f876c7e3ede49e1ac29993a35dd803
qa_sha=56844a2c683de8b5786db40fcc17d8b8129ed04f
archive_sha=32570c741cdf15bfd1bce5937bd799eabbcf630548bd93e7f364bb54cdc8e2b5
candidate_sha=263d80c052ded7809fad1b8fe0044706d1e12728cb9594f92e81337aae9af705
exe=MonitorIA-Protect-1.0.0-Setup.exe
test -n "${PROTECT_QA_ARTIFACT_KEY:-}"
gh api "repos/$repo/actions/runs/$run" | jq -e --arg sha "$qa_sha" '
 .conclusion == "success" and .head_sha == $sha and .head_branch == "ci/protect-windows-100"
 and .path == ".github/workflows/qualify-protect-windows-100.yml"' >/dev/null
gh api "repos/$repo/actions/artifacts/$artifact" | jq -e --arg digest "sha256:$archive_sha" --argjson run "$run" '
 .name == "protect-1.0.0-qualified" and .expired == false and .digest == $digest and .workflow_run.id == $run' >/dev/null
cd "$destination"
gh api "repos/$repo/actions/artifacts/$artifact/zip" > qualified.zip
printf '%s  qualified.zip\n' "$archive_sha" | sha256sum --check
unzip -p qualified.zip protect-1.0.0-qualified.tar.gz.enc |
 openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:PROTECT_QA_ARTIFACT_KEY |
 tar -xzf - -- "$exe" candidate.sha256 source.sha endpoint.txt
test "$(cat source.sha)" = "$source_sha"
test "$(cat endpoint.txt)" = 'https://monitoria.cam/api/protect/installation'
test "$(cut -d' ' -f1 candidate.sha256)" = "$candidate_sha"
printf '%s  %s\n' "$candidate_sha" "$exe" | sha256sum --check
echo 'Qualification run, encrypted artifact, commercial endpoint and installer SHA-256 verified.'

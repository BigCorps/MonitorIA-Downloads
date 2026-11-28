#!/usr/bin/env bash
set -euo pipefail
umask 077
destination=${1:?Provide an empty destination}
repo=BigCorps/MonitorIA-Downloads
run=46103853302
artifact=15245609742
source_sha=32873e70962aca5aa7b1f4a74e96b771990c9fd6
qa_sha=12108834b8ef283192e32635ec1840f14d0cbf7b
archive_sha=65ec2a8b02aafc674e79ce668f4952594b4d5ab9d319a76f13390141ac8a2c63
candidate_sha=eb77257378fb089232dbafd2be8f20083aae6e5198bc7a6bdd778aa3ea7d1870
exe=MonitorIA-Protect-1.0.0-Setup.exe
test -n "${PROTECT_QA_ARTIFACT_KEY:-}"
gh api "repos/$repo/actions/runs/$run" | jq -e --arg sha "$qa_sha" '
 .conclusion == "success" and .head_sha == $sha and .head_branch == "ci/protect-100-upgrade"
 and .path == ".github/workflows/qualify-protect-windows-100.yml"' >/dev/null
gh api "repos/$repo/actions/artifacts/$artifact" | jq -e --arg digest "sha256:$archive_sha" --argjson run "$run" '
 .name == "protect-1.0.0-qualified" and .expired == false and .digest == $digest and .workflow_run.id == $run' >/dev/null
cd "$destination"
gh api "repos/$repo/actions/artifacts/$artifact/zip" > qualified.zip
printf '%s  qualified.zip\n' "$archive_sha" | sha256sum --check
unzip -p qualified.zip protect-1.0.0-qualified.tar.gz.enc |
 openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:PROTECT_QA_ARTIFACT_KEY |
 tar -xzf - -- "$exe" candidate.sha256 source.sha endpoint.txt MonitorIA-Protect-0.4.4-Fixture.exe pilot.sha256
test "$(cat source.sha)" = "$source_sha"
test "$(cat endpoint.txt)" = 'https://monitoria.cam/api/protect/installation'
test "$(cut -d' ' -f1 candidate.sha256)" = "$candidate_sha"
printf '%s  %s\n' "$candidate_sha" "$exe" | sha256sum --check
sha256sum --check pilot.sha256
echo 'Qualification run, encrypted artifact, commercial endpoint and installer SHA-256 verified.'

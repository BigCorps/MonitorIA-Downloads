import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from zipfile import ZipFile


SCRIPT = Path(__file__).with_name("windows-vip-mosaic-draft.sh").resolve()
BUNDLE = "MonitorIA-VIP-Mosaico-1.0.0-beta.1-Homologacao-NAO-ASSINADO.zip"
PREVIEW = "MonitorIA-VIP-CapturePreview.exe"
FILES = [PREVIEW, "MonitorIA-VIP-Simulador.html", "LEIA-ME.txt"]
ASSETS = [BUNDLE, "RELEASE-MANIFEST.json", "SHA256SUMS.txt"]
FAKE_GH = """#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
state = pathlib.Path(os.environ["DRAFT_TEST_STATE"])
endpoint = "repos/BigCorps/MonitorIA-Downloads/releases"
if args[:4] == ["api", "--method", "POST", endpoint]:
    tag = "vip-mosaic-windows-unsigned-v1.0.0-beta.1-" + os.environ["MONITORIA_SOURCE_SHA"][:12]
    assert "tag_name=" + tag in args
    assert "target_commitish=" + os.environ["GITHUB_SHA"] in args
    assert "draft=true" in args and "prerelease=true" in args
    record = {"id": 1, "tag_name": tag, "draft": True, "prerelease": True, "published_at": None,
              "target_commitish": os.environ["GITHUB_SHA"], "assets": []}
    if os.environ.get("DRAFT_TEST_NOT_EMPTY"):
        record["assets"].append({"id": 99, "name": "third-party.txt"})
    state.write_text(json.dumps(record))
    print(json.dumps(record))
elif args[:2] == ["api", endpoint + "/1"]:
    record = json.loads(state.read_text())
    if record["assets"] and os.environ.get("DRAFT_TEST_BAD_DIGEST"):
        record["assets"][0]["digest"] = "sha256:fake"
    print(json.dumps(record))
elif args[:3] == ["api", "--method", "DELETE"]:
    asset_id = int(args[3].removeprefix(endpoint + "/assets/"))
    record = json.loads(state.read_text())
    assert record["draft"] is True and record["id"] == 1
    assert asset_id in [asset["id"] for asset in record["assets"]]
    record["assets"] = [asset for asset in record["assets"] if asset["id"] != asset_id]
    state.write_text(json.dumps(record))
elif args[0] == "api" and "/git/matching-refs/tags/" in args[1]:
    pass
elif args[:4] == ["api", "--method", "GET", endpoint]:
    assert args[-1].endswith("| .id")
    if state.exists():
        print(json.loads(state.read_text())["id"])
else:
    sys.exit("unexpected mock call")
"""
FAKE_CURL = """#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
from urllib.parse import parse_qs, urlsplit
args = sys.argv[1:]
assert args[0] == "-q"
assert "Authorization" not in " ".join(args)
state = pathlib.Path(os.environ["DRAFT_TEST_STATE"])
anonymous_check = state.with_name("mock-anonymous-check")
record = json.loads(state.read_text())
endpoint = "/repos/BigCorps/MonitorIA-Downloads/releases"
url = urlsplit(args[-1])
if url.netloc == "uploads.github.com":
    assert url.path == endpoint + "/1/assets"
    assert anonymous_check.exists()
    assert record["draft"] is True and record["id"] == 1
    assert args[1:3] == ["--config", "-"] and "--location" not in args
    assert os.environ["GH_TOKEN"] in sys.stdin.read()
    name = parse_qs(url.query)["name"][0]
    names = json.loads(os.environ["DRAFT_TEST_ASSETS"])
    assert args[args.index("--data-binary") + 1] == "@" + name
    assert name == names[len(record["assets"])]
    if len(record["assets"]) and os.environ.get("DRAFT_TEST_PARTIAL_UPLOAD"):
        record["assets"].append({"id": 99, "name": "third-party.txt"})
        state.write_text(json.dumps(record))
        sys.exit(22)
    item = {"id": 3 + len(record["assets"]), "name": name, "state": "uploaded",
            "digest": "sha256:" + hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()}
    record["assets"].append(item)
    state.write_text(json.dumps(record))
    print(json.dumps(item))
elif url.netloc == "api.github.com" and url.path == endpoint + "/1":
    assert "--config" not in args
    assert not record["assets"]
    status = os.environ.get("DRAFT_TEST_ANONYMOUS_RELEASE_STATUS", "404")
    if status == "404":
        anonymous_check.touch()
    print(status, end="")
else:
    assert "--config" not in args
    assert url.netloc == "api.github.com" and url.path.startswith(endpoint + "/assets/")
    print(os.environ.get("DRAFT_TEST_ANONYMOUS_ASSET_STATUS", "404"), end="")
"""


class DraftTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.private = self.root / "private-src"
        self.release = self.root / "release-vip"
        self.private.mkdir()
        self.release.mkdir()
        self.public_sha = self.init_git(self.root, "workflow")
        self.private_sha = self.init_git(self.private, "private")
        (self.release / "must-not-upload.txt").write_text("fixture")
        hashes = {}
        with ZipFile(self.release / BUNDLE, "w") as archive:
            for name in FILES:
                content = f"fixture:{name}".encode()
                archive.writestr(name, content)
                hashes[name] = hashlib.sha256(content).hexdigest()
        self.verification = {
            "files": hashes,
            "authenticode": {"file": PREVIEW, "status": "NotSigned", "timestampVerified": False},
        }
        (self.release / "WINDOWS-VERIFICATION.json").write_text(json.dumps(self.verification))
        for name, source in [("gh", FAKE_GH), ("curl", FAKE_CURL)]:
            mock = self.root / name
            mock.write_text(source)
            mock.chmod(0o755)
        self.state = self.root / "mock-release.json"
        self.env = os.environ | {
            "PATH": f"{self.root}{os.pathsep}{os.environ['PATH']}",
            "GITHUB_REPOSITORY": "BigCorps/MonitorIA-Downloads", "GITHUB_REF": "refs/heads/main",
            "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_SHA": self.public_sha,
            "MONITORIA_SOURCE_SHA": self.private_sha,
            "DRAFT_TEST_STATE": str(self.state), "DRAFT_TEST_ASSETS": json.dumps(ASSETS),
            "GH_TOKEN": "ghs_disposable_fixture",
        }

    def command(self, *args, cwd=None, binary=False):
        return subprocess.run(args, cwd=cwd or self.root, capture_output=True,
                              text=not binary, check=True).stdout

    def init_git(self, directory, message):
        self.command("git", "init", "-q", cwd=directory)
        self.command("git", "-c", "user.name=Draft Tests", "-c", "user.email=test@example.invalid",
                     "-c", "commit.gpgSign=false", "commit", "--allow-empty", "-qm", message, cwd=directory)
        return self.command("git", "rev-parse", "HEAD", cwd=directory).strip()

    def stage(self, mode="stage", **overrides):
        return subprocess.run(["bash", str(SCRIPT), mode], cwd=self.root, env=self.env | overrides,
                              capture_output=True, text=True)

    def test_only_expected_unsigned_assets_and_distinct_commits(self):
        result = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.release / "RELEASE-MANIFEST.json").read_text())
        self.assertEqual(manifest["sourceCommit"], self.private_sha)
        self.assertEqual(manifest["workflowCommit"], self.public_sha)
        self.assertEqual(manifest["artifactType"], "unsigned-internal-homologation-preview")
        self.assertEqual(manifest["authenticode"], self.verification["authenticode"])
        self.assertIs(manifest["manifestSigned"], False)
        self.command("sha256sum", "--check", "SHA256SUMS.txt", cwd=self.release)
        self.assertNotEqual(self.stage("check").returncode, 0)

    def test_mismatch_or_untrusted_ref_never_creates_draft(self):
        self.assertNotEqual(self.stage(GITHUB_EVENT_NAME="pull_request").returncode, 0)
        self.assertNotEqual(self.stage(GITHUB_REF="refs/heads/topic").returncode, 0)
        self.assertNotEqual(self.stage(MONITORIA_SOURCE_SHA="0" * 40).returncode, 0)
        self.assertFalse(self.state.exists())

    def test_invalid_windows_verification_never_creates_draft(self):
        self.verification["authenticode"]["status"] = "Valid"
        (self.release / "WINDOWS-VERIFICATION.json").write_text(json.dumps(self.verification))
        self.assertNotEqual(self.stage().returncode, 0)
        self.assertFalse(self.state.exists())

    def test_correction_branch_requires_owner_dispatch(self):
        branch = "refs/heads/codex/vip-mosaic-unsigned-homologation"
        self.assertNotEqual(self.stage(GITHUB_REF=branch, GITHUB_ACTOR="another-user").returncode, 0)
        self.assertFalse(self.state.exists())
        self.assertNotEqual(self.stage(GITHUB_REF=branch, GITHUB_ACTOR="BigCorps", GITHUB_TRIGGERING_ACTOR="another-user").returncode, 0)
        result = self.stage(GITHUB_REF=branch, GITHUB_ACTOR="BigCorps", GITHUB_TRIGGERING_ACTOR="BigCorps")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_initial_anonymous_access_stops_before_any_upload(self):
        result = self.stage(DRAFT_TEST_ANONYMOUS_RELEASE_STATUS="200")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Anonymous GitHub access", result.stderr)
        self.assertEqual(json.loads(self.state.read_text())["assets"], [])

    def test_existing_draft_asset_is_rejected_without_removal(self):
        self.assertNotEqual(self.stage(DRAFT_TEST_NOT_EMPTY="1").returncode, 0)
        self.assertEqual(json.loads(self.state.read_text())["assets"], [{"id": 99, "name": "third-party.txt"}])

    def test_unexpected_anonymous_asset_access_removes_staged_assets(self):
        result = self.stage(DRAFT_TEST_ANONYMOUS_ASSET_STATUS="302")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Anonymous GitHub access", result.stderr)
        self.assert_empty_draft()

    def test_corrupted_upload_digest_removes_staged_assets(self):
        self.assertNotEqual(self.stage(DRAFT_TEST_BAD_DIGEST="1").returncode, 0)
        self.assert_empty_draft()

    def test_partial_upload_removes_only_our_asset_in_the_same_draft(self):
        self.assertNotEqual(self.stage(DRAFT_TEST_PARTIAL_UPLOAD="1").returncode, 0)
        self.assertEqual(json.loads(self.state.read_text())["assets"], [{"id": 99, "name": "third-party.txt"}])

    def assert_empty_draft(self):
        record = json.loads(self.state.read_text())
        self.assertTrue(record["draft"])
        self.assertEqual(record["assets"], [])


if __name__ == "__main__":
    unittest.main()

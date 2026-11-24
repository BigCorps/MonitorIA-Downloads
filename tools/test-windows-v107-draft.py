import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("windows-v107-draft.sh").resolve()
ASSETS = [
    "MonitorIA-Setup.exe", "RELEASE-MANIFEST.json", "SHA256SUMS.txt",
    "SHA256SUMS.sig", "RELEASE-PUBLIC-KEY.pem",
]
FAKE_GH = """#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
args = sys.argv[1:]
state = pathlib.Path(os.environ["DRAFT_TEST_STATE"])
if args[:2] == ["release", "create"]:
    assert args[3:8] == json.loads(os.environ["DRAFT_TEST_ASSETS"])
    assert args[args.index("--target") + 1] == os.environ["GITHUB_SHA"]
    assert "--draft" in args and "--prerelease" in args
    assert args[2] == "windows-247-v1.0.7-rc-" + os.environ["MONITORIA_SOURCE_SHA"][:12]
    state.write_text(json.dumps({
        "id": 23, "draft": True, "prerelease": True, "published_at": None,
        "target_commitish": os.environ["GITHUB_SHA"],
        "assets": [
            {"name": name, "state": "uploaded", "digest": "sha256:" +
                hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()}
            for name in args[3:8]
        ],
    }))
elif args[0] == "api" and "/git/matching-refs/tags/" in args[1]:
    pass
elif args[:3] == ["api", "--method", "GET"]:
    if state.exists():
        data = json.loads(state.read_text())
        if args[-1].endswith("| .id"):
            print(data["id"])
        else:
            if os.environ.get("DRAFT_TEST_CORRUPT"):
                data["assets"][0]["digest"] = "sha256:0000"
            print(json.dumps(data))
else:
    sys.exit("Unexpected GitHub call")
"""


class DraftTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.private = self.root / "private-src"
        self.private.mkdir()
        self.release = self.private / "release-windows"
        self.release.mkdir()
        self.public_sha = self.init_git(self.root, "public workflow")
        self.private_sha = self.init_git(self.private, "private source")
        (self.release / ASSETS[0]).write_bytes(b"disposable draft test payload")
        (self.release / "other.exe").write_bytes(b"must never be uploaded")
        gh = self.root / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        key = self.command("openssl", "genpkey", "-algorithm", "ED25519", binary=True)
        der = subprocess.run(
            ["openssl", "pkey", "-pubout", "-outform", "DER"],
            input=key, capture_output=True, check=True,
        ).stdout
        self.state = self.root / "mock-release.json"
        self.env = dict(
            os.environ,
            PATH=f"{self.root}{os.pathsep}{os.environ['PATH']}",
            GITHUB_REPOSITORY="BigCorps/MonitorIA-Downloads", GITHUB_REF="refs/heads/main",
            GITHUB_EVENT_NAME="workflow_dispatch", GITHUB_SHA=self.public_sha,
            MONITORIA_SOURCE_SHA=self.private_sha,
            MONITORIA_AGENT_RELEASE_SIGNING_KEY_B64=base64.b64encode(key).decode(),
            MONITORIA_AGENT_RELEASE_KEY_SHA256=hashlib.sha256(der).hexdigest(),
            DRAFT_TEST_STATE=str(self.state), DRAFT_TEST_ASSETS=json.dumps(ASSETS),
        )

    def command(self, *args, cwd=None, binary=False):
        return subprocess.run(
            args, cwd=cwd or self.root, capture_output=True, text=not binary, check=True
        ).stdout

    def init_git(self, directory, message):
        self.command("git", "init", "-q", cwd=directory)
        self.command(
            "git", "-c", "user.name=Draft Tests", "-c", "user.email=test@example.invalid",
            "-c", "commit.gpgSign=false", "commit", "--allow-empty", "-qm", message, cwd=directory,
        )
        return self.command("git", "rev-parse", "HEAD", cwd=directory).strip()

    def run_script(self, mode, **overrides):
        return subprocess.run(
            ["bash", str(SCRIPT), mode, "private-src/release-windows"],
            cwd=self.root, env=self.env | overrides, capture_output=True, text=True,
        )

    def test_draft_files_and_source_identity(self):
        result = self.run_script("stage")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.private_sha, self.public_sha)
        manifest = json.loads((self.release / "RELEASE-MANIFEST.json").read_text())
        self.assertEqual(manifest["sourceCommit"], self.private_sha)
        self.assertEqual(manifest["workflowCommit"], self.public_sha)
        self.assertEqual(manifest["physicalValidation"], "pending")
        self.command("sha256sum", "--check", "SHA256SUMS.txt", cwd=self.release)
        self.command(
            "openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey",
            "RELEASE-PUBLIC-KEY.pem", "-in", "SHA256SUMS.txt", "-sigfile", "SHA256SUMS.sig",
            cwd=self.release,
        )
        self.assertNotEqual(self.run_script("check").returncode, 0)

    def test_gate_rejects_wrong_fingerprint_and_source_before_creating_draft(self):
        bad_key = self.run_script("stage", MONITORIA_AGENT_RELEASE_KEY_SHA256="0" * 64)
        self.assertNotEqual(bad_key.returncode, 0)
        self.assertIn("fingerprint mismatch", bad_key.stderr)
        self.assertNotEqual(self.run_script("stage", MONITORIA_SOURCE_SHA="0" * 40).returncode, 0)
        self.assertNotEqual(self.run_script("stage", GITHUB_REF="refs/heads/topic").returncode, 0)
        self.assertFalse(self.state.exists())

    def test_rejects_corrupted_upload_digest(self):
        self.assertNotEqual(self.run_script("stage", DRAFT_TEST_CORRUPT="1").returncode, 0)
        self.assertTrue(json.loads(self.state.read_text())["draft"])


if __name__ == "__main__":
    unittest.main()

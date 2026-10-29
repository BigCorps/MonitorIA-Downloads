import unittest
from pathlib import Path
import yaml

class PdvWorkflow(unittest.TestCase):
    def setUp(self):
        self.text = Path('.github/workflows/build-monitoria-pdv-diagnostic-pilot.yml').read_text()
        self.workflow = yaml.load(self.text, Loader=yaml.BaseLoader)
    def test_private_pin_and_checkout(self):
        self.assertEqual(self.workflow['env']['MONITORIA_SOURCE_SHA'], 'ae91c451f1b7f8de5903b0aab08bb3261986a188')
        steps = self.workflow['jobs']['windows-pilot']['steps']
        checkout = next(s for s in steps if s.get('uses','').startswith('actions/checkout'))
        self.assertEqual(checkout['with']['repository'], 'BigCorps/MonitorIA')
        self.assertEqual(checkout['with']['ref'], '${{ env.MONITORIA_SOURCE_SHA }}')
        self.assertEqual(checkout['with']['persist-credentials'], 'false')
    def test_no_source_cache_or_artifact(self):
        self.assertNotIn('upload-artifact', self.text)
        self.assertNotIn('cache: npm', self.text)
        self.assertNotIn('actions/cache', self.text)
        self.assertNotIn('pull_request:', self.text)
        self.assertNotIn('  push:', self.text)
    def test_draft_only_and_token_roles(self):
        self.assertIn('--repo BigCorps/MonitorIA-Downloads --target $env:GITHUB_SHA --draft --prerelease', self.text)
        self.assertIn('sourceCommit = $env:MONITORIA_SOURCE_SHA', self.text)
        self.assertIn('$short = $env:MONITORIA_SOURCE_SHA.Substring(0,12)', self.text)
        self.assertIn('productionReconciliationReady = $false', self.text)
        steps=self.workflow['jobs']['windows-pilot']['steps']
        baseline=next(s for s in steps if s.get('name','').startswith('Fetch and authenticate'))
        release=next(s for s in steps if s.get('name','').startswith('Preserve only'))
        self.assertEqual(baseline['env']['GH_TOKEN'], '${{ secrets.MONITORIA_PRIVATE_SOURCE_TOKEN }}')
        self.assertEqual(release['env']['GH_TOKEN'], '${{ github.token }}')
    def test_signature_upgrade_and_identity_gates(self):
        for marker in ['TimeStamperCertificate', 'SignerCertificate.Subject', 'unins000.exe', 'preserve-agent-local-data', 'serviceVariantConfirmed', 'Run PDV regressions', 'pdv-pilot-info', 'roundtrip mismatch']:
            self.assertIn(marker, self.text)
    def test_manual_branch_shim(self):
        shim=yaml.load(Path('.github/workflows/build-monitoria-v106-windows-pilot.yml').read_text(), Loader=yaml.BaseLoader)
        self.assertEqual(list(shim['on']), ['workflow_dispatch'])
        job=shim['jobs']['diagnostic-pilot']
        self.assertEqual(job['uses'], './.github/workflows/build-monitoria-pdv-diagnostic-pilot.yml')
        self.assertIn('refs/heads/build/pdv-diagnostic-pilot', job['if'])
        self.assertEqual(job['secrets'], 'inherit')

if __name__ == '__main__': unittest.main()

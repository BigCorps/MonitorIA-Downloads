import urllib.error
import base64,contextlib,importlib.util,io,json,os,pathlib,tempfile,unittest
from unittest.mock import patch
s=importlib.util.spec_from_file_location('provision',pathlib.Path(__file__).with_name('android-signing-provision.py'));p=importlib.util.module_from_spec(s);s.loader.exec_module(p)
class Provision(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.env=patch.dict(os.environ,{'GITHUB_REPOSITORY':'BigCorps/MonitorIA-Downloads','GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_REF':'refs/heads/main','GITHUB_STEP_SUMMARY':self.tmp.name+'/summary','MODE':'public-keys'},clear=True);self.env.start();self.addCleanup(self.env.stop)
  self.keys={r:{'key_id':'synthetic-key-id','key':base64.b64encode(b'x'*32).decode()} for r in p.REPOS}
  self.payload={'certificateSha256':p.FINGERPRINT,'repositories':{r:{'key_id':'synthetic-key-id','secrets':{n:base64.b64encode(b'x'*96).decode() for n in p.NAMES}} for r in p.REPOS}}
 def install(self):os.environ['MODE']='install';os.environ['ENCRYPTED_PAYLOAD']=json.dumps(self.payload)
 def test_valid_ciphertexts(self):p.validate(self.payload,self.keys)
 def test_plaintext_rejected(self):
  self.payload['repositories']['BigCorps/MonitorIA']['secrets']['MONITORIA_ANDROID_KEY_ALIAS']='not plaintext'
  with self.assertRaises(Exception):p.validate(self.payload,self.keys)
 def test_extra_secret_rejected(self):
  self.payload['repositories']['BigCorps/MonitorIA']['secrets']['GH_TOKEN']='x'
  with self.assertRaises(p.Stop):p.validate(self.payload,self.keys)
 def test_wrong_key_rejected(self):
  self.payload['repositories']['BigCorps/MonitorIA']['key_id']='stale'
  with self.assertRaises(p.Stop):p.validate(self.payload,self.keys)
 def test_signing_rotation_rejected(self):
  self.payload['certificateSha256']='f'*64
  with self.assertRaises(p.Stop):p.validate(self.payload,self.keys)
 def test_other_repo_rejected(self):
  self.payload['repositories']['Other/Repo']=self.payload['repositories']['BigCorps/MonitorIA']
  with self.assertRaises(p.Stop):p.validate(self.payload,self.keys)
 def test_non_main_never_contacts_api(self):
  os.environ['GITHUB_REF']='refs/heads/unreviewed'
  with patch.object(p,'api') as api,self.assertRaises(p.Stop):p.main()
  api.assert_not_called()
 def test_public_keys_no_write_or_secret_output(self):
  with patch.object(p,'contexts',return_value=self.keys),patch.object(p,'api') as api,contextlib.redirect_stdout(io.StringIO()) as out:p.main()
  api.assert_not_called();self.assertIn('synthetic-key-id',out.getvalue());self.assertNotIn('storePassword',out.getvalue())
 def test_conflict_in_second_repo_stops_all_writes(self):
  self.install()
  with patch.object(p,'contexts',return_value=self.keys),patch.object(p,'api',side_effect=[None,{'value':'f'*64}]) as api,self.assertRaises(p.Stop):p.main()
  self.assertTrue(all(len(c.args)<2 for c in api.call_args_list))
 def test_stale_key_stops_before_writes(self):
  self.install();self.keys['BigCorps/MonitorIA']['key_id']='new'
  with patch.object(p,'contexts',return_value=self.keys),patch.object(p,'api') as api,self.assertRaises(p.Stop):p.main()
  api.assert_not_called()
 def test_install_only_expected_names_and_no_payload_output(self):
  self.install()
  with patch.object(p,'contexts',return_value=self.keys),patch.object(p,'api',return_value=None) as api,contextlib.redirect_stdout(io.StringIO()) as out:p.main()
  puts=[c for c in api.call_args_list if len(c.args)>1 and c.args[1]=='PUT'];self.assertEqual(len(puts),8)
  self.assertTrue(all(c.args[0].startswith('repos/BigCorps/') for c in api.call_args_list if '/variables' in c.args[0]))
  self.assertTrue(all(set(c.args[2])=={'key_id','encrypted_value'} for c in puts));self.assertNotIn('eHh4',out.getvalue())
 def test_existing_protection_not_modified(self):
  def api(path,*args,**kwargs):
   if '/environments/' in path and '/secrets/' not in path:return {'protection_rules':[{'type':'required_reviewers'}]}
   if '/secrets/public-key' in path:return self.keys['BigCorps/MonitorIA']
   repo=path.removeprefix('repos/');return {'id':p.REPOS[repo],'full_name':repo,'private':repo=='BigCorps/MonitorIA'}
  with patch.object(p,'api',side_effect=api) as calls:self.assertEqual(p.contexts(),self.keys)
  self.assertTrue(all(len(c.args)==1 for c in calls.call_args_list))
 def test_http_403_identifies_endpoint_and_permission_without_body(self):
  path='repos/BigCorps/MonitorIA/environments/android-private-signing'
  error=urllib.error.HTTPError('https://api.github.com/'+path,403,'Forbidden',{'X-Accepted-GitHub-Permissions':'actions=read'},io.BytesIO(b'{"message":"Resource not accessible by personal access token","private":"NEVER_PRINT"}'))
  text=p.failure_details(error,'GET',path)
  self.assertIn('GET /'+path,text);self.assertIn('actions=read',text);self.assertIn('resource not accessible',text);self.assertNotIn('NEVER_PRINT',text)
 def test_plan_restriction_not_misclassified_as_missing_permission(self):
  error=urllib.error.HTTPError('synthetic',403,'Forbidden',{},io.BytesIO(b'{"message":"Upgrade to GitHub Pro to use this feature"}'))
  self.assertIn('plan upgrade required',p.failure_details(error,'GET','repos/BigCorps/MonitorIA/environments/android-private-signing'))
 def test_arbitrary_headers_and_malformed_body_never_logged(self):
  error=urllib.error.HTTPError('synthetic',403,'Forbidden',{'X-Accepted-GitHub-Permissions':'NEVER_PRINT\nSECRET'},io.BytesIO(b'PRIVATE_HTML'))
  text=p.failure_details(error,'GET','repos/BigCorps/MonitorIA');self.assertNotIn('NEVER_PRINT',text);self.assertNotIn('PRIVATE_HTML',text)
 def test_real_http_wrapper_preserves_safe_failure_diagnostic(self):
  os.environ['PROVISIONING_TOKEN']='SYNTHETIC_PRIVATE_TOKEN'
  error=urllib.error.HTTPError('synthetic',403,'Forbidden',{'X-Accepted-GitHub-Permissions':'environments=read'},io.BytesIO(b'{}'))
  with patch.object(p.urllib.request,'build_opener') as opener:
   opener.return_value.open.side_effect=error
   with self.assertRaises(p.Stop) as caught:p.api('repositories/1315024254/environments/android-private-signing/secrets/public-key')
  self.assertIn('environments=read',str(caught.exception));self.assertNotIn('SYNTHETIC_PRIVATE_TOKEN',str(caught.exception))
if __name__=='__main__':unittest.main()

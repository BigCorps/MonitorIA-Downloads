"""One-shot GitHub-encrypted secret provisioning; no APK/source/key generation."""
import base64,json,os,re,sys,urllib.request,urllib.error
REPOS={'BigCorps/MonitorIA':1315024254,'BigCorps/MonitorIA-Downloads':1428623271}
ENV='android-private-signing'
NAMES={'MONITORIA_ANDROID_SIGNING_STORE_B64','MONITORIA_ANDROID_STORE_PASSWORD','MONITORIA_ANDROID_KEY_ALIAS','MONITORIA_ANDROID_KEY_PASSWORD'}
VARIABLE='MONITORIA_ANDROID_CERT_SHA256'
FINGERPRINT='5f7be1cde41fb5b5098286723ffe57e15942783a213d62eb2df2c9f6300ac354'
class Stop(Exception):pass
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None

def api(path,method='GET',body=None,missing=False):
 token=os.environ.get('PROVISIONING_TOKEN','')
 if not token:raise Stop('ANDROID_PROVISIONING_TOKEN missing in Downloads repository secrets')
 req=urllib.request.Request('https://api.github.com/'+path,method=method,data=None if body is None else json.dumps(body).encode(),headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','Content-Type':'application/json','X-GitHub-Api-Version':'2022-11-28'})
 try:
  with urllib.request.build_opener(NoRedirect).open(req,timeout=20) as r:
   raw=r.read(128000);return json.loads(raw) if raw else {}
 except urllib.error.HTTPError as e:
  if e.code==404 and missing:return None
  raise Stop('GitHub API HTTP '+str(e.code)+'; no response body or credential logged') from None
 except Exception:raise Stop('GitHub API unavailable; no automatic retry') from None

def contexts():
 result={}
 for repo,rid in REPOS.items():
  info=api('repos/'+repo)
  if info.get('id')!=rid or info.get('full_name')!=repo:raise Stop('Repository identity mismatch')
  if info.get('private') is not (repo=='BigCorps/MonitorIA'):raise Stop('Repository visibility mismatch')
  path='repos/'+repo+'/environments/'+ENV
  if api(path,missing=True) is None:
   raise Stop('Create environment android-private-signing in both repositories first; existing protection rules are never changed here')
  key=api(f'repositories/{rid}/environments/{ENV}/secrets/public-key')
  if not isinstance(key.get('key_id'),str) or len(base64.b64decode(key.get('key',''),validate=True))!=32:raise Stop('Invalid GitHub encryption public key')
  result[repo]={'key_id':key['key_id'],'key':key['key']}
 return result

def validate(payload,keys):
 if type(payload)!=dict or set(payload)!={'certificateSha256','repositories'} or payload['certificateSha256']!=FINGERPRINT:raise Stop('Signing fingerprint mismatch')
 repos=payload['repositories']
 if type(repos)!=dict or set(repos)!=set(REPOS):raise Stop('Repository allowlist mismatch')
 for repo in REPOS:
  item=repos[repo]
  if type(item)!=dict or set(item)!={'key_id','secrets'} or item['key_id']!=keys[repo]['key_id'] or type(item['secrets'])!=dict or set(item['secrets'])!=NAMES:raise Stop('Encrypted secret allowlist/key mismatch')
  for value in item['secrets'].values():
   if not isinstance(value,str) or not 49<=len(base64.b64decode(value,validate=True))<=48000:raise Stop('Invalid sealed ciphertext; plaintext input is forbidden')

def main():
 if os.environ.get('GITHUB_REPOSITORY')!='BigCorps/MonitorIA-Downloads' or os.environ.get('GITHUB_EVENT_NAME')!='workflow_dispatch' or os.environ.get('GITHUB_REF')!='refs/heads/main':raise Stop('Manual Downloads main execution only')
 mode=os.environ.get('MODE','');raw=os.environ.get('ENCRYPTED_PAYLOAD','')
 if mode not in ('public-keys','install') or len(raw)>64000:raise Stop('Invalid mode/input size')
 keys=contexts()
 if mode=='public-keys':
  if raw.strip():raise Stop('No payload accepted in public-keys mode')
  text='Public GitHub encryption keys only (not signing/private keys):\n```json\n'+json.dumps(keys,indent=2)+'\n```\n'
 else:
  payload=json.loads(raw);validate(payload,keys)
  # Preflight ALL keys and variable conflicts before any write. GitHub offers no
  # multi-secret transaction: a failed partial install is safe to repeat verbatim.
  for repo,rid in REPOS.items():
   path=f'repos/{repo}/environments/{ENV}/variables/{VARIABLE}'
   old=api(path,missing=True)
   if old and old.get('value','').strip().lower()!=FINGERPRINT:raise Stop('Existing certificate differs; no signing identity replacement allowed')
  for repo,rid in REPOS.items():
   base=f'repositories/{rid}/environments/{ENV}'
   for name,value in sorted(payload['repositories'][repo]['secrets'].items()):
    api(base+'/secrets/'+name,'PUT',{'key_id':keys[repo]['key_id'],'encrypted_value':value})
   variables=f'repos/{repo}/environments/{ENV}/variables'
   path=variables+'/'+VARIABLE;old=api(path,missing=True)
   api(path if old else variables,'PATCH' if old else 'POST',{'name':VARIABLE,'value':FINGERPRINT})
  text='Installed the four encrypted Android signing secrets and expected certificate variable in both environments. No key generated, source token copied, build, merge or release performed.\n'
 print(text)
 with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:f.write(text)

if __name__=='__main__':
 try:main()
 except Stop as e:print(str(e),file=sys.stderr);sys.exit(1)
 except Exception:print('Provisioning stopped; private input and diagnostics suppressed',file=sys.stderr);sys.exit(1)

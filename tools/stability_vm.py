import json,time,urllib.request,subprocess,threading,pathlib
import argparse
parser=argparse.ArgumentParser(description="Run controlled checks on a disposable local OpenWrt VM only")
parser.add_argument('--ssh-key',required=True)
parser.add_argument('--ssh-port',default='29922')
parser.add_argument('--api-port',default='29925')
parser.add_argument('--output',required=True)
parser.add_argument('--expect-old',action='store_true')
parser.add_argument('--transparent-type',choices=['tproxy','redirect'],default='tproxy')
args=parser.parse_args()
ROOT=pathlib.Path(args.output);ROOT.mkdir(parents=True,exist_ok=True)
op=urllib.request.build_opener(urllib.request.ProxyHandler({})); token=''
ssh=['ssh','-F','NUL','-p',args.ssh_port,'-i',args.ssh_key,'-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=NUL','root@127.0.0.1']
def remote(cmd): return subprocess.check_output(ssh+[cmd],stderr=subprocess.DEVNULL,text=True).strip()
def api(method,path,data=None):
 req=urllib.request.Request(f'http://127.0.0.1:{args.api_port}/api/'+path,method=method,data=json.dumps(data).encode() if data is not None else None,headers={'Content-Type':'application/json','Authorization':token})
 with op.open(req,timeout=60) as r: out=json.load(r)
 if out.get('code')!='SUCCESS': raise RuntimeError(out)
 return out.get('data',{})
def control(path):
 with op.open(urllib.request.Request('http://127.0.0.1:18103/'+path,method='POST',data=b''),timeout=5) as r:r.read()
def pid():return remote("ps w | awk '/v2raya_core run --config=\/etc\/v2raya\/config.json/ && !/awk/ {print $1}'")
def policy(mode,interval='3600s'):
 api('PUT','outbound',{'outbound':'proxy','setting':{'type':mode,'autoAdd':True,'probeURL':'http://198.51.100.123:18100/health','probeInterval':interval}})
def login():
 global token
 creds={'username':'stability-test','password':'Disposable-VM-1234'}
 try:token=api('POST','account',creds)['token']
 except Exception:token=api('POST','login',creds)['token']
def update(): api('PUT','subscription',{'_type':'subscription','id':1,'sub':0,'outbound':'proxy','bypassProxy':True})

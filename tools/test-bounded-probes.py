import argparse,json,time,urllib.request,urllib.error,subprocess,threading,concurrent.futures
from pathlib import Path
parser=argparse.ArgumentParser(description="Exercise bounded group probes on one disposable OpenWrt VM")
parser.add_argument('--ssh-key',required=True)
parser.add_argument('--ssh-port',default='28922')
parser.add_argument('--api-port',default='28925')
parser.add_argument('--output',default='.')
args=parser.parse_args()
output=Path(args.output);output.mkdir(parents=True,exist_ok=True)
op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
base=f'http://127.0.0.1:{args.api_port}/api/'
token=''
def api(method,path,data=None,check=True):
 req=urllib.request.Request(base+path,data=None if data is None else json.dumps(data).encode(),method=method,headers={'Content-Type':'application/json','Authorization':token})
 with op.open(req,timeout=40) as r: obj=json.load(r)
 if check and obj.get('code')!='SUCCESS': raise RuntimeError(str(obj))
 return obj.get('data',{})
def control(path):
 with op.open(urllib.request.Request('http://127.0.0.1:18103/'+path,data=b'' if path!='state' else None),timeout=5) as r:
  return json.load(r) if path=='state' else None
ssh=['ssh','-F','NUL','-p',args.ssh_port,'-i',args.ssh_key,'-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=NUL','root@127.0.0.1']
def remote(cmd):return subprocess.check_output(ssh+[cmd],stderr=subprocess.DEVNULL,text=True)
def route():
 try:return remote("curl -fsS --max-time 4 -x http://127.0.0.1:20171 http://198.51.100.123:18100/trace").strip()
 except subprocess.CalledProcessError:return ''
def wait_route(want,seconds=35):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  if route()==want:return
  time.sleep(.5)
 raise AssertionError('route never became '+want)
def policy(mode,interval='6s',auto=True):
 api('PUT','outbound',{'outbound':'proxy','setting':{'type':mode,'autoAdd':auto,'probeURL':'http://198.51.100.123:18100/health','probeInterval':interval}})
creds={'username':'vm-test','password':'Resilient-VM-1234'}
try:token=api('POST','account',creds)['token']
except Exception:token=api('POST','login',creds)['token']
print('VERSION',api('GET','version'),flush=True)
# Initial account is a disposable VM fixture. Re-runs retain its two nodes.
touch=api('GET','touch')
if not touch.get('touch',{}).get('servers'):
 for node,port in [('A',18101),('B',18102)]:api('POST','import',{'kind':'server','url':f'socks5://10.0.2.2:{port}#{node}'})
control('A/up');control('B/up');control('A/fast');control('B/fast')
policy('keepcurrent','6s')
api('POST','outboundRefresh',{'outbound':'proxy'})
api('PUT','outboundSelection',{'outbound':'proxy','which':{'_type':'server','id':1,'sub':0,'outbound':'proxy'}})
api('POST','v2ray',{})
wait_route('A')
stop=threading.Event();samples=[]
def monitor():
 cmd="i=0; while [ $i -lt 1000 ]; do n=$(pidof v2raya_core | wc -w); m=$(awk '/MemAvailable/ {print $2}' /proc/meminfo); echo $n:$m; i=$((i+1)); sleep 0.1; done"
 proc=subprocess.Popen(ssh+[cmd],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 while not stop.is_set():
  line=proc.stdout.readline().strip()
  if not line:break
  try:samples.append(tuple(map(int,line.split(':'))))
  except ValueError:pass
 proc.terminate()
th=threading.Thread(target=monitor,daemon=True);th.start()
try:
 policy('keepcurrent','6s')
 time.sleep(8)
 before=control('state')['checks'].copy()
 time.sleep(9)
 after=control('state')['checks'].copy()
 assert after['A']>before['A'] and after['B']==before['B'],(before,after)
 print('PASS interval rechecks current speed only',before,after,flush=True)
 control('A/slow')
 wait_route('B')
 print('PASS low speed triggers replacement without URL outage',flush=True)
 control('A/fast');time.sleep(8);assert route()=='B'
 print('PASS healthy current retained after former node recovers',flush=True)
 # Membership refresh while backup is dead does not probe and retains both nodes.
 policy('keepcurrent','3600s');time.sleep(8);control('A/down')
 before=control('state')['checks'].copy();started=time.monotonic()
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  list(pool.map(lambda _:api('POST','outboundRefresh',{'outbound':'proxy'}),range(8)))
 elapsed=time.monotonic()-started
 after=control('state')['checks'].copy()
 assert before==after,(before,after)
 touch=api('GET','touch');(output/'touch.json').write_text(json.dumps(touch)); assert len(touch['touch']['connectedServer'])==2,touch
 print('PASS eight membership refreshes without checks',round(elapsed,3),'seconds',flush=True)
 control('A/up');control('A/slow')
 policy('leastping','6s');wait_route('B');print('PASS leastping skips slow candidate',flush=True)
 policy('random','6s');wait_route('B');time.sleep(8);assert route()=='B';print('PASS random excludes slow candidate',flush=True)
 policy('roundrobin','6s');wait_route('B');time.sleep(9); assert all(route()=='B' for _ in range(8)); print('PASS roundrobin excludes slow candidate',flush=True)
 # Removed mode is rejected by API.
 rejected=False
 try:policy('firstavailable')
 except (RuntimeError,urllib.error.HTTPError):rejected=True
 assert rejected
 print('PASS firstavailable rejected',flush=True)
finally:
 stop.set();th.join(timeout=3)
 if samples:
  result={'samples':len(samples),'max_core_processes':max(x[0] for x in samples),'min_available_kib':min(x[1] for x in samples)}
  (output/'metrics.json').write_text(json.dumps(result,indent=2));print('METRICS',result,flush=True)
  assert result['max_core_processes']<=2,result
print('ALL LIVE CHECKS PASSED',flush=True)

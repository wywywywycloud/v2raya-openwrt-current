import sys,time,json,pathlib,subprocess
sys.path.insert(0,str(pathlib.Path(__file__).parent));from stability_vm import *
results=[]
def record(name,**data):
 results.append({'test':name,**data});print(json.dumps(results[-1]),flush=True);(ROOT/'candidate-results.json').write_text(json.dumps(results,indent=2))
def setting():return api('GET','outbound?outbound=proxy')['setting']
def trace():return remote('curl -fsS --max-time 4 -x http://127.0.0.1:20171 http://198.51.100.123:18100/trace')
def pin(letter):
 t=api('GET','touch')['touch']
 sub=t['subscriptions'][0]
 for n in sub['servers']:
  # Names remain presentation only, used here to select the fixture node.
  if ('sub'+letter) in n.get('name','') or n.get('port')==str({'A':18101,'B':18102,'C':18104}[letter]):
   api('PUT','outboundSelection',{'outbound':'proxy','which':{'_type':'subscriptionServer','id':n['id'],'sub':0,'outbound':'proxy'}});return
 raise RuntimeError('node shape '+str(sub['servers'][0].keys()))
def route_wait(allowed,seconds=45):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  try:r=trace()
  except Exception:r=''
  if r in allowed:return r
  time.sleep(1)
 raise AssertionError('route failed: '+str(allowed)+' last='+r)
for attempt in range(30):
 try:login();break
 except Exception:
  if attempt==29:raise
  time.sleep(1)
print('VERSION',api('GET','version'),flush=True)
if not pid():api('POST','v2ray',{})
import threading
samples=[];stop=threading.Event()
def monitor():
 command="i=0; while [ $i -lt 2000 ]; do n=$(pidof v2raya_core | wc -w); m=$(awk '/MemAvailable/ {print $2}' /proc/meminfo); echo $n:$m; i=$((i+1)); sleep 0.1; done"
 proc=subprocess.Popen(ssh+[command],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 try:
  while not stop.is_set():
   line=proc.stdout.readline().strip()
   if not line:break
   samples.append(tuple(map(int,line.split(':'))))
 finally:proc.terminate();proc.wait(timeout=5)
th=threading.Thread(target=monitor,daemon=True);th.start()
try:
 for n in 'ABC':control(n+'/up');control(n+'/fast')
 if not api('GET','touch')['touch']['subscriptions']:
  api('POST','import',{'kind':'subscription','url':'http://10.0.2.2:18103/subscription','bypassProxy':True})
 update()
 if len(api('GET','touch')['touch']['subscriptions'][0]['servers'])==3:
  control('subscription/change');update()
 policy('keepcurrent');api('POST','outboundRefresh',{'outbound':'proxy'});time.sleep(10)
 (ROOT/'candidate-touch.json').write_text(json.dumps(api('GET','touch'),indent=2))
 pin('A');policy('fixed');route_wait(['A']);before=pid()
 stream=subprocess.Popen(ssh+['curl -fsS --max-time 60 -x http://127.0.0.1:20171 http://198.51.100.123:18100/stream -o /tmp/stability-stream'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 time.sleep(2)
 for _ in range(6): control('subscription/reverse');update()
 control('subscription/rename');update();time.sleep(2)
 assert pid()==before,(before,pid());assert stream.poll() is None,'stream broke on metadata change';assert trace()=='A'
 record('fixed-reorder-rename-preserves-stream',pid=before,updates=7)
 stream.terminate();stream.communicate(timeout=5)
 policy('keepcurrent','3s');pin('B');assert setting()['type']=='keepcurrent';assert setting()['autoAdd']
 active=[n for n in api('GET','touch')['touch']['connectedServer'] if n.get('active')]
 assert len(active)==1 and active[0].get('selected'),active
 api('PUT','outboundSelection',{'outbound':'proxy','which':None});assert setting()['type']=='keepcurrent'
 route_wait(['B']);before=pid();control('B/slow');time.sleep(15);assert trace()=='B';assert pid()==before
 record('manual-pin-and-slow-current-preserve-policy-and-route',pid=before)
 control('subscription/change');update();route=route_wait(['A','C']);assert setting()['type']=='keepcurrent'
 record('real-membership-change-reselects-with-speed',route=route)
 control(route+'/transient');before=pid();time.sleep(12);assert pid()==before
 record('single-health-failure-does-not-switch',route=route)
 control(route+'/down');replacement=route_wait([n for n in 'AC' if n!=route]);assert setting()['type']=='keepcurrent'
 record('confirmed-failure-switches-without-changing-mode',route=replacement)
 control(route+'/up');control('B/fast')
 for mode in ['leastping','random','roundrobin']:
  policy(mode,'4s');route_wait(['A','B','C']);time.sleep(7)
  assert setting()['type']==mode
  control('subscription/reverse');update();assert setting()['type']==mode
  record('automatic-policy-survives-update',mode=mode)
 policy('keepcurrent','3600s');record('complete')
finally:
 stop.set();th.join(timeout=5)
 if samples:
  metrics={'samples':len(samples),'max_core_processes':max(x[0] for x in samples),'min_available_kib':min(x[1] for x in samples)}
  (ROOT/'metrics.json').write_text(json.dumps(metrics,indent=2));print('METRICS',metrics,flush=True)
  assert metrics['max_core_processes']<=2,metrics

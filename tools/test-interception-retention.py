import sys,time,json,pathlib,subprocess,re,threading
sys.path.insert(0,str(pathlib.Path(__file__).parent));from stability_vm import *
mode='baseline' if args.expect_old else 'candidate'
remote('/etc/init.d/v2raya stop')
hook='''#!/bin/sh
case " $* " in
 *" --stage=pre-start "*)
   if [ -f /tmp/stability-pause ]; then sleep 2; fi
   if [ -f /tmp/stability-fail ]; then exit 1; fi
 ;;
esac
exit 0
'''
subprocess.run(ssh+['cat > /tmp/stability-hook'],input=hook.encode(),check=True,stderr=subprocess.DEVNULL)
remote("chmod +x /tmp/stability-hook; rm -f /tmp/stability-fail /tmp/stability-pause; uci set v2raya.config.core_hook=/tmp/stability-hook; uci commit v2raya; /etc/init.d/v2raya start")
time.sleep(15);login()
for n in 'ABC':control(n+'/up');control(n+'/fast')
if not api('GET','touch')['touch']['subscriptions']:
 api('POST','import',{'kind':'subscription','url':'http://10.0.2.2:18103/subscription','bypassProxy':True})
update()
if len(api('GET','touch')['touch']['subscriptions'][0]['servers'])==2:
 control('subscription/change');update()
policy('keepcurrent');api('POST','outboundRefresh',{'outbound':'proxy'})
def choose(letter):
 sub=api('GET','touch')['touch']['subscriptions'][0]
 node=next(n for n in sub['servers'] if ('sub'+letter) in n['name'])
 return api('PUT','outboundSelection',{'outbound':'proxy','which':{'_type':'subscriptionServer','id':node['id'],'sub':0,'outbound':'proxy'}})
choose('A');time.sleep(2)
# TEST-NET is normally a deliberate direct-route exclusion. Remove it from
# this disposable VM so the canary actually exercises proxy-assigned traffic.
api('PUT','tproxyWhiteIpGroups',{'countryCodes':[],'customIps':[]})
api('PUT','routingA',{'routingA':'ip(198.51.100.123) -> proxy\ndefault: direct'})
api('PUT','setting',{'transparent':'pac','rulePortMode':'routingA','transparentType':args.transparent_type})
api('DELETE','v2ray',{})
api('POST','v2ray',{})
if args.transparent_type=='redirect':
 # REDIRECT uses a built-in private-address set, separately from TPROXY's
 # configurable bypass list. Remove only the controlled fixture subnet.
 remote('nft delete element inet v2raya whitelist { 198.51.100.0/24 }')
assert remote('curl -fsS --max-time 5 http://198.51.100.123:18100/trace')=='A','transparent positive control failed'
remote('nft delete table inet stability_canary 2>/dev/null; true')
nft='''table inet stability_canary {
 chain post { type filter hook postrouting priority 300; policy accept;
 ip daddr 198.51.100.123 oifname != "lo" meta mark & 0x80 == 0 counter comment "raw_proxy_bypass"
 }
}
'''
subprocess.run(ssh+['nft -f -'],input=nft.encode(),check=True,stderr=subprocess.DEVNULL)
remote('touch /tmp/stability-pause')
def exercise(fail=False):
 if fail:remote('touch /tmp/stability-fail')
 command="i=0; while [ $i -lt 55 ]; do nft list table inet v2raya >/dev/null 2>&1; echo table:$?; nc 198.51.100.123 18100 </dev/null >/dev/null 2>&1 & probe=$!; sleep 0.08; kill $probe 2>/dev/null; i=$((i+1)); sleep 0.04; done"
 monitor=subprocess.Popen(ssh+[command],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 time.sleep(.4)
 failure=None
 try:choose('C' if fail else 'B')
 except Exception as e:failure=str(e)
 output=monitor.communicate(timeout=30)[0]
 rules=remote('nft list table inet stability_canary')
 counts=[int(v) for v in re.findall(r'counter packets (\d+)',rules)]
 state={'mode':mode,'failed_start':fail,'api_failed':failure is not None,'missing_table_samples':output.count('table:1'),'bypass_packets':sum(counts),'table_after':remote('nft list table inet v2raya >/dev/null 2>&1; echo $?')=='0'}
 print(json.dumps(state),flush=True)
 return state
result=[exercise(),exercise(True)]
(ROOT/f'guard-{mode}-{args.transparent_type}.json').write_text(json.dumps(result,indent=2))
remote('rm -f /tmp/stability-pause /tmp/stability-fail; uci -q delete v2raya.config.core_hook; uci commit v2raya')
# Explicit start after clearing the injected failure resumes the protected service.
try:api('POST','v2ray',{})
except Exception:pass
if mode=='candidate':
 assert all(x['bypass_packets']==0 and x['missing_table_samples']==0 and x['table_after'] for x in result),result
else:assert result[0]['bypass_packets']>0,result


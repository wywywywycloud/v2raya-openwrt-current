#!/bin/sh
# Run inside a freshly installed OpenWrt VM. The subscription fixture contains
# only an invalid-for-production test node; no router data is embedded here.
set -eu

test "${1:-}" != "" || exit 2
fixture_port=$1
api=http://127.0.0.1:2017/api

registration=$(curl -fsS --max-time 15 -H 'Content-Type: application/json' \
    -d '{"username":"vmtest","password":"TestOnly-VM-12345"}' "$api/account")
token=$(printf '%s' "$registration" | jsonfilter -e '@.data.token')
if [ -z "$token" ]; then echo 'VM account registration did not issue a token' >&2; exit 1; fi
echo 'VM account ready'

get_api() {
    curl -fsS --max-time 15 -H "Authorization: Bearer $token" "$api/$1"
}
post_api() {
    curl -fsS --max-time 30 -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' -d "$2" "$api/$1"
}
check_json() {
    actual=$(printf '%s' "$1" | jsonfilter -e "$2")
    if [ "$actual" != "$3" ]; then
        printf 'Mismatch at %s: got <%s>, expected <%s>\n' "$2" "$actual" "$3" >&2
        exit 1
    fi
}

setting=$(get_api setting)
check_json "$setting" '@.data.setting.logLevel' info
check_json "$setting" '@.data.setting.pacMode' routingA
check_json "$setting" '@.data.setting.proxyModeWhenSubscribe' direct
check_json "$setting" '@.data.setting.pacAutoUpdateMode' none
check_json "$setting" '@.data.setting.pacAutoUpdateIntervalHour' 0
check_json "$setting" '@.data.setting.subscriptionAutoUpdateMode' none
check_json "$setting" '@.data.setting.subscriptionAutoUpdateIntervalHour' 0
check_json "$setting" '@.data.setting.tcpFastOpen' no
check_json "$setting" '@.data.setting.muxOn' no
check_json "$setting" '@.data.setting.mux' 8
check_json "$setting" '@.data.setting.inboundSniffing' http,tls
check_json "$setting" '@.data.setting.transparent' pac
check_json "$setting" '@.data.setting.ipforward' true
check_json "$setting" '@.data.setting.routeOnly' false
check_json "$setting" '@.data.setting.portSharing' true
check_json "$setting" '@.data.setting.transparentType' tproxy
check_json "$setting" '@.data.setting.tproxyExcludedInterfaces' 'docker*,veth*,wg*,ppp*'
check_json "$setting" '@.data.setting.dnsListenAddr' '0.0.0.0:52353'
check_json "$setting" '@.data.setting.dnsCacheEnabled' true
check_json "$setting" '@.data.setting.dnsCacheSize' 4096
check_json "$setting" '@.data.setting.dnsCacheMinTTL' 60
check_json "$setting" '@.data.setting.dnsCacheMaxTTL' 86400
check_json "$setting" '@.data.setting.dnsPrefetch' true
check_json "$setting" '@.data.setting.dnsNegativeCache' true
echo 'Global defaults verified'

outbound=$(get_api 'outbound?outbound=proxy')
check_json "$outbound" '@.data.setting.autoAdd' true
check_json "$outbound" '@.data.setting.probeURL' 'https://www.gstatic.com/generate_204'
check_json "$outbound" '@.data.setting.probeInterval' 3000s
check_json "$outbound" '@.data.setting.type' keepcurrent
echo 'PROXY defaults verified'

rules=$(get_api routingA | jsonfilter -e '@.data.routingA')
rules_hash=$(printf '%s' "$rules" | sha256sum | cut -d ' ' -f 1)
if [ "$rules_hash" != b69c11abacc4466393876bcf249603f7958ce9e0aa960f0dae41e0b2799ebb27 ]; then
    echo "RoutingA digest mismatch: $rules_hash" >&2
    exit 1
fi
echo 'RoutingA defaults verified'

ports=$(get_api ports)
check_json "$ports" '@.data.socks5' 20170
check_json "$ports" '@.data.http' 20171
check_json "$ports" '@.data.httpWithPac' 20172

test "$(uci -q get v2raya.config.enabled)" = 1 || { echo 'UCI enabled mismatch' >&2; exit 1; }
test "$(uci -q get v2raya.config.address)" = '0.0.0.0:2017' || { echo 'UCI address mismatch' >&2; exit 1; }
test "$(uci -q get v2raya.config.log_level)" = info || { echo 'UCI log level mismatch' >&2; exit 1; }
echo 'Ports and UCI defaults verified'

import_body=$(printf '{"kind":"subscription","url":"http://10.0.2.2:%s/test-defaults-subscription.txt"}' "$fixture_port")
import_result=$(post_api import "$import_body")
check_json "$import_result" '@.code' SUCCESS
subscription=$(get_api touch)
check_json "$subscription" '@.data.touch.subscriptions[0].updateMode' interval_failsafe
check_json "$subscription" '@.data.touch.subscriptions[0].updateIntervalMinutes' 60
check_json "$subscription" '@.data.touch.subscriptions[0].failureIntervalMinutes' 1
check_json "$subscription" '@.data.touch.subscriptions[0].allowDirectRecovery' true

echo '__RESILIENT_DEFAULTS_VERIFIED__'

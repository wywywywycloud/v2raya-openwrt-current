#!/bin/sh
# Run after test-resilient-defaults-openwrt.sh in a disposable OpenWrt VM.
set -eu
api=http://127.0.0.1:2017/api
fixture_port=${1:?fixture port required}
login=$(curl -fsS --max-time 15 -H 'Content-Type: application/json' \
    -d '{"username":"vmtest","password":"TestOnly-VM-12345"}' "$api/login")
token=$(printf '%s' "$login" | jsonfilter -e '@.data.token')
test -n "$token"
request() {
    result=$(curl -fsS --max-time 30 -X "$1" -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' -d "$3" "$api/$2")
    actual=$(printf '%s' "$result" | jsonfilter -e '@.code')
    test "$actual" = "$4" || { printf '%s\n' "$result" >&2; exit 1; }
}
request DELETE v2ray '{}' SUCCESS
for mode in proxy pac; do
    request PUT setting "{\"proxyModeWhenSubscribe\":\"$mode\"}" SUCCESS
    request PUT subscription '{"_type":"subscription","id":1}' FAIL
    request PUT subscription '{"_type":"subscription","id":1,"bypassProxy":true}' SUCCESS
    request PUT subscription '{"_type":"subscription","id":1}' FAIL
    url="http://10.0.2.2:$fixture_port/test-defaults-subscription.txt?$mode"
    request POST import "{\"kind\":\"subscription\",\"url\":\"$url\"}" FAIL
    request POST import "{\"kind\":\"subscription\",\"url\":\"$url\",\"bypassProxy\":true}" SUCCESS
    request POST import "{\"kind\":\"subscription\",\"url\":\"$url\"}" FAIL
    setting=$(curl -fsS --max-time 15 -H "Authorization: Bearer $token" "$api/setting")
    test "$(printf '%s' "$setting" | jsonfilter -e '@.data.setting.proxyModeWhenSubscribe')" = "$mode"
    touch=$(curl -fsS --max-time 15 -H "Authorization: Bearer $token" "$api/touch")
    test "$(printf '%s' "$touch" | jsonfilter -e '@.data.running')" = false
    echo "Stopped-core $mode: import/update require explicit one-shot bypass; saved mode unchanged"
done
echo '__MANUAL_SUBSCRIPTION_BYPASS_OK__'

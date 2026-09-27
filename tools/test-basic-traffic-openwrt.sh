#!/bin/sh
# Run only inside the disposable OpenWrt VM with local-socks-fixture.py on the host.
set -eu

api=http://127.0.0.1:2017/api
target=http://198.51.100.123:18100/trace
password=Resilient-VM-1234

curl -fsS --max-time 10 --socks5 10.0.2.2:18101 --noproxy '' "$target" | grep -Fxq A
result=$(curl -fsS --max-time 15 -H 'Content-Type: application/json' \
    -d "{\"username\":\"vm-test\",\"password\":\"$password\"}" "$api/account")
token=$(printf '%s' "$result" | jsonfilter -e '@.data.token')
[ -n "$token" ] || { echo "account creation failed: $result" >&2; exit 1; }

request() {
    method=$1
    path=$2
    body=$3
    result=$(curl -fsS --max-time 30 -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $token" -X "$method" -d "$body" "$api/$path")
    code=$(printf '%s' "$result" | jsonfilter -e '@.code')
    [ "$code" = SUCCESS ] || { echo "$method $path failed: $result" >&2; return 1; }
}

request POST import '{"kind":"server","url":"socks5://10.0.2.2:18101#A"}'
request POST connection '{"_type":"server","id":1,"sub":0,"outbound":"proxy"}'
request PUT outboundSelection '{"outbound":"proxy","which":{"_type":"server","id":1,"sub":0,"outbound":"proxy"}}'
request POST v2ray '{}'

count=0
while [ "$count" -lt 4 ]; do
    actual=$(curl -fsS --max-time 15 --noproxy '' -x http://127.0.0.1:20171 "$target")
    [ "$actual" = A ] || { echo "unexpected proxied response: $actual" >&2; exit 1; }
    /etc/init.d/v2raya running
    count=$((count + 1))
    sleep 1
done
echo '__RESILIENT_TRAFFIC_OK__'

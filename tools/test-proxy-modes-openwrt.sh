#!/bin/sh
# Run only inside the disposable OpenWrt VM while local-socks-fixture.py is up.
set -eu

api=http://127.0.0.1:2017/api
target=http://198.51.100.123:18100
control=http://10.0.2.2:18103
password=Resilient-VM-1234

request() {
    method=$1
    path=$2
    body=$3
    result=$(curl -sS --max-time 120 -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $token" -X "$method" -d "$body" "$api/$path") || return 1
    code=$(printf '%s' "$result" | jsonfilter -e '@.code')
    [ "$code" = SUCCESS ] || { echo "$method $path failed: $result" >&2; return 1; }
    printf '%s\n' "$result"
}

trace() {
    curl -fsS --max-time 8 --noproxy '' -x http://127.0.0.1:20171 "$target/trace"
}

main_core_pid() {
    for candidate in $(pidof v2raya_core); do
        if tr '\0' ' ' < "/proc/$candidate/cmdline" | grep -Fq 'config.json'; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

expect_route() {
    expected=$1
    count=${2:-4}
    i=0
    while [ "$i" -lt "$count" ]; do
        actual=$(trace)
        [ "$actual" = "$expected" ] || {
            echo "route changed: expected $expected, got $actual" >&2
            return 1
        }
        /etc/init.d/v2raya running || return 1
        i=$((i + 1))
        sleep 1
    done
}

wait_route() {
    expected=$1
    i=0
    while [ "$i" -lt 25 ]; do
        actual=$(trace 2>/dev/null || true)
        if [ "$actual" = "$expected" ]; then return 0; fi
        i=$((i + 1))
        sleep 1
    done
    echo "route never became $expected; last=$actual" >&2
    return 1
}

wait_any_route() {
    i=0
    while [ "$i" -lt 25 ]; do
        actual=$(trace 2>/dev/null || true)
        case "$actual" in A|B) return 0 ;; esac
        i=$((i + 1))
        sleep 1
    done
    echo "neither fixture became routable" >&2
    return 1
}

curl -fsS --max-time 5 --socks5 10.0.2.2:18101 --noproxy '' "$target/trace" | grep -Fxq A
curl -fsS --max-time 5 --socks5 10.0.2.2:18102 --noproxy '' "$target/trace" | grep -Fxq B
result=$(curl -sS -H 'Content-Type: application/json' \
    -d "{\"username\":\"vm-test\",\"password\":\"$password\"}" "$api/account")
token=$(printf '%s' "$result" | jsonfilter -e '@.data.token')
[ -n "$token" ] || { echo "account creation failed: $result" >&2; exit 1; }

request POST import '{"kind":"server","url":"socks5://10.0.2.2:18101#A"}' >/dev/null
request POST import '{"kind":"server","url":"socks5://10.0.2.2:18102#B"}' >/dev/null
request POST connection '{"_type":"server","id":1,"sub":0,"outbound":"proxy"}' >/dev/null
request POST connection '{"_type":"server","id":2,"sub":0,"outbound":"proxy"}' >/dev/null
request PUT outboundSelection '{"outbound":"proxy","which":{"_type":"server","id":1,"sub":0,"outbound":"proxy"}}' >/dev/null
request POST v2ray '{}' >/dev/null
expect_route A
echo '__RESILIENT_FIXED_TRAFFIC_OK__'

policy() {
    request PUT outbound "{\"outbound\":\"proxy\",\"setting\":{\"autoAdd\":$2,\"probeURL\":\"$target/health\",\"probeInterval\":\"1s\",\"type\":\"$1\"}}" >/dev/null
}

policy keepcurrent false
expect_route A 8
curl -fsS -X POST "$control/A/down" >/dev/null
wait_route B
expect_route B
curl -fsS -X POST "$control/A/up" >/dev/null
expect_route B 8
echo '__RESILIENT_KEEP_CURRENT_TRAFFIC_OK__'

# Restore the first server as the active route, then remove only backup B
# from automatic membership. The running core must keep its PID and route.
request PUT outboundSelection '{"outbound":"proxy","which":{"_type":"server","id":1,"sub":0,"outbound":"proxy"}}' >/dev/null
expect_route A 2
policy keepcurrent true
request POST outboundRefresh '{"outbound":"proxy"}' >/dev/null
expect_route A 2
before=$(main_core_pid)
curl -fsS -X POST "$control/B/down" >/dev/null
request POST outboundRefresh '{"outbound":"proxy"}' >/dev/null
after=$(main_core_pid)
[ "$before" = "$after" ] || { echo "core restarted after backup membership changed" >&2; exit 1; }
expect_route A
curl -fsS -X POST "$control/B/up" >/dev/null
request POST outboundRefresh '{"outbound":"proxy"}' >/dev/null
expect_route A
echo '__RESILIENT_REFRESH_NO_DROP_OK__'

stable=$(main_core_pid)
policy leastping false
[ "$(main_core_pid)" = "$stable" ] || { echo "policy edit restarted the core" >&2; exit 1; }
wait_route A
expect_route A 6
echo '__RESILIENT_LEAST_LATENCY_TRAFFIC_OK__'

policy firstavailable false
[ "$(main_core_pid)" = "$stable" ] || { echo "policy edit restarted the core" >&2; exit 1; }
wait_route A
expect_route A 6
echo '__RESILIENT_FIRST_AVAILABLE_TRAFFIC_OK__'

policy random false
wait_any_route
[ "$(main_core_pid)" = "$stable" ] || { echo "policy edit restarted the core" >&2; exit 1; }
i=0
while [ "$i" -lt 8 ]; do
    actual=$(trace)
    case "$actual" in A|B) ;; *) echo "random routed to $actual" >&2; exit 1 ;; esac
    /etc/init.d/v2raya running
    i=$((i + 1))
    sleep 1
done
echo '__RESILIENT_RANDOM_TRAFFIC_OK__'

policy roundrobin false
wait_any_route
seen_a=0
seen_b=0
i=0
while [ "$i" -lt 20 ]; do
    actual=$(trace)
    case "$actual" in A) seen_a=1 ;; B) seen_b=1 ;; *) echo "round robin routed to $actual" >&2; exit 1 ;; esac
    /etc/init.d/v2raya running
    i=$((i + 1))
done
[ "$seen_a" = 1 ] && [ "$seen_b" = 1 ] || { echo "round robin never used both nodes" >&2; exit 1; }
echo '__RESILIENT_ROUND_ROBIN_TRAFFIC_OK__'

# A subscription can reorder its members without changing the node currently
# selected from the rest of the catalog. That must not restart the main core.
request PUT outboundSelection '{"outbound":"proxy","which":{"_type":"server","id":1,"sub":0,"outbound":"proxy"}}' >/dev/null
policy keepcurrent true
wait_route A
request POST import "{\"kind\":\"subscription\",\"url\":\"$control/subscription\"}" >/dev/null
request POST outboundRefresh '{"outbound":"proxy"}' >/dev/null
expect_route A 2
before=$(main_core_pid)
curl -fsS -X POST "$control/subscription/reverse" >/dev/null
request PUT subscription '{"_type":"subscription","id":1,"sub":0,"outbound":"proxy"}' >/dev/null
after=$(main_core_pid)
[ "$before" = "$after" ] || { echo "subscription reorder restarted the main core" >&2; exit 1; }
expect_route A
echo '__RESILIENT_SUBSCRIPTION_REORDER_NO_DROP_OK__'

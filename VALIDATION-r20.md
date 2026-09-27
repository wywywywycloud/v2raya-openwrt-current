# Resilient r20 validation

Service/core: `2.5.7-resilient.13-r20.resilient1`. LuCI:
`26.268.0-r20.resilient1`. Application commit:
`0f5101f285cddaedaf7e7f041c833bedb36de0a2`, plus the existing packaging-only
`tools/apply-resilient-defaults.py` patch. No router account or subscription
data is included.

## Behavior

- Automatic membership copies every catalog node, including unavailable nodes,
  without ping, speed checks or a temporary core.
- One shared slot permits at most one temporary probe core beside the traffic
  core. Cancellation holds the slot until the process has exited.
- Least latency uses direct TCP ping ordering, then sequential URL and complete
  256 KiB speed samples. The first candidate reaching 100 KiB/s wins.
- Keep current checks the current server's speed at every configured interval.
  While it passes, no other candidate is probed. Failure, unknown speed or speed
  below the threshold starts the least-latency replacement search.
- Random shuffles candidates and checks them sequentially. Round robin only
  uses candidates that passed. If none qualify, traffic fails closed.
- Subscription recovery checks candidates sequentially and stops on the first
  reachable URL. Unknown speed alone does not trigger subscription recovery.
- First available is removed. Saved values migrate to least latency.

## Checks performed

- Fork GUI: 236 tests; typecheck, all six locale key sets, lint and production
  build passed. Lint retains existing formatting warnings.
- Upstream PR branch: 222 GUI tests, typecheck, locales, lint and build passed.
- Service and core build/vet passed. Linux service tests ran on the same ARM64
  VM. The assets test intentionally allocating over 256 MiB ran separately on
  the Windows host; remaining asset tests passed on Linux. Early attempts to
  run the large Go test executable beside the live service or staged tmpfs IPKs
  hit the VM memory limit; the final service run passed with that memory freed.
- The separate upstream branch's service, controller, kernel and database
  packages passed on Linux. Its reload test was corrected to actually change
  strategy; a worker-only policy edit correctly avoids a reload.
- One OpenWrt 24.10.4 ARM64 VM with **256 MiB RAM** installed the matching IPKs.
  Package signature verification with OpenWrt usign passed. Both binaries report
  `2.5.7-resilient.13`, and the version API reports `coreVersionValid: true`.
- Live controlled SOCKS fixtures proved periodic current-only speed checks,
  replacement after low speed while the URL remained reachable, retaining the
  healthy current server when the former one recovered, least-latency/random
  speed filtering, and repeated round-robin requests excluding a slow node.
- Eight concurrent membership refresh requests retained the dead node and
  completed in 0.187 seconds without increasing probe counters.
- 598 samples at approximately 100 ms intervals observed a maximum of **two
  core processes**, with minimum MemAvailable **108440 KiB** during that run.
- The live browser showed the reduced strategy list, the interval-speed
  explanation and immediate membership refresh. The dialog was inspected at
  390 px width in both dark and light themes.

Reproduction uses `tools/local-socks-fixture.py` and
`tools/test-bounded-probes.py` in the packaging repository. This is one VM run,
not a new nine-version matrix or a physical-router test. The process bound
reduces probe memory spikes; it is not a claim that every possible cause of
core memory growth is fixed.

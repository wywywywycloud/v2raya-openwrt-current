# Resilient r19 validation

Application/core: `2.5.7-resilient.12-r19.resilient1`. LuCI:
`26.268.0-r19.resilient1`. Application source is `b3c8a0a4` plus the
packaging-only defaults patch. Fork main `48fc14b5` additionally corrects a
test fixture; it changes no runtime code.

Manual subscription import and update now ask before a stopped-core proxy/PAC
request uses a direct route. Yes applies only to that request. No cancels.
Update all asks once. Scheduled routing and stored settings are unchanged.

Before publication:

- Fork GUI: 236 tests passed; typecheck, i18n check, lint (existing formatting
  warnings only) and production build passed. The final dashboard guard was
  then checked by all 14 dashboard tests and another typecheck/build.
- Separate upstream PR branch: 228 GUI tests, typecheck, i18n check and service
  tests passed.
- Service and core `go build ./...` and `go vet ./...` passed.
- Service Go tests were cross-compiled and executed in the OpenWrt ARM64 VM.
  The existing reload test was corrected to use a strategy change that actually
  requires a reload; its controller package then passed. The assets package
  passed excluding its 256 MiB allocation test, which exceeded the VM's 512 MiB
  RAM (confirmed OOM). That test passed separately on the Windows host.
- A clean official OpenWrt 24.10.4 armsr/armv8 VM installed all three candidate
  IPKs. Package/binary versions, service, embedded GUI, LuCI files and version
  API passed. `coreVersionValid` was true.
- The existing first-install defaults checks passed, including RoutingA,
  TPROXY, sniffing, timers and group settings.
- Live API tests for both proxy and PAC rejected ordinary stopped-core import
  and update, accepted the same requests with `bypassProxy: true`, and rejected
  later requests without it. Saved routing remained unchanged and the core
  remained stopped.
- The UI confirmation was exercised in a browser and reviewed by the user.

The VM uses a test-only Cortex-A53 opkg architecture alias and extra `/usr`
disk. This is not a physical-router test. This release's new VM checks cover
24.10.4; the preceding r17 release covered all nine 24.10.0–24.10.8 versions.

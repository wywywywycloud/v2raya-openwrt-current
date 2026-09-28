# Current-source packages for OpenWrt 24.10

The legacy SDK recipe at `v2raya/Makefile` targets v2.2.7.4. Current
v2rayA has a separate `core/` Go module and requires its matching
`v2raya_core`, not an independently installed `xray-core` binary.

This alternative source-build pipeline packages both binaries and the LuCI
sources from this checkout for `aarch64_cortex-a53`. It does not require
replacing the Go compiler inside the OpenWrt 24.10 SDK.

Requirements: Go 1.26 (or automatic Go toolchain selection), Node.js 24,
Yarn Classic, Python 3, Git and `shasum`.

```sh
./tools/build-current.sh /path/to/v2rayA 2.5.7-recovery.1 r1 ./packages
```

The input checkout must include the desired changes. Both binaries receive
exactly the same version. `BUILD.txt` records source commits and dirty files;
release builds should use committed, reviewed sources. The output directory
must not exist, to prevent mixing packages from different builds.

The application depends on the matching `v2raya-core` package, CA certificates,
`kmod-nft-tproxy` and official geodata packages. LuCI depends on the application
and `luci-light`. `/etc/config/v2raya` is an opkg conffile; `/etc/v2raya/` is
preserved by sysupgrade via `/lib/upgrade/keep.d/v2raya`. A directory must not
be placed in the binary package's `conffiles` list: opkg cannot back it up as
a regular file during an upgrade.

The init script uses `/usr/share/v2ray`, where OpenWrt installs geodata,
avoiding an unnecessary download into a second directory on first startup.

For an upgrade from the signed Resilient feed, run
`tools/upgrade-resilient.sh` on the router. It checks that the overlay has room
for the largest expanded binary and stages all three checksum-verified IPKs in
`/tmp` before calling opkg. This preflight prevents a low-space core failure
from leaving a newer service paired with an older core. opkg itself is not
transactional, so an unrelated installation error can still require repair.
For a local installation, copy all three IPKs to the router, update its
configured official feed indices and install the three files together.
Check `/api/version`: `coreVersionValid` must be true. Start the service,
open LuCI's Services / v2rayA page and test actual proxied traffic.

`test-openwrt-24.10.4-arm64.ps1` boots the official `armsr/armv8` EFI image,
installs the three packages with their release-native dependencies, starts the
service and checks both versions, the embedded GUI and LuCI. The test-only
architecture entry permits the Cortex-A53 package on the generic ARM64 image.

For the complete published-feed compatibility check, use
`prepare-openwrt-24.10-arm64.ps1` to download and verify the official EFI image
for each release from 24.10.0 through 24.10.8. Then run
`test-openwrt-24.10-feed-matrix.ps1` with the verified image directory, current
three-IPK package directory, QEMU, firmware and Python paths, plus the stamped
`-AppVersion` and `-PackageRelease`. It boots up to three VMs concurrently by
default, runs the signed feed setup inside each VM, checks `opkg download` and
install from the published source, service, GUI, LuCI and `coreVersionValid`,
and writes `matrix-results.json` and a serial log for every release. Add
`-TrafficSmoke` to start the local SOCKS fixture and verify four proxied HTTP
requests through each VM's running core. These are clean-install tests on a
generic ARM64 image with a test-only architecture alias and extra `/usr` disk;
they do not establish hardware compatibility for every router model.

Example in PowerShell 7, from this checkout (`$qemu`, `$firmware`, `$python`
and `$packages` point to installed tools and the three current IPKs):

```powershell
$images = Join-Path $PWD 'verified-images'
0..8 | ForEach-Object {
    ./tools/prepare-openwrt-24.10-arm64.ps1 -Version "24.10.$_" -OutputDir $images
}
./tools/test-openwrt-24.10-feed-matrix.ps1 -Qemu $qemu -Firmware $firmware `
    -ImageDir $images -Packages $packages -Python $python `
    -AppVersion '2.5.7-resilient.11' -PackageRelease 'r18.resilient1' `
    -WorkRoot (Join-Path $PWD 'vm-results') -ThrottleLimit 3 -TrafficSmoke
```

For publication, sign `Packages` using OpenWrt `usign`, distribute only the
public key through a trusted channel and configure an HTTPS opkg source.
Do not disable signature verification. The scripts generate an unsigned
index; they never generate or publish a private signing key.

These packages contain static userspace ARM64 programs, not kernel modules.
Kernel dependencies must come from the exact installed OpenWrt release's
feeds. VM validation on generic ARM64 does not validate a physical router's
wireless drivers, hardware offload or flash upgrade process.

## Resilient distribution branch

This branch packages the same tested application as `v2raya-resilient`,
`v2raya-resilient-core` and `luci-app-v2raya-resilient`. Install the LuCI package to
resolve the exact matching service/core pair. The packages replace the original
names while retaining their service and configuration paths.

The index ends every package paragraph, including the final one, with a blank
line: OpenWrt 24.10 LuCI otherwise omits the last package from Software.

Use release `r19.resilient1` with application version `2.5.7-resilient.12`.
`test-openwrt-24.10.4-arm64.ps1` accepts `-AppVersion` and `-PackageRelease`
so each package set is checked against its own stamped binaries. For a live
traffic run, start `local-socks-fixture.py` on the host, pass `-LiveTestSignal`
to keep the VM running after package checks, install the official `curl`
package in the VM and run `test-proxy-modes-openwrt.sh` there. That script
checks all six group strategies, repeated HTTP proxy requests, failover,
manual membership refresh, subscription reordering and manual start with a
cached automatic group. Create the signal file
to let the VM script shut down and save its serial log.
See [installation instructions](../RESILIENT-INSTALL.md).

## OpenWrt-only first-install defaults (r18)

`apply-resilient-defaults.py` is applied to an **isolated** checkout of
`wywywywycloud/v2rayA-current` at `7d9fcfca05070226066f7f7d16e67aa99c08c3aa`.
The fork's `main` branch and upstream pull requests are not changed. The
packaging release remains application version `2.5.7-resilient.11`, with opkg
release `r18.resilient1` to distinguish the patched binary.

On a new database this selects RoutingA, TPROXY, HTTP+TLS sniffing, IP
forwarding and port sharing. The PROXY group starts in keep-current mode with
auto-add enabled, the standard 204 probe URL, and a 3000-second interval. New
subscriptions use interval/failsafe updates: 60 minutes normally, one minute
after a failure, with direct recovery. The UCI service is enabled on a clean
install. The bundled RoutingA rules match the public Russia template on the
reference router; its MIT notice is shipped in the service IPK.

These values are defaults, so an existing SQLite database, account, node,
subscription URL and manual pin are never overwritten. No private router data
is bundled. The router's old `dnsfix.sh` transparent hook is intentionally not
copied: the current service has native DNS redirect rules, and installing a
second NAT hook would duplicate them. Existing UCI conffiles retain any
locally configured hook during an upgrade.

To reproduce the build, clone the above commit into a disposable checkout,
run `python3 tools/apply-resilient-defaults.py /path/to/disposable-checkout`,
then build the GUI and both Linux ARM64 binaries from that checkout at version
`2.5.7-resilient.11`. Package them with `package-current.py` using service/core
version `2.5.7-resilient.11-r18.resilient1` and LuCI version
`26.268.0-r18.resilient1`. `test-openwrt-24.10.4-arm64.ps1
-CheckResilientDefaults` verifies the first-install settings and a new
subscription through the live API on a clean OpenWrt VM.


## Manual subscription bypass confirmation (r19)

Build application commit `b3c8a0a490bd03a4b2107a3e5802028259d4b7af` with
`apply-resilient-defaults.py` applied only to the disposable source copy. Stamp
both binaries as `2.5.7-resilient.12`; package service/core as
`2.5.7-resilient.12-r19.resilient1` and LuCI as `26.268.0-r19.resilient1`.

Run the ARM64 VM pipeline with `-CheckResilientDefaults
-CheckManualSubscriptionBypass`. The second check uses the disposable account
from the defaults test, verifies import and update in stopped-core proxy/PAC
modes, and checks that confirmation does not persist or start the core. Repeat
with `-InstallFromPublishedFeed` after publishing the signed index.


## Bounded probes (r20)

Build application commit `0f5101f285cddaedaf7e7f041c833bedb36de0a2` with
`apply-resilient-defaults.py` applied to the disposable source copy only. Stamp
both binaries `2.5.7-resilient.13`, service/core packages
`2.5.7-resilient.13-r20.resilient1` and LuCI `26.268.0-r20.resilient1`.

Use the existing ARM64 harness with `-MemoryMiB 256 -LiveTestSignal <path>`.
Keep exactly one VM running. Stage package files on its extra `/usr` disk to
avoid using guest RAM for IPKs while measuring the application. Run large Go
test executables separately with the service stopped.

For the deterministic live checks, generate a disposable self-signed certificate
with SAN `DNS:speed.cloudflare.com`, trust it only in the guest's CA bundle,
and start `local-socks-fixture.py --speed-cert <cert.pem> --speed-key <key.pem>`.
The fixture intercepts the speed URL through its local SOCKS endpoints and can
return fast or throttled complete samples. It does not contact Cloudflare.
Forward host port 28925 to guest 127.0.0.1:2017, then run:

```text
python tools/test-bounded-probes.py --ssh-key <vm-key> --ssh-port 28922 --api-port 28925 --output <results>
```

The script is for a disposable VM. It creates the `vm-test` fixture account,
imports two local SOCKS nodes, changes group policies, records sampled core
counts and exercises real proxied requests. Do not run it against a router.
The `ssh -F NUL` default is for the Windows host used by the ARM64 harness.

## Subscription stability and protected switches (r21)

Build application commit `283daeb0` with `apply-resilient-defaults.py` applied
only to a disposable source checkout. Stamp both binaries
`2.5.7-resilient.14`, service/core packages `2.5.7-resilient.14-r21.resilient1`
and LuCI `26.268.0-r21.resilient1`.

Use the ARM64 harness and test certificate described above. The r21 checks use
`local-stability-fixture.py` instead of the r20 fixture: it provides three
controlled SOCKS nodes, reorder/rename/membership changes, transient health
failures, slow speed responses, and UDP DNS with a rejecting TCP listener.
Run it with `--speed-cert <cert.pem> --speed-key <key.pem>`.

```text
python tools/test-subscription-stability.py --ssh-key <vm-key> --ssh-port 29922 --api-port 29925 --output <results>
python tools/test-interception-retention.py --ssh-key <vm-key> --ssh-port 29922 --api-port 29925 --output <results> --transparent-type tproxy
python tools/test-interception-retention.py --ssh-key <vm-key> --ssh-port 29922 --api-port 29925 --output <results> --transparent-type redirect
```

These scripts change the disposable VM's policy, routing rules, interception
exclusions and lifecycle hook. Never run them against a real router. The
subscription test checks uninterrupted streams on reorder/rename, policy
preservation, reachable slow nodes, true catalog changes and confirmed failover,
and samples the process count. The interception test assigns TEST-NET traffic
to the proxy through RoutingA, verifies a working transparent request first,
then delays startup and injects startup/rollback failures while counting any
unmarked packets that leave the guest. It removes TEST-NET's usual deliberate
direct exemption so that the counter measures actual bypass. A restored table
alone is insufficient: every sample and packet counter must pass. Install the
old r20 packages first and add `--expect-old` to reproduce the previous failure.

Keep-current now retains a reachable current node even with low or unknown
speed; three failed reachability checks trigger a speed-qualified replacement.
Do not use the historical r20 low-speed-eviction assertion for r21. The r21
release was checked on one 24.10.4 ARM64 VM with 512 MiB; it does not claim a
new physical-router or nine-version matrix run.

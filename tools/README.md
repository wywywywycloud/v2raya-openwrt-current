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

For a local installation, copy all three IPKs to the router, update its
configured official feed indices and install the three files together.
Check `/api/version`: `coreVersionValid` must be true. Start the service,
open LuCI's Services / v2rayA page and test actual proxied traffic.

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

Use release `r9.resilient1` with application version `2.5.7-resilient.3`.
See [installation instructions](../RESILIENT-INSTALL.md).

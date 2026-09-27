# v2rayA Resilient for OpenWrt 24.10

This is the personal fork distribution, separate from the upstream pull requests.
Supported package architecture: **aarch64_cortex-a53**. Do not add a different
architecture to a physical router to bypass opkg checks.

## Supported OpenWrt releases

The current r18 feed is offered for **OpenWrt 24.10.0 through 24.10.8**,
inclusive, on **aarch64_cortex-a53** routers. The feed setup script accepts all
nine releases. r13 was installed across that entire version range; r17 was
installed from the published signed feed on the official `armsr/armv8`
VM images for **all nine releases**. The package, service, embedded GUI and LuCI
checks passed on each version. Physical routers remain to be tested for r18.
Each VM also passed four proxied HTTP requests against a controlled local
SOCKS5 test node.
Use the newest 24.10 security update available for the router.

OpenWrt 25.12 is outside this distribution: that series replaced opkg/IPK with
apk/APK and requires separate native packages and a signed APK repository. No
end-of-life OpenWrt series is listed as supported.

## Names

| Package | Purpose | Version |
| --- | --- | --- |
| **luci-app-v2raya-resilient** | Install this one in LuCI; pulls the complete fork | 26.268.0-r18.resilient1 |
| v2raya-resilient | Service and embedded v2rayA web interface | 2.5.7-resilient.11-r18.resilient1 |
| v2raya-resilient-core | Exact matching proxy core | 2.5.7-resilient.11-r18.resilient1 |

r18 adds credential-free settings from the reference router as first-install
defaults. The service and core carry matching version stamps.

The menu is **Services > v2rayA Resilient**. Configuration and service paths retain
`v2raya` so existing settings and accounts can survive replacement. This is a
replacement for the original packages, not a second concurrent instance.
No separate xray-core installation is needed by this distribution.

## Add the signed source once

Run over SSH on the router:

```sh
wget -O /tmp/add-resilient-feed.sh https://raw.githubusercontent.com/wywywywycloud/v2rayA-current/openwrt-feed/add-resilient-feed.sh
sh /tmp/add-resilient-feed.sh
```

The script validates OpenWrt version, architecture, the pinned public-key digest
and feed signature before adding the source. It does **not** install the fork or
change its settings. It replaces this project's previous feed entries and keeps
all other sources. The previous source configuration is saved as
`/etc/opkg/customfeeds.conf.before-resilient` when changed.

Public key fingerprint: `9478c50315c92021`.
Public key SHA256: `7a5f9426bdbacd25d1e89ad7e5e65579b2c33bcd278b0489772f3ab017df8787`.

Release r11 rotates the Resilient feed key. Existing installations must run
the setup command above once before `opkg update`; package settings and the
installed service are not changed by the setup script.

The source line, also visible under Software > Configure opkg, is:

```text
src/gz v2raya_resilient https://raw.githubusercontent.com/wywywywycloud/v2rayA-current/openwrt-feed/openwrt-24.10/resilient/aarch64_cortex-a53
```

Adding this line alone does not install the signing key; use the setup above.
Keep signature verification enabled.

## Install using the OpenWrt GUI

1. Open **System > Software**, click **Update lists**, then filter **resilient**.
2. Click **Install** beside **luci-app-v2raya-resilient** and confirm the dependency
   dialog. Leave **Allow overwriting conflicting package files** unchecked.
3. Refresh LuCI. Open **Services > v2rayA Resilient**. On a clean installation,
   enable the service and click **Save & Apply**, then open its web interface.
4. Confirm the application and core both report `2.5.7-resilient.11`.

If Software is absent, install the official `luci-app-package-manager` first.
The setup needs normal working Internet access. Stop a broken transparent proxy
before adding/updating sources if it prevents downloads.

## Existing installations

Back up `/etc/config/v2raya` and `/etc/v2raya/` before migration. The branded
packages declare replacement of `v2raya`, `v2raya-core` and `luci-app-v2raya`.
The previous personal package names are also replaced automatically.
Modified UCI configuration is retained. opkg may report that the new template
was saved as `/etc/config/v2raya-opkg`; this message is expected and does not mean
the preserved configuration was overwritten.

If the early experimental **v2raya-fork** metapackage is installed, remove that
metapackage in Software first: it pins the old 2.2.x packages. Do not remove the
configuration directory. Migration of an arbitrary production database should
always retain an off-router backup.

## Configure automatic groups and updates

In the application, open the proxy group settings and enable **Automatically
add available servers**. The group checks the entire Proxies catalog using its
probe URL; new groups default to **300s**. The selection list offers latency,
random-within-a-bounded-latency-window and first-available strategies. Use the
`?` help beside the selector for the exact behavior. An empty automatic group
blocks traffic assigned to it. On a manual start, cached group members let the
core start immediately while membership is checked in the background; a group
without cached members is checked before the first start.
Random chooses a server at first connection or after the selected server fails;
it does not rotate a healthy connection on each scheduled check. Keep-current
likewise retains its working server, including through a subscription reorder.
Choosing a concrete server in the dashboard pins it and changes the strategy to
**Do not switch**. Choosing **Auto** returns the group to least latency. The
dashboard distinguishes automatic selection, a fixed pin and keep-current
failover, and both group gears edit the group currently shown on the card.
Each candidate checks the configured URL and downloads a concurrent 256 KiB
speed sample. Servers below 100 KiB/s are excluded while a faster server is
available; if all reachable servers are slower, the fastest measured server is
kept as a fallback.
This is not a system-wide kill switch for service crashes or manual shutdown.

For each subscription, choose one **Automatic subscription update** mode:

- **Disabled** updates only when requested manually.
- **On service start** refreshes once whenever v2rayA starts.
- **At an interval** refreshes on startup and at the required interval in minutes.
- **At an interval with fail-safe recovery** also tests the saved servers at the
  required failure interval and refreshes until at least one server works.

Both interval fields accept whole minutes from 1 to 525600 when their mode uses
them. Failed or empty downloads retain the saved nodes. Upgrades preserve the
old global startup/interval behavior without enabling fail-safe recovery.
The retired per-subscription auto-select option enables automatic membership for
the `PROXY` group once when at least one old subscription used it. Otherwise,
automatic group membership remains disabled until enabled explicitly.

For an existing Resilient installation, use the staged upgrade helper over SSH:

```sh
wget -O /tmp/upgrade-resilient.sh https://raw.githubusercontent.com/wywywywycloud/v2raya-openwrt-current/release/resilient-openwrt-24.10/tools/upgrade-resilient.sh
sh /tmp/upgrade-resilient.sh
```

The helper updates the signed feed index, checks flash and temporary space,
downloads and verifies all three IPKs, then installs the matching core, service
and LuCI package together. If there is too little free flash, it stops before
upgrading any of them. The three package versions are checked afterward. opkg
does not provide an atomic transaction, so retain a configuration backup and
inspect the package status if an installation fails for another reason.
An already installed r18 service/core pair does not need another upgrade.

## Sources and validation

- Application/core: [Resilient source](https://github.com/wywywywycloud/v2rayA-current/tree/main), application commit `7d9fcfca`, with a packaging-only defaults patch.
- Packaging/LuCI: [Resilient packaging branch](https://github.com/wywywywycloud/v2raya-openwrt-current/tree/release/resilient-openwrt-24.10).
- [Signed feed and validation report](https://github.com/wywywywycloud/v2rayA-current/tree/openwrt-feed/openwrt-24.10/resilient).

The service embeds its GUI and uses its matching v2raya_core. Packages are
assembled by `tools/build-current.sh` / `tools/package-current.py` using static
Linux ARM64 binaries. This is not a claim of a full OpenWrt SDK build.

The r17 packages installed from the published feed on the official OpenWrt
24.10.0–24.10.8 `armsr/armv8` images with release-native kernel modules and
dependencies. The test starts the
service, checks both `2.5.7-resilient.11` versions, the embedded GUI, LuCI and
`coreVersionValid`. A test-only `/usr` disk gives the small generic image enough
room for both static binaries. The generic ARM64 image accepts the Cortex-A53
package through a **test-only** opkg architecture alias. Physical hardware and
other architectures are not covered by these VM runs.

r18 was also installed on a fresh OpenWrt 24.10.4 ARM64 VM before publication.
The service, matching core, LuCI menu, embedded GUI and API started. Its live
settings matched the reference router's public defaults, including RoutingA,
TPROXY, HTTP+TLS sniffing, PROXY keep-current/auto-add/3000s and a newly
imported test subscription's 60-minute/one-minute failover schedule. The
published-feed opkg installation is checked separately after release.

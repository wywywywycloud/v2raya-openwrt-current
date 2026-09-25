# v2rayA Resilient for OpenWrt 24.10.4

This is the personal fork distribution, separate from the upstream pull requests.
Supported package architecture: **aarch64_cortex-a53**. Do not add a different
architecture to a physical router to bypass opkg checks.

## Names

| Package | Purpose | Version |
| --- | --- | --- |
| **luci-app-v2raya-resilient** | Install this one in LuCI; pulls the complete fork | 26.268.0-r9.resilient1 |
| v2raya-resilient | Service and embedded v2rayA web interface | 2.5.7-resilient.3-r9.resilient1 |
| v2raya-resilient-core | Exact matching proxy core | 2.5.7-resilient.3-r9.resilient1 |

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

Public key fingerprint: `9f02e659f24749fa`.
Public key SHA256: `6ef5500355caf6da06e020818151ee1a6533336387450b7ac28dcaba5540d979`.

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
4. Confirm the application and core both report `2.5.7-resilient.3`.

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
probe URL; new groups default to **300s**. Keep group selection on **Auto** for
least-latency selection. An empty automatic group blocks traffic assigned to it.
This is not a system-wide kill switch for service crashes or manual shutdown.

For each subscription, enable **Automatically update subscription** and enter
both intervals in minutes. **Regular interval = 0** disables unconditional
updates. **Failure retry** must be at least 1 minute and applies while all
servers in that subscription are unavailable. Failed downloads keep saved nodes.

Earlier first-server, auto-connect and recovery switches are retired. Existing
accounts, subscriptions and group members are preserved; the new switches
default off. Enable them explicitly after upgrading.

For an existing Resilient installation, update package lists and upgrade
**luci-app-v2raya-resilient** in Software; it requires the matching r9 service/core.

## Sources and validation

- Application/core: [Resilient source branch](https://github.com/wywywywycloud/v2rayA-current/tree/release/resilient-openwrt-24.10), application commit `0aafe7fc`.
- Packaging/LuCI: [Resilient packaging branch](https://github.com/wywywywycloud/v2raya-openwrt-current/tree/release/resilient-openwrt-24.10).
- [Signed feed and validation report](https://github.com/wywywywycloud/v2rayA-current/tree/openwrt-feed/openwrt-24.10/resilient).

The service embeds its GUI and uses its matching v2raya_core. Packages are
assembled by `tools/build-current.sh` / `tools/package-current.py` using static
Linux ARM64 binaries. This is not a claim of a full OpenWrt SDK build.

The disposable VM uses official OpenWrt 24.10.4 armsr/armv8 with 256 MiB RAM.
Its generic ARM64 CPU accepts the Cortex-A53 package via a **test-only** opkg
architecture alias. Physical hardware and other architectures are not covered.

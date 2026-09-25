# v2rayA Levin for OpenWrt 24.10.4

This is the personal fork distribution, separate from the upstream pull requests.
Supported package architecture: **aarch64_cortex-a53**. Do not add a different
architecture to a physical router to bypass opkg checks.

## Names

| Package | Purpose | Version |
| --- | --- | --- |
| **luci-app-v2raya-levin** | Install this one in LuCI; pulls the complete fork | 26.268.0-r7.levin1 |
| v2raya-levin | Service and embedded v2rayA web interface | 2.5.7-recovery.2-r7.levin1 |
| v2raya-levin-core | Exact matching proxy core | 2.5.7-recovery.2-r7.levin1 |

The menu is **Services > v2rayA Levin**. Configuration and service paths retain
`v2raya` so existing settings and accounts can survive replacement. This is a
replacement for the original packages, not a second concurrent instance.
No separate xray-core installation is needed by this distribution.

## Add the signed source once

Run over SSH on the router:

```sh
wget -O /tmp/add-levin-feed.sh https://raw.githubusercontent.com/wywywywycloud/v2rayA-current/openwrt-feed/add-levin-feed.sh
sh /tmp/add-levin-feed.sh
```

The script validates OpenWrt version, architecture, the pinned public-key digest
and feed signature before adding the source. It does **not** install the fork or
change its settings. It replaces this project's previous feed entries and keeps
all other sources. The previous source configuration is saved as
`/etc/opkg/customfeeds.conf.before-levin` when changed.

Public key fingerprint: `9f02e659f24749fa`.
Public key SHA256: `6ef5500355caf6da06e020818151ee1a6533336387450b7ac28dcaba5540d979`.

The source line, also visible under Software > Configure opkg, is:

```text
src/gz v2raya_levin https://raw.githubusercontent.com/wywywywycloud/v2rayA-current/openwrt-feed/openwrt-24.10/levin/aarch64_cortex-a53
```

Adding this line alone does not install the signing key; use the setup above.
Keep signature verification enabled.

## Install using the OpenWrt GUI

1. Open **System > Software**, click **Update lists**, then filter **levin**.
2. Click **Install** beside **luci-app-v2raya-levin** and confirm the dependency
   dialog. Leave **Allow overwriting conflicting package files** unchecked.
3. Refresh LuCI. Open **Services > v2rayA Levin**. On a clean installation,
   enable the service and click **Save & Apply**, then open its web interface.
4. Confirm the application and core both report `2.5.7-recovery.2`.

If Software is absent, install the official `luci-app-package-manager` first.
The setup needs normal working Internet access. Stop a broken transparent proxy
before adding/updating sources if it prevents downloads.

## Existing installations

Back up `/etc/config/v2raya` and `/etc/v2raya/` before migration. The branded
packages declare replacement of `v2raya`, `v2raya-core` and `luci-app-v2raya`.
Modified UCI configuration is retained. opkg may report that the new template
was saved as `/etc/config/v2raya-opkg`; this message is expected and does not mean
the preserved configuration was overwritten.

If the early experimental **v2raya-fork** metapackage is installed, remove that
metapackage in Software first: it pins the old 2.2.x packages. Do not remove the
configuration directory. Migration of an arbitrary production database should
always retain an off-router backup.

## Sources and validation

- Application/core: [Levin source branch](https://github.com/wywywywycloud/v2rayA-current/tree/release/levin-openwrt-24.10), application commit `b3c6789330daf3c25f4aaa5464ad2385a7e3c35a`.
- Packaging/LuCI: [Levin packaging branch](https://github.com/wywywywycloud/v2raya-openwrt-current/tree/release/levin-openwrt-24.10).
- [Signed feed and validation report](https://github.com/wywywywycloud/v2rayA-current/tree/openwrt-feed/openwrt-24.10/levin).

The service embeds its GUI and uses its matching v2raya_core. Packages are
assembled by `tools/build-current.sh` / `tools/package-current.py` using static
Linux ARM64 binaries. This is not a claim of a full OpenWrt SDK build.

The disposable VM uses official OpenWrt 24.10.4 armsr/armv8 with 256 MiB RAM.
Its generic ARM64 CPU accepts the Cortex-A53 package via a **test-only** opkg
architecture alias. Physical hardware and other architectures are not covered.

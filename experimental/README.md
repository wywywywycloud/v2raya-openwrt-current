# x-Ray VPN for OpenWrt 24.10 ARM64

This directory contains the package builder, LuCI view, init script, configuration and license copied from packaging revision `564fc811`, with display branding for x-Ray VPN. It needs only Python 3 and two already-built static Linux ARM64 binaries, with the GUI embedded in the service. No lab checkout or absolute build path is required.

Build on Linux with Go **1.26.8**, Node 24 and Yarn 1.22.22. Use the committed `core/go.mod`, `core/go.sum` and `gui/yarn.lock`; do not replace the pinned Xray or net forks with local checkouts. Both remote fork replacements are declared in the main core module because dependency-module replacements are not inherited.

The build commands below run from the **application checkout**, not this packaging repository. Use application commit `002c144fef9be4aeee4716adb2f8d2913d04d6ca` from `wywywywycloud/v2rayA-resilient`, as recorded in [SOURCE.json](SOURCE.json). This is the exact source used for the validated release build.

From that application checkout, build the frontend and ARM64 binaries with a shared version:

```sh
version=2026.09.28-experimental.1
yarn --cwd gui install --frozen-lockfile
yarn --cwd gui lint
yarn --cwd gui typecheck
yarn --cwd gui i18n-check
yarn --cwd gui test
yarn --cwd gui build
mkdir -p service/server/router/web dist
cp -a web/. service/server/router/web/
(cd core && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -mod=readonly -trimpath \
  -ldflags="-X main.Version=$version -s -w" -o ../dist/v2raya_core ./main)
(cd service && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -mod=readonly -trimpath \
  -ldflags="-X github.com/v2rayA/v2rayA/conf.Version=$version -s -w" -o ../dist/v2raya .)
```

Use a clean source checkout so the embedded web directory contains only this build. Package those binaries:

```sh
python3 install/openwrt-experimental/tools/package-current.py \
  --service dist/v2raya --core dist/v2raya_core \
  --version 2026.09.28-experimental.1 \
  --luci-version 2026.09.28-experimental.1 \
  --output dist/openwrt
```

Use an output directory that does not yet exist. The result contains three IPKs and `Packages`/`Packages.gz`. Archive timestamps are fixed for reproducibility. Install the complete matching set; the dependencies require the exact service/core version. Package names, init/UCI identifiers, binary paths and configuration paths retain their existing names for upgrade compatibility.

The target is `aarch64_cortex-a53`. The builder rejects non-ARM64 ELF inputs; building a package does not replace an installation and runtime test on OpenWrt. Supply service and core compiled with the same release version, and retain their hashes in release validation notes.

The identical packaging-only command in this repository is `python3 experimental/tools/package-current.py` with the same arguments and paths to those two built binaries. The release is named **xray-proxy-client-experimental**, while **x-Ray VPN** is the visible application name. This is a downloadable experimental release, not an automatically enabled or officially accepted OpenWrt feed.

#!/bin/sh
# Stage and verify the complete signed-feed release before changing installed packages.
set -eu

feed_index=${RESILIENT_FEED_INDEX:-/var/opkg-lists/v2raya_resilient}
packages='v2raya-resilient-core v2raya-resilient luci-app-v2raya-resilient'

fail() {
    echo "v2rayA Resilient upgrade: $*" >&2
    exit 1
}

field() {
    # OpenWrt 24.10 opkg keeps downloaded Packages.gz in /var/opkg-lists,
    # although the cached filename has no .gz suffix. Accept plain indices
    # too, for local mirrors and older opkg variants.
    if gzip -t "$feed_index" >/dev/null 2>&1; then
        gzip -dc "$feed_index"
    else
        cat "$feed_index"
    fi | awk -v package="$1" -v key="$2" '
        /^Package: / { selected = ($2 == package) }
        selected && index($0, key ": ") == 1 {
            print substr($0, length(key) + 3)
            exit
        }
    '
}

free_kib() {
    df -Pk "$1" | awk 'NR == 2 { print $4 }'
}

is_number() {
    case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

command -v opkg >/dev/null 2>&1 || fail 'opkg is required'
opkg print-architecture | awk '$2 == "aarch64_cortex-a53" { found = 1 } END { exit !found }' ||
    fail 'this feed requires the aarch64_cortex-a53 package architecture'
opkg update || fail 'package-list update failed; installed packages were not changed'
[ -s "$feed_index" ] || fail "signed feed index is missing: $feed_index"

core_version=$(field v2raya-resilient-core Version)
app_version=$(field v2raya-resilient Version)
luci_version=$(field luci-app-v2raya-resilient Version)
[ -n "$core_version" ] && [ "$core_version" = "$app_version" ] && [ -n "$luci_version" ] ||
    fail 'the feed does not contain a complete matching service/core release'

core_bytes=$(field v2raya-resilient-core Installed-Size)
app_bytes=$(field v2raya-resilient Installed-Size)
core_download=$(field v2raya-resilient-core Size)
app_download=$(field v2raya-resilient Size)
luci_download=$(field luci-app-v2raya-resilient Size)
for amount in "$core_bytes" "$app_bytes" "$core_download" "$app_download" "$luci_download"; do
    is_number "$amount" || fail 'the signed feed has an invalid package size'
done

# opkg checks the full expanded package against free overlay space while
# upgrading. A low-space failure here must happen before even the service is
# upgraded, otherwise the new service can be left with the old core.
largest_bytes=$core_bytes
[ "$app_bytes" -le "$largest_bytes" ] || largest_bytes=$app_bytes
overlay_needed_kib=$(( (largest_bytes + 1023) / 1024 + 512 ))
overlay_free_kib=$(free_kib /overlay)
is_number "$overlay_free_kib" || fail 'cannot read free overlay space'
[ "$overlay_free_kib" -ge "$overlay_needed_kib" ] ||
    fail "overlay has ${overlay_free_kib} KiB free; need at least ${overlay_needed_kib} KiB before upgrading. Free space and retry. Installed packages were not changed"

# Downloads live in tmpfs, so package transfer does not consume flash or
# depend on the service still running during installation.
tmp_needed_kib=$(( (core_download + app_download + luci_download + 1023) / 1024 + 2048 ))
tmp_free_kib=$(free_kib /tmp)
is_number "$tmp_free_kib" || fail 'cannot read free /tmp space'
[ "$tmp_free_kib" -ge "$tmp_needed_kib" ] ||
    fail "/tmp has ${tmp_free_kib} KiB free; need at least ${tmp_needed_kib} KiB to stage the release"

stage=$(mktemp -d "${TMPDIR:-/tmp}/v2raya-upgrade.XXXXXX") || fail 'cannot create the staging directory'
trap 'rm -rf "$stage"' EXIT HUP INT TERM
cd "$stage"
for package in $packages; do
    filename=$(field "$package" Filename)
    digest=$(field "$package" SHA256sum)
    case "$filename" in ''|*/*|*'..'*) fail "invalid filename for $package" ;; esac
    [ -n "$digest" ] || fail "missing SHA256 for $package"
    opkg download "$package" || fail "download failed for $package; installed packages were not changed"
    [ -f "$filename" ] || fail "downloaded file is missing for $package"
    actual=$(sha256sum "$filename" | awk '{ print $1 }')
    [ "$actual" = "$digest" ] || fail "checksum mismatch for $package; installed packages were not changed"
done

echo "Installing matching Resilient release $app_version (LuCI $luci_version)."
opkg install \
    "./$(field v2raya-resilient-core Filename)" \
    "./$(field v2raya-resilient Filename)" \
    "./$(field luci-app-v2raya-resilient Filename)" ||
    fail 'opkg install failed; inspect package status before starting v2rayA'

installed_version() {
    opkg status "$1" | awk '/^Version: / { print $2; exit }'
}
[ "$(installed_version v2raya-resilient-core)" = "$core_version" ] &&
[ "$(installed_version v2raya-resilient)" = "$app_version" ] &&
[ "$(installed_version luci-app-v2raya-resilient)" = "$luci_version" ] ||
    fail 'installed package versions differ from the staged release'

echo "v2rayA Resilient service and core: $app_version; LuCI: $luci_version"
if /etc/init.d/v2raya running >/dev/null 2>&1; then
    echo 'v2rayA service is running.'
else
    echo 'v2rayA service is stopped; inspect /etc/config/v2raya and the service log.' >&2
fi

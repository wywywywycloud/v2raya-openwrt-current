#!/usr/bin/env python3
"""Apply Resilient OpenWrt-only defaults to an isolated v2rayA source copy.

This deliberately does not edit or commit the application fork. Every replacement
is anchored to the currently tested source, so an upstream change fails closed.
"""

import argparse
from pathlib import Path


ROUTING_A = """default: proxy
# Russian domains that still need the proxy.
domain(domain: abook-club.ru, domain: amdm.ru, domain: anime-portal.su, domain: animespirit.ru, domain: anistars.ru) -> proxy
domain(domain: baikal-journal.ru, domain: bestchange.ru, domain: colta.ru, domain: coomer.su, domain: doramalive.ru) -> proxy
domain(domain: ej.ru, domain: fn-volga.ru, domain: grani.ru, domain: itsmycity.ru, domain: jut.su) -> proxy
domain(domain: kara.su, domain: kasparov.ru, domain: kemono.su, domain: mangahub.ru, domain: megapeer.ru) -> proxy
domain(domain: moscowtimes.ru, domain: newtimes.ru, domain: novayagazeta.ru, domain: ohmyswift.ru, domain: paperpaper.ru) -> proxy
domain(domain: pimpletv.ru, domain: polit.ru, domain: republic.ru, domain: scryde.ru, domain: seasonvar.ru) -> proxy
domain(domain: sklatchiki.ru, domain: the-village.ru, domain: theins.ru, domain: tvrain.ru, domain: ua) -> proxy
domain(domain: zahav.ru) -> proxy

# v2fly geosite.dat category-ru covers Russian services and domains.
domain(geosite: category-ru) -> direct

# Russian services outside category-ru.
domain(domain: 1018213540.rsc.cdn77.org, domain: bitrix.info) -> direct

# Local hostnames.
domain(geosite:private)->direct
ip(geoip:private)->direct

protocol(bittorrent)->direct"""


def replace_one(root: Path, relative: str, old: str, new: str) -> None:
    path = root / relative
    content = path.read_text(encoding="utf-8")
    if content.count(old) != 1:
        raise ValueError(f"Expected one source marker in {relative}: {old[:72]!r}")
    path.write_text(content.replace(old, new), encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="isolated checkout; never the app fork's main checkout")
    args = parser.parse_args()
    root = args.source.resolve()
    if not (root / "service/go.mod").is_file():
        parser.error("not a v2rayA source checkout")

    setting = "service/db/configure/setting.go"
    replace_one(root, setting, '\t"github.com/v2rayA/v2rayA/kernel/ipforward"\n', "")
    changes = {
        "RulePortMode:                       WhitelistMode,": "RulePortMode:                       RoutingAMode,",
        "TcpFastOpen:                        Default,": "TcpFastOpen:                        No,",
        'InboundSniffing:                    "http,tls,quic",': 'InboundSniffing:                    "http,tls",',
        "Transparent:                        TransparentClose,": "Transparent:                        TransparentFollowRule,",
        "IpForward:                          ipforward.IsIpForwardOn(),": "IpForward:                          true,",
        "PortSharing:                        false,": "PortSharing:                        true,",
        "TransparentType:                    TransparentRedirect,": "TransparentType:                    TransparentTproxy,",
    }
    for old, new in changes.items():
        replace_one(root, setting, old, new)

    const = "service/db/configure/const.go"
    content = (root / const).read_text(encoding="utf-8")
    begin = '\tRoutingATemplate = `'
    start = content.index(begin) + len(begin)
    end = content.index('`\n)', start)
    old_template = content[start:end]
    if "mail.qq.com" not in old_template or "geoip:private" not in old_template:
        raise ValueError("Unexpected RoutingA template; inspect source before patching")
    replace_one(root, const, old_template, ROUTING_A)

    replace_one(
        root, "service/pre_database.go",
        '\tif err != nil {\n\t\tlog.Fatal("initDBValue: %v", err)\n\t}\n}',
        '\tif err != nil {\n\t\tlog.Fatal("initDBValue: %v", err)\n\t}\n'
        '\t// Seed only a newly created database. Existing groups and pins survive upgrades.\n'
        '\tif err := configure.SetOutboundSetting(configure.DefaultOutboundName, configure.OutboundSetting{\n'
        '\t\tAutoAdd: true,\n'
        '\t\tProbeURL: configure.DefaultProbeURL,\n'
        '\t\tProbeInterval: "3000s",\n'
        '\t\tType: configure.KeepCurrent,\n'
        '\t}); err != nil {\n'
        '\t\tlog.Fatal("initDBValue outbound: %v", err)\n'
        '\t}\n}',
    )
    replace_one(
        root, "service/server/service/import.go",
        '\t\t\tAddress: source,\n\t\t\tStatus:  string(touch.NewUpdateStatus()),',
        '\t\t\tAddress:                source,\n'
        '\t\t\tUpdateMode:             configure.SubscriptionUpdateIntervalFailsafe,\n'
        '\t\t\tUpdateIntervalMinutes:  60,\n'
        '\t\t\tFailureIntervalMinutes: 1,\n'
        '\t\t\tAllowDirectRecovery:    true,\n'
        '\t\t\tStatus:                 string(touch.NewUpdateStatus()),',
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check a release build number or insert one version item in appcast.xml.

Usage:
  update-appcast.py --feed appcast.xml --tag v1.1 --short-version 1.1 \
      --build 2 --asset-url https://.../FloBlur-1.1.zip \
      --length 1234567 --edsig BASE64SIG [--min-os 14.0] [--notes-html notes.html]

Use --check-build with --feed, --tag, --short-version, and --build to
validate against the published feed without changing it.

A retry may refresh the same release with the same build number. A
different release must use a different build number.

Why not generate_appcast: it rewrites every enclosure URL from a single
--download-url-prefix, but GitHub release assets live under per-tag paths
(/releases/download/<tag>/<file>). Regenerating would break old items.
"""
import argparse
import sys
import xml.etree.ElementTree as ET

NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
SPARKLE = f"{{{NS['sparkle']}}}"
ET.register_namespace("sparkle", NS["sparkle"])
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def parse(args):
    p = argparse.ArgumentParser()
    p.add_argument("--feed", required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--short-version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--check-build", action="store_true")
    p.add_argument("--asset-url")
    p.add_argument("--length")
    p.add_argument("--edsig")
    p.add_argument("--min-os", default="14.0")
    p.add_argument("--notes-html", default=None)
    p.add_argument("--repo", default="DeaDoes/FloBlur")
    parsed = p.parse_args(args)
    if not parsed.check_build and not all(
        value and value.strip() for value in (parsed.asset_url, parsed.length, parsed.edsig)
    ):
        p.error("--asset-url, --length, and --edsig are required when writing the feed")
    return parsed


def load_or_skeleton(path, repo):
    try:
        return ET.parse(path)
    except FileNotFoundError:
        rss = ET.Element("rss", version="2.0")
        ch = ET.SubElement(rss, "channel")
        ET.SubElement(ch, "title").text = "FloBlur"
        ET.SubElement(ch, "link").text = f"https://github.com/{repo}/releases/latest"
        ET.SubElement(ch, "description").text = (
            "One clear window — keep the window you're using sharp "
            "and soften everything behind it."
        )
        ET.SubElement(ch, "language").text = "en"
        return ET.ElementTree(rss)


def normalize_build(value):
    value = value.strip()
    if value.isascii() and value.isdecimal():
        return value.lstrip("0") or "0"
    return value


def matching_release_items(channel, version, build):
    """Find retry entries after confirming the build is unique to this release."""
    matches = []
    for item in channel.findall("item"):
        version_tags = {item.findtext(f"{SPARKLE}shortVersionString")}
        builds = {item.findtext(f"{SPARKLE}version")}
        for enclosure in item.findall("enclosure"):
            version_tags.add(enclosure.get(f"{SPARKLE}shortVersionString"))
            builds.add(enclosure.get(f"{SPARKLE}version"))
        versions = {value.strip() for value in version_tags if value and value.strip()}
        builds = {normalize_build(value) for value in builds if value and value.strip()}
        if versions == {version}:
            if builds and builds != {build}:
                raise ValueError(f"release {version} already has build {', '.join(sorted(builds))}")
            matches.append(item)
        elif build in builds:
            owner = ", ".join(sorted(versions)) or item.findtext("title") or "another release"
            raise ValueError(f"build {build} is already assigned to {owner}; increase CURRENT_PROJECT_VERSION")
    return matches


def main(argv):
    a = parse(argv)
    try:
        tree = ET.parse(a.feed) if a.check_build else load_or_skeleton(a.feed, a.repo)
        channel = tree.getroot().find("channel")
        if channel is None:
            raise ValueError("feed has no channel")
        build = normalize_build(a.build)
        if not build.isascii() or not build.isdecimal() or build == "0":
            raise ValueError("expected a positive integer build number")
        matches = matching_release_items(channel, a.short_version, build)
    except (OSError, ET.ParseError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if a.check_build:
        print(f"appcast: build {build} is valid for {a.tag}")
        return 0

    for item in matches:
        channel.remove(item)

    notes = ""
    if a.notes_html:
        with open(a.notes_html, encoding="utf-8") as f:
            notes = f.read()

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"FloBlur {a.short_version}"
    ET.SubElement(item, "link").text = f"https://github.com/{a.repo}/releases/tag/{a.tag}"
    ET.SubElement(item, f"{SPARKLE}version").text = build
    ET.SubElement(item, f"{SPARKLE}shortVersionString").text = a.short_version
    ET.SubElement(item, f"{SPARKLE}minimumSystemVersion").text = a.min_os
    if notes:
        desc = ET.SubElement(item, "description")
        desc.text = notes
    ET.SubElement(item, "enclosure", {
        "url": a.asset_url,
        f"{SPARKLE}version": build,
        f"{{{NS['sparkle']}}}shortVersionString": a.short_version,
        "length": a.length,
        "type": "application/octet-stream",
        f"{{{NS['sparkle']}}}edSignature": a.edsig,
    })

    channel.insert(list(channel).index(channel.find("item")) if channel.find("item") is not None else len(list(channel)), item)
    tree.write(a.feed, encoding="utf-8", xml_declaration=True)
    print(f"appcast: upserted {a.tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Insert (or refresh) one version item in appcast.xml. Idempotent by tag.

Usage:
  update-appcast.py --feed appcast.xml --tag v1.1 --short-version 1.1 \
      --build 2 --asset-url https://.../FloBlur-1.1.zip \
      --length 1234567 --edsig BASE64SIG [--min-os 14.0] [--notes-html notes.html]

Behavior:
  - Parses the existing feed (creates a skeleton if missing).
  - Removes any item whose enclosure tag/shortVersion equals the new tag
    (re-runs are clean, never duplicates).
  - Prepends the new item (newest first), preserves everything else byte-
    byte: old items, order, and URLs are never rewritten, so per-tag
    download URLs stay valid forever.
  - Writes the file back with an XML declaration.

Why not generate_appcast: it rewrites every enclosure URL from a single
--download-url-prefix, but GitHub release assets live under per-tag paths
(/releases/download/<tag>/<file>). Regenerating would break old items.
"""
import argparse
import sys
import xml.etree.ElementTree as ET

NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
ET.register_namespace("sparkle", NS["sparkle"])
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def parse(args):
    p = argparse.ArgumentParser()
    p.add_argument("--feed", required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--short-version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--asset-url", required=True)
    p.add_argument("--length", required=True)
    p.add_argument("--edsig", required=True)
    p.add_argument("--min-os", default="14.0")
    p.add_argument("--notes-html", default=None)
    p.add_argument("--repo", default="DeaDoes/FloBlur")
    return p.parse_args(args)


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


def item_tag(item):
    for child in item:
        if child.tag.endswith("}enclosure") or child.tag == "enclosure":
            return child.get("sparkle:shortVersionString") or child.get("sparkle:version")
    return None


def main(argv):
    a = parse(argv)
    tree = load_or_skeleton(a.feed, a.repo)
    channel = tree.getroot().find("channel")
    if channel is None:
        print("ERROR: feed has no channel", file=sys.stderr)
        return 1

    # Drop any existing entry for this version (idempotent re-runs).
    for item in list(channel.findall("item")):
        enc = item.find("enclosure")
        if enc is None:
            continue
        ver = enc.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString")
        tag = enc.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
        if ver == a.short_version or tag == a.build:
            channel.remove(item)

    notes = ""
    if a.notes_html:
        with open(a.notes_html, encoding="utf-8") as f:
            notes = f.read()

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"FloBlur {a.short_version}"
    ET.SubElement(item, "link").text = f"https://github.com/{a.repo}/releases/tag/{a.tag}"
    ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}version").text = a.build
    ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString").text = a.short_version
    ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}minimumSystemVersion").text = a.min_os
    if notes:
        desc = ET.SubElement(item, "description")
        desc.text = notes
    ET.SubElement(item, "enclosure", {
        "url": a.asset_url,
        f"{{{NS['sparkle']}}}version": a.build,
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

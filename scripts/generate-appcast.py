#!/usr/bin/env python3
"""Generate Fission's single-item Sparkle appcast from sign_update output."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import shlex
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)


def sparkle(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


def parse_signature(path: Path) -> dict[str, str]:
    attributes: dict[str, str] = {}
    for pair in shlex.split(path.read_text(encoding="utf-8")):
        key, value = pair.split("=", 1)
        attributes[key] = value
    required = {"sparkle:edSignature", "length"}
    missing = required.difference(attributes)
    if missing:
        raise ValueError(f"sign_update output is missing: {', '.join(sorted(missing))}")
    return attributes


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--signature", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()

    repository = "https://github.com/blntrsz/Fission"
    release_url = f"{repository}/releases/tag/{args.tag}"
    download_url = f"{repository}/releases/download/{args.tag}/Fission.dmg"
    attributes = parse_signature(args.signature)

    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Fission Desktop Updates"
    ET.SubElement(channel, "link").text = repository
    ET.SubElement(channel, "description").text = "Fission Desktop release updates"
    ET.SubElement(channel, "language").text = "en"

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Fission {args.version}"
    ET.SubElement(item, "pubDate").text = datetime.now(timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S %z"
    )
    ET.SubElement(item, sparkle("version")).text = args.build
    ET.SubElement(item, sparkle("shortVersionString")).text = args.version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = "14.0"
    ET.SubElement(item, sparkle("fullReleaseNotesLink")).text = release_url
    ET.SubElement(item, "description").text = (
        f"<p>Automated desktop build from commit "
        f"<a href=\"{repository}/commit/{args.commit}\"><code>{args.commit[:12]}</code></a>.</p>"
    )

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", download_url)
    enclosure.set("type", "application/octet-stream")
    for key, value in attributes.items():
        if key.startswith("sparkle:"):
            enclosure.set(sparkle(key.removeprefix("sparkle:")), value)
        else:
            enclosure.set(key, value)

    ET.ElementTree(rss).write(
        args.output,
        encoding="utf-8",
        xml_declaration=True,
    )


if __name__ == "__main__":
    main()

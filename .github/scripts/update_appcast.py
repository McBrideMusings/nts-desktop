#!/usr/bin/env python3
"""Prepend a release item to .github/appcast.xml — invoked by the CI release job.

Release notes are pulled from CHANGELOG.md's `## [VERSION]` section (already
rolled from Unreleased by the /release skill before the tag was pushed) and
lightly converted from Markdown to HTML: headings, bullet lists, paragraphs.
Nothing fancier — the appcast update panel is not a full Markdown renderer.
"""
import argparse
import html
import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

ITEM_TEMPLATE = """        <item>
            <title>Version {version}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
{notes_html}
            ]]></description>
            <enclosure url="{dmg_url}" {signature} type="application/octet-stream" />
        </item>
"""


def changelog_section(changelog_text, version):
    pattern = re.compile(
        rf"^## \[{re.escape(version)}\].*?$(.*?)(?=^## \[|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(changelog_text)
    return match.group(1).strip() if match else ""


def markdown_to_html(text):
    # Each bullet/paragraph is hard-wrapped across several physical lines in
    # CHANGELOG.md, with continuation lines carrying no leading "- ". Those
    # have to fold back into the item they continue, not start a new one.
    html_lines = []
    in_list = False
    current = None  # ("li" | "p", [words])

    def flush():
        nonlocal current, in_list
        if current is None:
            return
        kind, words = current
        text = html.escape(" ".join(words))
        if kind == "li":
            if not in_list:
                html_lines.append("<ul>")
                in_list = True
            html_lines.append(f"<li>{text}</li>")
        else:
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append(f"<p>{text}</p>")
        current = None

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            flush()
            continue
        heading = re.match(r"^(#{2,4})\s+(.*)", line)
        bullet = re.match(r"^-\s+(.*)", line)
        if heading:
            flush()
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append(f"<h4>{html.escape(heading.group(2))}</h4>")
        elif bullet:
            flush()
            current = ("li", [bullet.group(1)])
        elif current is not None:
            current[1].append(line)
        else:
            current = ("p", [line])
    flush()
    if in_list:
        html_lines.append("</ul>")
    return "\n".join(html_lines) or "<p>No release notes.</p>"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--dmg-url", required=True)
    parser.add_argument("--signature", required=True,
                         help='sign_update output, e.g. sparkle:edSignature="..." length="123"')
    parser.add_argument("--pub-date", required=True)
    parser.add_argument("--changelog", default="CHANGELOG.md")
    parser.add_argument("--appcast", default=".github/appcast.xml")
    args = parser.parse_args()

    # This string is embedded directly into an XML attribute list (ITEM_TEMPLATE's
    # <enclosure> tag) rather than escaped, since escaping it would corrupt the
    # attribute syntax it already carries — so it's validated shape instead.
    if not re.fullmatch(r'sparkle:edSignature="[A-Za-z0-9+/=]+" length="[0-9]+"', args.signature):
        print(f"error: --signature has an unexpected shape: {args.signature!r}", file=sys.stderr)
        sys.exit(1)

    changelog_text = Path(args.changelog).read_text()
    section = changelog_section(changelog_text, args.version)
    if not section:
        print(f"warning: no CHANGELOG.md section for [{args.version}]", file=sys.stderr)
    notes_html = markdown_to_html(section)

    item = ITEM_TEMPLATE.format(
        version=xml_escape(args.version),
        build=args.build,
        pub_date=args.pub_date,
        notes_html=notes_html,
        dmg_url=xml_escape(args.dmg_url),
        signature=args.signature,
    )

    appcast_path = Path(args.appcast)
    appcast_text = appcast_path.read_text()
    marker = "<language>en</language>"
    if marker not in appcast_text:
        print(f"error: marker {marker!r} not found in {appcast_path}", file=sys.stderr)
        sys.exit(1)
    appcast_text = appcast_text.replace(marker, f"{marker}\n{item}", 1)
    appcast_path.write_text(appcast_text)


if __name__ == "__main__":
    main()

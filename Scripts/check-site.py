#!/usr/bin/env python3
"""Validate the static website's crawlable metadata, schema, and local links."""

from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

SITE_ROOT = Path(__file__).resolve().parents[1] / "docs" / "site"
SITE_URL = "https://jeffalldridge.github.io/macSubtitleOCR-gui/"


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title = ""
        self.in_title = False
        self.h1_count = 0
        self.ids: set[str] = set()
        self.duplicate_ids: set[str] = set()
        self.links: list[str] = []
        self.images: list[dict[str, str | None]] = []
        self.meta_by_name: dict[str, str] = {}
        self.meta_by_property: dict[str, str] = {}
        self.canonical = ""
        self.json_ld: list[str] = []
        self.in_json_ld = False
        self.json_ld_buffer: list[str] = []
        self.hidden_disclosure = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        element_id = values.get("id")
        if element_id:
            if element_id in self.ids:
                self.duplicate_ids.add(element_id)
            self.ids.add(element_id)
        if tag == "title":
            self.in_title = True
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "a" and values.get("href"):
            self.links.append(values["href"] or "")
        elif tag == "link":
            href = values.get("href")
            if href:
                self.links.append(href)
            if values.get("rel") == "canonical":
                self.canonical = href or ""
        elif tag == "img":
            self.images.append(values)
            if values.get("src"):
                self.links.append(values["src"] or "")
        elif tag == "meta":
            content = values.get("content") or ""
            if values.get("name"):
                self.meta_by_name[values["name"] or ""] = content
            if values.get("property"):
                self.meta_by_property[values["property"] or ""] = content
        elif tag == "script" and values.get("type") == "application/ld+json":
            self.in_json_ld = True
            self.json_ld_buffer = []
        elif tag in {"details", "summary"}:
            self.hidden_disclosure = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False
        elif tag == "script" and self.in_json_ld:
            self.json_ld.append("".join(self.json_ld_buffer))
            self.in_json_ld = False

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.title += data
        if self.in_json_ld:
            self.json_ld_buffer.append(data)


def route_for(page: Path) -> str:
    relative = page.relative_to(SITE_ROOT)
    return "" if relative == Path("index.html") else relative.parent.as_posix() + "/"


def parse_page(page: Path) -> PageParser:
    parser = PageParser()
    parser.feed(page.read_text(encoding="utf-8"))
    parser.close()
    return parser


def local_target(page: Path, href: str) -> tuple[Path, str] | None:
    if href.startswith(("https://", "http://", "mailto:")):
        return None
    parts = urlsplit(href)
    target = (page.parent / parts.path).resolve() if parts.path else page.resolve()
    if target.is_dir():
        target /= "index.html"
    return target, parts.fragment


def main() -> int:
    pages = sorted(SITE_ROOT.glob("**/index.html"))
    errors: list[str] = []
    parsed = {page.resolve(): parse_page(page) for page in pages}
    seen: dict[str, set[str]] = {"title": set(), "description": set(), "canonical": set()}
    canonicals: set[str] = set()

    for page in pages:
        data = parsed[page.resolve()]
        label = page.relative_to(SITE_ROOT)
        description = data.meta_by_name.get("description", "")
        expected_canonical = SITE_URL + route_for(page)

        if data.h1_count != 1:
            errors.append(f"{label}: expected one h1, found {data.h1_count}")
        if not data.title.strip() or len(data.title.strip()) > 65:
            errors.append(f"{label}: title must be 1-65 characters")
        if not description or len(description) > 165:
            errors.append(f"{label}: description must be 1-165 characters")
        if data.canonical != expected_canonical:
            errors.append(f"{label}: canonical must be {expected_canonical}")
        if data.duplicate_ids:
            errors.append(f"{label}: duplicate ids: {sorted(data.duplicate_ids)}")
        if data.hidden_disclosure:
            errors.append(f"{label}: answers must not be hidden in details/summary elements")

        for field, value in (("title", data.title.strip()), ("description", description), ("canonical", data.canonical)):
            if value in seen[field]:
                errors.append(f"{label}: duplicate {field}: {value}")
            seen[field].add(value)
        canonicals.add(data.canonical)

        required_og = {
            "og:title", "og:description", "og:type", "og:url", "og:image",
            "og:image:type", "og:image:width", "og:image:height", "og:image:alt",
            "og:site_name", "og:locale",
        }
        missing_og = required_og - data.meta_by_property.keys()
        if missing_og:
            errors.append(f"{label}: missing Open Graph fields: {sorted(missing_og)}")
        if data.meta_by_property.get("og:url") != data.canonical:
            errors.append(f"{label}: og:url must match canonical")
        required_twitter = {"twitter:card", "twitter:title", "twitter:description", "twitter:image", "twitter:image:alt"}
        missing_twitter = required_twitter - data.meta_by_name.keys()
        if missing_twitter:
            errors.append(f"{label}: missing Twitter card fields: {sorted(missing_twitter)}")

        if not data.json_ld:
            errors.append(f"{label}: missing JSON-LD")
        for block in data.json_ld:
            try:
                json.loads(block)
            except json.JSONDecodeError as error:
                errors.append(f"{label}: invalid JSON-LD: {error}")

        for image in data.images:
            if image.get("alt") is None:
                errors.append(f"{label}: image is missing alt text")
        for href in data.links:
            resolved = local_target(page, href)
            if resolved is None:
                continue
            target, fragment = resolved
            if not target.exists():
                errors.append(f"{label}: missing local target {href}")
            elif fragment and target.suffix == ".html":
                target_data = parsed.get(target.resolve()) or parse_page(target)
                if fragment not in target_data.ids:
                    errors.append(f"{label}: missing fragment target {href}")

    namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    sitemap_root = ET.parse(SITE_ROOT / "sitemap.xml").getroot()
    sitemap_urls = {node.text or "" for node in sitemap_root.findall(".//s:loc", namespace)}
    if sitemap_urls != canonicals:
        errors.append(f"sitemap URLs do not match page canonicals: {sorted(sitemap_urls ^ canonicals)}")
    robots = (SITE_ROOT / "robots.txt").read_text(encoding="utf-8")
    if f"Sitemap: {SITE_URL}sitemap.xml" not in robots:
        errors.append("robots.txt does not advertise the sitemap")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Site checks passed for {len(pages)} pages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

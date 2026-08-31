#!/usr/bin/env python3
"""Small JSON-lines backend for the CustomWallpaper Quickshell UI."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

UA = "Mozilla/5.0 (Linux; Hyprland) CustomWallpaper/1.0"


def request(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json,text/html,*/*"})
    with urllib.request.urlopen(req, timeout=25) as response:
        return response.read()


def emit(items: list[dict]) -> None:
    for item in items:
        print(json.dumps(item, ensure_ascii=False))


def _runtime_thumbnail(item: dict) -> dict:
    """Fetch a hotlink-protected preview into the per-login runtime cache."""
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/tmp/custom-wallpaper-{os.getuid()}")
    folder = Path(runtime) / "custom-wallpaper-thumbnails"
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / (re.sub(r"[^a-zA-Z0-9_-]", "-", item["id"])[:90] + ".jpg")
    try:
        if not target.exists() or target.stat().st_size == 0:
            target.write_bytes(request(item["thumb"]))
        item["thumb"] = target.as_uri()
    except OSError:
        pass
    return item


def cache_moe_thumbnails(items: list[dict]) -> list[dict]:
    # Parallel requests keep a 30-card page from waiting on each image in turn.
    with ThreadPoolExecutor(max_workers=8) as pool:
        return list(pool.map(_runtime_thumbnail, items))


def wallhaven(query: str, page: int, purity: str, browse_filter: str) -> list[dict]:
    params = {
        "q": query,
        "page": str(page),
        "sorting": "relevance" if query else ("toplist" if browse_filter == "toplist" else "date_added"),
        "order": "desc",
        "purity": purity,
        "atleast": "1920x1080",
    }
    url = "https://wallhaven.cc/api/v1/search?" + urllib.parse.urlencode(params)
    payload = json.loads(request(url))
    return [{
        "id": row["id"],
        "title": "Wallhaven · " + row["id"],
        "thumb": row["thumbs"]["large"],
        "full": row["path"],
        "pageUrl": row["url"],
        "resolution": row.get("resolution", ""),
        "source": "wallhaven",
    } for row in payload.get("data", [])]


def _moe_image(block: str) -> str:
    patterns = [
        r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)',
        r'<img[^>]+(?:data-src|src)=["\']([^"\']+)',
    ]
    for pattern in patterns:
        match = re.search(pattern, block, re.I)
        if match:
            return html.unescape(match.group(1)).replace("\\/", "/")
    return ""


def moewalls(query: str, page: int, browse_filter: str) -> list[dict]:
    # MoeWalls has no public API. Its searchable HTML is intentionally parsed
    # loosely so small theme/template changes do not break the provider.
    slug = urllib.parse.quote_plus(query.strip())
    if slug:
        url = f"https://moewalls.com/?s={slug}&paged={page}"
    elif browse_filter in {"anime", "games", "landscape", "sci-fi"}:
        suffix = f"page/{page}/" if page > 1 else ""
        url = f"https://moewalls.com/category/{browse_filter}/{suffix}"
    else:
        url = f"https://moewalls.com/page/{page}/" if page > 1 else "https://moewalls.com/"
    body = request(url).decode("utf-8", "replace")
    out: list[dict] = []
    articles = re.findall(r'<article\b.*?</article>', body, re.I | re.S)
    for article in articles:
        card = re.search(r'<a[^>]+title=["\']([^"\']+)["\'][^>]+href=["\'](https?://moewalls\.com/[^"\']+)["\']', article, re.I)
        image = re.search(r'<img[^>]+src=["\']([^"\']+)["\']', article, re.I)
        if not card or not image:
            continue
        title, link = html.unescape(card.group(1)), html.unescape(card.group(2))
        thumb = html.unescape(image.group(1))
        # WordPress exposes the original 1920px poster as the last srcset item.
        srcset = re.search(r'srcset=["\']([^"\']+)["\']', article, re.I)
        full = thumb
        if srcset:
            candidates = re.findall(r'(https?://\S+)\s+\d+w', html.unescape(srcset.group(1)))
            if candidates:
                full = candidates[-1]
        res = re.search(r'class=["\']entry-resolutions["\'].*?>(\d+x\d+)<', article, re.I | re.S)
        ident = re.sub(r'[^a-z0-9]+', '-', link.rstrip('/').split('/')[-1].lower()).strip('-')
        out.append({"id": ident or "moe-" + str(len(out)), "title": title, "thumb": thumb,
                    "full": full, "pageUrl": link, "resolution": res.group(1) if res else "Live preview",
                    "source": "moewalls"})
        if len(out) >= 30:
            break
    return cache_moe_thumbnails(out)


def download(url: str, source: str, ident: str) -> Path:
    parsed = urllib.parse.urlparse(url)
    suffix = Path(parsed.path).suffix.lower()
    if suffix not in {".jpg", ".jpeg", ".png", ".webp"}:
        suffix = ".jpg"
    # Keep exactly one persistent original. Caelestia stores this path as the
    # active wallpaper, so it must survive logout/reboot. A new selection removes
    # the old file first, preventing the selector from growing a wallpaper archive.
    data_home = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))
    folder = Path(data_home) / "custom-wallpaper"
    folder.mkdir(parents=True, exist_ok=True)
    clean_id = re.sub(r"[^a-zA-Z0-9_-]", "-", ident)[:80]
    target = folder / f"{source}-{clean_id}{suffix}"
    payload = request(url)
    # Do not remove the active wallpaper until its replacement has downloaded
    # successfully; a network failure must leave the desktop's current file valid.
    for old in folder.iterdir():
        if old.is_file() and old != target:
            old.unlink(missing_ok=True)
    target.write_bytes(payload)
    return target


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    search = sub.add_parser("search")
    search.add_argument("--source", choices=("wallhaven", "moewalls"), required=True)
    search.add_argument("--query", default="")
    search.add_argument("--page", type=int, default=1)
    search.add_argument("--purity", default="100")
    search.add_argument("--filter", default="latest")
    get = sub.add_parser("download")
    get.add_argument("--url", required=True)
    get.add_argument("--source", required=True)
    get.add_argument("--id", required=True)
    args = parser.parse_args()
    try:
        if args.command == "search":
            emit(wallhaven(args.query, args.page, args.purity, args.filter) if args.source == "wallhaven"
                 else moewalls(args.query, args.page, args.filter))
        else:
            print(download(args.url, args.source, args.id))
        return 0
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

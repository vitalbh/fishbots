#!/usr/bin/env python3
"""Builds community/index.json, the pack catalog the app's "Explorar pacotes…" reads.

It lists every pack in packs/examples/ and community/packs/ (not the template): its metadata from pack.json, the files
the app downloads (pack.json, .metal, cover.png, .md, .txt) and what it brings. Paths are relative to the repository's
root; the app resolves them against the index's own address.

    python3 scripts/catalog.py           # write community/index.json
    python3 scripts/catalog.py --check   # exit 1 if it's out of date (CI)
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["packs/examples", "community/packs"]
REQUIRED = ["id", "name", "version", "author", "license", "description"]
KEEP = (".json", ".metal", ".md", ".txt")


def pack_entry(rel):
    path = os.path.join(ROOT, rel)
    with open(os.path.join(path, "pack.json"), encoding="utf-8") as f:
        p = json.load(f)
    missing = [k for k in REQUIRED if not p.get(k)]
    if missing:
        raise SystemExit(f"{rel}: pack.json needs {', '.join(missing)}")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,40}", p["id"]):
        raise SystemExit(f"{rel}: invalid id {p['id']!r}")
    if not os.path.exists(os.path.join(path, "cover.png")):
        raise SystemExit(f"{rel}: no cover.png (fishbots pack cover {rel})")
    files = sorted(f for f in os.listdir(path)
                   if (f.endswith(KEEP) or f == "cover.png") and not f.startswith(".") and os.path.isfile(os.path.join(path, f)))
    e = {k: p[k] for k in ["id", "name", "version", "author", "license", "description", "descriptions", "names", "homepage", "minApp"] if k in p}
    e["path"] = rel
    e["files"] = files
    e["cover"] = "cover.png"
    e["contents"] = {k: len(p.get(k, [])) for k in ["themes", "styles", "fish", "scenery", "fauna", "agents"] if p.get(k)}
    return e


def build():
    packs = []
    for d in DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if os.path.isfile(os.path.join(base, name, "pack.json")):
                packs.append(pack_entry(f"{d}/{name}"))
    ids = [p["id"] for p in packs]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        raise SystemExit(f"duplicate pack ids: {', '.join(sorted(dup))}")
    return {"format": 1, "packs": sorted(packs, key=lambda p: p["name"].lower())}


def main():
    out = os.path.join(ROOT, "community", "index.json")
    text = json.dumps(build(), ensure_ascii=False, indent=2) + "\n"
    if "--check" in sys.argv:
        current = open(out, encoding="utf-8").read() if os.path.exists(out) else ""
        if current != text:
            print("community/index.json is out of date: run python3 scripts/catalog.py")
            sys.exit(1)
        print("community/index.json is up to date")
        return
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"wrote community/index.json ({text.count('\"path\"')} packs)")


if __name__ == "__main__":
    main()

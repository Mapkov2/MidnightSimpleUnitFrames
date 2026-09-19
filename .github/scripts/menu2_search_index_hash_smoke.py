"""Both generated Menu2 search indexes still describe the Menu2 sources they ship with.

Each index records the SHA256 of every Lua and XML file under Shell/Menu2 at the moment
it was generated, so a stale index is detectable without regenerating it. The two files
hash different sets, and that is deliberate:

  * MSUF_Menu2_Search_StaticIndex_Data_Classic.lua excludes BOTH index files, so its
    recorded hash does not depend on either generated blob and stays stable while the
    Mainline file is restamped.
  * MSUF_Menu2_Search_StaticIndex_Data.lua excludes only itself, so its hash covers the
    Classic file. Restamp the Classic one first, then this one.

Only the Mainline hash was ever checked, and only while packaging a release
(.github/scripts/assert-classic-changelog-links.ps1), so the Classic index could drift
from its own sources indefinitely. This runs in the gate, on the working tree, for both.
"""
import csv
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MENU2 = ROOT / "MidnightSimpleUnitFrames_Options/Shell/Menu2"
SEARCH = MENU2 / "Search"
MAINLINE_INDEX = "Search/MSUF_Menu2_Search_StaticIndex_Data.lua"
CLASSIC_INDEX = "Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua"
RECORDED = re.compile(r'Search\.StaticIndexSourceSha256 = "([0-9A-F]{64})"')
COUNT = re.compile(r"Search\.StaticIndexRecordCount = (\d+)")
PAGE_KEY = re.compile(r"^[A-Za-z0-9_]+$")
BLOB = "Search.StaticIndexBlob = [==[\n"


def check(condition, *detail):
    """Fail explicitly; unlike assert, python -O cannot strip this."""
    if not condition:
        raise SystemExit("Menu2 search index contract failed: " + " | ".join(str(part) for part in detail))


def read(path):
    """Line endings are normalized: the worktree is CRLF and the generator writes LF."""
    return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")


def source_sha256(excluded):
    """The hash both the generator and the release assert compute: relative path, NUL,
    normalized content, NUL, over every Lua/XML file under Shell/Menu2 in path order."""
    digest = hashlib.sha256()
    names = sorted(
        path.relative_to(MENU2).as_posix()
        for path in MENU2.rglob("*")
        if path.is_file() and path.suffix.lower() in (".lua", ".xml")
    )
    hashed = 0
    for name in names:
        if name.lower() in excluded:
            continue
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(read(MENU2 / name).encode("utf-8"))
        digest.update(b"\0")
        hashed += 1
    check(hashed > 0, "no Menu2 sources were hashed")
    return digest.hexdigest().upper(), hashed


def client_indexes():
    """Which index file each client's Options TOC loads, so the two exclusion rules stay
    tied to what actually ships instead of to a hard-coded flavor list."""
    with open(ROOT / "tools/classic-client-matrix.tsv", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    check(rows, "tools/classic-client-matrix.tsv names no clients")
    loaded = {}
    for row in rows:
        suffix = row["Suffix"]
        toc = ROOT / f"MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options_{suffix}.toc"
        check(toc.is_file(), suffix, f"missing Options TOC: {toc}")
        found = set()
        for entry in read(toc).splitlines():
            entry = entry.strip().replace("\\", "/")
            if not entry or entry.startswith("#") or not entry.lower().endswith(".xml"):
                continue
            xml = ROOT / "MidnightSimpleUnitFrames_Options" / entry
            check(xml.is_file(), suffix, f"missing manifest: {xml}")
            for name in re.findall(r'<Script\s+file="([^"]+)"', read(xml)):
                name = name.replace("\\", "/")
                if "MSUF_Menu2_Search_StaticIndex_Data" in name:
                    found.add((xml.parent.relative_to(MENU2).as_posix() + "/" + name).lstrip("./"))
        check(len(found) == 1, suffix, "loads these static index files:", sorted(found))
        loaded[suffix] = found.pop()
    return loaded


loaded = client_indexes()
mainline = sorted(suffix for suffix, name in loaded.items() if name == MAINLINE_INDEX)
classic = sorted(suffix for suffix, name in loaded.items() if name == CLASSIC_INDEX)
check(mainline and classic, "one of the two index files is loaded by no client:", loaded)
check(len(mainline) + len(classic) == len(loaded), "a client loads an unknown index file:", loaded)
print(f"PASS index ownership: {', '.join(mainline)} load the Mainline index; {', '.join(classic)} load the Classic index")

# The Classic file is hashed first and without either blob, so restamping the Mainline
# file never invalidates it; the Mainline file then covers the settled Classic file.
for label, name, excluded in (
    ("Classic", CLASSIC_INDEX, {MAINLINE_INDEX.lower(), CLASSIC_INDEX.lower()}),
    ("Mainline", MAINLINE_INDEX, {MAINLINE_INDEX.lower()}),
):
    path = MENU2 / name
    check(path.is_file(), label, f"missing generated index: {path}")
    text = read(path)
    recorded = RECORDED.search(text)
    check(recorded, label, "index records no source hash")
    computed, hashed = source_sha256(excluded)
    check(
        recorded.group(1) == computed,
        label,
        "index is stale: it records",
        recorded.group(1)[:16],
        "but its", hashed, "sources hash to",
        computed[:16],
        "- regenerate it (.github/scripts/search_static_index_project.lua) and restamp the Classic file first",
    )

    count = COUNT.search(text)
    check(count, label, "index records no record count")
    check(BLOB in text, label, "index has no blob")
    rows = [row for row in text.split(BLOB, 1)[1].rsplit("\n]==]\n", 1)[0].split("\n") if row]
    check(
        int(count.group(1)) == len(rows),
        label, "index records", count.group(1), "rows but carries", len(rows),
    )
    fields = {len(row.split("\t")) for row in rows}
    check(fields == {12}, label, "index rows are not all 12 fields:", sorted(fields))

    # Nothing can hash a file into itself, so the blob gets a row-level integrity pass
    # instead: the runtime splits on the tab, routes on the identity and scores on the
    # normalized label, and every one of those has to hold for a row to be reachable.
    seen = {}
    unit = chr(31)
    for row in rows:
        page, _, _, _, _, _, label_norm, identity = row.split("\t")[:8]
        check(PAGE_KEY.match(page), label, "row has a malformed page key:", repr(page))
        check(label_norm.strip(), label, "row has an empty normalized label:", repr(row[:120]))
        check(identity not in seen, label, "two rows share a search identity:", repr(identity))
        seen[identity] = row
        parts = identity.split(unit)
        check(len(parts) >= 2, label, "row identity has no page component:", repr(identity))
        encoded = page.replace("%", "%25").replace(unit, "%1F").replace(".", "%2E")
        check(parts[1] == encoded, label, "row identity names page", repr(parts[1]), "but sits on", repr(page))
    print(f"PASS {label} index: {hashed} Menu2 sources hash to {computed[:16]}, "
          f"{len(rows)} rows of 12 fields with unique, page-consistent identities")

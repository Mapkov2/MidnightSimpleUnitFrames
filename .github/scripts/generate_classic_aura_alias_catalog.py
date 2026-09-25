"""Compile SpellName CSV exports into the WoW Forever aura alias catalog.

WoW Forever runs Classic Era spell data (ranked spells) under a Mainline
client, so it uses the native AuraContainer runtime, where aura names are not
readable at runtime. The runtime therefore expands every configured or
curated spell ID to all IDs that share its exact localized SpellName before
handing the ID set to Blizzard's candidate filters.

Vanilla, TBC and Mists need no catalog and ship none: their Lua aura backend
reads aura payloads and matches the aura name whenever the ID misses
(Game/Classic/Auras ClassicFeatures.NameHash), which covers spell ranks and
cast-versus-aura ID drift on whatever build the client runs.

Input: one <locale>/SpellName.csv per supported locale exported from the
Forever client build (wago.tools DB2 CSV export of SpellName, FileDataID
1990283). The encoding, loader (MSUF_Auras3_AuraAliases.lua) and file naming
are identical to Retail's .github/scripts/generate_aura_alias_catalog.py; only
the row-count sanity floor and the header differ, because the build ships
roughly 30k spell names instead of Retail's 400k+.

Guard: WoW Forever shares the Mainline TOCs with Midnight, which carry the
Retail catalog behind [ExcludeLoadGameType camelot]. The Forever files still
carry an MSUF.Client.IsForever guard and return on every other Mainline client.

Locale folding: an export that is byte-identical to enUS (wago.tools answers
the itIT request with the enUS table on every Classic build) produces the same
payload, and shipping it twice costs a second file that compiles at every
login. Such a locale is served by the enUS file, whose locale guard accepts it,
and gets no file of its own. The loader only reads AuraAliasCatalog.localized
from whichever file matches GetLocale(), so the resolved groups are unchanged.

Usage (run from the Classic repository root):
  python .github/scripts/generate_classic_aura_alias_catalog.py \
      --flavor Forever --build 1.60.1.69876 --input <dir-with-locale-folders>

Reproduction without the exports:
  python .github/scripts/generate_classic_aura_alias_catalog.py --verify Forever
recovers every locale's groups from the shipped files, re-renders them into a
temporary directory and fails on the first byte of difference. It proves the
emitted files, not the CSV parsing, so it never writes into the addon tree.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import tempfile
from collections import defaultdict
from pathlib import Path

LOCALES = ("enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW")
FOREVER = "Forever"
FLAVORS = (FOREVER,)
DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
WIDTH = 4
MIN_ROWS = 20_000
BASE_LOCALE = "enUS"
HEADER = re.compile(r"^-- SpellName / (?P<label>.+?) (?P<build>[0-9.]+) / (?P<locales>[A-Za-z+]+); ", re.M)
GUARD = re.compile(r'^if (?P<tests>locale ~= "[A-Za-z]+"( and locale ~= "[A-Za-z]+")*) then return end$', re.M)


def encode(value: int) -> str:
    if not 0 < value < 36 ** WIDTH:
        raise ValueError(f"Spell ID outside catalog encoding: {value}")
    result = ""
    for _ in range(WIDTH):
        value, digit = divmod(value, 36)
        result = DIGITS[digit] + result
    return result


def read_groups(path: Path) -> tuple[set[tuple[int, ...]], dict]:
    names = defaultdict(list)
    ids = set()
    with path.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != ["ID", "Name_lang"]:
            raise ValueError(f"Unexpected SpellName columns in {path}: {reader.fieldnames}")
        for row in reader:
            spell_id = int(row["ID"])
            encode(spell_id)
            if spell_id in ids:
                raise ValueError(f"Duplicate SpellName ID: {spell_id}")
            ids.add(spell_id)
            if row["Name_lang"]:
                names[row["Name_lang"]].append(spell_id)
    if len(ids) < MIN_ROWS:
        raise ValueError(f"Incomplete Classic SpellName export: {path} ({len(ids)} rows)")
    groups = {tuple(sorted(group)) for group in names.values() if len(group) > 1}
    return groups, {"csv_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "rows": len(ids), "groups": len(groups),
                    "alias_ids": sum(map(len, groups)), "max_id": max(ids)}


def pack(groups: set[tuple[int, ...]]) -> str:
    return "\n" + "\n".join("".join("_" + encode(i) for i in group)
                               for group in sorted(groups)) + "\n"


def unpack(blob: str) -> set[tuple[int, ...]]:
    return {tuple(int(token, 36) for token in row.split("_")[1:])
            for row in blob.splitlines() if row}


def partition(groups: dict) -> tuple[set, list]:
    """The shared intersection plus the emit plan: one entry per file, with the locales
    that file serves. A locale whose payload equals enUS joins the enUS file instead of
    duplicating it; every other locale keeps its own."""
    common = set.intersection(*groups.values())
    base = groups[BASE_LOCALE] - common
    plan = [(BASE_LOCALE, [BASE_LOCALE])]
    for locale in LOCALES:
        if locale == BASE_LOCALE:
            continue
        if groups[locale] - common == base:
            plan[0][1].append(locale)
        else:
            plan.append((locale, [locale]))
    return common, plan


def render(flavor: str, build: str, common: set, groups: dict, plan: list) -> dict:
    """Every file's exact bytes, keyed by filename. Nothing is written here."""
    label = flavor
    files = {}
    for locale, served in [("Common", ["Common"])] + plan:
        selected = common if locale == "Common" else groups[locale] - common
        blob = pack(selected)
        assert unpack(blob) == selected
        if locale != "Common":
            for name in served:
                assert common | unpack(blob) == groups[name], f"{name} does not resolve to its own groups"
            assert not {i for g in common for i in g}.intersection(i for g in selected for i in g)
        header = ("-- GENERATED by .github/scripts/generate_classic_aura_alias_catalog.py; do not edit.\n"
                  f"-- SpellName / {label} {build} / {'+'.join(served)}; exact-name groups, base36 IDs.\n"
                  "local _, MSUF = ...\n")
        if flavor == FOREVER:
            # WoW Forever reads the Mainline TOCs, which also carry the Retail catalog
            # for every other game type; without this guard both would load on Midnight.
            header += ("local Client = MSUF.Client\n"
                       "if not (Client ~= nil and Client.IsForever == true) then return end\n")
        if locale != "Common":
            tests = " and ".join(f'locale ~= "{name}"' for name in served)
            header += ("local locale = GetLocale()\n"
                       "if locale == \"enGB\" then locale = \"enUS\" end\n"
                       "if locale == \"ptPT\" then locale = \"ptBR\" end\n"
                       f"if {tests} then return end\n")
        field = "common" if locale == "Common" else "localized"
        if locale == "Common":
            header += f'MSUF.MSUF_Auras3.AuraAliasCatalog = {{ build = "{flavor}-{build}", width = {WIDTH} }}\n'
        else:
            header += "MSUF.MSUF_Auras3.AuraAliasCatalog.locale = locale\n"
        files[f"MSUF_Auras3_AliasData_{locale}.lua"] = header + \
            f"MSUF.MSUF_Auras3.AuraAliasCatalog.{field} = [[\n" + blob + "]]\n"
    return files


def describe(files: dict, plan: list) -> dict:
    served = dict(plan)
    out = {}
    for name, source in files.items():
        entry = {"bytes": len(source), "sha256": hashlib.sha256(source.encode()).hexdigest()}
        locale = name[len("MSUF_Auras3_AliasData_"):-len(".lua")]
        if locale != "Common":
            entry["locales"] = served[locale]
        out[name] = entry
    return out


def generate(inputs: Path, output: Path, flavor: str, build: str) -> dict:
    groups, provenance = {}, {}
    for locale in LOCALES:
        csv_path = inputs / locale / "SpellName.csv"
        groups[locale], provenance[locale] = read_groups(csv_path)
    row_counts = {p["rows"] for p in provenance.values()}
    if len(row_counts) != 1:
        raise ValueError(f"Locale exports disagree on row count: {row_counts}")
    common, plan = partition(groups)
    files = render(flavor, build, common, groups, plan)
    output.mkdir(parents=True, exist_ok=True)
    for stale in output.glob("MSUF_Auras3_AliasData_*.lua"):
        if stale.name not in files:
            stale.unlink()
    for name, source in files.items():
        (output / name).write_text(source, encoding="ascii", newline="\n")
    folded = {name: locale for locale, names in plan for name in names if name != locale}
    return {"flavor": flavor, "build": build, "file_data_id": 1990283,
            "encoding": "base36-token-groups-v1", "common_groups": len(common),
            "folded_locales": folded, "locales": provenance, "generated": describe(files, plan)}


def recover(directory: Path, flavor: str) -> tuple[str, set, dict, list]:
    """Read a shipped catalog back into the inputs render() needs. The payload is a
    lossless encoding of the per-locale groups, so this recovers every group exactly;
    the CSV row counts, hashes and maximum IDs are not in the files and are not
    invented here."""
    def read(name):
        path = directory / name
        if not path.is_file():
            raise SystemExit(f"{path}: missing; cannot reproduce this catalog")
        # The worktree is CRLF and the generator writes LF: compare the content, not the
        # checkout's line endings.
        return path.read_text(encoding="ascii").replace("\r\n", "\n")

    def blob_of(text, field):
        marker = f"MSUF.MSUF_Auras3.AuraAliasCatalog.{field} = [[\n"
        if marker not in text:
            raise SystemExit(f"catalog file has no {field} payload")
        return text.split(marker, 1)[1].rsplit("]]\n", 1)[0]

    shared = read("MSUF_Auras3_AliasData_Common.lua")
    head = HEADER.search(shared)
    if not head:
        raise SystemExit("Common file carries no '-- SpellName / <flavor> <build> / <locale>' header")
    expected = flavor
    if head["label"] != expected:
        raise SystemExit(f"Common file is a {head['label']} catalog, not {expected}")
    build = head["build"]
    common = unpack(blob_of(shared, "common"))

    groups, plan, seen = {}, [], set()
    for locale in LOCALES:
        if locale in seen:
            continue
        name = f"MSUF_Auras3_AliasData_{locale}.lua"
        if not (directory / name).is_file():
            raise SystemExit(f"{directory / name}: no file and no earlier file serves {locale}")
        text = read(name)
        guard = GUARD.search(text)
        if not guard:
            raise SystemExit(f"{name}: no locale guard to read the served locales from")
        served = re.findall(r'locale ~= "([A-Za-z]+)"', guard["tests"])
        if served[0] != locale:
            raise SystemExit(f"{name}: guards {served[0]}, expected {locale}")
        localized = unpack(blob_of(text, "localized"))
        for name_served in served:
            groups[name_served] = common | localized
            seen.add(name_served)
        plan.append((locale, served))
    missing = [locale for locale in LOCALES if locale not in groups]
    if missing:
        raise SystemExit(f"no file serves these locales: {', '.join(missing)}")
    return build, common, groups, plan


def verify(directory: Path, flavor: str) -> dict:
    """Re-render the catalog from what it already contains and compare byte for byte."""
    build, common, groups, plan = recover(directory, flavor)
    recomputed, replan = partition(groups)
    if recomputed != common:
        raise SystemExit(f"{flavor}: the shared partition does not follow from the locale payloads "
                         f"({len(common)} shipped groups, {len(recomputed)} recomputed)")
    if replan != plan:
        raise SystemExit(f"{flavor}: locale folding does not follow from the payloads; "
                         f"shipped {plan}, recomputed {replan}")
    files = render(flavor, build, common, groups, plan)
    shipped = sorted(path.name for path in directory.glob("MSUF_Auras3_AliasData_*.lua"))
    if shipped != sorted(files):
        raise SystemExit(f"{flavor}: the tree holds {shipped}, a fresh run would write {sorted(files)}")
    with tempfile.TemporaryDirectory(prefix="msuf-alias-") as scratch:
        for name, source in files.items():
            (Path(scratch) / name).write_text(source, encoding="ascii", newline="\n")
            fresh = (Path(scratch) / name).read_bytes()
            tree = (directory / name).read_bytes().replace(b"\r\n", b"\n")
            if fresh != tree:
                raise SystemExit(f"{flavor}: {name} differs from a fresh render "
                                 f"({len(tree)} tree bytes vs {len(fresh)} generated)")
    folded = {name: locale for locale, names in plan for name in names if name != locale}
    return {"flavor": flavor, "build": build, "file_data_id": 1990283,
            "encoding": "base36-token-groups-v1", "common_groups": len(common),
            "folded_locales": folded,
            "locales": {locale: {"groups": len(groups[locale]),
                                 "alias_ids": sum(len(group) for group in groups[locale])}
                        for locale in LOCALES},
            "locales_source": "recovered from the shipped catalog: csv_sha256, rows and max_id "
                              "live only in the SpellName exports and are restored by the next "
                              "run with --input",
            "generated": describe(files, plan)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flavor", choices=FLAVORS, help="required unless --verify is given")
    parser.add_argument("--build", help="client build, e.g. 1.60.1.69876")
    parser.add_argument("--input", type=Path, help="directory holding <locale>/SpellName.csv")
    parser.add_argument("--verify", choices=FLAVORS + ("all",), default=None,
                        help="re-render the shipped catalog from its own payload and compare byte for byte")
    parser.add_argument("--output", type=Path, default=None,
                        help="defaults to MidnightSimpleUnitFrames/Game/<flavor>/Auras/AliasData")
    parser.add_argument("--manifest", type=Path, default=None,
                        help="defaults to .github/auras3-alias-catalog-<flavor>.json")
    parser.add_argument("--write-manifest", action="store_true",
                        help="with --verify, rewrite the manifest from the recovered catalog")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]

    def catalog_dir(flavor):
        return args.output or root / "MidnightSimpleUnitFrames" / "Game" / flavor / "Auras" / "AliasData"

    def manifest_file(flavor):
        return args.manifest or root / ".github" / f"auras3-alias-catalog-{flavor.lower()}.json"

    if args.verify:
        flavors = FLAVORS if args.verify == "all" else (args.verify,)
        for flavor in flavors:
            manifest = verify(catalog_dir(flavor), flavor)
            if args.write_manifest:
                path = manifest_file(flavor)
                if path.is_file():
                    # csv_sha256, rows and max_id are facts about an export that no
                    # recovered catalog can reconstruct. Never overwrite them with the
                    # weaker recovered block; a later run with --input refreshes them.
                    previous = json.loads(path.read_text(encoding="utf-8"))
                    if any("csv_sha256" in entry for entry in previous.get("locales", {}).values()):
                        manifest["locales"] = previous["locales"]
                        manifest.pop("locales_source", None)
                path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            folded = manifest["folded_locales"]
            print(f"{flavor} {manifest['build']}: {len(manifest['generated'])} files re-rendered from their own "
                  f"payload and byte-identical to the tree; {manifest['common_groups']} shared groups"
                  + (f"; {', '.join(f'{k} served by {v}' for k, v in folded.items())}" if folded else ""))
        return

    if not args.flavor or not args.build or not args.input:
        parser.error("--flavor, --build and --input are required without --verify")
    manifest = generate(args.input, catalog_dir(args.flavor), args.flavor, args.build)
    manifest_file(args.flavor).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    folded = manifest["folded_locales"]
    print(f"{args.flavor} {args.build}: verified all {len(LOCALES)} locale partitions; "
          f"{manifest['common_groups']} shared groups; "
          f"{sum(f['bytes'] for f in manifest['generated'].values()):,} generated bytes -> {catalog_dir(args.flavor)}"
          + (f"; folded {', '.join(f'{k}->{v}' for k, v in folded.items())}" if folded else ""))


if __name__ == "__main__":
    main()

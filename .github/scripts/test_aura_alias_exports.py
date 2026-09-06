"""Validate catalog provenance and Lua queries against independent SpellName CSVs.

No game access or instrumentation. --exports is the immutable extraction folder.
"""
import argparse
import csv
import hashlib
import json
import random
import subprocess
from collections import defaultdict
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exports", required=True, type=Path)
    parser.add_argument("--lua", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    manifest = json.loads((root / ".github/auras3-alias-catalog.json").read_text())
    data_dir = root / "MidnightSimpleUnitFrames/Auras3/AliasData"
    for filename, record in manifest["generated"].items():
        assert hashlib.sha256((data_dir / filename).read_bytes()).hexdigest() == record["sha256"]
    rng = random.Random(69587)
    script = ['local root=arg[1]',
              'local loader=assert(loadfile(root.."/.github/scripts/auras3_test_loader.lua"))()',
              'local function forbidden() error("catalog touched live API") end',
              'CreateFrame=forbidden; C_Spell={GetSpellName=forbidden}; C_UnitAuras={GetAuraDataBySpellName=forbidden}',
              'local checks=0; local times={}; local retained={}',
              'local function check(A3,id,expected)',
              '  A3.CompileCustomAuraAliases({[id]=true})',
              '  local actual=A3.AuraSpellIDAliases[id] or {id}',
              '  assert(#actual==#expected,"count mismatch "..id)',
              '  local hash={}; for _,v in ipairs(actual) do assert(not hash[v]);hash[v]=true end',
              '  for _,v in ipairs(expected) do assert(hash[v],"missing "..id.." -> "..v) end',
              '  checks=checks+1',
              'end']
    row_total = 0
    for locale, record in manifest["locales"].items():
        folder = locale + ("-hotfix" if record["hotfixed"] else "")
        source = args.exports / folder / "SpellName.csv"
        assert hashlib.sha256(source.read_bytes()).hexdigest() == record["csv_sha256"]
        names = defaultdict(list)
        with source.open(encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                if row["Name_lang"]:
                    names[row["Name_lang"]].append(int(row["ID"]))
                row_total += 1
        groups = sorted(tuple(sorted(g)) for g in names.values())
        packed = data_dir / f"MSUF_Auras3_AliasData_{locale}.lua"
        common = data_dir / "MSUF_Auras3_AliasData_Common.lua"
        actual_groups = set()
        actual_ids = set()
        for path in (common, packed):
            # Independent exhaustive roundtrip: each exact same-name group and
            # every member must match the exported table, not only a sample.
            blob = path.read_text(encoding="ascii").split("= [[\n", 1)[1].rsplit("]]", 1)[0]
            for row in blob.splitlines():
                if not row:
                    continue
                group = tuple(int(i, 36) for i in row.split("_")[1:])
                assert not actual_ids.intersection(group), "an ID occurs in two locale groups"
                actual_ids.update(group)
                actual_groups.add(group)
        assert actual_groups == {g for g in groups if len(g) > 1}, locale
        samples = rng.sample(groups, 100)
        samples += sorted(groups, key=len)[-3:]  # Include huge groups, no 100-ID cap.
        script += ['do', f'GetLocale=function() return "{locale}" end',
                   'collectgarbage("collect"); local memory=collectgarbage("count"); local t=os.clock()',
                   'local ns={MSUF_Auras3={AuraSpellIDAliases={}}};loader.LoadAliasCatalog(root,ns)',
                   'local A3=ns.MSUF_Auras3; local loaded=os.clock();collectgarbage("collect")',
                   'local dataKB=collectgarbage("count")-memory']
        for group in samples:
            for source_id in {group[0], group[len(group) // 2], group[-1]}:
                script.append('check(A3,%d,{%s})' % (source_id, ','.join(map(str, group))))
        script += [f'print(string.format("{locale}: load %.3f ms; retained %.1f KiB",(loaded-t)*1000,dataKB))', 'end']
    script += ['print("PASS CSV oracle queries: "..checks.."; all locale groups verified independently")']
    result = subprocess.run([args.lua, "-", str(root)], input="\n".join(script), text=True,
                            cwd=root, capture_output=True)
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr)
    result.check_returncode()
    print(f"PASS full exports: {row_total:,} rows; generated source hashes; 11 exact locale partitions")


if __name__ == "__main__":
    main()

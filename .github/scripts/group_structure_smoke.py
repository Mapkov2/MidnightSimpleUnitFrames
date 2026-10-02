"""Check structural headroom for the group-frame package only."""
import argparse
from collections import defaultdict
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def source_files(root):
    for folder in ("GroupFrames", "UnitFrames/Engine/Group"):
        for path in sorted((root / "MidnightSimpleUnitFrames" / folder).glob("*.lua")):
            if path.name != "MSUF_UF_Group_Visuals.lua":
                yield path


def mask_literals(source):
    pattern = r"--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"
    return re.sub(pattern, lambda match: re.sub(r"[^\n]", " ", match[0]), source, flags=re.S)


def measure(root, luac):
    results, windows = [], defaultdict(list)
    for path in source_files(root):
        source = path.read_text(encoding="utf-8-sig")
        lines, code = source.splitlines(), mask_literals(source).splitlines()
        listing = subprocess.check_output([luac, "-l", "-p", str(path)], text=True)
        prototypes = re.findall(r"(main|function) <[^\n]+:(\d+),(\d+)>[^\n]*\n([^\n]+)", listing)
        locals_count, upvalues, longest = 0, 0, 0
        for kind, start, end, description in prototypes:
            upvalues = max(upvalues, int(re.search(r"(\d+) upvalue", description)[1]))
            if kind == "main":
                locals_count = int(re.search(r"(\d+) local", description)[1])
            else:
                longest = max(longest, int(end) - int(start) + 1)
        relative = path.relative_to(root).as_posix()
        meaningful = [(i, re.sub(r"\s+", " ", line.strip())) for i, line in enumerate(lines)
                      if line.strip() and not line.lstrip().startswith("--")]
        for offset in range(len(meaningful) - 5):
            window = meaningful[offset:offset + 6]
            windows[tuple(line for _, line in window)].append((relative, tuple(i for i, _ in window)))
        results.append(dict(file=relative, lines=len(lines), locals=locals_count, upvalues=upvalues,
                            longest=longest, wide=sum(len(line) > 160 for line in lines),
                            semicolons=sum(line.count(";") for line in code)))
    duplicate_lines = set()
    duplicates = []
    for sites in windows.values():
        if len(sites) > 1:
            duplicates.append(sites)
            duplicate_lines.update((path, line) for path, indexes in sites for line in indexes)
    return results, duplicates, len(duplicate_lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--limits-only", action="store_true")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    luac = os.getenv("MSUF_LUAC") or shutil.which("luac")
    if not luac:
        luac = str(Path(os.environ["LOCALAPPDATA"]) / "Temp/msuf-lua51/portable/luac.exe")
    results, duplicates, clone_lines = measure(args.root.resolve(), luac)
    total = sum(item["lines"] for item in results)
    share = clone_lines / total
    for item in results:
        print("{file}: {lines} lines, {locals} locals, {upvalues} upvalues, {longest} function lines, "
              "{wide} wide lines, {semicolons} semicolons".format(**item))
    print(f"Group structure: {total} lines; {len(duplicates)} clone windows; {clone_lines} clone lines ({share:.2%})")
    if args.json:
        args.json.write_text(json.dumps(dict(files=results, clones=duplicates, clone_lines=clone_lines), indent=2) + "\n")
    if args.report:
        return
    owned = set((args.root / "tools/classic-owned-addon-paths.txt").read_text().splitlines())
    overrides = {line.split("\t")[0] for line in
                 (args.root / "tools/classic-retail-overrides.tsv").read_text().splitlines()}
    for item in results:
        assert item["locals"] <= 150, f"{item['file']}: main chunk needs headroom below 160"
        assert item["upvalues"] <= 45, f"{item['file']}: upvalue limit"
        assert item["longest"] <= 150, f"{item['file']}: split long function by responsibility"
        if not args.limits_only and item["file"] in owned | overrides:
            assert item["wide"] == 0 and item["semicolons"] == 0, f"{item['file']}: layout limits"
    if not args.limits_only:
        assert share <= .01, "group clone-line share exceeds one percent"
    print("group_structure_smoke: PASS")


if __name__ == "__main__":
    main()

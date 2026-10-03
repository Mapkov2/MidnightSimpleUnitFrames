"""Reject protected-call aliases in owned runtime Lua and XML, including string lookups."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BANNED = {
    "pcall", "xpcall", "securecall", "securecallfunction", "SecureCall",
    "MSUF_SafeCall", "MSUF_FastCall", "InvokeBoundary", "InvokeLabeledBoundary",
    "ProfileIO_RunProtected", "MSUF_ProfileIO_RunProtected", "CallIf",
    "SafeFrameCall", "TryCodecCall", "CallAnchorMethod",
    # coroutine.resume/wrap capture errors exactly like pcall does.
    "coroutine",
}
# Exact native input-rejection sites in the designated boundary module only.
# Each statement is allowed once; generic wrappers and aliases remain forbidden.
REJECTION_BOUNDARIES = {
    "MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua": {
        "local ok, value = pcall(encoding.DeserializeCBOR, payload)",
        "local decoded, blob = pcall(encoding.DecodeBase64, cleaned)",
        "inflated, payload = pcall(encoding.DecompressString, blob, method)",
        "inflated, payload = pcall(encoding.DecompressString, blob)",
        # Host API v1 steps (another addon's page-reset steps, MSUF's scale
        # appliers) run inside host state that a raise must not leave half done.
        "local ok, result = pcall(step, ...)",
    },
}
NAME = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
LONG = re.compile(r"\[(=*)\[")
NUMBER = re.compile(r"\d{1,3}")


def tokens(source):
    """Ignore comments; retain names and literal keys, so aliases cannot evade the gate."""
    i = 0
    while i < len(source):
        comment = source.startswith("--", i)
        start = i + 2 if comment else i
        long = LONG.match(source, start)
        if long:
            body = long.end()
            close = "]" + long[1] + "]"
            end = source.find(close, body)
            if end < 0:
                raise ValueError("unterminated long string/comment")
            if not comment:
                yield source[body:end], i
            i = end + len(close)
        elif comment:
            end = source.find("\n", start)
            i = len(source) if end < 0 else end + 1
        elif source[i] in "\"'":
            quote, begin = source[i], i
            i += 1
            value = []
            while i < len(source) and source[i] != quote:
                if source[i] == "\\":
                    i += 1
                    number = NUMBER.match(source, i)
                    if number:
                        value.append(chr(int(number[0])))
                        i += len(number[0])
                        continue
                value.append(source[i])
                i += 1
            yield "".join(value), begin
            i += 1
        elif source[i].isalpha() or source[i] == "_":
            match = NAME.match(source, i)
            if match:
                yield match[0], i
                i += len(match[0])
            else:
                i += 1
        else:
            i += 1


def versionable(addons):
    """The files git versions below the addon folders: tracked plus untracked
    files no ignore rule excludes. A folder walk would also read ignored local
    leftovers and make a local run disagree with CI."""
    listed = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *addons],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if listed.returncode != 0:
        raise SystemExit("git ls-files failed: " + listed.stderr.decode("utf-8", "replace").strip())
    return sorted({name for name in listed.stdout.decode("utf-8").split("\0") if name})


def owned_files():
    # XML <Script> bodies and On* handlers are Lua too.
    for relative in versionable(("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options")):
        path = ROOT / relative
        if path.suffix.lower() not in (".lua", ".xml") or not path.is_file():
            continue
        if any(part in {"tools", "tests", "scripts"} for part in Path(relative).parts):
            continue
        if "/Libs/" in relative and "/Libs/MSUFUnitFrames/" not in relative:
            continue
        yield path


def main():
    failures, count = [], 0
    for path in owned_files():
        count += 1
        source = path.read_text(encoding="utf-8-sig")
        allowed = set(REJECTION_BOUNDARIES.get(path.relative_to(ROOT).as_posix(), ()))
        for token, offset in tokens(source):
            if token in BANNED:
                end = source.find("\n", offset)
                statement = source[source.rfind("\n", 0, offset) + 1:end if end >= 0 else len(source)].strip()
                if token == "pcall" and statement in allowed:
                    allowed.remove(statement)
                    continue
                line = source.count("\n", 0, offset) + 1
                failures.append(f"{path.relative_to(ROOT).as_posix()}:{line}: {token}")
    if failures:
        raise SystemExit("Forbidden runtime call boundary:\n" + "\n".join(failures))
    print(f"PASS direct error paths: {count} owned Lua/XML files; only reviewed native codec rejection sites; no protected-call aliases")


if __name__ == "__main__":
    main()

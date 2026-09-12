"""Reject protected-call aliases in owned runtime Lua, including string lookups."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
BANNED = {
    "pcall", "xpcall", "securecall", "securecallfunction", "SecureCall",
    "MSUF_SafeCall", "MSUF_FastCall", "InvokeBoundary", "InvokeLabeledBoundary",
    "ProfileIO_RunProtected", "MSUF_ProfileIO_RunProtected", "CallIf",
    "SafeFrameCall", "TryCodecCall", "CallAnchorMethod",
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


def owned_files():
    for addon in ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options"):
        for path in sorted((ROOT / addon).rglob("*.lua")):
            relative = path.relative_to(ROOT).as_posix()
            if any(part in {"tools", "tests", "scripts", ".codex-remote-attachments"} for part in path.relative_to(ROOT).parts):
                continue
            if "Assistant" in relative:
                continue
            if "/Libs/" in relative and "/Libs/MSUFUnitFrames/" not in relative:
                continue
            yield path


def main():
    failures, count = [], 0
    for path in owned_files():
        count += 1
        source = path.read_text(encoding="utf-8-sig")
        for token, offset in tokens(source):
            if token in BANNED:
                line = source.count("\n", 0, offset) + 1
                failures.append(f"{path.relative_to(ROOT).as_posix()}:{line}: {token}")
    if failures:
        raise SystemExit("Forbidden runtime call boundary:\n" + "\n".join(failures))
    print(f"PASS direct error paths: {count} owned Lua files; no protected-call names or aliases")


if __name__ == "__main__":
    main()

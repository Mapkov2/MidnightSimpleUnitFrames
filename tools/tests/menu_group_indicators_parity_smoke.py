"""Replay whole-page observations from the original GroupIndicators builders.

Widget creation ordinals can shift when unrelated previews create fewer frames.
Canonicalise only widget:<digits> identities by first appearance within each case;
retain every row, field and repeated identity when comparing the full structure.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

def observation_receipt(output):
    identities = {}

    def canonical_widget(match):
        token = match.group()
        if token not in identities:
            identities[token] = f"widget:{len(identities) + 1}".encode("ascii")
        return identities[token]

    digest, rows = hashlib.sha256(), 0
    for line in output:
        line = line.replace(b"\r\n", b"\n")
        line = re.sub(rb"widget:[0-9]+", canonical_widget, line)
        digest.update(line)
        rows += line.count(b"\n")
    return {"sha256": digest.hexdigest(), "rows": rows}


def main():
    root, flavor = Path(sys.argv[1]), sys.argv[2]
    lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
    assert lua, "Lua 5.1 executable missing"
    expected = json.loads((root / "tools/fixtures/menu-group-indicators/parity.json").read_text())
    assert expected["baseline"] == "76eb2c69ba22d15201df07eb863241666ed69b63"

    widths, states = (720, 1040), ("default", "general", "edge")
    if len(sys.argv) > 3:
        assert len(sys.argv) == 5, "optional representative requires width and state"
        width, state = int(sys.argv[3]), sys.argv[4]
        assert width in widths and state in states, "unknown representative"
        widths, states = (width,), (state,)
    # Only the replaced page comes from the immutable pre-schema revision. Shared
    # schema, widgets, scenes and client APIs are current on BOTH sides; retain
    # all fields and rows, including the new finite motion surfaces.
    page = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua"
    original = subprocess.check_output(["git", "show", expected["baseline"] + ":" + page], cwd=root)
    assert len(original) > 1000, "authentic group-indicator parent unavailable"
    (root / ".checks").mkdir(exist_ok=True)
    total, cases = 0, 0
    with tempfile.TemporaryDirectory(prefix="indicators-parent-", dir=root / ".checks") as directory:
        proof = Path(directory)
        (proof / "main-page.lua").write_bytes(original)
        (proof / "main-schema.lua").write_bytes((root / "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua").read_bytes())
        for width in widths:
            for state in states:
                key = f"{flavor}-{width}-{state}"
                assert key in expected["cases"], "unregistered full-page case"
                command = [lua, str(root / "tools/tests/menu_group_indicators_parity_world.lua"), str(root), flavor, str(width), state]
                with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors, tempfile.TemporaryFile() as prior, tempfile.TemporaryFile() as prior_errors:
                    candidate = subprocess.Popen(command, cwd=root, stdout=output, stderr=errors)
                    parent = subprocess.Popen(command + [str(proof)], cwd=root, stdout=prior, stderr=prior_errors)
                    candidate_code, parent_code = candidate.wait(), parent.wait()
                    for code, error in ((candidate_code, errors), (parent_code, prior_errors)):
                        error.seek(0)
                        assert code == 0, error.read().decode(errors="replace")
                    output.seek(0)
                    prior.seek(0)
                    actual, baseline = observation_receipt(output), observation_receipt(prior)
                assert actual == baseline, f"{key}: full-page observations differ from authentic parent: {actual} != {baseline}"
                total += actual["rows"]
                cases += 1
    print(f"menu_group_indicators_parity_smoke {flavor}: {cases} exact full-page parent replays, {total} rows")



if __name__ == "__main__":
    main()

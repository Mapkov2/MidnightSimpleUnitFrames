"""tools/load-graph.lua on fixtures: the lock follows the manifests and the invariants hold.

tools/load-graph.lock lists the ordered Lua files each client loads. The gate runs
`lua tools/load-graph.lua --check`; this smoke proves that the check

  * passes on a fresh lock and tells Midnight, WoW Forever (the Mainline TOCs with game type
    camelot) and each Classic client apart,
  * goes red, with the regenerate command in the message, when a Lua file is added to an XML
    manifest, removed, or reordered without regenerating the lock,
  * refuses a graph that breaks an invariant: Mainline or Forever loading Classic-only code
    (Lua or XML, under any game type a Mainline TOC line names), a Classic client loading the
    Retail aura runtime, a file loaded twice by one client.

Every case runs the real tool on a scratch copy of the repository layout.

Usage: python tools/tests/load_graph_lock_smoke.py <repository root>
"""
from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
CORE = "MidnightSimpleUnitFrames"
OPTIONS = "MidnightSimpleUnitFrames_Options"
LOCALES = "MidnightSimpleUnitFrames_Locales"
REGENERATE = "lua tools/load-graph.lua --write"
failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


def find_lua():
    for candidate in (os.environ.get("MSUF_LUA"), shutil.which("lua")):
        if not candidate:
            continue
        run = subprocess.run([candidate, "-e", "io.write(_VERSION)"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if run.returncode == 0 and run.stdout.decode() == "Lua 5.1":
            return candidate
    raise SystemExit("Lua 5.1 is required (set MSUF_LUA or put it on PATH)")


LUA = find_lua()


def write(base, relative, text):
    path = base / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


def toc(entries):
    return "## Interface: 1\n" + "\n".join(entries) + "\n"


def build(base):
    """A small repository layout: the real tool and walker, the real matrix, fixture addons."""
    for relative in ("tools/load-graph.lua", "tools/tests/client_manifest.lua", "tools/classic-client-matrix.tsv"):
        target = base / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / relative, target)
    for suffix in ("Mainline", "Vanilla", "Mists", "TBC"):
        classic = suffix != "Mainline"
        core = ["Game\\Shared\\Initialize.lua", "Embeds\\Elements.xml"]
        if classic:
            core.append("Game\\Classic\\Initialize.lua")
            core.append("Auras3\\Classic.xml")
        else:
            core += ["Auras3\\MSUF_Auras3_DotData.lua",
                     "Game\\Forever\\Pad.lua [AllowLoadGameType camelot]",
                     "Auras3\\AliasData\\Midnight.lua [ExcludeLoadGameType camelot]"]
        write(base, "%s/%s_%s.toc" % (CORE, CORE, suffix), toc(core))
        write(base, "%s/%s_%s.toc" % (OPTIONS, OPTIONS, suffix), toc(["Menu\\Menu.lua"]))
        write(base, "%s/%s_%s.toc" % (LOCALES, LOCALES, suffix), toc(["..\\" + CORE + "\\Locales\\enUS.lua"]))
    write(base, CORE + "/Locales/enUS.lua", "-- shared locale fixture\n")
    write(base, CORE + "/Embeds/Elements.xml",
          '<Ui><!-- <Script file="../Ghost.lua"/> --><Script file="../Elements/Health.lua"/>'
          '<Script file="../Elements/Power.lua"/></Ui>')
    write(base, CORE + "/Auras3/Classic.xml", '<Ui><Script file="../Game/Classic/Auras.lua"/></Ui>')
    for relative in ("Game/Shared/Initialize.lua", "Game/Classic/Initialize.lua", "Game/Classic/Auras.lua",
                     "Game/Forever/Pad.lua", "Auras3/MSUF_Auras3_DotData.lua", "Auras3/AliasData/Midnight.lua",
                     "Elements/Health.lua", "Elements/Power.lua", "Elements/Cast.lua", "Ghost.lua"):
        write(base, CORE + "/" + relative, "-- fixture\n")
    write(base, OPTIONS + "/Menu/Menu.lua", "-- fixture\n")
    write(base, OPTIONS + "/Menu/Extra_Classic.lua", "-- fixture\n")
    write(base, OPTIONS + "/Menu/Panel_Classic.xml", "<Ui/>")
    write(base, CORE + "/Game/Classic/Templates.xml", "<Ui/>")


def run(base, mode):
    done = subprocess.run([LUA, "tools/load-graph.lua", mode], cwd=str(base), stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
    return done.returncode, (done.stdout + done.stderr).decode("utf-8", "replace")


def section(base, name):
    """The paths of one lock section, in order."""
    paths, inside = [], False
    for line in (base / "tools/load-graph.lock").read_text(encoding="utf-8").splitlines():
        if line.startswith("@ "):
            inside = line.startswith("@ " + name + " (")
        elif inside and not line.startswith("#"):
            paths.append(line)
    return paths


def remove_tree(path):
    def make_writable(function, target, _):
        os.chmod(target, stat.S_IWRITE)
        function(target)
    if sys.version_info >= (3, 12):
        shutil.rmtree(str(path), onexc=make_writable)
    else:
        shutil.rmtree(str(path), onerror=make_writable)


def edit(base, relative, before, after):
    path = base / relative
    text = path.read_text(encoding="utf-8")
    assert before in text, (relative, before)
    path.write_text(text.replace(before, after, 1), encoding="utf-8", newline="")


print("load graph lock (tools/load-graph.lua)")
scratch = Path(tempfile.mkdtemp(prefix="msuf-load-graph-smoke-")).resolve()
try:
    base = scratch / "repo"

    # 1. A fresh lock passes and tells the clients apart.
    build(base)
    code, text = run(base, "--check")
    check(code == 1 and "tools/load-graph.lock is missing" in text and REGENERATE in text,
          "a missing lock fails and names the regenerate command")
    code, text = run(base, "--write")
    check(code == 0, "--write succeeds on a clean layout: " + text.strip()[:200])
    code, text = run(base, "--check")
    check(code == 0 and "current" in text, "--check passes on a fresh lock: " + text.strip()[:200])
    midnight = section(base, "Mainline " + CORE)
    forever = section(base, "Forever " + CORE)
    check(midnight == [CORE + "/Game/Shared/Initialize.lua", CORE + "/Elements/Health.lua", CORE + "/Elements/Power.lua",
                       CORE + "/Auras3/MSUF_Auras3_DotData.lua", CORE + "/Auras3/AliasData/Midnight.lua"],
          "Midnight lists its files in TOC order with the XML manifest expanded, minus the camelot line: %s" % midnight)
    check(CORE + "/Game/Forever/Pad.lua" in forever and CORE + "/Auras3/AliasData/Midnight.lua" not in forever,
          "WoW Forever takes the camelot line and skips the Midnight-only line")
    check(CORE + "/Ghost.lua" not in midnight, "a commented-out XML entry is no load")
    check(section(base, "Vanilla " + CORE)[-1] == CORE + "/Game/Classic/Auras.lua",
          "a Classic client expands its own XML manifest")
    check(section(base, "TBC " + OPTIONS) == [OPTIONS + "/Menu/Menu.lua"], "the Options addon has its own section per client")

    # 2. The lock follows the manifests: add, remove, reorder.
    edit(base, CORE + "/Embeds/Elements.xml", '<Script file="../Elements/Power.lua"/>',
         '<Script file="../Elements/Power.lua"/><Script file="../Elements/Cast.lua"/>')
    code, text = run(base, "--check")
    check(code == 1 and "stale" in text and CORE + "/Elements/Cast.lua" in text and REGENERATE in text
          and "Mainline " + CORE in text and "Vanilla " + CORE in text,
          "a Lua file added to an XML manifest turns the check red, naming the file, the clients and the fix")
    code, text = run(base, "--write")
    code, text = run(base, "--check")
    check(code == 0, "regenerating the lock turns the check green again")
    edit(base, CORE + "/Embeds/Elements.xml", '<Script file="../Elements/Power.lua"/><Script file="../Elements/Cast.lua"/>',
         '<Script file="../Elements/Cast.lua"/><Script file="../Elements/Power.lua"/>')
    code, text = run(base, "--check")
    check(code == 1 and "load order changed" in text, "a reordered manifest turns the check red: " + text.strip()[:160])
    run(base, "--write")
    edit(base, CORE + "/Embeds/Elements.xml", '<Script file="../Elements/Health.lua"/>', "")
    code, text = run(base, "--check")
    check(code == 1 and "no longer loads " + CORE + "/Elements/Health.lua" in text,
          "a Lua file removed from a manifest turns the check red")
    run(base, "--write")
    lock = (base / "tools/load-graph.lock").read_bytes()
    (base / "tools/load-graph.lock").write_bytes(lock.replace(b"\n", b"\r\n"))
    code, text = run(base, "--check")
    check(code == 0, "a lock checked out with CRLF line endings still passes")
    remove_tree(base)

    # 3. Invariants: the tool refuses to bless, and --check reports, a graph that breaks one.
    cases = [
        ("stacked TOC conditions", CORE + "/MidnightSimpleUnitFrames_Mainline.toc",
         "Game\\Shared\\Initialize.lua\n",
         "Game\\Shared\\Initialize.lua [AllowLoadTextLocale enUS] [AllowLoadGameType camelot]\n",
         "stacked TOC conditions: only the first is honored"),
        ("Midnight loading a Classic tree", CORE + "/MidnightSimpleUnitFrames_Mainline.toc",
         "Game\\Shared\\Initialize.lua\n", "Game\\Shared\\Initialize.lua\nGame\\Classic\\Initialize.lua\n",
         "Mainline (%s, any game type) loads Classic-only code" % CORE),
        ("Forever alone loading a Classic tree", CORE + "/MidnightSimpleUnitFrames_Mainline.toc",
         "Game\\Forever\\Pad.lua [AllowLoadGameType camelot]", "Game\\Classic\\Auras.lua [AllowLoadGameType camelot]",
         "Mainline (%s, any game type) loads Classic-only code" % CORE),
        ("a line gated to a third game type loading a Classic tree", CORE + "/MidnightSimpleUnitFrames_Mainline.toc",
         "Game\\Shared\\Initialize.lua\n",
         "Game\\Shared\\Initialize.lua\nGame\\Classic\\Initialize.lua [AllowLoadGameType plunderstorm]\n",
         "Mainline (%s, any game type) loads Classic-only code %s/Game/Classic/Initialize.lua" % (CORE, CORE)),
        ("Midnight loading a Classic XML manifest without any Lua", CORE + "/MidnightSimpleUnitFrames_Mainline.toc",
         "Game\\Shared\\Initialize.lua\n", "Game\\Shared\\Initialize.lua\nGame\\Classic\\Templates.xml\n",
         "loads Classic-only code %s/Game/Classic/Templates.xml" % CORE),
        ("Options loading a *_Classic.xml file", OPTIONS + "/MidnightSimpleUnitFrames_Options_Mainline.toc",
         "Menu\\Menu.lua", "Menu\\Menu.lua\nMenu\\Panel_Classic.xml", "loads the Classic-only file"),
        ("Options loading a *_Classic.lua file", OPTIONS + "/MidnightSimpleUnitFrames_Options_Mainline.toc",
         "Menu\\Menu.lua", "Menu\\Menu.lua\nMenu\\Extra_Classic.lua", "loads the Classic-only file"),
        ("Classic loading the Retail aura runtime", CORE + "/MidnightSimpleUnitFrames_Mists.toc",
         "Game\\Classic\\Initialize.lua", "Game\\Classic\\Initialize.lua\nAuras3\\MSUF_Auras3_DotData.lua",
         "loads the Retail aura runtime"),
        ("a file loaded by the core and the Options addon", OPTIONS + "/MidnightSimpleUnitFrames_Options_TBC.toc",
         "Menu\\Menu.lua", "..\\MidnightSimpleUnitFrames\\Game\\Shared\\Initialize.lua", "loads"),
    ]
    for name, relative, before, after, fragment in cases:
        build(base)
        edit(base, relative, before, after)
        code, text = run(base, "--write")
        check(code == 1 and fragment in text and not (base / "tools/load-graph.lock").exists(),
              "--write refuses: %s (%s)" % (name, " ".join(text.split())[:150]))
        remove_tree(base)
    # A file named on two conditional lines is no violation of its own: the walk over every game
    # type meets it twice, the per-client views once each.
    build(base)
    edit(base, CORE + "/MidnightSimpleUnitFrames_Mainline.toc", "Game\\Shared\\Initialize.lua\n",
         "Game\\Shared\\Initialize.lua\nElements\\Cast.lua [AllowLoadGameType plunderstorm]\n"
         "Elements\\Cast.lua [AllowLoadGameType camelot]\n")
    code, text = run(base, "--write")
    check(code == 0, "one file on two game-type lines is accepted: " + text.strip()[:160])
    remove_tree(base)
    build(base)
    edit(base, OPTIONS + "/MidnightSimpleUnitFrames_Options_TBC.toc", "Menu\\Menu.lua",
         "..\\MidnightSimpleUnitFrames\\Game\\Shared\\Initialize.lua")
    code, text = run(base, "--check")
    check(code == 1 and "twice" in text, "a file loaded twice by one client is named: " + text.strip()[:200])
    remove_tree(base)
    build(base)
    run(base, "--write")
    edit(base, CORE + "/MidnightSimpleUnitFrames_Mainline.toc", "Game\\Shared\\Initialize.lua\n",
         "Game\\Shared\\Initialize.lua\nGame\\Classic\\Initialize.lua\n")
    code, text = run(base, "--check")
    check(code == 1 and "Classic-only" in text, "--check also reports an invariant break on an existing lock")
finally:
    remove_tree(scratch)

print()
if failures:
    print("load graph lock smoke: %d FAILED" % len(failures))
    for message in failures:
        print("  " + message)
    sys.exit(1)
print("load graph lock smoke: ok")

"""Resolve each real client manifest and enforce the split runtime providers."""
import csv
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MidnightSimpleUnitFrames"


def check(condition, *detail):
    """Fail explicitly; unlike assert, python -O cannot strip this."""
    if not condition:
        raise SystemExit("Classic load-order contract failed: " + " | ".join(str(part) for part in detail))


def client_suffixes():
    """Every client in tools/classic-client-matrix.tsv, the single list of supported clients."""
    with open(ROOT / "tools/classic-client-matrix.tsv", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    check(rows, "tools/classic-client-matrix.tsv names no clients")
    return [row["Suffix"] for row in rows]


def load_order(toc):
    ordered = []
    active = set()

    def visit(path):
        path = path.resolve()
        check(path.is_file(), f"Missing manifest dependency: {path}")
        check(path not in active, f"Manifest cycle: {path}")
        if path.suffix.lower() == ".lua":
            ordered.append(path.relative_to(ROOT).as_posix())
            return
        active.add(path)
        if path.suffix.lower() == ".xml":
            children = [node.attrib["file"] for node in ET.parse(path).iter()
                        if node.tag.split("}")[-1] in {"Script", "Include"} and "file" in node.attrib]
        else:
            children = [line.strip() for line in path.read_text(encoding="utf-8-sig").splitlines()
                        if line.strip() and not line.lstrip().startswith("#")]
        for child in children:
            visit(path.parent / child.replace("\\", "/"))
        active.remove(path)

    visit(toc)
    return ordered


for client in client_suffixes():
    order = load_order(CORE / f"MidnightSimpleUnitFrames_{client}.toc")
    check(len(order) == len(set(order)), client, "duplicate core Lua load")
    prefix = "MidnightSimpleUnitFrames/"
    for provider, consumer in (
        ("Game/Shared/Initialize.lua", "Kernel/MSUF_Bootstrap.lua"),
        ("Kernel/MSUF_Bootstrap.lua", "Kernel/MSUF_RuntimeContracts.lua"),
        ("State/MSUF_AuraDefaults.lua", "Auras3/MSUF_Auras3_Core.lua"),
        ("Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua"),
        ("Kernel/MSUF_Require.lua", "State/MSUF_Profiles.lua"),
        ("State/MSUF_StateHelpers.lua", "State/MSUF_Profiles.lua"),
        ("State/MSUF_ProfileCodec.lua", "State/MSUF_Profiles.lua"),
        ("State/MSUF_ProfileRuntime.lua", "State/MSUF_Profiles.lua"),
        ("Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua", "Libs/MSUFUnitFrames/MSUF_UF_Core.lua"),
        ("UnitFrames/Engine/MSUF_UF_Shared.lua", "UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua"),
        ("GroupFrames/MSUF_GroupFrames_DB.lua", "GroupFrames/MSUF_GroupFrames_DB_Migrations.lua"),
        ("GroupFrames/MSUF_GroupFrames_DB_Migrations.lua", "UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"),
    ):
        check(order.index(prefix + provider) < order.index(prefix + consumer), client, provider, "must load before", consumer)
    defaults = "State/MSUF_Defaults.lua" if client == "Mainline" else "Game/Classic/State/MSUF_Defaults.lua"
    for provider in ("State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua",
                     "State/Defaults/MSUF_Defaults_Bars.lua", "State/Defaults/MSUF_Defaults_Units.lua"):
        check(order.index(prefix + provider) < order.index(prefix + defaults), client, provider, "must load before", defaults)
    if client != "Mainline":
        check(order.index(prefix + "Game/Classic/Auras/MSUF_Auras3_Preview.lua") < order.index(prefix + "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"),
              client, "Classic aura preview must load before the Classic aura backend")
        check(order.index(prefix + "Game/Classic/Auras/MSUF_Auras3_Compile.lua") < order.index(prefix + "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"),
              client, "Classic aura compiler must load before the Classic aura backend")
    controller = "ClassPower/MSUF_CP_Controller.lua" if client == "Mainline" else "Game/Classic/ClassPower/MSUF_CP_Controller.lua"
    for part in ("Config", "Colors", "Surface"):
        check(order.index(prefix + f"ClassPower/MSUF_CP_Controller_{part}.lua") < order.index(prefix + controller),
              client, f"ClassPower/MSUF_CP_Controller_{part}.lua must load before", controller)
    options = load_order(ROOT / f"MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options_{client}.toc")
    check(len(options) == len(set(options)), client, "duplicate options Lua load")
    menu = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
    if client != "Mainline":
        check(options.index(menu + "MSUF_Menu2_Theme_Classic.lua") < options.index(menu + "MSUF_Menu2_Theme_Tokens.lua") < options.index(menu + "MSUF_Menu2_Theme.lua"), client, "atlas must precede theme capture")
    else:
        check(menu + "MSUF_Menu2_Theme_Classic.lua" not in options, "Mainline must not load the Classic skin")
    check(options.index(menu + "MSUF_Menu2_ColorPicker.lua") < options.index(menu + "MSUF_Menu2_Widgets.lua"),
          client, "Menu2 color picker must load before the widgets")
    if client != "Mainline":
        for helper in ("AuraPreview",):
            check(options.index(menu + "Pages/MSUF_Menu2_" + helper + "_Classic.lua") < options.index(menu + "Pages/MSUF_Menu2_Auras_Classic.lua"),
                  client, helper + "_Classic must load before the Classic aura page")
    suffix = "" if client == "Mainline" else "_Classic"
    workspace = menu + "Pages/MSUF_Menu2_Auras_CustomWorkspace.lua"
    check(options.count(workspace) == 1, client, "shared Custom workspace must load exactly once")
    check(options.index(menu + "Pages/MSUF_Menu2_Auras" + suffix + ".lua") < options.index(workspace),
          client, "the aura page must load before the shared Custom workspace")
    for helper in ("AuraSettings", "AuraControls"):
        check(options.index(menu + f"Pages/MSUF_Menu2_{helper}.lua") < options.index(menu + f"Pages/MSUF_Menu2_Auras{suffix}.lua"),
              client, helper, "must load before the aura page")
    for provider, consumer in (
        ("Pages/MSUF_Menu2_Group_SpellModel.lua", "Pages/MSUF_Menu2_GroupAuras.lua"),
        ("Pages/MSUF_Menu2_GlobalCastbars_Preview.lua", "Pages/MSUF_Menu2_GlobalCastbars.lua"),
        ("Pages/MSUF_Menu2_AdvancedColors_Meta.lua", "Pages/MSUF_Menu2_AdvancedColors.lua"),
        ("Preview/MSUF_Menu2_ClassPowerPreview_Lifecycle.lua", "Preview/MSUF_Menu2_ClassPowerPreview.lua"),
        ("Preview/MSUF_Menu2_ClassPowerPreview_Interaction.lua", "Preview/MSUF_Menu2_ClassPowerPreview.lua"),
    ):
        check(options.index(menu + provider) < options.index(menu + consumer), client, provider, "must load before", consumer)
    for part in ("Group", "Resources", "Context"):
        check(menu + f"Pages/MSUF_Menu2_AdvancedColors_{part}.lua" in options, client, f"AdvancedColors_{part} is not loaded")
    for helper in ("Handles", "Chrome"):
        check(options.index(menu + f"Preview/MSUF_Menu2_UnitPreview_View_{helper}.lua") < options.index(menu + f"Preview/MSUF_Menu2_UnitPreview_View{suffix}.lua"),
              client, f"UnitPreview_View_{helper} must load before the unit preview view")
    check(order[-1] == prefix + "Kernel/MSUF_RuntimeContracts.lua", client, "Kernel/MSUF_RuntimeContracts.lua must load last")
    print(f"PASS {client}: split state, unit catalogue, group migrations and final runtime contracts")

for path in (ROOT / "MidnightSimpleUnitFrames_Options/Shell/Menu2").rglob("*_Classic.lua"):
    source = path.read_text(encoding="utf-8-sig")
    for removed in ("M.CallIf(", "MSUF_SetStatusIconStyleUseMidnight"):
        check(removed not in source, path, removed)
print("PASS Classic pages: removed shared dispatch and nonexistent status setter are not referenced")

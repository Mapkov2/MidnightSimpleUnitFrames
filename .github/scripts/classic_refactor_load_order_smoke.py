"""Resolve each real client manifest and enforce the split runtime providers."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MidnightSimpleUnitFrames"


def load_order(toc):
    ordered = []
    active = set()

    def visit(path):
        path = path.resolve()
        assert path.is_file(), f"Missing manifest dependency: {path}"
        assert path not in active, f"Manifest cycle: {path}"
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


for client in ("Mainline", "Vanilla", "Mists", "TBC"):
    order = load_order(CORE / f"MidnightSimpleUnitFrames_{client}.toc")
    prefix = "MidnightSimpleUnitFrames/"
    for provider, consumer in (
        ("Kernel/MSUF_Require.lua", "State/MSUF_Profiles.lua"),
        ("State/MSUF_StateHelpers.lua", "State/MSUF_Profiles.lua"),
        ("State/MSUF_ProfileCodec.lua", "State/MSUF_Profiles.lua"),
        ("State/MSUF_ProfileRuntime.lua", "State/MSUF_Profiles.lua"),
        ("Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua", "Libs/MSUFUnitFrames/MSUF_UF_Core.lua"),
        ("UnitFrames/Engine/MSUF_UF_Shared.lua", "UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua"),
        ("GroupFrames/MSUF_GroupFrames_DB.lua", "GroupFrames/MSUF_GroupFrames_DB_Migrations.lua"),
        ("GroupFrames/MSUF_GroupFrames_DB_Migrations.lua", "UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"),
    ):
        assert order.index(prefix + provider) < order.index(prefix + consumer), (client, provider, consumer)
    controller = "ClassPower/MSUF_CP_Controller.lua" if client == "Mainline" else "Game/Classic/ClassPower/MSUF_CP_Controller.lua"
    for part in ("Config", "Colors", "Surface"):
        assert order.index(prefix + f"ClassPower/MSUF_CP_Controller_{part}.lua") < order.index(prefix + controller)
    options = load_order(ROOT / f"MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options_{client}.toc")
    menu = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
    suffix = "" if client == "Mainline" else "_Classic"
    for helper in ("AuraSettings", "AuraControls"):
        assert options.index(menu + f"Pages/MSUF_Menu2_{helper}.lua") < options.index(menu + f"Pages/MSUF_Menu2_Auras{suffix}.lua")
    for provider, consumer in (
        ("Pages/MSUF_Menu2_Group_SpellModel.lua", "Pages/MSUF_Menu2_GroupAuras.lua"),
        ("Pages/MSUF_Menu2_GlobalCastbars_Preview.lua", "Pages/MSUF_Menu2_GlobalCastbars.lua"),
        ("Pages/MSUF_Menu2_AdvancedColors_Meta.lua", "Pages/MSUF_Menu2_AdvancedColors.lua"),
        ("Preview/MSUF_Menu2_ClassPowerPreview_Lifecycle.lua", "Preview/MSUF_Menu2_ClassPowerPreview.lua"),
        ("Preview/MSUF_Menu2_ClassPowerPreview_Interaction.lua", "Preview/MSUF_Menu2_ClassPowerPreview.lua"),
    ):
        assert options.index(menu + provider) < options.index(menu + consumer), (client, provider, consumer)
    for part in ("Group", "Resources", "Context"):
        assert menu + f"Pages/MSUF_Menu2_AdvancedColors_{part}.lua" in options, client
    for helper in ("Handles", "Chrome"):
        assert options.index(menu + f"Preview/MSUF_Menu2_UnitPreview_View_{helper}.lua") < options.index(menu + f"Preview/MSUF_Menu2_UnitPreview_View{suffix}.lua")
    assert order[-1] == prefix + "Kernel/MSUF_RuntimeContracts.lua", client
    print(f"PASS {client}: split state, unit catalogue, group migrations and final runtime contracts")

for path in (ROOT / "MidnightSimpleUnitFrames_Options/Shell/Menu2").rglob("*_Classic.lua"):
    source = path.read_text(encoding="utf-8-sig")
    for removed in ("M.CallIf(", "MSUF_SetStatusIconStyleUseMidnight"):
        assert removed not in source, (path, removed)
print("PASS Classic pages: removed shared dispatch and nonexistent status setter are not referenced")

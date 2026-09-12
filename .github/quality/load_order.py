"""Verify the actual TOC/XML order of the shared refactor contracts."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
ordered = []


def visit(path):
    path = path.resolve()
    if path.suffix.lower() == ".lua":
        ordered.append(path)
        return
    source = path.read_text(encoding="utf-8-sig")
    if path.suffix.lower() == ".xml":
        references = re.findall(r'\bfile\s*=\s*"([^"]+\.(?:lua|xml))"', source, re.I)
    else:
        references = [line.strip() for line in source.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    for reference in references:
        visit(path.parent / reference.replace("\\", "/"))


for addon in ("MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options"):
    visit(ROOT / addon / (addon + ".toc"))

core = "MidnightSimpleUnitFrames/"
menu = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
contracts = {
    "MSUF_ComposeFontFlags": core + "Kernel/MSUF_Libs.lua",
    "MSUF_NormalizeFrameStrata": core + "Kernel/MSUF_Util.lua",
    "MSUF_NormalizeAuraDebuffTypeBorderMode": core + "Auras3/MSUF_Auras3_Core.lua",
    "MSUF_NormalizeLegacyDispelBorderMode": core + "Auras3/MSUF_Auras3_Core.lua",
    "MSUF_AuraSyncFrameStrata": core + "Auras3/MSUF_Auras3_Core.lua",
    "MSUF_UF_PointFraction": core + "UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_FrameRectToUI": core + "Kernel/MSUF_Util.lua",
    "RequestGroupGeometryApply": core + "Kernel/MSUF_Util.lua",
    "M.ControlMeta": menu + "MSUF_Menu2_ControlCatalog.lua",
    "M.RegisterControlMetadata": menu + "MSUF_Menu2_ControlCatalog.lua",
    "M.ProfileSystemNeedsInit": menu + "MSUF_Menu2_Bindings.lua",
    "ParseHexColor": menu + "MSUF_Menu2_Widgets.lua",
    "CreateNestedAuraBuilder": menu + "MSUF_Menu2_Widgets.lua",
    "M.AuraSettings": menu + "Pages/MSUF_Menu2_AuraSettings.lua",
    "M.AuraControls": menu + "Pages/MSUF_Menu2_AuraControls.lua",
    "M.AuraGroupSettings": menu + "Pages/MSUF_Menu2_Auras_Group.lua",
    "M.NormalizeControlPath": menu + "MSUF_Menu2_ControlCatalog.lua",
    "M.PortableControlToken": menu + "MSUF_Menu2_ControlCatalog.lua",
    "M.AuraCatalogToken": menu + "MSUF_Menu2_ControlCatalog.lua",
    "M.GroupAuraSettingKeys": menu + "MSUF_Menu2_ControlCatalog.lua",
    "M.TrimText": menu + "MSUF_Menu2_Support.lua",
    "M.PlayerDisplayName": menu + "MSUF_Menu2_Support.lua",
    "W.SetTileVisual": menu + "MSUF_Menu2_Widgets.lua",
    "W.ToggleBadge": menu + "MSUF_Menu2_Widgets.lua",
    "W.ThemedControlCard": menu + "MSUF_Menu2_Widgets.lua",
    "M.Widgets.SetTextLayout": menu + "MSUF_Menu2_Widgets.lua",
    "M.Widgets.ResolveContextColorOption": menu + "MSUF_Menu2_Widgets.lua",
    "W.RegisterSearchObject": menu + "MSUF_Menu2_Widgets.lua",
    "PreviewHelpers.ExactPreviewDelta": menu + "MSUF_Menu2_PreviewHelpers.lua",
    "PreviewHelpers.HealthBackgroundColorMode": menu + "MSUF_Menu2_PreviewHelpers.lua",
    "PreviewHelpers.ReadPreviewBarsBool": menu + "MSUF_Menu2_PreviewHelpers.lua",
}
contracts.update({
    "MSUF_IsGroupUnitToken": core + "Kernel/MSUF_Util.lua",
    "MSUF_NormalizeProfileDefaults": core + "State/MSUF_Defaults.lua",
    "M.CreateGuidedCopyOpener": menu + "MSUF_Menu2_Support.lua",
    "M.DisposePageHeader": menu + "MSUF_Menu2_Window_PageEntry.lua",
    "MSUF_AuraButtonAnchor": "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua",
    "MSUF_AuraTableHasAnyKey": core + "Auras3/MSUF_Auras3_Core.lua",
    "MSUF_GF_CopySpellConfig": core + "UnitFrames/Engine/Group/MSUF_UF_Group_SpellRegistry.lua",
    "MSUF_GlobalCooldownAnchorEnabled": core + "Kernel/MSUF_Util.lua",
    "MSUF_AuraAnchorOffset": "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua",
    "MSUF_AuraReadParentFrameStrata": "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua",
    "MSUF_AuraPaddingInset": "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua",
    "MSUF_AuraSpellIDFromKey": "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua",
    "MSUF_NormalizeDispelBorderTrigger": "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua",
    "MSUF_CastbarFrameInset": "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua",
    "MSUF_EnsureCastbarGeneralDB": "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua",
    "MSUF_CastTimeUnitKey": "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua",
    "MSUF_NormalizeCastbarIconPosition": "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarVisuals.lua",
    "MSUF_NormalizeCastbarTruncate": "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarVisuals.lua",
    "MSUF_NormalizeCastbarTextPosition": "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarVisuals.lua",
    "MSUF_NormalizeCastbarTextJustify": "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarVisuals.lua",
    "MSUF_GetSharedMedia": "MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua",
    "MSUF_RoundOffset": "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua",
    "MSUF_GetGeneralDB": "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua",
    "MSUF_CooldownAnchorSupported": "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua",
    "MSUF_IsPlayerInCombat": "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua",
    "MSUF_ClampRoundedEdgeSize": "MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua",
    "MSUF_UF_ShapeOutlineAlpha": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_NormalizeShapeAlign": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_NormalizePlayerHPShape": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_OutlineModeEnabled": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_MaskHas": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_ClampBoxAxis": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_ClampAnchorOffsetOnScreen": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_ScheduleApplyCommit": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_NormalizeClassPowerShape": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_UF_NormalizeDetachedPowerShape": "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua",
    "MSUF_NormalizeRaidManagerMode": "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua"
})

sources = {path: path.read_text(encoding="utf-8-sig") for path in ordered}
for symbol, owner in contracts.items():
    owner_path = (ROOT / owner).resolve()
    owner_index = ordered.index(owner_path)
    consumers = [path for path in ordered if path != owner_path and symbol in sources[path]]
    assert consumers, (symbol, "has no loaded consumer")
    assert all(ordered.index(path) > owner_index for path in consumers), (symbol, "consumer loads before owner")
print(f"PASS load order: {len(contracts)} shared contracts in actual TOC/XML order")

# Window/API callbacks are declared before the lazy preview module, but invoked
# only after Options finishes loading. Its lifecycle hook must exist by then;
# classpower_resume_smoke.lua also checks that no page build is needed.
preview_owner = (ROOT / (menu + "Preview/MSUF_Menu2_ClassPowerPreview_Lifecycle.lua")).resolve()
options_ready = (ROOT / "MidnightSimpleUnitFrames_Options/MSUF_OptionsLOD_Finalize.lua").resolve()
assert ordered.index(preview_owner) < ordered.index(options_ready), "Class Resources hook loads after Options ready"
print("PASS deferred lifecycle: Class Resources module before Options ready")

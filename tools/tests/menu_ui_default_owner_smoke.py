"""Cold declarations use one UI owner and the existing text binding adapter."""
import sys
from pathlib import Path

root = Path(sys.argv[1])
menu = root / "MidnightSimpleUnitFrames_Options/Shell/Menu2"
schema = (menu / "MSUF_Menu2_ControlSchema.lua").read_text(encoding="utf-8-sig")
support = (menu / "MSUF_Menu2_Support.lua").read_text(encoding="utf-8-sig")
extra = (root / "MidnightSimpleUnitFrames/ClassPower/MSUF_CP_ExtraAuras.lua").read_text(encoding="utf-8-sig")
assert "NormalizeDefaults" not in schema, "runtime normalization cannot own legacy page fallbacks"
assert "local UI_DEFAULTS =" in schema and "Schema.MarkDefaults =" in schema
assert 'local EXTRA_DEFAULTS = MSUF.CPBuilders.ExtraAuraDefaults' in schema
assert "DEFAULTS." not in extra.split("-- Bound by", 1)[1], "hot default table read returned"
assert "local DEFAULT_WARN_SECONDS, DEFAULT_TEXT =" in extra
assert "local DEFAULT_WIDTH, DEFAULT_HEIGHT =" in extra and "local DEFAULT_OFFSET_Y =" in extra
adapter = support.split("function M.BindTextInputWidget", 1)[1].split("function M.BindTextInputAt", 1)[0]
assert 'function() return getValue() or "" end' in adapter, "existing text getter normalization lost"
assert 'function(v) setValue(v or "") end' in adapter, "existing text setter normalization lost"
assert "return M.BindTextInputWidget(ctx, widget" in support.split("function M.BindTextInputAt", 1)[1]
assert "if spec.textAdapter then M.BindTextInputWidget" in schema, "renderer bypassed existing adapter"
for name in ("AdvancedGameplay", "ResourceExtras", "UnitAlpha", "UnitRangeFade", "SwingTimers"):
    page = (menu / f"Pages/MSUF_Menu2_{name}.lua").read_text(encoding="utf-8-sig")
    assert "NormalizeDefaults" not in page and "ExtraAuraDefaults" not in page, name
    if name == "SwingTimers":
        assert "row.textAdapter = true" in page, "actual attack inputs bypass adapter"
    else:
        assert "Schema.Default(" in page, name
assert "local MARK_DEFAULTS=Schema.MarkDefaults" in (menu / "Pages/MSUF_Menu2_ResourceExtras.lua").read_text()
print("menu_ui_default_owner_smoke: legacy UI owner, scalar runtime defaults and existing getter adapter OK")

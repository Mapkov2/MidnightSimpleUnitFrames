-- Regression coverage for group power bars reaching unit-frame parity: the
-- border, embed/detach geometry and fill direction the unit Resource Bar page
-- exposes must all compile into the shared power spec. Colour and bar art stay
-- global on both sides, so they are asserted as inherited, not per-scope.
--
-- The colour-domain half also pins the cheap in-place DIRTY_COLOR lane: a field
-- added to CompileSpecUncached but missed in RefreshColorDomain would silently
-- stale until a full cache drop.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end
_G.MSUF_GetBarTexture = function() return "Interface\\Shared\\Health" end

_G.MSUF_DB = {
    general = {
        barMode = "class",
        powerColorOverrides = {
            MANA = { r = 0.11, g = 0.22, b = 0.33 },
        },
        classPowerColorOverrides = {
            MANA = { r = 1, g = 1, b = 1 },
            RAGE = { r = 0.9, g = 0.1, b = 0.1 },
        },
        barOutlineColorR = 0.25,
        barOutlineColorG = 0.5,
        barOutlineColorB = 0.75,
        barOutlineColorA = 0.8,
    },
    gf_party = {},
}

local MSUF = { UF = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local GF = MSUF.GF
local conf = _G.MSUF_DB.gf_party

local function Recompile()
    GF.InvalidateCompiledSpecs("party")
    return GF.CompileSpec("party", nil, "party1").power
end

local function RefreshColors()
    Check(GF.RefreshCompiledSpecDomains("party", GF.DIRTY_COLOR) == true,
        "group colour refresh did not accept the party spec")
    return GF.CompileSpec("party", nil, "party1").power
end

-- 1. Defaults: embedded, attached, no border, art and colour inherited.
local power = Recompile()
Check(power.embed == true, "group power bars must default to embedded")
Check(power.detached == false, "group power bars must default to attached")
Check(power.borderEnabled == false, "power border must default to off")
Check(power.mode == "type", "default power colour mode should be per-resource type")
Check(power.r == nil and power.g == nil and power.b == nil,
    "type mode must leave r/g/b nil so SetColor keeps the dynamic lookup")
Check(power.texture == "Interface\\Shared\\Health",
    "the power bar must follow the shared group bar texture")

-- 2. Per-token overrides come from the account-wide colour tables, with the
--    class-power table filling only the tokens the power table did not set.
Check(type(power.colors) == "table", "power spec must carry a colour override table")
Check(power.colors.MANA and power.colors.MANA.r == 0.11,
    "powerColorOverrides did not reach the group power spec")
Check(power.colors.RAGE and power.colors.RAGE.r == 0.9,
    "classPowerColorOverrides did not backfill missing tokens")

-- 3. Constant-colour modes must publish concrete r/g/b, which is what lets the
--    element skip its power-type sampling entirely. This was compiled as a bare
--    mode string with no colour before, so those modes silently did nothing.
conf.powerColorMode = "unified"
_G.MSUF_DB.general.unifiedBarR = 0.7
_G.MSUF_DB.general.unifiedBarG = 0.8
_G.MSUF_DB.general.unifiedBarB = 0.9
power = Recompile()
Check(power.mode == "unified", "unified power colour mode did not compile")
Check(power.r == 0.7 and power.g == 0.8 and power.b == 0.9,
    "unified power mode did not publish a concrete colour")

-- 4. Border, mirroring the unit compiler's 0..10 clamp and shared outline colour.
conf.powerBarBorderEnabled = true
conf.powerBarBorderThickness = 40
conf.reverseFill = true
power = Recompile()
Check(power.borderEnabled == true, "power border toggle did not compile")
Check(power.borderThickness == 10, "power border thickness must clamp to the 0..10 band")
Check(power.borderR == 0.25 and power.borderA == 0.8,
    "power border colour must follow the shared bar outline colour")
Check(power.reverse == true, "power fill direction must follow the health reverse setting")

-- A zero thickness disables the border even with the toggle on, so the element
-- never allocates its border frame and textures for an invisible edge.
conf.powerBarBorderThickness = 0
Check(Recompile().borderEnabled == false, "zero thickness must disable the power border")
conf.powerBarBorderThickness = 2

-- 5. Embed off keeps the bar attached but below the frame; the health bar then
--    stops being inset, which is what Health.Layout keys off.
conf.embedPowerBarIntoHealth = false
power = Recompile()
Check(power.embed == false and power.detached == false,
    "clearing embed must not detach the bar")

-- 6. Detached geometry, matching the fields a non-Player unit frame gets.
conf.powerBarDetached = true
conf.detachedPowerBarOffsetX = 12
conf.detachedPowerBarOffsetY = -20
conf.detachedPowerBarWidth = 140
conf.detachedPowerBarHeight = 9
conf.detachedPowerBarFrameLevelOffset = 11
conf.detachedPowerBarTextOnBar = true
power = Recompile()
Check(power.detached == true, "detached power bar did not compile")
Check(power.detachedX == 12 and power.detachedY == -20, "detached offsets did not compile")
Check(power.detachedWidth == 140 and power.detachedHeight == 9, "detached size did not compile")
Check(power.detachedWidthExplicit == 140, "an explicitly configured detached width must stay authoritative")
Check(power.detachedLevel == 11, "detached draw order did not compile")
Check(power.textOnDetached == true, "text-on-detached-bar did not compile")
-- Class Resource sync/anchor and the shaped bars are Player-only on the unit
-- page, so group members must stay on the plain rectangular bar.
Check(power.shape == "BAR", "group power bars must not take the Player-only shapes")
Check(power.detachedSyncClass == false and power.detachedAnchorClass == false,
    "group power bars must not opt into Class Resource width sync or anchoring")

-- An unset detached width falls back to the frame width rather than to zero.
conf.detachedPowerBarWidth = 0
power = Recompile()
Check(power.detachedWidth > 0, "an unset detached width must fall back to the frame width")
Check(power.detachedWidthExplicit == nil, "an unset detached width must not report as explicit")

-- 7. The in-place colour lane must refresh the colour domain without a cache
--    drop, and must not disturb the geometry the last full compile produced.
_G.MSUF_DB.general.unifiedBarR = 0.15
_G.MSUF_DB.general.powerColorOverrides.MANA = { r = 0.05, g = 0.06, b = 0.07 }
conf.powerBarBorderEnabled = false
conf.reverseFill = false
power = RefreshColors()
Check(power.r == 0.15, "colour refresh did not update the unified power colour")
Check(power.colors.MANA.r == 0.05, "colour refresh did not update per-token power colours")
Check(power.borderEnabled == false, "colour refresh did not update the power border toggle")
Check(power.reverse == false, "colour refresh did not update the power fill direction")
Check(power.detached == true and power.detachedX == 12,
    "colour refresh must leave detached geometry alone")

-- 8. Per-frame specs inherit the whole power domain while role gating keeps
--    ownership of enabled/height, so the fields cost one shallow copy per bump.
local frame = {}
local frameSpec = GF.CompileSpec("party", frame, "party1")
Check(frameSpec.power.detached == true, "per-frame spec did not inherit detached placement")
Check(frameSpec.power.colors.MANA.r == 0.05, "per-frame spec did not inherit power colour overrides")
Check(conf.powerShowDamager ~= true, "smoke expects the default DPS power toggle to be off")
Check(frameSpec.power.enabled == false and frameSpec.power.height == 0,
    "role-gated power height must survive the visual-domain copy")
conf.powerShowDamager = true
frameSpec = GF.CompileSpec("party", frame, "party1")
Check(frameSpec.power.enabled == true and frameSpec.power.height > 0,
    "enabling the DPS role did not restore the per-frame power height")
Check(frameSpec.power.mode == "unified", "role gating must not clobber the inherited colour mode")

_G.MSUF_DB.general.unifiedBarR = 0.42
Check(GF.RefreshCompiledSpecDomains("party", GF.DIRTY_COLOR) == true, "second colour refresh was rejected")
frameSpec = GF.CompileSpec("party", frame, "party1")
Check(frameSpec.power.r == 0.42,
    "per-frame power spec did not pick up a colour refresh through the visual revision")

-- 9. Preview parity contract: the group preview mock must honour the same
--    three placements Power.Apply uses instead of hard-anchoring the bar
--    embedded, and only the embedded bar may inset the mock health bar.
local renderPath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua"
local renderFile = assert(io.open(renderPath, "rb"), "group preview renderer missing")
local render = renderFile:read("*a"):gsub("\r\n", "\n")
renderFile:close()
Check(render:find('if powerDetached then', 1, true), "group preview lost the detached power placement branch")
Check(render:find('elseif not powerEmbed then', 1, true), "group preview lost the attached-below (embed off) placement branch")
Check(render:find('mock._power:SetPoint("TOP", mock, "BOTTOM"', 1, true),
    "group preview detached bar must anchor TOP to frame BOTTOM like LayoutDetached")
Check(render:find('powerInsetH > 0 and (powerInsetH + inset) or inset', 1, true),
    "group preview health inset must key off the embedded-only powerInsetH")
Check(render:find('powerH > 0 and LayerOn("power")', 1, true),
    "group preview power bar must be gated by its preview layer")
Check(render:find('power = powerAvailable', 1, true),
    "group preview must publish role-gated power layer availability")
local nativePath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua"
local nativeFile = assert(io.open(nativePath, "rb"), "group preview native missing")
local native = nativeFile:read("*a"):gsub("\r\n", "\n")
nativeFile:close()
Check(native:find('{ "Power", { 0.30, 0.62, 0.98 }, "power", "power" }', 1, true),
    "group preview LAYERS panel lost its Power entry")
Check(native:find("local function PreviewRole(kind)", 1, true)
    and native:find("M.gfPreviewRoles[kind]", 1, true),
    "group preview does not retain an independent simulated role per scope")
Check(native:find('btn:SetSize(92, 22)', 1, true)
    and native:find('DAMAGER = "DPS"', 1, true),
    "group preview lacks the visible Tank/Healer/DPS member-role selector")
Check(native:find("if box._previewRoleButton then box._previewRoleButton:Hide() end", 1, true)
    and native:find("if box._previewRoleButton then box._previewRoleButton:Show() end", 1, true),
    "group preview member-role selector ignores compact/pinned tool visibility")
Check(native:find("gf.GetEffectivePowerHeight(kind, nil, previewRole, conf)", 1, true),
    "group preview power visibility still uses a fixed member role")
Check(render:find("gf.GetRoleTexture(kind, scene.previewRole", 1, true),
    "group preview role icon does not follow the selected simulated role")
local menuPath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua"
local menuFile = assert(io.open(menuPath, "rb"), "group Resource Bar menu missing")
local menu = menuFile:read("*a"):gsub("\r\n", "\n")
menuFile:close()
Check(menu:find('FocusPreviewRole(showTank, "TANK")', 1, true)
    and menu:find('FocusPreviewRole(showHealer, "HEALER")', 1, true)
    and menu:find('FocusPreviewRole(showDamager, "DAMAGER")', 1, true),
    "role visibility toggles do not focus their matching preview member role")

-- 10. Interactive handle contract: the resource bar handle must exist with the
--     full drag/nudge/exact write dispatch, and the render must lock it while
--     the bar is embedded (only the detached bar owns free offsets at runtime).
local handlesPath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua"
local handlesFile = assert(io.open(handlesPath, "rb"), "group preview handles missing")
local handles = handlesFile:read("*a"):gsub("\r\n", "\n")
handlesFile:close()
Check(handles:find('CreatePreviewHandle("powerBar", "power"', 1, true),
    "resource bar preview handle is no longer created")
Check(handles:find('powerBarHandle._cfgPower = true', 1, true),
    "resource bar handle lost its _cfgPower dispatch tag")
Check(handles:find('conf.detachedPowerBarOffsetX = OffsetToConfig(offX or 0, scale)', 1, true),
    "drag write-back to detachedPowerBarOffsetX/Y is gone from SaveHandlePosition")
Check(handles:find('conf.detachedPowerBarOffsetX = cfgX', 1, true),
    "arrow-key nudge no longer writes the detached power offsets")
Check(handles:find('conf.detachedPowerBarOffsetX, conf.detachedPowerBarOffsetY = x, y', 1, true),
    "exact-nudge write no longer covers the resource bar handle")
Check(handles:find('powerBarHandle = powerBarHandle', 1, true),
    "resource bar handle is not exported to the render deps")
Check(render:find('powerBarHandle._locked = not powerDetached', 1, true),
    "render no longer locks the handle while the bar is embedded")
Check(render:find('mock._power:SetPoint("TOP", powerBarHandle, "TOP", 0, 0)', 1, true),
    "detached bar no longer rides the handle during drags")
Check(native:find('elseif handle._cfgPower then', 1, true),
    "HandleOffsets lost the resource bar branch (arrow-key nudges would break)")

print("PASS group power parity: border, embed/detach geometry, colour domain and preview placements")

-- Texture selections repaint owned border sinks without rebuilding other surfaces.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true })
local M, env, UF, GF = mw.M, mw.env, mw.core.UF, mw.core.GF
local dropdown
local Dropdown = M.Widgets.Dropdown
M.Widgets.Dropdown = function(parent, label, ...)
    local result = Dropdown(parent, label, ...)
    if label == "Outline style" then dropdown = result end
    return result
end
mw:Select("opt_bars")
M.Widgets.EnsureSectionContent(assert(M.cache.opt_bars.sections.bars_outline))
mw:RunTimers()
assert(dropdown and dropdown._msuf2OnValueChanged, "real outline dropdown did not bind")
local db, borders = M.EnsureDB(), UF.elements.Borders
local frames, paints = {}, {}
for _, unit in ipairs({ "target", "player" }) do
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(180, 40)
    frame.MSUFUnitKey, frame.unit = unit, unit
    frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
    frame.hpBar:SetSize(180, 40)
    frame.targetPowerBar = env.CreateFrame("StatusBar", nil, frame)
    frame.targetPowerBar:SetSize(180, 8)
    UF.frames[unit], UF.frameList[#UF.frameList + 1] = frame, frame
    frames[unit], paints[unit] = frame, 0
end
local function Paint(frame, spec)
    UF.SetFrameSpec(frame, spec)
    borders.Apply(frame, spec)
    borders.Update(frame, spec, "MSUF_FORCE_UPDATE")
    paints[frame.MSUFUnitKey] = paints[frame.MSUFUnitKey] + 1
end
UF.ApplyElementsToFrame = function(frame, names, spec)
    UF.SetFrameSpec(frame, spec)
    for _, name in ipairs(names) do if name == "Borders" then Paint(frame, spec) end end
end
local roundedPasses, borderPasses, groupPasses = 0, 0, {}
local Rounded, RefreshBorders, RefreshGroup = env.MSUF_ApplyRoundedUnitframes,
    env.MSUF_ApplyBarOutlineThickness_All, GF.RefreshVisuals
env.MSUF_ApplyRoundedUnitframes = function(...)
    roundedPasses = roundedPasses + 1
    return Rounded(...)
end
env.MSUF_ApplyBarOutlineThickness_All = function(...)
    borderPasses = borderPasses + 1
    return RefreshBorders(...)
end
GF.RefreshVisuals = function(kind, ...)
    local key = kind or "all"
    groupPasses[key] = (groupPasses[key] or 0) + 1
    return RefreshGroup(kind, ...)
end
local function GroupTotal()
    local sum = 0
    for _, count in pairs(groupPasses) do sum = sum + count end
    return sum
end
local function ExpectStyle(frame, style, shape)
    local cfg = assert(frame.MSUFSpec.border)
    local mode, key, texture = mw.core.BorderStyles.ResolveFrame(style)
    if style == "" then mode, key, texture = nil, nil, nil end
    assert(cfg.textureMode == mode and cfg.textureKey == key and cfg.texture == texture, "compiled outline style stale")
    if cfg.textureMode and shape ~= "square" then
        assert(frame._msufRUFModernBorderSuppressed, "shaped border sink was not active")
        assert(frame._msufRoundedBorderStyledRings, "shaped border pool missing")
    end
    assert(frame._msufBorderShown, "outline became hidden after selection")
end
local styles = { "", "BORDER:GLOW", "BORDER:SHADOW", "BORDER:BLIZZARD", "BORDER:DIALOG", "BORDER:ACHIEVEMENT", "Blizzard" }
local cases, totalWork, peakWork = 0, 0, 0
for _, shape in ipairs({ "square", "rounded", "slanted" }) do
    db.bars.roundedFramesEnabled, db.bars.slantedBarsEnabled = shape == "rounded", shape == "slanted"
    db.bars.roundedUnitFrames, db.bars.slantedUnitFrames = true, true
    db.bars.barOutlineThickness = 2
    for _, unit in ipairs({ "target", "player" }) do
        db[unit].frameBarShape = shape:upper()
        db[unit].barOutlineThickness = 2
    end
    for _, scope in ipairs({ "shared", "target", "gf_party", "gf_raid" }) do
        db.general.hpPowerTextSelectedKey = scope
        db.target.hlOverride = scope == "target"
        M.GlobalPage.ScopeSetOverride("gf_party", "hlOverride", scope == "gf_party")
        M.GlobalPage.ScopeSetOverride("gf_raid", "hlOverride", scope == "gf_raid")
        for _, style in ipairs(styles) do
            local oldStyle = style == "BORDER:GLOW" and "BORDER:SHADOW" or "BORDER:GLOW"
            db.bars.barOutlineTexture = oldStyle
            for _, key in ipairs({ "target", "gf_party", "gf_raid", "gf_mythicraid" }) do
                db[key].barOutlineTexture = oldStyle
            end
            env.MSUF_ApplyRoundedUnitframes()
            for unit, frame in pairs(frames) do Paint(frame, UF.Config.RefreshUnit(unit)) end
            mw:RunTimers()
            local full, border, group = roundedPasses, borderPasses, GroupTotal()
            local target, player = paints.target, paints.player
            local instructions = 0
            debug.sethook(function() instructions = instructions + 100 end, "", 100)
            dropdown._msuf2OnValueChanged(style)
            assert(borderPasses == border and roundedPasses == full, "selection painted before deferred flush")
            mw:RunTimers()
            debug.sethook()
            totalWork, peakWork = totalWork + instructions, math.max(peakWork, instructions)
            assert(roundedPasses == full, "outline texture selection rebuilt all rounded surfaces")
            if scope == "shared" or scope == "target" then
                assert(borderPasses == border + 1, "selection did not use one border pass")
                assert(paints.target == target + 1, "target did not repaint exactly once")
                ExpectStyle(frames.target, style, shape)
                assert(paints.player == player + (scope == "shared" and 1 or 0), "selection ignored unit scope")
            else
                assert(borderPasses == border and paints.target == target and paints.player == player,
                    "group selection repainted individual unit borders")
            end
            local expectedGroups = scope == "shared" and 1 or scope == "gf_raid" and 2 or scope == "gf_party" and 1 or 0
            assert(GroupTotal() == group + expectedGroups, "selection repeated or lost group dirty passes")
            local after = borderPasses
            dropdown._msuf2OnValueChanged(style)
            mw:RunTimers()
            assert(borderPasses == after and roundedPasses == full, "same selection repeated apply work")
            cases = cases + 1
        end
    end
end

-- A burst paints the last texture once. A pending flush defers through combat.
db.general.hpPowerTextSelectedKey, db.target.hlOverride = "target", true
local border, full = borderPasses, roundedPasses
dropdown._msuf2OnValueChanged("BORDER:GLOW")
dropdown._msuf2OnValueChanged("Blizzard")
dropdown._msuf2OnValueChanged("BORDER:SHADOW")
mw.world:EnterCombat()
mw:RunTimers()
assert(borderPasses == border and roundedPasses == full, "combat did not defer texture apply")
mw.world:LeaveCombat()
mw:RunTimers()
assert(borderPasses == border + 1 and roundedPasses == full, "burst replay repeated broad apply")
ExpectStyle(frames.target, "BORDER:SHADOW", "slanted")
mw:RunTimers()
assert(borderPasses == border + 1, "idle repeated the last selection")
local full = roundedPasses
M.ApplyService.RequestRoundedBars("MSUF2_TEST_SHAPE_CHANGE", "shared")
mw:RunTimers()
assert(roundedPasses == full + 1, "shape settings lost their required rounded apply")
print("bars_outline_texture_apply_smoke: OK (" .. flavor .. "; " .. cases .. " texture selections; "
    .. totalWork .. " VM instructions; " .. peakWork .. " max)")

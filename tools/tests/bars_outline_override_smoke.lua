-- The real Bars scope toggle must repaint the outline when returning to Shared.
-- Exercise the loaded menu, ApplyService, compiler and border painter. Gameplay
-- elements are excluded from this fixture; native rendering still needs WoW.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true })
local M, env, UF, GF = mw.M, mw.env, mw.core.UF, mw.core.GF
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, flavor .. ": " .. message)
end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 0.000001 end

local scopeUI, scopeOptions
local BuildScope = M.GlobalPage.BuildScopeOverrideSection
M.GlobalPage.BuildScopeOverrideSection = function(ctx, builder, options)
    scopeOptions = options
    scopeUI = BuildScope(ctx, builder, options)
    return scopeUI
end
mw:Select("opt_bars")
Check(scopeUI and scopeOptions, "the real scope controls did not build")
local db = M.EnsureDB()
local frames, paints = {}, {}
local border = UF.elements.Borders
for _, unit in ipairs({ "target", "player" }) do
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(180, 40)
    frame.MSUFUnitKey, frame.unit = unit, unit
    frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
    frame.hpBar:SetSize(180, 40)
    frame.targetPowerBar = env.CreateFrame("StatusBar", nil, frame)
    frame.targetPowerBar:SetSize(180, 8)
    UF.frames[unit] = frame
    UF.frameList[#UF.frameList + 1] = frame
    frames[unit], paints[unit] = frame, 0
end
local function Paint(frame, spec, reason)
    UF.SetFrameSpec(frame, spec)
    border.Apply(frame, spec)
    border.Update(frame, spec, reason or "MSUF_FORCE_UPDATE")
    paints[frame.MSUFUnitKey] = paints[frame.MSUFUnitKey] + 1
end
-- Keep the real scoped iteration and compile; isolate the owned border sink
-- from prediction/health APIs this scenario does not exercise.
UF.ApplyElementsToFrame = function(frame, names, spec, reason)
    UF.SetFrameSpec(frame, spec)
    for _, name in ipairs(names) do
        if name == "Borders" then Paint(frame, spec, reason) end
    end
end
local outlineCalls, roundedCalls, groups = 0, 0, {}
local Outline, Rounded, GroupVisuals = env.MSUF_ApplyBarOutlineThickness_All,
    env.MSUF_ApplyRoundedUnitframes, GF.RefreshVisuals
env.MSUF_ApplyBarOutlineThickness_All = function(...)
    outlineCalls = outlineCalls + 1
    return Outline(...)
end
env.MSUF_ApplyRoundedUnitframes = function(...)
    roundedCalls = roundedCalls + 1
    return Rounded(...)
end
GF.RefreshVisuals = function(kind, ...)
    groups[kind or "all"] = (groups[kind or "all"] or 0) + 1
    return GroupVisuals(kind, ...)
end
local function Seed(unit)
    Paint(frames[unit], UF.Config.RefreshUnit(unit))
end
local function AssertOutline(unit, thickness, r, g, b, style)
    local frame, cfg = frames[unit], frames[unit].MSUFSpec.border
    Check(cfg.thickness == thickness, unit .. " has stale compiled thickness")
    Check(cfg.enabled == (thickness > 0), unit .. " has stale enabled state")
    Check(frame._msufBorderShown == (thickness > 0), unit .. " has stale painted visibility")
    Check(frame._msufBorderVisualSource == (thickness > 0 and "normal" or "hidden"),
        unit .. " retained the previous border source")
    Check(Near(cfg.r, r) and Near(cfg.g, g) and Near(cfg.b, b), unit .. " has stale compiled color")
    if thickness > 0 then
        Check(frame._msufBorderVisualThickness == thickness, unit .. " retained painted thickness")
        Check(Near(frame._msufBorderVisualR, r) and Near(frame._msufBorderVisualG, g)
            and Near(frame._msufBorderVisualB, b), unit .. " retained painted color")
    end
    Check(cfg.textureKey == (style ~= "" and (style:match("^BORDER:(.+)$") or style) or nil), unit .. " retained the outline style")
end
db.bars.showBarBorder = true
db.general.barOutlineColorR, db.general.barOutlineColorG, db.general.barOutlineColorB = 0.15, 0.35, 0.55
db.general.barOutlineColorA = 1
db.target.barOutlineThickness = 4
db.target.barOutlineColorR, db.target.barOutlineColorG, db.target.barOutlineColorB = 0.8, 0.1, 0.05
db.target.barOutlineColorA = 1
db.player.hlOverride = false
for _, shape in ipairs({ "square", "rounded", "slanted" }) do
    db.bars.roundedFramesEnabled, db.bars.roundedUnitFrames = shape == "rounded", true
    db.bars.slantedBarsEnabled, db.bars.slantedUnitFrames = shape == "slanted", true
    for _, style in ipairs({ "", "BORDER:SHADOW" }) do
        db.bars.barOutlineTexture = style
        db.target.barOutlineTexture = "BORDER:GLOW"
        for _, shared in ipairs({ 0, 2 }) do
            db.bars.barOutlineThickness = shared
            db.target.hlOverride = true
            db.general.hpPowerTextSelectedKey = "target"
            env.MSUF_ApplyRoundedUnitframes()
            Seed("target")
            Seed("player")
            local calls, playerPaints = outlineCalls, paints.player
            scopeUI.override:Click()
            Check(db.target.hlOverride == false, "the real toggle did not disable Override")
            Check(outlineCalls == calls, "a click bypassed the deferred apply")
            mw:RunTimers()
            AssertOutline("target", shared, 0.15, 0.35, 0.55, style)
            Check(outlineCalls == calls + 1, "a scoped toggle must repaint once")
            Check(paints.player == playerPaints, "a Target toggle repainted Player")
            Check(db.bars.barOutlineThickness == shared and db.target.barOutlineThickness == 4,
                "turning off Override changed stored thickness")
            Check(db.target.barOutlineTexture == "BORDER:GLOW" and Near(db.target.barOutlineColorR, 0.8),
                "turning off Override discarded its saved style/color")
            scopeUI.override:Click()
            mw:RunTimers()
            AssertOutline("target", 4, 0.8, 0.1, 0.05, "BORDER:GLOW")
        end
    end
end

-- A click burst uses the existing single timer and paints the latest choice.
local calls, rounded = outlineCalls, roundedCalls
scopeUI.override:Click()
scopeUI.override:Click()
scopeUI.override:Click()
Check(outlineCalls == calls, "a click burst painted before the flush")
mw:RunTimers()
Check(outlineCalls == calls + 1 and roundedCalls == rounded, "a click burst repeated runtime work")
AssertOutline("target", 2, 0.15, 0.35, 0.55, "BORDER:SHADOW")
mw:RunTimers()
Check(outlineCalls == calls + 1, "an idle menu repeated the repaint")

-- A pending change defers through the existing combat gate and keeps its scope.
db.target.hlOverride = true
Seed("target")
scopeUI.override:Click()
calls = outlineCalls
mw.world:EnterCombat()
mw:RunTimers()
Check(outlineCalls == calls and frames.target._msufBorderShown == true, "combat did not defer the paint")
mw.world:LeaveCombat()
mw:RunTimers()
Check(outlineCalls == calls + 1, "combat replay did not apply the pending change once")
AssertOutline("target", 2, 0.15, 0.35, 0.55, "BORDER:SHADOW")

-- Group texture refresh already paints Borders: keep its single existing pass.
for _, scope in ipairs({ "gf_party", "gf_raid" }) do
    db.general.hpPowerTextSelectedKey = scope
    M.GlobalPage.ScopeSetOverride(scope, "hlOverride", true)
    calls = outlineCalls
    local party, raid, mythic = groups.party or 0, groups.raid or 0, groups.mythicraid or 0
    scopeUI.override:Click()
    mw:RunTimers()
    Check(not M.GlobalPage.ScopeHasOverride(scope, "hlOverride"), scope .. " Override stayed on")
    Check(outlineCalls == calls, scope .. " unnecessarily refreshed unit outlines")
    if scope == "gf_party" then
        Check(groups.party == party + 1, "Party repeated its group refresh")
    else
        Check(groups.raid == raid + 1 and groups.mythicraid == mythic + 1, "Raid lost/repeated a group refresh")
    end
end

-- Reset is visible on Shared. Its callback must also target every scope if a
-- caller invokes it with another selection; the selection is not its scope.
for _, selected in ipairs({ "shared", "target", "gf_raid" }) do
    for _, unit in ipairs({ "target", "player" }) do
        db[unit].hlOverride, db[unit].barOutlineThickness = true, 4
        Seed(unit)
    end
    db.general.hpPowerTextSelectedKey = selected
    calls = outlineCalls
    local groupPasses = groups.all or 0
    if selected == "shared" then scopeUI.reset:Click() else scopeOptions.reset() end
    mw:RunTimers()
    Check(outlineCalls == calls + 1, "Reset did not use one global outline pass")
    Check(groups.all == groupPasses + 1, "Reset repeated the texture-covered group border refresh")
    for _, unit in ipairs({ "target", "player" }) do
        Check(db[unit].hlOverride == false and db[unit].barOutlineThickness == 4, "Reset discarded a saved override")
        AssertOutline(unit, 2, 0.15, 0.35, 0.55, "BORDER:SHADOW")
    end
end

-- An outline-only request still owns its group refresh; the texture-covered
-- shortcut applies only to global transactions, including widened bursts.
local groupPasses = groups.all or 0
M.ApplyService.RequestBarOutline("MSUF2_TEST_OUTLINE_ONLY", "shared")
mw:RunTimers()
Check(groups.all == groupPasses + 1, "outline-only Shared lost its group refresh")
local party = groups.party or 0
M.ApplyService.RequestBarOutline("MSUF2_TEST_OUTLINE_ONLY", "gf_party")
mw:RunTimers()
Check(groups.party == party + 1, "outline-only Party lost its group refresh")
local priority = groups.priority or 0
M.RequestGeneralApply("MSUF2_TEST_PRIORITY_OUTLINE", {
    preview = true, applyAll = false, bars = true, barOutline = true, barsScope = "gf_priority",
})
mw:RunTimers()
Check(groups.priority == priority + 1, "Priority lost the group pass its texture path does not cover")
print("bars_outline_override_smoke: OK (" .. flavor .. "; " .. checks .. " checks)")

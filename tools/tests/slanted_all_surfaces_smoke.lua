-- All supported unit scopes, castbar slots, and Player resource contours use
-- the same scoped direction in runtime and previews.
local root, flavor = assert(arg[1]), assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", keepFlush = true })
local env, core, M = mw.env, mw.core, mw.M
local db, kit, UF = M.EnsureDB(), core.RoundedSurfaceKit, core.UF
local directions = { "LEFT_UP", "RIGHT_DOWN", "BOTH_UP", "LEFT_DOWN", "RIGHT_UP", "BOTH_DOWN" }
db.bars.slantedBarsEnabled, db.bars.slantedUnitFrames, db.bars.slantedGroupFrames = true, true, true
db.bars.slantedPowerBars, db.bars.slantedCastbars, db.bars.slantedClassResources = true, true, true
db.bars.slantedBarDirection, db.bars.classPowerShape, db.bars.classPowerOutline = "BOTH_DOWN", "BAR", 1
local scopes = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }
local units = {}
for index, scope in ipairs(scopes) do
    db[scope] = db[scope] or {}
    db[scope].frameBarShape, db[scope].slantedBarDirection = "SLANTED", directions[(index - 1) % 6 + 1]
    if core.Client.SupportsUnit(scope) then
        local count = scope == "boss" and (tonumber(env.MAX_BOSS_FRAMES) or 5) or scope == "arena" and core.Client.MaxArenaOpponents or 1
        for slot = 1, count do
            units[#units + 1] = { unit = count > 1 and scope .. slot or scope, scope = scope }
        end
    end
end
local function Bar(parent)
    local bar = env.CreateFrame("StatusBar", nil, parent)
    bar:SetSize(180, 25)
    return bar
end
local initialFrameCount = #UF.frameList
for _, entry in ipairs(units) do
    entry.originalFrame = UF.frames[entry.unit]
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(180, 40)
    frame.MSUFUnitKey, frame.unit = entry.unit, entry.unit
    frame.bg, frame.hpBar, frame.targetPowerBar = frame:CreateTexture(), Bar(frame), Bar(frame)
    UF.frames[entry.unit], UF.frameList[#UF.frameList + 1], entry.frame = frame, frame, frame
end
env.MSUF_ApplyRoundedUnitframes()
for _, entry in ipairs(units) do
    local frame, direction = entry.frame, db[entry.scope].slantedBarDirection
    local masks = assert(frame._msufRUF_MaskedTextures, entry.unit .. ": no runtime masks")
    for _, bar in ipairs({ frame.hpBar, frame.targetPowerBar }) do
        assert(masks[bar:GetStatusBarTexture()]:GetTexture() == kit.SLANTED_MASK_PATHS[direction],
            entry.unit .. ": wrong Health/Power cut")
    end
    assert(frame._msufRUF_Edge:GetTexture() == kit.SLANTED_EDGE_PATHS[direction], entry.unit .. ": wrong outline")
end
-- Retire the minimal Health/Power fixtures before real Edit Mode previews run.
for _, entry in ipairs(units) do UF.frames[entry.unit] = entry.originalFrame end
while #UF.frameList > initialFrameCount do table.remove(UF.frameList) end
-- Both live and preview castbars use unit tokens, including every pool slot.
core.RoundedCastbarsApplyAll(true)
local casts = {}
env.MSUF_ShouldUseMSUFCastbar = function() return true end
for _, entry in ipairs(units) do
    if entry.scope == "player" or entry.scope == "target" or entry.scope == "focus"
        or entry.scope == "boss" or entry.scope == "arena" then
        local frame = env.CreateFrame("Frame", nil, env.UIParent)
        frame.unit, frame.statusBar = entry.unit, Bar(frame)
        frame.backgroundBar, frame.latencyBar = frame:CreateTexture(), frame:CreateTexture()
        frame.empowerSegments = { frame:CreateTexture(), frame:CreateTexture() }
        assert(env.MSUF_RoundedCastbar_RefreshFrame(frame), entry.unit .. ": castbar runtime disabled")
        assert(env.MSUF_RoundedCastbar_RenderPreview(frame, 2, 0, 0, 0, 1), "castbar preview failed")
        casts[#casts + 1] = { frame = frame, scope = entry.scope }
    end
end
local function CheckCasts()
    for _, entry in ipairs(casts) do
        local direction = db[entry.scope].slantedBarDirection or db.bars.slantedBarDirection
        local frame = entry.frame
        local masked = assert(frame._msufRoundedCastbarMasked)
        assert(next(masked), "castbar painted no masks")
        for _, mask in pairs(masked) do
            assert(mask:GetTexture() == kit.SLANTED_MASK_PATHS[direction], entry.scope .. ": wrong castbar mask")
        end
        assert(frame._msufRoundedCastbarOutlineStack[1]:GetTexture() == kit.SLANTED_EDGE_PATHS[direction],
            entry.scope .. ": wrong castbar edge")
    end
end
CheckCasts()
-- The real unit preview painter must update its scope when its selector changes.
local methods = mw.world.widgets.Methods
for _, key in ipairs({ "SetStartPoint", "SetEndPoint", "SetThickness", "SetAutoFocus", "SetMaxLetters", "EnableKeyboard" }) do
    if not methods[key] then methods[key] = function() end end
end
env.C_Texture = { GetAtlasInfo = function() return nil end }
local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel, selected = env.CreateFrame("Frame", nil, env.UIParent), "player"
panel._msufGetCurrentKey = function() return selected end
local preview = core.UFPreview._BuildPreview(parent, panel, 900, 400)
preview:Show()
preview._msuf2ColorPainterForceCastbar = true
preview.canvas:SetSize(400, 200)
db.general.enablePlayerCastbar, db.general.enableTargetCastbar, db.general.enableFocusCastbar = true, true, true
UF.Config.Refresh()
for _, scope in ipairs({ "player", "target", "focus", "boss", "arena" }) do
    if core.Client.SupportsUnit(scope) then
        selected = scope
        core.UFPreview.Refresh(preview, "SLANTED_ALL_SCOPES")
        assert(preview.mock.cast:IsShown(), scope .. ": unit castbar preview was silently skipped")
        do
            assert(preview.mock.cast.configKey == scope, "unit castbar preview lost selected scope")
            assert(next(preview.mock.cast._msufRoundedCastbarMasked))
            for _, mask in pairs(preview.mock.cast._msufRoundedCastbarMasked) do
                assert(mask:GetTexture() == kit.SLANTED_MASK_PATHS[db[scope].slantedBarDirection],
                    scope .. ": unit castbar preview lost direction")
            end
        end
    end
end
-- The Castbars page preview uses the same renderer, including style changes.
-- A cold surface can be refused during combat; a failed paint must be retried.
local Require, refused = core.Require, false
core.Require = function(name, context)
    local provider = Require(name, context)
    if name == "MSUF_RoundedCastbar_RenderPreview" then
        refused = true
        return function() return false end
    end
    return provider
end
mw:Select("opt_castbar")
core.Require = Require
assert(refused, "cold shaped preview was not exercised")
local pagePreview = assert(M._msuf2CastbarPreview, "Castbars page preview missing")
assert(pagePreview.outlineFrame:IsShown() and not pagePreview.bar._msufRoundedCastbarActive,
    "refused cold shape did not retain rectangular fallback")
for _, scope in ipairs({ "player", "target", "focus", "boss", "arena" }) do
    if core.Client.SupportsUnit(scope) then
        assert(M.SetCastbarPreviewUnit(scope))
        local bar, direction = pagePreview.bar, db[scope].slantedBarDirection
        assert(bar.configKey == scope, "Castbars page lost selected scope")
        assert(bar._msufRoundedCastbarMasked[pagePreview.fill]:GetTexture() == kit.SLANTED_MASK_PATHS[direction],
            scope .. ": Castbars page used wrong contour")
        assert(bar._msufRoundedCastbarOutlineStack[1]:GetTexture() == kit.SLANTED_EDGE_PATHS[direction],
            scope .. ": Castbars page used wrong outline")
        for _, texture in ipairs(bar.empowerSegments) do
            assert(bar._msufRoundedCastbarMasked[texture]:GetTexture() == kit.SLANTED_MASK_PATHS[direction],
                "empower stage escaped scoped contour")
        end
    end
end
local host, layoutCalls = pagePreview.bar._msufRoundedCastbarOutlineHost, 0
local Clear = host.ClearAllPoints
host.ClearAllPoints = function(self, ...)
    layoutCalls = layoutCalls + 1
    return Clear(self, ...)
end
for _ = 1, 5 do pagePreview:Refresh() end
assert(layoutCalls == 0, "unchanged animated preview rebuilt its shaped outline")
db.general.castbarOutlineThickness = 0
pagePreview:Refresh()
assert(pagePreview.bar._msufRoundedCastbarActive and not host:IsShown(), "zero outline disabled cut or retained edge")
db.bars.slantedCastbars, db.bars.roundedCastbars = false, false
db.general.castbarOutlineThickness = 1
pagePreview:Refresh()
assert(pagePreview.bar._msufRoundedCastbarMasked == nil and pagePreview.outlineFrame:IsShown(),
    "disabling shape did not restore rectangular Castbars preview")
db.bars.roundedFramesEnabled, db.bars.roundedCastbars = true, true
pagePreview:Refresh()
assert(pagePreview.bar._msufRoundedCastbarMasked[pagePreview.fill]:GetTexture() == core.RoundedSurface.ResolveMedia(),
    "Castbars preview did not change to rounded media")
db.bars.slantedCastbars, db.bars.roundedCastbars = true, false
pagePreview:Refresh()
assert(pagePreview.bar._msufRoundedCastbarMasked[pagePreview.fill]:GetTexture()
    == kit.SLANTED_MASK_PATHS[db[pagePreview.layoutUnit].slantedBarDirection], "rounded-to-slanted transition stayed rounded")
-- Player class resources share Player's contour, including cached reapply.
local cp = { container = env.CreateFrame("Frame", nil, env.UIParent), bars = {}, currentMax = 3 }
cp.container:SetSize(180, 20)
cp.bgTex = cp.container:CreateTexture()
for index = 1, 3 do
    cp.bars[index] = Bar(cp.container)
    cp.bars[index]._bg = cp.container:CreateTexture()
end
local fills, backgrounds = {}, {}
local sample = env.CreateFrame("Frame", nil, env.UIParent)
sample:SetSize(180, 20)
for index = 1, 3 do fills[index], backgrounds[index] = sample:CreateTexture(), sample:CreateTexture() end
for _, direction in ipairs(directions) do
    db.player.slantedBarDirection = direction
    assert(core.RoundedSurface.ApplyClassPower(cp, true), "class resource runtime failed")
    assert(core.RoundedSurface.ApplyClassPower(cp, true), "class resource cached apply failed")
    assert(cp.container._msufRCPMaskedTextures[cp.bgTex]:GetTexture() == kit.SLANTED_MASK_PATHS[direction],
        "class resources ignored Player direction")
    assert(cp._msufRCPOutlineEdge:GetTexture() == kit.SLANTED_EDGE_PATHS[direction], "class resource edge ignored Player")
    assert(M.PreviewHelpers.ApplyRoundedClassPowerSurface(sample, true, fills, backgrounds, 3, 1, { style = "SLANTED" }),
        "class resource preview failed")
    assert(sample._msufCPPreviewRoundedMasked[fills[1]]:GetTexture() == kit.SLANTED_MASK_PATHS[direction],
        "class resource preview ignored Player direction")
end
-- Clearing a scoped direction restores Shared without disturbing other units.
db.player.slantedBarDirection = nil
for _, entry in ipairs(casts) do
    assert(env.MSUF_RoundedCastbar_RefreshFrame(entry.frame))
end
CheckCasts()
for _, entry in ipairs(casts) do
    assert(env.MSUF_RoundedCastbar_RenderPreview(entry.frame, 2, 0, 0, 0, 1))
end
CheckCasts()
assert(core.RoundedSurface.ApplyClassPower(cp, true))
assert(cp.container._msufRCPMaskedTextures[cp.bgTex]:GetTexture() == kit.SLANTED_MASK_PATHS.BOTH_DOWN)
assert(M.PreviewHelpers.ApplyRoundedClassPowerSurface(sample, true, fills, backgrounds, 3, 1, { style = "SLANTED" }))
assert(sample._msufCPPreviewRoundedMasked[fills[1]]:GetTexture() == kit.SLANTED_MASK_PATHS.BOTH_DOWN,
    "class resource preview did not restore Shared")
print("slanted_all_surfaces_smoke: OK (" .. flavor .. ", " .. #units .. " unit frames, " .. #casts .. " castbars)")

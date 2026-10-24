-- Both menu previews paint the real Health/Power elements; gloss must retain
-- that ownership through cold creation, scoped refresh and cached restoration.
local root = assert(arg[1], "root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local sourceOverride = arg[4]
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", clientScriptBindings = true, beforeCore = function(world)
    if not sourceOverride then return end
    local load = world.LoadFile
    world.LoadFile = function(self, path, ...)
        if path:sub(-#"MSUF_UF_Elements_BarGloss.lua") == "MSUF_UF_Elements_BarGloss.lua" then path = sourceOverride end
        return load(self, path, ...)
    end
end })
local env, core, M = mw.env, mw.core, mw.M
local UF, GF = core.UF, core.GF
local Common = assert(core.UFBarTextCommon, "shared bar helpers missing")
assert(type(Common.ApplyBarGloss) == "function", "shared runtime gloss painter missing")
-- Optional causal controls alter only this process's loaded painter. They never
-- rewrite the worktree another package is editing.
local mutant = arg[3]
if mutant == "-" then mutant = nil end
if mutant then
    local paint = Common.ApplyBarGloss
    assert(mutant == "drop-health" or mutant == "drop-group" or mutant == "dark-tint"
        or mutant == "ignore-strength" or mutant == "retain-disabled" or mutant == "replace-regions", "unknown mutant")
    Common.ApplyBarGloss = function(frame, bar, spec, key, opacity)
        if mutant == "drop-health" and key == "hpGloss" then return end
        if mutant == "drop-group" and frame.MSUFSpec.scope == "group" then return end
        if mutant == "retain-disabled" and (not spec or spec.enabled ~= true) then return frame[key] end
        if mutant == "replace-regions" then frame[key] = nil end
        if mutant == "ignore-strength" and spec then spec = { enabled = spec.enabled, strength = 0.5 } end
        local gloss = paint(frame, bar, spec, key, opacity)
        if mutant == "dark-tint" and gloss then gloss.upper:SetVertexColor(0, 0, 0, 1) end
        return gloss
    end
end
local db = M.EnsureDB()
local checks = 0
local function Check(ok, label)
    checks = checks + 1
    assert(ok, flavor .. ": " .. label)
end
local function Near(a, b)
    return type(a) == "number" and math.abs(a - b) < 0.000001
end
local function RefreshConfig()
    UF.Config.Refresh()
    GF.InvalidateCompiledSpecs()
end
local function RuntimeCalls(run, label, disabled)
    local painter, count = Common.ApplyBarGloss, 0
    debug.sethook(function()
        if debug.getinfo(2, "f").func == painter then count = count + 1 end
    end, "c")
    local ok, failure = pcall(run)
    debug.sethook()
    assert(ok, failure)
    if disabled then
        Check(count == 0, label .. " called the disabled gloss material painter")
    else
        Check(count > 0, label .. " bypassed the shared runtime gloss painter")
    end
end
local function Gloss(frame, storeKey, bar, strength, label)
    local gloss = frame[storeKey]
    Check(type(gloss) == "table", label .. " gloss regions absent")
    Check(gloss.upper and gloss.lower, label .. " gloss bands absent")
    Check(gloss.upper:IsShown() and gloss.lower:IsShown(), label .. " gloss bands hidden")
    local spec = frame.MSUFSpec[storeKey == "hpGloss" and "health" or "power"].barGloss
    Check(spec.enabled and Near(spec.strength, strength), label .. " compiled strength differs")
    local r, g, b, a = gloss.upper:GetVertexColor()
    Check(Near(r, strength * 0.65) and r == g and g == b, label .. " dark mode tinted the gloss")
    local art = gloss.upper:GetTexture()
    Check(art and art:sub(-#"msuf_skin_gloss_top.tga") == "msuf_skin_gloss_top.tga"
        and gloss.upper:GetBlendMode() == "ADD",
        label .. " dark mode removed or changed the neutral reflected light")
    Check(Near(gloss.lower:GetVertexColor(), strength * 0.08),
        label .. " lower reflection differs from the restrained material dose")
    local fill, anchored = bar:GetStatusBarTexture(), false
    for i = 1, gloss.upper:GetNumPoints() do
        if select(2, gloss.upper:GetPoint(i)) == fill then anchored = true end
    end
    Check(anchored, label .. " gloss is not anchored to the native filled texture")
    return gloss
end
local function Hidden(frame, key, label)
    local gloss = frame[key]
    Check(not gloss or not gloss.upper:IsShown() and not gloss.lower:IsShown(), label)
end

-- The actual Unit page constructor creates an engine scene on first refresh.
local selected = "player"
local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, parent)
panel._msufGetCurrentKey = function() return selected end
local Preview = core.UFPreview
local box = Preview._BuildPreview(parent, panel, 900, 400)
box.canvas:SetSize(600, 260)
box:Show()
db.player.showPowerBar = true
db.general.darkMode, db.general.barMode, db.general.powerColorMode = true, "dark", "dark"
db.general.darkBarR, db.general.darkBarG, db.general.darkBarB = 0, 0, 0
db.player.healthColorMode, db.target.healthColorMode = "dark", "dark"
RefreshConfig()
RuntimeCalls(function() Preview.Refresh(box, "GLOSS_COLD_OFF") end, "unit cold preview", true)
local body = assert(box.mock._body, "unit runtime body absent")
Hidden(body, "hpGloss", "default health gloss allocated or shown")
Hidden(body, "powerGloss", "default power gloss allocated or shown")
Check(db.general.healthGlossEnabled == nil and db.general.healthGlossStrength == nil,
    "cold preview materialized health gloss defaults")

db.general.healthGlossEnabled, db.general.healthGlossStrength = true, 0.65
db.general.powerGlossEnabled, db.general.powerGlossStrength = true, 0.2
RefreshConfig()
RuntimeCalls(function() Preview.Refresh(box, "GLOSS_SHARED_ON") end, "unit enabled preview")
local hp = Gloss(body, "hpGloss", body.hpBar, 0.65, "unit health")
local power = Gloss(body, "powerGloss", body.targetPowerBar, 0.2, "unit power")
local hr, hg, hb = body.hpBar:GetStatusBarColor()
Check(hr == 0 and hg == 0 and hb == 0, "unit dark-mode test did not use a black base bar")
db.player.hlOverride, db.player.healthGlossEnabled = true, false
db.player.powerGlossEnabled, db.player.powerGlossStrength = true, 0
RefreshConfig()
Preview.Refresh(box, "GLOSS_EXPLICIT_FALSE_ZERO")
Hidden(body, "hpGloss", "explicit false inherited shared health gloss")
Hidden(body, "powerGloss", "explicit zero retained visible power gloss")
Check(db.player.healthGlossEnabled == false and db.player.powerGlossStrength == 0,
    "preview changed explicit false/zero")
db.player.healthGlossEnabled, db.player.healthGlossStrength = true, 0.85
db.player.powerGlossStrength = 0.35
RefreshConfig()
Preview.Refresh(box, "GLOSS_REENABLE")
Check(Gloss(body, "hpGloss", body.hpBar, 0.85, "unit restored health") == hp, "unit health regions replaced")
Check(Gloss(body, "powerGloss", body.targetPowerBar, 0.35, "unit restored power") == power, "unit power regions replaced")
selected = "target"
RefreshConfig()
Preview.Refresh(box, "GLOSS_SCOPE_TARGET")
local target = assert(box.mock._body)
Gloss(target, "hpGloss", target.hpBar, 0.65, "target shared health")
selected = "player"
box:Hide()
box:Show()
Preview.Refresh(box, "GLOSS_REOPEN")
Check(box.mock._body == body and body.hpGloss == hp, "unit reopen replaced cached engine/gloss")

-- The real native Group page preview also creates an engine scene. Its scope
-- selector must not keep the prior Raid material when Party takes ownership.
M.gfScope = "raid"
local raid = GF.GetConf("raid")
raid.powerBarEnabled, raid.powerHeight, raid.hlOverride = true, 6, true
raid.healthGlossEnabled, raid.healthGlossStrength = true, 0.8
raid.powerGlossEnabled, raid.powerGlossStrength = true, 0.3
local group = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
group._stage:SetSize(600, 150)
group:Show()
RefreshConfig()
RuntimeCalls(function() group:Refresh("GLOSS_RAID_COLD") end, "group cold preview")
local cell = assert(group._mock._cell, "group runtime cell absent")
local raidHP = Gloss(cell, "hpGloss", cell.hpBar, 0.8, "raid health")
local raidPower = Gloss(cell, "powerGloss", cell.targetPowerBar, 0.3, "raid power")
hr, hg, hb = cell.hpBar:GetStatusBarColor()
Check(hr == 0 and hg == 0 and hb == 0, "raid dark-mode test did not use a black base bar")
raid.healthGlossEnabled = false
RefreshConfig()
group:Refresh("GLOSS_RAID_HEALTH_OFF")
Hidden(cell, "hpGloss", "raid health toggle left gloss shown")
Gloss(cell, "powerGloss", cell.targetPowerBar, 0.3, "raid independent power")
raid.healthGlossEnabled = true
RefreshConfig()
group:Refresh("GLOSS_RAID_REENABLE")
Check(cell.hpGloss == raidHP and cell.powerGloss == raidPower, "raid toggles replaced gloss regions")
M.gfScope = "party"
GF.GetConf("party").powerBarEnabled = true
RefreshConfig()
group:Refresh("GLOSS_SCOPE_PARTY")
local partyCell = assert(group._mock._cell)
Gloss(partyCell, "hpGloss", partyCell.hpBar, 0.65, "party shared health")
M.gfScope = "raid"
group:Hide()
group:Show()
group:Refresh("GLOSS_RAID_REOPEN")
Check(group._mock._cell == cell and cell.hpGloss == raidHP, "raid reopen replaced cached scene/gloss")

-- A changed shared material is picked up by a warm preview, with the same
-- runtime getter as a new profile would use. Explicit scope values stay local.
db.general.healthGlossStrength = 0.4
selected = "target"
RefreshConfig()
Preview.Refresh(box, "GLOSS_SHARED_PROFILE_REFRESH")
Gloss(box.mock._body, "hpGloss", box.mock._body.hpBar, 0.4, "warm shared refresh")
Gloss(cell, "hpGloss", cell.hpBar, 0.8, "raid retained local material")

-- The actual frame decorator must include both new material regions, including
-- a first creation while a scope is already shaped and subsequent shape edits.
local kit = assert(core.RoundedSurfaceKit)
local function GlossMasks(frame, shaped, powerShaped, label)
    local masked = kit.FrameIsGroup(frame) and frame._msufRGF_MaskedTextures or frame._msufRUF_MaskedTextures
    local expected = shaped and kit.SurfaceMaskPath(frame) or nil
    for _, key in ipairs({ "hpGloss", "powerGloss" }) do
        local wanted = shaped and (key == "hpGloss" or powerShaped)
        local gloss = assert(frame[key], label .. ": material missing")
        for _, band in ipairs({ "upper", "lower" }) do
            local region = gloss[band]
            local mask = masked and masked[region]
            Check((mask ~= nil) == wanted, label .. " " .. key .. "." .. band .. " mask membership")
            if wanted then
                Check(mask:GetTexture() == expected, label .. " " .. key .. "." .. band .. " mask path")
                Check(region:GetNumMaskTextures() == 1, label .. " " .. key .. "." .. band
                    .. " duplicate/missing mask (" .. region:GetNumMaskTextures() .. ")")
            else
                Check(region:GetNumMaskTextures() == 0, label .. " " .. key .. "." .. band .. " stale mask")
            end
        end
    end
end
selected, M.gfScope = "player", "raid"
db.bars.slantedBarsEnabled, db.bars.slantedUnitFrames, db.bars.slantedGroupFrames = true, true, true
db.bars.roundedPowerBars, db.bars.slantedPowerBars = true, true
db.player.slantedBarDirection, raid.slantedBarDirection = "LEFT_UP", "RIGHT_DOWN"
local function Shape(style, powerShaped)
    db.player.frameBarShape, raid.frameBarShape = style, style
    db.bars.slantedPowerBars = powerShaped
    env.MSUF_ApplyRoundedUnitframes()
    RefreshConfig()
    Preview.Refresh(box, "GLOSS_SHAPE_" .. style)
    group:Refresh("GLOSS_SHAPE_" .. style)
    Check(box.mock._body == body and group._mock._cell == cell, "shape change replaced preview scene frames")
    GlossMasks(body, style ~= "SQUARE", powerShaped, "unit " .. style)
    GlossMasks(cell, style ~= "SQUARE", powerShaped, "raid " .. style)
end
Shape("SQUARE", true)
Shape("ROUNDED", true)
Shape("SLANTED", true)
Shape("SLANTED", false)
Shape("SLANTED", true)
Shape("SQUARE", true)
Shape("ROUNDED", true)
local coldUnit = Preview._BuildPreview(parent, panel, 900, 400)
coldUnit.canvas:SetSize(600, 260)
coldUnit:Show()
Preview.Refresh(coldUnit, "GLOSS_SHAPED_FIRST_CREATION")
GlossMasks(assert(coldUnit.mock._body), true, true, "cold rounded unit")
local coldGroup = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
coldGroup._stage:SetSize(600, 150)
coldGroup:Show()
coldGroup:Refresh("GLOSS_SHAPED_FIRST_CREATION")
GlossMasks(assert(coldGroup._mock._cell), true, true, "cold rounded raid")
-- A nil gradient fast path must retain masks for real gradient materials
-- sharing the rounded group decorator with gloss.
db.general.enableGradient, db.general.enablePowerGradient = true, true
db.general.gradientDirRight, db.general.powerGradientDirRight = true, true
RefreshConfig()
Preview.Refresh(box, "GLOSS_AND_GRADIENT_MASKS")
group:Refresh("GLOSS_AND_GRADIENT_MASKS")
UF.Surface.OnVisualChanged(cell, "barGloss")
for _, bar in ipairs({ cell.hpBar, cell.targetPowerBar }) do
    local grads = assert(bar._msufGFGrads, "group gradient material missing")
    local texture = assert(grads.right, "group gradient region missing")
    local mask = cell._msufRGF_MaskedTextures and cell._msufRGF_MaskedTextures[texture]
    local attached = false
    for index = 1, texture:GetNumMaskTextures() do
        if texture:GetMaskTexture(index) == mask then attached = true end
    end
    Check(mask ~= nil and attached and mask:GetTexture() == kit.SurfaceMaskPath(cell),
        "live gradient lost its rounded group mask")
end
GlossMasks(cell, true, true, "rounded gloss and gradients")
print("bar gloss preview smoke: " .. flavor .. " PASS (" .. checks .. " checks; actual unit/group lifecycle and runtime painter identity)")

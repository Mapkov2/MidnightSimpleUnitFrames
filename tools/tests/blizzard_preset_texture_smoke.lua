-- A global texture pick must survive the Suite Blizzard preset's frame apply.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", keepFlush = true,
    beforeCore = function(world)
        world.env.MAX_TOTEMS = 4
        -- Native formatted-text sinks accept opaque values; string.format in
        -- the generic widget fixture cannot emulate that unrelated text path.
        world.widgets.Methods.SetFormattedText = function(self, format) self.text = format end
    end })
local M, env, UF = mw.M, mw.env, mw.core.UF
env.TotemFrame = false
env.UnitExists = function() return true end
env.UnitIsVisible = function() return true end
env.UnitIsConnected = function() return true end
env.UnitClass = function() return "Mage", "MAGE" end
env.SetPortraitTexture = function(texture, unit) texture:SetTexture("portrait:" .. unit) end
local db, frames = M.EnsureDB(), {}
local ResolveTexture = mw.core.Require("MSUF_ResolveStatusbarTextureKey", "blizzard_preset_texture_smoke")
local RefreshTextures = mw.core.Require("MSUF_UpdateAllBarTextures_Immediate", "blizzard_preset_texture_smoke")
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, "blizzard_preset_texture: " .. message)
end
local function Settle()
    for _ = 1, 12 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(500)
    end
    Check(#mw.world.widgets.timers == 0, "menu apply did not settle")
end
db.general.barTexture, db.general.hpPowerTextSelectedKey = "Blizzard", "shared"
UF.Config.Refresh()
for _, unit in ipairs({ "player", "target" }) do
    local spec = UF.Config.GetSpec(unit)
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(spec.width, spec.height)
    frame:SetFrameLevel(20)
    frame.MSUFUnitKey, frame.unit = unit, unit
    frame._msufVisibilityManaged = true
    UF.ApplySpec(frame, spec)
    UF.frames[unit], UF.frameList[#UF.frameList + 1] = frame, frame
    frames[unit] = frame
    local bar, SetTexture = frame.hpBar, frame.hpBar.SetStatusBarTexture
    bar.observedTexture, bar.textureWrites = bar._msufTexture, 0
    bar.SetStatusBarTexture = function(self, texture, ...)
        self.observedTexture, self.textureWrites = texture, self.textureWrites + 1
        return SetTexture(self, texture, ...)
    end
end
local dropdown
local Dropdown = M.Widgets.Dropdown
M.Widgets.Dropdown = function(parent, label, ...)
    local control = Dropdown(parent, label, ...)
    if label == "Bar textures (SharedMedia)" then dropdown = control end
    return control
end
mw:Select("opt_bars")
M.Widgets.EnsureSectionContent(assert(M.cache.opt_bars.sections.bars_textures))
Settle()
Check(dropdown and dropdown._msuf2OnValueChanged, "global texture dropdown missing")
local function Pick(key)
    dropdown._msuf2OnValueChanged(key)
    Settle()
    Check(db.general.barTexture == key and dropdown:GetValue() == key, "texture selection did not persist")
end
local function ExpectFill(key)
    local texture = ResolveTexture(key)
    for unit, frame in pairs(frames) do
        Check(frame.MSUFSpec.health.texture == texture, unit .. " spec has the wrong texture")
        Check(frame.hpBar.observedTexture == texture, unit .. " actual HP fill retained the preset texture")
        Check(frame.hpBar._msufTexture == texture, unit .. " element texture cache disagrees")
        Check(frame.hpBar.MSUF_cachedStatusbarTexture == texture, unit .. " global texture cache disagrees")
    end
end
-- Relevant decoded fields from Suite's Blizzard Frames preset. Keep this small
-- fixture independent of a Suite installation; the real core compiles/paints it.
local BLIZZARD_FILL = "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\HealthFill.tga"
local function ApplyBlizzardPreset()
    db.general.barTexture, db.general.barBackgroundTexture = BLIZZARD_FILL, "Solid"
    db.bars.powerBarTexture = "RaidPower"
    for unit in pairs(frames) do
        local conf = db[unit]
        conf.barTexture, conf.barBackgroundTexture, conf.hlOverride = BLIZZARD_FILL, "Flat", false
        conf.powerBarTexture = "RaidPower"
    end
    UF.Config.Refresh()
    for unit in pairs(frames) do
        Check(UF.Apply(unit, UF.Metadata.coordinatedApplyMask), unit .. " preset frame apply failed: "
            .. table.concat(mw.world.reported or {}, "; "))
        Check(frames[unit].hpBar.observedTexture == BLIZZARD_FILL, unit .. " preset did not paint")
    end
    M.Refresh()
    Settle()
end
-- The first menu apply warms its cache; the preset then paints through the
-- normal Health element. Returning to the previous global choice must repaint.
for _, key in ipairs({ "MSUF Lucent", "Flat" }) do
    Pick(key)
    ExpectFill(key)
    ApplyBlizzardPreset()
    Pick(key)
    ExpectFill(key)
    local playerWrites, targetWrites = frames.player.hpBar.textureWrites, frames.target.hpBar.textureWrites
    RefreshTextures()
    Check(frames.player.hpBar.textureWrites == playerWrites and frames.target.hpBar.textureWrites == targetWrites,
        "unchanged global refresh rewrote the HP textures")
    ExpectFill(key)
end
print("blizzard_preset_texture_smoke: " .. checks .. " checks passed (" .. flavor .. ")")

--[[
MSUF_GF_Render.lua
Render bridge: connects GF frames to the existing UpdateSimpleUnitFrame pipeline.

Provides:
  1. Config injection into MSUF_DB (overrides RebuildVirtualConfigs)
  2. Font/bar-texture application with override resolution
  3. Global settings change propagation via hooksecurefunc

Secret-safe: All HP/power reads go through UFCore.
Lua 5.1: Well under limits.
]]

local addonName, ns = ...
ns = ns or {}

local _G               = _G
local type             = type
local select           = select
local CreateFrame      = CreateFrame
local hooksecurefunc   = hooksecurefunc

local GF = ns.GF or {}
ns.GF = GF

-- ═══════════════════════════════════════════════════════════════
-- Font Application
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyFonts(f)
    if not f then return end
    local gfConf
    if f._msufGFMode == "party" then
        gfConf = GF.GetPartyConf()
    elseif f._msufGFMode == "raid" then
        gfConf = GF.GetRaidConf()
    else
        return
    end

    local fontPath = GF.ResolveFont(gfConf, "font")
    if not fontPath and type(_G.MSUF_GetFontPath) == "function" then
        fontPath = _G.MSUF_GetFontPath()
    end
    if not fontPath then fontPath = "Fonts\\FRIZQT__.TTF" end

    local fontFlags = GF.ResolveFont(gfConf, "fontFlags") or ""
    local fontSize  = GF.ResolveFont(gfConf, "fontSize") or 10

    local fr = GF.ResolveColor(gfConf, "fontColorR") or 1
    local fg = GF.ResolveColor(gfConf, "fontColorG") or 1
    local fb = GF.ResolveColor(gfConf, "fontColorB") or 1

    if f.nameText then
        f.nameText:SetFont(fontPath, fontSize, fontFlags)
        f.nameText:SetTextColor(fr, fg, fb)
    end
    if f.hpText then
        local hpSize = fontSize - 1
        if hpSize < 7 then hpSize = 7 end
        f.hpText:SetFont(fontPath, hpSize, fontFlags)
        f.hpText:SetTextColor(fr, fg, fb)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Bar Texture Application
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyBarTexture(f)
    if not f then return end
    local gfConf
    if f._msufGFMode == "party" then
        gfConf = GF.GetPartyConf()
    elseif f._msufGFMode == "raid" then
        gfConf = GF.GetRaidConf()
    end

    local barTex
    if gfConf then barTex = GF.ResolveBar(gfConf, "barTexture") end
    if not barTex and type(_G.MSUF_GetBarTexture) == "function" then
        barTex = _G.MSUF_GetBarTexture()
    end
    if not barTex then barTex = "Interface\\TargetingFrame\\UI-StatusBar" end

    if f.hpBar then f.hpBar:SetStatusBarTexture(barTex) end
    if f.targetPowerBar then f.targetPowerBar:SetStatusBarTexture(barTex) end
end

-- ═══════════════════════════════════════════════════════════════
-- Full Visual Refresh
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyFrameVisuals(f)
    if not f then return end
    GF.ApplyFonts(f)
    GF.ApplyBarTexture(f)
end

function GF.RefreshAllVisuals()
    local partyFrames = GF.GetPartyFrames()
    if partyFrames then
        for i = 1, 4 do
            local pf = partyFrames[i]
            if pf then GF.ApplyFrameVisuals(pf) end
        end
    end
    local header = GF.GetRaidHeader()
    if header then
        local child = 1
        while true do
            local cf = select(child, header:GetChildren())
            if not cf then break end
            if cf._msufIsGroupFrame then GF.ApplyFrameVisuals(cf) end
            child = child + 1
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Hook global settings apply to propagate changes to GF frames.
-- MSUF_ApplyAllSettings_Immediate fires on font/bar/color changes.
-- Deferred to PLAYER_LOGIN (function may not exist at parse time).
-- ═══════════════════════════════════════════════════════════════
do
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then
            hooksecurefunc("MSUF_ApplyAllSettings_Immediate", function()
                -- Re-inject configs (override resolution may have changed)
                GF.RebuildVirtualConfigs()
                local db = _G.MSUF_DB
                if db then
                    db.gf_party = GF.GetVirtualPartyConf()
                    db.gf_raid  = GF.GetVirtualRaidConf()
                end
                GF.RefreshAllVisuals()
            end)
        end
    end)
end

_G.MSUF_GF_ApplyFrameVisuals = GF.ApplyFrameVisuals
_G.MSUF_GF_RefreshAllVisuals = GF.RefreshAllVisuals

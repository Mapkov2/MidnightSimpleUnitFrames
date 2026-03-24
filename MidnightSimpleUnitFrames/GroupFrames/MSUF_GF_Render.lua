--[[
MSUF_GF_Render.lua  v7
Render bridge: connects GF frames to the visual pipeline.

v7 fix: hooks ALL main visual refresh entry points so GF frames update
live when fonts, colors, bars, or textures change in any menu:
  - MSUF_UpdateAllFonts_Immediate
  - MSUF_RefreshAllFrames
  - MSUF_RefreshAllIdentityColors
  - MSUF_RefreshAllPowerTextColors
  - MSUF_UpdateAllBarTextures_Immediate
  - MSUF_ApplyAllSettings_Immediate

Each hook calls GF.RefreshAllVisuals() which re-reads override tables
and applies resolved settings to all visible GF frames.
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
-- Font Application (reads from override resolution)
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

    -- Font path: override → main castbars font → default
    local fontPath = GF.ResolveFont(gfConf, "font")
    if not fontPath then
        -- Try the castbars font resolver (used by main UFs)
        local cb = ns.Castbars
        if cb and type(cb._GetFontPath) == "function" then
            fontPath = cb._GetFontPath()
        end
    end
    if not fontPath and type(_G.MSUF_GetFontPath) == "function" then
        fontPath = _G.MSUF_GetFontPath()
    end
    if not fontPath then fontPath = "Fonts\\FRIZQT__.TTF" end

    local fontFlags = GF.ResolveFont(gfConf, "fontFlags") or ""
    local fontSize  = GF.ResolveFont(gfConf, "fontSize") or 10

    -- Bold override
    local bold = GF.ResolveFont(gfConf, "boldText")
    if bold then
        fontFlags = "OUTLINE"
    end
    local noOutline = GF.ResolveFont(gfConf, "noOutline")
    if noOutline then
        fontFlags = ""
    end

    -- Font color
    local fr = GF.ResolveColor(gfConf, "fontColorR") or 1
    local fg = GF.ResolveColor(gfConf, "fontColorG") or 1
    local fb = GF.ResolveColor(gfConf, "fontColorB") or 1

    -- Apply to name text
    if f.nameText then
        f.nameText:SetFont(fontPath, fontSize, fontFlags)
        -- Name class coloring
        local nameClassColor = GF.ResolveFont(gfConf, "nameClassColor")
        if nameClassColor and f.unit then
            local _, cls = UnitClass(f.unit)
            if cls then
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                if cc then
                    f.nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
                else
                    f.nameText:SetTextColor(fr, fg, fb)
                end
            else
                f.nameText:SetTextColor(fr, fg, fb)
            end
        else
            f.nameText:SetTextColor(fr, fg, fb)
        end
    end

    -- Apply to HP text
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
-- Bar Background Color
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyBarBackground(f)
    if not f then return end
    -- BG color from main DB (GF inherits unless color override)
    local gfConf
    if f._msufGFMode == "party" then
        gfConf = GF.GetPartyConf()
    elseif f._msufGFMode == "raid" then
        gfConf = GF.GetRaidConf()
    end

    local bgR = GF.ResolveColor(gfConf, "classBarBgR") or 0
    local bgG = GF.ResolveColor(gfConf, "classBarBgG") or 0
    local bgB = GF.ResolveColor(gfConf, "classBarBgB") or 0

    if f.hpBarBG then
        f.hpBarBG:SetVertexColor(bgR, bgG, bgB, 0.9)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Full Visual Refresh
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyFrameVisuals(f)
    if not f then return end
    GF.ApplyFonts(f)
    GF.ApplyBarTexture(f)
    GF.ApplyBarBackground(f)
end

function GF.RefreshAllVisuals()
    local partyFrames = GF.GetPartyFrames and GF.GetPartyFrames()
    if partyFrames then
        for i = 1, 4 do
            local pf = partyFrames[i]
            if pf and pf:IsShown() then GF.ApplyFrameVisuals(pf) end
        end
    end
    local header = GF.GetRaidHeader and GF.GetRaidHeader()
    if header then
        local child = 1
        while true do
            local cf = select(child, header:GetChildren())
            if not cf then break end
            if cf._msufIsGroupFrame and cf:IsShown() then
                GF.ApplyFrameVisuals(cf)
            end
            child = child + 1
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Comprehensive Hooks
--
-- Hook ALL main visual refresh entry points.
-- Each hook calls GF.RefreshAllVisuals() so GF frames update
-- live whenever fonts, colors, bars, or textures change.
-- Deferred to PLAYER_LOGIN (functions may not exist at parse time).
-- ═══════════════════════════════════════════════════════════════
do
    local _hookedFns = {}

    local function DoRefresh()
        GF.RebuildVirtualConfigs()
        local db = _G.MSUF_DB
        if db then
            db.gf_party = GF.GetVirtualPartyConf()
            db.gf_raid  = GF.GetVirtualRaidConf()
        end
        GF.RefreshAllVisuals()
    end

    local function InstallHooks()
        local targets = {
            "MSUF_ApplyAllSettings_Immediate",
            "MSUF_UpdateAllFonts_Immediate",
            "MSUF_UpdateAllFonts",
            "MSUF_RefreshAllIdentityColors",
            "MSUF_RefreshAllPowerTextColors",
            "MSUF_UpdateAllBarTextures_Immediate",
            "MSUF_UpdateAllBarTextures",
            "MSUF_RefreshAllFrames",
        }

        for _, fname in ipairs(targets) do
            if not _hookedFns[fname] and type(_G[fname]) == "function" then
                _hookedFns[fname] = true
                hooksecurefunc(fname, DoRefresh)
            end
        end
    end

    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        InstallHooks()
        -- Retry once after a short delay (some functions are defined late)
        C_Timer.After(1, function()
            InstallHooks()
        end)
    end)
end

_G.MSUF_GF_ApplyFrameVisuals = GF.ApplyFrameVisuals
_G.MSUF_GF_RefreshAllVisuals = GF.RefreshAllVisuals

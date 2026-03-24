--[[
MSUF_GF_Render.lua  v10 (perf)
Render bridge: connects GF frames to the visual pipeline.

Perf (v10):
  - DoRefresh coalesced via C_Timer.After(0) — fires once per frame even
    when multiple hooked functions cascade (e.g. ApplyAllSettings_Immediate
    calls UpdateAllFonts which calls RefreshAllFrames → 1 GF refresh, not 3)
  - ApplyFonts: single _G.MSUF_DB read at top, passed to all sub-reads
  - ApplyFonts: resolves gfConf once, used for all ResolveFont/Color calls
  - RefreshAllVisuals: resolves party/raid conf once outside loop
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

-- PERF: Upvalue WoW APIs used in ApplyFonts (avoid _G hash per call)
local UnitClass    = _G.UnitClass
local UnitIsPlayer = _G.UnitIsPlayer
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS

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

    -- PERF: single DB read for fallback resolution
    local db = _G.MSUF_DB
    local g = db and db.general

    -- Font path
    local fontPath = GF.ResolveFont(gfConf, "font")
    if not fontPath then
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

    -- Bold / Outline
    if GF.ResolveFont(gfConf, "boldText") then fontFlags = "OUTLINE" end
    if GF.ResolveFont(gfConf, "noOutline") then fontFlags = "" end

    -- Text Backdrop (shadow)
    local textBackdrop = GF.ResolveFont(gfConf, "textBackdrop")
    if textBackdrop == nil then textBackdrop = g and g.textBackdrop end

    -- Font color
    -- ── Font Color (correct DB key resolution) ─────────────
    -- Colors menu writes: general.fontColorCustomR/G/B + useCustomFontColor
    -- OR palette key: general.fontColor ("white"/"yellow"/etc.)
    -- GF color override: groupframes.party.colors.fontColorCustomR/G/B
    local fr, fg, fb = 1, 1, 1
    if gfConf.overrideColors and type(gfConf.colors) == "table" then
        local c = gfConf.colors
        if c.fontColorCustomR and c.fontColorCustomG and c.fontColorCustomB then
            fr, fg, fb = c.fontColorCustomR, c.fontColorCustomG, c.fontColorCustomB
        end
    else
        local getFn = ns.MSUF_GetConfiguredFontColor or _G.MSUF_GetConfiguredFontColor
        if type(getFn) == "function" then
            fr, fg, fb = getFn()
        elseif g and g.useCustomFontColor and g.fontColorCustomR then
            fr, fg, fb = g.fontColorCustomR, g.fontColorCustomG or 1, g.fontColorCustomB or 1
        end
    end

    -- Name coloring flags (resolved once)
    local nameClassColor = GF.ResolveFont(gfConf, "nameClassColor")
    if nameClassColor == nil then nameClassColor = g and g.nameClassColor end
    local npcNameRed = GF.ResolveFont(gfConf, "npcNameRed")
    if npcNameRed == nil then npcNameRed = g and g.npcNameRed end

    -- ── Name text ───────────────────────────────────────────
    local nt = f.nameText
    if nt then
        nt:SetFont(fontPath, fontSize, fontFlags)

        -- Shadow
        if textBackdrop then
            if nt.SetShadowColor then nt:SetShadowColor(0, 0, 0, 1) end
            nt:SetShadowOffset(1, -1)
        else
            nt:SetShadowOffset(0, 0)
        end

        -- Color
        local colorApplied = false
        if nameClassColor and f.unit and not f._msufGFPreviewActive then
            if UnitIsPlayer and UnitIsPlayer(f.unit) then
                local _, cls = UnitClass(f.unit)
                local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                if cc then
                    nt:SetTextColor(cc.r, cc.g, cc.b, 1)
                    colorApplied = true
                end
            elseif npcNameRed then
                nt:SetTextColor(0.85, 0.10, 0.10, 1)
                colorApplied = true
            end
        end
        if not colorApplied then nt:SetTextColor(fr, fg, fb) end
    end

    -- ── HP text ─────────────────────────────────────────────
    local ht = f.hpText
    if ht then
        local hpSize = fontSize - 1
        if hpSize < 7 then hpSize = 7 end
        ht:SetFont(fontPath, hpSize, fontFlags)
        ht:SetTextColor(fr, fg, fb)
        if textBackdrop then
            if ht.SetShadowColor then ht:SetShadowColor(0, 0, 0, 1) end
            ht:SetShadowOffset(1, -1)
        else
            ht:SetShadowOffset(0, 0)
        end
    end

    -- ── Cache invalidation ──────────────────────────────────
    f._msufClampStamp = nil
    f._msufNameClipAnchorStamp = nil
    f._msufNameClipTextStamp = nil
    f._msufTextSpec = nil
    f._msufPwrTextConf = nil
    f._msufPTColorType = nil
    f._msufPTColorByPower = nil
    f._msufFontOverrideStamp = nil
    f._msufHealthColorDirty = true

    -- ── Name shortening ─────────────────────────────────────
    if type(MSUF_ClampNameWidth) == "function" then
        local conf = f.cachedConfig or (db and db[f.msufConfigKey])
        MSUF_ClampNameWidth(f, conf)
    end

    -- ── Trigger render for live units ───────────────────────
    if not f._msufGFPreviewActive and f.unit then
        if _G.UnitExists and _G.UnitExists(f.unit) then
            if type(_G.UpdateSimpleUnitFrame) == "function" then
                _G.UpdateSimpleUnitFrame(f)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Bar Texture
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyBarTexture(f)
    if not f then return end
    local gfConf = (f._msufGFMode == "party") and GF.GetPartyConf()
        or (f._msufGFMode == "raid") and GF.GetRaidConf() or nil

    -- GF override → groupframes.party.bars.barTexture
    local barTex = gfConf and GF.ResolveBar(gfConf, "barTexture")

    -- Fallback: main DB general.barTexture (SharedMedia key → resolve to path)
    if not barTex then
        local db = _G.MSUF_DB
        local g = db and db.general
        barTex = g and g.barTexture
    end

    -- Resolve SharedMedia key to actual texture path
    if barTex and type(barTex) == "string" and barTex ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then
            local resolved = resolve(barTex)
            if resolved then barTex = resolved end
        end
    end

    if not barTex or barTex == "" then
        barTex = "Interface\\TargetingFrame\\UI-StatusBar"
    end

    if f.hpBar then f.hpBar:SetStatusBarTexture(barTex) end
    if f.targetPowerBar then f.targetPowerBar:SetStatusBarTexture(barTex) end
end

-- ═══════════════════════════════════════════════════════════════
-- Bar Background Color
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyBarBackground(f)
    if not f then return end
    local gfConf = (f._msufGFMode == "party") and GF.GetPartyConf()
        or (f._msufGFMode == "raid") and GF.GetRaidConf() or nil

    local db = _G.MSUF_DB
    local g = db and db.general

    -- HP bar background
    local bgR = GF.ResolveColor(gfConf, "classBarBgR")
    local bgG = GF.ResolveColor(gfConf, "classBarBgG")
    local bgB = GF.ResolveColor(gfConf, "classBarBgB")
    if bgR == nil then bgR = g and tonumber(g.classBarBgR) or 0 end
    if bgG == nil then bgG = g and tonumber(g.classBarBgG) or 0 end
    if bgB == nil then bgB = g and tonumber(g.classBarBgB) or 0 end
    if f.hpBarBG then f.hpBarBG:SetVertexColor(bgR, bgG, bgB, 0.9) end

    -- Power bar background
    if f.powerBarBG then
        local pbR = GF.ResolveColor(gfConf, "powerBarBgColorR")
        local pbG = GF.ResolveColor(gfConf, "powerBarBgColorG")
        local pbB = GF.ResolveColor(gfConf, "powerBarBgColorB")
        if pbR == nil then pbR = g and tonumber(g.powerBarBgColorR) or bgR end
        if pbG == nil then pbG = g and tonumber(g.powerBarBgColorG) or bgG end
        if pbB == nil then pbB = g and tonumber(g.powerBarBgColorB) or bgB end
        f.powerBarBG:SetVertexColor(pbR, pbG, pbB, 0.9)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- HP Bar Color (barMode-aware: class / dark / unified)
--
-- For LIVE units: invalidate heavy visual cache so main pipeline
-- re-applies bar color via MSUF_UFStep_HeavyVisual.
-- For PREVIEW: apply barMode directly since no real unit.
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyBarColor(f)
    if not f then return end

    -- For live units: invalidate heavy visual cache, UpdateSimpleUnitFrame
    -- (called by ApplyFonts) will re-run MSUF_UFStep_HeavyVisual
    if not f._msufGFPreviewActive then
        f._msufHeavyVisualNextAt = nil
        f._msufHeavyVisualSettingsSerial = nil
        f._msufHeavyVisualApplied = nil
        return
    end

    -- Preview: apply barMode colors
    local db = _G.MSUF_DB
    local g = db and db.general
    if not g then return end
    local hb = f.hpBar
    if not hb then return end

    local mode = g.barMode
    if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
        mode = (g.useClassColors and "class") or (g.darkMode and "dark") or "dark"
    end

    if mode == "dark" then
        local dR, dG, dB = 0, 0, 0
        local gray = g.darkBarGray
        if type(gray) == "number" then
            if gray < 0 then gray = 0 elseif gray > 1 then gray = 1 end
            dR, dG, dB = gray, gray, gray
        else
            local toneKey = g.darkBarTone or "black"
            local tones = _G.MSUF_DARK_TONES
            local tone = tones and tones[toneKey]
            if tone then dR, dG, dB = tone[1] or 0, tone[2] or 0, tone[3] or 0 end
        end
        hb:SetStatusBarColor(dR, dG, dB, 1)

    elseif mode == "unified" then
        local uR = tonumber(g.unifiedBarR) or 0.10
        local uG = tonumber(g.unifiedBarG) or 0.60
        local uB = tonumber(g.unifiedBarB) or 0.90
        hb:SetStatusBarColor(uR, uG, uB, 1)

    else -- "class"
        -- Re-apply stored preview class color (needed when switching
        -- from dark/unified back to class while in preview)
        if f._msufGFPreviewBarR then
            hb:SetStatusBarColor(f._msufGFPreviewBarR, f._msufGFPreviewBarG, f._msufGFPreviewBarB, 1)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Full Visual Refresh
-- ═══════════════════════════════════════════════════════════════
function GF.ApplyFrameVisuals(f)
    if not f then return end
    -- CRITICAL: Invalidate bar-color caches BEFORE ApplyFonts, because
    -- ApplyFonts calls UpdateSimpleUnitFrame which re-runs HeavyVisual.
    -- If we invalidate AFTER, the bar-color change only appears on the
    -- next health event, not immediately.
    GF.ApplyBarColor(f)
    GF.ApplyFonts(f)
    GF.ApplyBarTexture(f)
    GF.ApplyBarBackground(f)
end

function GF.RefreshAllVisuals()
    local pf = GF.GetPartyFrames and GF.GetPartyFrames()
    if pf then
        for i = 1, 4 do
            local f = pf[i]
            if f and f:IsShown() then
                if f._msufGFPreviewActive then
                    -- Preview: re-apply texture + BG, then preview data on top
                    GF.ApplyBarTexture(f)
                    GF.ApplyBarBackground(f)
                    local idx = f._msufGFIndex or i
                    if type(_G.MSUF_GF_ReapplyPreview) == "function" then
                        _G.MSUF_GF_ReapplyPreview(f, idx)
                    end
                else
                    GF.ApplyFrameVisuals(f)
                end
            end
        end
    end
    -- Raid preview frames
    local raidPrev = _G.MSUF_GF_RaidPreviewFrames
    if type(raidPrev) == "table" then
        for i = 1, #raidPrev do
            local f = raidPrev[i]
            if f and f:IsShown() and f._msufGFPreviewActive then
                GF.ApplyBarTexture(f)
                GF.ApplyBarBackground(f)
                if type(_G.MSUF_GF_ReapplyPreview) == "function" then
                    _G.MSUF_GF_ReapplyPreview(f, i)
                end
            end
        end
    end
    -- Live raid header
    local header = GF.GetRaidHeader and GF.GetRaidHeader()
    if header then
        local idx = 1
        while true do
            local cf = select(idx, header:GetChildren())
            if not cf then break end
            if cf._msufIsGroupFrame and cf:IsShown() and not cf._msufGFPreviewActive then
                GF.ApplyFrameVisuals(cf)
            end
            idx = idx + 1
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Coalesced Hook System
--
-- PERF: Multiple hooked functions cascade (ApplyAllSettings calls
-- UpdateAllFonts which calls RefreshAllFrames). Without coalescing,
-- DoRefresh fires 2-3x per settings change. C_Timer.After(0)
-- coalesces to exactly 1 fire per frame.
-- ═══════════════════════════════════════════════════════════════
do
    local _hookedFns = {}
    local _refreshScheduled = false

    local function DoRefreshNow()
        _refreshScheduled = false
        GF.RebuildVirtualConfigs()
        local db = _G.MSUF_DB
        if db then
            db.gf_party = GF.GetVirtualPartyConf()
            db.gf_raid  = GF.GetVirtualRaidConf()
        end
        GF.RefreshAllVisuals()
    end

    local function ScheduleRefresh()
        if _refreshScheduled then return end
        _refreshScheduled = true
        C_Timer.After(0, DoRefreshNow)
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
                hooksecurefunc(fname, ScheduleRefresh)
            end
        end
    end

    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        InstallHooks()
        C_Timer.After(1, InstallHooks)
    end)
end

_G.MSUF_GF_ApplyFrameVisuals = GF.ApplyFrameVisuals
_G.MSUF_GF_RefreshAllVisuals = GF.RefreshAllVisuals

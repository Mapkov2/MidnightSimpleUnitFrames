-- BossCastbars_Preview.lua
-- Edit-mode boss castbar previews. Split from MidnightSimpleUnitFrames_BossCastbars.lua
-- so fake preview frames stay isolated from runtime boss cast handling.

local addonName, ns = ...
ns = ns or {}

local CreateFrame = CreateFrame
local UIParent = UIParent
local type, tonumber, rawget, select = type, tonumber, rawget, select
local pcall = pcall
local math_floor = math.floor

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(ns) == "table" and type(ns.Translate) == "function" then
        return ns.Translate(text)
    end
    local locale = (type(ns) == "table" and ns.L) or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = MSUF_FastCall(fn, ...)
    if ok then return a, b, c, d, e end
    return nil
end

local function GetColorFromKeyFallback(key)
    if key == "red" then return 1, 0, 0 end
    if key == "green" then return 0, 1, 0 end
    if key == "blue" then return 0, 0.5, 1 end
    if key == "white" then return 1, 1, 1 end
    if key == "yellow" then return 1, 0.9, 0.1 end
    if key == "turquoise" then return 0.2, 0.8, 0.8 end
    return 0.85, 0.2, 0.2
end

local function EnsureDBSafe()
    if type(_G.EnsureDB) == "function" then
        SafeCall(_G.EnsureDB)
    end
end
-- Boss Castbar Preview (Castbar Edit Mode only)
-- --------------------------------------------------
-- Multi-preview upgrade:
-- If Boss unitframe previews show boss1..bossN, we show a matching castbar preview for each visible boss frame.
-- Boss castbar previews remain DETACHED (anchored to UIParent) and are positioned relative to each boss unitframe preview.

local function MSUF_GetBossPreviewCount()
    -- Prefer Blizzard constant if present
    local n = tonumber(_G.MAX_BOSS_FRAMES)
    if not n or n < 1 or n > 12 then
        n = 5
    end
    return n
end

local function MSUF_HideAllBossCastbarPreviews()
    if _G.MSUF_BossCastbarPreview then
        _G.MSUF_BossCastbarPreview:Hide()
    end
    local max = MSUF_GetBossPreviewCount()
    for i = 2, max do
        local f = _G["MSUF_BossCastbarPreview" .. i]
        if f then f:Hide() end
    end
end

-- --------------------------------------------------
-- Boss Castbar Preview helpers (Edit Mode)
-- --------------------------------------------------

-- Always show a deterministic "fake" icon in boss castbar previews so the user can position it
-- even if gameplay icons are disabled.
local MSUF_BOSS_PREVIEW_FAKE_ICON = 136235 -- generic spell icon (safe across builds)

local function MSUF_ApplyInterruptiblePreviewColor(f)
    if not f or not f.statusBar or not f.statusBar.SetStatusBarColor then return end

    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}

    local r, gg, b

    local function ResolveColorKey(key, fallbackKey)
        if type(_G.MSUF_GetColorFromKey) == "function" then
            local c = _G.MSUF_GetColorFromKey(key)
            if c and type(c) == "table" and c.GetRGB then
                local rr, rg, rb = c:GetRGB()
                return rr, rg, rb
            end
            if type(c) == "number" then
                -- Some older implementations return r,g,b directly.
                return c, select(2, _G.MSUF_GetColorFromKey(key))
            end
        end
        return GetColorFromKeyFallback(fallbackKey or key)
    end

    if type(_G.MSUF_GetInterruptibleCastColor) == "function" then
        r, gg, b = _G.MSUF_GetInterruptibleCastColor()
    end

    if not (r and gg and b) then
        local key = g.castbarInterruptibleColor or "turquoise"
        r, gg, b = ResolveColorKey(key, key)
    end

    if not (r and gg and b) then
        r, gg, b = 0.2, 0.8, 0.8
    end

    SafeCall(f.statusBar.SetStatusBarColor, f.statusBar, r, gg, b, 1)
end

local function MSUF_CreateBossCastbarPreview(index)
    index = tonumber(index) or 1
    if index < 1 then index = 1 end

    -- Keep boss1 name stable for compatibility
    if index == 1 and _G.MSUF_BossCastbarPreview then
        return _G.MSUF_BossCastbarPreview
    end

    local name = (index == 1) and "MSUF_BossCastbarPreview" or ("MSUF_BossCastbarPreview" .. index)
    local existing = _G[name]
    if existing then
        if index == 1 then _G.MSUF_BossCastbarPreview = existing end
        return existing
    end

    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetSize(240, 12)
    -- Enabled so any Boss castbar preview can be clicked in MSUF Edit Mode to open the Boss castbar popup.
    f:EnableMouse(true)
    f._msufBossPreviewIndex = index
    f.unit = "boss"

    -- simple border like the other preview bars
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.55)
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end

    local statusBar = CreateFrame("StatusBar", nil, f)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0.6)
    statusBar:SetPoint("TOP", f, "TOP", 0, -1)
    statusBar:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
    statusBar:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    statusBar:SetPoint("LEFT", f, "LEFT", 1, 0)
    f.statusBar = statusBar

	-- Text overlay frame: FontStrings must be ABOVE the StatusBar fill.
	-- If they are parented to the preview frame (f), the StatusBar (child frame, higher framelevel)
	-- can visually cover them as the bar fills. Parent the texts to an overlay frame above the StatusBar.
	local textOverlay = CreateFrame("Frame", nil, f)
	textOverlay:SetAllPoints(statusBar)
	if textOverlay.SetFrameLevel and statusBar.GetFrameLevel then
		textOverlay:SetFrameLevel(statusBar:GetFrameLevel() + 10)
	end
	f._msufTextOverlay = textOverlay

    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetAlpha(0.25)
    f.backgroundBar = bg

    local icon = f:CreateTexture(nil, "OVERLAY", nil, 7)
    -- Deterministic fake icon (preview only). Add a fallback path in case fileIDs behave oddly.
    if icon and icon.SetTexture then
        local ok = pcall(icon.SetTexture, icon, MSUF_BOSS_PREVIEW_FAKE_ICON)
        if not ok then
            pcall(icon.SetTexture, icon, "Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
    if icon and icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if icon and icon.SetVertexColor then
        icon:SetVertexColor(1, 1, 1, 1)
    end
    f.icon = icon

	local castText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castText:SetJustifyH("LEFT")
    castText:SetText(Tr("Boss castbar preview"))
    f.castText = castText

	local timeText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetJustifyH("RIGHT")
    if type(_G.MSUF_GetCastbarTimeFormat) == "function" and type(_G.MSUF_FormatCastbarTimeText) == "function" then
        timeText:SetText(_G.MSUF_FormatCastbarTimeText(_G.MSUF_GetCastbarTimeFormat("boss"), 3.2, 4.0) or "3.2")
    else
        timeText:SetText("3.2")
    end
    f.timeText = timeText

    if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(f, true) end

    
    -- Wire the standard Castbar Preview Edit handlers (drag + click-to-open popup).
    -- IMPORTANT: Always treat boss2..bossN previews as kind "boss" so they open the Boss popup.
    if type(_G.MSUF_SetupCastbarPreviewEditHandlers) == "function" then
        _G.MSUF_SetupCastbarPreviewEditHandlers(f, "boss")
    end
-- Keep boss1 global stable
    if index == 1 then
        _G.MSUF_BossCastbarPreview = f
    end

    return f
end

local function MSUF_ApplyBossCastbarPreviewLayout(f, index)
    if not f then return end
    index = tonumber(index) or f._msufBossPreviewIndex or 1

    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}

    local uf = _G["MSUF_boss" .. index] or _G["MSUF_boss1"]
    local forcedW, forcedH
    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        forcedW, forcedH = _G.MSUF_GetCastbarDesiredSize("boss" .. index, g, f, 240, 12)
    else
        forcedW = tonumber(g.bossCastbarWidth)
        forcedH = tonumber(g.bossCastbarHeight)
    end
    local w = (forcedW and forcedW > 10) and forcedW or (uf and uf.GetWidth and uf:GetWidth()) or 240
    local h = (forcedH and forcedH > 4) and forcedH or 12

    -- Icon size: when bossCastIconSize is set, it overrides the default (bar height).
    local iconSize = h
    if g.bossCastIconSize ~= nil then
        iconSize = tonumber(g.bossCastIconSize) or iconSize
    end
    if iconSize < 6 then iconSize = 6 end
    if iconSize > 128 then iconSize = 128 end

    f:SetSize(w, h)

    -- Preview behavior: ALWAYS show the icon in MSUF Edit Mode so the user can position it
    -- even if gameplay icons are disabled.
    local showIcon = true
    local iconOffsetX = tonumber(g.bossCastIconOffsetX)
    if iconOffsetX == nil then iconOffsetX = tonumber(g.castbarIconOffsetX) end
    if iconOffsetX == nil then iconOffsetX = 0 end
    local iconOffsetY = tonumber(g.bossCastIconOffsetY)
    if iconOffsetY == nil then iconOffsetY = tonumber(g.castbarIconOffsetY) end
    if iconOffsetY == nil then iconOffsetY = 0 end
    local iconDetached = (iconOffsetX ~= 0 or iconOffsetY ~= 0)

    if f.icon then
        if f.icon.SetTexture then
            -- Deterministic fake icon (preview only). Add a fallback path in case fileIDs behave oddly.
            local ok = pcall(f.icon.SetTexture, f.icon, MSUF_BOSS_PREVIEW_FAKE_ICON)
            if not ok then
                pcall(f.icon.SetTexture, f.icon, "Interface\\Icons\\INV_Misc_QuestionMark")
            end
        end
        if f.icon.SetTexCoord then
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if f.icon.SetVertexColor then
            f.icon:SetVertexColor(1, 1, 1, 1)
        end
        f.icon:ClearAllPoints()
        if f.icon.SetParent and f.statusBar then
            if iconDetached then
                f.icon:SetParent(f.statusBar)
            else
                f.icon:SetParent(f)
            end
        end
        if f.icon.SetDrawLayer then
            f.icon:SetDrawLayer("OVERLAY", 7)
        end
        f.icon:SetSize(iconSize, iconSize)
        f.icon:SetPoint("LEFT", f, "LEFT", iconOffsetX, iconOffsetY)
        f.icon:SetShown(showIcon)
    end

    if f.statusBar then
        f.statusBar:ClearAllPoints()

        if showIcon and f.icon and not iconDetached then
            f.statusBar:SetPoint("LEFT", f, "LEFT", iconSize + 1, 0)
        else
            f.statusBar:SetPoint("LEFT", f, "LEFT", 1, 0)
        end

        f.statusBar:SetPoint("TOP", f, "TOP", 0, -1)
        f.statusBar:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
        f.statusBar:SetPoint("RIGHT", f, "RIGHT", -1, 0)
    end

    -- texture (if the helper exists)
    do
        local t
        if type(_G.MSUF_RefreshCastbarStyleCache) == "function" then
            SafeCall(_G.MSUF_RefreshCastbarStyleCache, f)
        end
        t = f.MSUF_cachedCastbarTexture or SafeCall(_G.MSUF_GetCastbarTexture)
        if t and f.statusBar and f.statusBar.SetStatusBarTexture then
            SafeCall(f.statusBar.SetStatusBarTexture, f.statusBar, t)
        end
        if t and f.backgroundBar then
            local bgTex = t
            if type(_G.MSUF_GetCastbarBackgroundTexture) == "function" then
                local t2 = _G.MSUF_GetCastbarBackgroundTexture()
                if t2 and t2 ~= "" then
                    bgTex = t2
                end
            end
            SafeCall(f.backgroundBar.SetTexture, f.backgroundBar, bgTex)
        end
    end

    -- Force the preview bar to use the *interruptible* cast color, mirroring the real boss castbar
    -- resolution so the Colors menu applies.
    MSUF_ApplyInterruptiblePreviewColor(f)

    -- boss cast text offsets (spell name inside the bar)
    local textOX = tonumber(g.bossCastTextOffsetX) or 0
    local textOY = tonumber(g.bossCastTextOffsetY) or 0

    local timeOX = tonumber(g.bossCastTimeOffsetX) or 0
    local timeOY = tonumber(g.bossCastTimeOffsetY) or 0

	-- Ensure preview texts are always ABOVE the StatusBar fill.
	-- Older builds created FontStrings on the parent preview frame (f), which can be covered by the child StatusBar.
	local textOverlay = f._msufTextOverlay
	if (not textOverlay) and f.statusBar and type(CreateFrame) == "function" then
		textOverlay = CreateFrame("Frame", nil, f)
		textOverlay:SetAllPoints(f.statusBar)
		if textOverlay.SetFrameLevel and f.statusBar.GetFrameLevel then
			textOverlay:SetFrameLevel(f.statusBar:GetFrameLevel() + 10)
		end
		f._msufTextOverlay = textOverlay
	end
	if textOverlay then
		if f.castText and f.castText.SetParent then
			pcall(f.castText.SetParent, f.castText, textOverlay)
		end
		if f.timeText and f.timeText.SetParent then
			pcall(f.timeText.SetParent, f.timeText, textOverlay)
		end
	end

	if f.castText and f.timeText and f.statusBar then
        f.castText:ClearAllPoints()
        f.timeText:ClearAllPoints()

        f.castText:SetPoint("LEFT", f.statusBar, "LEFT", 2 + textOX, 0 + textOY)
        f.timeText:SetPoint("RIGHT", f.statusBar, "RIGHT", -2 + timeOX, 0 + timeOY)

        -- Prevent overlap between spell name and time (even if time is hidden via alpha)
        f.castText:SetPoint("RIGHT", f.timeText, "LEFT", -6, 0)

        local showTime = (g.showBossCastTime ~= false)
        f.timeText:Show()
        f.timeText:SetAlpha(showTime and 1 or 0)

        local showBossName = (g.showBossCastName ~= false)
        f.castText:Show()
        f.castText:SetAlpha(showBossName and 1 or 0)

        -- font sizes: boss-only override for spell name/time, otherwise fall back to global
        local baseSize = g.fontSize or 14
        local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
        local globalSize = (globalOverride and globalOverride > 0) and globalOverride or baseSize

        local bossSize = tonumber(g.bossCastSpellNameFontSize)
        if not bossSize or bossSize < 6 or bossSize > 72 then
            bossSize = globalSize
        else
            bossSize = math.floor(bossSize + 0.5)
        end

        local timeSize = tonumber(g.bossCastTimeFontSize)
        if not timeSize or timeSize < 6 or timeSize > 72 then
            timeSize = globalSize
        else
            timeSize = math.floor(timeSize + 0.5)
        end

        local font1, _, flags1 = f.castText:GetFont()
        if font1 then f.castText:SetFont(font1, bossSize, flags1) end

        local font2, _, flags2 = f.timeText:GetFont()
        if font2 then f.timeText:SetFont(font2, timeSize, flags2) end
    end
end

local function MSUF_PositionBossCastbarPreview(f, index)
    if not f then return end
    index = tonumber(index) or f._msufBossPreviewIndex or 1

    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local ox = math.floor((tonumber(g.bossCastbarOffsetX) or 0) + 0.5)
    local oy = math.floor((tonumber(g.bossCastbarOffsetY) or 0) + 0.5)

    if g.bossCastbarDetached == true then
        -- Detached: anchor to UIParent CENTER, keep per-boss vertical stacking.
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", ox, oy - ((index - 1) * 24))
        return
    end

    local uf = _G["MSUF_boss" .. index]
    if uf and uf.IsShown and uf:IsShown() then
        f:ClearAllPoints()
        -- Keep legacy relative placement, but previews themselves stay parented to UIParent.
        f:SetPoint("BOTTOMLEFT", uf, "TOPLEFT", 0 + ox, 2 + oy)
    else
        -- fallback if boss frames aren't visible (still useful for slider tweaking)
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -320, -200 - ((index - 1) * 24))
    end
end


function _G.MSUF_UpdateBossCastbarPreview()
    if _G.MSUF_InCombat == true or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false) then
        return
    end
    EnsureDBSafe()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or {}

    -- Hard gate: never show boss preview when Boss Frames are disabled, or outside MSUF Edit Mode.
    if ((_G.MSUF_DB and _G.MSUF_DB.boss and _G.MSUF_DB.boss.enabled == false) or (_G.MSUF_UnitEditModeActive ~= true)) then
        MSUF_HideAllBossCastbarPreviews()
        return
    end

    -- Only in Castbar Edit Mode
    if not g.castbarPlayerPreviewEnabled then
        MSUF_HideAllBossCastbarPreviews()
        return
    end

    -- Respect "Enable Boss castbar"
    if g.enableBossCastbar == false then
        MSUF_HideAllBossCastbarPreviews()
        return
    end

    local max = MSUF_GetBossPreviewCount()
    for i = 1, max do
        local uf = _G["MSUF_boss" .. i]
        local f = MSUF_CreateBossCastbarPreview(i)

        -- Only show a preview when the corresponding boss unitframe preview exists & is visible.
        if uf and uf.IsShown and uf:IsShown() then
            MSUF_PositionBossCastbarPreview(f, i)
            -- Hard-sync first (runtime truth), then apply layout from DB.
            -- IMPORTANT: If we hard-sync *after* layout, it overrides live width/height edits
            -- and makes the boss preview look like it "won't live apply".
            if type(_G.MSUF_HardSyncCastbarPreview) == "function" then
                local real = (_G.MSUF_BossCastbars and _G.MSUF_BossCastbars[i]) or _G["MSUF_BossCastbar" .. i]
                _G.MSUF_HardSyncCastbarPreview(f, real)
            end

            -- Apply DB-driven layout last so Edit Mode changes to width/height are visible immediately.
            MSUF_ApplyBossCastbarPreviewLayout(f, i)

            f:Show()
        else
            f:Hide()
        end
    end
end

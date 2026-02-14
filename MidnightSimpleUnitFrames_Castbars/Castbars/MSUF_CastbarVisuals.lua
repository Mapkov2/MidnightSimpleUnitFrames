-- Castbars/MSUF_CastbarVisuals.lua
-- Step 9: Centralize Castbar fonts/colors/icon layering + basic sizing/anchors.

local _, ns = ...

-- Midnight/Beta note:
-- Some sub-addons can run in isolated environments where helper functions from the main addon
-- are not visible as bare globals. Castbar visuals depend on MSUF_GetGlobalFontSettings.
-- Resolve it once (prefer local env -> root global), and provide a safe fallback.
local ROOT_G = (getfenv and getfenv(0)) or _G

local MSUF_GetGlobalFontSettings_Resolved = MSUF_GetGlobalFontSettings or (ROOT_G and ROOT_G.MSUF_GetGlobalFontSettings)
if type(MSUF_GetGlobalFontSettings_Resolved) ~= "function" then
    local tonumber = tonumber
    local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
    MSUF_GetGlobalFontSettings_Resolved = function()
        -- Ensure DB is present if possible.
        if type(EnsureDB) == "function" then
            EnsureDB()
        end
        local db = MSUF_DB
        local g = db and db.general or nil

        local baseSize = (g and tonumber(g.fontSize)) or 14
        local useShadow = true

        -- Flags: keep it minimal; outline is the common setting in MSUF.
        local fontFlags = (g and g.boldText) and "OUTLINE" or ""

        -- Font: prefer LSM key from global settings.
        local fontPath = DEFAULT_FONT
        local lsm = (ns and ns.LSM) or (LibStub and LibStub("LibSharedMedia-3.0", true))
        local fontKey = g and (g.fontKey or g.font)
        if fontKey and fontKey ~= "" and lsm and lsm.Fetch then
            local p = lsm:Fetch("font", fontKey)
            if p and p ~= "" then
                fontPath = p
            end
        end

        -- Global font color default (white). CastbarText override is applied later.
        local fr, fg, fb = 1, 1, 1
        if g and g.useCustomFontColor then
            local r = tonumber(g.fontR)
            local gg = tonumber(g.fontG)
            local b = tonumber(g.fontB)
            if r and gg and b then
                fr, fg, fb = r, gg, b
            end
        end

        return fontPath, fontFlags, fr, fg, fb, baseSize, useShadow
    end
end

local function Ensure()
    if type(EnsureDB) == "function" then
        EnsureDB()
    end
end

local function GetUnitKey(frame)
    if not frame then return nil end
    local u = frame.unit
    if not u then
        return nil
    end
    if u == "player" or u == "target" or u == "focus" then
        return u
    end
    -- Treat boss preview / boss castbars as one group.
    if u == "boss" or (type(u) == "string" and u:match("^boss")) then
        return "boss"
    end
    return u
end

local function GetFontColor(g, fr, fg, fb)
    if not g then
        return fr, fg, fb
    end
    if g.castbarTextUseCustom then
        local r = tonumber(g.castbarTextR)
        local gg = tonumber(g.castbarTextG)
        local b = tonumber(g.castbarTextB)
        if r and gg and b then
            return r, gg, b
        end
    end
    return fr, fg, fb
end



local function ApplyPreviewInterruptibleColor(frame, unitKey, g)
    if not (frame and frame._msufIsPreview and frame.statusBar) then return end

    -- Boss previews are handled by the Boss module (it applies the user-configured colors directly).
    if unitKey == "boss" then return end

    g = g or {}

    -- Player preview must respect the optional Player Castbar Override color (Colors menu).
    -- This should match the real player castbar fill whenever the override is enabled.
    if unitKey == "player" and g.playerCastbarOverrideEnabled then
        local mode = g.playerCastbarOverrideMode
        local r, gg, b

        if mode == "CUSTOM" then
            r  = tonumber(g.playerCastbarOverrideR)
            gg = tonumber(g.playerCastbarOverrideG)
            b  = tonumber(g.playerCastbarOverrideB)
        else
            local _, classToken = UnitClass("player")
            if classToken then
                if type(_G.MSUF_GetClassBarColor) == "function" then
                    r, gg, b = _G.MSUF_GetClassBarColor(classToken)
                end
                if (not r) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                    local c = RAID_CLASS_COLORS[classToken]
                    r, gg, b = c.r, c.g, c.b
                end
            end
        end

        if r and gg and b then
            if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
                _G.MSUF_SetStatusBarColorIfChanged(frame.statusBar, r, gg, b, 1)
            elseif frame.statusBar.SetStatusBarColor then
                frame.statusBar:SetStatusBarColor(r, gg, b, 1)
            end
            return
        end
    end

    -- Default preview: interruptible cast color as configured in Colors menu.
    local ir, ig, ib, nr, ng, nb
    if type(_G.MSUF_ResolveCastbarColors) == "function" then
        ir, ig, ib, nr, ng, nb = _G.MSUF_ResolveCastbarColors()
    end
    if not (ir and ig and ib) then
        -- Fallback (should never happen).
        ir, ig, ib = 0.2, 0.8, 0.8
    end
    if not (nr and ng and nb) then
        nr, ng, nb = 0.9, 0.1, 0.1
    end

    if type(_G.MSUF_Castbar_ApplyNonInterruptibleTint) == "function" then
        -- Preview is always shown as interruptible (we don't simulate shielded casts here).
        _G.MSUF_Castbar_ApplyNonInterruptibleTint(frame, false, nr, ng, nb, 1, ir, ig, ib, 1, false)
    elseif type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(frame.statusBar, ir, ig, ib, 1)
    elseif frame.statusBar.SetStatusBarColor then
        frame.statusBar:SetStatusBarColor(ir, ig, ib, 1)
    end
end
local function ApplyShadow(fs, useShadow)
    if not fs or not fs.SetShadowOffset then return end
    if useShadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function ApplyIconAndBarLayout(frame, unitKey, g)
    if not frame or not frame.statusBar then return end
    if not g then return end

    local showIcon = (g.castbarShowIcon ~= false)
    if frame and frame._msufIsPreview then
        -- In Edit Mode previews we ALWAYS show an icon for positioning (even if disabled in settings).
        showIcon = true
    end
    local iconOX = tonumber(g.castbarIconOffsetX) or 0
    local iconOY = tonumber(g.castbarIconOffsetY) or 0

    if unitKey == "boss" then
        if g.showBossCastIcon ~= nil then
            showIcon = (g.showBossCastIcon ~= false)
        end
        iconOX = tonumber(g.bossCastIconOffsetX) or iconOX
        iconOY = tonumber(g.bossCastIconOffsetY) or iconOY
    else
        local prefix = (unitKey == "player" and "castbarPlayer") or (unitKey == "target" and "castbarTarget") or (unitKey == "focus" and "castbarFocus") or nil
        if prefix then
            if g[prefix .. "ShowIcon"] ~= nil then
                showIcon = (g[prefix .. "ShowIcon"] ~= false)
            end
            if g[prefix .. "IconOffsetX"] ~= nil then
                iconOX = tonumber(g[prefix .. "IconOffsetX"]) or iconOX
            end
            if g[prefix .. "IconOffsetY"] ~= nil then
                iconOY = tonumber(g[prefix .. "IconOffsetY"]) or iconOY
            end
        end
    end

    local icon = frame.icon
    local statusBar = frame.statusBar
    local backgroundBar = frame.backgroundBar
    local width = (frame.GetWidth and frame:GetWidth()) or 0
    local height = (frame.GetHeight and frame:GetHeight()) or 0
    if width <= 0 then width = 250 end
    if height <= 0 then height = 18 end

    local iconDetached = (iconOX ~= 0 or iconOY ~= 0)
    local iconSize = height

    if icon then
        if frame and frame._msufIsPreview and icon.SetTexture then
            icon:SetTexture(136235) -- generic spell icon
        end
        local desiredParent = iconDetached and statusBar or frame
        if icon.GetParent and icon.SetParent and icon:GetParent() ~= desiredParent then
            icon:SetParent(desiredParent)
        end
        icon:SetShown(showIcon)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", frame, "LEFT", iconOX, iconOY)
        icon:SetSize(iconSize, iconSize)
        if icon.SetDrawLayer then
            icon:SetDrawLayer("OVERLAY", 7)
        end
    end

    statusBar:ClearAllPoints()
    if showIcon and icon and not iconDetached then
        statusBar:SetPoint("LEFT", frame, "LEFT", iconSize + 1, 0)
        statusBar:SetWidth(width - (iconSize + 1))
    else
        statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
        statusBar:SetWidth(width)
    end
    statusBar:SetHeight(height - 2)

    if backgroundBar and statusBar then
        backgroundBar:ClearAllPoints()
        backgroundBar:SetAllPoints(statusBar)
    end
end

local function ApplyFontsAndTextLayout(frame, unitKey, g)
    if not frame or not g then return end
    if not frame.statusBar then return end

    local fontPath, fontFlags, fr, fg, fb, baseSize, useShadow = MSUF_GetGlobalFontSettings_Resolved()
    fr, fg, fb = GetFontColor(g, fr, fg, fb)

    -- Global spell name size override
    local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
    local globalSize = (globalOverride and globalOverride > 0) and globalOverride or (baseSize or 14)

    local spellSize = globalSize
    local timeSize = spellSize

    if unitKey == "boss" then
        local bossSize = tonumber(g.bossCastSpellNameFontSize)
        if bossSize and bossSize > 0 then
            spellSize = math.floor(bossSize + 0.5)
        end
        local bossTime = tonumber(g.bossCastTimeFontSize)
        if bossTime and bossTime > 0 then
            timeSize = math.floor(bossTime + 0.5)
        else
            timeSize = spellSize
        end
    else
        local prefix = (unitKey == "player" and "castbarPlayer") or (unitKey == "target" and "castbarTarget") or (unitKey == "focus" and "castbarFocus") or nil
        if prefix then
            local ov = tonumber(g[prefix .. "SpellNameFontSize"]) or 0
            if ov and ov > 0 then
                spellSize = ov
            end
            local tov = tonumber(g[prefix .. "TimeFontSize"]) or 0
            if tov and tov > 0 then
                timeSize = tov
            else
                timeSize = spellSize
            end
        end
    end

    if frame.castText and frame.castText.SetFont then
        frame.castText:SetFont(fontPath, spellSize, fontFlags)
        if frame.castText.SetTextColor then
            frame.castText:SetTextColor(fr, fg, fb, 1)
        end
        ApplyShadow(frame.castText, useShadow)
    end

    if frame.timeText and frame.timeText.SetFont then
        frame.timeText:SetFont(fontPath, timeSize, fontFlags)
        if frame.timeText.SetTextColor then
            frame.timeText:SetTextColor(fr, fg, fb, 1)
        end
        ApplyShadow(frame.timeText, useShadow)
    end

    -- Layout offsets + per-unit show/hide are handled by shared Style helpers.
    if unitKey == "boss" then
        if type(_G.MSUF_ApplyBossCastbarTextsLayout) == "function" then
            local showName = (g.showBossCastName ~= false)
            local showTime = (g.showBossCastTime ~= false)
            local textOX = tonumber(g.bossCastTextOffsetX) or 0
            local textOY = tonumber(g.bossCastTextOffsetY) or 0
            local tx = tonumber(g.bossCastTimeOffsetX)
            local ty = tonumber(g.bossCastTimeOffsetY)
            if tx == nil then tx = -2 end
            if ty == nil then ty = 0 end

            _G.MSUF_ApplyBossCastbarTextsLayout(frame, {
                baselineTimeX = -2,
                baselineTimeY = 0,
                textOffsetX   = textOX,
                textOffsetY   = textOY,
                timeOffsetX   = tx,
                timeOffsetY   = ty,
                showName      = showName,
                showTime      = showTime,
                nameFontSize  = spellSize,
                timeFontSize  = timeSize,
            })
        end
    else
		if type(_G.MSUF_ApplyCastbarSpellNameLayout) == "function" then
			-- Guard against Midnight/Beta "secret value" arithmetic inside the style helper.
			-- If it throws, fall back to a simple LEFT-anchor layout (no width math).
			local ok = pcall(_G.MSUF_ApplyCastbarSpellNameLayout, frame, unitKey)
			if not ok then
				local showName = (g.castbarShowSpellName ~= false)
				local ox, oy = 0, 0
				if unitKey == "player" then
					if g.castbarPlayerShowSpellName ~= nil then
						showName = (g.castbarPlayerShowSpellName ~= false)
					end
					ox = tonumber(g.castbarPlayerTextOffsetX) or 0
					oy = tonumber(g.castbarPlayerTextOffsetY) or 0
				elseif unitKey == "target" then
					if g.castbarTargetShowSpellName ~= nil then
						showName = (g.castbarTargetShowSpellName ~= false)
					end
					ox = tonumber(g.castbarTargetTextOffsetX) or 0
					oy = tonumber(g.castbarTargetTextOffsetY) or 0
				elseif unitKey == "focus" then
					if g.castbarFocusShowSpellName ~= nil then
						showName = (g.castbarFocusShowSpellName ~= false)
					end
					ox = tonumber(g.castbarFocusTextOffsetX) or 0
					oy = tonumber(g.castbarFocusTextOffsetY) or 0
				end

				if frame.castText and frame.statusBar then
					frame.castText:Show()
					if type(_G.MSUF_SetAlphaIfChanged) == "function" then
						_G.MSUF_SetAlphaIfChanged(frame.castText, showName and 1 or 0)
					else
						frame.castText:SetAlpha(showName and 1 or 0)
					end
					if not showName then
						if type(_G.MSUF_SetTextIfChanged) == "function" then
							_G.MSUF_SetTextIfChanged(frame.castText, "")
						else
							frame.castText:SetText("")
						end
					end

					if type(_G.MSUF_SetPointIfChanged) == "function" then
						_G.MSUF_SetPointIfChanged(frame.castText, "LEFT", frame.statusBar, "LEFT", 2 + ox, 0 + oy)
					else
						frame.castText:ClearAllPoints()
						frame.castText:SetPoint("LEFT", frame.statusBar, "LEFT", 2 + ox, 0 + oy)
					end
					if frame.castText.SetJustifyH then
						if type(_G.MSUF_SetJustifyHIfChanged) == "function" then
							_G.MSUF_SetJustifyHIfChanged(frame.castText, "LEFT")
						else
							frame.castText:SetJustifyH("LEFT")
						end
					end
				end
			end
		end

        if type(_G.MSUF_ApplyCastbarTimeTextLayout) == "function" then
            -- Guard against Midnight/Beta "secret value" arithmetic inside the style helper.
            -- If it throws, fall back to a simple RIGHT-anchor layout (no width math).
            local ok = pcall(_G.MSUF_ApplyCastbarTimeTextLayout, frame, unitKey)
            if not ok then
                local tx, ty
                if unitKey == "target" then
                    tx = g.castbarTargetTimeOffsetX
                    ty = g.castbarTargetTimeOffsetY
                elseif unitKey == "focus" then
                    tx = g.castbarFocusTimeOffsetX
                    ty = g.castbarFocusTimeOffsetY
                else
                    tx = g.castbarPlayerTimeOffsetX
                    ty = g.castbarPlayerTimeOffsetY
                end

                if tx == nil then tx = g.castbarPlayerTimeOffsetX end
                if ty == nil then ty = g.castbarPlayerTimeOffsetY end

                tx = tonumber(tx)
                ty = tonumber(ty)
                if tx == nil then tx = -2 end
                if ty == nil then ty = 0 end

                if frame.timeText and frame.statusBar then
                    frame.timeText:Show()

                    -- Respect the show-cast-time toggle even in fallback mode
                    local showTime = true
                    if type(_G.MSUF_IsCastTimeEnabled) == "function" then
                        showTime = _G.MSUF_IsCastTimeEnabled(frame)
                    else
                        if unitKey == "player" then
                            showTime = (g.showPlayerCastTime ~= false)
                        elseif unitKey == "target" then
                            showTime = (g.showTargetCastTime ~= false)
                        elseif unitKey == "focus" then
                            showTime = (g.showFocusCastTime ~= false)
                        end
                    end

                    if type(_G.MSUF_SetAlphaIfChanged) == "function" then
                        _G.MSUF_SetAlphaIfChanged(frame.timeText, showTime and 1 or 0)
                    else
                        frame.timeText:SetAlpha(showTime and 1 or 0)
                    end

                    if type(_G.MSUF_SetPointIfChanged) == "function" then
                        _G.MSUF_SetPointIfChanged(frame.timeText, "RIGHT", frame.statusBar, "RIGHT", tx, ty)
                    else
                        frame.timeText:ClearAllPoints()
                        frame.timeText:SetPoint("RIGHT", frame.statusBar, "RIGHT", tx, ty)
                    end

                    if type(_G.MSUF_SetJustifyHIfChanged) == "function" then
                        _G.MSUF_SetJustifyHIfChanged(frame.timeText, "RIGHT")
                    elseif frame.timeText.SetJustifyH then
                        frame.timeText:SetJustifyH("RIGHT")
                    end
                end
            end
        end
    end

    if frame and frame._msufIsPreview then
        -- In Edit Mode previews we always keep both texts visible for layout/positioning.
        if frame.castText and frame.castText.Show then frame.castText:Show() end
        if frame.timeText and frame.timeText.Show then frame.timeText:Show() end
    end
end

local function IterateCastbarFrames(fn)
    -- Real castbars
    fn(_G.MSUF_PlayerCastbar)
    fn(_G.MSUF_TargetCastbar)
    fn(_G.MSUF_FocusCastbar)

    -- Previews
    fn(_G.MSUF_PlayerCastbarPreview)
    fn(_G.MSUF_TargetCastbarPreview)

    fn(_G.MSUF_FocusCastbarPreview)

    -- Boss previews (boss1 stable name + optional boss2..bossN)
    fn(_G.MSUF_BossCastbarPreview)
    do
        local n = tonumber(_G.MAX_BOSS_FRAMES) or 5
        if n < 1 or n > 12 then n = 5 end
        for i = 2, n do
            fn(_G["MSUF_BossCastbarPreview" .. i])
        end
    end

end

-- Preserve any pre-existing implementation for safety.
local _Old_Update = _G.MSUF_UpdateCastbarVisuals

function _G.MSUF_UpdateCastbarVisuals()
    Ensure()
    local g = (MSUF_DB and MSUF_DB.general) or {}

    -- Let any legacy visuals logic (bar colors/textures, etc.) run first,
    -- then we enforce the centralized text/icon styling so it always wins.
    if type(_Old_Update) == "function" and _Old_Update ~= _G.MSUF_UpdateCastbarVisuals then
        _Old_Update()
    end

    IterateCastbarFrames(function(frame)
        if not frame or not frame.statusBar then return end
        local unitKey = GetUnitKey(frame)
        if unitKey ~= "player" and unitKey ~= "target" and unitKey ~= "focus" and unitKey ~= "boss" then
            return
        end

        ApplyIconAndBarLayout(frame, unitKey, g)
        ApplyFontsAndTextLayout(frame, unitKey, g)
        ApplyPreviewInterruptibleColor(frame, unitKey, g)
    end)
end

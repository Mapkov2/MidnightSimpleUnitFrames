-- Castbars/MSUF_CastbarStyle.lua
-- MSUF Castbar Style (Step 2: Outline extraction)
--
-- Goal: centralized visual apply helpers for ALL castbars (player/target/focus/boss/previews).
-- outline/border logic here (no behavior change).

local addonName, ns = ...
ns = ns or {}

ns.MSUF_CastbarStyle = ns.MSUF_CastbarStyle or {}
local S = ns.MSUF_CastbarStyle

-- -------------------------------------------------
-- Castbar outline/border (color + thickness)
-- Menu: "Castbar border color" + "Outline thickness"
-- -------------------------------------------------

local function EnsureOutline(frame)
    if not frame or frame._msufOutline then return end

    local function MakeEdge()
        local t = frame:CreateTexture(nil, "OVERLAY")
        -- IMPORTANT: Use a WHITE base texture so SetVertexColor can tint it.
        -- If the base texture is black, vertex color multiplication keeps it black.
        t:SetColorTexture(1, 1, 1, 1)
        t:Hide()
        return t
    end

    frame._msufOutline = {
        top    = MakeEdge(),
        bottom = MakeEdge(),
        left   = MakeEdge(),
        right  = MakeEdge(),
    }
end

-- Internal implementation (mirrors the old MSUF_Castbars.lua logic 1:1)
function S:ApplyCastbarOutline(frame, force)
    if not frame then return end
    EnsureOutline(frame)
    local o = frame._msufOutline
    if not o then return end

    if type(EnsureDB) == "function" then
        EnsureDB()
    end
    local g = (MSUF_DB and MSUF_DB.general) or {}

    local thickness = tonumber(g.castbarOutlineThickness)
    if thickness == nil then thickness = 1 end
    thickness = math.floor(thickness + 0.5)
    if thickness < 0 then thickness = 0 end
    if thickness > 12 then thickness = 12 end

    local r = tonumber(g.castbarBorderR); if r == nil then r = 0 end
    local gg = tonumber(g.castbarBorderG); if gg == nil then gg = 0 end
    local b = tonumber(g.castbarBorderB); if b == nil then b = 0 end
    local a = tonumber(g.castbarBorderA); if a == nil then a = 1 end

    if thickness <= 0 then
        o.top:Hide(); o.bottom:Hide(); o.left:Hide(); o.right:Hide()
        frame._msufOutlineT = 0
        return
    end

    if force or frame._msufOutlineT ~= thickness then
        o.top:ClearAllPoints()
        -- OUTSIDE outline: thickness grows outward (true "outline"), not inward over the bar.
        -- Corner cleanup: top/bottom edges avoid overlapping left/right edges (no fat corners at thickness 5-6).
        o.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, thickness)
        o.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, thickness)
        o.top:SetHeight(thickness)

        o.bottom:ClearAllPoints()
        o.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, -thickness)
        o.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -thickness)
        o.bottom:SetHeight(thickness)

        o.left:ClearAllPoints()
        o.left:SetPoint("TOPLEFT", frame, "TOPLEFT", -thickness, thickness)
        o.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -thickness, -thickness)
        o.left:SetWidth(thickness)

        o.right:ClearAllPoints()
        o.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", thickness, thickness)
        o.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, -thickness)
        o.right:SetWidth(thickness)

        frame._msufOutlineT = thickness
    end

    if force or frame._msufOutlineR ~= r or frame._msufOutlineG ~= gg or frame._msufOutlineB ~= b or frame._msufOutlineA ~= a then
        o.top:SetVertexColor(r, gg, b, a)
        o.bottom:SetVertexColor(r, gg, b, a)
        o.left:SetVertexColor(r, gg, b, a)
        o.right:SetVertexColor(r, gg, b, a)

        frame._msufOutlineR, frame._msufOutlineG, frame._msufOutlineB, frame._msufOutlineA = r, gg, b, a
    end

    o.top:Show(); o.bottom:Show(); o.left:Show(); o.right:Show()
end

function S:ApplyCastbarOutlineToAll(force)
    local list = {
        _G.MSUF_PlayerCastbar,
        _G.MSUF_TargetCastbar,
        _G.MSUF_FocusCastbar,
        _G.MSUF_PlayerCastbarPreview,
        _G.MSUF_TargetCastbarPreview,
        _G.MSUF_FocusCastbarPreview,
        _G.MSUF_BossCastbarPreview,
    }

    -- Optional extra boss previews (boss2..bossN)
    do
        local n = tonumber(_G.MAX_BOSS_FRAMES) or 5
        if n < 1 or n > 12 then n = 5 end
        for i = 2, n do
            local f = _G["MSUF_BossCastbarPreview" .. i]
            if f then
                list[#list + 1] = f
            end
        end
    end

    for i = 1, #list do
        local f = list[i]
        if f and f.IsShown and f:CanChangeAttribute() ~= false then
            S:ApplyCastbarOutline(f, force)
        elseif f then
            S:ApplyCastbarOutline(f, force)
        end
    end

    local boss = _G.MSUF_BossCastbars
    if type(boss) == "table" then
        for i = 1, #boss do
            local f = boss[i]
            if f then
                S:ApplyCastbarOutline(f, force)
            end
        end
    end
end

-- -------------------------------------------------
-- Compatibility global exports (keep existing call sites working)
-- -------------------------------------------------
if not _G.MSUF_ApplyCastbarOutline then
    function _G.MSUF_ApplyCastbarOutline(frame, force)
        return S:ApplyCastbarOutline(frame, force)
    end
end

if not _G.MSUF_ApplyCastbarOutlineToAll then
    function _G.MSUF_ApplyCastbarOutlineToAll(force)
        return S:ApplyCastbarOutlineToAll(force)
    end
end

-- ==============================================================
-- Fill direction live-apply (Options -> Castbars -> Fill direction)
--
-- Regression note:
-- The options menu calls MSUF_UpdateCastbarFillDirection(), but older builds relied on
-- side-effects during Cast() to update ReverseFill. In 12.0, timer direction is
-- elapsed-vs-remaining; visual left/right fill still comes from SetReverseFill.
--
-- This function re-applies timer state + reverse fill to all known MSUF castbars and
-- previews and also re-anchors the player latency zone to match the chosen direction.
-- ==============================================================
_G.MSUF_UpdateCastbarFillDirection = function()
    -- Ensure castbars exist if the project exports the helper.
    if type(_G.MSUF_EnsureCastbars) == "function" then
        _G.MSUF_EnsureCastbars()
    end

    local function applyToFrame(f)
        if not f or not f.statusBar then return end

        -- Determine current cast type for this frame (channel vs cast) so we mirror correctly.
        local isChan = (f.MSUF_isChanneled == true) or (f.isChanneling == true)
        if f.isEmpower then
            isChan = true
        end

        -- IMPORTANT: compute reverseFill from the canonical resolver (DB-driven).
        -- This must reflect the latest Options value immediately.
        local rf = (type(_G.MSUF_GetReverseFillSafe) == "function") and (_G.MSUF_GetReverseFillSafe(f, isChan) and true or false) or false

        -- If the bar is currently timer-driven, re-apply the timer direction using the stored duration object.
        -- (If nil, ApplyTimerDirection will fall back to ReverseFill only.)
        local durObj = f.MSUF_durationObj
        if type(_G.MSUF_ApplyCastbarTimerDirection) == "function" then
            _G.MSUF_ApplyCastbarTimerDirection(f.statusBar, durObj, rf, isChan)
        elseif f.statusBar.SetReverseFill then
            -- Fallback for ultra-legacy environments.
            f.statusBar:SetReverseFill(rf and true or false)
        end

        -- Latency zone is player-only; it must flip sides with direction.
        if f.latencyBar and type(_G.MSUF_PlayerCastbar_UpdateLatencyZone) == "function" then
            local durSec = f.MSUF_latencyLastDurSec
            if type(durSec) == "number" and durSec > 0 then
                _G.MSUF_PlayerCastbar_UpdateLatencyZone(f, isChan, durSec)
            else
                -- No cached duration -> just force anchor + hide.
                _G.MSUF_PlayerCastbar_UpdateLatencyZone(f, isChan, 0)
            end
        end

        -- If this frame is actively casting, force a lightweight recast so any
        -- bar-local cached fields (timer-driven flags, stripe anchoring, etc.)
        -- are recomputed under the new direction.
        local build = _G.MSUF_Driver_BuildCastStateFor
        if build and f.Cast and type(build) == "function" then
            local st = build(f)
            if st and st.active then
                f:Cast(st)
            end
        end

        -- Empower stage markers/segments anchor based on direction.
        -- Layout is handled inside the empower module via its own hooks, but we can nudge it
        -- by marking the layout pending and triggering a cheap visual refresh.
        if f.isEmpower then
            f.MSUF_empowerLayoutPending = true
        end
    end

    -- Real castbars
    applyToFrame(_G.MSUF_PlayerCastbar)
    applyToFrame(_G.MSUF_TargetCastbar)
    applyToFrame(_G.MSUF_FocusCastbar)

    -- Previews
    applyToFrame(_G.MSUF_PlayerCastbarPreview)
    applyToFrame(_G.MSUF_TargetCastbarPreview)
    applyToFrame(_G.MSUF_FocusCastbarPreview)

    -- Boss castbars + previews
    local n = tonumber(_G.MAX_BOSS_FRAMES) or 5
    if n < 1 or n > 12 then n = 5 end
    for i = 1, n do
        applyToFrame(_G["MSUF_boss" .. i .. "Castbar"])
        if i == 1 then
            applyToFrame(_G.MSUF_BossCastbarPreview)
        end
        applyToFrame(_G["MSUF_BossCastbarPreview" .. i])
    end

    -- If any centralized visuals refresh exists, run it so previews reflect immediately.
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
end


-- These helpers reduce drift between real castbars and previews
-- and provide a single source of truth for text anchor rules.

function S:ApplyBossCastbarTextsLayout(frame, opts)
    if not frame or not frame.statusBar or not frame.castText or not frame.timeText then return end
    local sb = frame.statusBar
    opts = opts or {}

    local bx = tonumber(opts.baselineTimeX); if bx == nil then bx = -2 end
    local by = tonumber(opts.baselineTimeY); if by == nil then by = 0 end

    local textOX = tonumber(opts.textOffsetX) or 0
    local textOY = tonumber(opts.textOffsetY) or 0

    local tx = tonumber(opts.timeOffsetX); if tx == nil then tx = bx end
    local ty = tonumber(opts.timeOffsetY); if ty == nil then ty = by end

    frame.castText:ClearAllPoints()
    frame.timeText:ClearAllPoints()

    frame.castText:SetJustifyH("LEFT")
    frame.timeText:SetJustifyH("RIGHT")

    frame.castText:SetPoint("LEFT", sb, "LEFT", 2 + textOX, 0 + textOY)
    frame.timeText:SetPoint("RIGHT", sb, "RIGHT", tx, ty)
    -- Prevent overlap between spell name and time
    frame.castText:SetPoint("RIGHT", frame.timeText, "LEFT", -6, 0)

    -- Optional: drive visibility via alpha (keeps anchors stable)
    local showName = opts.showName
    if showName ~= nil then
        frame.castText:Show()
        if type(_G.MSUF_SetAlphaIfChanged) == "function" then
            _G.MSUF_SetAlphaIfChanged(frame.castText, showName and 1 or 0)
        else
            frame.castText:SetAlpha(showName and 1 or 0)
        end
        if (not showName) and (opts.clearIfHidden ~= false) then
            if type(_G.MSUF_SetTextIfChanged) == "function" then
                _G.MSUF_SetTextIfChanged(frame.castText, "")
            else
                frame.castText:SetText("")
            end
        end
    end

    local showTime = opts.showTime
    if showTime ~= nil then
        frame.timeText:Show()
        if type(_G.MSUF_SetAlphaIfChanged) == "function" then
            _G.MSUF_SetAlphaIfChanged(frame.timeText, showTime and 1 or 0)
        else
            frame.timeText:SetAlpha(showTime and 1 or 0)
        end
        if (not showTime) and (opts.clearIfHidden ~= false) then
            if type(_G.MSUF_SetTextIfChanged) == "function" then
                _G.MSUF_SetTextIfChanged(frame.timeText, "")
            else
                frame.timeText:SetText("")
            end
        end
    end

    -- Optional: font size overrides
    local nameSize = tonumber(opts.nameFontSize)
    if nameSize and nameSize > 0 then
        local font, _, flags = frame.castText:GetFont()
        if font then
            frame.castText:SetFont(font, nameSize, flags)
        end
    end

    local timeSize = tonumber(opts.timeFontSize)
    if timeSize and timeSize > 0 then
        local font, _, flags = frame.timeText:GetFont()
        if font then
            frame.timeText:SetFont(font, timeSize, flags)
        end
    end
end

local function GetTimeOffsetsForUnit(g, unitKey)
    local tx, ty
    if unitKey == "player" then
        tx = g.castbarPlayerTimeOffsetX
        ty = g.castbarPlayerTimeOffsetY
    elseif unitKey == "target" then
        tx = g.castbarTargetTimeOffsetX
        ty = g.castbarTargetTimeOffsetY
    elseif unitKey == "focus" then
        tx = g.castbarFocusTimeOffsetX
        ty = g.castbarFocusTimeOffsetY
    end

    if tx == nil then tx = g.castbarPlayerTimeOffsetX end
    if ty == nil then ty = g.castbarPlayerTimeOffsetY end

    tx = tonumber(tx)
    ty = tonumber(ty)

    if tx == nil then tx = -2 end
    if ty == nil then ty = 0 end
    return tx, ty
end

local function GetShowTimeForUnit(g, unitKey, frame)
    if type(_G.MSUF_IsCastTimeEnabled) == "function" then
        -- Prefer the central helper if available
        if frame and frame.unit then
            return _G.MSUF_IsCastTimeEnabled(frame)
        end
        return _G.MSUF_IsCastTimeEnabled({ unit = unitKey })
    end

    if unitKey == "player" then
        return g.showPlayerCastTime ~= false
    elseif unitKey == "target" then
        return g.showTargetCastTime ~= false
    elseif unitKey == "focus" then
        return g.showFocusCastTime ~= false
    end
    return true
end

function S:ApplyCastbarTimeTextLayout(frame, unitKey)
    if not frame or not frame.timeText or not frame.statusBar then return end
    unitKey = unitKey or frame.unit
    if not unitKey then return end

    if type(EnsureDB) == "function" then
        EnsureDB()
    end
    local g = (MSUF_DB and MSUF_DB.general) or {}

    local showTime = GetShowTimeForUnit(g, unitKey, frame)

    -- Keep the fontstring alive (for layout), but hide via alpha when disabled
    frame.timeText:Show()
    if type(_G.MSUF_SetAlphaIfChanged) == "function" then
        _G.MSUF_SetAlphaIfChanged(frame.timeText, showTime and 1 or 0)
    else
        frame.timeText:SetAlpha(showTime and 1 or 0)
    end
    if not showTime then
        if type(_G.MSUF_SetTextIfChanged) == "function" then
            _G.MSUF_SetTextIfChanged(frame.timeText, "")
        else
            frame.timeText:SetText("")
        end
    end

    local tx, ty = GetTimeOffsetsForUnit(g, unitKey)
    if type(_G.MSUF_SetPointIfChanged) == "function" then
        _G.MSUF_SetPointIfChanged(frame.timeText, "RIGHT", frame.statusBar, "RIGHT", tx, ty)
    else
        frame.timeText:ClearAllPoints()
        frame.timeText:SetPoint("RIGHT", frame.statusBar, "RIGHT", tx, ty)
    end
    if type(_G.MSUF_SetJustifyHIfChanged) == "function" then
        _G.MSUF_SetJustifyHIfChanged(frame.timeText, "RIGHT")
    else
        frame.timeText:SetJustifyH("RIGHT")
    end
end

-- Global compatibility exports (used by BossCastbars + preview hook)
_G.MSUF_ApplyBossCastbarTextsLayout = function(frame, opts)
    return S:ApplyBossCastbarTextsLayout(frame, opts)
end

_G.MSUF_ApplyCastbarTimeTextLayout = function(frame, unitKey)
    return S:ApplyCastbarTimeTextLayout(frame, unitKey)
end

-- -------------------------------------------------
-- Shared spell-name (castText) layout helper
-- -------------------------------------------------
-- Mirrors the existing DB keys used by Options/Edit Mode:
--   g.castbarShowSpellName (global)
--   g.castbar<Player|Target|Focus>ShowSpellName (per unit)
--   g.castbar<Player|Target|Focus>TextOffsetX/Y

local function GetSpellNameLayoutForUnit(g, unitKey)
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

    return showName, ox, oy
end

function S:ApplyCastbarSpellNameLayout(frame, unitKey)
    if not frame or not frame.castText or not frame.statusBar then return end
    unitKey = unitKey or frame.unit
    if not unitKey then return end

    if type(EnsureDB) == "function" then
        EnsureDB()
    end
    local g = (MSUF_DB and MSUF_DB.general) or {}

    local showName, ox, oy = GetSpellNameLayoutForUnit(g, unitKey)

    -- Show/hide via alpha (keep FontString alive for layout)
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
        return
    end

    -- -------------------------------------------------
    -- Secret-safe spell name shortening
    --  * No string ops, no GetStringWidth, no pcall.
    --  * Constrain FontString WIDTH + alignment only.
    -- -------------------------------------------------
    local mode = tonumber(g.castbarSpellNameShortening) or 0

    -- Boss castbars may have their own overrides (keep fully optional / backward compatible)
    local isBoss = false
    if type(unitKey) == "string" then
        if unitKey == "boss" or string.sub(unitKey, 1, 4) == "boss" then
            isBoss = true
        end
    end
    if isBoss then
        if g.bossCastSpellNameShortening ~= nil then
            mode = tonumber(g.bossCastSpellNameShortening) or mode
        end
    end

	-- These must be numeric (Options store them in MSUF_DB.general)
	local maxLen = tonumber(g.castbarSpellNameMaxLen) or 0
	if maxLen <= 0 then maxLen = 12 end
	local reserved = tonumber(g.castbarSpellNameReservedSpace) or 0
	if reserved < 0 then reserved = 0 end

    -- Optional boss-specific maxLen / reservedSpace (fallback to global if unset)
    if isBoss then
        local bossMaxLen = g.bossCastSpellNameMaxLen or g.bossCastSpellNameMaxChars or g.bossSpellNameMaxLen
        local bossReserved = g.bossCastSpellNameReservedSpace or g.bossCastSpellNameReserved or g.bossSpellNameReservedSpace
        local ml = tonumber(bossMaxLen or 0) or 0
        local rs = tonumber(bossReserved or 0) or 0
        if ml and ml > 0 then maxLen = ml end
        if rs and rs > 0 then reserved = rs end
    end
    -- On/Off only (Options maps legacy values to 1). Any non-zero enables shortening at END.
    local shortenEnabled = (mode and mode > 0)

    -- Basic truncation setup
    if frame.castText.SetMaxLines then frame.castText:SetMaxLines(1) end
    if frame.castText.SetWordWrap then frame.castText:SetWordWrap(false) end

    -- If disabled: restore default "full" layout (no forced width clamp)
    if not shortenEnabled then
        frame.castText:ClearAllPoints()
        frame.castText:SetPoint("LEFT", frame.statusBar, "LEFT", 4 + (ox or 0), 0 + (oy or 0))
        if frame.timeText then
            frame.castText:SetPoint("RIGHT", frame.timeText, "LEFT", -4, 0)
        else
            frame.castText:SetPoint("RIGHT", frame.statusBar, "RIGHT", -4, 0)
        end
        if frame.castText.SetJustifyH then frame.castText:SetJustifyH("LEFT") end
        return
    end
    -- Available width (numeric only; secret-safe)
    local barW = (frame.statusBar.GetWidth and frame.statusBar:GetWidth()) or 0
    local timeW = 0
    if frame.timeText and frame.timeText.GetWidth and frame.timeText.GetAlpha then
        if (frame.timeText:GetAlpha() or 0) > 0 then
            timeW = frame.timeText:GetWidth() or 0
        end
    end

    local leftPad = 4
    local rightPad = 4
    local avail = 0
    if barW and barW > 0 then
        avail = barW - timeW - reserved - leftPad - rightPad
        if avail < 20 then avail = 20 end
    end

    -- Approx "max name length" -> pixel width
    local _, fontSize = (frame.castText.GetFont and frame.castText:GetFont())
    fontSize = tonumber(fontSize) or 12
    local est = (maxLen * (fontSize * 0.60)) + 6
    if est < 40 then est = 40 end
    if est > 800 then est = 800 end

    local finalW = est
    if avail and avail > 0 and avail < finalW then
        finalW = avail
    end

    -- Stable anchors: always left-anchored box; alignment decides which side is preserved.
    frame.castText:ClearAllPoints()
    frame.castText:SetPoint("LEFT", frame.statusBar, "LEFT", leftPad + (ox or 0), 0 + (oy or 0))
    frame.castText:SetWidth(finalW)
    if frame.castText.SetJustifyH then
        frame.castText:SetJustifyH("LEFT")
    end
end


_G.MSUF_ApplyCastbarSpellNameLayout = function(frame, unitKey)
    return S:ApplyCastbarSpellNameLayout(frame, unitKey)
end

-- Placeholders for later steps (kept for API stability)
-- -------------------------------------------------
function S:ApplyFillDirection(statusbar, direction)
    -- Runtime direction application lives in MSUF_CastbarRuntime.lua.
    -- 'direction' is kept for future refactors (L/R naming).
end

function S:ApplyTextAnchors(frame, style)
    -- placeholder
end

function S:ApplyAll(frame, state, style)
    -- placeholder
end

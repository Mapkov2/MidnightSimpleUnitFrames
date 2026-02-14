-- Castbars/MSUF_CastbarFrames.lua
-- Step 11: Move castbar frame construction helpers out of MSUF_Castbars.lua (safe refactor).
-- Contains ONLY constructors/builders (no runtime cast logic).

local _G = _G

function _G.MSUF_BuildCastbarFrameElements(self)
    local height = 18
    self:SetHeight(height)
    if (not self:GetWidth()) or self:GetWidth() == 0 then self:SetWidth(250) end

    local background = self:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(self)
    background:SetColorTexture(0, 0, 0, 1)
    self.background = background

    local statusBar = CreateFrame("StatusBar", nil, self)
    statusBar:SetSize(self:GetWidth() - height - 1, self:GetHeight() - 2)
    statusBar:SetPoint("LEFT", self, "LEFT", height + 1, 0)

    local texture = MSUF_GetCastbarTexture and MSUF_GetCastbarTexture() or "Interface\\TargetingFrame\\UI-StatusBar"
    statusBar:SetStatusBarTexture(texture)
    statusBar:GetStatusBarTexture():SetHorizTile(true)
    local rf = MSUF_GetCastbarReverseFillForFrame(self, false)
    if _G.MSUF_ApplyCastbarTimerDirection then
        _G.MSUF_ApplyCastbarTimerDirection(statusBar, nil, rf)
    else
        statusBar:SetReverseFill(rf)
    end
    self.statusBar = statusBar

    -- Empower first-cast fix:
    -- Empower tick markers are laid out based on the *actual* rendered StatusBar width.
    -- On the first empower cast the bar can still report width=0/1, which sets
    -- frame.MSUF_empowerLayoutPending=true inside MSUF_LayoutEmpowerTicks().
    -- If we never re-run layout after the frame becomes visible/sized, ticks only appear
    -- starting with the *second* empower cast. Re-run layout when the bar is shown/sized.
    if statusBar and statusBar.HookScript and not statusBar._msufEmpowerLayoutHooked then
        statusBar._msufEmpowerLayoutHooked = true
        statusBar:HookScript("OnSizeChanged", function()
            if self and self.isEmpower and self.MSUF_empowerLayoutPending and type(_G.MSUF_LayoutEmpowerTicks) == "function" then
                _G.MSUF_LayoutEmpowerTicks(self)
            end
        end)
    end
    if self and self.HookScript and not self._msufEmpowerShowHooked then
        self._msufEmpowerShowHooked = true
        self:HookScript("OnShow", function(f)
            if f and f.isEmpower and f.MSUF_empowerLayoutPending and type(_G.MSUF_LayoutEmpowerTicks) == "function" then
                _G.MSUF_LayoutEmpowerTicks(f)
            end
        end)
    end

    local icon = statusBar:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(height, height)
    icon:SetPoint("LEFT", self, "LEFT", 0, 0)
    self.icon = icon

    local backgroundBar = statusBar:CreateTexture(nil, "BACKGROUND")
    backgroundBar:SetAllPoints(statusBar)
    local bgTex = texture
    if type(_G.MSUF_GetCastbarBackgroundTexture) == "function" then
        local t = _G.MSUF_GetCastbarBackgroundTexture()
        if t and t ~= "" then
            bgTex = t
        end
    end
    backgroundBar:SetTexture(bgTex)
    backgroundBar:SetVertexColor(0.176, 0.176, 0.176, 1)
    self.backgroundBar = backgroundBar

    local castText = statusBar:CreateFontString(nil, "OVERLAY")
    castText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
    self.castText = castText
    local timeText = statusBar:CreateFontString(nil, "OVERLAY")
    timeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    timeText:SetPoint("RIGHT", statusBar, "RIGHT", -2, 0)
    timeText:SetText("")
    self.timeText = timeText

    if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(self, true) end
end

function _G.MSUF_CreateCastbarPreviewFrame(kind, frameName, opts)
    opts = opts or {}
    local parent = opts.parent or UIParent
    local w = tonumber(opts.width) or 250
    local h = tonumber(opts.height) or 18
    local sbH = tonumber(opts.statusBarHeight) or math.max(4, h - 2)

    local f = CreateFrame("Frame", frameName, parent, opts.template or "BackdropTemplate")
    f.unit = kind
    -- Mark as preview so centralized visuals can apply preview-only behavior:
    -- - always show icon in Edit Mode
    -- - apply preview fill color (from Colors menu)
    -- - keep texts visible for positioning
    -- Boss preview already did this; other previews must match.
    f._msufIsPreview = true
    f:SetClampedToScreen(true)
    f:SetFrameStrata(opts.strata or "DIALOG")
    f:SetSize(w, h)

    -- Outer frame background (behind everything). This is NOT the bar background.
    -- IMPORTANT: The bar background MUST be parented to the StatusBar (see boss preview),
    -- otherwise a parent texture can visually cover the fill animation.
    local frameBG = f:CreateTexture(nil, "BACKGROUND")
    frameBG:SetAllPoints(f)
    frameBG:SetColorTexture(0, 0, 0, opts.bgAlpha or 0.8)
    f._msufFrameBG = frameBG

    local statusBar = CreateFrame("StatusBar", nil, f)
    if f.GetFrameLevel and statusBar.SetFrameLevel then
        statusBar:SetFrameLevel(f:GetFrameLevel() + 1)
    end
    statusBar:SetPoint("LEFT", f, "LEFT", 0, 0)
    statusBar:SetSize(w, sbH)
    local tex = (type(MSUF_GetCastbarTexture) == "function" and MSUF_GetCastbarTexture()) or "Interface\\TargetingFrame\\UI-StatusBar"
    statusBar:SetStatusBarTexture(tex)
    local sbTex = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    if sbTex and sbTex.SetHorizTile then
        sbTex:SetHorizTile(true)
    end

    -- Bar background (must be a StatusBar region; see Boss preview layering).
    local barBG = statusBar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints(statusBar)
    barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    barBG:SetAlpha(0.25)
    f.backgroundBar = barBG

    -- Ensure the fill texture stays above the background in all cases.
    if sbTex and sbTex.SetDrawLayer then
        sbTex:SetDrawLayer("ARTWORK", 0)
    end

    statusBar:SetMinMaxValues(0, 1)
    if opts.initialValue ~= nil then
        statusBar:SetValue(tonumber(opts.initialValue) or 0)
    end
    if opts.hideFillTexture and statusBar.GetStatusBarTexture then
        local t = statusBar:GetStatusBarTexture()
        if t and t.SetAlpha then
            t:SetAlpha(0)
        end
        statusBar.MSUF_hideFillTexture = true
    end

    f.statusBar = statusBar

	    -- Player-only latency indicator (so Edit Mode previews can show it too).
	    -- This is only created for the player preview because the latency zone is a player-only feature.
	    if kind == "player" then
	        local latencyBar = statusBar:CreateTexture(nil, "OVERLAY")
	        latencyBar:SetColorTexture(1, 0, 0, 0.25)
	        latencyBar:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
	        latencyBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
	        latencyBar:SetWidth(0)
	        latencyBar:Hide()
	        f.latencyBar = latencyBar
	    end

    if opts.showIcon ~= false then
        local icon = f:CreateTexture(nil, "OVERLAY", nil, 7)
        local iconSize = tonumber(opts.iconSize) or h
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("LEFT", f, "LEFT", 0, 0)
        icon:SetTexture(opts.iconTexture or 136235) -- generic spell icon
        f.icon = icon
    end

    -- Text overlay frame: FontStrings must be ABOVE the StatusBar fill.
    -- Parent the texts to an overlay frame above the StatusBar so the fill never covers them.
    local textOverlay = CreateFrame("Frame", nil, f)
    textOverlay:SetAllPoints(statusBar)
    if textOverlay.SetFrameLevel and statusBar.GetFrameLevel then
        textOverlay:SetFrameLevel(statusBar:GetFrameLevel() + 10)
    end
    f._msufTextOverlay = textOverlay

    local castText = textOverlay:CreateFontString(nil, "OVERLAY")
    local fontPath, fontSize, flags = GameFontHighlight:GetFont()
    castText:SetFont(fontPath, fontSize, flags)
    castText:SetJustifyH("LEFT")
    castText:SetPoint("LEFT", textOverlay, "LEFT", 2, 0)

    local label = opts.label
    if not label then
        if kind == "player" then label = "Player castbar preview"
        elseif kind == "target" then label = "Target castbar preview"
        elseif kind == "focus" then label = "Focus castbar preview"
        elseif kind == "boss" then label = "Boss castbar preview"
        else label = "Castbar preview"
        end
    end
    castText:SetText(label)
    f.castText = castText

    local showTime = opts.showTime
    if showTime == nil then showTime = true end
    if showTime then
        local timeText = textOverlay:CreateFontString(nil, "OVERLAY")
        timeText:SetFont(fontPath, fontSize, flags)
        timeText:SetJustifyH("RIGHT")
        timeText:SetPoint("RIGHT", textOverlay, "RIGHT", -2, 0)
        timeText:SetText(opts.timeLabel or "3.2")
        f.timeText = timeText
    end

    if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(f, true) end


    return f
end

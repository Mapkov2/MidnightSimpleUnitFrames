-- ============================================================================
-- MSUF_EM2_Movers.lua — v9 Ticker-driven
-- Movers are dumb overlays. All drag math lives in Ticker.lua.
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Movers = {}
EM2.Movers = Movers

local max = math.max
local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local round = function(n) return n + (2^52 + 2^51) - (2^52 + 2^51) end

local function T()
    return _G.MSUF_THEME or {
        bgR=0.08, bgG=0.09, bgB=0.10,
        edgeR=0.20, edgeG=0.30, edgeB=0.50,
        textR=0.92, textG=0.94, textB=1.00,
        titleR=1.00, titleG=0.82, titleB=0.00,
    }
end

local movers = {}
local moverParent

local function IsGroupPreviewMover(key)
    if key ~= "group_party" and key ~= "group_raid" then return false end
    return _G.MSUF_GroupPreviewActive and true or false
end

local function SyncMoverToFrame(mover, frame)
    if not frame then return end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return end
    local fS = frame:GetEffectiveScale()
    local uiS = UIParent:GetEffectiveScale()
    local ratio = fS / uiS
    local w = round((r - l) * ratio)
    local h = round((t - b) * ratio)
    local x = round(l * ratio)
    local y = round(t * ratio - UIParent:GetHeight())
    mover:ClearAllPoints()
    mover:SetSize(w, h)
    mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
end

local function CreateMover(key, cfg)
    local th = T()

    local mover = CreateFrame("Button", nil, moverParent)
    mover:SetSize(100, 30)
    mover:SetFrameStrata("FULLSCREEN"); mover:SetFrameLevel(300)
    mover:SetMovable(true); mover:RegisterForDrag("LeftButton")
    mover:EnableMouse(true); mover:SetClampedToScreen(true)
    mover._barKey = key

    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
    mover._bg = bg

    local brd = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    brd:SetAllPoints(); brd:SetFrameLevel(max(0, mover:GetFrameLevel() - 1))
    brd:SetBackdrop({ edgeFile = W8, edgeSize = 1 })
    brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
    mover._brd = brd

    local label = mover:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 10, "OUTLINE"); label:SetPoint("CENTER")
    label:SetTextColor(th.textR, th.textG, th.textB, 0.85); label:SetText(cfg.label or key)
    mover._label = label

    local coordFS = mover:CreateFontString(nil, "OVERLAY")
    coordFS:SetFont(FONT, 9, "OUTLINE"); coordFS:SetPoint("TOP", mover, "BOTTOM", 0, -2)
    coordFS:SetTextColor(th.titleR, th.titleG, th.titleB, 0.90); coordFS:Hide()
    mover._coordFS = coordFS

    mover:SetScript("OnEnter", function(self)
        if self._dragging then return end
        local t = T()
        self._bg:SetColorTexture(t.bgR+0.05, t.bgG+0.05, t.bgB+0.08, 0.75)
        self._brd:SetBackdropBorderColor(t.titleR, t.titleG, t.titleB, 0.80)
        if self._label:IsShown() then self._label:SetTextColor(1, 1, 1, 1) end
    end)
    mover:SetScript("OnLeave", function(self)
        if self._dragging then return end
        local t = T()
        self._bg:SetColorTexture(t.bgR, t.bgG, t.bgB, 0.55)
        self._brd:SetBackdropBorderColor(t.edgeR, t.edgeG, t.edgeB, 0.60)
        if self._label:IsShown() then self._label:SetTextColor(t.textR, t.textG, t.textB, 0.85) end
    end)

    -- Hide label when preview is active (preview frame already shows unit name)
    function mover:UpdateLabelVisibility()
        if (_G.MSUF_PreviewTestMode or IsGroupPreviewMover(self._barKey)) and not self._dragging then
            self._label:Hide()
            self._bg:SetColorTexture(0, 0, 0, 0)
            self._brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.25)
        else
            self._label:Show()
            self._bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
            self._brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
        end
    end

    -- Drag → delegate to Ticker
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self._dragging = true
        self._coordFS:Show()

        if EM2.State then EM2.State.SetUnitKey(key) end
        if EM2.HUD and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
        if cfg and cfg.popupType == "group" and type(_G.MSUF_Group_SyncPreview) == "function" then
            _G.MSUF_Group_SyncPreview()
        end

        if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
            _G.MSUF_EM_UndoBeforeChange("unit", key)
        end

        if EM2.Ticker then EM2.Ticker.BeginDrag(self, key, cfg) end
    end)

    mover:SetScript("OnDragStop", function(self)
        self._dragging = false
        self._coordFS:Hide()

        if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

        local moved = false
        if EM2.Ticker then moved = EM2.Ticker.EndDrag() end

        -- Restore hover
        local t = T()
        self._bg:SetColorTexture(t.bgR, t.bgG, t.bgB, 0.55)
        self._brd:SetBackdropBorderColor(t.edgeR, t.edgeG, t.edgeB, 0.60)
        self._label:SetTextColor(t.textR, t.textG, t.textB, 0.85)
    end)

    -- Click → popup
    mover:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        if EM2.State then EM2.State.SetUnitKey(key) end
        if EM2.HUD then EM2.HUD.RefreshUnitSelector() end
        if EM2.Popups and EM2.Popups.Open then EM2.Popups.Open(key, self) end
    end)

    movers[key] = mover
    local frame = cfg.getFrame and cfg.getFrame()
    if frame then SyncMoverToFrame(mover, frame) end
    return mover
end

function Movers.Show()
    if not moverParent then
        moverParent = CreateFrame("Frame", "MSUF_EM2_MoverParent", UIParent)
        moverParent:SetAllPoints(UIParent); moverParent:SetFrameStrata("FULLSCREEN")
    end
    moverParent:Show()
    local reg = EM2.Registry and EM2.Registry.All()
    if not reg then return end
    for k, c in pairs(reg) do
        if not movers[k] then CreateMover(k, c) end
        local m = movers[k]
        local f = c.getFrame and c.getFrame()
        if f then SyncMoverToFrame(m, f); m:Show(); m:UpdateLabelVisibility() else m:Hide() end
    end
end

function Movers.Hide()
    if moverParent then moverParent:Hide() end
    for _, m in pairs(movers) do m:Hide() end
end
function Movers.IsShown() return moverParent and moverParent:IsShown() or false end
function Movers.All() return movers end
function Movers.Get(k) return movers[k] end

function Movers.SyncAll()
    if not moverParent or not moverParent:IsShown() then return end
    if EM2.Ticker and EM2.Ticker.IsDragging() then return end
    for k, m in pairs(movers) do
        local c = EM2.Registry and EM2.Registry.Get(k)
        if c then
            local f = c.getFrame and c.getFrame()
            if f then SyncMoverToFrame(m, f); m:Show(); m:UpdateLabelVisibility() end
        end
    end
end

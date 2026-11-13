-- Group preview HandleView owner.
local _, MSUF = ...
local M = MSUF.MSUF2
local FILE = "Menu2/GroupPreview_Handles"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local Stage = {}
local max = math.max
local ManagerCombatLocked = M.PreviewContracts.RequireFields("GroupHandleView.HandleStorage", M.GroupPreviewHandleStorage,
    "ManagerCombatLocked").ManagerCombatLocked
local RequestBoxRefresh = M.PreviewContracts.RequireFields("GroupHandleView.HandleStorage", M.GroupPreviewHandleStorage, "RequestBoxRefresh").RequestBoxRefresh
local SelectSpellAura = M.PreviewContracts.RequireFields("GroupHandleView.HandleStorage", M.GroupPreviewHandleStorage, "SelectSpellAura").SelectSpellAura
local HANDLE_LABEL_HIT_HEIGHT = 14
local SPELL_DROP_ANCHOR_FRAC = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
-- A handle takes its universal Layer from its section; the tracked buff row shares the buffs section but has its own layer.
local GROUP_HANDLE_LAYER_BY_KEY = { trackedBuff = "trackedBuff" }
local GROUP_SECTION_LAYER = {
    text = "text", power = "power", portrait = "portrait", si = "si", sicons = "status",
    buffs = "buff", debuffs = "debuff", externals = "external", dispel = "dispelSymbol", dispelSymbol = "dispelSymbol",
}
-- Handle kinds whose offsets are one X/Y key pair of the group config, with the Y value used while it is unset.
local TEXT_NAME_COLOR, TEXT_HP_COLOR, TEXT_POWER_COLOR = { 0.30, 0.66, 1.00 }, { 0.25, 0.90, 0.42 }, { 0.95, 0.72, 0.18 }
-- Text handles in creation order: box._textHandles key, handle key, label, color, text kind, slot (nil = the whole group).
local TEXT_HANDLES = {
    { "name", "nameText", "NAME", TEXT_NAME_COLOR, "name" },
    { "hpGroup", "hpText", "HP", TEXT_HP_COLOR, "hp" },
    { "hpLeft", "hpTextLeft", "HP L", TEXT_HP_COLOR, "hp", "left" },
    { "hpCenter", "hpTextCenter", "HP C", TEXT_HP_COLOR, "hp", "center" },
    { "hpRight", "hpTextRight", "HP R", TEXT_HP_COLOR, "hp", "right" },
    { "powerGroup", "powerText", "POWER", TEXT_POWER_COLOR, "power" },
    { "powerLeft", "powerTextLeft", "PWR L", TEXT_POWER_COLOR, "power", "left" },
    { "powerCenter", "powerTextCenter", "PWR C", TEXT_POWER_COLOR, "power", "center" },
    { "powerRight", "powerTextRight", "PWR R", TEXT_POWER_COLOR, "power", "right" },
}
-- Aura lane, resource bar, portrait and dispel-symbol handles in creation order (the status and spell handles follow).
-- w/h default to 86x34, stage parents a handle on the preview stage, pool is the number of pooled aura icons and
-- fields are the flags the drag, nudge and render code read from the handle.
local LAYER_HANDLES = {
    { slot = "buffHandle", key = "buff", section = "buffs", color = { 0.36, 0.79, 0.36 }, label = "BUFFS", pool = 6,
        fields = { _cfgGroup = "buff" } },
    { slot = "trackedBuffHandle", key = "trackedBuff", section = "buffs", color = { 0.62, 0.78, 1.00 }, label = "TRACKED", pool = 4,
        fields = { _cfgGroup = "buff", _cfgTrackedBuff = true, _previewText = "Tracked Buff Icons" } },
    { slot = "debuffHandle", key = "debuff", section = "debuffs", color = { 0.89, 0.29, 0.29 }, label = "DEBUFFS", pool = 6,
        fields = { _cfgGroup = "debuff" } },
    { slot = "externalHandle", key = "external", section = "externals", color = { 0.30, 0.72, 1.00 }, label = "EXTERNAL", pool = 2,
        fields = { _cfgGroup = "externals", _openSettingsOnRightClick = true } },
    -- Resource bar handle. Live parity: only the detached bar owns free
    -- offsets (the embedded bar's texture cannot move on the live frame), so
    -- the render locks this handle while the bar is embedded; a simple click
    -- still opens its owning settings section like any other layer.
    { slot = "powerBarHandle", key = "powerBar", section = "power", color = { 0.30, 0.62, 0.98 }, label = "POWER", h = 16,
        fields = { _cfgPower = true, _previewText = "Resource Bar" } },
    -- Attached portraits can sit completely outside the mock frame. Keep their
    -- mouse handle on the preview stage so WoW does not clip hit-testing to
    -- the mock parent's bounds; rendering/offsets remain anchored to the mock.
    { slot = "portraitHandle", key = "portrait", section = "portrait", color = { 0.90, 0.42, 1.00 }, label = "PORTRAIT", w = 36, h = 36,
        stage = true, fields = { _cfgPortrait = true, _previewText = "Portrait" } },
    -- Dispel-type symbol row. Like the portrait it can sit outside the mock
    -- frame, so its mouse handle lives on the preview stage; rendering and
    -- offsets stay anchored to the mock. Five icon slots: one per dispel type in
    -- "one per dispel type" mode, of which only the first is used in TOP mode.
    { slot = "dispelSymbolHandle", key = "dispelSymbol", section = "dispelSymbol", color = { 0.30, 0.80, 1.00 }, label = "DISPEL",
        w = 44, h = 20, stage = true, pool = 5, fields = { _cfgDispelSymbol = true, _previewText = "Dispel Symbol" } },
}
local SPELL_HANDLE = { slot = "spellHandle", key = "si", section = "si", color = { 0.69, 0.50, 0.88 }, label = "SPELL", w = 44, h = 44,
    pool = 1, fields = { _cfgSpell = true } }
-- What Handles.Install returns for the group preview render layer.
local HANDLE_BUNDLE_KEYS = {
    "buffHandle", "trackedBuffHandle", "debuffHandle", "externalHandle", "powerBarHandle", "portraitHandle", "dispelSymbolHandle",
    "statusHandles", "spellHandle", "SelectHandle", "NudgeHandlePosition", "StopHandleDrag",
}

local function InteractionLevel(ns, mock, extra)
    local core = ns.UFPreviewCore
    if core and type(core.InteractionFrameLevel) == "function" then
        return core.InteractionFrameLevel(mock, extra)
    end
    return ((mock.GetFrameLevel and mock:GetFrameLevel()) or 0) + 140 + (tonumber(extra) or 0)
end
-- Cold paths only (scripted nudge, spell drop, release, text focus); the per-frame drag and key-repeat nudge paths
-- below keep these checks inline so they add no Lua call.
local function GroupGearClassification()
    return tostring(M.activeKey or ""):match("^gf_") and "action" or "navigation"
end
-- Registers the handle as a preview control and, when the helper exists, its open-settings gear.
local function RegisterHandleControls(st, handle, key, label)
    local box, M, T, Tr, PreviewHelpers = st.box, st.M, st.T, st.TR, st.PreviewHelpers
    local SelectHandle, OpenHandleSettings, RegisterPreviewControl = st.SelectHandle, st.OpenHandleSettings, st.RegisterPreviewControl
    handle._msuf2CommandAction = {
        kind = "button",
        historyMode = "none",
        interaction = "preview.handle.select",
        previewSurface = "group",
        previewHandleKey = key,
        previewScope = st.H.CurrentScope(),
        set = function()
            if handle.IsShown and not handle:IsShown() then return false end
            SelectHandle(handle)
            return box._selectedHandle == handle
        end,
    }
    RegisterPreviewControl(handle, "handle." .. tostring(key), label or key, "button", "ephemeral")
    if not PreviewHelpers.EnsurePreviewHandleGear then return end
    local gear = PreviewHelpers.EnsurePreviewHandleGear(handle, {
        T = T,
        Tr = Tr,
        shown = false,
        openSettings = OpenHandleSettings,
    })
    if not gear then return end
    gear._msuf2GroupPreviewOpenCommand = gear._msuf2GroupPreviewOpenCommand or {
        kind = "button",
        historyMode = "none",
        set = function() return OpenHandleSettings(handle) end,
    }
    RegisterPreviewControl(gear, "handle." .. tostring(key) .. ".open_settings",
        M.Format("Open %s settings", M.Tr(label or key)), "button", GroupGearClassification(), {
            historyMode = "none",
            help = "Opens the exact Group Frames settings section for this preview element.",
            command = gear._msuf2GroupPreviewOpenCommand,
        })
end

function Stage.BindHandleFactory(st)
    local box, M, T, Tr, WHITE8X8, PreviewHelpers, mock = st.box, st.M, st.T, st.TR, st.WHITE8X8, st.PreviewHelpers, st.mock
    local HandleText, RefreshHandleSelection, SelectHandle = st.HandleText, st.RefreshHandleSelection, st.SelectHandle
    local OpenHandleSettings, StartHandleDrag, StopHandleDrag = st.OpenHandleSettings, st.StartHandleDrag, st.StopHandleDrag
    -- Every handle of this install shares these scripts; each one only uses the frame it is called on.
    local function OnEnter(self)
        self._hovering = true
        RefreshHandleSelection(box)
        local showTooltip = GameTooltip and (not PreviewHelpers.ShouldShowPreviewHandleTooltip
            or PreviewHelpers.ShouldShowPreviewHandleTooltip(box))
        if not showTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(HandleText(self), 1, 1, 1)
        if self._locked then
            GameTooltip:AddLine((M.Tr and M.Tr("This preview layer is locked.")) or "This preview layer is locked.", 0.82, 0.82, 0.82, true)
        else
            GameTooltip:AddLine(Tr("Drag to move. Arrow keys nudge."), 0.82, 0.82, 0.82, true)
        end
        GameTooltip:AddLine(Tr("Right-click opens quick actions."), 0.50, 0.78, 0.92, true)
        GameTooltip:Show()
    end
    local function OnLeave(self)
        self._hovering = nil
        RefreshHandleSelection(box)
        if GameTooltip then GameTooltip:Hide() end
    end
    local function OnClick(self, button)
        if self._suppressNextClick then
            self._suppressNextClick = nil
            return
        end
        SelectHandle(self)
        if button ~= "RightButton" then return end
        if self._openSettingsOnRightClick == true then
            OpenHandleSettings(self)
        elseif PreviewHelpers.ShowPreviewHandleContext then
            PreviewHelpers.ShowPreviewHandleContext(self, {
                M = M,
                T = T,
                Tr = Tr,
                title = HandleText(self),
                openSettings = OpenHandleSettings,
            })
        end
    end
    local function OnMouseUp(self, button) StopHandleDrag(self, button, true) end
    local function OnDragStop(self, button) StopHandleDrag(self, button, false) end
    local function OnHide(self)
        StopHandleDrag(self, nil, false)
        if box._selectedHandle == self then SelectHandle(nil) end
    end
    local function CreatePreviewHandle(key, sectionKey, color, label, width, height, locked, parent)
        local handle = PixelLayoutRegion(CreateFrame("Button", nil, parent or mock, T.Template()), true)
        handle:SetSize(width or 32, height or 32)
        -- The colored label is part of the visible affordance. Without this,
        -- clicking its glyphs falls through to a different overlapping handle
        -- or the preview canvas and appears to route randomly.
        if handle.SetHitRectInsets then handle:SetHitRectInsets(0, 0, -HANDLE_LABEL_HIT_HEIGHT, 0) end
        handle:SetMovable(true)
        handle:EnableMouse(true)
        handle:EnableMouseWheel(true)
        if handle.SetPropagateMouseWheel then handle:SetPropagateMouseWheel(false) end
        if handle.RegisterForClicks then handle:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp") end
        if handle.RegisterForDrag then handle:RegisterForDrag("LeftButton") end
        PixelLayoutRegion(handle, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        handle:SetBackdropColor(color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, 0.42)
        handle:SetBackdropBorderColor(color[1], color[2], color[3], locked and 0.55 or 0.95)
        handle._key = key
        handle._sectionKey = sectionKey
        handle._previewLayerKey = GROUP_HANDLE_LAYER_BY_KEY[key] or GROUP_SECTION_LAYER[sectionKey]
        handle._locked = locked and true or false
        handle._color = color
        local selectFill = PixelLayoutRegion(handle:CreateTexture(nil, "OVERLAY", nil, 6))
        selectFill:SetAllPoints()
        selectFill:SetColorTexture(color[1], color[2], color[3], 0)
        handle._selectFill = selectFill
        local selectBorder = PixelLayoutRegion(CreateFrame("Frame", nil, handle, T.Template()))
        selectBorder:SetPoint("TOPLEFT", handle, "TOPLEFT", -2, 2)
        selectBorder:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", 2, -2)
        PixelLayoutRegion(selectBorder, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        selectBorder:SetBackdropColor(0, 0, 0, 0)
        selectBorder:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        selectBorder:Hide()
        handle._selectBorder = selectBorder
        local fs = T.Font(handle, "GameFontDisableSmall", label or key, { color[1], color[2], color[3], 0.95 })
        fs:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        fs:SetJustifyH("CENTER")
        handle._label = fs
        handle:SetScript("OnEnter", OnEnter)
        handle:SetScript("OnLeave", OnLeave)
        handle:SetScript("OnClick", OnClick)
        handle:SetScript("OnMouseWheel", st.ZoomWheel)
        handle:SetScript("OnMouseDown", StartHandleDrag)
        handle:SetScript("OnMouseUp", OnMouseUp)
        handle:SetScript("OnDragStart", StartHandleDrag)
        handle:SetScript("OnDragStop", OnDragStop)
        handle:HookScript("OnHide", OnHide)
        RegisterHandleControls(st, handle, key, label)
        box._handles[key] = handle
        box._handleList[#box._handleList + 1] = handle
        return handle
    end
    st.CreatePreviewHandle = CreatePreviewHandle
end

--- Creates the aura, power, portrait, dispel, status and spell indicator
--- handles plus the dynamic per-spell handle pool.
function Stage.CreateLayerHandles(st)
    local CreatePreviewHandle, H, StatusLabel, T, box = st.CreatePreviewHandle, st.H, st.StatusLabel, st.T, st.box
    local function CreateLayerHandle(row)
        local handle = CreatePreviewHandle(row.key, row.section, row.color, row.label, row.w or 86, row.h or 34, false,
            row.stage and st.dragParent or nil)
        for field, value in pairs(row.fields) do
            handle[field] = value
        end
        st[row.slot] = handle
    end
    for i = 1, #LAYER_HANDLES do
        CreateLayerHandle(LAYER_HANDLES[i])
    end
    local statusHandles = {}
    local statusSpecs = H.StatusSpecs()
    for i = 1, #statusSpecs do
        local spec = statusSpecs[i]
        local statusHandle = CreatePreviewHandle("status_" .. tostring(spec.value or i), "sicons", { 0.80, 0.67, 0.20 }, StatusLabel(spec), 78, 28, false)
        statusHandle._cfgStatus = true
        statusHandle._statusSpec = spec
        statusHandle._previewText = spec.text or "Status"
        statusHandles[#statusHandles + 1] = statusHandle
    end
    st.statusHandles = statusHandles
    CreateLayerHandle(SPELL_HANDLE)
    local spellIndicatorHandles = {}
    box._spellIndicatorHandles = spellIndicatorHandles
    local function SpellIndicatorHandleKey(item, index)
        local key = tostring(item and (item.key or item.slotKey) or index or "spell")
        key = key:gsub("[^%w_]+", "_")
        if key == "" then key = tostring(index or "spell") end
        return "si_" .. key
    end
    function box:EnsureSpellIndicatorHandle(item, index)
        if type(item) ~= "table" then return nil end
        local key = SpellIndicatorHandleKey(item, index)
        local handle = spellIndicatorHandles[key]
        if not handle then
            local c = item.color or { 0.69, 0.50, 0.88 }
            handle = CreatePreviewHandle(key, "si", { c[1] or 0.69, c[2] or 0.50, c[3] or 0.88 },
                tostring(item.display or item.auraName or "SPELL"):upper(), 44, 44, false)
            handle._cfgSpell = true
            spellIndicatorHandles[key] = handle
        end
        local identity = handle._cfgSpellItem or {}
        identity.specKey, identity.auraName = item.specKey, item.auraName
        handle._cfgSpellItem = identity
        handle._msufSpellIndicatorPlaced = item.spellIndicatorSlot == true and item or item.placed
        handle._previewText = item.display or item.auraName or "Spell"
        handle._msufSpellIndicatorPreviewKey = key
        return handle
    end
    function box:HideUnusedSpellIndicatorHandles(active)
        active = active or {}
        for key, handle in pairs(spellIndicatorHandles) do
            if not active[key] then handle:Hide() end
        end
    end
end

--- Spell drop target: cursor hit-testing, the drop guide and the
--- box:SetSpellDropTarget / box:DropSpellIndicatorAtCursor API.
function Stage.BindSpellDrop(st)
    local H, M, T, Tr, WHITE8X8, box, mock = st.H, st.M, st.T, st.TR, st.WHITE8X8, st.box, st.mock
    local SpellConfigForHandle, SpellPlacedForHandle, UpdateHint = st.SpellConfigForHandle, st.SpellPlacedForHandle, st.UpdateHint
    local function CursorPositionInUI()
        local x, y = GetCursorPosition()
        if not (x and y) then return nil end
        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        return x / scale, y / scale
    end
    local function CursorInsideFrame(frame)
        if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return false end
        local x, y = CursorPositionInUI()
        if not (x and y) then return false end
        local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        return left and right and top and bottom and x >= left and x <= right and y >= bottom and y <= top or false
    end
    local function EnsureSpellDropGuide()
        if box._spellDropGuide then return box._spellDropGuide end
        local guide = PixelLayoutRegion(CreateFrame("Frame", nil, mock, T.Template()))
        guide:SetAllPoints(mock)
        guide:EnableMouse(false)
        if guide.SetFrameLevel then guide:SetFrameLevel(InteractionLevel(st.MSUF, mock, 1)) end
        PixelLayoutRegion(guide, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 2 })
        guide._text = T.Font(guide, "GameFontNormal", "Drop to place spell icon", { 0.72, 0.90, 1, 1 })
        guide._text:SetPoint("BOTTOM", guide, "TOP", 0, 6)
        guide:Hide()
        box._spellDropGuide = guide
        return guide
    end
    function box:SetSpellDropTarget(active, spellLabel)
        local guide = EnsureSpellDropGuide()
        if not active then
            guide:Hide()
            guide._dropInside = nil
            guide._dropLabel = nil
            if self._hint then UpdateHint(self, self._selectedHandle) end
            return false
        end
        local inside = CursorInsideFrame(mock)
        if guide._dropInside ~= inside then
            guide._dropInside = inside
            if inside then
                guide:SetBackdropColor(0.12, 0.72, 0.38, 0.10)
                guide:SetBackdropBorderColor(0.22, 1.00, 0.55, 1)
                guide._text:SetText("Release to place and position")
                guide._text:SetTextColor(0.42, 1.00, 0.65, 1)
            else
                guide:SetBackdropColor(0.12, 0.50, 0.82, 0.07)
                guide:SetBackdropBorderColor(0.32, 0.76, 1.00, 0.95)
                guide._text:SetText("Drag onto the frame to place")
                guide._text:SetTextColor(0.72, 0.90, 1.00, 1)
            end
        end
        guide:Show()
        if self._hint and (guide._dropLabel ~= spellLabel or guide._hintInside ~= inside) then
            guide._dropLabel = spellLabel
            guide._hintInside = inside
            self._hint:SetText(string.format("%s   %s", tostring(spellLabel or Tr("Spell icon")),
                Tr(inside and "release to place at this position" or "drag onto the unit frame")))
        end
        return inside
    end
    function box:DropSpellIndicatorAtCursor(specKey, auraName)
        if ManagerCombatLocked(M) then return false, "combat-locked" end
        if not (specKey and auraName and auraName ~= "") then return false, "spell-required" end
        if not CursorInsideFrame(mock) then return false, "outside-frame" end
        local cursorX, cursorY = CursorPositionInUI()
        local left, bottom = mock:GetLeft(), mock:GetBottom()
        local width, height = mock:GetWidth(), mock:GetHeight()
        if not (cursorX and cursorY and left and bottom and width and height and width > 0 and height > 0) then
            return false, "preview-geometry-unavailable"
        end
        local kind = H.CurrentScope()
        local dropHandle = {
            _key = "si_drop_" .. tostring(specKey) .. ":" .. tostring(auraName),
            _cfgSpell = true,
            _cfgSpellItem = { specKey = specKey, auraName = auraName },
            _previewText = auraName,
        }
        local existingCfg = SpellConfigForHandle(dropHandle, false)
        local placedForSize = existingCfg and type(existingCfg.placed) == "table" and existingCfg.placed or {}
        local previewScale = tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
        if previewScale <= 0 then previewScale = 1 end
        local iconWidth = tonumber(placedForSize.size) or 18
        if (placedForSize.type or "icon") == "bar" then iconWidth = tonumber(placedForSize.barWidth) or (iconWidth * 3) end
        local iconHeight = tonumber(placedForSize.size) or 18
        iconWidth, iconHeight = iconWidth * previewScale, iconHeight * previewScale
        local rx = (cursorX - left) / width
        local ry = 1 - ((cursorY - bottom) / height)
        local anchor = st.ResolveAnchor(rx, ry)
        local frac = SPELL_DROP_ANCHOR_FRAC[anchor] or SPELL_DROP_ANCHOR_FRAC.CENTER
        local anchorX = cursorX + ((frac[1] - 0.5) * iconWidth)
        local anchorY = cursorY + ((frac[2] - 0.5) * iconHeight)
        local offX, offY = st.PointOffset(anchorX, anchorY, mock, anchor)
        local nextX, nextY = st.OffsetToConfig(offX, previewScale), st.OffsetToConfig(offY, previewScale)
        local placedSuccessfully = false
        local function PlaceSpellIcon()
            local cfg = SpellConfigForHandle(dropHandle, true)
            local placed = SpellPlacedForHandle(dropHandle, true)
            if not (placed and cfg) then return false end
            local conf = H.Conf(kind)
            local si = conf and conf.spellIndicators
            if si then si.enabled = true end
            cfg.enabled = true
            placed.type = (placed.type and placed.type ~= "none") and placed.type or "icon"
            placed.anchor, placed.x, placed.y = anchor, nextX, nextY
            SelectSpellAura(M, kind, si, specKey, auraName)
            st.RefreshGroupPreviewAfterMove(dropHandle)
            placedSuccessfully = true
            return true
        end
        local historyKey = "group:spellDrop:" .. tostring(kind) .. ":" .. tostring(specKey) .. ":" .. tostring(auraName)
        if type(M.RunWithHistory) == "function" then
            M.RunWithHistory("Place Spell Indicator", historyKey, PlaceSpellIcon)
        else
            PlaceSpellIcon()
            if placedSuccessfully then st.CheckpointHandleHistory(dropHandle, "Place") end
        end
        if not placedSuccessfully then return false, "spell-config-unavailable" end
        if M.RequestRefresh then M.RequestRefresh(nil, "gf-spell-drop-controls") end
        return true, anchor, nextX, nextY
    end
end

--- Text handles (name, HP and power groups/slots) and the
--- box:FocusTextSlot API.
function Stage.CreateTextHandles(st)
    local CreatePreviewHandle, H, box = st.CreatePreviewHandle, st.H, st.box
    local textHandles = {}
    for i = 1, #TEXT_HANDLES do
        local row = TEXT_HANDLES[i]
        local color, kind, slot = row[4], row[5], row[6]
        local handle = CreatePreviewHandle(row[2], "text", color, row[3], 74, 18, false)
        handle._cfgText = true
        handle._cfgTextKind = kind
        handle._cfgTextSlot = slot
        handle._previewText = H.TextLabel(kind, slot)
        if handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
        if handle.SetBackdropBorderColor then handle:SetBackdropBorderColor(color[1], color[2], color[3], 0) end
        if handle._label then handle._label:Hide() end
        textHandles[row[1]] = handle
    end
    box._textHandles = textHandles
    function box:FocusTextSlot(kind, slot, active)
        kind = H.NormalizeTextFocusKind(kind)
        slot = H.NormalizeTextFocusSlot(slot)
        self._msufMenuTextFocus = kind and { kind = kind, slot = slot, active = active == true } or nil
        RequestBoxRefresh(self, kind and "GROUP_PREVIEW_TEXT_FOCUS" or "GROUP_PREVIEW_TEXT_CLEAR_FOCUS")
        return true
    end
end

--- Public handle bundle consumed by the group preview render layer.
function Stage.BuildBundle(st)
    local bundle = {}
    for i = 1, #HANDLE_BUNDLE_KEYS do
        bundle[HANDLE_BUNDLE_KEYS[i]] = st[HANDLE_BUNDLE_KEYS[i]]
    end
    return bundle
end

M.GroupPreviewHandleView = Stage
Stage.InteractionLevel = InteractionLevel

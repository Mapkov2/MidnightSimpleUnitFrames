-- GroupIndicators: Spells responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.GroupIndicatorsParts
local AddCustomBuffSpellID = Parts.AddCustomBuffSpellID
local CUSTOM_BUFF_COLOR = Parts.CUSTOM_BUFF_COLOR
local CUSTOM_BUFF_LIMIT = Parts.CUSTOM_BUFF_LIMIT
local ClearCurrentSpellAura = Parts.ClearCurrentSpellAura
local Conf = Parts.Conf
local CurrentScope = Parts.CurrentScope
local CurrentSpellAura = Parts.CurrentSpellAura
local CurrentSpellConfig = Parts.CurrentSpellConfig
local CustomBuffInfo = Parts.CustomBuffInfo
local CustomBuffSpellID = Parts.CustomBuffSpellID
local CustomBuffSpellIDListText = Parts.CustomBuffSpellIDListText
local CustomBuffSpellIDs = Parts.CustomBuffSpellIDs
local DefaultCustomBuffPlaced = Parts.DefaultCustomBuffPlaced
local EffectiveSpellSpec = Parts.EffectiveSpellSpec
local GF = Parts.GF
local IsCustomBuffEntry = Parts.IsCustomBuffEntry
local PixelLayoutRegion = Parts.PixelLayoutRegion
local QueueSpellIndicators = Parts.QueueSpellIndicators
local RefreshGFPreview = Parts.RefreshGFPreview
local RegisterControl = Parts.RegisterControl
local RequestCustomBuffSpellData = Parts.RequestCustomBuffSpellData
local ResolveCustomBuffSpellIDs = Parts.ResolveCustomBuffSpellIDs
local SetCurrentSpellAura = Parts.SetCurrentSpellAura
local SpellIndicators = Parts.SpellIndicators
local SuggestedActivePlayerAuraID = Parts.SuggestedActivePlayerAuraID
local T = Parts.T
local Tr = Parts.Tr
local W = Parts.W
local WHITE_RGB = Parts.WHITE_RGB
local floor = Parts.floor
local issecretvalue = Parts.issecretvalue
local max = Parts.max
local min = Parts.min

local function SpellIndicatorRuntime()
    local gf = GF()
    return gf and gf.SpellIndicators
end
local function EnsureSpellDefaults(kind, specKey)
    local runtime = SpellIndicatorRuntime()
    if runtime and type(runtime.EnsureSpecConfig) == "function" and specKey then
        runtime.EnsureSpecConfig(SpellIndicators(kind), specKey)
    end
end
local function SpellConfigFor(kind, specKey, auraName, create)
    if not (specKey and auraName and auraName ~= "") then return nil end
    local cfg = SpellIndicators(kind)
    cfg.specs = cfg.specs or {}
    if create and not cfg.specs[specKey] then cfg.specs[specKey] = {} end
    local specCfg = cfg.specs[specKey]
    if create and specCfg and type(specCfg[auraName]) ~= "table" then specCfg[auraName] = { enabled = true, onlyOwn = true } end
    return specCfg and specCfg[auraName]
end
local function CurrentAuraInfo(kind)
    local runtime, specKey, auraName = SpellIndicatorRuntime(), EffectiveSpellSpec(kind), CurrentSpellAura(kind)
    local trackable = specKey and runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
    for i = 1, type(trackable) == "table" and #trackable or 0 do
        if trackable[i] and trackable[i].name == auraName then return trackable[i], specKey, auraName end
    end
    return nil, specKey, auraName
end
local function CurrentSpellIsExternalDefensive(kind)
    local cfg, specKey, auraName = CurrentSpellConfig(kind, false)
    local runtime = SpellIndicatorRuntime()
    return runtime and type(runtime.IsExternalDefensiveAura) == "function"
        and runtime.IsExternalDefensiveAura(specKey, auraName, cfg) == true
end
local function ExternalAutoBlacklistActive(kind)
    local conf = Conf(kind)
    local root = type(conf and conf.auras) == "table" and conf.auras or nil
    local externals = root and type(root.externals) == "table" and root.externals or {}
    return (root == nil or root.enabled ~= false)
        and externals.enabled ~= false
        and (tonumber(externals.max) or 2) > 0
        and externals.autoBlacklistBuffs ~= false
end
local function CurrentAuraColor(kind)
    local info = CurrentAuraInfo(kind)
    return (info and info.color) or WHITE_RGB
end
local function TrackableSpellID(runtime, specKey, info)
    if type(info) ~= "table" then return nil end
    local id = CustomBuffSpellID(info.spellID or info.spellId or info.id)
    if id then return id end
    local auraName = info.name
    for _, registry in ipairs({ runtime and runtime.SpellIDs, runtime and runtime.SecretSpellIDs }) do
        id = registry and registry[specKey] and CustomBuffSpellID(registry[specKey][auraName])
        if id then return id end
    end
    local altIDs = runtime and runtime.AltSpellIDs and runtime.AltSpellIDs[specKey]
    for altID, mappedAura in pairs(type(altIDs) == "table" and altIDs or {}) do
        if mappedAura == auraName then
            id = CustomBuffSpellID(altID)
            if id then
                return id
            end
        end
    end
    return CustomBuffSpellID(auraName)
end
local function CustomEntryContainsSpellID(auraName, entry, spellID)
    spellID = CustomBuffSpellID(spellID)
    if not spellID then return false end
    if CustomBuffSpellID(auraName) == spellID then return true end
    if type(entry) ~= "table" then return false end
    if CustomBuffSpellID(entry.spellID or entry.spellId or entry.id) == spellID then return true end
    local ids = CustomBuffSpellIDs(entry.spells)
    for i = 1, type(ids) == "table" and #ids or 0 do if ids[i] == spellID then return true end end
    return false
end
local function ExistingAuraForSpellIDs(runtime, specKey, spellIDs, specCfg)
    if type(spellIDs) ~= "table" then return nil end
    for auraName, entry in pairs(type(specCfg) == "table" and specCfg or {}) do
        if IsCustomBuffEntry(auraName, entry) then
            for i = 1, #spellIDs do if CustomEntryContainsSpellID(auraName, entry, spellIDs[i]) then return auraName end end
        end
    end
    local trackable = specKey and runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
    for i = 1, type(trackable) == "table" and #trackable or 0 do
        local info, id = trackable[i], TrackableSpellID(runtime, specKey, trackable[i])
        for j = 1, #spellIDs do
            if id == spellIDs[j] and (info.custom ~= true or (type(specCfg) == "table" and specCfg[info.name] ~= nil)) then return info.name end
        end
    end
end
local function CountCustomBuffs(specCfg)
    local count = 0
    for auraName, entry in pairs(type(specCfg) == "table" and specCfg or {}) do
        if IsCustomBuffEntry(auraName, entry) then count = count + 1 end
    end
    return count
end
local function SpellFeedback(text, kind)
    if M.ShowStatusFeedback then M.ShowStatusFeedback(text, kind, 3) end
end
local function RefreshSpellPage(refreshPage)
    RefreshGFPreview()
    if refreshPage then refreshPage() end
end
local function AddCustomBuffResolved(refreshPage, kind, specKey, spellIDs)
    local spellID = spellIDs and spellIDs[1]
    if not spellID then
        SpellFeedback("Enter a valid buff Spell ID, link, or name.", "error")
        return false
    end
    if not specKey then
        SpellFeedback("No spell-indicator spec selected.", "error")
        return false
    end
    local runtime, key, cfg = SpellIndicatorRuntime(), tostring(spellID), SpellIndicators(kind)
    cfg.specs = cfg.specs or {}
    cfg.specs[specKey] = cfg.specs[specKey] or {}
    local specCfg = cfg.specs[specKey]
    local existingAura = ExistingAuraForSpellIDs(runtime, specKey, spellIDs, specCfg)
    if existingAura and existingAura ~= key then
        SetCurrentSpellAura(kind, existingAura)
        SpellFeedback("Buff already exists; selected existing icon.", "info")
        RefreshSpellPage(refreshPage)
        return true
    end
    local exists, customCount = type(specCfg[key]) == "table", CountCustomBuffs(specCfg)
    if not exists and customCount >= CUSTOM_BUFF_LIMIT then
        SpellFeedback("Custom buff limit reached.", "error")
        return false
    end
    local display, icon = CustomBuffInfo(spellID)
    local spellIDListText = CustomBuffSpellIDListText(spellIDs)
    local function ApplyCustomBuff()
        local entry = exists and specCfg[key] or {}
        entry.enabled = true
        if entry._msufCustomOnlyOwnExplicit ~= true then entry.onlyOwn = false end
        entry.custom, entry.spellID, entry.spells = true, spellID, spellIDListText
        -- Without spell data the runtime names the tile from the spell later
        -- (SpellRegistry EnsureTrackable); a saved placeholder would win over it.
        entry.display, entry.icon = display or entry.display, icon or entry.icon
        if type(entry.placed) ~= "table" then entry.placed = DefaultCustomBuffPlaced(exists and max(1, customCount) or customCount + 1) end
        specCfg[key] = entry
        SetCurrentSpellAura(kind, key)
        QueueSpellIndicators(kind)
    end
    M.RunWithHistory("Add Custom Buff", "group:spellCustomAdd:" .. tostring(kind) .. ":" .. tostring(specKey) .. ":" .. key, ApplyCustomBuff)
    RefreshSpellPage(refreshPage)
    return true
end
-- Escape does not answer it: a menu-owned prompt (M.ShowPrompt). Only the
-- second button picks the entered ID; a replaced question adds nothing.
local function ShowCustomBuffAuraIDSuggestion(refreshPage, kind, specKey, spellIDs, suggestedID, spellName)
    M.ShowPrompt("MSUF2_GF_SPELL_CUSTOM_BUFF_AURA_ID", {
        text = M.Format("%s is active on you with Aura ID %d. Your entered ID is %d. Track both IDs?",
            tostring(spellName or Tr("This buff")), tonumber(suggestedID) or 0, tonumber(spellIDs and spellIDs[1]) or 0),
        accept = Tr("Use both IDs"), cancel = Tr("Entered ID only"), hideOnEscape = false,
        onAccept = function()
            local combined, seen = {}, {}
            for i = 1, #(spellIDs or {}) do AddCustomBuffSpellID(combined, seen, spellIDs[i]) end
            AddCustomBuffSpellID(combined, seen, suggestedID)
            AddCustomBuffResolved(refreshPage, kind, specKey, combined)
        end,
        onCancel = function() AddCustomBuffResolved(refreshPage, kind, specKey, spellIDs) end,
    })
    return true
end
local function AddCustomBuff(refreshPage, kind, specKey, rawValue)
    local spellIDs = ResolveCustomBuffSpellIDs(rawValue)
    if not spellIDs then return AddCustomBuffResolved(refreshPage, kind, specKey) end
    RequestCustomBuffSpellData(spellIDs)
    local suggestedID, spellName = SuggestedActivePlayerAuraID(spellIDs)
    if suggestedID and ShowCustomBuffAuraIDSuggestion(refreshPage, kind, specKey, spellIDs, suggestedID, spellName) then return true end
    return AddCustomBuffResolved(refreshPage, kind, specKey, spellIDs)
end
local function RemoveCustomBuff(refreshPage, kind, specKey, auraName)
    if not (kind and specKey and auraName and auraName ~= "") then return false end
    local cfg = SpellIndicators(kind)
    local specCfg = type(cfg.specs) == "table" and cfg.specs[specKey]
    local entry = type(specCfg) == "table" and specCfg[auraName]
    if not IsCustomBuffEntry(auraName, entry) then return false end
    local function ApplyRemove()
        specCfg[auraName] = nil
        local order = cfg.sortOrder and cfg.sortOrder[specKey]
        for i = type(order) == "table" and #order or 0, 1, -1 do if order[i] == auraName then table.remove(order, i) end end
        if CurrentSpellAura(kind) == auraName then ClearCurrentSpellAura(kind, specKey) end
        QueueSpellIndicators(kind)
    end
    M.RunWithHistory("Remove Custom Buff", "group:spellCustomRemove:" .. tostring(kind) .. ":" .. tostring(specKey) .. ":" .. tostring(auraName), ApplyRemove)
    RefreshSpellPage(refreshPage)
    return true
end
-- Blizzard's generic text-input dialog (M.ShowPrompt): it opens empty with
-- the focus in its edit box, Enter accepts, and Add waits for some text.
local function ShowCustomBuffPopup(refreshPage, kind, specKey)
    M.ShowPrompt("MSUF2_GF_SPELL_CUSTOM_BUFF_ID", {
        text = Tr("Enter buff Spell ID, link, or name"), accept = Tr("Add"), cancel = CANCEL or Tr("Cancel"),
        input = { maxLetters = 255 },
        onAccept = function(text) AddCustomBuff(refreshPage, kind, specKey, text or "") end,
    })
    return true
end

local function EnsureSpellSortOrder(siCfg, specKey, trackable)
    siCfg.sortOrder = siCfg.sortOrder or {}
    if type(siCfg.sortOrder[specKey]) ~= "table" then
        local order = {}
        for i = 1, #(trackable or {}) do order[#order + 1] = trackable[i].name end
        siCfg.sortOrder[specKey] = order
    end
    local order, seen = siCfg.sortOrder[specKey], {}
    for i = 1, #order do seen[order[i]] = true end
    for i = 1, #(trackable or {}) do
        local name = trackable[i] and trackable[i].name
        if name and not seen[name] then order[#order + 1], seen[name] = name, true end
    end
    return order
end
local function OrderedTrackable(runtime, siCfg, specKey)
    local source = runtime and runtime.TrackableAuras and runtime.TrackableAuras[specKey]
    if type(source) ~= "table" then return nil end
    local specCfg = type(siCfg.specs) == "table" and siCfg.specs[specKey]
    local trackable = {}
    for i = 1, #source do
        local info = source[i]
        if info and (info.custom ~= true or (type(specCfg) == "table" and specCfg[info.name] ~= nil)) then trackable[#trackable + 1] = info end
    end
    local order = siCfg.sortOrder and siCfg.sortOrder[specKey]
    if type(order) ~= "table" or #order == 0 then return trackable end
    local byName, result = {}, {}
    for i = 1, #trackable do byName[trackable[i].name] = trackable[i] end
    for i = 1, #order do
        local info = byName[order[i]]
        if info then result[#result + 1], byName[order[i]] = info, nil end
    end
    for i = 1, #trackable do if byName[trackable[i].name] then result[#result + 1] = trackable[i] end end
    return result
end
local function InsertSpellAt(siCfg, specKey, trackable, auraName, targetSlot)
    local order = EnsureSpellSortOrder(siCfg, specKey, trackable)
    local from
    for i = 1, #order do
        if order[i] == auraName then
            from = i
            break
        end
    end
    if not from then return end
    targetSlot = max(1, min(#order, tonumber(targetSlot) or from))
    if from == targetSlot then return end
    table.remove(order, from)
    table.insert(order, targetSlot, auraName)
end
local function SetSpellTileBorder(tile, selected, color, scale, alpha)
    tile:SetBackdropBorderColor(selected and 0.38 or color[1] * scale, selected and 0.66 or color[2] * scale,
        selected and 1 or color[3] * scale, selected and 1 or alpha)
end

local SetIconTexture -- the tile painter runs on every refresh, so MSUF_SetIconTexture is required once, on first use
local SpellTileGrid = {}
SpellTileGrid.__index = SpellTileGrid
local SpellTileDragOnUpdate
function SpellTileGrid.New(ctx, parent, x, y, width, refreshPage)
    local frame = PixelLayoutRegion(CreateFrame("Frame", nil, parent, "BackdropTemplate"))
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, 150)
    frame._tiles = {}
    local self = setmetatable({
        ctx = ctx, parent = parent, frame = frame, refreshPage = refreshPage,
        label = W.LabelAt(parent, "Spells for this spec", x, y + 48, width, "GameFontNormalSmall", T.colors.accent),
        hint = W.Text(parent, "Click: edit. Right-click: toggle. Drag: reorder or preview.", x, y + 27, width, T.colors.muted),
        tileSize = 52, gap = 8,
    }, SpellTileGrid)
    self.perRow = max(1, floor((width + self.gap) / (self.tileSize + self.gap)))
    return self
end
function SpellTileGrid:SlotPosition(slot)
    local stride = self.tileSize + self.gap
    return ((slot - 1) % self.perRow) * stride, -(floor((slot - 1) / self.perRow) * stride)
end
function SpellTileGrid:Position(tile, slot, specKey, trackable)
    local x, y = self:SlotPosition(slot)
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    tile._slot, tile._specKey, tile._trackable, tile._dragged = slot, specKey, trackable, false
end
function SpellTileGrid:OnEnter(tile)
    if tile._isAddTile then
        GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Tr("Add custom buff"), 1, 1, 1)
        GameTooltip:AddLine(Tr("Accepts a buff Spell ID, spell link, or spell name and tracks exact Aura IDs through native AuraSlot filters."), 0.75, 0.78,
            0.86)
        GameTooltip:AddLine(M.Format("%d / %d", tonumber(tile._customCount) or 0, CUSTOM_BUFF_LIMIT), 0.55, 0.70, 0.95)
        GameTooltip:Show()
        tile:SetBackdropColor(0.055, 0.075, 0.115, 1)
        tile:SetBackdropBorderColor(CUSTOM_BUFF_COLOR[1], CUSTOM_BUFF_COLOR[2], CUSTOM_BUFF_COLOR[3], 1)
        return
    end
    local info, color = tile._info or {}, tile._color or WHITE_RGB
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:AddLine(info.display or info.name, 1, 1, 1)
    if tile._customBuff then
        local cfg = SpellConfigFor(CurrentScope(), tile._specKey, tile._auraName, false)
        if cfg and cfg.spells and cfg.spells ~= "" then GameTooltip:AddLine(M.Format("IDs: %s", tostring(cfg.spells)), 0.55, 0.70, 0.95) end
    end
    if info.secret then GameTooltip:AddLine(Tr("Secret aura (name/fingerprint matched)"), 0.72, 0.62, 0.95) end
    GameTooltip:AddLine(Tr("Left-click to configure"), 0.75, 0.78, 0.86)
    GameTooltip:AddLine(Tr(tile._customBuff and "Right-click to remove" or "Right-click to toggle"), 0.55, 0.82, 0.55)
    GameTooltip:AddLine(Tr("Drag onto the Group Frame Preview to place and position it"), 0.42, 0.90, 1.00, true)
    GameTooltip:AddLine(Tr("Drop within this list to reorder"), 0.55, 0.70, 0.95)
    GameTooltip:Show()
    tile:SetBackdropColor(0.070, 0.085, 0.125, 1)
    tile:SetBackdropBorderColor(color[1], color[2], color[3], 1)
end
function SpellTileGrid:OnLeave(tile)
    GameTooltip:Hide()
    tile:SetBackdropColor(0.035, 0.040, 0.070, 0.96)
    SetSpellTileBorder(tile, not tile._isAddTile and tile._auraName == CurrentSpellAura(CurrentScope()),
        tile._color or WHITE_RGB, tile._isAddTile and 0.72 or 0.62, 0.82)
end
function SpellTileGrid:OnDragStart(tile)
    if tile._isAddTile then return end
    GameTooltip:Hide()
    tile._dragged = true
    tile:StartMoving()
    tile:SetFrameStrata("TOOLTIP")
    local preview = M.GroupPreview
    if preview and type(preview.UpdateSpellDropTarget) == "function" then
        preview.UpdateSpellDropTarget(true, tile._info and (tile._info.display or tile._info.name) or tile._auraName)
    end
    tile:SetScript("OnUpdate", SpellTileDragOnUpdate)
end
function SpellTileGrid:OnDragStop(tile)
    if tile._isAddTile then return end
    tile:SetScript("OnUpdate", nil)
    tile:StopMovingOrSizing()
    local strata = self.frame:GetFrameStrata()
    if issecretvalue(strata) ~= true and strata then tile:SetFrameStrata(strata) end
    local preview = M.GroupPreview
    local dropped = preview and type(preview.DropSpellIndicatorAtCursor) == "function"
        and preview.DropSpellIndicatorAtCursor(tile._specKey, tile._auraName) == true
    if preview and type(preview.UpdateSpellDropTarget) == "function" then preview.UpdateSpellDropTarget(false) end
    if dropped then
        if M.Refresh then M.Refresh(self.ctx) else self.refreshPage() end
        return
    end
    local hostLeft, hostTop, cx, cy = self.frame:GetLeft(), self.frame:GetTop(), tile:GetCenter()
    if not (hostLeft and hostTop and cx and cy) then return end
    local bestSlot, bestDist = tile._slot or 1, math.huge
    for slot = 1, #(tile._trackable or {}) do
        local x, y = self:SlotPosition(slot)
        local dx, dy = cx - (hostLeft + x + self.tileSize / 2), cy - (hostTop + y - self.tileSize / 2)
        local distance = dx * dx + dy * dy
        if distance < bestDist then bestSlot, bestDist = slot, distance end
    end
    local kind = CurrentScope()
    local function Reorder()
        InsertSpellAt(SpellIndicators(kind), tile._specKey, tile._trackable, tile._auraName, bestSlot)
        QueueSpellIndicators(kind)
    end
    M.RunWithHistory("Spell Indicator Order", "group:spellOrder:" .. tostring(kind) .. ":" .. tostring(tile._specKey), Reorder)
    if M.Refresh then M.Refresh(self.ctx) else self.refreshPage() end
end
function SpellTileGrid:OnMouseUp(tile, button)
    if SpellIndicators(CurrentScope()).enabled ~= true then return end
    if tile._suppressNextClick then
        tile._suppressNextClick = nil
        tile._dragged = false
        return
    end
    if tile._dragged then
        tile._dragged = false
        return
    end
    local kind = CurrentScope()
    if tile._isAddTile then
        if button == "LeftButton" then ShowCustomBuffPopup(self.refreshPage, kind, tile._specKey) end
        return
    end
    if button == "RightButton" then
        if tile._customBuff then
            RemoveCustomBuff(self.refreshPage, kind, tile._specKey, tile._auraName)
        else
            local function Toggle()
                local cfg = SpellConfigFor(kind, tile._specKey, tile._auraName, true)
                if cfg then cfg.enabled = cfg.enabled == false and true or false end
                QueueSpellIndicators(kind)
            end
            M.RunWithHistory("Toggle Spell Indicator",
                "group:spellToggle:" .. tostring(kind) .. ":" .. tostring(tile._specKey) .. ":" .. tostring(tile._auraName), Toggle)
        end
    else
        SetCurrentSpellAura(kind, tile._auraName)
        RefreshGFPreview()
    end
    if M.Refresh then M.Refresh(self.ctx) else self.refreshPage() end
end
local function SpellTileOnEnter(tile) tile._grid:OnEnter(tile) end
local function SpellTileOnLeave(tile) tile._grid:OnLeave(tile) end
local function SpellTileOnMouseUp(tile, button) tile._grid:OnMouseUp(tile, button) end
SpellTileDragOnUpdate = function(tile)
    local preview = M.GroupPreview
    if preview and type(preview.UpdateSpellDropTarget) == "function" then
        preview.UpdateSpellDropTarget(true, tile._info and (tile._info.display or tile._info.name) or tile._auraName)
    end
end
local function StopSpellTilePendingDrag(tile)
    tile._pendingDrag = nil
    tile._dragStartCursorX, tile._dragStartCursorY = nil, nil
    tile:SetScript("OnUpdate", nil)
end
-- hot path: kept whole (perf rule)
local function SpellTilePendingDragOnUpdate(tile)
    if not tile._pendingDrag then return StopSpellTilePendingDrag(tile) end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        StopSpellTilePendingDrag(tile)
        return
    end
    local x, y = GetCursorPosition()
    if not (x and y and tile._dragStartCursorX and tile._dragStartCursorY) then return end
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local dx, dy = (x - tile._dragStartCursorX) / scale, (y - tile._dragStartCursorY) / scale
    if (dx * dx + dy * dy) < 36 then return end
    StopSpellTilePendingDrag(tile)
    tile._grid:OnDragStart(tile)
end
local function SpellTileOnMouseDown(tile, button)
    if button ~= "LeftButton" or tile._isAddTile then return end
    tile._pendingDrag = true
    tile._dragStartCursorX, tile._dragStartCursorY = GetCursorPosition()
    tile:SetScript("OnUpdate", SpellTilePendingDragOnUpdate)
end
local function SpellTileInputMouseUp(tile, button)
    if button ~= "LeftButton" then return end
    StopSpellTilePendingDrag(tile)
    if tile._dragged then
        tile._suppressNextClick = true
        tile._grid:OnDragStop(tile)
    end
end
local function SpellTileOnHide(tile)
    StopSpellTilePendingDrag(tile)
    if tile._dragged then
        tile:StopMovingOrSizing()
        tile._dragged = false
        local preview = M.GroupPreview
        if preview and type(preview.UpdateSpellDropTarget) == "function" then preview.UpdateSpellDropTarget(false) end
    end
end
function SpellTileGrid:EnsureTile(index)
    local tile = self.frame._tiles[index]
    if tile then return tile end
    tile = PixelLayoutRegion(CreateFrame("Button", nil, self.frame, "BackdropTemplate"))
    tile:SetSize(self.tileSize, self.tileSize)
    tile:SetMovable(true)
    tile:EnableMouse(true)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    PixelLayoutRegion(tile, "SetBackdrop", { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    tile:SetBackdropColor(0.035, 0.040, 0.070, 0.96)
    tile.icon = PixelLayoutRegion(tile:CreateTexture(nil, "ARTWORK"))
    tile.icon:SetSize(36, 36)
    tile.icon:SetPoint("TOP", tile, "TOP", 0, -3)
    tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local addMark = PixelLayoutRegion(CreateFrame("Frame", nil, tile))
    addMark:SetSize(20, 20)
    addMark:SetPoint("CENTER", tile.icon, "CENTER")
    addMark.horizontal = PixelLayoutRegion(addMark:CreateTexture(nil, "OVERLAY"))
    addMark.horizontal:SetSize(16, 3)
    addMark.horizontal:SetPoint("CENTER")
    addMark.vertical = PixelLayoutRegion(addMark:CreateTexture(nil, "OVERLAY"))
    addMark.vertical:SetSize(3, 16)
    addMark.vertical:SetPoint("CENTER")
    function addMark:SetText() end
    function addMark:SetTextColor(r, g, b, a)
        self.horizontal:SetColorTexture(r, g, b, a)
        self.vertical:SetColorTexture(r, g, b, a)
    end
    tile.addText = addMark
    tile.addText:SetTextColor(0.70, 0.90, 1, 1)
    tile.addText:Hide()
    tile.label = PixelLayoutRegion(tile:CreateFontString(nil, "OVERLAY"))
    tile.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE")
    tile.label:SetPoint("BOTTOM", tile, "BOTTOM", 0, 2)
    tile.label:SetWidth(self.tileSize - 4)
    tile.label:SetMaxLines(1)
    tile.label:SetJustifyH("CENTER")
    tile._grid = self
    tile:SetScript("OnEnter", SpellTileOnEnter)
    tile:SetScript("OnLeave", SpellTileOnLeave)
    tile:SetScript("OnMouseDown", SpellTileOnMouseDown)
    tile:SetScript("OnMouseUp", SpellTileInputMouseUp)
    tile:SetScript("OnClick", SpellTileOnMouseUp)
    tile:SetScript("OnHide", SpellTileOnHide)
    tile._msuf2CommandAction = {
        kind = "button",
        valueKind = "text",
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(value)
            if tile._isAddTile then
                return AddCustomBuff(self.refreshPage, CurrentScope(), tile._specKey, value)
            end
            return tile._grid:OnMouseUp(tile, "LeftButton")
        end,
    }
    RegisterControl(tile, self.ctx, "spell.tile.slot." .. tostring(index), M.Format("Tracked spell tile %d", index), "button", "action")
    self.frame._tiles[index] = tile
    return tile
end
function SpellTileGrid:Refresh()
    local kind = CurrentScope()
    local indicatorsOn = SpellIndicators(kind).enabled == true
    local runtime, specKey = SpellIndicatorRuntime(), EffectiveSpellSpec(kind)
    if specKey then EnsureSpellDefaults(kind, specKey) end
    local siCfg = SpellIndicators(kind)
    local trackable = specKey and OrderedTrackable(runtime, siCfg, specKey) or {}
    local selected = CurrentSpellAura(kind)
    if self.frame.SetAlpha then self.frame:SetAlpha(indicatorsOn and 1 or 0.45) end
    if self.label and self.label.SetTextColor then
        local color = indicatorsOn and T.colors.accent or T.colors.dim
        self.label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    for i = 1, #self.frame._tiles do self.frame._tiles[i]:Hide() end
    trackable = type(trackable) == "table" and trackable or {}
    local specCfg = type(siCfg.specs) == "table" and specKey and siCfg.specs[specKey]
    local customCount = CountCustomBuffs(specCfg)
    self.hint:SetText(#trackable == 0 and "No spells for this spec." or "Click: edit. Right-click: toggle. Drag: reorder or preview.")
    if self.hint.SetTextColor then
        local color = indicatorsOn and T.colors.muted or T.colors.dim
        self.hint:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    for i = 1, #trackable do
        local info, tile = trackable[i], self:EnsureTile(i)
        self:Position(tile, i, specKey, trackable)
        tile._auraName, tile._info, tile._isAddTile = info.name, info, false
        RegisterControl(tile, self.ctx, "spell.tile.slot." .. tostring(i),
            M.Format("Tracked spell %s", tostring(info.display or info.name or i)), "button", "action")
        local auraCfg = SpellConfigFor(kind, specKey, info.name, false)
        tile._customBuff = IsCustomBuffEntry(info.name, auraCfg) or info.custom == true
        local tileEnabled = indicatorsOn and not (auraCfg and auraCfg.enabled == false)
        local color = info.color or { 0.55, 0.65, 0.85 }
        tile._color = color
        tile.addText:Hide()
        tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tile.icon:SetVertexColor(1, 1, 1, 1)
        if runtime and type(runtime.GetAuraIcon) == "function" then
            SetIconTexture = SetIconTexture or MSUF.Require("MSUF_SetIconTexture", "Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")
            SetIconTexture(tile.icon, runtime.GetAuraIcon(specKey, info.name), "")
        else
            tile.icon:SetTexture(136243)
        end
        tile:EnableMouse(indicatorsOn)
        tile.icon:SetDesaturated(not tileEnabled)
        tile.icon:SetAlpha(tileEnabled and 1 or 0.35)
        tile.label:SetText(info.display or info.name)
        local textAlpha = tileEnabled and 0.92 or 0.45
        tile.label:SetTextColor(textAlpha, textAlpha, textAlpha, 1)
        SetSpellTileBorder(tile, indicatorsOn and info.name == selected, color, 0.42, indicatorsOn and 0.82 or 0.45)
        tile:Show()
    end
    if specKey and customCount < CUSTOM_BUFF_LIMIT then
        local slot, tile = #trackable + 1, self:EnsureTile(#trackable + 1)
        self:Position(tile, slot, specKey, trackable)
        tile._auraName, tile._info, tile._isAddTile, tile._customBuff = nil, nil, true, false
        RegisterControl(tile, self.ctx, "spell.tile.slot." .. tostring(slot),
            "Add custom group spell indicator", "button", "action")
        tile._customCount, tile._color = customCount, CUSTOM_BUFF_COLOR
        tile.icon:SetTexture("Interface\\Buttons\\WHITE8x8")
        tile.icon:SetTexCoord(0, 1, 0, 1)
        tile.icon:SetVertexColor(0.055, 0.150, 0.220, indicatorsOn and 0.95 or 0.40)
        tile.icon:SetDesaturated(false)
        tile.icon:SetAlpha(indicatorsOn and 0.95 or 0.35)
        tile.addText:SetText("+")
        tile.addText:SetTextColor(0.70, 0.90, 1, indicatorsOn and 1 or 0.45)
        tile.addText:Show()
        tile.label:SetText(M.Format("%d/%d", customCount, CUSTOM_BUFF_LIMIT))
        tile.label:SetTextColor(indicatorsOn and 0.70 or 0.45, indicatorsOn and 0.90 or 0.45, indicatorsOn and 1 or 0.45, 1)
        tile:EnableMouse(indicatorsOn)
        SetSpellTileBorder(tile, false, CUSTOM_BUFF_COLOR, 0.72, indicatorsOn and 0.82 or 0.45)
        tile:Show()
    end
    local tileCount = #trackable + ((specKey and customCount < CUSTOM_BUFF_LIMIT) and 1 or 0)
    local rows = max(1, floor((max(1, tileCount) + self.perRow - 1) / self.perRow))
    self.frame:SetHeight((rows * (self.tileSize + self.gap)) - self.gap)
    return rows
end

-- IconScale owns its coalesced drag/release lifecycle; the typed row owns UI input.

-- Explicit load-time exports for the following responsibility modules.
Parts.CurrentAuraColor = CurrentAuraColor
Parts.CurrentSpellIsExternalDefensive = CurrentSpellIsExternalDefensive
Parts.EnsureSpellDefaults = EnsureSpellDefaults
Parts.ExternalAutoBlacklistActive = ExternalAutoBlacklistActive
Parts.SpellTileGrid = SpellTileGrid

--- Blizzard Edit Mode adapter for MSUF Edit Mode: Minimap, Chat, Micro Menu
--- and the Tooltip move through the game's OWN layout data
--- (C_EditMode.GetLayouts → edit the active saved layout → SaveLayouts). The
--- client answers a save with EDIT_MODE_LAYOUTS_UPDATED carrying fresh C-side
--- data, and Blizzard's manager re-anchors every system from that clean copy —
--- MSUF never leaves tainted values in the applied anchors. Offsets are
--- stored in UIParent pixels (Blizzard divides by the system frame's scale on
--- SetPoint), so mover deltas apply 1:1.
---
--- Blizzard PRESET layouts are read-only. Selecting an element while a preset
--- is active creates a saved "MSUF" layout as an exact copy of that preset
--- (no visual jump) and activates it — the same step Blizzard's own UI forces
--- before any edit. An existing "MSUF" layout is reactivated, never duplicated.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local API = _G.MSUF_EditModeAPI
if not (API and API.RegisterElement) then return end

local systemEnum = _G.Enum and _G.Enum.EditModeSystem
if type(systemEnum) ~= "table" then return end

local OWNER, SETTING = "MSUF.Blizzard", "blizzardEditModeIntegration"
local LAYOUT_NAME = "MSUF"
local registered = {}
local active, tooltipContainerShown, sessionActive = false, false, false

local function Export(name, value)
    if type(MSUF.ExportPublic) == "function" then return MSUF.ExportPublic(name, value) end
    _G[name] = value
    return value
end

local function General()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local function Enabled()
    local general = General()
    return not general or general[SETTING] ~= false
end

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

local function Blizzard()
    local api = _G.C_EditMode
    if type(api) ~= "table" or type(api.GetLayouts) ~= "function"
        or type(api.SaveLayouts) ~= "function" then return nil end
    return api
end

--- The layout list from C_EditMode excludes the Blizzard presets, while
--- activeLayout indexes presets + saved layouts combined; Blizzard's own
--- manager uses Enum.EditModePresetLayoutsMeta.NumValues for that offset.
local function PresetCount()
    local meta = _G.Enum and _G.Enum.EditModePresetLayoutsMeta
    if type(meta) == "table" and tonumber(meta.NumValues) then return tonumber(meta.NumValues) end
    return 2
end

--- C_EditMode.GetLayouts right after a SaveLayouts serves ONE-BEHIND data
--- (field-verified: alternating anchor ping-pong on repeated setting
--- clicks). All mid-session reads and writes therefore run on ONE cached
--- info table: fetched once at a save-free moment, mutated in place, saved
--- from — never re-fetched between saves.
local cachedLayoutInfo

local function InvalidateLayoutCache()
    cachedLayoutInfo = nil
end

local function LayoutInfo()
    if cachedLayoutInfo then return cachedLayoutInfo end
    local api = Blizzard()
    if not api then return nil end
    local info = api.GetLayouts()
    if type(info) ~= "table" or type(info.layouts) ~= "table" then return nil end
    cachedLayoutInfo = info
    return info
end

local function ActiveLayout()
    local info = LayoutInfo()
    if not info then return nil end
    local index = (tonumber(info.activeLayout) or 0) - PresetCount()
    local layout = index >= 1 and info.layouts[index] or nil
    if type(layout) ~= "table" or type(layout.systems) ~= "table" then return nil end
    return info, layout
end

local function SystemEntry(systemId)
    local info, layout = ActiveLayout()
    if not layout then return nil end
    for i = 1, #layout.systems do
        local entry = layout.systems[i]
        if type(entry) == "table" and entry.system == systemId
            and type(entry.anchorInfo) == "table" then
            return entry, info
        end
    end
end

local function CopyTable(value, depth)
    if type(value) ~= "table" or depth > 8 then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = CopyTable(child, depth + 1) end
    return result
end

--- Systems for the new layout: Blizzard's preset manager first, and as a
--- fallback the Edit Mode manager's own combined layout list (presets are
--- prepended there). Always deep-copied so the saved layout never aliases
--- live manager tables.
local function PresetSystems(info)
    local index = tonumber(info.activeLayout) or 1
    local manager = _G.EditModePresetLayoutManager
    local copies = type(manager) == "table" and type(manager.GetCopyOfPresetLayouts) == "function"
        and manager:GetCopyOfPresetLayouts() or nil
    local preset = type(copies) == "table" and copies[index] or nil
    if type(preset) == "table" and type(preset.systems) == "table" then
        return CopyTable(preset.systems, 0)
    end
    local em = _G.EditModeManagerFrame
    local combined = type(em) == "table" and type(em.layoutInfo) == "table"
        and type(em.layoutInfo.layouts) == "table" and em.layoutInfo.layouts or nil
    local activePreset = combined and combined[index] or nil
    if type(activePreset) == "table" and type(activePreset.systems) == "table" then
        return CopyTable(activePreset.systems, 0)
    end
    return nil
end

--- Preset escape hatch: reactivate an existing layout with the wanted name,
--- or create one as a copy of the ACTIVE preset and activate it through
--- C_EditMode. Falls back from the Account pool to the Character pool when
--- the 5-per-type cap is reached (Mapko field-hit "layout_cap" with five
--- account layouts). The reason string surfaces in chat on failure and
--- through the exported probe — a silent no-op here is undebuggable.
local function EnsureEditableLayout(name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 24) or ""
    if name == "" then name = LAYOUT_NAME end
    local api = Blizzard()
    if not api then return false, "no_api" end
    if InCombat() then return false, "combat" end
    --- Preset situations have no in-flight MSUF saves, so a fresh fetch is
    --- trustworthy here — and required, the cache may predate a layout
    --- switch the user made in Blizzard's own Edit Mode.
    InvalidateLayoutCache()
    if ActiveLayout() then return true, "already_editable" end
    local info = api.GetLayouts()
    if type(info) ~= "table" or type(info.layouts) ~= "table" then return false, "no_layout_list" end
    if type(api.SetActiveLayout) ~= "function" then return false, "no_setactivelayout" end
    local presets = PresetCount()
    for i = 1, #info.layouts do
        local layout = info.layouts[i]
        if type(layout) == "table" and layout.layoutName == name then
            api.SetActiveLayout(presets + i)
            info.activeLayout = presets + i
            cachedLayoutInfo = info
            if API.RefreshOwner then API.RefreshOwner(OWNER) end
            return true, "activated_existing"
        end
    end
    local systems = PresetSystems(info)
    if not systems then return false, "no_preset_source" end
    local enumTypes = _G.Enum.EditModeLayoutType or {}
    local counts = {}
    for i = 1, #info.layouts do
        local layout = info.layouts[i]
        if type(layout) == "table" and layout.layoutType ~= nil then
            counts[layout.layoutType] = (counts[layout.layoutType] or 0) + 1
        end
    end
    local maxPerType = 5
    local layoutType = enumTypes.Account or 1
    if (counts[layoutType] or 0) >= maxPerType then
        layoutType = enumTypes.Character or 2
        if (counts[layoutType] or 0) >= maxPerType then return false, "layout_cap" end
    end
    info.layouts[#info.layouts + 1] = {
        layoutName = name, layoutType = layoutType, systems = systems,
    }
    api.SaveLayouts(info)
    api.SetActiveLayout(presets + #info.layouts)
    --- The just-saved table IS the truth; a re-fetch here would serve the
    --- pre-creation state and hide the new layout from every reader.
    info.activeLayout = presets + #info.layouts
    cachedLayoutInfo = info
    if API.RefreshOwner then API.RefreshOwner(OWNER) end
    return true, "created"
end

local function ReportLayoutFailure(reason)
    if type(_G.print) == "function" then
        _G.print("MSUF Edit Mode: Blizzard layout is not editable (" .. tostring(reason) .. ")")
    end
end

--- Small MSUF-styled dialog asking for the new layout's name when a preset
--- is active. Falls back to direct creation when the popup UI is not around.
local layoutDialog

--- The failure reason must be readable INSIDE the dialog — a chat-only
--- print makes the block look like an MSUF defect instead of Blizzard's
--- 5-per-pool layout cap.
local function ShowDialogStatus(reason)
    if not (layoutDialog and layoutDialog._statusFS) then return end
    local translate = layoutDialog._tr
    local function Localize(text) return translate and translate(text) or text end
    local text
    if reason == "layout_cap" then
        text = Localize("All Edit Mode layout slots are full (5 account + 5 character). Delete a layout in Blizzard's Edit Mode, then try again.")
    elseif reason == "combat" then
        text = Localize("In combat")
    else
        text = Localize("Layout creation failed:") .. " " .. tostring(reason)
    end
    layoutDialog._statusFS:SetText(text)
    layoutDialog._statusFS:Show()
end

local function CreateFromDialog()
    if not layoutDialog then return end
    local name = layoutDialog._nameBox and layoutDialog._nameBox.GetText
        and layoutDialog._nameBox:GetText() or nil
    local ok, reason = EnsureEditableLayout(name)
    if ok then
        layoutDialog:Hide()
    else
        ReportLayoutFailure(reason)
        ShowDialogStatus(reason)
    end
end

local function OpenLayoutDialog()
    local EM2 = _G.MSUF_EM2
    local Quick = EM2 and EM2.QuickPopup
    if not (Quick and Quick.CreateShell and Quick.FS and Quick.Box and Quick.ButtonAt) then
        local ok, reason = EnsureEditableLayout()
        if not ok then ReportLayoutFailure(reason) end
        return
    end
    if not layoutDialog then
        --- Offset above and stacked over the external popup shell (both
        --- default to CENTER +250 / level 900), or the popup that opens on
        --- the same click covers the dialog completely.
        layoutDialog = Quick.CreateShell("MSUF_EM2_BlizzardLayoutDialog", {
            width = 380, height = 212, title = "Create Edit Mode layout",
            y = 190, frameLevel = 960,
            hoverSource = "blizzard-layout-dialog",
        })
        layoutDialog._tr = Quick.Tr
        local body = Quick.FS(layoutDialog, "body")
        body:SetPoint("TOPLEFT", layoutDialog, "TOPLEFT", 20, -52)
        body:SetPoint("TOPRIGHT", layoutDialog, "TOPRIGHT", -20, -52)
        body:SetJustifyH("LEFT")
        if body.SetWordWrap then body:SetWordWrap(true) end
        body:SetText(Quick.Tr and Quick.Tr("Blizzard presets cannot be edited. Save a copy as a new layout to move and adjust Blizzard frames.")
            or "Blizzard presets cannot be edited. Save a copy as a new layout to move and adjust Blizzard frames.")
        layoutDialog._nameBox = Quick.Box(layoutDialog, 212, { boxHeight = 32 })
        layoutDialog._nameBox:SetPoint("TOPLEFT", layoutDialog, "TOPLEFT", 20, -116)
        layoutDialog._nameBox:SetMaxLetters(24)
        layoutDialog._nameBox:SetScript("OnEnterPressed", CreateFromDialog)
        layoutDialog._createBtn = Quick.ButtonAt(layoutDialog, "Create", 244, -116, 116, 32,
            CreateFromDialog, { variant = "primary", hoverWash = true })
        layoutDialog._statusFS = Quick.FS(layoutDialog, "caption")
        layoutDialog._statusFS:SetPoint("TOPLEFT", layoutDialog, "TOPLEFT", 20, -156)
        layoutDialog._statusFS:SetPoint("TOPRIGHT", layoutDialog, "TOPRIGHT", -20, -156)
        layoutDialog._statusFS:SetJustifyH("LEFT")
        if layoutDialog._statusFS.SetWordWrap then layoutDialog._statusFS:SetWordWrap(true) end
        layoutDialog._statusFS:SetTextColor(1, 0.4, 0.35, 1)
    end
    layoutDialog._nameBox:SetText(LAYOUT_NAME)
    layoutDialog._statusFS:SetText("")
    layoutDialog:Show()
end

local function SelectSystem()
    if not ActiveLayout() and Blizzard() and not InCombat() then
        OpenLayoutDialog()
    end
    return true
end

local FRAME_NAMES = {
    [systemEnum.Minimap or -1] = "MinimapCluster",
    [systemEnum.ChatFrame or -2] = "ChatFrame1",
    [systemEnum.MicroMenu or -3] = "MicroMenuContainer",
    [systemEnum.HudTooltip or -4] = "GameTooltipDefaultContainer",
    [systemEnum.Bags or -5] = "BagsBar",
    [systemEnum.DamageMeter or -7] = "DamageMeter",
}
--- ObjectiveTrackerFrame is intentionally absent. Its dirty layout reaches
--- combat-secret aura APIs, so it must remain entirely Blizzard-owned.

local function SystemFrame(systemId)
    local manager = _G.EditModeManagerFrame
    local frames = type(manager) == "table" and manager.registeredSystemFrames or nil
    if type(frames) == "table" then
        for i = 1, #frames do
            local frame = frames[i]
            if type(frame) == "table" and frame.system == systemId then return frame end
        end
    end
    local name = FRAME_NAMES[systemId]
    local fallback = name and _G[name]
    return type(fallback) == "table" and fallback or nil
end

--- Layouts saved before a system shipped carry NO row for it (the 12.x
--- Damage Meter most visibly) — Blizzard's own manager reconciles those
--- lazily (EditModeManager AddNewSystemsAndSettings), so a layout that
--- never went through Blizzard's Edit Mode since the patch stays bare and
--- every capture/move/setting dies on the missing entry. Seed the row from
--- the frame's live anchor, CENTER-based; the next commit saves it.
local function EnsureSystemEntry(systemId)
    local entry, info = SystemEntry(systemId)
    if entry then return entry, info end
    local layout
    info, layout = ActiveLayout()
    if not layout then return nil end
    local frame = SystemFrame(systemId)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    local uiScale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or 1
    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or uiScale
    local ratio = uiScale ~= 0 and frameScale / uiScale or 1
    local screenW = _G.UIParent and _G.UIParent.GetWidth and _G.UIParent:GetWidth() or 0
    local screenH = _G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight() or 0
    entry = {
        system = systemId,
        anchorInfo = {
            point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
            offsetX = (left + right) * 0.5 * ratio - screenW * 0.5,
            offsetY = (bottom + top) * 0.5 * ratio - screenH * 0.5,
        },
        settings = {},
    }
    layout.systems[#layout.systems + 1] = entry
    return entry, info
end

--- Layout settings live as { setting = enum, value = raw } rows next to the
--- anchor. All reads/writes stay inside one fetched info table and one save.
local function ApplySettingsTo(entry, changes)
    if type(entry.settings) ~= "table" then entry.settings = {} end
    for settingId, raw in pairs(changes) do
        local found
        for i = 1, #entry.settings do
            local row = entry.settings[i]
            if type(row) == "table" and row.setting == settingId then
                found = row
                break
            end
        end
        if found then found.value = raw
        else entry.settings[#entry.settings + 1] = { setting = settingId, value = raw } end
    end
end

local function ReadSetting(systemId, settingId)
    local entry = SystemEntry(systemId)
    local list = entry and entry.settings
    if type(list) ~= "table" then return nil end
    for i = 1, #list do
        local row = list[i]
        if type(row) == "table" and row.setting == settingId then return tonumber(row.value) end
    end
end

--- Reads the raw settings straight from the in-hand layout entry — NEVER
--- from a fresh GetLayouts after a save: the client may still answer with
--- the pre-save data there, which silently re-applies the OLD values
--- (field-hit: minimap/micro size "did nothing").
local function EntrySettings(entry)
    local map = {}
    local list = type(entry) == "table" and type(entry.settings) == "table" and entry.settings or nil
    for i = 1, #(list or {}) do
        local row = list[i]
        if type(row) == "table" and row.setting ~= nil then
            map[row.setting] = tonumber(row.value)
        end
    end
    return map
end

local function ApplyAnchorVisual(systemId, point, relativeTo, relativePoint, x, y)
    local frame = SystemFrame(systemId)
    if not (frame and frame.ClearAllPoints and frame.SetPoint) then return false end
    local scale = frame.GetScale and frame:GetScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    local relative = type(relativeTo) == "string" and _G[relativeTo] or _G.UIParent
    frame:ClearAllPoints()
    frame:SetPoint(point, relative or _G.UIParent, relativePoint or point, x / scale, y / scale)
    return true
end

--- SaveLayouts persists the layout but applies nothing on its own, and
--- SetActiveLayout on the unchanged index is a no-op (both field-verified).
--- Settings therefore apply visually right here, through the same plain
--- frame methods Blizzard's own system mixins run — Minimap, Chat, Micro
--- Menu and the tooltip container are non-protected HUD frames, so this
--- stays taint-safe. The saved layout remains the clean source of truth for
--- the next login or layout switch.
local function ApplyVisual(systemId, entry)
    local frame = SystemFrame(systemId)
    if not frame then return end
    local map = EntrySettings(entry)
    if systemId == systemEnum.Minimap then
        local setting = _G.Enum.EditModeMinimapSetting or {}
        local rotate = map[setting.RotateMinimap or 1]
        if rotate ~= nil and type(frame.SetRotateMinimap) == "function" then
            frame:SetRotateMinimap(rotate == 1)
        end
        local size = map[setting.Size or 2]
        if size ~= nil and type(frame.SetEditModeScale) == "function" then
            frame:SetEditModeScale((size * 10 + 50) / 100)
        end
        if type(frame.SetHeaderUnderneath) == "function" then
            frame:SetHeaderUnderneath(map[setting.HeaderUnderneath or 0] == 1)
        end
        if type(frame.Layout) == "function" then frame:Layout() end
    elseif systemId == systemEnum.ChatFrame then
        local setting = _G.Enum.EditModeChatFrameSetting or {}
        local widthHundreds = map[setting.WidthHundreds or 0]
        local widthTens = map[setting.WidthTensAndOnes or 1]
        local heightHundreds = map[setting.HeightHundreds or 2]
        local heightTens = map[setting.HeightTensAndOnes or 3]
        local width = (widthHundreds or widthTens)
            and ((widthHundreds or 0) * 100 + (widthTens or 0)) or nil
        local height = (heightHundreds or heightTens)
            and ((heightHundreds or 0) * 100 + (heightTens or 0)) or nil
        if (width or height) and type(frame.SetSize) == "function" then
            frame:SetSize(width or (frame.GetWidth and frame:GetWidth()) or 430,
                height or (frame.GetHeight and frame:GetHeight()) or 180)
        end
    elseif systemId == systemEnum.MicroMenu then
        local setting = _G.Enum.EditModeMicroMenuSetting or {}
        local micro = _G.MicroMenu
        if type(micro) == "table" then
            local size = map[setting.Size or 2]
            if size ~= nil and type(micro.SetNormalScale) == "function" then
                micro:SetNormalScale((size * 5 + 70) / 100)
            end
            local eye = map[setting.EyeSize or 3]
            if eye ~= nil and type(micro.SetQueueStatusScale) == "function" then
                micro:SetQueueStatusScale((eye * 5 + 50) / 100)
            end
            local orientationEnum = _G.Enum.MicroMenuOrientation or {}
            local orientation = map[setting.Orientation or 0]
            if orientation ~= nil then
                micro.isHorizontal = orientation == (orientationEnum.Horizontal or 0)
            end
            local orderEnum = _G.Enum.MicroMenuOrder or {}
            local order = map[setting.Order or 1]
            if order ~= nil then
                micro.layoutFramesGoingRight = order == (orderEnum.Default or 0)
                micro.layoutFramesGoingUp = order ~= (orderEnum.Default or 0)
            end
        end
        if type(frame.Layout) == "function" then frame:Layout() end
    elseif systemId == systemEnum.Bags then
        local setting = _G.Enum.EditModeBagsSetting or {}
        local size = map[setting.Size or 2]
        if size ~= nil and type(frame.SetScale) == "function" then
            frame:SetScale((size * 5 + 75) / 100)
        end
        local orientationEnum = _G.Enum.BagsOrientation or {}
        local orientation = map[setting.Orientation or 0]
        if orientation ~= nil then
            frame.isHorizontal = orientation == (orientationEnum.Horizontal or 0)
        end
        local direction = map[setting.Direction or 1]
        if direction ~= nil then frame.direction = direction end
        local padding = map[setting.BagSlotPadding or 3]
        if padding ~= nil then frame.bagPadding = padding end
        if type(frame.Layout) == "function" then frame:Layout() end
    elseif systemId == systemEnum.DamageMeter then
        --- Every damage meter setting applies through a plain method on the
        --- (non-secure) DamageMeter frame — the same calls Blizzard's own
        --- system mixin runs (EditModeSystemTemplates, system 23).
        local setting = _G.Enum.EditModeDamageMeterSetting or {}
        local width = map[setting.FrameWidth or 3]
        local height = map[setting.FrameHeight or 4]
        if (width ~= nil or height ~= nil) and type(frame.SetSize) == "function" then
            frame:SetSize(
                width and (width + 200) or (frame.GetWidth and frame:GetWidth()) or 300,
                height and (height + 120) or (frame.GetHeight and frame:GetHeight()) or 200)
        end
        local barHeight = map[setting.BarHeight or 10]
        if barHeight ~= nil and type(frame.SetBarHeight) == "function" then
            frame:SetBarHeight(barHeight + 15)
        end
        local padding = map[setting.Padding or 5]
        if padding ~= nil and type(frame.SetBarSpacing) == "function" then
            frame:SetBarSpacing(padding + 2)
        end
        local transparency = map[setting.Transparency or 6]
        if transparency ~= nil and type(frame.SetWindowTransparency) == "function" then
            frame:SetWindowTransparency(transparency + 50)
        end
        local backgroundTransparency = map[setting.BackgroundTransparency or 12]
        if backgroundTransparency ~= nil and type(frame.SetBackgroundTransparency) == "function" then
            frame:SetBackgroundTransparency(backgroundTransparency)
        end
        local textSize = map[setting.TextSize or 11]
        if textSize ~= nil and type(frame.SetTextSize) == "function" then
            frame:SetTextSize(textSize * 10 + 50)
        end
        local specIcon = map[setting.ShowSpecIcon or 8]
        if specIcon ~= nil and type(frame.SetShowBarIcons) == "function" then
            frame:SetShowBarIcons(specIcon == 1)
        end
        local classColor = map[setting.ShowClassColor or 9]
        if classColor ~= nil and type(frame.SetUseClassColor) == "function" then
            frame:SetUseClassColor(classColor == 1)
        end
    end
end

local SNAPSHOT_KEYS = {
    [systemEnum.Minimap or -1] = "minimap",
    [systemEnum.ChatFrame or -2] = "chat",
    [systemEnum.MicroMenu or -3] = "micromenu",
    [systemEnum.HudTooltip or -4] = "tooltip",
    [systemEnum.Bags or -5] = "bags",
    [systemEnum.DamageMeter or -7] = "damagemeter",
}

--- Every committed anchor + raw settings row also lands in the MSUF profile
--- (general.blizzardEditModeSnapshot), so a profile export carries the
--- Blizzard Edit Mode arrangement and a profile apply can restore it.
local function StoreSnapshot(systemId, entry)
    local key = SNAPSHOT_KEYS[systemId]
    local general = General()
    if not key or not general then return end
    entry = entry or SystemEntry(systemId)
    if not entry then return end
    local anchor = entry.anchorInfo
    local snapshot = type(general.blizzardEditModeSnapshot) == "table"
        and general.blizzardEditModeSnapshot or {}
    general.blizzardEditModeSnapshot = snapshot
    local settings
    local list = type(entry.settings) == "table" and entry.settings or nil
    for i = 1, #(list or {}) do
        local row = list[i]
        if type(row) == "table" and row.setting ~= nil and tonumber(row.value) then
            settings = settings or {}
            settings[row.setting] = tonumber(row.value)
        end
    end
    snapshot[key] = {
        point = type(anchor.point) == "string" and anchor.point or "CENTER",
        relativeTo = type(anchor.relativeTo) == "string" and anchor.relativeTo or "UIParent",
        relativePoint = type(anchor.relativePoint) == "string" and anchor.relativePoint or nil,
        x = tonumber(anchor.offsetX) or 0, y = tonumber(anchor.offsetY) or 0,
        settings = settings,
    }
end

local function MutateSettings(systemId, changes)
    if InCombat() then return false end
    local entry, info = EnsureSystemEntry(systemId)
    if not entry then return false end
    local api = Blizzard()
    if not api then return false end
    ApplySettingsTo(entry, changes)
    api.SaveLayouts(info)
    ApplyVisual(systemId, entry)
    --- Blizzard-side relayouts (the tracker's UpdateHeight most visibly)
    --- re-anchor the frame from the manager's own cached anchor, which never
    --- learns about MSUF's data-only saves — re-assert the saved anchor after
    --- every settings apply or the frame snaps back to its pre-move position.
    local anchor = entry.anchorInfo
    if type(anchor) == "table" and type(anchor.point) == "string" then
        ApplyAnchorVisual(systemId, anchor.point, anchor.relativeTo, anchor.relativePoint,
            tonumber(anchor.offsetX) or 0, tonumber(anchor.offsetY) or 0)
    end
    StoreSnapshot(systemId, entry)
    return true
end

--- Refreshes the profile snapshot for every system from the current layout.
--- Runs on session exit (the arrangement the user just finished) and once at
--- load when the snapshot does not exist yet, so profile copies/exports carry
--- the Blizzard arrangement even without a fresh commit.
local function SnapshotAll()
    if not Enabled() then return end
    for systemId in pairs(SNAPSHOT_KEYS) do
        StoreSnapshot(systemId)
    end
end

local function CaptureSettings(entry, settingIds)
    if not settingIds then return nil end
    local list = type(entry.settings) == "table" and entry.settings or nil
    local captured = {}
    for i = 1, #settingIds do
        local settingId = settingIds[i]
        for j = 1, #(list or {}) do
            local row = list[j]
            if type(row) == "table" and row.setting == settingId and tonumber(row.value) then
                captured[settingId] = tonumber(row.value)
                break
            end
        end
    end
    return next(captured) and captured or nil
end

local function Capture(systemId, settingIds)
    local entry = EnsureSystemEntry(systemId)
    if not entry then return nil end
    local anchor = entry.anchorInfo
    local frame = SystemFrame(systemId)
    return {
        point = type(anchor.point) == "string" and anchor.point or "CENTER",
        relativeTo = type(anchor.relativeTo) == "string" and anchor.relativeTo or "UIParent",
        relativePoint = type(anchor.relativePoint) == "string" and anchor.relativePoint or nil,
        x = tonumber(anchor.offsetX) or 0, y = tonumber(anchor.offsetY) or 0,
        settings = CaptureSettings(entry, settingIds),
        width = frame and frame.GetWidth and frame:GetWidth() or nil,
        height = frame and frame.GetHeight and frame:GetHeight() or nil,
    }
end

--- Commit path: mutate the entry inside the freshly fetched layout table,
--- save once, apply the visuals directly and refresh the profile snapshot.
local function Restore(systemId, state)
    if InCombat() or type(state) ~= "table" then return false end
    local x, y = tonumber(state.x), tonumber(state.y)
    if type(state.point) ~= "string" or not x or not y then return false end
    local entry, info = EnsureSystemEntry(systemId)
    if not entry then return false end
    local api = Blizzard()
    if not api then return false end
    local anchor = entry.anchorInfo
    anchor.point = state.point
    if type(state.relativeTo) == "string" then anchor.relativeTo = state.relativeTo end
    if type(state.relativePoint) == "string" then anchor.relativePoint = state.relativePoint end
    anchor.offsetX, anchor.offsetY = x, y
    if type(state.settings) == "table" then ApplySettingsTo(entry, state.settings) end
    api.SaveLayouts(info)
    ApplyAnchorVisual(systemId, anchor.point, anchor.relativeTo, anchor.relativePoint, x, y)
    if type(state.settings) == "table" then ApplyVisual(systemId, entry) end
    StoreSnapshot(systemId, entry)
    return true
end

--- Preview drags anchor the frame directly (out of combat, visual only);
--- the commit saves the clean anchor into the layout data.
local function Move(systemId, request)
    local state = request and request.state
    if type(state) ~= "table" or InCombat() then return false end
    local x = (tonumber(state.x) or 0) + (tonumber(request.deltaX) or 0)
    local y = (tonumber(state.y) or 0) + (tonumber(request.deltaY) or 0)
    if request.phase == "commit" then
        return Restore(systemId, {
            point = state.point, relativeTo = state.relativeTo,
            relativePoint = state.relativePoint, x = x, y = y,
        })
    end
    return ApplyAnchorVisual(systemId, state.point, state.relativeTo,
        state.relativePoint or state.point, x, y)
end

local snapshotRetry

--- Profile apply/import: push the stored snapshot back into the active
--- saved layout in ONE SaveLayouts, then apply the visuals directly.
--- Presets stay untouched — the user creates an editable layout through the
--- Edit Mode dialog first. In combat this arms a one-shot
--- PLAYER_REGEN_ENABLED retry (no recurring cost).
local function ApplyProfileSnapshot()
    if not Enabled() then return false end
    local general = General()
    local snapshot = general and general.blizzardEditModeSnapshot
    if type(snapshot) ~= "table" or not next(snapshot) then return false end
    if InCombat() then
        if not snapshotRetry and type(_G.CreateFrame) == "function" then
            snapshotRetry = _G.CreateFrame("Frame")
            snapshotRetry:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ApplyProfileSnapshot()
            end)
        end
        if snapshotRetry then snapshotRetry:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    local api = Blizzard()
    InvalidateLayoutCache()
    local info, layout = ActiveLayout()
    if not (api and layout) then return false end
    local applied = {}
    for systemId, key in pairs(SNAPSHOT_KEYS) do
        local state = snapshot[key]
        if type(state) == "table" and type(state.point) == "string" then
            for i = 1, #layout.systems do
                local entry = layout.systems[i]
                if type(entry) == "table" and entry.system == systemId
                    and type(entry.anchorInfo) == "table" then
                    local anchor = entry.anchorInfo
                    anchor.point = state.point
                    if type(state.relativeTo) == "string" then anchor.relativeTo = state.relativeTo end
                    if type(state.relativePoint) == "string" then anchor.relativePoint = state.relativePoint end
                    anchor.offsetX = tonumber(state.x) or 0
                    anchor.offsetY = tonumber(state.y) or 0
                    if type(state.settings) == "table" then ApplySettingsTo(entry, state.settings) end
                    applied[#applied + 1] = { systemId, entry }
                    break
                end
            end
        end
    end
    if #applied == 0 then return false end
    api.SaveLayouts(info)
    for i = 1, #applied do
        local systemId, entry = applied[i][1], applied[i][2]
        local anchor = entry.anchorInfo
        ApplyAnchorVisual(systemId, anchor.point, anchor.relativeTo, anchor.relativePoint,
            tonumber(anchor.offsetX) or 0, tonumber(anchor.offsetY) or 0)
        ApplyVisual(systemId, entry)
    end
    --- One-shot hard resync (LibEditModeOverride's trick): toggling
    --- Blizzard's Edit Mode panel makes the manager reload and re-apply the
    --- saved layouts, so its internal caches finally match our data-only
    --- saves. Only here — after a profile apply a brief flash is fine; per
    --- stepper click it would not be. Never mid-session or in combat.
    if not sessionActive and not InCombat() then
        local manager = _G.EditModeManagerFrame
        if manager and type(_G.ShowUIPanel) == "function" and type(_G.HideUIPanel) == "function" then
            _G.ShowUIPanel(manager)
            _G.HideUIPanel(manager)
            InvalidateLayoutCache()
        end
    end
    return true
end

local function OpenSettings()
    local manager = _G.EditModeManagerFrame
    if InCombat() or not manager then return false end
    if type(_G.ShowUIPanel) == "function" then
        --- Blizzard's own manager can switch the active layout while the MSUF
        --- session stays open. The cached info predates that switch, so keeping
        --- it would make the next mover drag edit the previous layout and save
        --- the whole stale table back over the user's choice. Handing control
        --- over is a save-free moment, so dropping the cache is safe here.
        InvalidateLayoutCache()
        _G.ShowUIPanel(manager)
        return true
    end
    return false
end

local function BlizzardLabel(globalName, fallback)
    local text = _G[globalName]
    if type(text) == "string" and text ~= "" and #text <= 40 then return text end
    return fallback
end

--- Setting steppers/toggles mirror Blizzard's Edit Mode sliders: same ranges,
--- raw layout values converted exactly like their display info does
--- (raw = (display - min) / step). Chat width/height are composite settings
--- split into hundreds and tens-and-ones rows.
local function SteppedSetting(systemId, controlId, globalName, fallback, minValue, maxValue, step, settingId)
    return {
        id = controlId, kind = "number", label = BlizzardLabel(globalName, fallback),
        min = minValue, max = maxValue, step = step,
        get = function()
            local raw = ReadSetting(systemId, settingId)
            if not raw then return nil end
            return raw * step + minValue
        end,
        set = function(value)
            value = tonumber(value)
            if not value then return false end
            local raw = math.floor((value - minValue) / step + 0.5)
            local maxRaw = math.floor((maxValue - minValue) / step + 0.5)
            if raw < 0 then raw = 0 elseif raw > maxRaw then raw = maxRaw end
            return MutateSettings(systemId, { [settingId] = raw })
        end,
    }
end

local function ToggleSetting(systemId, controlId, globalName, fallback, settingId)
    return {
        id = controlId, kind = "toggle", label = BlizzardLabel(globalName, fallback),
        get = function() return ReadSetting(systemId, settingId) == 1 end,
        set = function(value)
            return MutateSettings(systemId, { [settingId] = value and 1 or 0 })
        end,
    }
end

local function CompositeSetting(systemId, controlId, globalName, fallback, minValue, maxValue, hundredsId, tensId)
    return {
        id = controlId, kind = "number", label = BlizzardLabel(globalName, fallback),
        min = minValue, max = maxValue,
        get = function()
            local hundreds = ReadSetting(systemId, hundredsId)
            local tens = ReadSetting(systemId, tensId)
            if not hundreds and not tens then return nil end
            return (hundreds or 0) * 100 + (tens or 0)
        end,
        set = function(value)
            value = tonumber(value)
            if not value then return false end
            value = math.floor(value + 0.5)
            if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
            return MutateSettings(systemId, {
                [hundredsId] = math.floor(value / 100),
                [tensId] = value % 100,
            })
        end,
    }
end

local function Element(systemId, elementId, label, order, controls, settingIds)
    return {
        id = elementId, label = label, group = "Blizzard", order = order,
        getFrame = function() return SystemFrame(systemId) end,
        isEnabled = function()
            return active and Enabled() and Blizzard() ~= nil and SystemFrame(systemId) ~= nil
        end,
        captureState = function() return Capture(systemId, settingIds) end,
        restoreState = function(state) return Restore(systemId, state) end,
        movePosition = function(request) return Move(systemId, request) end,
        openSettings = OpenSettings,
        onSelect = SelectSystem,
        extraControls = controls,
    }
end

--- The tooltip's default-anchor container only exists on screen inside
--- Blizzard's own Edit Mode; mirror that for the MSUF session so its mover
--- has a visible, highlighted target. MSUF unit tooltips using the default
--- anchor follow the moved position automatically.
--- MSUF's tooltip module exports the control mode; without it (older
--- runtime) the Blizzard element stays available.
local function TooltipIsBlizzardControlled()
    local check = _G.MSUF_Tooltip_IsBlizzardControlled
    return type(check) ~= "function" or check() == true
end

local function SessionChanged(enabled)
    sessionActive = enabled == true
    if not enabled then
        if layoutDialog then layoutDialog:Hide() end
        SnapshotAll()
        InvalidateLayoutCache()
    else
        --- Session start is save-free, so this is the safe moment to drop
        --- the cache and see layout switches made outside MSUF. With a
        --- preset active, surface the create-layout dialog immediately so
        --- the user never has to discover why Blizzard elements refuse to
        --- move.
        InvalidateLayoutCache()
        if Enabled() and Blizzard() and not InCombat() and not ActiveLayout() then
            OpenLayoutDialog()
        end
    end
    local container = SystemFrame(systemEnum.HudTooltip)
    if not container then return end
    if enabled and TooltipIsBlizzardControlled() then
        if container.IsShown and not container:IsShown() and container.Show then
            tooltipContainerShown = true
            container:Show()
        end
    elseif tooltipContainerShown then
        tooltipContainerShown = false
        if container.Hide then container:Hide() end
    end
end

local function Add(element)
    if registered[element.id] then return true end
    local ok = API.RegisterElement(OWNER, element)
    if ok then registered[element.id] = true end
    return ok == true
end

local function Activate()
    if active or not Enabled() then return false end
    if not Blizzard() then return false end
    active = true
    local minimapSetting = _G.Enum.EditModeMinimapSetting or {}
    local chatSetting = _G.Enum.EditModeChatFrameSetting or {}
    local microSetting = _G.Enum.EditModeMicroMenuSetting or {}
    local minimapSize = minimapSetting.Size or 2
    local minimapRotate = minimapSetting.RotateMinimap or 1
    local minimapHeader = minimapSetting.HeaderUnderneath or 0
    local chatWidthHundreds = chatSetting.WidthHundreds or 0
    local chatWidthTens = chatSetting.WidthTensAndOnes or 1
    local chatHeightHundreds = chatSetting.HeightHundreds or 2
    local chatHeightTens = chatSetting.HeightTensAndOnes or 3
    local microSize = microSetting.Size or 2
    --- Labels reuse Blizzard's own Edit Mode strings, so the mover markers
    --- match the game's wording in every locale.
    if not Add(Element(systemEnum.Minimap, "minimap",
        BlizzardLabel("HUD_EDIT_MODE_MINIMAP_LABEL", "Minimap"), 860, {
            SteppedSetting(systemEnum.Minimap, "size", "HUD_EDIT_MODE_SETTING_MINIMAP_SIZE",
                "Size", 50, 200, 10, minimapSize),
            ToggleSetting(systemEnum.Minimap, "rotate", "HUD_EDIT_MODE_SETTING_MINIMAP_ROTATE_MINIMAP",
                "Rotate minimap", minimapRotate),
            ToggleSetting(systemEnum.Minimap, "header", "HUD_EDIT_MODE_SETTING_MINIMAP_HEADER_UNDERNEATH",
                "Header underneath", minimapHeader),
        }, { minimapSize, minimapRotate, minimapHeader })) then
        active = false
        return false
    end
    Add(Element(systemEnum.ChatFrame, "chat",
        BlizzardLabel("HUD_EDIT_MODE_CHAT_FRAME_LABEL", "Chat"), 861, {
            CompositeSetting(systemEnum.ChatFrame, "width", "HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH",
                "Width", 250, 800, chatWidthHundreds, chatWidthTens),
            CompositeSetting(systemEnum.ChatFrame, "height", "HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT",
                "Height", 120, 800, chatHeightHundreds, chatHeightTens),
        }, { chatWidthHundreds, chatWidthTens, chatHeightHundreds, chatHeightTens }))
    local microEye = microSetting.EyeSize or 3
    local microOrientation = microSetting.Orientation or 0
    local microOrder = microSetting.Order or 1
    Add(Element(systemEnum.MicroMenu, "micromenu",
        BlizzardLabel("HUD_EDIT_MODE_MICRO_MENU_LABEL", "Micro Menu"), 862, {
            SteppedSetting(systemEnum.MicroMenu, "size", "HUD_EDIT_MODE_SETTING_MICRO_MENU_SIZE",
                "Size", 70, 200, 5, microSize),
            SteppedSetting(systemEnum.MicroMenu, "eyesize", "HUD_EDIT_MODE_SETTING_MICRO_MENU_EYE_SIZE",
                "Eye Size", 50, 150, 5, microEye),
            ToggleSetting(systemEnum.MicroMenu, "vertical",
                "HUD_EDIT_MODE_SETTING_MICRO_MENU_ORIENTATION_VERTICAL", "Vertical", microOrientation),
            ToggleSetting(systemEnum.MicroMenu, "reverse",
                "HUD_EDIT_MODE_SETTING_MICRO_MENU_ORDER_REVERSE", "Reverse", microOrder),
        }, { microSize, microEye, microOrientation, microOrder }))
    if systemEnum.HudTooltip then
        local tooltipElement = Element(systemEnum.HudTooltip, "tooltip",
            BlizzardLabel("HUD_EDIT_MODE_HUD_TOOLTIP_LABEL", "Tooltip"), 863, nil, nil)
        local tooltipBaseEnabled = tooltipElement.isEnabled
        --- Only ONE tooltip surface may exist: while MSUF controls the
        --- tooltip anchor, its own preview/drag owns Edit Mode and this
        --- element stays hidden (and vice versa in the runtime module).
        tooltipElement.isEnabled = function()
            if not TooltipIsBlizzardControlled() then return false end
            return tooltipBaseEnabled()
        end
        Add(tooltipElement)
    end
    if systemEnum.Bags then
        local bagsSetting = _G.Enum.EditModeBagsSetting or {}
        local bagsSize = bagsSetting.Size or 2
        local bagsPadding = bagsSetting.BagSlotPadding or 3
        local bagsOrientation = bagsSetting.Orientation or 0
        local bagsDirection = bagsSetting.Direction or 1
        Add(Element(systemEnum.Bags, "bags",
            BlizzardLabel("HUD_EDIT_MODE_BAGS_LABEL", "Bags"), 864, {
                SteppedSetting(systemEnum.Bags, "size", "HUD_EDIT_MODE_SETTING_BAGS_SIZE",
                    "Size", 75, 200, 5, bagsSize),
                SteppedSetting(systemEnum.Bags, "padding", "HUD_EDIT_MODE_SETTING_BAGS_BAG_SLOT_PADDING",
                    "Bag Slot Padding", 2, 10, 1, bagsPadding),
                ToggleSetting(systemEnum.Bags, "vertical",
                    "HUD_EDIT_MODE_SETTING_BAGS_ORIENTATION_VERTICAL", "Vertical", bagsOrientation),
                ToggleSetting(systemEnum.Bags, "reversedir",
                    "HUD_EDIT_MODE_SETTING_BAGS_DIRECTION", "Reverse direction", bagsDirection),
            }, { bagsSize, bagsPadding, bagsOrientation, bagsDirection }))
    end
    if systemEnum.DamageMeter then
        local meterSetting = _G.Enum.EditModeDamageMeterSetting or {}
        local meterWidth = meterSetting.FrameWidth or 3
        local meterHeight = meterSetting.FrameHeight or 4
        local meterBar = meterSetting.BarHeight or 10
        local meterPad = meterSetting.Padding or 5
        local meterAlpha = meterSetting.Transparency or 6
        local meterBgAlpha = meterSetting.BackgroundTransparency or 12
        local meterText = meterSetting.TextSize or 11
        local meterSpec = meterSetting.ShowSpecIcon or 8
        local meterClass = meterSetting.ShowClassColor or 9
        Add(Element(systemEnum.DamageMeter, "damagemeter",
            BlizzardLabel("HUD_EDIT_MODE_DAMAGE_METER_LABEL", "Damage Meter"), 866, {
                SteppedSetting(systemEnum.DamageMeter, "width",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_FRAME_WIDTH", "Width", 200, 600, 1, meterWidth),
                SteppedSetting(systemEnum.DamageMeter, "height",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_FRAME_HEIGHT", "Height", 120, 400, 1, meterHeight),
                SteppedSetting(systemEnum.DamageMeter, "barheight",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_BAR_HEIGHT", "Bar Height", 15, 40, 1, meterBar),
                SteppedSetting(systemEnum.DamageMeter, "padding",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_PADDING", "Padding", 2, 10, 1, meterPad),
                SteppedSetting(systemEnum.DamageMeter, "transparency",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_TRANSPARENCY", "Opacity", 50, 100, 1, meterAlpha),
                SteppedSetting(systemEnum.DamageMeter, "bgtransparency",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_BACKGROUND", "Background", 0, 100, 1, meterBgAlpha),
                SteppedSetting(systemEnum.DamageMeter, "textsize",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_TEXT_SIZE", "Text Size", 50, 150, 10, meterText),
                ToggleSetting(systemEnum.DamageMeter, "specicon",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_SHOW_SPEC_ICON", "Spec icons", meterSpec),
                ToggleSetting(systemEnum.DamageMeter, "classcolor",
                    "HUD_EDIT_MODE_SETTING_DAMAGE_METER_SHOW_CLASS_COLOR", "Class colors", meterClass),
            }, { meterWidth, meterHeight, meterBar, meterPad, meterAlpha, meterBgAlpha,
                meterText, meterSpec, meterClass }))
    end
    API.RegisterSessionListener(OWNER, SessionChanged)
    if API.RefreshOwner then API.RefreshOwner(OWNER) end
    --- First fill only — an imported snapshot must never be overwritten by
    --- the local layout at load.
    local general = General()
    if general and general.blizzardEditModeSnapshot == nil then SnapshotAll() end
    return true
end

local function Deactivate()
    if not active then return false end
    SessionChanged(false)
    active = false
    if next(registered) then API.UnregisterOwner(OWNER) end
    registered = {}
    return true
end

local function SetEnabled(enabled)
    enabled = enabled ~= false
    local general = General()
    if general then general[SETTING] = enabled end
    return enabled and Activate() or Deactivate()
end

Export("MSUF_BlizzardEditMode_IsAvailable", function() return Blizzard() ~= nil end)
Export("MSUF_BlizzardEditMode_SetEnabled", SetEnabled)
--- Field probe: /run print(MSUF_BlizzardEditMode_EnsureLayout())
Export("MSUF_BlizzardEditMode_EnsureLayout", function() return EnsureEditableLayout() end)
Export("MSUF_BlizzardEditMode_ApplyProfileSnapshot", ApplyProfileSnapshot)
--- Field probe: /run print(MSUF_BlizzardEditMode_Debug())
Export("MSUF_BlizzardEditMode_Debug", function()
    local parts = {}
    for systemId, key in pairs(SNAPSHOT_KEYS) do
        local frame = SystemFrame(systemId)
        local entry = SystemEntry(systemId)
        local rows = entry and type(entry.settings) == "table" and #entry.settings or 0
        parts[#parts + 1] = key .. "=" .. (frame and "frame" or "NOFRAME")
            .. (entry and ("+rows" .. rows) or "+NOENTRY")
    end
    table.sort(parts)
    local minimapCluster = _G.MinimapCluster
    parts[#parts + 1] = "scaleApi=" .. type(minimapCluster and minimapCluster.SetEditModeScale)
    parts[#parts + 1] = "microApi=" .. type(_G.MicroMenu)
    return table.concat(parts, " ")
end)

if Enabled() then Activate() end

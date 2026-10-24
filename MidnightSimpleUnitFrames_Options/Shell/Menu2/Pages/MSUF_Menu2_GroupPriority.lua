--- Menu2 Priority Frames page.
---
--- Priority Frames are profile-wide and inherit the active Party/Raid
--- visual spec. This page owns only cold UI state and calls the dedicated
--- Priority runtime API; it never rebuilds the normal group headers.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua"
-- Core functions this page calls by their global names: required here at
-- load, resolved through MSUF.Require when called so a hook installed on one later still applies.
M.RequireGlobals(FILE, {
    "MSUF_SetManagedBinding",
    "MSUF_ClearManagedBinding",
    "MSUF_EM2_SetFocusSelection",
})

local W = M.Widgets
local Schema = M.ControlSchema
local CUSTOM_OPTIONS = Schema.UnitOptions()
local T = M.Theme
local GP = M.GroupPage or {}
local GF = GP.GF
local ScopeSection = GP.ScopeSection
local ControlMeta = GP.ControlMeta
local RegisterControl = GP.RegisterControl
local SetSectionBadgesAndStatus = GP.SetSectionBadgesAndStatus or M.Noop
local TrackSectionRefresh = GP.TrackSectionRefresh or M.TrackCollapsibleRefresh
local OnOffBadge = GP.OnOffBadge or M.OnOffBadge
local BadgeNumber = GP.BadgeNumber or M.BadgeNumber
local max = math.max
local min = math.min
local floor = math.floor

local PRIORITY_BINDING = "MSUF_PRIORITY_TOGGLE"
local PIN_ROWS_PER_PAGE = 5
local PLACEMENT_VALUES = M.ValueTextList(
    "RAID_RIGHT", "Right of group frames",
    "RAID_LEFT", "Left of group frames",
    "RAID_TOP", "Above group frames",
    "RAID_BOTTOM", "Below group frames",
    "FREE", "Free position"
)
local GROWTH_VALUES = M.ValueTextList(
    "DOWN", "Down",
    "UP", "Up",
    "RIGHT", "Right",
    "LEFT", "Left"
)
local SLOT_VALUES = {
    { value = 1, text = "1" }, { value = 2, text = "2" }, { value = 3, text = "3" },
    { value = 4, text = "4" }, { value = 5, text = "5" },
}

local Tr = M.Tr

local function PriorityConf()
    local gf = GF()
    if gf and type(gf.GetPriorityConf) == "function" then return gf.GetPriorityConf() end
    local db = type(M.EnsureDB) == "function" and M.EnsureDB() or MSUF_DB
    if type(db) ~= "table" then return {} end
    if type(db.gf_priority) ~= "table" then db.gf_priority = {} end
    return db.gf_priority
end

local function PriorityMeta(ctx, path, settingKey)
    local meta = type(ControlMeta) == "function" and ControlMeta(ctx, path, "setting") or {
        pageKey = ctx and ctx.key or "gf_priority",
        classification = "setting",
    }
    meta.settingKey = settingKey
    return meta
end

local function RegisterAction(widget, ctx, path, label, extra, domain)
    if type(RegisterControl) ~= "function" then return widget end
    local directAction = type(extra) == "table" and extra.actionKey and extra.actionKey ~= "open_page"
    local actionLabel = directAction and label or M.Format("Open Priority Frames for %s", M.TranslateText(tostring(label)))
    extra = M.Assign({
        -- Character pins, row indices, and key capture depend on live page
        -- context. From Search chat these controls therefore navigate to
        -- the exact Priority page instead of mutating a guessed character or
        -- row; the physical Menu button keeps its normal direct behavior.
        actionKey = "open_page",
        actionFixedArgs = { page = "gf_priority", label = actionLabel },
    }, extra)
    RegisterControl(widget, ctx, path, actionLabel, "button", "action", extra)
    Schema.Owned(widget, "profile", domain or "priority")
    widget._msuf2ControlSchema.action = Schema.ButtonAction(widget)
    if path == "pins.clear_all" or path:match("^pins%.row%.%d+%.") then
        widget._msuf2ControlSchema.setting = Schema.Record({ "MSUF_GlobalDB.char.{character}.priorityFrames.pins" })
        widget._msuf2ControlSchema.ephemeralReason = nil
    end
    return widget
end

local function RequestPageRefresh(ctx, reason)
    if type(M.RequestRefresh) == "function" then return M.RequestRefresh(ctx, reason or "priority-ui") end
    if type(M.Refresh) == "function" then return M.Refresh(ctx) end
end

local function SetPriorityOption(ctx, key, value, label)
    local conf = PriorityConf()
    if conf[key] == value then return false end
    local gf = GF()
    local changed = false
    local function Write()
        if gf and type(gf.SetPriorityOption) == "function" then
            changed = gf.SetPriorityOption(key, value) ~= false
        else
            conf[key] = value
            changed = true
            if gf and type(gf.RequestPriorityApply) == "function" then
                gf.RequestPriorityApply(key, "menu-option-" .. tostring(key))
            end
        end
        return changed
    end
    if type(M.RunWithHistory) == "function" then
        M.RunWithHistory(M.TranslatedHistoryLabel(label and Tr(label) or M.Format("Priority Frames %s", tostring(key))),
            "group:priority:" .. tostring(key), Write)
    else
        Write()
    end
    if changed then RequestPageRefresh(ctx, "priority-option-" .. tostring(key)) end
    return changed
end

local function Feedback(text, kind, seconds)
    if type(M.ShowStatusFeedback) == "function" then M.ShowStatusFeedback(text, kind, seconds) end
end

local function CenterLabels(...)
    if not T.CenterButtonLabel then return end
    for i = 1, select("#", ...) do T.CenterButtonLabel((select(i, ...))) end
end

-- Profile-scoped text row; returns its widget (word-wrapped when `wrap`).
local function TextRow(ctx, parent, id, text, x, y, width, color, wrap)
    local widget = Schema.Build(ctx, parent, { { "text", id, nil, { text, x, y, width, color }, scope = "profile" } })[id]
    if wrap and widget.SetWordWrap then widget:SetWordWrap(true) end
    return widget
end

-- Collapsible profile-scoped section; returns it with its usable width.
local function OpenSection(b, id, title, height, expanded)
    local section = b:CollapsibleSection(id, title, height, expanded)
    if section._msuf2CollapsibleEntry then Schema.Section(section, "profile") end
    return section, section._msuf2Width or b.width or 720
end

-- Number slider bound to one Priority option; `rounded` rows store floor(value + 0.5).
local function SliderRow(ctx, key, fallback, label, low, high, path, historyLabel, place, rounded)
    return { "slider", key, fallback, { label, low, high, 1, 300 }, place,
        get = function() return tonumber(PriorityConf()[key]) or fallback end,
        write = { call = SetPriorityOption, context = ctx, numberDefault = rounded and fallback or nil,
            round = rounded, args = { historyLabel or label } } --[[schema setter: GroupPriority.Sliders]],
        meta = M.Assign(PriorityMeta(ctx, path, "gf_priority." .. key), { step = 1, roundStep = true }),
        domain = "priority", scope = "profile" }
end

local function FormatBindingKey(key)
    if type(key) ~= "string" or key == "" then return Tr("Not bound") end
    local parts = {}
    for modifier in key:gmatch("(%u+)%-") do
        parts[#parts + 1] = modifier:sub(1, 1) .. modifier:sub(2):lower()
    end
    parts[#parts + 1] = key:match("[^%-]+$") or key
    return table.concat(parts, " + ")
end

local function BindingActionLabel(action)
    if type(action) ~= "string" or action == "" then return Tr("another action") end
    return _G["BINDING_NAME_" .. action] or action
end

-- Blizzard's generic confirmation (M.ShowPrompt); nothing is written to
-- StaticPopupDialogs.
local function ShowBindingConflictPrompt(fullKey, action, commit)
    M.ShowPrompt("MSUF2_PRIORITY_BINDING_CONFLICT", {
        text = string.format(Tr("%s is currently bound to %s. Replace that binding?"),
            FormatBindingKey(fullKey), BindingActionLabel(action)),
        accept = ACCEPT or Tr("Replace"),
        cancel = CANCEL or Tr("Cancel"),
        onAccept = function() commit(fullKey, true) end,
    })
end

local function ShowClearPinsPrompt(clear)
    M.ShowPrompt("MSUF2_PRIORITY_CLEAR_PINS", {
        text = Tr("Clear every manually pinned Priority Frame for this character?"),
        accept = ACCEPT or Tr("Clear all"),
        cancel = CANCEL or Tr("Cancel"),
        onAccept = clear,
    })
end

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
}
-- Keyboard and wheel capture are on only while the hotkey button listens for a key.
local function SetKeyCapture(button, on)
    if button.EnableKeyboard then button:EnableKeyboard(on) end
    if button.EnableMouseWheel then button:EnableMouseWheel(on) end
    if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(not on) end
end
local function BuildBindingCapture(ctx, parent, x, y, width)
    local heading = W.LabelAt(parent, "Hover hotkey", x, y, width, "GameFontNormalSmall", T.colors.accent)
    Schema.Custom(heading, {
        id = "menu2.gf_priority.binding.title", kind = "font", scope = "profile", applyDomain = "presentation", owner = heading })
    local button = T.Button(parent, "Not bound", min(250, width), 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24)
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    SetKeyCapture(button, false)
    CenterLabels(button)
    RegisterAction(button, ctx, "binding.capture", "Priority Frames hotkey", nil, "keyBinding")

    TextRow(ctx, parent, "menu2.gf_priority.bindingcapture.hint",
        "Hover an MSUF Party, Raid, or Priority frame and press this key to pin or unpin that player.",
        x + min(250, width) + 14, y - 22, max(180, width - min(250, width) - 14), T.colors.muted, true)

    local listening = false
    -- CurrentKey runs on every page refresh (RefreshLabel): resolve the provider exactly once.
    local getKeys
    local function CurrentKey()
        getKeys = getKeys or MSUF.Require("MSUF_GetManagedBindingKeys", FILE)
        local keys = getKeys(PRIORITY_BINDING)
        return type(keys) == "table" and keys[1] or nil
    end
    local function RefreshLabel()
        if listening then return end
        button:SetText(FormatBindingKey(CurrentKey()), true)
    end
    local function StopListening(refresh)
        listening = false
        SetKeyCapture(button, false)
        if refresh ~= false then RefreshLabel() end
    end
    local function BeginListening()
        if listening then return end
        listening = true
        button:SetText("Press a key...")
        SetKeyCapture(button, true)
    end
    local function Changed(reason)
        StopListening()
        RequestPageRefresh(ctx, reason or "priority-binding")
        Feedback("Priority hotkey updated", "ok", 1.3)
    end
    local function BindingFailed(code)
        if code == "COMBAT" then
            Feedback("Keybindings cannot be changed during combat.", "danger", 1.8)
        else
            Feedback("Could not update that keybinding.", "danger", 1.8)
        end
    end
    local function ClearBinding()
        if not CurrentKey() then
            StopListening()
            return true
        end
        local ok, code = MSUF.Require("MSUF_ClearManagedBinding", FILE)(PRIORITY_BINDING)
        if ok then Changed("priority-binding-cleared") end
        if not ok then BindingFailed(code) end
        return ok
    end
    local function ApplyKey(key, replaceConflict)
        if CurrentKey() == key then
            StopListening()
            return true
        end
        local ok, code, action = MSUF.Require("MSUF_SetManagedBinding", FILE)(PRIORITY_BINDING, key, replaceConflict == true)
        if ok then Changed(replaceConflict and "priority-binding-replaced" or "priority-binding-set") end
        if not ok and code ~= "CONFLICT" then BindingFailed(code) end
        return ok, code, action
    end
    local function CommitKey(key)
        if not listening or type(key) ~= "string" then return end
        key = key:upper()
        if MODIFIER_KEYS[key] or key == "UNKNOWN" then return end
        if key == "ESCAPE" then
            StopListening()
            return
        end
        if key == "BACKSPACE" or key == "DELETE" then
            ClearBinding()
            return
        end
        local prefix = ""
        if IsShiftKeyDown and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
        if IsControlKeyDown and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
        if IsAltKeyDown and IsAltKeyDown() then prefix = prefix .. "ALT-" end
        local fullKey = prefix .. key
        local ok, code, action = ApplyKey(fullKey, false)
        if ok then return end
        StopListening()
        if code == "CONFLICT" then ShowBindingConflictPrompt(fullKey, action, ApplyKey) end
    end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            StopListening(false)
            ClearBinding()
        elseif listening then
            StopListening()
        else
            BeginListening()
        end
    end)
    button:SetScript("OnKeyDown", function(_, key)
        if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(not listening) end
        if listening then CommitKey(key) end
    end)
    button:HookScript("OnMouseDown", function(_, mouseButton)
        if not listening or mouseButton == "LeftButton" or mouseButton == "RightButton" then return end
        local key = mouseButton == "MiddleButton" and "BUTTON3" or tostring(mouseButton):upper()
        key = key:gsub("^BUTTON", "BUTTON")
        CommitKey(key)
    end)
    button:SetScript("OnMouseWheel", function(_, delta)
        if listening then CommitKey(delta >= 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end
    end)
    button:HookScript("OnHide", function() StopListening(false) end)
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(button, "Priority Frames hotkey",
            "Left-click and press a key. Right-click, Backspace, or Delete clears it. Existing bindings are never replaced without confirmation.",
                { hook = true })
    end
    M.TrackRefresh(ctx, RefreshLabel)
    return button, RefreshLabel, StopListening
end

local function OpenPriorityEditModeWithFeedback()
    local enabled = PriorityConf().enabled == true
    if type(M.SetMSUFEditModeActive) ~= "function" then return false end
    local ok = M.SetMSUFEditModeActive(true, "gf_priority", { source = "priority-page" })
    if ok then
        MSUF.Require("MSUF_EM2_SetFocusSelection", FILE)("gf_priority", "placement", nil, {
            source = "priority-page",
            menu = false,
        })
        Feedback(enabled and "Priority Frames selected in Edit Mode"
            or "Priority Frames remain disabled; Edit Mode is showing the placement preview.",
            enabled and "ok" or "info", 1.8)
    end
    return ok
end

-- A button that opens Edit Mode on the Priority Frames placement.
local function EditModeButton(ctx, parent, text, width, point, x, y, path, label)
    local button = T.Button(parent, text, width, 26)
    button:SetPoint(point, parent, point, x, y)
    CenterLabels(button)
    button:SetScript("OnClick", OpenPriorityEditModeWithFeedback)
    return RegisterAction(button, ctx, path, label, {
        actionKey = "menu.action.editMode.enter",
        actionFixedArgs = { unit = "gf_priority" },
    })
end

local function BuildPriorityPlacement(ctx, b)
    local placement, placementW = OpenSection(b, "placement", "Placement", 525, false)
    local rightX = max(360, placementW - 342)
    local placementControls = Schema.Build(ctx, placement, {
        { "text", "menu2.gf_priority.placement.help", nil,
            { "Attach the strip to the active Party, Raid, or Mythic Raid container, or choose Free position and place it with Edit Mode.",
            24, -40, placementW - 48, T.colors.muted }, scope = "profile" },
        { "dropdown", "place", nil, { "Placement", PLACEMENT_VALUES, 300 }, { 24, -80, 300, "LEFT" }, get = function() return PriorityConf().anchorMode or
            "RAID_RIGHT" end,
            write = { call = SetPriorityOption, context = ctx, fallback = "RAID_RIGHT",
                args = { "Priority Frames placement" } } --[[schema setter: GroupPriority.2]],
            meta = PriorityMeta(ctx, "placement.mode", "gf_priority.anchorMode"), domain = "priority", scope = "profile" },
        { "segment", "growth", nil, { "Growth", GROWTH_VALUES, 318 }, { rightX, -80, 318, "LEFT" }, get = function() return
            PriorityConf().growth or "DOWN" end,
            write = { call = SetPriorityOption, context = ctx, fallback = "DOWN", args = { "Priority Frames growth" } } --[[schema setter: GroupPriority.3]],
            meta = PriorityMeta(ctx, "placement.growth", "gf_priority.growth"), domain = "priority", scope = "profile" },
        SliderRow(ctx, "spacing", 2, "Frame spacing", 0, 40, "placement.spacing", "Priority Frames spacing",
            { 24, -156, 300, "LEFT" }, true),
        SliderRow(ctx, "attachGap", 8, "Attachment gap", 0, 100, "placement.attach_gap", "Priority Frames attachment gap",
            { rightX, -156, 300, "LEFT" }, true),
        SliderRow(ctx, "attachOffset", 0, "Alignment offset", -200, 200, "placement.attach_offset",
            "Priority Frames alignment offset", { 24, -230, 300, "LEFT" }, true),
    }, CUSTOM_OPTIONS)
    local attachGap = placementControls.attachGap
    local attachOffset = placementControls.attachOffset
    local move = EditModeButton(ctx, placement, "Position in Edit Mode", 172, "TOPLEFT", rightX, -252,
        "placement.open_edit_mode", "Position Priority Frames in Edit Mode")
    for _, entry in ipairs({
        { "width", "Priority frame width (0 inherits)", 0, 500, 0, 24, -342 },
        { "height", "Priority frame height (0 inherits)", 0, 200, 0, rightX, -342 },
        { "unitsPerColumn", "Frames per row or column", 1, 5, 5, 24, -422 },
    }) do
        local key, label, low, high, fallback, x, y = unpack(entry)
        local row = SliderRow(ctx, key, fallback, label, low, high, "placement." .. key)
        row.beforeBind = function(widget) W.MoveWidget(widget, placement, x, y, 300, "LEFT") end
        Schema.Build(ctx, placement, { row }, CUSTOM_OPTIONS)
    end
    local placementHint = TextRow(ctx, placement, "menu2.gf_priority.prioritypage.placementHint", "", 24, -490,
        placementW - 48, T.colors.muted)
    local function RefreshPlacement()
        local conf = PriorityConf()
        local attached = conf.anchorMode ~= "FREE"
        move:SetText(conf.enabled == true and "Position in Edit Mode" or "Preview position in Edit Mode")
        W.SetControlEnabled(attachGap, attached)
        W.SetControlEnabled(attachOffset, attached)
        placementHint:SetText(attached and "The strip follows the active Party, Raid, or Mythic Raid container automatically."
            or "Free position uses the dedicated Priority Frames mover.")
        SetSectionBadgesAndStatus(placement, {
            { text = Tr(attached and "Attached" or "Free"), kind = attached and "info" or "accent" },
            { text = Tr("Growth: ") .. Tr((conf.growth or "DOWN"):sub(1, 1) .. (conf.growth or "DOWN"):sub(2):lower()), kind = "muted" },
            { text = BadgeNumber(conf.spacing or 2) .. " px", kind = "muted" },
        })
    end
    TrackSectionRefresh(ctx, placement, RefreshPlacement)
end

-- Snapshot first in the page refresher list. Overview and the pooled pin
-- rows then consume the same roster resolution instead of each scanning
-- the active Party or Raid roster independently. snap.state / snap.pins are
-- scratch tables the group module refills in place. The refresher is built once per
-- page, so each refresh is still exactly one call.
local function SnapshotRefresher(snap)
    return function()
        local gf = GF()
        if gf and type(gf.GetPriorityMenuSnapshot) == "function" then
            local state, pins = gf.GetPriorityMenuSnapshot(snap.state, snap.pins)
            if type(state) == "table" then snap.state = state end
            if type(pins) == "table" then snap.pins = pins end
            return
        end
        if gf and type(gf.GetPriorityState) == "function" then
            snap.state = gf.GetPriorityState(snap.state) or snap.state
        end
        if gf and type(gf.GetPriorityPinView) == "function" then
            snap.pins = gf.GetPriorityPinView(snap.pins) or snap.pins
        elseif gf and type(gf.GetPriorityPins) == "function" then
            snap.pins = gf.GetPriorityPins() or snap.pins
        end
    end
end

local function BuildPriorityOverview(ctx, b, snap)
    local overview, overviewW = OpenSection(b, "overview", "Priority Frames", 220, true)
    Schema.Build(ctx, overview, {
        { "text", "menu2.gf_priority.overview.help", nil,
            { "Keep tanks and manually pinned group members in one stable strip without removing them from the normal Party or Raid frames.",
            24, -40, overviewW - 210, T.colors.muted }, scope = "profile" },
        { "switch", "enable", nil, { "Enable Priority Frames", 24, -88, 310 }, get = function() return PriorityConf().enabled == true end,
            write = { call = SetPriorityOption, context = ctx, strictBoolean = true, args = { "Enable Priority Frames" } } --[[schema setter: GroupPriority.4]],
            meta = PriorityMeta(ctx, "overview.enabled", "gf_priority.enabled"), domain = "priority", scope = "profile" },
    }, CUSTOM_OPTIONS)
    local editMode = EditModeButton(ctx, overview, "Open Edit Mode", 146, "TOPRIGHT", -22, -40,
        "overview.open_edit_mode", "Open Priority Frames in Edit Mode")
    local statusLabels = Schema.Build(ctx, overview, {
        { "text", "menu2.gf_priority.prioritypage.liveStatus", nil, { "", 24, -132, overviewW - 48, T.colors.accent }, scope = "profile" },
        { "text", "menu2.gf_priority.prioritypage.behavior", nil,
            { "Profile-wide layout · character-specific pins · available in parties and raids · inherits the active " ..
                "group-frame appearance and click-cast behavior.",
            24, -166, overviewW - 48, T.colors.muted }, scope = "profile" },
    })
    local liveStatus = statusLabels["menu2.gf_priority.prioritypage.liveStatus"]
    local behavior = statusLabels["menu2.gf_priority.prioritypage.behavior"]
    if behavior.SetWordWrap then behavior:SetWordWrap(true) end
    local function RefreshOverview()
        local state = snap.state
        local enabled = state.enabled == true
        local active = tonumber(state.activeCount) or 0
        local pins = tonumber(state.pinCount) or 0
        local inGroup = state.inGroup == true
        local inParty = state.inParty == true
        editMode:SetText(enabled and "Open Edit Mode" or "Preview in Edit Mode")
        if enabled and inGroup and state.baseFramesEnabled == false then
            liveStatus:SetText(inParty and "Waiting — enable Party frames first."
                or "Waiting — enable the active Raid or Mythic Raid frames first.")
        elseif enabled and inGroup and active > 0 then
            T.SetTranslatedText(liveStatus, M.Format("Active now: %d / %d", active, tonumber(state.maxFrames) or 5))
        elseif enabled and inGroup and pins > 0 then
            liveStatus:SetText("Waiting — none of your saved players are in the current group.")
        elseif enabled and inGroup then
            liveStatus:SetText("Ready — pin a group member or include tanks automatically.")
        elseif enabled then
            liveStatus:SetText("Ready — join a party or raid to show Priority Frames.")
        else
            liveStatus:SetText("Disabled — your manual pins stay saved.")
        end
        SetSectionBadgesAndStatus(overview, {
            OnOffBadge(enabled, "Enabled", "Disabled"),
            { text = M.Format("%s visible", BadgeNumber(active)), kind = active > 0 and "accent" or "muted" },
            { text = M.Format("%s pinned", BadgeNumber(pins)), kind = pins > 0 and "info" or "muted" },
            { text = Tr(inParty and "In party" or (state.inRaid == true and "In raid" or "Not grouped")),
              kind = inGroup and "ok" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, overview, RefreshOverview)
end

-- One pooled row of the manual pin list: the labels, the Up / Down / Remove buttons and their declarations.
local function BuildPinRow(ctx, pinsCard, pinsCardW, i)
    local row = T.Panel(pinsCard, nil, { 0.018, 0.032, 0.064, 0.78 }, T.colors.borderSoft)
    row:SetPoint("TOPLEFT", pinsCard, "TOPLEFT", 16, -66 - ((i - 1) * 30))
    row:SetPoint("TOPRIGHT", pinsCard, "TOPRIGHT", -16, -66 - ((i - 1) * 30))
    row:SetHeight(26)
    local labels = Schema.Build(ctx, row, {
        { "font", "menu2.gf_priority.pins.number." .. i, nil, { "GameFontNormalSmall", tostring(i), T.colors.dim }, scope = "profile" },
        { "font", "menu2.gf_priority.pins.name." .. i, nil, { "GameFontHighlightSmall", "", T.colors.text }, scope = "profile" },
        { "font", "menu2.gf_priority.pins.status." .. i, nil, { "GameFontDisableSmall", "", T.colors.muted }, scope = "profile" },
    })
    local number, name, status = labels["menu2.gf_priority.pins.number." .. i],
        labels["menu2.gf_priority.pins.name." .. i], labels["menu2.gf_priority.pins.status." .. i]
    number:SetPoint("LEFT", row, "LEFT", 8, 0)
    number:SetWidth(22)
    name:SetPoint("LEFT", number, "RIGHT", 4, 0)
    name:SetWidth(max(150, pinsCardW - 330))
    name:SetJustifyH("LEFT")
    status:SetPoint("RIGHT", row, "RIGHT", -176, 0)
    status:SetWidth(130)
    status:SetJustifyH("RIGHT")
    local up = T.Button(row, "Up", 42, 20)
    local down = T.Button(row, "Down", 48, 20)
    local remove = T.Button(row, "Remove", 68, 20)
    remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    down:SetPoint("RIGHT", remove, "LEFT", -4, 0)
    up:SetPoint("RIGHT", down, "LEFT", -4, 0)
    CenterLabels(up, down, remove)
    RegisterAction(up, ctx, "pins.row." .. i .. ".up", "Move pinned player up")
    RegisterAction(down, ctx, "pins.row." .. i .. ".down", "Move pinned player down")
    RegisterAction(remove, ctx, "pins.row." .. i .. ".remove", "Remove pinned player")
    Schema.Custom(row, { id = "menu2.gf_priority.pins.row." .. i, kind = "pinRow",
        scope = "character", applyDomain = "priority", owner = row })
    return { frame = row, number = number, name = name, status = status, up = up, down = down, remove = remove }
end

-- The "Manual pins" card: header, paging, empty note, the pooled rows and the clear-all button.
local function BuildPinsCard(ctx, who, whoW)
    local pinsCard = Schema.Build(ctx, who, { { "card", "menu2.gf_priority.prioritypage.pinsCard", nil, { "Manual pins", nil, 20, -232,
        whoW - 40, 246 }, domain = "layout", scope = "profile" }, })["menu2.gf_priority.prioritypage.pinsCard"]
    local pinsCardW = whoW - 40
    local pinsStatus = TextRow(ctx, pinsCard, "menu2.gf_priority.prioritypage.pinsStatus", "", 16, -42,
        pinsCardW - 260, T.colors.muted)
    local prevPage = T.Button(pinsCard, "Previous", 72, 22)
    local nextPage = T.Button(pinsCard, "Next", 58, 22)
    local pageText = Schema.Build(ctx, pinsCard, { { "font", "menu2.gf_priority.prioritypage.pageText", nil, { "GameFontDisableSmall", "",
        T.colors.dim }, scope = "profile" }, })["menu2.gf_priority.prioritypage.pageText"]
    nextPage:SetPoint("TOPRIGHT", pinsCard, "TOPRIGHT", -16, -36)
    pageText:SetPoint("RIGHT", nextPage, "LEFT", -8, 0)
    prevPage:SetPoint("RIGHT", pageText, "LEFT", -8, 0)
    CenterLabels(prevPage, nextPage)
    RegisterAction(prevPage, ctx, "pins.page.previous", "Previous pinned players")
    RegisterAction(nextPage, ctx, "pins.page.next", "Next pinned players")
    local emptyPins = TextRow(ctx, pinsCard, "menu2.gf_priority.prioritypage.emptyPins",
        "No manual pins yet. While grouped, hover an MSUF Party, Raid, or Priority frame, then press your hotkey.", 18, -104,
        pinsCardW - 36, T.colors.muted, true)
    local pinRows = {}
    for i = 1, PIN_ROWS_PER_PAGE do pinRows[i] = BuildPinRow(ctx, pinsCard, pinsCardW, i) end

    local clearPins = W.RoleButton(who, "Clear all", "danger", 92, 24)
    clearPins:SetPoint("TOPLEFT", who, "TOPLEFT", 24, -500)
    CenterLabels(clearPins)
    RegisterAction(clearPins, ctx, "pins.clear_all", "Clear all Priority Frame pins")
    TextRow(ctx, who, "menu2.gf_priority.prioritypage.hotkeyHint", "Use the hover hotkey above to add or remove players.",
        124, -503, whoW - 164, T.colors.muted, true)
    return { status = pinsStatus, prevPage = prevPage, nextPage = nextPage, pageText = pageText, emptyPins = emptyPins,
        rows = pinRows, clearPins = clearPins }
end

local PIN_WAIT_STATUS = {
    CAPACITY = "Saved · slots full",
    NOT_IN_GROUP = "Saved · not grouped",
    NOT_PRESENT = "Saved · not in current group",
    DISABLED = "Saved · Priority Frames disabled",
}

-- Up / Down click handler: moves the row's pin by `delta`, then refreshes the page.
local function PinMoveClick(ctx, delta, reason)
    return function(self)
        local gf = GF()
        if self._pinIndex and gf and type(gf.MovePriorityPin) == "function" and gf.MovePriorityPin(self._pinIndex, delta) then
            RequestPageRefresh(ctx, reason)
        end
    end
end

-- Paging, the pooled row refresh and the button handlers of the manual pin list.
local function BindPriorityPins(ctx, who, snap, ui)
    local pinPage = tonumber(M.gfPriorityPinPage) or 1
    local function SetPinPage(value)
        pinPage = max(1, floor((tonumber(value) or 1) + 0.5))
        M.gfPriorityPinPage = pinPage
        RequestPageRefresh(ctx, "priority-pin-page")
    end
    ui.prevPage:SetScript("OnClick", function() SetPinPage(pinPage - 1) end)
    ui.nextPage:SetScript("OnClick", function() SetPinPage(pinPage + 1) end)
    local function RefreshPins()
        local entries, state = snap.pins, snap.state
        local count = #entries
        local pages = max(1, math.ceil(count / PIN_ROWS_PER_PAGE))
        if pinPage > pages then
            pinPage = pages
            M.gfPriorityPinPage = pinPage
        end
        local first = (pinPage - 1) * PIN_ROWS_PER_PAGE + 1
        T.SetTranslatedText(ui.status, count == 1 and Tr("1 saved player") or M.Format("%d saved players", count))
        ui.pageText:SetText(tostring(pinPage) .. " / " .. tostring(pages))
        ui.prevPage:SetShown(pages > 1)
        ui.nextPage:SetShown(pages > 1)
        ui.pageText:SetShown(pages > 1)
        W.SetControlEnabled(ui.prevPage, pinPage > 1)
        W.SetControlEnabled(ui.nextPage, pinPage < pages)
        ui.emptyPins:SetShown(count == 0)
        W.SetControlEnabled(ui.clearPins, count > 0)
        for slot = 1, PIN_ROWS_PER_PAGE do
            local row = ui.rows[slot]
            local index = first + slot - 1
            local entry = entries[index]
            if entry then
                local active = entry.active == true
                local statusText
                if active and entry.isTank == true and state.autoTanks == true then
                    statusText = "Visible · auto tank"
                elseif active then
                    statusText = "Visible"
                elseif entry.waitingReason == "GROUP_FRAMES_DISABLED" then
                    statusText = state.inParty == true and "Saved · Party frames disabled"
                        or "Saved · Raid frames disabled"
                else
                    statusText = PIN_WAIT_STATUS[entry.waitingReason] or "Saved"
                end
                row.number:SetText(tostring(index))
                T.SetTranslatedText(row.name, entry.name or Tr("Unknown player"))
                row.status:SetText(statusText)
                local color = active and T.colors.accent or T.colors.muted
                row.status:SetTextColor(color[1], color[2], color[3], color[4] or 1)
                row.up._pinIndex = index
                row.down._pinIndex = index
                row.remove._pinIndex = index
                W.SetControlEnabled(row.up, index > 1)
                W.SetControlEnabled(row.down, index < count)
                row.frame:Show()
            else
                row.up._pinIndex, row.down._pinIndex, row.remove._pinIndex = nil, nil, nil
                row.frame:Hide()
            end
        end
        SetSectionBadgesAndStatus(who, {
            OnOffBadge(state.autoTanks == true, "Auto tanks", "Manual only"),
            { text = M.Format("%s slots", BadgeNumber(state.maxFrames or 5)), kind = "info" },
            { text = M.Format("%s saved", BadgeNumber(count)), kind = count > 0 and "accent" or "muted" },
        })
    end
    for i = 1, PIN_ROWS_PER_PAGE do
        local row = ui.rows[i]
        row.up:SetScript("OnClick", PinMoveClick(ctx, -1, "priority-pin-up"))
        row.down:SetScript("OnClick", PinMoveClick(ctx, 1, "priority-pin-down"))
        row.remove:SetScript("OnClick", function(self)
            local gf = GF()
            if self._pinIndex and gf and type(gf.RemovePriorityPin) == "function" and gf.RemovePriorityPin(self._pinIndex) then
                Feedback("Priority pin removed", "ok", 1.2)
                RequestPageRefresh(ctx, "priority-pin-removed")
            end
        end)
    end
    ui.clearPins:SetScript("OnClick", function()
        local gf = GF()
        if not (gf and type(gf.ClearPriorityPins) == "function") then return end
        ShowClearPinsPrompt(function()
            if gf.ClearPriorityPins() then
                SetPinPage(1)
                Feedback("All Priority pins cleared", "ok", 1.3)
            end
        end)
    end)
    TrackSectionRefresh(ctx, who, RefreshPins)
end

local function BuildPriorityWho(ctx, b, snap)
    local who, whoW = OpenSection(b, "who_appears", "Who Appears", 548, true)
    local selectionControls = Schema.Build(ctx, who, {
        { "switch", "autoTanks", nil, { "Include tanks automatically", 24, -52, 330 }, get = function() return PriorityConf().autoTanks == true end,
            write = { call = SetPriorityOption, context = ctx, strictBoolean = true,
                args = { "Priority Frames automatic tanks" } } --[[schema setter: GroupPriority.5]],
            meta = PriorityMeta(ctx, "selection.auto_tanks", "gf_priority.autoTanks"), domain = "priority", scope = "profile" },
        { "segment", "slots", nil, { "Visible slots", SLOT_VALUES, 300 }, { max(380, whoW - 320), -30, 292, "LEFT" }, get = function() return
            floor((tonumber(PriorityConf().maxFrames) or 5) + 0.5) end,
            write = { call = SetPriorityOption, context = ctx, numberDefault = 5,
                args = { "Priority Frames visible slots" } } --[[schema setter: GroupPriority.6]],
            meta = PriorityMeta(ctx, "selection.max_frames", "gf_priority.maxFrames"), domain = "priority", scope = "profile" },
        { "card", "menu2.gf_priority.prioritypage.bindingCard", nil, { "Fast pinning", nil, 20, -106, whoW - 40, 112 }, domain = "layout", scope = "profile" },
    }, CUSTOM_OPTIONS)
    local bindingCard = selectionControls["menu2.gf_priority.prioritypage.bindingCard"]
    BuildBindingCapture(ctx, bindingCard, 16, -42, whoW - 72)
    BindPriorityPins(ctx, who, snap, BuildPinsCard(ctx, who, whoW))
end

local function RegisterPriorityListener(ctx)
    M._priorityMenuListenerSerial = (M._priorityMenuListenerSerial or 0) + 1
    local listenerOwner = "Menu2Priority:" .. tostring(M._priorityMenuListenerSerial)
    local listenerActive = false
    local listenerGF
    local function RegisterListener()
        local gf = GF()
        if listenerActive or not (gf and type(gf.RegisterPriorityListener) == "function") then return end
        listenerActive = gf.RegisterPriorityListener(listenerOwner, function(reason)
            if ctx.wrapper and ctx.wrapper.IsShown and ctx.wrapper:IsShown() then
                RequestPageRefresh(ctx, "priority-listener-" .. tostring(reason or "change"))
            end
        end) == true
        listenerGF = listenerActive and gf or nil
        -- Cached pages can reopen after the menu spent minutes hidden. Marking
        -- the cold page data dirty here makes SelectPage run the shared snapshot
        -- exactly once without retaining roster events while the page is hidden.
        if listenerActive and type(M.MarkMenuDataDirty) == "function" then
            M.MarkMenuDataDirty("priority-page-shown")
        end
    end
    local function UnregisterListener()
        if not listenerActive then return end
        listenerActive = false
        local gf = listenerGF or GF()
        listenerGF = nil
        if gf and type(gf.UnregisterPriorityListener) == "function" then gf.UnregisterPriorityListener(listenerOwner) end
    end
    if ctx.wrapper and ctx.wrapper.HookScript then
        ctx.wrapper:HookScript("OnShow", RegisterListener)
        ctx.wrapper:HookScript("OnHide", UnregisterListener)
        if ctx.wrapper.IsShown and ctx.wrapper:IsShown() then RegisterListener() end
    end
end

local function BuildPriorityPage(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b, { priorityMode = true })
    local snap = { state = {}, pins = {} }
    M.TrackRefresh(ctx, SnapshotRefresher(snap))
    BuildPriorityOverview(ctx, b, snap)
    BuildPriorityWho(ctx, b, snap)
    BuildPriorityPlacement(ctx, b)
    RegisterPriorityListener(ctx)

    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(math.abs(b.y) + 42) end
end

M.RegisterPage("gf_priority", { title = "MSUF Priority Frames", build = BuildPriorityPage, version = 1 })

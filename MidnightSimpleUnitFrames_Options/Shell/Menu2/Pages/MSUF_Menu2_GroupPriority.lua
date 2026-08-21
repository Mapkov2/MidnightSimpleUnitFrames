--- Menu2 Priority Frames page.
---
--- Priority Frames are profile-wide and inherit the active Party/Raid
--- visual spec. This page owns only cold UI state and calls the dedicated
--- Priority runtime API; it never rebuilds the normal group headers.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local GF = GP.GF or function() return MSUF and MSUF.GF end
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

local function Tr(text)
    return type(M.Tr) == "function" and M.Tr(text) or tostring(text or "")
end

local function PriorityConf()
    local gf = GF()
    if gf and type(gf.GetPriorityConf) == "function" then return gf.GetPriorityConf() end
    local db = type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
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
    meta.assistantDisposition = nil
    meta.assistantDispositionReason = nil
    return meta
end

local function RegisterAction(widget, ctx, path, label, extra)
    if type(RegisterControl) ~= "function" then return widget end
    local directAssistantAction = type(extra) == "table" and extra.actionKey and extra.actionKey ~= "open_page"
    local assistantLabel = directAssistantAction and label or ("Open Priority Frames for " .. tostring(label))
    extra = M.Assign({
        -- Character pins, row indices, and key capture depend on live page
        -- context. From Assistant chat these controls therefore navigate to
        -- the exact Priority page instead of mutating a guessed character or
        -- row; the physical Menu button keeps its normal direct behavior.
        actionKey = "open_page",
        actionFixedArgs = { page = "gf_priority", label = assistantLabel },
    }, extra)
    return RegisterControl(widget, ctx, path, assistantLabel, "button", "action", extra)
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
        M.RunWithHistory(label and Tr(label) or M.Format("Priority Frames %s", tostring(key)), "group:priority:" .. tostring(key), Write)
    else
        Write()
    end
    if changed then RequestPageRefresh(ctx, "priority-option-" .. tostring(key)) end
    return changed
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

local function EnsureBindingConflictPopup()
    if not _G.StaticPopupDialogs or _G.StaticPopupDialogs.MSUF2_PRIORITY_BINDING_CONFLICT then return end
    _G.StaticPopupDialogs.MSUF2_PRIORITY_BINDING_CONFLICT = {
        text = Tr("%s is currently bound to %s. Replace that binding?"),
        button1 = _G.ACCEPT or Tr("Replace"),
        button2 = _G.CANCEL or Tr("Cancel"),
        OnAccept = function(_, data)
            if not data then return end
            if type(data.commit) == "function" then data.commit(data.key, true); return end
            if type(_G.MSUF_SetManagedBinding) ~= "function" then return end
            local ok = _G.MSUF_SetManagedBinding(PRIORITY_BINDING, data.key, true)
            if ok and type(data.refresh) == "function" then data.refresh("priority-binding-replaced") end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

local function EnsureClearPinsPopup()
    if not _G.StaticPopupDialogs or _G.StaticPopupDialogs.MSUF2_PRIORITY_CLEAR_PINS then return end
    _G.StaticPopupDialogs.MSUF2_PRIORITY_CLEAR_PINS = {
        text = Tr("Clear every manually pinned Priority Frame for this character?"),
        button1 = _G.ACCEPT or Tr("Clear all"),
        button2 = _G.CANCEL or Tr("Cancel"),
        OnAccept = function(_, data)
            if not data or type(data.clear) ~= "function" then return end
            data.clear()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
}
local function BuildBindingCapture(ctx, parent, x, y, width)
    W.LabelAt(parent, "Hover hotkey", x, y, width, "GameFontNormalSmall", T.colors.accent)
    local button = T.Button(parent, Tr("Not bound"), min(250, width), 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24)
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if button.EnableKeyboard then button:EnableKeyboard(false) end
    if button.EnableMouseWheel then button:EnableMouseWheel(false) end
    if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(true) end
    if T.CenterButtonLabel then T.CenterButtonLabel(button) end
    RegisterAction(button, ctx, "binding.capture", "Priority Frames hotkey")

    local hint = W.Text(parent,
        "Hover an MSUF Party, Raid, or Priority frame and press this key to pin or unpin that player.",
        x + min(250, width) + 14, y - 22, max(180, width - min(250, width) - 14), T.colors.muted)
    if hint.SetWordWrap then hint:SetWordWrap(true) end

    local listening = false
    local function CurrentKey()
        local get = _G.MSUF_GetManagedBindingKeys
        local keys = type(get) == "function" and get(PRIORITY_BINDING) or nil
        return type(keys) == "table" and keys[1] or nil
    end
    local function RefreshLabel()
        if listening then return end
        button:SetText(FormatBindingKey(CurrentKey()))
    end
    local function StopListening(refresh)
        listening = false
        if button.EnableKeyboard then button:EnableKeyboard(false) end
        if button.EnableMouseWheel then button:EnableMouseWheel(false) end
        if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(true) end
        if refresh ~= false then RefreshLabel() end
    end
    local function BeginListening()
        if listening then return end
        listening = true
        button:SetText(Tr("Press a key..."))
        if button.EnableKeyboard then button:EnableKeyboard(true) end
        if button.EnableMouseWheel then button:EnableMouseWheel(true) end
        if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(false) end
    end
    local function Changed(reason)
        StopListening()
        RequestPageRefresh(ctx, reason or "priority-binding")
        if type(M.ShowStatusFeedback) == "function" then M.ShowStatusFeedback(Tr("Priority hotkey updated"), "ok", 1.3) end
    end
    local function BindingFailed(code)
        if type(M.ShowStatusFeedback) ~= "function" then return end
        if code == "COMBAT" then
            M.ShowStatusFeedback(Tr("Keybindings cannot be changed during combat."), "danger", 1.8)
        else
            M.ShowStatusFeedback(Tr("Could not update that keybinding."), "danger", 1.8)
        end
    end
    local function ClearBinding()
        if not CurrentKey() then StopListening(); return true end
        if type(_G.MSUF_ClearManagedBinding) ~= "function" then return false end
        local ok, code = _G.MSUF_ClearManagedBinding(PRIORITY_BINDING)
        if ok then Changed("priority-binding-cleared") end
        if not ok then BindingFailed(code) end
        return ok
    end
    local function ApplyKey(key, replaceConflict)
        if CurrentKey() == key then StopListening(); return true end
        local set = _G.MSUF_SetManagedBinding
        if type(set) ~= "function" then return false, "UNAVAILABLE" end
        local ok, code, action = set(PRIORITY_BINDING, key, replaceConflict == true)
        if ok then Changed(replaceConflict and "priority-binding-replaced" or "priority-binding-set") end
        if not ok and code ~= "CONFLICT" then BindingFailed(code) end
        return ok, code, action
    end
    local function CommitKey(key)
        if not listening or type(key) ~= "string" then return end
        key = key:upper()
        if MODIFIER_KEYS[key] or key == "UNKNOWN" then return end
        if key == "ESCAPE" then StopListening(); return end
        if key == "BACKSPACE" or key == "DELETE" then ClearBinding(); return end
        local prefix = ""
        if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
        if _G.IsControlKeyDown and _G.IsControlKeyDown() then prefix = prefix .. "CTRL-" end
        if _G.IsAltKeyDown and _G.IsAltKeyDown() then prefix = prefix .. "ALT-" end
        local fullKey = prefix .. key
        local ok, code, action = ApplyKey(fullKey, false)
        if ok then return end
        StopListening()
        if code == "CONFLICT" then
            EnsureBindingConflictPopup()
            if _G.StaticPopup_Show then
                _G.StaticPopup_Show("MSUF2_PRIORITY_BINDING_CONFLICT", FormatBindingKey(fullKey), BindingActionLabel(action), {
                    key = fullKey,
                    commit = ApplyKey,
                    refresh = Changed,
                })
            end
        end
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
        if not listening then
            if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(true) end
            return
        end
        if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(false) end
        CommitKey(key)
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
            "Left-click and press a key. Right-click, Backspace, or Delete clears it. Existing bindings are never replaced without confirmation.", { hook = true })
    end
    M.TrackRefresh(ctx, RefreshLabel)
    return button, RefreshLabel, StopListening
end

local function OpenPriorityEditMode()
    if type(M.SetMSUFEditModeActive) ~= "function" then return false end
    local ok = M.SetMSUFEditModeActive(true, "gf_priority", { source = "priority-page" })
    if ok and type(_G.MSUF_EM2_SetFocusSelection) == "function" then
        _G.MSUF_EM2_SetFocusSelection("gf_priority", "placement", nil, {
            source = "priority-page",
            menu = false,
        })
    end
    return ok
end

local function OpenPriorityEditModeWithFeedback()
    local enabled = PriorityConf().enabled == true
    local ok = OpenPriorityEditMode()
    if ok and type(M.ShowStatusFeedback) == "function" then
        M.ShowStatusFeedback(enabled and Tr("Priority Frames selected in Edit Mode")
            or Tr("Priority Frames remain disabled; Edit Mode is showing the placement preview."),
            enabled and "ok" or "info", 1.8)
    end
    return ok
end

local function BuildPriorityPage(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b, { priorityMode = true })

    -- Snapshot first in the page refresher list. Overview and the pooled pin
    -- rows then consume the same roster resolution instead of each scanning
    -- the active Party or Raid roster independently.
    local stateScratch, pinViewScratch = {}, {}
    local function RefreshSnapshot()
        local gf = GF()
        if gf and type(gf.GetPriorityMenuSnapshot) == "function" then
            local state, pins = gf.GetPriorityMenuSnapshot(stateScratch, pinViewScratch)
            if type(state) == "table" then stateScratch = state end
            if type(pins) == "table" then pinViewScratch = pins end
            return
        end
        if gf and type(gf.GetPriorityState) == "function" then
            stateScratch = gf.GetPriorityState(stateScratch) or stateScratch
        end
        if gf and type(gf.GetPriorityPinView) == "function" then
            pinViewScratch = gf.GetPriorityPinView(pinViewScratch) or pinViewScratch
        elseif gf and type(gf.GetPriorityPins) == "function" then
            pinViewScratch = gf.GetPriorityPins() or pinViewScratch
        end
    end
    M.TrackRefresh(ctx, RefreshSnapshot)

    local overview = b:CollapsibleSection("overview", "Priority Frames", 220, true)
    local overviewW = overview._msuf2Width or b.width or 720
    W.Text(overview,
        "Keep tanks and manually pinned group members in one stable strip without removing them from the normal Party or Raid frames.",
        24, -40, overviewW - 210, T.colors.muted)
    local enable = W.SwitchAt(overview, "Enable Priority Frames", 24, -88, 310)
    M.BindBoolWidget(ctx, enable,
        function() return PriorityConf().enabled == true end,
        function(value) SetPriorityOption(ctx, "enabled", value == true, "Enable Priority Frames") end,
        PriorityMeta(ctx, "overview.enabled", "gf_priority.enabled"))
    local editMode = T.Button(overview, Tr("Open Edit Mode"), 146, 26)
    editMode:SetPoint("TOPRIGHT", overview, "TOPRIGHT", -22, -40)
    if T.CenterButtonLabel then T.CenterButtonLabel(editMode) end
    editMode:SetScript("OnClick", OpenPriorityEditModeWithFeedback)
    RegisterAction(editMode, ctx, "overview.open_edit_mode", "Open Priority Frames in Edit Mode", {
        actionKey = "assistant.action.editMode.enter",
        actionFixedArgs = { unit = "gf_priority" },
    })
    local liveStatus = W.Text(overview, "", 24, -132, overviewW - 48, T.colors.accent)
    local behavior = W.Text(overview,
        "Profile-wide layout · character-specific pins · available in parties and raids · inherits the active group-frame appearance and click-cast behavior.",
        24, -166, overviewW - 48, T.colors.muted)
    if behavior.SetWordWrap then behavior:SetWordWrap(true) end
    local function RefreshOverview()
        local state = stateScratch
        local enabled = state.enabled == true
        local active = tonumber(state.activeCount) or 0
        local pins = tonumber(state.pinCount) or 0
        local inGroup = state.inGroup == true
        local inParty = state.inParty == true
        editMode:SetText(Tr(enabled and "Open Edit Mode" or "Preview in Edit Mode"))
        if enabled and inGroup and state.baseFramesEnabled == false then
            liveStatus:SetText(Tr(inParty and "Waiting — enable Party frames first."
                or "Waiting — enable the active Raid or Mythic Raid frames first."))
        elseif enabled and inGroup and active > 0 then
            liveStatus:SetText(M.Format("Active now: %d / %d", active, tonumber(state.maxFrames) or 5))
        elseif enabled and inGroup and pins > 0 then
            liveStatus:SetText(Tr("Waiting — none of your saved players are in the current group."))
        elseif enabled and inGroup then
            liveStatus:SetText(Tr("Ready — pin a group member or include tanks automatically."))
        elseif enabled then
            liveStatus:SetText(Tr("Ready — join a party or raid to show Priority Frames."))
        else
            liveStatus:SetText(Tr("Disabled — your manual pins stay saved."))
        end
        SetSectionBadgesAndStatus(overview, {
            OnOffBadge(enabled, "Enabled", "Disabled"),
            { text = BadgeNumber(active) .. " " .. Tr("visible"), kind = active > 0 and "accent" or "muted" },
            { text = BadgeNumber(pins) .. " " .. Tr("pinned"), kind = pins > 0 and "info" or "muted" },
            { text = Tr(inParty and "In party" or (state.inRaid == true and "In raid" or "Not grouped")),
              kind = inGroup and "ok" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, overview, RefreshOverview)

    local who = b:CollapsibleSection("who_appears", "Who Appears", 548, true)
    local whoW = who._msuf2Width or b.width or 720
    local autoTanks = W.SwitchAt(who, "Include tanks automatically", 24, -52, 330)
    M.BindBoolWidget(ctx, autoTanks,
        function() return PriorityConf().autoTanks == true end,
        function(value) SetPriorityOption(ctx, "autoTanks", value == true, "Priority Frames automatic tanks") end,
        PriorityMeta(ctx, "selection.auto_tanks", "gf_priority.autoTanks"))
    local slots = W.Segment(who, "Visible slots", SLOT_VALUES, 300)
    W.MoveWidget(slots, who, max(380, whoW - 320), -30, 292, "LEFT")
    M.BindSegment(ctx, slots,
        function() return floor((tonumber(PriorityConf().maxFrames) or 5) + 0.5) end,
        function(value) SetPriorityOption(ctx, "maxFrames", tonumber(value) or 5, "Priority Frames visible slots") end,
        PriorityMeta(ctx, "selection.max_frames", "gf_priority.maxFrames"))

    local bindingCard = W.ControlCard(who, "Fast pinning", nil, 20, -106, whoW - 40, 112)
    BuildBindingCapture(ctx, bindingCard, 16, -42, whoW - 72)

    local pinsCard = W.ControlCard(who, "Manual pins", nil, 20, -232, whoW - 40, 246)
    local pinsCardW = whoW - 40
    local pinsStatus = W.Text(pinsCard, "", 16, -42, pinsCardW - 260, T.colors.muted)
    local prevPage = T.Button(pinsCard, Tr("Previous"), 72, 22)
    local nextPage = T.Button(pinsCard, Tr("Next"), 58, 22)
    local pageText = T.Font(pinsCard, "GameFontDisableSmall", "", T.colors.dim)
    nextPage:SetPoint("TOPRIGHT", pinsCard, "TOPRIGHT", -16, -36)
    pageText:SetPoint("RIGHT", nextPage, "LEFT", -8, 0)
    prevPage:SetPoint("RIGHT", pageText, "LEFT", -8, 0)
    if T.CenterButtonLabel then T.CenterButtonLabel(prevPage); T.CenterButtonLabel(nextPage) end
    RegisterAction(prevPage, ctx, "pins.page.previous", "Previous pinned players")
    RegisterAction(nextPage, ctx, "pins.page.next", "Next pinned players")
    local emptyPins = W.Text(pinsCard,
        "No manual pins yet. While grouped, hover an MSUF Party, Raid, or Priority frame, then press your hotkey.",
        18, -104, pinsCardW - 36, T.colors.muted)
    if emptyPins.SetWordWrap then emptyPins:SetWordWrap(true) end

    local pinRows = {}
    for i = 1, PIN_ROWS_PER_PAGE do
        local row = T.Panel(pinsCard, nil, { 0.018, 0.032, 0.064, 0.78 }, T.colors.borderSoft)
        row:SetPoint("TOPLEFT", pinsCard, "TOPLEFT", 16, -66 - ((i - 1) * 30))
        row:SetPoint("TOPRIGHT", pinsCard, "TOPRIGHT", -16, -66 - ((i - 1) * 30))
        row:SetHeight(26)
        local number = T.Font(row, "GameFontNormalSmall", tostring(i), T.colors.dim)
        number:SetPoint("LEFT", row, "LEFT", 8, 0)
        number:SetWidth(22)
        local name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        name:SetPoint("LEFT", number, "RIGHT", 4, 0)
        name:SetWidth(max(150, pinsCardW - 330))
        name:SetJustifyH("LEFT")
        local status = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
        status:SetPoint("RIGHT", row, "RIGHT", -176, 0)
        status:SetWidth(130)
        status:SetJustifyH("RIGHT")
        local up = T.Button(row, Tr("Up"), 42, 20)
        local down = T.Button(row, Tr("Down"), 48, 20)
        local remove = T.Button(row, Tr("Remove"), 68, 20)
        remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        down:SetPoint("RIGHT", remove, "LEFT", -4, 0)
        up:SetPoint("RIGHT", down, "LEFT", -4, 0)
        if T.CenterButtonLabel then T.CenterButtonLabel(up); T.CenterButtonLabel(down); T.CenterButtonLabel(remove) end
        RegisterAction(up, ctx, "pins.row." .. i .. ".up", "Move pinned player up")
        RegisterAction(down, ctx, "pins.row." .. i .. ".down", "Move pinned player down")
        RegisterAction(remove, ctx, "pins.row." .. i .. ".remove", "Remove pinned player")
        pinRows[i] = { frame = row, number = number, name = name, status = status, up = up, down = down, remove = remove }
    end

    local clearPins = (W.RoleButton and W.RoleButton(who, Tr("Clear all"), "danger", 92, 24)) or T.Button(who, Tr("Clear all"), 92, 24)
    clearPins:SetPoint("TOPLEFT", who, "TOPLEFT", 24, -500)
    if T.CenterButtonLabel then T.CenterButtonLabel(clearPins) end
    RegisterAction(clearPins, ctx, "pins.clear_all", "Clear all Priority Frame pins")
    local hotkeyHint = W.Text(who, "Use the hover hotkey above to add or remove players.", 124, -503, whoW - 164, T.colors.muted)
    if hotkeyHint.SetWordWrap then hotkeyHint:SetWordWrap(true) end

    local pinPage = tonumber(M.gfPriorityPinPage) or 1
    local function SetPinPage(value)
        pinPage = max(1, floor((tonumber(value) or 1) + 0.5))
        M.gfPriorityPinPage = pinPage
        RequestPageRefresh(ctx, "priority-pin-page")
    end
    prevPage:SetScript("OnClick", function() SetPinPage(pinPage - 1) end)
    nextPage:SetScript("OnClick", function() SetPinPage(pinPage + 1) end)
    local function RefreshPins()
        local entries = pinViewScratch
        local count = #entries
        local pages = max(1, math.ceil(count / PIN_ROWS_PER_PAGE))
        if pinPage > pages then pinPage = pages; M.gfPriorityPinPage = pinPage end
        local first = (pinPage - 1) * PIN_ROWS_PER_PAGE + 1
        pinsStatus:SetText(count == 1 and Tr("1 saved player") or (tostring(count) .. " " .. Tr("saved players")))
        pageText:SetText(tostring(pinPage) .. " / " .. tostring(pages))
        prevPage:SetShown(pages > 1)
        nextPage:SetShown(pages > 1)
        pageText:SetShown(pages > 1)
        W.SetControlEnabled(prevPage, pinPage > 1)
        W.SetControlEnabled(nextPage, pinPage < pages)
        emptyPins:SetShown(count == 0)
        W.SetControlEnabled(clearPins, count > 0)
        for slot = 1, PIN_ROWS_PER_PAGE do
            local row = pinRows[slot]
            local index = first + slot - 1
            local entry = entries[index]
            if entry then
                local active = entry.active == true
                local statusText
                if active and entry.isTank == true and stateScratch.autoTanks == true then
                    statusText = Tr("Visible · auto tank")
                elseif active then
                    statusText = Tr("Visible")
                elseif entry.waitingReason == "CAPACITY" then
                    statusText = Tr("Saved · slots full")
                elseif entry.waitingReason == "NOT_IN_GROUP" then
                    statusText = Tr("Saved · not grouped")
                elseif entry.waitingReason == "NOT_PRESENT" then
                    statusText = Tr("Saved · not in current group")
                elseif entry.waitingReason == "GROUP_FRAMES_DISABLED" then
                    statusText = Tr(stateScratch.inParty == true and "Saved · Party frames disabled"
                        or "Saved · Raid frames disabled")
                elseif entry.waitingReason == "DISABLED" then
                    statusText = Tr("Saved · Priority Frames disabled")
                else
                    statusText = Tr("Saved")
                end
                row.number:SetText(tostring(index))
                row.name:SetText(entry.name or Tr("Unknown player"))
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
            OnOffBadge(stateScratch.autoTanks == true, "Auto tanks", "Manual only"),
            { text = BadgeNumber(stateScratch.maxFrames or 5) .. " " .. Tr("slots"), kind = "info" },
            { text = BadgeNumber(count) .. " " .. Tr("saved"), kind = count > 0 and "accent" or "muted" },
        })
    end
    for i = 1, PIN_ROWS_PER_PAGE do
        local row = pinRows[i]
        row.up:SetScript("OnClick", function(self)
            local gf = GF()
            if self._pinIndex and gf and type(gf.MovePriorityPin) == "function" and gf.MovePriorityPin(self._pinIndex, -1) then
                RequestPageRefresh(ctx, "priority-pin-up")
            end
        end)
        row.down:SetScript("OnClick", function(self)
            local gf = GF()
            if self._pinIndex and gf and type(gf.MovePriorityPin) == "function" and gf.MovePriorityPin(self._pinIndex, 1) then
                RequestPageRefresh(ctx, "priority-pin-down")
            end
        end)
        row.remove:SetScript("OnClick", function(self)
            local gf = GF()
            if self._pinIndex and gf and type(gf.RemovePriorityPin) == "function" and gf.RemovePriorityPin(self._pinIndex) then
                if type(M.ShowStatusFeedback) == "function" then M.ShowStatusFeedback(Tr("Priority pin removed"), "ok", 1.2) end
                RequestPageRefresh(ctx, "priority-pin-removed")
            end
        end)
    end
    clearPins:SetScript("OnClick", function()
        local gf = GF()
        if not (gf and type(gf.ClearPriorityPins) == "function") then return end
        local function Clear()
            if gf.ClearPriorityPins() then
                SetPinPage(1)
                if type(M.ShowStatusFeedback) == "function" then M.ShowStatusFeedback(Tr("All Priority pins cleared"), "ok", 1.3) end
            end
        end
        EnsureClearPinsPopup()
        if _G.StaticPopup_Show then
            _G.StaticPopup_Show("MSUF2_PRIORITY_CLEAR_PINS", nil, nil, { clear = Clear })
        else
            Clear()
        end
    end)
    TrackSectionRefresh(ctx, who, RefreshPins)

    local placement = b:CollapsibleSection("placement", "Placement", 352, false)
    local placementW = placement._msuf2Width or b.width or 720
    W.Text(placement,
        "Attach the strip to the active Party, Raid, or Mythic Raid container, or choose Free position and place it with Edit Mode.",
        24, -40, placementW - 48, T.colors.muted)
    local place = W.Dropdown(placement, "Placement", PLACEMENT_VALUES, 300)
    W.MoveWidget(place, placement, 24, -80, 300, "LEFT")
    M.BindDropdownWidget(ctx, place,
        function() return PriorityConf().anchorMode or "RAID_RIGHT" end,
        function(value) SetPriorityOption(ctx, "anchorMode", value or "RAID_RIGHT", "Priority Frames placement") end,
        PriorityMeta(ctx, "placement.mode", "gf_priority.anchorMode"))
    local growth = W.Segment(placement, "Growth", GROWTH_VALUES, 318)
    W.MoveWidget(growth, placement, max(360, placementW - 342), -80, 318, "LEFT")
    M.BindSegment(ctx, growth,
        function() return PriorityConf().growth or "DOWN" end,
        function(value) SetPriorityOption(ctx, "growth", value or "DOWN", "Priority Frames growth") end,
        PriorityMeta(ctx, "placement.growth", "gf_priority.growth"))
    local spacing = W.Slider(placement, "Frame spacing", 0, 40, 1, 300)
    W.MoveWidget(spacing, placement, 24, -156, 300, "LEFT")
    M.BindNumberWidget(ctx, spacing,
        function() return tonumber(PriorityConf().spacing) or 2 end,
        function(value) SetPriorityOption(ctx, "spacing", floor((tonumber(value) or 2) + 0.5), "Priority Frames spacing") end,
        2, M.Assign(PriorityMeta(ctx, "placement.spacing", "gf_priority.spacing"), { step = 1, roundStep = true }))
    local attachGap = W.Slider(placement, "Attachment gap", 0, 100, 1, 300)
    W.MoveWidget(attachGap, placement, max(360, placementW - 342), -156, 300, "LEFT")
    M.BindNumberWidget(ctx, attachGap,
        function() return tonumber(PriorityConf().attachGap) or 8 end,
        function(value) SetPriorityOption(ctx, "attachGap", floor((tonumber(value) or 8) + 0.5), "Priority Frames attachment gap") end,
        8, M.Assign(PriorityMeta(ctx, "placement.attach_gap", "gf_priority.attachGap"), { step = 1, roundStep = true }))
    local attachOffset = W.Slider(placement, "Alignment offset", -200, 200, 1, 300)
    W.MoveWidget(attachOffset, placement, 24, -230, 300, "LEFT")
    M.BindNumberWidget(ctx, attachOffset,
        function() return tonumber(PriorityConf().attachOffset) or 0 end,
        function(value) SetPriorityOption(ctx, "attachOffset", floor((tonumber(value) or 0) + 0.5), "Priority Frames alignment offset") end,
        0, M.Assign(PriorityMeta(ctx, "placement.attach_offset", "gf_priority.attachOffset"), { step = 1, roundStep = true }))
    local move = T.Button(placement, Tr("Position in Edit Mode"), 172, 26)
    move:SetPoint("TOPLEFT", placement, "TOPLEFT", max(360, placementW - 342), -252)
    if T.CenterButtonLabel then T.CenterButtonLabel(move) end
    move:SetScript("OnClick", OpenPriorityEditModeWithFeedback)
    RegisterAction(move, ctx, "placement.open_edit_mode", "Position Priority Frames in Edit Mode", {
        actionKey = "assistant.action.editMode.enter",
        actionFixedArgs = { unit = "gf_priority" },
    })
    local placementHint = W.Text(placement, "", 24, -308, placementW - 48, T.colors.muted)
    local function RefreshPlacement()
        local conf = PriorityConf()
        local attached = conf.anchorMode ~= "FREE"
        move:SetText(Tr(conf.enabled == true and "Position in Edit Mode" or "Preview position in Edit Mode"))
        W.SetControlEnabled(attachGap, attached)
        W.SetControlEnabled(attachOffset, attached)
        placementHint:SetText(attached and Tr("The strip follows the active Party, Raid, or Mythic Raid container automatically.")
            or Tr("Free position uses the dedicated Priority Frames mover."))
        SetSectionBadgesAndStatus(placement, {
            { text = Tr(attached and "Attached" or "Free"), kind = attached and "info" or "accent" },
            { text = Tr("Growth: ") .. Tr((conf.growth or "DOWN"):sub(1, 1) .. (conf.growth or "DOWN"):sub(2):lower()), kind = "muted" },
            { text = BadgeNumber(conf.spacing or 2) .. " px", kind = "muted" },
        })
    end
    TrackSectionRefresh(ctx, placement, RefreshPlacement)

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

    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(math.abs(b.y) + 42) end
end

M.RegisterPage("gf_priority", { title = "MSUF Priority Frames", build = BuildPriorityPage, version = 1 })

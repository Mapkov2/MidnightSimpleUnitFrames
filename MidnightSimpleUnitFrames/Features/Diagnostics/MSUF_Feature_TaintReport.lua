local _, MSUF = ...
local Client = MSUF.Client
if not Client.IsSupported then return end

local Report = { version = 1 }
MSUF.TaintReport = Report

local LIMIT = 20
local entries = {}
local recording, discarded = false, 0
local listener, window
local IsSecret, InCombat = MSUF.Util.IsSecret, MSUF.Util.InCombat
local L = MSUF.L

local function PublicText(value, limit)
    if IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    if #value <= limit then return value end
    local boundary = limit + 1
    while boundary > 1 do
        local byte = value:byte(boundary)
        if byte < 128 or byte > 191 then break end
        boundary = boundary - 1
    end
    return value:sub(1, boundary - 1)
end

local function Record(_, event, addon, action)
    if not recording then return end
    addon = PublicText(addon, 160) or "(unavailable)"
    action = PublicText(action, 320) or "(unavailable)"
    local now = date("%Y-%m-%d %H:%M:%S")
    local combat = InCombat()
    local previous = entries[#entries]
    if previous and previous.event == event and previous.addon == addon
        and previous.action == action and previous.combat == combat then
        previous.count = previous.count + 1
        previous.last = now
        return
    end

    local stack = PublicText(debugstack(2, 10, 0), 1600)
    if #entries == LIMIT then
        discarded = discarded + table.remove(entries, 1).count
    end
    entries[#entries + 1] = {
        event = event, addon = addon, action = action, combat = combat,
        first = now, last = now, count = 1, stack = stack,
    }
end

local function Start()
    if not listener then
        listener = CreateFrame("Frame")
        listener:SetScript("OnEvent", Record)
    end
    for index = #entries, 1, -1 do entries[index] = nil end
    discarded = 0
    recording = true
    listener:RegisterEvent("ADDON_ACTION_BLOCKED")
    listener:RegisterEvent("ADDON_ACTION_FORBIDDEN")
end

local function BuildText()
    local version, build = GetBuildInfo()
    local flavor = Client.IsForever and "WoW Forever" or Client.Flavor
    local lines = {
        "MSUF Taint Report",
        ("Client: %s %s (build %s, interface %s)"):format(flavor, version, build, tostring(Client.Interface)),
        "MSUF: " .. (MSUF.GetAddonVersion() or "unknown"),
        "Times are local. Addon attribution is supplied by WoW at the block.",
        "Capture lasts until stopped or the UI reloads.",
    }
    if #entries == 0 then lines[#lines + 1] = "No blocked actions recorded." end
    if discarded > 0 then lines[#lines + 1] = ("Older occurrences omitted: %d"):format(discarded) end
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("%s  %s  (%d occurrence(s))"):format(entry.first, entry.event, entry.count)
        if entry.count > 1 then lines[#lines + 1] = "Last occurrence: " .. entry.last end
        lines[#lines + 1] = "Reported addon: " .. entry.addon
        lines[#lines + 1] = "Protected action: " .. entry.action
        lines[#lines + 1] = "Combat lockdown: " .. (entry.combat and "yes" or "no")
        if entry.stack then lines[#lines + 1] = "Stack at first event:\n" .. entry.stack end
    end
    return table.concat(lines, "\n")
end

local function Refresh(selectText)
    window.toggle:SetText(L[recording and "Stop recording" or "Start new recording"])
    window.status:SetText(L[recording and "Recording blocked actions." or "Recording is off."])
    window.text = BuildText()
    local edit = window.edit
    edit:SetText(window.text)
    edit:SetCursorPosition(0)
    window.scroll:SetVerticalScroll(0)
    if selectText then
        edit:SetFocus()
        edit:HighlightText()
    end
end

function Report.Stop()
    if not recording then return end
    recording = false
    listener:UnregisterAllEvents()
    if window and window:IsShown() then Refresh(false) end
end

local function Button(parent, label, width, click)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(label)
    button:SetScript("OnClick", click)
    return button
end

local function CreateWindow()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetSize(640, 396)
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.06, 0.07, 0.09, 0.98)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L["Taint Report"])
    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.status:SetPoint("TOPLEFT", 16, -42)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -67)
    scroll:SetPoint("BOTTOMRIGHT", -35, 72)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetMaxBytes(0)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetSize(589, 24)
    edit:SetScript("OnEscapePressed", function() panel:Hide() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(panel.text) end
    end)
    scroll:SetScrollChild(edit)
    panel.scroll, panel.edit = scroll, edit
    panel:SetScript("OnHide", function() edit:ClearFocus() end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 46)
    hint:SetText(L["Press Ctrl+C to copy:"])
    panel.toggle = Button(panel, "", 235, function()
        if recording then
            Report.Stop()
        else
            Start()
            Refresh(false)
        end
    end)
    panel.toggle:SetPoint("BOTTOMLEFT", 16, 14)
    local copy = Button(panel, L["Copy report"], 190, function() Refresh(true) end)
    copy:SetPoint("LEFT", panel.toggle, "RIGHT", 8, 0)
    local close = Button(panel, L["Close"], 90, function() panel:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    return panel
end

function Report.Show()
    if InCombat() then
        print(L["Open the Taint Report outside combat."])
        return
    end
    if not window then window = CreateWindow() end
    window:Show()
    Refresh(false)
end

MSUF.SlashCommands.Register({
    name = "taint",
    group = "diagnostics",
    usage = "/msuf taint",
    help = "Open the copyable report for blocked addon actions.",
    run = Report.Show,
})

-- Profiles page: delete several profiles at once. The popup lists the whole
-- account-wide pool with what still uses each profile. One confirmation then
-- runs MSUF_DeleteProfiles, which takes every name through the same path as
-- "Delete current profile" (character bindings, spec maps, the new-character
-- default, sync groups, the Suite) and prints one chat summary.
local _, MSUF = ...
local M = MSUF.MSUF2
M.RequireGlobals("Shell/Menu2/Pages/MSUF_Menu2_ProfileCleanup.lua", {
    "MSUF_GetAllProfiles",
    "MSUF_GetDefaultProfileForNewCharacters",
    "MSUF_DeleteProfiles",
})
local T = M.Theme
local max = math.max
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...)
    if type(policy) == "string" then return region[policy](region, ...) end
    return region
end

local Cleanup = {}
M.ProfileCleanup = Cleanup

local POPUP_W, POPUP_H = 560, 460
local ROW_H, ROW_STEP = 26, 30
local LIST_TOP, LIST_BOTTOM = -88, 52
local USAGE_W = 230
local SHOWN_NAMES = 8
-- Every deleted profile's characters move to "Default", so it is never offered
-- (State/MSUF_Profiles.lua refuses it as well). The active profile keeps its
-- own action, "Delete current profile", which also switches this character.
local PROTECTED = "Default"

local popup, onChanged
local selected, names, rows = {}, {}, {}

-- What still points at each profile: characters bound to it, a spec mapping,
-- the account's choice for new characters, or a profile synchronization group.
local function ProfileUsage()
    local usage = {}
    local function Entry(name)
        local entry = usage[name]
        if not entry then
            entry = { characters = 0 }
            usage[name] = entry
        end
        return entry
    end
    local gdb = _G.MSUF_GlobalDB
    local chars = type(gdb) == "table" and type(gdb.char) == "table" and gdb.char or {}
    for _, char in pairs(chars) do
        if type(char) == "table" then
            if type(char.activeProfile) == "string" then
                local entry = Entry(char.activeProfile)
                entry.characters = entry.characters + 1
            end
            local specMap = type(char.specProfileMap) == "table" and char.specProfileMap or {}
            for _, name in pairs(specMap) do
                if type(name) == "string" then Entry(name).spec = true end
            end
        end
    end
    local newCharacters = _G.MSUF_GetDefaultProfileForNewCharacters()
    if newCharacters then Entry(newCharacters).newCharacters = true end
    local meta = type(gdb) == "table" and type(gdb.global) == "table" and gdb.global or {}
    local groups = type(meta.profileSyncGroups) == "table" and meta.profileSyncGroups or {}
    for _, group in pairs(groups) do
        local members = type(group) == "table" and type(group.members) == "table" and group.members or {}
        for name, enabled in pairs(members) do
            if enabled == true and type(name) == "string" then Entry(name).sync = true end
        end
    end
    return usage
end

local function IsLocked(name, active)
    return name == active or name == PROTECTED
end

local function UsageText(name, entry, active)
    if name == active then return M.Tr("Active") end
    if name == PROTECTED then return M.Tr("Protected") end
    if not entry then return M.Tr("Unused") end
    if entry.characters == 1 then return M.Tr("Used by 1 character") end
    if entry.characters > 1 then return M.Format("Used by %d characters", entry.characters) end
    if entry.spec then return M.Tr("Spec profile") end
    if entry.newCharacters then return M.Tr("New-character default") end
    return M.Tr("Sync group")
end

local function SelectedNames()
    local out = {}
    for i = 1, #names do
        if selected[names[i]] then out[#out + 1] = names[i] end
    end
    return out
end

-- The count is written to the label directly: Button:SetText would register
-- every count as a menu search entry.
local function RefreshFooter()
    local count = #SelectedNames()
    T.SetTranslatedText(popup._deleteBtn._msuf2Label, M.Format("Delete selected (%d)", count))
    popup._deleteBtn:SetEnabled(count > 0)
end

local function ToggleRow(row)
    local name = row._msuf2ProfileName
    if not name or row._msuf2Locked then return end
    selected[name] = not selected[name] or nil
    row:SetActive(selected[name] == true)
    RefreshFooter()
end

local function EnsureRow(index)
    local row = rows[index]
    if row then return row end
    local content = popup._content
    row = T.Button(content, "", content:GetWidth(), ROW_H, { noSearch = true, history = false })
    row._msuf2SkipHistoryCheckpoint = true
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_STEP)
    local label = row._msuf2Label
    label:ClearAllPoints()
    label:SetPoint("LEFT", row, "LEFT", 12, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -(USAGE_W + 16), 0)
    if label.SetWordWrap then label:SetWordWrap(false) end
    local usage = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
    usage:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    usage:SetWidth(USAGE_W)
    usage:SetJustifyH("RIGHT")
    row._msuf2Usage = usage
    row:SetScript("OnClick", ToggleRow)
    rows[index] = row
    return row
end

-- Rebuilds the list from the stored profiles. Names are shown as typed, never
-- translated; a selection survives only while its profile can still be deleted.
local function RefreshRows()
    local active = _G.MSUF_ActiveProfile or PROTECTED
    local usage = ProfileUsage()
    names = _G.MSUF_GetAllProfiles() or {}
    local present = {}
    for i = 1, #names do
        local name = names[i]
        local locked = IsLocked(name, active)
        present[name] = true
        if locked then selected[name] = nil end
        local row = EnsureRow(i)
        row._msuf2ProfileName, row._msuf2Locked = name, locked
        T.SetTranslatedText(row._msuf2Label, name)
        T.SetTranslatedText(row._msuf2Usage, UsageText(name, usage[name], active))
        row:SetEnabled(not locked)
        row:SetActive(selected[name] == true)
        row:Show()
    end
    for name in pairs(selected) do
        if not present[name] then selected[name] = nil end
    end
    for i = #names + 1, #rows do rows[i]:Hide() end
    popup._content:SetHeight(max(1, #names * ROW_STEP))
    RefreshFooter()
end

local function SelectUnused()
    local active = _G.MSUF_ActiveProfile or PROTECTED
    local usage = ProfileUsage()
    for i = 1, #names do
        local name = names[i]
        if not IsLocked(name, active) and not usage[name] then selected[name] = true end
    end
    RefreshRows()
end

local function ClearSelection()
    for name in pairs(selected) do selected[name] = nil end
    RefreshRows()
end

local function DeleteSelected(list)
    if M.BlockCombatAction() then return end
    local deleted = _G.MSUF_DeleteProfiles(list)
    for name in pairs(selected) do selected[name] = nil end
    M.ClearHistory()
    if popup:IsShown() then RefreshRows() end
    if onChanged then onChanged() end
    if M.ShowStatusFeedback then M.ShowStatusFeedback(M.Format("Profiles deleted: %d", deleted), "info", 1.8, true) end
end

local function ConfirmDelete()
    if M.BlockCombatAction() then return end
    local list = SelectedNames()
    if #list == 0 then return end
    local shown = {}
    for i = 1, math.min(#list, SHOWN_NAMES) do shown[i] = list[i] end
    local text = table.concat(shown, ", ")
    if #list > SHOWN_NAMES then text = text .. " " .. M.Format("and %d more", #list - SHOWN_NAMES) end
    M.ShowPrompt("MSUF2_CONFIRM_DELETE_PROFILES", {
        text = M.Format(
            "Delete %d selected profiles?\n\n%s\n\nCharacters using them switch to Default. Without an export this cannot be undone.",
            #list, text),
        accept = DELETE or M.Tr("Delete"),
        cancel = CANCEL or M.Tr("Cancel"),
        onAccept = function() DeleteSelected(list) end,
    })
end

local function PopupButton(label, width, role)
    local btn = T.Button(popup, label, width, 24, { noSearch = true, history = false })
    btn._msuf2SkipHistoryCheckpoint = true
    if role then T.ApplyButtonRole(btn, role) end
    T.CenterButtonLabel(btn)
    return btn
end

local function BuildList()
    local scroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, popup))
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -36, LIST_BOTTOM)
    local content = PixelLayoutRegion(CreateFrame("Frame", nil, scroll))
    content:SetSize(POPUP_W - 52, 1)
    scroll:SetScrollChild(content)
    T.StyleScrollFrame(scroll, popup)
    popup._content = content
end

local function BuildPopup()
    popup = M.CreateMenuPopupPanel(UIParent)
    popup:SetSize(POPUP_W, POPUP_H)
    local title = T.Font(popup, "GameFontNormal", "Delete profiles", T.colors.accent)
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -14)
    local help = T.Font(popup, "GameFontDisableSmall",
        "Click profiles to select them. The active profile and Default cannot be deleted here.", T.colors.muted)
    help:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -38)
    help:SetWidth(POPUP_W - 32)
    help:SetJustifyH("LEFT")
    local close = PopupButton("x", 24, "danger")
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -10)
    close:SetScript("OnClick", function() popup:Hide() end)
    BuildList()
    local unused = PopupButton("Select unused", 150)
    unused:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 16, 14)
    unused:SetScript("OnClick", SelectUnused)
    local clear = PopupButton("Clear selection", 150)
    clear:SetPoint("LEFT", unused, "RIGHT", 8, 0)
    clear:SetScript("OnClick", ClearSelection)
    local delete = PopupButton("Delete selected (%d)", 200, "danger")
    delete:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -16, 14)
    delete:SetScript("OnClick", ConfirmDelete)
    popup._deleteBtn = delete
    -- The popup lives on UIParent; it closes with the menu window.
    if M.frame then M.frame:HookScript("OnHide", function() popup:Hide() end) end
end

--- Opens the cleanup list. changed runs after a delete so the page can refresh
--- its profile pickers and counts.
function Cleanup.Open(changed)
    if M.BlockCombatAction() then return end
    onChanged = changed
    if not popup then BuildPopup() end
    RefreshRows()
    M.ApplyPopupFramePriority(popup)
    popup:ClearAllPoints()
    popup:SetPoint("CENTER", M.frame or UIParent, "CENTER", 0, 0)
    popup:Show()
end

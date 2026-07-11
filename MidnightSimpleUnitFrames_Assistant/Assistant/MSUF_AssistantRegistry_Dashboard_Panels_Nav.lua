-- Assistant Dashboard navigation and search-intro workflow helpers.
-- Loaded after MSUF_AssistantRegistry_Dashboard_Panels.lua; actions consume these A.Workflow helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

local NAV_SECTION_LABELS = {
    unitframes = "Frames",
    groupframes = "Group Frames",
    auras = "Auras",
    globalstyle = "Appearance",
    modules = "Advanced",
}

local NAV_SECTION_ALIASES = {
    frames = "unitframes",
    frame = "unitframes",
    unitframe = "unitframes",
    unitframes = "unitframes",
    group = "groupframes",
    groups = "groupframes",
    groupframe = "groupframes",
    groupframes = "groupframes",
    raidframes = "groupframes",
    partyframes = "groupframes",
    aura = "auras",
    auras = "auras",
    buffs = "auras",
    debuffs = "auras",
    appearance = "globalstyle",
    global = "globalstyle",
    globalstyle = "globalstyle",
    style = "globalstyle",
    look = "globalstyle",
    advanced = "modules",
    module = "modules",
    modules = "modules",
}

local function NormalizeKey(text)
    text = tostring(text or ""):lower()
    text = text:gsub("&", " and ")
    text = text:gsub("[^%w]+", "")
    return text
end

local function ResolveNavSection(section)
    if M and type(M.ResolveNavHeader) == "function" then
        local id, label, item = M.ResolveNavHeader(section)
        if id then return id, NAV_SECTION_LABELS[id] or tostring(id), item end
    end
    local token = NormalizeKey(section)
    local aliasId = NAV_SECTION_ALIASES[token]
    local nav = M and type(M.navItems) == "table" and M.navItems or {}
    for i = 1, #nav do
        local item = nav[i]
        if item and item.header then
            local id = tostring(item.id or item.header)
            if aliasId == id or token == NormalizeKey(id) or token == NormalizeKey(item.header) then
                return id, NAV_SECTION_LABELS[id] or id, item
            end
        end
    end
    if aliasId then return aliasId, NAV_SECTION_LABELS[aliasId] or aliasId, nil end
    return nil
end

local function ReflowNavRail()
    local nav = M and M.nav
    if nav and type(nav._msuf2NavReflow) == "function" then
        nav:_msuf2NavReflow()
        return true
    end
    local frame = M and M.frame
    nav = frame and (frame.nav or frame._msufNavRail or frame._msufNavStack)
    if nav and type(nav._msuf2NavReflow) == "function" then
        nav:_msuf2NavReflow()
        return true
    end
    return false
end

local function PersistSearchIntroSeen(seen)
    seen = seen and true or false
    if M and type(M.SetSearchIntroSeen) == "function" then
        M.SetSearchIntroSeen(seen)
    elseif M and type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("searchIntroSeen", seen)
    elseif M then
        M.searchIntroSeen = seen
    end
end

function A.Workflow.SetNavSection(section, open)
    if M and type(M.SetNavHeaderOpen) == "function" then
        local ok, message, state, resolvedId = M.SetNavHeaderOpen(section, open)
        if not ok then return ok, message end
        if not resolvedId then resolvedId = select(1, ResolveNavSection(section)) end
        if state == nil and resolvedId and type(M.navHeaderState) == "table" then
            state = M.navHeaderState[resolvedId]
        end
        if state == nil then state = open ~= false end
        return true, (state and "Opened " or "Closed ") .. tostring(NAV_SECTION_LABELS[resolvedId] or resolvedId or section) .. " navigation section."
    end
    local id, label, item = ResolveNavSection(section)
    if not id then return false, "Which navigation section do you want me to open?" end
    if M and type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    if not M then return false, "Open the MSUF menu first so I can navigate the Dashboard." end
    M.navHeaderState = type(M.navHeaderState) == "table" and M.navHeaderState or {}
    if M.navHeaderState[id] == nil then
        M.navHeaderState[id] = not (item and item.defaultOpen == false)
    end
    if open == nil then
        open = not M.navHeaderState[id]
    else
        open = open and true or false
    end
    M.navHeaderState[id] = open
    ReflowNavRail()
    return true, (open and "Opened " or "Closed ") .. tostring(label or id) .. " navigation section."
end

function A.Workflow.SetNavSearchIntro(command)
    command = tostring(command or "show")
    if command == "hide" or command == "seen" then
        PersistSearchIntroSeen(true)
        if M and type(M.HideNavSearchIntro) == "function" then M.HideNavSearchIntro() end
        return true, "Search intro is marked seen."
    end
    if command == "reset" then
        PersistSearchIntroSeen(false)
        return true, "Search intro will show again the next time the search box is focused."
    end
    if command == "show" then
        PersistSearchIntroSeen(false)
        if M and type(M.ShowNavSearchIntro) == "function" then
            M.ShowNavSearchIntro()
            return true, "Shown the search intro."
        end
        return true, "Search intro will show the next time the search box is focused."
    end
    return false, "Which search intro do you want me to open?"
end

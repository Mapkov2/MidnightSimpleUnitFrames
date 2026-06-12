local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (Registry and type(Registry.RegisterAction) == "function") then return end

A.Workflow = A.Workflow or {}

local function ActiveProfileName()
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

function A.Workflow.DashboardState()
    _G.MSUF_GlobalDB = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {}
    _G.MSUF_GlobalDB.global = type(_G.MSUF_GlobalDB.global) == "table" and _G.MSUF_GlobalDB.global or {}
    _G.MSUF_GlobalDB.global.dashboard = type(_G.MSUF_GlobalDB.global.dashboard) == "table" and _G.MSUF_GlobalDB.global.dashboard or {}
    return _G.MSUF_GlobalDB.global.dashboard
end

function A.Workflow.SetWagoBackupConfirmed(confirmed)
    local dash = A.Workflow.DashboardState()
    dash.wagoProfileBackupConfirmed = type(dash.wagoProfileBackupConfirmed) == "table" and dash.wagoProfileBackupConfirmed or {}
    if confirmed == true then
        dash.wagoProfileBackupConfirmed[ActiveProfileName()] = true
    else
        dash.wagoProfileBackupConfirmed[ActiveProfileName()] = nil
    end
    if M and type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if M and type(M.SelectPage) == "function" then M.SelectPage("home") end
    return true
end

local DASHBOARD_PANEL_FIELDS = {
    recovery = { field = "dashboardRecoveryOpen", label = "Dashboard recovery tools" },
    scaling = { field = "dashboardScalingOpen", label = "Dashboard scaling tools" },
    changelog = { field = "dashboardChangelogOpen", label = "Dashboard changelog" },
}

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
        if id then return id, label, item end
    end
    local token = NormalizeKey(section)
    local aliasId = NAV_SECTION_ALIASES[token]
    local nav = M and type(M.navItems) == "table" and M.navItems or {}
    for i = 1, #nav do
        local item = nav[i]
        if item and item.header then
            local id = tostring(item.id or item.header)
            if aliasId == id or token == NormalizeKey(id) or token == NormalizeKey(item.header) then
                return id, item.header, item
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

function A.Workflow.SetDashboardPanel(panel, open)
    local spec = DASHBOARD_PANEL_FIELDS[tostring(panel or "")]
    if not spec then return false, "I do not know which Dashboard panel to change." end
    if open == nil then
        open = not (M and M[spec.field] == true)
    else
        open = open and true or false
    end
    if M and type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue(spec.field, open)
    elseif M then
        M[spec.field] = open
    end
    if M and type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if M and type(M.Open) == "function" then
        if M.Open("home") == false then return false, "Dashboard navigation is not available right now." end
    elseif M and type(M.SelectPage) == "function" then
        if M.SelectPage("home") == false then return false, "Dashboard navigation is not available right now." end
    else
        return false, "Dashboard navigation is not available right now."
    end
    return true, (open and "Opened " or "Closed ") .. spec.label .. "."
end

function A.Workflow.OpenDashboardPanel(panel)
    return A.Workflow.SetDashboardPanel(panel, true)
end

function A.Workflow.SetNavSection(section, open)
    if M and type(M.SetNavHeaderOpen) == "function" then
        return M.SetNavHeaderOpen(section, open)
    end
    local id, label, item = ResolveNavSection(section)
    if not id then return false, "I do not know that navigation section." end
    if M and type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    if not M then return false, "Dashboard navigation is not available right now." end
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
    return false, "I do not know which search intro action to run."
end

local UNIT_PAGE_KEYS = {
    player = "uf_player",
    target = "uf_target",
    focus = "uf_focus",
    pet = "uf_pet",
    targettarget = "uf_targettarget",
    focustarget = "uf_focustarget",
    boss = "uf_boss",
}

local GROUP_SCOPE_LABELS = {
    party = "Party",
    raid = "Raid",
    mythicraid = "Mythic Raid",
}

local TEXT_TAB_LABELS = {
    name = "Name Text",
    hp = "HP Text",
    power = "Power Text",
    advanced = "Advanced Text",
}

local TEXT_SLOT_LABELS = {
    left = "left",
    center = "center",
    right = "right",
}

local STATUS_TAB_LABELS = {
    basic = "Basic",
    advanced = "Advanced",
}

local PROFILE_EXPORT_KIND_LABELS = {
    all = "Full profile",
    unitframe = "Unitframes",
    castbar = "Castbars",
    colors = "Colors",
    gameplay = "Gameplay",
    groupframe = "Group Frames",
}

local UNIT_COPY_CATEGORY_FALLBACK = {
    { key = "basics", label = "Frame Basics", default = true, aliases = { "frame basics", "basic settings", "basics", "enable state", "smooth fill", "reverse fill" } },
    { key = "text", label = "Text", default = true, aliases = { "text", "name", "hp", "health text", "hp text", "power text", "font", "fonts" } },
    { key = "portrait", label = "Portrait", default = true, aliases = { "portrait", "portrait settings" } },
    { key = "power", label = "Power Bar", default = true, aliases = { "power", "power bar", "powerbar", "detached power", "detached power bar", "resource bar" } },
    { key = "castbar", label = "Castbar", default = true, aliases = { "castbar", "cast bar" } },
    { key = "status", label = "Status Icons", default = true, aliases = { "status", "status icon", "status icons", "status indicator", "status indicators", "indicator", "indicators", "level indicator", "raid marker", "pvp flag", "pvp indicator" } },
    { key = "load", label = "Load Conditions", default = true, aliases = { "load", "load condition", "load conditions", "hide mounted", "hide out of combat" } },
    { key = "transparency", label = "Transparency", default = true, aliases = { "transparency", "opacity", "alpha", "range fade" } },
    { key = "layout", label = "Size & Anchoring", default = false, aliases = { "layout", "position", "size", "anchoring", "anchor", "width", "height" } },
}

local GROUP_COPY_CATEGORY_FALLBACK = {
    { key = "general", label = "Basics", aliases = { "general", "basics", "basic", "layout", "size", "spacing", "growth", "sort", "sorting" } },
    { key = "health", label = "Health & Bars", aliases = { "health", "health bars", "bars", "power", "power bar", "dispel overlay" } },
    { key = "text", label = "Text & Name", aliases = { "text", "name", "health text", "hp text", "text and name" } },
    { key = "font", label = "Font Override", aliases = { "font", "fonts", "font override", "font color", "font outline" } },
    { key = "border", label = "Background & Opacity", aliases = { "background", "opacity", "alpha", "transparency", "background opacity" } },
    { key = "range", label = "Range Fade", aliases = { "range", "range fade", "offline alpha" } },
    { key = "indicators", label = "Indicators & Status Icons", aliases = { "indicators", "status icons", "status icon", "role icon", "leader icon", "assist icon", "raid marker", "pvp flag", "pvp indicator" } },
    { key = "auras", label = "Auras", aliases = { "auras", "aura", "buffs", "debuffs" } },
    { key = "highlight", label = "Highlight & Aggro", aliases = { "highlight", "aggro", "dispel border", "purge border" } },
    { key = "dstripe", label = "Debuff Stripe", aliases = { "debuff stripe", "stripe" } },
    { key = "features", label = "Corner/Spell", aliases = { "corner", "corner indicator", "corner indicators", "spell indicator", "spell indicators", "corner spell" } },
}

local GROUP_STATUS_ICON_SPECS = {
    roleIcon = "Role Icon",
    leaderIcon = "Leader Icon",
    assistIcon = "Assist Icon",
    raidMarker = "Raid Marker",
    readyCheckIcon = "Ready Check Icon",
    summonIcon = "Summon Icon",
    resurrectIcon = "Resurrection Icon",
    pvpIcon = "PvP Flag Icon",
    phaseIcon = "Phase Icon",
    statusText = "Dead Text",
    statusGhostText = "Ghost Text",
    statusAFKText = "AFK Text",
}

local GROUP_STATUS_ICON_ALIASES = {
    roleicon = "roleIcon",
    roleindicator = "roleIcon",
    leadericon = "leaderIcon",
    leaderindicator = "leaderIcon",
    assisticon = "assistIcon",
    assistanticon = "assistIcon",
    assistindicator = "assistIcon",
    raidmarker = "raidMarker",
    targetmarker = "raidMarker",
    readycheck = "readyCheckIcon",
    readycheckicon = "readyCheckIcon",
    summonicon = "summonIcon",
    summonindicator = "summonIcon",
    resurrecticon = "resurrectIcon",
    resurrectionicon = "resurrectIcon",
    rezicon = "resurrectIcon",
    pvpflag = "pvpIcon",
    pvpicon = "pvpIcon",
    pvpindicator = "pvpIcon",
    pvpstatus = "pvpIcon",
    phaseicon = "phaseIcon",
    phasingicon = "phaseIcon",
    statustext = "statusText",
    deadtext = "statusText",
    ghosttext = "statusGhostText",
    afktext = "statusAFKText",
    dndtext = "statusAFKText",
}

local function UnitLabel(unit)
    return tostring((A.UnitLabels or {})[unit] or unit or "")
end

local function GroupLabel(scope)
    return tostring(GROUP_SCOPE_LABELS[scope] or (A.UnitLabels or {})[scope] or scope or "")
end

local function ResolveUnitKey(unit)
    unit = tostring(unit or "")
    local direct = NormalizeKey(unit)
    for key in pairs(UNIT_PAGE_KEYS) do
        if direct == NormalizeKey(key) then return key end
    end
    local aliases = A.UnitAliases or {}
    for key in pairs(UNIT_PAGE_KEYS) do
        local list = aliases[key] or {}
        for i = 1, #list do
            if direct == NormalizeKey(list[i]) then return key end
        end
    end
    return nil
end

local function ResolveGroupScope(scope)
    scope = tostring(scope or "")
    local key = NormalizeKey(scope)
    if key == "party" or key == "partyframes" or key == "group" or key == "groupframes" then return "party" end
    if key == "raid" or key == "raidframes" then return "raid" end
    if key == "mythicraid" or key == "mythicraidframes" or key == "mythic" then return "mythicraid" end
    local aliases = A.UnitAliases or {}
    for _, candidate in ipairs({ "party", "raid", "mythicraid" }) do
        local list = aliases[candidate] or {}
        for i = 1, #list do
            if key == NormalizeKey(list[i]) then return candidate end
        end
    end
    return nil
end

local function ResolveTextTab(tab)
    tab = NormalizeKey(tab)
    if tab == "health" or tab == "healthtext" then tab = "hp" end
    if tab == "mana" or tab == "manatext" or tab == "powertext" then tab = "power" end
    if tab == "nametext" then tab = "name" end
    if TEXT_TAB_LABELS[tab] then return tab end
    return nil
end

local function ResolveTextSlot(slot)
    slot = NormalizeKey(slot)
    if slot == "centre" or slot == "middle" then slot = "center" end
    if TEXT_SLOT_LABELS[slot] then return slot end
    return nil
end

local function ResolveStatusTab(tab)
    tab = NormalizeKey(tab)
    if STATUS_TAB_LABELS[tab] then return tab end
    return nil
end

local function ResolveProfileExportKind(kind)
    local workflow = A and A.ProfileWorkflow
    if workflow and type(workflow.ExportKind) == "function" then
        local resolved = workflow.ExportKind(kind)
        if PROFILE_EXPORT_KIND_LABELS[resolved] then return resolved, PROFILE_EXPORT_KIND_LABELS[resolved] end
    end
    kind = tostring(kind or "all"):lower()
    if kind == "full" or kind == "profile" then kind = "all" end
    if kind == "unitframes" or kind == "unit frame" or kind == "unit frames" then kind = "unitframe" end
    if kind == "castbars" or kind == "cast bar" or kind == "cast bars" then kind = "castbar" end
    if kind == "color" then kind = "colors" end
    if kind == "group" or kind == "groupframes" or kind == "group frame" or kind == "group frames" then kind = "groupframe" end
    if PROFILE_EXPORT_KIND_LABELS[kind] then return kind, PROFILE_EXPORT_KIND_LABELS[kind] end
    return "all", PROFILE_EXPORT_KIND_LABELS.all
end

local function UnitCopyCategories()
    local cats = M and M.UnitPage and type(M.UnitPage.UF_COPY_CATEGORIES) == "table" and M.UnitPage.UF_COPY_CATEGORIES or nil
    if cats and #cats > 0 then return cats end
    return UNIT_COPY_CATEGORY_FALLBACK
end

local function EnsureUnitCopyScopes()
    M.unitCopyScopes = type(M.unitCopyScopes) == "table" and M.unitCopyScopes or {}
    local cats = UnitCopyCategories()
    for i = 1, #cats do
        local cat = cats[i]
        local key = cat and cat.key
        if type(key) == "string" and M.unitCopyScopes[key] == nil then
            local defaultValue = cat.default
            if defaultValue == nil then
                for j = 1, #UNIT_COPY_CATEGORY_FALLBACK do
                    if UNIT_COPY_CATEGORY_FALLBACK[j].key == key then
                        defaultValue = UNIT_COPY_CATEGORY_FALLBACK[j].default
                        break
                    end
                end
            end
            M.unitCopyScopes[key] = defaultValue ~= false
        end
    end
    return M.unitCopyScopes, cats
end

local function UnitCopyFallbackSpec(key)
    for i = 1, #UNIT_COPY_CATEGORY_FALLBACK do
        local spec = UNIT_COPY_CATEGORY_FALLBACK[i]
        if spec.key == key then return spec end
    end
    return nil
end

local function ResolveUnitCopyCategory(category)
    local needle = NormalizeKey(category)
    if needle == "" then return nil end
    local cats = UnitCopyCategories()
    for i = 1, #cats do
        local cat = cats[i]
        local key = cat and cat.key
        local fallback = UnitCopyFallbackSpec(key)
        local label = cat and cat.label or fallback and fallback.label
        if key and (needle == NormalizeKey(key) or needle == NormalizeKey(label)) then return key, label or key end
        local aliases = cat and cat.aliases or fallback and fallback.aliases
        for j = 1, #(aliases or {}) do
            if needle == NormalizeKey(aliases[j]) then return key, label or key end
        end
    end
    return nil
end

local function GroupCopyCategories()
    local cats = M and M.GroupPage and type(M.GroupPage.GF_COPY_CATEGORIES) == "table" and M.GroupPage.GF_COPY_CATEGORIES or nil
    if cats and #cats > 0 then return cats end
    return GROUP_COPY_CATEGORY_FALLBACK
end

local function EnsureGroupCopyScopes()
    M.gfCopyScopes = type(M.gfCopyScopes) == "table" and M.gfCopyScopes or {}
    local cats = GroupCopyCategories()
    for i = 1, #cats do
        local key = cats[i] and cats[i].key
        if type(key) == "string" and M.gfCopyScopes[key] == nil then M.gfCopyScopes[key] = true end
    end
    return M.gfCopyScopes, cats
end

local function ResolveGroupCopyCategory(category)
    local needle = NormalizeKey(category)
    if needle == "" then return nil end
    local cats = GroupCopyCategories()
    for i = 1, #cats do
        local cat = cats[i]
        local key = cat and cat.key
        local label = cat and cat.label
        if key and (needle == NormalizeKey(key) or needle == NormalizeKey(label)) then return key, label or key end
        local aliases = cat and cat.aliases
        for j = 1, #(aliases or {}) do
            if needle == NormalizeKey(aliases[j]) then return key, label or key end
        end
    end
    return nil
end

local function ResolveGroupStatusIcon(icon)
    local key = NormalizeKey(icon)
    local canonical = GROUP_STATUS_ICON_ALIASES[key]
    if canonical then return canonical, GROUP_STATUS_ICON_SPECS[canonical] end
    for value, label in pairs(GROUP_STATUS_ICON_SPECS) do
        if key == NormalizeKey(value) or key == NormalizeKey(label) then return value, label end
    end
    return nil
end

local function ResolveToken(tokens, token)
    local key = tostring(token or "")
    local compact = NormalizeKey(key)
    for i = 1, #(tokens or {}) do
        local spec = tokens[i]
        local value = spec and spec.key
        local label = spec and (spec.label or spec.text or value)
        if value and (key == value or compact == NormalizeKey(value) or compact == NormalizeKey(label)) then
            return value, label
        end
    end
    return nil
end

local function EnsureMenuState()
    if M and type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
end

local function PersistScalar(field, value)
    EnsureMenuState()
    if M and type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue(field, value)
    elseif M then
        M[field] = value
    else
        return false
    end
    return true
end

local function PersistentTable(field)
    EnsureMenuState()
    if M and type(M.GetPersistentMenuStateTable) == "function" then
        local target = M.GetPersistentMenuStateTable(field)
        if type(target) == "table" then return target end
    end
    if not M then return nil end
    M[field] = type(M[field]) == "table" and M[field] or {}
    return M[field]
end

local function PersistTableValue(field, key, value)
    local target = PersistentTable(field)
    if type(target) ~= "table" then return false end
    target[key] = value
    return true
end

local function PersistNestedTableValue(field, key1, key2, value)
    local target = PersistentTable(field)
    if type(target) ~= "table" then return false end
    target[key1] = type(target[key1]) == "table" and target[key1] or {}
    target[key1][key2] = value
    return true
end

local function OpenMenuPage(pageKey)
    if pageKey and M and type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
    if M and type(M.Open) == "function" then
        return M.Open(pageKey) ~= false
    end
    if M and type(M.SelectPage) == "function" then
        return M.SelectPage(pageKey) ~= false
    end
    return true
end

local function FocusUnitText(unit, tab, slot)
    if type(_G.MSUF_UFPreview_FocusTextSlot) == "function" then
        _G.MSUF_UFPreview_FocusTextSlot(unit, tab, slot, true)
    end
    if type(_G.MSUF_EM2_SetFocusSelection) == "function" then
        _G.MSUF_EM2_SetFocusSelection(unit, tab, slot, { source = "assistant", clearHover = true })
    end
end

local function FocusGroupText(scope, tab, slot)
    if M and type(M.FocusGFPreviewTextSlot) == "function" then
        M.FocusGFPreviewTextSlot(tab, slot, true)
    end
    if type(_G.MSUF_EM2_SetFocusSelection) == "function" then
        local key = scope == "raid" and "gf_raid" or (scope == "mythicraid" and "gf_mythicraid" or "gf_party")
        _G.MSUF_EM2_SetFocusSelection(key, tab, slot, { source = "assistant", clearHover = true })
    end
end

local function FocusUnitStatus(status)
    if type(_G.MSUF_UFPreview_SelectStatusIcon) == "function" then
        _G.MSUF_UFPreview_SelectStatusIcon(status)
    end
end

local function SelectorBool(value)
    if value == false then return false end
    return true
end

local function CurrentUnitTextSlot(unit, tab)
    local byUnit = M and M.unitTextSlotSelection and M.unitTextSlotSelection[unit]
    local slot = byUnit and byUnit[tab]
    return ResolveTextSlot(slot) or "center"
end

local function CurrentGroupTextSlot(scope, tab)
    local byScope = M and M.gfTextSlotSelection and M.gfTextSlotSelection[scope]
    local slot = byScope and byScope[tab]
    return ResolveTextSlot(slot) or "center"
end

local function RememberSelectedTextTarget(frameType, unitOrScope, tab, slot)
    if tab ~= "hp" and tab ~= "power" then return end
    slot = ResolveTextSlot(slot)
    if not slot then return end
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return end
    ctx.lastTextFrameType = frameType
    ctx.lastTextUnit = unitOrScope
    ctx.lastTextArea = tab
    ctx.lastTextSlot = slot
    ctx.selectedTextEditorTarget = {
        frameType = frameType,
        unit = unitOrScope,
        tab = tab,
        slot = slot,
    }
end

local function SetUnitTextSelector(args)
    local unit = ResolveUnitKey(args and args.unit)
    local tab = ResolveTextTab(args and args.tab)
    local slot = ResolveTextSlot(args and args.slot)
    if not unit then return false, "I do not know which unit text menu to select." end
    if not tab then return false, "I do not know which text tab to select." end
    PersistTableValue("unitTextTabSelection", unit, tab)
    if slot and (tab == "hp" or tab == "power") then PersistNestedTableValue("unitTextSlotSelection", unit, tab, slot) end
    RememberSelectedTextTarget("unitframe", unit, tab, slot)
    FocusUnitText(unit, tab, slot)
    OpenMenuPage(UNIT_PAGE_KEYS[unit])
    return true, "Selected " .. UnitLabel(unit) .. " " .. TEXT_TAB_LABELS[tab] .. (slot and (" " .. TEXT_SLOT_LABELS[slot] .. " slot") or " tab") .. "."
end

local function SetUnitTextMoveTogether(args)
    local unit = ResolveUnitKey(args and args.unit)
    local tab = ResolveTextTab(args and args.tab)
    local value = SelectorBool(args and args.value)
    if not unit then return false, "I do not know which unit text move mode to set." end
    if tab ~= "hp" and tab ~= "power" then return false, "Text move-together mode is only available for HP and Power text." end
    M.unitTextMoveTogether = type(M.unitTextMoveTogether) == "table" and M.unitTextMoveTogether or {}
    M.unitTextMoveTogether[unit] = type(M.unitTextMoveTogether[unit]) == "table" and M.unitTextMoveTogether[unit] or {}
    M.unitTextMoveTogether[unit][tab] = value
    PersistTableValue("unitTextTabSelection", unit, tab)
    local slot = value and nil or CurrentUnitTextSlot(unit, tab)
    RememberSelectedTextTarget("unitframe", unit, tab, slot)
    FocusUnitText(unit, tab, slot)
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then _G.MSUF_UFPreview_RequestRefresh("MSUF_ASSISTANT_TEXT_MOVE_MODE") end
    OpenMenuPage(UNIT_PAGE_KEYS[unit])
    return true, "Set " .. UnitLabel(unit) .. " " .. TEXT_TAB_LABELS[tab] .. " move text as one group " .. (value and "on" or "off") .. "."
end

local function SetGroupTextSelector(args)
    local scope = ResolveGroupScope(args and args.scope) or "party"
    local tab = ResolveTextTab(args and args.tab)
    local slot = ResolveTextSlot(args and args.slot)
    if not tab then return false, "I do not know which group text tab to select." end
    PersistScalar("gfScope", scope)
    PersistTableValue("gfTextTabSelection", scope, tab)
    if slot and (tab == "hp" or tab == "power") then PersistNestedTableValue("gfTextSlotSelection", scope, tab, slot) end
    RememberSelectedTextTarget("group", scope, tab, slot)
    FocusGroupText(scope, tab, slot)
    OpenMenuPage("gf_bars")
    return true, "Selected " .. GroupLabel(scope) .. " " .. TEXT_TAB_LABELS[tab] .. (slot and (" " .. TEXT_SLOT_LABELS[slot] .. " slot") or " tab") .. "."
end

local function SetGroupTextMoveTogether(args)
    local scope = ResolveGroupScope(args and args.scope) or "party"
    local tab = ResolveTextTab(args and args.tab)
    local value = SelectorBool(args and args.value)
    if tab ~= "hp" and tab ~= "power" then return false, "Text move-together mode is only available for HP and Power text." end
    PersistScalar("gfScope", scope)
    M.gfTextMoveTogether = type(M.gfTextMoveTogether) == "table" and M.gfTextMoveTogether or {}
    M.gfTextMoveTogether[scope] = type(M.gfTextMoveTogether[scope]) == "table" and M.gfTextMoveTogether[scope] or {}
    M.gfTextMoveTogether[scope][tab] = value
    PersistTableValue("gfTextTabSelection", scope, tab)
    local slot = value and nil or CurrentGroupTextSlot(scope, tab)
    RememberSelectedTextTarget("group", scope, tab, slot)
    FocusGroupText(scope, tab, slot)
    if M and type(M.RefreshGFNativePreviews) == "function" then M.RefreshGFNativePreviews() end
    OpenMenuPage("gf_bars")
    return true, "Set " .. GroupLabel(scope) .. " " .. TEXT_TAB_LABELS[tab] .. " move text as one group " .. (value and "on" or "off") .. "."
end

local function SetUnitStatusSelector(args)
    local unit = ResolveUnitKey(args and args.unit)
    local tab = ResolveStatusTab(args and args.tab)
    local spec = unit and A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, args and (args.status or args.text)) or nil
    if not unit then return false, "I do not know which unit status menu to select." end
    if not (tab or spec) then return false, "I do not know which unit status indicator to select." end
    if tab then PersistTableValue("unitStatusTabSelection", unit, tab) end
    if spec then
        PersistTableValue("unitStatusSelection", unit, spec.value)
        FocusUnitStatus(spec.value)
    end
    OpenMenuPage(UNIT_PAGE_KEYS[unit])
    if spec then
        return true, "Selected " .. UnitLabel(unit) .. " " .. tostring(spec.label or spec.value) .. " status indicator."
    end
    return true, "Selected " .. UnitLabel(unit) .. " " .. STATUS_TAB_LABELS[tab] .. " status tab."
end

local function SetGroupStatusSelector(args)
    local scope = ResolveGroupScope(args and args.scope) or "party"
    local tab = ResolveStatusTab(args and args.tab)
    local icon, label = ResolveGroupStatusIcon(args and (args.icon or args.text))
    if not (tab or icon) then return false, "I do not know which group status indicator to select." end
    PersistScalar("gfScope", scope)
    if tab then PersistTableValue("gfStatusIconTabSelection", scope, tab) end
    if icon then PersistScalar("gfStatusIconSelection", icon) end
    OpenMenuPage("gf_indicators")
    if icon then return true, "Selected " .. GroupLabel(scope) .. " " .. tostring(label or icon) .. " indicator." end
    return true, "Selected " .. GroupLabel(scope) .. " " .. STATUS_TAB_LABELS[tab] .. " status icon tab."
end

local function SetGroupSpellSelector(args)
    local scope = ResolveGroupScope(args and args.scope) or "party"
    local spec = A.ResolveGroupSpellSpec and A.ResolveGroupSpellSpec(args and (args.spec or args.text)) or nil
    local aura, resolvedSpec, display
    if type(A.ResolveGroupSpellAura) == "function" then
        aura, resolvedSpec, display = A.ResolveGroupSpellAura(spec, tostring(args and (args.aura or args.text) or ""))
    end
    spec = spec or resolvedSpec
    if not (spec or aura) then return false, "I do not know which spell indicator selector to set." end
    PersistScalar("gfScope", scope)
    if spec then PersistTableValue("gfSpellMultiSpecSelection", scope, spec) end
    if aura then PersistTableValue("gfSpellIndicatorSelection", scope, aura) end
    OpenMenuPage("gf_indicators")
    local specLabel = spec and A.GroupSpellSpecDisplay and A.GroupSpellSpecDisplay(spec) or spec
    if aura then
        return true, "Selected " .. GroupLabel(scope) .. " " .. tostring(display or aura) .. " spell indicator."
    end
    return true, "Selected " .. GroupLabel(scope) .. " " .. tostring(specLabel or spec) .. " spell indicator spec."
end

local function SetGroupCornerSelector(args)
    local scope = ResolveGroupScope(args and args.scope) or "party"
    local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(args and (args.slot or args.text)) or nil
    if not slot then return false, "I do not know which corner editor slot to select." end
    PersistScalar("gfScope", scope)
    PersistScalar("gfCornerSlotSelection", slot.key or slot.value)
    OpenMenuPage("gf_indicators")
    return true, "Selected " .. GroupLabel(scope) .. " " .. tostring(slot.label or slot.text or slot.key or slot.value) .. " corner editor slot."
end

local function SetColorTokenSelector(args)
    local kind = NormalizeKey(args and args.kind)
    if kind == "classpower" or kind == "classresource" or kind == "cp" then
        local token, label = ResolveToken(A.ClassPowerColorTokens or {}, args and args.token)
        if not token then return false, "I do not know which class resource color token to select." end
        PersistScalar("colorsCPToken", token)
        OpenMenuPage("opt_colors")
        return true, "Selected " .. tostring(label or token) .. " class resource color token."
    end
    local token, label = ResolveToken(A.PowerColorTokens or {}, args and args.token)
    if not token then return false, "I do not know which power color token to select." end
    PersistScalar("colorsPowerToken", token)
    OpenMenuPage("opt_colors")
    return true, "Selected " .. tostring(label or token) .. " power color token."
end

local function SetProfileStagingSelector(args)
    local field = NormalizeKey(args and (args.field or args.selector))
    if field == "profileexportkind" or field == "exportkind" or field == "exporttype" then
        local kind, label = ResolveProfileExportKind(args and args.kind)
        PersistScalar("profileExportKind", kind)
        OpenMenuPage("profiles")
        return true, "Selected " .. tostring(label or kind) .. " profile export kind."
    end
    if field == "profileimportcreatenew" or field == "importcreatenew" or field == "importnewprofile" or field == "newprofileimport" then
        local value = SelectorBool(args and args.value)
        PersistScalar("profileImportCreateNew", value)
        OpenMenuPage("profiles")
        return true, "Set profile import and create new profile " .. (value and "on" or "off") .. "."
    end
    if field == "profilecreatecopyname" or field == "createname" or field == "copyname" or field == "profilename" then
        M.profileCreateCopyName = tostring(args and args.value or "")
        OpenMenuPage("profiles")
        return true, "Set profile create/copy name to " .. tostring(M.profileCreateCopyName) .. "."
    end
    if field == "profileimportnewname" or field == "importnewname" or field == "newprofilename" then
        M.profileImportNewName = tostring(args and args.value or "")
        OpenMenuPage("profiles")
        return true, "Set profile import new-profile name to " .. tostring(M.profileImportNewName) .. "."
    end
    if field == "profilestring" or field == "profileimportstring" or field == "importstring" then
        M.profileImportString = tostring(args and args.value or "")
        OpenMenuPage("profiles")
        return true, "Set profile string field."
    end
    return false, "I do not know which profile staging field to set."
end

local function ResolveClassPowerStyleTab(tab)
    local key = NormalizeKey(tab)
    if key == "texture" or key == "textures" or key == "resource" or key == "resources" then return "resources", "Textures" end
    if key == "text" or key == "texts" then return "text", "Text" end
    if key == "opacity" or key == "alpha" or key == "transparency" then return "opacity", "Opacity" end
    if key == "pip" or key == "pips" or key == "separator" or key == "separators" then return "pips", "Pips" end
    return nil
end

local function SetClassPowerStyleTabSelector(args)
    local tab, label = ResolveClassPowerStyleTab(args and args.tab)
    if not tab then return false, "I do not know which Class Resources style tab to select." end
    PersistScalar("classPowerStyleTab", tab)
    OpenMenuPage("classpower")
    return true, "Selected Class Resources Style " .. tostring(label or tab) .. " tab."
end

local function ResolveBarsHighlightTab(tab)
    local key = NormalizeKey(tab)
    if key == "mode" or key == "modes" or key == "border" or key == "borders" then return "modes", "Modes" end
    if key == "preview" or key == "test" or key == "tests" then return "preview", "Preview" end
    if key == "priority" or key == "priorities" or key == "order" or key == "ordering" then return "priority", "Priority" end
    return nil
end

local function SetBarsHighlightTabSelector(args)
    local tab, label = ResolveBarsHighlightTab(args and args.tab)
    if not tab then return false, "I do not know which Highlight Borders tab to select." end
    PersistScalar("barsHighlightTab", tab)
    OpenMenuPage("opt_bars")
    return true, "Selected Highlight Borders " .. tostring(label or tab) .. " tab."
end

local function CurrentUnitPage()
    local page = M and M.activeKey
    if type(page) ~= "string" then return nil end
    for unit, key in pairs(UNIT_PAGE_KEYS) do
        if key == page then return unit end
    end
    return nil
end

local function SetUnitCopyScopeSelector(args)
    local scopes, cats = EnsureUnitCopyScopes()
    local unit = ResolveUnitKey(args and args.unit) or CurrentUnitPage() or "player"
    local command = NormalizeKey(args and args.command)
    local function refresh()
        OpenMenuPage(UNIT_PAGE_KEYS[unit] or "uf_player")
        if M and type(M.Refresh) == "function" then M.Refresh() end
    end
    if command == "all" or command == "selectall" then
        for i = 1, #cats do scopes[cats[i].key] = true end
        refresh()
        return true, "Selected all unit copy categories."
    end
    if command == "none" or command == "clear" or command == "selectnone" then
        for i = 1, #cats do scopes[cats[i].key] = false end
        refresh()
        return true, "Cleared all unit copy categories."
    end
    if command == "only" then
        local wanted = args and args.categories
        if type(wanted) ~= "table" or #wanted == 0 then return false, "I need at least one unit copy category." end
        for i = 1, #cats do scopes[cats[i].key] = false end
        local labels = {}
        for i = 1, #wanted do
            local key, label = ResolveUnitCopyCategory(wanted[i])
            if key then
                scopes[key] = true
                labels[#labels + 1] = tostring(label or key)
            end
        end
        if #labels == 0 then return false, "I do not know those unit copy categories." end
        refresh()
        return true, "Selected only unit copy categories: " .. table.concat(labels, ", ") .. "."
    end
    local key, label = ResolveUnitCopyCategory(args and args.category)
    if not key then return false, "I do not know which unit copy category to set." end
    scopes[key] = SelectorBool(args and args.value)
    refresh()
    return true, "Set unit copy category " .. tostring(label or key) .. " " .. (scopes[key] and "on" or "off") .. "."
end

local function SetGroupCopyScopeSelector(args)
    local scopes, cats = EnsureGroupCopyScopes()
    local command = NormalizeKey(args and args.command)
    local function refresh()
        OpenMenuPage("gf_layout")
        if M and type(M.Refresh) == "function" then M.Refresh() end
    end
    if command == "all" or command == "selectall" then
        for i = 1, #cats do
            scopes[cats[i].key] = true
        end
        refresh()
        return true, "Selected all group copy categories."
    end
    if command == "none" or command == "clear" or command == "selectnone" then
        for i = 1, #cats do scopes[cats[i].key] = false end
        refresh()
        return true, "Cleared all group copy categories."
    end
    if command == "only" then
        local wanted = args and args.categories
        if type(wanted) ~= "table" or #wanted == 0 then return false, "I need at least one group copy category." end
        for i = 1, #cats do scopes[cats[i].key] = false end
        local labels = {}
        for i = 1, #wanted do
            local key, label = ResolveGroupCopyCategory(wanted[i])
            if key then
                scopes[key] = true
                labels[#labels + 1] = tostring(label or key)
            end
        end
        if #labels == 0 then return false, "I do not know those group copy categories." end
        refresh()
        return true, "Selected only group copy categories: " .. table.concat(labels, ", ") .. "."
    end
    local key, label = ResolveGroupCopyCategory(args and args.category)
    if not key then return false, "I do not know which group copy category to set." end
    scopes[key] = SelectorBool(args and args.value)
    refresh()
    return true, "Set group copy category " .. tostring(label or key) .. " " .. (scopes[key] and "on" or "off") .. "."
end

function A.Workflow.SetMenuSelectorState(args)
    local selector = tostring(args and args.selector or "")
    if selector == "unit_text" then return SetUnitTextSelector(args) end
    if selector == "group_text" then return SetGroupTextSelector(args) end
    if selector == "unit_text_move_together" then return SetUnitTextMoveTogether(args) end
    if selector == "group_text_move_together" then return SetGroupTextMoveTogether(args) end
    if selector == "unit_status" then return SetUnitStatusSelector(args) end
    if selector == "group_status" then return SetGroupStatusSelector(args) end
    if selector == "group_spell" then return SetGroupSpellSelector(args) end
    if selector == "group_corner" then return SetGroupCornerSelector(args) end
    if selector == "color_token" then return SetColorTokenSelector(args) end
    if selector == "profile_staging" then return SetProfileStagingSelector(args) end
    if selector == "class_power_style_tab" then return SetClassPowerStyleTabSelector(args) end
    if selector == "bars_highlight_tab" then return SetBarsHighlightTabSelector(args) end
    if selector == "unit_copy_scope" then return SetUnitCopyScopeSelector(args) end
    if selector == "group_copy_scope" then return SetGroupCopyScopeSelector(args) end
    return false, "I do not know which menu selector to set."
end

function A.Workflow.ControlMenuWindow(command)
    command = tostring(command or "")
    local frame = M and M.frame or nil
    if command == "close" then
        if M and type(M.HideSlashMenuAndMinibar) == "function" then
            M.HideSlashMenuAndMinibar(frame)
            return true, "Closed the MSUF menu."
        end
        return false, "Menu close is not available right now."
    end
    if command == "minimize" then
        if M and type(M.MinimizeSlashMenuWindow) == "function" then
            if M.MinimizeSlashMenuWindow(frame) ~= false then return true, "Minimized the MSUF menu." end
        end
        return false, "Menu minimize is not available right now."
    end
    if command == "maximize" then
        if M and type(M.MaximizeSlashMenuWindow) == "function" then
            if M.MaximizeSlashMenuWindow(frame) ~= false then return true, "Maximized or restored the MSUF menu." end
        end
        return false, "Menu maximize is not available right now."
    end
    if command == "restore" then
        if M and M.minimizedBar and M.minimizedBar.IsShown and M.minimizedBar:IsShown() and type(M.RestoreMinimizedSlashMenu) == "function" then
            if M.RestoreMinimizedSlashMenu(frame) ~= false then return true, "Restored the MSUF menu." end
        end
        if M and type(M.RestoreSlashMenuWindow) == "function" then
            if M.RestoreSlashMenuWindow(frame) ~= false then return true, "Restored the MSUF menu." end
        end
        return false, "Menu restore is not available right now."
    end
    return false, "I do not know which menu window action to run."
end

function A.Workflow.StageFactoryReset()
    if not (M and type(M.StageFactoryReset) == "function") then
        return false, "Factory reset is not available right now."
    end
    if M.StageFactoryReset() then
        return true, "Done. Factory reset is staged. Reload UI to rebuild clean defaults."
    end
    return false, "Factory reset could not be staged right now."
end

Registry:RegisterAction({
    key = "confirm_wago_backup",
    label = "Confirm Wago Backup",
    type = "setup",
    combatSafe = true,
    run = function(args)
        local confirmed = not (args and args.confirmed == false)
        A.Workflow.SetWagoBackupConfirmed(confirmed)
        return true, confirmed and "Done. Wago backup is marked confirmed for this profile." or "Done. Wago backup confirmation was cleared for this profile."
    end,
})

Registry:RegisterAction({
    key = "open_recovery_tools",
    label = "Open Recovery Tools",
    type = "navigation",
    combatSafe = true,
    run = function()
        return A.Workflow.OpenDashboardPanel("recovery")
    end,
})

Registry:RegisterAction({
    key = "open_dashboard_panel",
    label = "Open Dashboard Panel",
    type = "navigation",
    combatSafe = true,
    run = function(args)
        return A.Workflow.OpenDashboardPanel(args and args.panel)
    end,
})

Registry:RegisterAction({
    key = "set_dashboard_panel",
    label = "Set Dashboard Panel",
    type = "navigation",
    aliases = {
        "open dashboard panel", "close dashboard panel", "toggle dashboard panel",
        "open recovery tools", "close recovery tools", "toggle recovery tools",
        "open scaling tools", "close scaling tools", "toggle scaling tools",
        "open changelog", "close changelog", "toggle changelog",
    },
    combatSafe = true,
    run = function(args)
        return A.Workflow.SetDashboardPanel(args and args.panel, args and args.open)
    end,
})

Registry:RegisterAction({
    key = "set_nav_section",
    label = "Set Navigation Section",
    type = "navigation",
    aliases = {
        "open navigation section", "close navigation section", "toggle navigation section",
        "expand frames section", "collapse frames section",
        "expand group frames section", "collapse group frames section",
        "expand appearance section", "collapse appearance section",
        "expand advanced section", "collapse advanced section",
    },
    combatSafe = true,
    run = function(args)
        return A.Workflow.SetNavSection(args and args.section, args and args.open)
    end,
})

Registry:RegisterAction({
    key = "set_nav_search_intro",
    label = "Set Search Intro",
    type = "navigation",
    aliases = {
        "show search intro", "hide search intro", "reset search intro",
        "mark search intro seen", "show ask msuf intro",
    },
    combatSafe = true,
    run = function(args)
        return A.Workflow.SetNavSearchIntro(args and args.command)
    end,
})

Registry:RegisterAction({
    key = "set_menu_selector_state",
    label = "Set Menu Selector State",
    type = "navigation",
    aliases = {
        "select text tab", "select text slot", "select status tab", "select status indicator",
        "select group status icon", "select spell indicator", "select corner editor slot",
        "select power color token", "select class resource color token",
        "select class power style tab", "select class resource style tab", "select class resources style area",
        "select highlight borders tab", "select bars highlight tab", "select highlight area",
        "move text as one group", "move text per slot", "text move together",
        "select profile export kind", "set profile staging field", "set profile string field",
        "set unit copy category", "select unit copy categories",
        "set group copy category", "select group copy categories",
    },
    combatSafe = true,
    run = function(args)
        return A.Workflow.SetMenuSelectorState(args)
    end,
})

Registry:RegisterAction({
    key = "menu_window_close",
    label = "Close MSUF Menu",
    type = "navigation",
    aliases = { "close menu", "close msuf menu", "close dashboard", "hide menu", "hide msuf menu" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("close")
    end,
})

Registry:RegisterAction({
    key = "menu_window_minimize",
    label = "Minimize MSUF Menu",
    type = "navigation",
    aliases = { "minimize menu", "minimize msuf menu", "minimize dashboard", "collapse menu window" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("minimize")
    end,
})

Registry:RegisterAction({
    key = "menu_window_maximize",
    label = "Maximize MSUF Menu",
    type = "navigation",
    aliases = { "maximize menu", "maximize msuf menu", "maximize dashboard", "fullscreen menu" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("maximize")
    end,
})

Registry:RegisterAction({
    key = "menu_window_restore",
    label = "Restore MSUF Menu",
    type = "navigation",
    aliases = { "restore menu", "restore msuf menu", "restore dashboard", "restore maximized menu", "unminimize menu", "show minimized menu" },
    combatSafe = true,
    run = function()
        return A.Workflow.ControlMenuWindow("restore")
    end,
})

Registry:RegisterAction({
    key = "assistant.action.history.undo",
    label = "Undo Last Assistant Change",
    type = "history",
    combatSafe = false,
    run = function()
        if not (A and type(A.UndoLast) == "function") then
            return false, "Assistant undo is not available right now."
        end
        return A.UndoLast()
    end,
})

Registry:RegisterAction({
    key = "assistant.action.history.redo",
    label = "Redo Last Assistant Change",
    type = "history",
    combatSafe = false,
    run = function()
        if not (A and type(A.RedoLast) == "function") then
            return false, "Assistant redo is not available right now."
        end
        return A.RedoLast()
    end,
})

Registry:RegisterAction({
    key = "menu_history_undo",
    label = "Undo Last Menu Change",
    type = "history",
    aliases = { "undo menu change", "undo menu history", "undo ui change", "undo navrail history" },
    combatSafe = false,
    run = function()
        if not (M and type(M.Undo) == "function") then return false, "MSUF menu undo is not available right now." end
        local ok = M.Undo()
        if ok then return true, "Done. Undid the last MSUF menu change." end
        return false, "There is no MSUF menu change to undo."
    end,
})

Registry:RegisterAction({
    key = "menu_history_redo",
    label = "Redo Last Menu Change",
    type = "history",
    aliases = { "redo menu change", "redo menu history", "redo ui change", "redo navrail history" },
    combatSafe = false,
    run = function()
        if not (M and type(M.Redo) == "function") then return false, "MSUF menu redo is not available right now." end
        local ok = M.Redo()
        if ok then return true, "Done. Redid the last MSUF menu change." end
        return false, "There is no MSUF menu change to redo."
    end,
})

Registry:RegisterAction({
    key = "menu_history_reset_session",
    label = "Reset Menu Session Changes",
    type = "history",
    aliases = {
        "reset all menu changes", "reset menu session changes", "reset all session changes",
        "reset msuf2 menu changes", "reset navrail history session",
    },
    combatSafe = false,
    confirmRequired = true,
    captureProfileSnapshot = true,
    run = function()
        if not (M and type(M.ResetHistorySession) == "function") then return false, "MSUF menu session reset is not available right now." end
        local state = M.GetHistoryState and M.GetHistoryState() or nil
        if state and not state.canResetAll then return false, "There are no MSUF menu session changes to reset." end
        local ok = M.ResetHistorySession()
        if ok then return true, "Done. Reset all MSUF menu changes from this open session." end
        return false, "MSUF menu session changes could not be reset right now."
    end,
})

Registry:RegisterAction({
    key = "factory_reset_all",
    label = "Factory Reset All",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    captureProfileSnapshot = true,
    run = function()
        return A.Workflow.StageFactoryReset()
    end,
})

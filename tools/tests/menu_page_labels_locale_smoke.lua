-- menu_page_labels_locale_smoke.lua <repoRoot> <flavor> [reportFile]
--
-- Every menu-facing string must exist in all ten translated language packs, and
-- must not be the English key itself.
-- locale_key_coverage_smoke compares the packs with each other, so a label that
-- no pack defines passes it. This smoke closes that gap for the Options menu: it
-- boots the flavor's real core and Options graph (tools/tests/client_world.lua),
-- builds every page, and records every string the menu resolves through the locale
-- table (rawget on MSUF.L, so a helper that captured MSUF.Translate at load time
-- is seen too). A page is not one state: its content differs by unit, lane, tool,
-- group scope and selected indicator, so after the default build the smoke visits
--   * every segment tab of every page in place,
--   * every Aura workspace view (unit page x lane/container x tool, group scope x
--     lane x tool, the global Appearance products, the Dashboard cards),
--   * the selectable status indicators of the Player and Target pages, the Group
--     status icons and corner slots, and every Class Resources workspace,
-- rebuilds the owning page in each and records again. Tooltips (OnEnter), dropdown
-- entries (their value lists) and color shortcut targets are translated only when
-- the player hovers or opens them, so those paths are run too.
--
-- A recorded string counts when it is a quoted literal of a loaded addon file: text
-- composed at run time (profile names, spell names) is data, not a key. A counted
-- string fails when a pack lacks it or defines it as the English key, unless
-- tools/locale-same-text-allowlist.tsv excuses it for that pack (a proper name, a
-- unit, a word the language shares). The bundled release notes are not scanned:
-- most of their entries have never been translated and are not menu labels.
--
-- enUS and enGB fall back to the key itself (MSUF_Localization.lua), so the ten
-- other packs are the ones checked.
--
-- Plain Lua 5.1 with the repo root and a flavor (a client matrix Suffix or
-- Forever) as arguments. A third argument names a file that receives every failing
-- string as text, file, first state, packs without a translation, packs that keep
-- the English text (tab separated), for translators.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
local reportPath = arg and arg[3]
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu_page_labels_locale_smoke boots the real TOC graph; run it with plain Lua 5.1")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

-- Strings whose controls these changes touched that no page build reaches in a
-- state of its own: format keys that replaced concatenated text
-- (menu_pages_quality_smoke section 10) and the Profiles page variant error.
local REQUIRED = {
    "Show on Target castbar", "Show on Focus castbar", "Show on Boss castbars",
    "Place GCD bar separately", "Spell-specific channel tick markers",
    "Mana spend preview", "Regeneration pause after spending", "Mana return pulse",
    "Arcane Surge window timer", "Arcane window warning (seconds)", "Arcane window bar",
    "Arcane window warning text", "Arcane window text", "Seconds left", "Global cooldowns you can still start",
    "Seconds and global cooldowns", "Show the time from (seconds left, 0 = always)",
    "Warn during the last global cooldown", "Arcane Soul phase bar",
    "The saved profile variants cannot be read (%s). They are kept unchanged, and editing them here is blocked.",
    "%s px", "Name %s", "HP %s", "Power %s", "Offline %d%%", "Offline visible", "Offline hidden",
    "Border %s", "IDs: %s", "%s: %s", "%s Indicator", "Group %s", "Texture: %s",
}

---------------------------------------------------------------------------
-- The ten translated packs, executed as the client runs them, and the strings
-- they may leave in English (tools/locale-same-text-allowlist.tsv).
---------------------------------------------------------------------------
local Packs = assert(loadfile(root .. "/tools/tests/locale_packs.lua"))()
local LOCALES = Packs.LOCALES
local packs = Packs.Load(root)
local allowlist = Packs.ReadAllowlist(root, packs)
local function MissingIn(key) return Packs.Missing(packs, allowlist, key) end

---------------------------------------------------------------------------
-- Boot the client and give the page builders the widget surface they use.
---------------------------------------------------------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor):Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local Methods = world.widgets.Methods
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
for name, method in pairs({
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    SetThumbTexture = Store("thumbTexture"), GetThumbTexture = Fetch("thumbTexture"),
    SetValueStep = Store("valueStep"), SetObeyStepOnDrag = Store("obeyStepOnDrag"), SetStepsPerPage = Store("stepsPerPage"),
    SetAutoFocus = Store("autoFocus"), SetNumeric = Store("numeric"), SetMaxLetters = Store("maxLetters"),
    SetPropagateMouseWheel = Store("propagateMouseWheel"),
    SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
    HasFocus = function() return false end, ClearFocus = function() end, SetFocus = function() end,
    HighlightText = function() end, SetCursorPosition = function() end, GetCursorPosition = function() return 0 end,
    SetTextInsets = function() end, SetTimerDuration = function() end,
    SetScrollChild = Store("scrollChild"), GetScrollChild = Fetch("scrollChild"), SetVerticalScroll = Store("verticalScroll"),
    GetVerticalScroll = function(self) return self.verticalScroll or 0 end, GetVerticalScrollRange = function() return 0 end,
}) do
    if Methods[name] == nil then Methods[name] = method end
end
local StubGetValue = Methods.GetValue
Methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end

local env, MSUF = world.env, world.core
local M = Check(world.options.MSUF2, "Menu2 did not load")
env.InCombatLockdown = function() return false end
-- The tooltip frame is a bare stub; the hover path calls these.
for _, name in ipairs({ "SetOwner", "SetText", "AddLine", "AddDoubleLine", "ClearLines", "SetHyperlink", "SetSpellByID" }) do
    env.GameTooltip[name] = function() end
end
-- The GCD Bar section exists only where the client drives the bar natively.
env.C_Spell = setmetatable({ GetSpellCooldownDuration = function() return nil end },
    { __index = function() return World.Stub end })
env.MSUF_EnsureDB(true)
-- A variant and a sync group, so the Profiles page builds both editors in full.
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB, Other = { general = {} } }, char = {}, global = {} }
MSUF.ProfileRuntime.Apply = function() end
Check(MSUF.ProfileVariants.Replace(env.MSUF_DB, { version = 1, entries = { { name = "Check", patch = {} } } }),
    "harness: the profile variant was not saved")
Check(MSUF.ProfileSync.Replace({ { name = "Shared", members = { Default = true, Other = true }, modules = { unitframes = true } } }),
    "harness: the sync group was not saved")
M.frame = M.frame or { IsShown = function() return true end }
M.cache = M.cache or {}
M.scrollChild = M.scrollChild or env.CreateFrame("Frame", nil, env.UIParent)
M.GetContentMetrics = M.GetContentMetrics or function() return 900, 800 end

---------------------------------------------------------------------------
-- Record every string the menu resolves through the locale table, with the
-- state that first produced it.
---------------------------------------------------------------------------
local hit, hitState = {}, {}
local currentState = "default"
local function Record(text)
    if type(text) == "string" and text ~= "" and hit[text] == nil then
        hit[text] = true
        hitState[text] = currentState
    end
end
local L = MSUF.L
local nativeRawget = rawget
env.rawget = function(table, key)
    if table == L and type(key) == "string" then Record(key) end
    return nativeRawget(table, key)
end
local fallback = getmetatable(L).__index
getmetatable(L).__index = function(table, key)
    if type(key) == "string" then Record(key) end
    return fallback(table, key)
end

-- Tooltips and dropdown entries are translated when the player hovers or opens
-- them, color shortcut targets when the popup opens: run those paths here.
local function DropdownText(item)
    if type(item) ~= "table" then return item end
    if item.translate == false then return nil end
    return item.text or item.label or item[1] or item.value
end
local function Harvest(frames, from)
    for index = from, #frames do
        local frame = frames[index]
        local scripts = rawget(frame, "scripts")
        if rawget(frame, "_msuf2TooltipTarget") and scripts and scripts.OnEnter then pcall(scripts.OnEnter, frame) end
        local values = rawget(frame, "values")
        if values ~= nil and rawget(frame, "SetValues") then
            local list = values
            if type(list) == "function" then
                local ok, resolved = pcall(list)
                list = ok and resolved or nil
            end
            for _, item in ipairs(type(list) == "table" and list or {}) do
                Record(DropdownText(item))
                if type(item) == "table" then
                    for _, field in ipairs({ "tooltip", "description", "tooltipTitle" }) do Record(item[field]) end
                end
            end
        end
    end
end
local W = M.Widgets
local Shortcut = W.AttachContextColorShortcut
if Shortcut then
    W.AttachContextColorShortcut = function(section, opts, ...)
        if type(opts) == "table" then
            Record(opts.title)
            for _, target in ipairs(type(opts.getTargets) == "function" and opts.getTargets() or {}) do
                if type(target) == "table" then Record(target.label) end
            end
        end
        return Shortcut(section, opts, ...)
    end
end

---------------------------------------------------------------------------
-- State visits. Menu2 slices hidden lazy sections through construction timers,
-- and a unit page reaches them two ways (inline sections through
-- UnitPage.BuildSectionLazy, registered sections through spec.lazy). Both are
-- forced eager for a rebuild, or the page would come back without every lazily
-- built section. The frames of a visit are dropped afterwards (a stub widget
-- keeps its parent's child list), or the many views would exhaust memory.
---------------------------------------------------------------------------
local function EnsureTable(owner, key)
    local value = owner[key]
    if type(value) ~= "table" then
        value = {}
        owner[key] = value
    end
    return value
end

local function RebuildPage(pageKey)
    local timer, menuTimer = env.C_Timer, M.MenuTimer
    local after = timer and timer.After
    local menuAfter, menuNewTimer = menuTimer and menuTimer.After, menuTimer and menuTimer.NewTimer
    local function RunNow(_, callback) if type(callback) == "function" then callback() end end
    if timer then timer.After = RunNow end
    if menuTimer then
        menuTimer.After = RunNow
        menuTimer.NewTimer = function(_, callback)
            RunNow(nil, callback)
            return { Cancel = function() end }
        end
    end
    local unitPage = type(M.UnitPage) == "table" and M.UnitPage or nil
    local lazyBuilder = unitPage and unitPage.BuildSectionLazy
    local registry = unitPage and type(unitPage._sectionRegistry) == "table" and unitPage._sectionRegistry or {}
    local specLazy = {}
    if unitPage then unitPage.BuildSectionLazy = nil end
    for index = 1, #registry do
        local spec = registry[index]
        if type(spec) == "table" then specLazy[index] = spec.lazy; spec.lazy = false end
    end
    M.InvalidatePage(pageKey)
    -- In game the page being built is the active one.
    local activeKey = M.activeKey
    M.activeKey = pageKey
    local ok, result = pcall(M.BuildPageEntry, pageKey, true)
    M.activeKey = activeKey
    for index = 1, #registry do
        local spec = registry[index]
        if type(spec) == "table" then spec.lazy = specLazy[index] end
    end
    if unitPage then unitPage.BuildSectionLazy = lazyBuilder end
    if timer then timer.After = after end
    if menuTimer then menuTimer.After, menuTimer.NewTimer = menuAfter, menuNewTimer end
    Check(ok and result ~= nil, "the " .. pageKey .. " view " .. currentState .. " did not build: " .. tostring(result))
end

local frames = world.widgets.frames
local visits = 0
--- Drops the frames a visit created, and their entry in each parent's child list.
local function DropFrames(from)
    local dropped, parents = {}, {}
    for index = from, #frames do dropped[frames[index]] = true end
    for frame in pairs(dropped) do
        local parent = rawget(frame, "parent")
        if type(parent) == "table" and not dropped[parent] then parents[parent] = true end
    end
    for parent in pairs(parents) do
        local children = rawget(parent, "children")
        if type(children) == "table" then
            local kept = {}
            for _, child in ipairs(children) do
                if not dropped[child] then kept[#kept + 1] = child end
            end
            parent.children = kept
        end
    end
    for index = #frames, from, -1 do frames[index] = nil end
end
local function Visit(pageKey, label)
    currentState = pageKey .. "/" .. label
    local from = #frames + 1
    RebuildPage(pageKey)
    Harvest(frames, from)
    DropFrames(from)
    visits = visits + 1
    if visits % 100 == 0 then collectgarbage() end
end

-- Default build of every page, remembering each segment tab strip to visit it.
local strips = {}
local SegmentTabs = W.SegmentTabs
W.SegmentTabs = function(ctx, parent, opts)
    local segment, refresh, current, setTab = SegmentTabs(ctx, parent, opts)
    strips[#strips + 1] = { opts = opts, set = setTab, current = current, page = currentState }
    return segment, refresh, current, setTab
end
local pageKeys = {}
for key in pairs(M.pages) do pageKeys[#pageKeys + 1] = key end
table.sort(pageKeys)
for _, key in ipairs(pageKeys) do
    currentState = key .. "/default"
    Check(M.BuildPageEntry(key, true), "the " .. key .. " page did not build")
    world.widgets:RunTimers(20000)
end
W.SegmentTabs = SegmentTabs
currentState = "default/harvest"
Harvest(frames, 1)
-- Every tab of every strip, in place (all tab bodies exist; a tab may build lazily when shown).
local tabSets = 0
for _, strip in ipairs(strips) do
    local original = strip.current()
    for _, item in ipairs(strip.opts.values or {}) do
        currentState = "tab/" .. tostring(strip.page) .. "/" .. tostring(item.value)
        pcall(strip.set, item.value)
        world.widgets:RunTimers(20000)
        tabSets = tabSets + 1
    end
    pcall(strip.set, original)
end
Harvest(frames, 1)
strips = nil
collectgarbage()

-- The finite Aura workspace views, the same matrix the search index collects
-- (.github/scripts/search_static_index_project.lua): four unit frames and every
-- container tool, three group scopes and every lane tool, the global Appearance
-- products and their compatibility landings. A Custom container is also visited
-- as a Debuff container, where its Filters and Behavior branch on the aura type.
local pages = M.pages
local model = Check(world.env.MSUF_NS.MSUF_Auras3 and world.env.MSUF_NS.MSUF_Auras3.MenuModel, "the Auras3 menu model did not load")
local UNIT_PAGES = {
    { unit = "player", page = "uf_player" }, { unit = "pet", page = "uf_pet" }, { unit = "target", page = "uf_target" },
    { unit = "focus", page = "uf_focus" }, { unit = "boss", page = "uf_boss" }, { unit = "arena", page = "uf_arena" },
}
local LANE_TOOLS = { "layout", "behavior", "filters", "blacklist", "style" }
local CUSTOM_TOOLS = { "setup", "layout", "behavior", "filters", "whitelist", "style" }
local AURA_TYPE_TOOLS = { "filters", "behavior" }
local INDEX4_TOOLS = {
    player = { "setup", "layout", "behavior", "filters", "defensives", "style" },
    other = { "setup", "layout", "behavior", "filters", "dots", "style" },
}
local EXTERNALS_TOOLS = { "layout", "behavior", "style" }
local GROUP_SCOPES = { "party", "raid", "mythicraid" }
local APPEARANCE_PRODUCTS = { "buff", "debuff", "playerDefensives", "targetDots" }
local function SetCustomAuraType(unit, index, auraType)
    local item = model.CustomContainer(unit, index, true)
    if type(item) == "table" then item.auraType = auraType end
end
for _, row in ipairs(UNIT_PAGES) do
    if pages[row.page] then
        local function UnitView(container, tool)
            EnsureTable(M, "unitAuraTabSelection")[row.unit] = container
            EnsureTable(EnsureTable(M, "unitAuraToolSelection"), row.unit)[container] = tool
            Visit(row.page, container .. "/" .. tool)
        end
        for _, lane in ipairs({ "buff", "debuff" }) do
            for _, tool in ipairs(LANE_TOOLS) do UnitView(lane, tool) end
        end
        for index = 1, 3 do
            local container = "custom" .. index
            SetCustomAuraType(row.unit, index, "BUFF")
            for _, tool in ipairs(CUSTOM_TOOLS) do UnitView(container, tool) end
            SetCustomAuraType(row.unit, index, "DEBUFF")
            for _, tool in ipairs(AURA_TYPE_TOOLS) do UnitView(container, tool) end
            SetCustomAuraType(row.unit, index, "BUFF")
        end
        for _, tool in ipairs(INDEX4_TOOLS[row.unit] or INDEX4_TOOLS.other) do UnitView("custom4", tool) end
        UnitView("buff", "layout")
    end
end
for _, scope in ipairs(GROUP_SCOPES) do
    if M.SupportsFrameScope(scope) then
        M.gfScope = scope
        for _, pageKey in ipairs({ "gf_layout", "gf_bars", "gf_indicators", "gf_priority" }) do
            if pages[pageKey] then Visit(pageKey, scope) end
        end
        if pages.gf_auras then
            local function GroupView(lane, tool)
                EnsureTable(M, "gfAuraLaneSelection")[scope] = lane
                EnsureTable(EnsureTable(M, "gfAuraToolSelection"), scope)[lane] = tool
                Visit("gf_auras", scope .. "/" .. lane .. "/" .. tool)
            end
            for _, lane in ipairs({ "buff", "debuff" }) do
                for _, tool in ipairs(LANE_TOOLS) do GroupView(lane, tool) end
            end
            for _, tool in ipairs(EXTERNALS_TOOLS) do GroupView("externals", tool) end
        end
    end
end
for _, product in ipairs(APPEARANCE_PRODUCTS) do
    -- The Mainline Aura page keeps the selected product in auraAppearanceContainer,
    -- the Classic one in auraSharedStyleContainer.
    M.auraAppearanceContainer, M.auraSharedStyleContainer = product, product
    if product == "buff" or product == "debuff" then M.auraStyleGFLane = product end
    if pages.auras3_styling then Visit("auras3_styling", product) end
    for _, pageKey in ipairs({ "auras3_buffs", "auras3_debuffs" }) do
        if pages[pageKey] and (product == "buff" or product == "debuff") then Visit(pageKey, product) end
    end
end
-- The Dashboard's Display & recovery and Scaling cards build their controls only while open.
if pages.home then
    M.dashboardRecoveryOpen, M.dashboardScalingOpen = true, true
    Visit("home", "cards")
end
-- The selectable indicators: each status indicator of a unit page changes the
-- icon styles and tooltips its section lists; so do the group status icons and
-- corner slots and the Class Resources workspaces.
local UNIT_STATUS = { "leader", "assist", "raidmarker", "level", "bossNumber", "raceText", "classText", "raidgroupname", "eliteicon",
    "statusText", "statusGhostText", "statusAFKText", "statusAFKTimer", "statusDNDText", "statusCombat", "statusResting",
    "statusIncomingRes", "stance", "statusPvp", "statusPetHappiness", "statusPetXP", "statusThreat" }
for _, unit in ipairs({ "player", "target" }) do
    if pages["uf_" .. unit] then
        for _, value in ipairs(UNIT_STATUS) do
            EnsureTable(M, "unitStatusSelection")[unit] = value
            Visit("uf_" .. unit, "status/" .. value)
        end
    end
end
if pages.gf_indicators then
    M.gfScope = "party"
    for _, value in ipairs({ "roleIcon", "leaderIcon", "assistIcon", "raidMarker", "readyCheckIcon", "summonIcon", "resurrectIcon",
        "pvpIcon", "phaseIcon", "statusText", "statusGhostText", "statusAFKText", "statusAFKTimer", "statusDNDText", "levelText", "threatText" }) do
        M.gfStatusIconSelection = value
        Visit("gf_indicators", "status/" .. value)
    end
    for _, slot in ipairs({ "TL", "TR", "BL", "BR", "C" }) do
        M.gfCornerSlotSelection = slot
        Visit("gf_indicators", "corner/" .. slot)
    end
end
if pages.classpower then
    for _, workspace in ipairs({ "class", "power", "hp", "mana", "extras" }) do
        M.classPowerWorkspaceKey = workspace
        Visit("classpower", "workspace/" .. workspace)
    end
end

---------------------------------------------------------------------------
-- The quoted literals of the loaded files (the release notes excepted): a
-- recorded string that is no literal anywhere is composed at run time.
---------------------------------------------------------------------------
local literalFile = {}
do
    local paths = {}
    for _, list in ipairs({ world.corePaths or {}, world.optionsPaths or {} }) do
        for _, path in ipairs(list) do paths[#paths + 1] = path end
    end
    for _, path in ipairs(paths) do
        local relative = path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2) or path
        if not relative:find("/Locales/", 1, true) and not relative:find("AliasData", 1, true)
            and not relative:find("StaticIndex_Data", 1, true) and not relative:find("Changelog", 1, true) then
            local handle = io.open(path, "rb")
            if handle then
                local source = handle:read("*a"):gsub("\r\n", "\n")
                handle:close()
                local function Add(piece)
                    if #piece >= 2 and literalFile[piece] == nil and piece:find("%a") then literalFile[piece] = relative end
                end
                Packs.ScanLiterals(source, function(piece)
                    Add(piece)
                    -- Packed dropdown lists: "KEY=Label|KEY2=Label2".
                    if piece:find("|", 1, true) and piece:find("=", 1, true) then
                        for entry in piece:gmatch("[^|]+") do
                            local label = entry:match("^[%w_]+=(.+)$")
                            if label then Add(label) end
                        end
                    end
                end)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Every counted string is translated in every pack.
---------------------------------------------------------------------------
local texts = {}
for text in pairs(hit) do
    if literalFile[text] then texts[#texts + 1] = text end
end
table.sort(texts)
local problems, report = {}, {}
for _, text in ipairs(texts) do
    local missing = MissingIn(text)
    if #missing > 0 then
        local escaped = text:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t")
        problems[#problems + 1] = string.format("%s (%s): %q is untranslated in %s", literalFile[text]:match("[^/]+$"),
            hitState[text], text:sub(1, 90), table.concat(missing, ","))
        report[#report + 1] = table.concat({ escaped, literalFile[text], hitState[text], table.concat(missing, ",") }, "\t")
    end
end
for _, text in ipairs(REQUIRED) do
    local missing = MissingIn(text)
    if #missing > 0 then
        problems[#problems + 1] = string.format("required: %q is untranslated in %s", text, table.concat(missing, ","))
    end
end
if reportPath then
    local handle = assert(io.open(reportPath, "wb"))
    handle:write(table.concat(report, "\n"), "\n")
    handle:close()
end
-- Composed labels must translate the format and its label independently.
do
    local oldTr, oldTranslateText, oldFormat = M.Tr, M.TranslateText, M.Format
    local dictionary = {
        Text = "TEXT_DE", ["%s On"] = "%s AN", ["%s Off"] = "%s AUS",
        ["Buff Appearance"] = "BUFF_AUSSEHEN",
        ["only the global %s icon shape, border and shadow settings; other Aura types and all Unit/Group lane settings stay unchanged"] = "SUMMARY %s",
        ["only the global %s icon shape, border and shadow settings, plus the shared Blizzard Buff/Debuff visibility settings; other Aura types and all Unit/Group lane settings stay unchanged"] = "SUMMARY %s",
        ["Reset %s to defaults?\n\nThis resets %s for the active profile. Defaults are read from the current MSUF factory profile, so future default changes are used automatically."] = "RESET %s | %s",
    }
    M.Tr = function(key) return dictionary[key] or key end
    M.TranslateText = M.Tr
    M.Format = function(key, ...) return string.format(M.Tr(key), ...) end
    Check(M.Widgets.ToggleBadge("Text", true).text == "TEXT_DE AN", "toggle badge left the label or state English")
    Check(M.Widgets.ToggleBadge("Text", false).text == "TEXT_DE AUS", "disabled badge left the label or state English")
    local warning = M.BuildPageResetWarning("auras3_buffs")
    Check(warning == "RESET BUFF_AUSSEHEN | SUMMARY BUFF_AUSSEHEN", "aura reset summary left its inner label English")
    M.Tr, M.TranslateText, M.Format = oldTr, oldTranslateText, oldFormat
end

local shown = {}
for index = 1, math.min(#problems, 40) do shown[index] = problems[index] end
if #problems > #shown then shown[#shown + 1] = "... and " .. (#problems - #shown) .. " more (pass a report file as the third argument for all)" end
Check(#problems == 0, #problems .. " untranslated menu string(s) (first state in brackets):\n  " .. table.concat(shown, "\n  "))
Check(#texts > 0, "no literal menu string was recorded")
if flavor == "Forever" then
    local swing = false
    for _, state in pairs(hitState) do
        if state:find("^swingtimers/") then swing = true break end
    end
    Check(swing, "the Swing Timers page recorded no label on WoW Forever")
end
local inViews = 0
for _, text in ipairs(texts) do
    local state = hitState[text]
    if not (state:find("/default$") or state:find("^default/") or state:find("^tab/")) then inViews = inViews + 1 end
end

print(string.format("menu_page_labels_locale_smoke: ok (%s; %d menu strings in %d packs: %d pages with %d tab selections, %d more in %d workspace and indicator views)",
    flavor, #texts, #LOCALES, #pageKeys, tabSets, inViews, visits))

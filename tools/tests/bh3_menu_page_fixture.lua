-- menu_pages_client_gates_smoke.lua <repoRoot> <flavor>
--
-- Every client builds the same Retail-named Menu2 page files. A control or a
-- list entry that only some clients can use must follow an MSUF.Client fact
-- (or a Blizzard constant that is exact per client), never assume Midnight.
-- This smoke boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real pages hidden (as the search
-- index does) and checks what each page offers on this client:
--
--   1. Unit page, top "Copy To" popup: only frames the client can produce
--      (MSUF.Client.SupportsUnit). Classic Era has no Focus, Focus Target,
--      Boss or Arena frames, TBC no Boss frames and WoW Forever no Arena.
--   2. Group Layout > Sorting, class priority: one row per class of this
--      client. CLASS_SORT_ORDER is exact per client (9 classes on Classic
--      Era, TBC and WoW Forever, 11 on Mists, 13 on Midnight); the
--      RAID_CLASS_COLORS table also carries classes the client lacks.
--   3. Group Layout sections: "Missing class buffs (Forever)" exists only on
--      WoW Forever, declared by its section spec (clientCapability), and
--      "Hide groups 5–8 in Mythic raids" only where the Mythic Raid scope
--      exists (Midnight); the other clients do not build it at all.
--   4. Class Resources > Additional resources and Colors > Additional resource
--      colors: each extra control exists only where its runtime draws it (the
--      native duration bars and their size sliders on Midnight, the regeneration
--      pause and return pulse on Classic Era, TBC and WoW Forever, the mana spend
--      preview everywhere), and a resource mark offers only power types the
--      client can have.
--   5. Castbars page: "Show on Focus/Boss/Arena castbars" only for castbar
--      units the client has, the preview's Empowered cast type only where
--      MSUF.Client.HasEmpoweredCasts is true, and the dependent controls follow
--      their switches: the separate GCD bar controls need the GCD bar and
--      "Place GCD bar separately", "Highlight last channel tick" needs the
--      channel tick markers, the interrupt time markers need a castbar toggle.
--      The page preview re-anchors its cast row only while a shake moves it.
--   6. The group portrait zoom offers the unit page's (and the runtime's)
--      100-300 % range.
--
-- Plain Lua 5.1 with the repo root and a flavor (a client matrix Suffix or
-- Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu_pages_client_gates_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "menu_pages_client_gates_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local function Join(list)
    local copy = {}
    for i = 1, #list do copy[i] = tostring(list[i]) end
    return table.concat(copy, ",")
end

---------------------------------------------------------------------------
-- Client facts this smoke expects, per flavor. They restate the client model
-- (Game/Shared/Initialize.lua) and Blizzard_FrameXMLBase's CLASS_SORT_ORDER
-- of each mirror branch, so a silent change to either fails here.
---------------------------------------------------------------------------
local ALL_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
local NINE_CLASSES = { "WARRIOR", "PALADIN", "PRIEST", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER" }
-- Class Resources extras by runtime owner (MSUF_CP_ExtraAuras.lua, MSUF_CP_ManaExtras.lua).
local MIDNIGHT_EXTRAS = { "showIgnorePain", "ignorePainTimeMarker", "showArcaneWindow", "arcaneWindowText",
    "arcaneWindowTextFrom", "arcaneWindowWarnSeconds", "arcaneWindowWarnLastGCD",
    "resourceExtraWidth", "resourceExtraHeight", "resourceExtraOffsetX", "resourceExtraOffsetY" }
-- The regeneration pause after spending Mana and the return pulses are game rules
-- of Classic Era, TBC and WoW Forever only.
local REGEN_EXTRAS = { "manaRegenPause", "manaGainPulse" }
local MIDNIGHT_COLORS = { "ignorePainColor", "arcaneWindowColor", "arcaneWindowSoulColor", "arcaneWindowWarnColor" }
local REGEN_COLORS = { "manaRegenPauseColor", "manaGainPulseColor" }
local BASIC_POWER_TYPES = "ALL,MANA,ENERGY,RAGE,FOCUS,COMBO_POINTS"
local EXPECTED = {
    Mainline = {
        copyTargets = "player,target,targettarget,focustarget,focus,boss,arena,pet,pettarget,all",
        classSortOrder = ALL_CLASSES,
        buffCoverage = false, friendlyBosses = true, mythicRaid = true,
        midnightExtras = true, regenExtras = false,
        powerTypes = "ALL,MANA,ENERGY,RAGE,FOCUS,RUNIC_POWER,COMBO_POINTS,HOLY_POWER,CHI,SOUL_SHARDS,"
            .. "ARCANE_CHARGES,ESSENCE,INSANITY,MAELSTROM,LUNAR_POWER",
        kickUnits = "Target,Focus,Boss,Arena", empowered = true,
    },
    Forever = {
        copyTargets = "player,target,targettarget,focustarget,focus,boss,pet,pettarget,all",
        classSortOrder = NINE_CLASSES,
        buffCoverage = true, friendlyBosses = true, mythicRaid = false,
        midnightExtras = false, regenExtras = true,
        powerTypes = BASIC_POWER_TYPES,
        kickUnits = "Target,Focus,Boss", empowered = false,
    },
    Vanilla = {
        copyTargets = "player,target,targettarget,pet,pettarget,all",
        classSortOrder = NINE_CLASSES,
        buffCoverage = false, friendlyBosses = false, mythicRaid = false,
        midnightExtras = false, regenExtras = true,
        powerTypes = BASIC_POWER_TYPES,
        kickUnits = "Target", empowered = false,
    },
    TBC = {
        copyTargets = "player,target,targettarget,focustarget,focus,arena,pet,pettarget,all",
        classSortOrder = NINE_CLASSES,
        buffCoverage = false, friendlyBosses = false, mythicRaid = false,
        midnightExtras = false, regenExtras = true,
        powerTypes = BASIC_POWER_TYPES,
        kickUnits = "Target,Focus,Arena", empowered = false,
    },
    Mists = {
        copyTargets = "player,target,targettarget,focustarget,focus,boss,arena,pet,pettarget,all",
        classSortOrder = { "WARRIOR", "DEATHKNIGHT", "PALADIN", "MONK", "PRIEST", "SHAMAN", "DRUID",
            "ROGUE", "MAGE", "WARLOCK", "HUNTER" },
        buffCoverage = false, friendlyBosses = true, mythicRaid = false,
        midnightExtras = false, regenExtras = false,
        powerTypes = "ALL,MANA,ENERGY,RAGE,FOCUS,RUNIC_POWER,COMBO_POINTS,HOLY_POWER,CHI,SOUL_SHARDS,ARCANE_CHARGES",
        kickUnits = "Target,Focus,Boss,Arena", empowered = false,
    },
}
local expected = Check(EXPECTED[flavor], "unknown flavor; state what its pages offer")

---------------------------------------------------------------------------
-- Boot the client and give the page builders the widget surface they use.
---------------------------------------------------------------------------
local world = World.New(root, flavor)
-- Blizzard constants the page reads, as this client defines them. Classic
-- RAID_CLASS_COLORS (Blizzard_SharedXML/Vanilla and TBC/ClassColors.lua) lists
-- Death Knight, Monk and Demon Hunter too; Midnight and WoW Forever build it
-- from a longer class list than CLASS_SORT_ORDER.
local env = world.env
env.CLASS_SORT_ORDER = expected.classSortOrder
env.RAID_CLASS_COLORS = {}
env.LOCALIZED_CLASS_NAMES_MALE = {}
for _, token in ipairs(ALL_CLASSES) do
    env.RAID_CLASS_COLORS[token] = { r = 1, g = 1, b = 1, colorStr = "ffffffff" }
    env.LOCALIZED_CLASS_NAMES_MALE[token] = token:sub(1, 1) .. token:sub(2):lower()
end
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

-- Widget calls the page widgets make that the shared stubs do not model. Added
-- after the boot, so the load itself runs on the same surface client_boot_smoke uses.
local Methods = world.widgets.Methods
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
local extraMethods = {
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    SetThumbTexture = function(self, value)
        if type(value) == "string" or type(value) == "number" then
            self.thumbTexture = self.thumbTexture or self:CreateTexture(nil, "OVERLAY")
            self.thumbTexture:SetTexture(value)
        else
            self.thumbTexture = value
        end
    end,
    GetThumbTexture = Fetch("thumbTexture"),
    SetValueStep = Store("valueStep"), SetObeyStepOnDrag = Store("obeyStepOnDrag"), SetStepsPerPage = Store("stepsPerPage"),
    SetAutoFocus = Store("autoFocus"), SetNumeric = Store("numeric"), SetMaxLetters = Store("maxLetters"),
    SetPropagateMouseWheel = Store("propagateMouseWheel"),
    SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
    HasFocus = function() return false end, ClearFocus = function() end, SetFocus = function() end,
    HighlightText = function() end, SetCursorPosition = function() end, GetCursorPosition = function() return 0 end,
    SetTextInsets = function() end,
}
for name, method in pairs(extraMethods) do
    if Methods[name] == nil then Methods[name] = method end
end
-- A native slider starts at its minimum; the stub leaves the value unset.
local StubGetValue = Methods.GetValue
Methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end

local MSUF = world.core
local M = Check(world.options.MSUF2, "Menu2 did not load")
local client = Check(MSUF.Client, "no MSUF.Client")
Check(type(M.BuildPageEntry) == "function", "Menu2 has no hidden page builder")
env.InCombatLockdown = function() return false end
env.MSUF_EnsureDB(true)
M.frame = M.frame or { IsShown = function() return true end }
M.cache = M.cache or {}
M.scrollChild = M.scrollChild or env.CreateFrame("Frame", nil, env.UIParent)

-- Build one page hidden, then run every queued lazy section build.
local function BuildPage(key)
    local entry = M.BuildPageEntry(key, true)
    world.widgets:RunTimers(20000)
    return Check(entry, "the " .. key .. " page did not build")
end

local Shared = Check(M.UnitSectionsShared, "the shared unit section helpers did not load")

-- Every bound control registers its command with the runtime control catalog,
-- by page: { [pageKey] = { [settingKey or controlId] = payload } }; the widget
-- of each payload is kept beside it.
local registered, widgetOf = {}, {}
local RegisterRuntimeControl = Check(M.RegisterRuntimeControl, "M.RegisterRuntimeControl is missing")
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and payload.pageKey then
        -- Search registration borrows a reusable payload; retain a snapshot.
        local captured = {}
        for field, value in pairs(payload) do captured[field] = value end
        local page = registered[captured.pageKey] or {}
        registered[captured.pageKey] = page
        if captured.settingKey then page[captured.settingKey] = captured end
        if captured.controlId then page[captured.controlId] = captured end
        widgetOf[captured] = widget
    end
    return RegisterRuntimeControl(widget, payload, ...)
end
-- What the page's enable gates last asked for (W.SetControlEnabled).
local function DesiredEnabled(payload)
    local widget = payload and widgetOf[payload]
    return widget ~= nil and widget._msuf2DesiredEnabled ~= false
end
local function RunRefreshers(entry)
    for _, refresh in ipairs(entry.refreshers or {}) do refresh() end
end

---------------------------------------------------------------------------
-- 1. Unit page: the top Copy To popup offers only frames this client has.
---------------------------------------------------------------------------
do
    local offered
    local MakeScopeCopyPopup = Check(Shared.MakeScopeCopyPopup, "MakeScopeCopyPopup is missing")
    Shared.MakeScopeCopyPopup = function(anchor, opts)
        if type(opts) == "table" and opts.controlDomain == "unit" then
            local list = {}
            for i, item in ipairs(opts.targets or {}) do
                list[i] = type(item) == "table" and (item.value or item.key) or item
            end
            offered = list
        end
        return MakeScopeCopyPopup(anchor, opts)
    end
    BuildPage("uf_player")
    Shared.MakeScopeCopyPopup = MakeScopeCopyPopup
    Check(offered ~= nil, "the Player page built no Copy To popup")
    Check(Join(offered) == expected.copyTargets, "the Player page's Copy To popup offers " .. Join(offered)
        .. ", expected " .. expected.copyTargets)
    for _, target in ipairs(offered) do
        Check(target == "all" or client.SupportsUnit(target),
            "the Copy To popup offers " .. target .. ", which MSUF.Client.SupportsUnit rejects")
    end
end

-- True when the caller two levels up (the widget constructor's caller) is the page file.
local function CalledFrom(file)
    local info = debug.getinfo(3, "S")
    return info ~= nil and info.source:gsub("\\", "/"):find(file, 1, true) ~= nil
end

return { world = world, env = env, M = M, MSUF = MSUF, BuildPage = BuildPage, RunRefreshers = RunRefreshers, registered = registered, widgetOf = widgetOf }

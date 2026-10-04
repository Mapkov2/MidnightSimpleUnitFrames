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
local W = Check(M.Widgets, "Menu2 widgets did not load")

---------------------------------------------------------------------------
-- 2. Group Layout > Sorting: one class priority row per class of this client.
-- 3. Group Layout sections and options that exist only on some clients.
---------------------------------------------------------------------------
do
    local rows
    local layoutToggles = {}
    local MakeDragSortRows = Check(Shared.MakeDragSortRows, "MakeDragSortRows is missing")
    Shared.MakeDragSortRows = function(parent, defs, opts)
        if type(opts) == "table" and opts.controlPath == "sorting.class_priority" then
            rows = {}
            for i, def in ipairs(defs or {}) do rows[i] = def.key end
        end
        return MakeDragSortRows(parent, defs, opts)
    end
    local ToggleAt = W.ToggleAt
    W.ToggleAt = function(parent, label, ...)
        if CalledFrom("Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua") then layoutToggles[label] = true end
        return ToggleAt(parent, label, ...)
    end
    local entry = BuildPage("gf_layout")
    Shared.MakeDragSortRows, W.ToggleAt = MakeDragSortRows, ToggleAt

    local sections = entry.sections or {}
    Check(sections.layout_advanced ~= nil and sections.sorting ~= nil, "Group Layout built no Group Layout or Sorting section")
    Check((sections.buff_coverage ~= nil) == expected.buffCoverage, "Buff coverage (Forever) is "
        .. (sections.buff_coverage and "built" or "not built") .. " although MSUF.Client.IsForever is " .. tostring(client.IsForever))
    Check((sections.friendly_bosses ~= nil) == expected.friendlyBosses, "Allied boss frames is "
        .. (sections.friendly_bosses and "built" or "not built") .. " although boss units are "
        .. (client.SupportsUnit("boss1") and "supported" or "unsupported"))
    Check(layoutToggles["Collapse empty preserved raid groups"] and layoutToggles["Center party frames while solo"],
        "the Group visibility card lost its shared options")
    Check((layoutToggles["Hide groups 5–8 in Mythic raids"] == true) == expected.mythicRaid,
        "Hide groups 5–8 in Mythic raids is " .. (layoutToggles["Hide groups 5–8 in Mythic raids"] and "built" or "not built")
        .. " although the Mythic Raid scope is " .. (expected.mythicRaid and "supported" or "unsupported"))
    Check(client.SupportsGroupKind("mythicraid") == expected.mythicRaid, "MSUF.Client.SupportsGroupKind(mythicraid) changed")

    Check(rows ~= nil, "Group Layout built no class priority rows")
    local want = {}
    for _, token in ipairs(expected.classSortOrder) do want[token] = true end
    local got = {}
    for _, token in ipairs(rows) do
        Check(want[token], "the class priority list offers " .. token .. ", a class this client does not have")
        Check(not got[token], "the class priority list offers " .. token .. " twice")
        got[token] = true
    end
    for token in pairs(want) do
        Check(got[token], "the class priority list misses " .. token)
    end
    -- The rows keep MSUF's own order, so saved class orders stay comparable.
    local position = {}
    for i, token in ipairs(ALL_CLASSES) do position[token] = i end
    for i = 2, #rows do
        Check(position[rows[i - 1]] < position[rows[i]], "the class priority rows lost MSUF's class order: " .. Join(rows))
    end
end

---------------------------------------------------------------------------
-- 4. Class Resources and Colors: extras only where their runtime draws them.
---------------------------------------------------------------------------
do
    -- The regeneration bars run on the native duration API. Every client has it
    -- (Blizzard_APIDocumentationGenerated/DurationUtilDocumentation.lua on each
    -- mirror branch); the harness does not model it.
    env.C_DurationUtil = setmetatable({ CreateDuration = function() return World.Stub end }, { __index = World.Stub })
    local regenSupported = Check(MSUF.CPBuilders and MSUF.CPBuilders.ManaRegenTimersSupported,
        "MSUF.CPBuilders.ManaRegenTimersSupported is missing")
    Check(regenSupported() == expected.regenExtras, "the regeneration timers are "
        .. (regenSupported() and "supported" or "unsupported") .. " on this client")
    BuildPage("classpower")
    BuildPage("opt_colors")
    local classpower = registered.classpower or {}
    local colors = registered.opt_colors or {}
    local function Expect(page, list, wanted, where)
        for _, key in ipairs(list) do
            local present = page["bars." .. key] ~= nil
            Check(present == wanted, where .. " " .. (present and "builds" or "misses") .. " bars." .. key)
        end
    end
    Expect(classpower, { "manaUpcomingCost" }, true, "Class Resources > Additional resources")
    Expect(classpower, MIDNIGHT_EXTRAS, expected.midnightExtras, "Class Resources > Additional resources")
    Expect(classpower, REGEN_EXTRAS, expected.regenExtras, "Class Resources > Additional resources")
    Expect(colors, { "manaCostColor" }, true, "Colors > Additional resource colors")
    Expect(colors, MIDNIGHT_COLORS, expected.midnightExtras, "Colors > Additional resource colors")
    Expect(colors, REGEN_COLORS, expected.regenExtras, "Colors > Additional resource colors")

    -- The bound dropdown keeps its entries (W.Dropdown: a list or a function).
    local mark = classpower["menu2.classpower.advanced.resource.extras.marks.resource"]
    local markValues = mark and widgetOf[mark] and widgetOf[mark].values
    if type(markValues) == "function" then markValues = markValues() end
    Check(type(markValues) == "table", "the resource mark has no Power type dropdown")
    local offered = {}
    for i, item in ipairs(markValues) do offered[i] = item.value end
    Check(Join(offered) == expected.powerTypes, "the resource mark offers power types " .. Join(offered)
        .. ", expected " .. expected.powerTypes)
end

---------------------------------------------------------------------------
-- 5. Castbars page: unit toggles, Empowered preview, dependent controls.
---------------------------------------------------------------------------
do
    -- The GCD Bar section exists only where the client drives the bar natively
    -- (C_Spell.GetSpellCooldownDuration plus StatusBar:SetTimerDuration) and, on
    -- WoW Forever, only while its spell data has the GCD spell (61304); give the
    -- harness all three so the section and its gates can be checked everywhere.
    env.C_Spell = setmetatable({ GetSpellCooldownDuration = function() return nil end,
        DoesSpellExist = function(spellID) return spellID == 61304 end },
        { __index = function() return World.Stub end })
    if Methods.SetTimerDuration == nil then Methods.SetTimerDuration = function() end end
    local general = env.MSUF_DB.general
    general.showGCDBar, general.gcdBarDetached = true, false
    general.castbarShowChannelTicks = false
    general.kickReadyShowTarget, general.kickReadyShowFocus = false, false
    general.kickReadyShowBoss, general.kickReadyShowArena = true, true
    local entry = BuildPage("opt_castbar")
    local castbar = registered.opt_castbar or {}

    local units = {}
    for _, unit in ipairs({ "Target", "Focus", "Boss", "Arena" }) do
        if castbar["general.kickReadyShow" .. unit] then units[#units + 1] = unit end
    end
    Check(Join(units) == expected.kickUnits, "the Interrupt Ready section shows castbar toggles for " .. Join(units)
        .. ", expected " .. expected.kickUnits)

    -- Gates as the page refresh applies them.
    local function Enabled(settingKey)
        local payload = Check(castbar[settingKey], "the castbar page has no control for " .. settingKey)
        return DesiredEnabled(payload)
    end
    local separate = { "gcdBarIdle", "gcdBarCombatOnly", "gcdBarWidth", "gcdBarHeight", "gcdBarX", "gcdBarY", "gcdBarOpacity" }
    RunRefreshers(entry)
    Check(Enabled("general.gcdBarDetached"), "Place GCD bar separately is locked while the GCD bar is on")
    for _, key in ipairs(separate) do
        Check(not Enabled("general." .. key), key .. " is editable while Place GCD bar separately is off")
    end
    Check(not Enabled("general.castbarAccentLastTick"), "Highlight last channel tick is editable without channel tick markers")
    -- Only the Boss and Arena toggles are on: where the client has neither castbar,
    -- nothing can show the indicator, so its time markers lock too.
    local indicatorOn = expected.kickUnits:find("Boss", 1, true) ~= nil or expected.kickUnits:find("Arena", 1, true) ~= nil
    for _, key in ipairs({ "kickReadyTimeMarker", "kickReadyTimeSegment" }) do
        Check(Enabled("general." .. key) == indicatorOn, key .. " is " .. (indicatorOn and "locked" or "editable")
            .. " with the castbar toggles " .. expected.kickUnits .. " (Boss and Arena on)")
    end
    general.gcdBarDetached, general.castbarShowChannelTicks = true, true
    general.kickReadyShowBoss, general.kickReadyShowArena = false, false
    RunRefreshers(entry)
    for _, key in ipairs(separate) do
        Check(Enabled("general." .. key), key .. " stays locked with the GCD bar placed separately")
    end
    Check(Enabled("general.castbarAccentLastTick"), "Highlight last channel tick stays locked with channel tick markers on")
    for _, key in ipairs({ "kickReadyTimeMarker", "kickReadyTimeSegment" }) do
        Check(not Enabled("general." .. key), key .. " is editable with every Interrupt Ready castbar toggle off")
    end
    general.showGCDBar = false
    RunRefreshers(entry)
    Check(not Enabled("general.gcdBarDetached") and not Enabled("general.gcdBarWidth"),
        "the separate GCD bar controls stay editable with the GCD bar off")

    -- The preview is built only when the page is shown, not by hidden builds.
    M._msuf2CastbarPreview = nil
    Check(M.BuildPageEntry("opt_castbar", false), "the castbar page did not build for display")
    world.widgets:RunTimers(20000)
    local preview = Check(M._msuf2CastbarPreview, "the castbar page built no preview")
    Check(preview.typeButtons and preview.typeButtons.normal and preview.typeButtons.channel,
        "the castbar preview lost its Normal or Channel cast type")
    Check((preview.typeButtons.empowered ~= nil) == expected.empowered, "the castbar preview "
        .. (preview.typeButtons.empowered and "offers" or "misses") .. " the Empowered cast type although "
        .. "MSUF.Client.HasEmpoweredCasts is " .. tostring(client.HasEmpoweredCasts))
    M.SetCastbarPreviewType("empowered")
    Check((M._msuf2CastbarPreviewType == "empowered") == expected.empowered,
        "selecting the Empowered preview type gave " .. tostring(M._msuf2CastbarPreviewType))
    M.SetCastbarPreviewType("normal")

    -- The preview's OnUpdate re-anchors its cast row only while a shake moves it.
    local row, box = preview.castRow, preview.castRowBase and preview.castRowBase.parent
    local onUpdate = Check(box and box:GetScript("OnUpdate"), "the castbar preview has no OnUpdate")
    local anchors = 0
    local ClearAllPoints = row.ClearAllPoints
    row.ClearAllPoints = function(self, ...) anchors = anchors + 1; return ClearAllPoints(self, ...) end
    for _ = 1, 10 do onUpdate(box, 0.016) end
    Check(anchors == 0, "an idle castbar preview re-anchored its cast row " .. anchors .. " times in 10 frames")
    preview.shakeStart, preview.shakeUntil, preview.shakeStrength = env.GetTime(), env.GetTime() + 1, 8
    for _ = 1, 3 do world.widgets:AdvanceTime(0.05); onUpdate(box, 0.05) end
    Check(anchors >= 2, "a shaking castbar preview did not move its cast row")
    world.widgets:AdvanceTime(2)
    onUpdate(box, 0.016)
    local settled = anchors
    for _ = 1, 5 do onUpdate(box, 0.016) end
    Check(anchors == settled, "the castbar preview kept re-anchoring after the shake ended")
    row.ClearAllPoints = ClearAllPoints
end

---------------------------------------------------------------------------
-- 6. One portrait zoom range: the group portrait offers what the unit page
-- and the portrait runtime use (100-300 %, Shared.NormalizePortraitZoom).
---------------------------------------------------------------------------
do
    -- The unit page binds settingKey <unit>.portraitZoom; the group portrait names
    -- the fixed Party key through searchSettingKeys.
    local function WritesZoom(payload)
        if type(payload.settingKey) == "string" and payload.settingKey:match("%.portraitZoom$") then return true end
        for _, key in ipairs(type(payload.searchSettingKeys) == "table" and payload.searchSettingKeys or {}) do
            if key:match("%.portraitZoom$") then return true end
        end
        return false
    end
    -- The range is the bound slider's own (Slider:GetMinMaxValues).
    local function ZoomRange(pageKey)
        for _, payload in pairs(registered[pageKey] or {}) do
            local slider = widgetOf[payload]
            if payload.kind == "slider" and WritesZoom(payload) and slider and slider.GetMinMaxValues then
                return slider:GetMinMaxValues()
            end
        end
    end
    local unitMin, unitMax = ZoomRange("uf_player")
    local groupMin, groupMax = ZoomRange("gf_layout")
    Check(unitMin == 100 and unitMax == 300, "the Player page portrait zoom is " .. tostring(unitMin) .. "-" .. tostring(unitMax))
    Check(groupMin == unitMin and groupMax == unitMax, "the group portrait zoom is " .. tostring(groupMin) .. "-"
        .. tostring(groupMax) .. ", the unit page offers " .. tostring(unitMin) .. "-" .. tostring(unitMax))
end

print(string.format("menu_pages_client_gates_smoke: ok (%s; Copy To %s; %d class priority rows; %d mark power types)",
    flavor, expected.copyTargets, #expected.classSortOrder, #expected.powerTypes:gsub("[^,]", "") + 1))

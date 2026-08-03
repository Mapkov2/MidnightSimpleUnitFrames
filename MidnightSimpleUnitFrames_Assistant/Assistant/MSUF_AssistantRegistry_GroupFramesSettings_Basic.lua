-- Assistant GroupFrames basic setting registration.
-- Split from the main settings registry to keep behavior toggles separate from layout/color registration.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterBasicSettings(ctx, scope)
    if type(ctx) ~= "table" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local GroupReverseFillExactAliases = ctx.GroupReverseFillExactAliases
    local GroupReverseFillBooleanAliases = ctx.GroupReverseFillBooleanAliases
    if type(AddAliasesForUnit) ~= "function"
        or type(RegisterGroupBoolean) ~= "function"
        or type(RegisterGroupNumber) ~= "function"
        or type(RegisterGroupEnum) ~= "function"
    then
        return
    end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "frames", "frames")
    AddAliasesForUnit(aliases, scope, "group frames", "gruppenframes")
    RegisterGroupBoolean(scope, "enabled", "enabled", "Frames Enabled", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade", "range fade")
    AddAliasesForUnit(aliases, scope, "range fading", "reichweite fade")
    RegisterGroupBoolean(scope, "rangeFade", "rangeFadeEnabled", "Range Fade", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show player", "spieler anzeigen")
    AddAliasesForUnit(aliases, scope, "player in group", "spieler in gruppe")
    AddAliasesForUnit(aliases, scope, "player in group frames")
    AddAliasesForUnit(aliases, scope, "show player in group")
    AddAliasesForUnit(aliases, scope, "show player in group frames")
    AddAliasesForUnit(aliases, scope, "show player when solo")
    AddAliasesForUnit(aliases, scope, "show player in group when solo")
    RegisterGroupBoolean(scope, "showPlayer", "showPlayer", "Show Player", true, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show solo", "solo anzeigen")
    AddAliasesForUnit(aliases, scope, "solo mode", "solo modus")
    AddAliasesForUnit(aliases, scope, "show while solo")
    AddAliasesForUnit(aliases, scope, "show frame while solo")
    AddAliasesForUnit(aliases, scope, "show frame when solo")
    AddAliasesForUnit(aliases, scope, "show group while solo")
    AddAliasesForUnit(aliases, scope, "show group frame while solo")
    AddAliasesForUnit(aliases, scope, "show group frame when solo")
    AddAliasesForUnit(aliases, scope, "show group frames while solo")
    AddAliasesForUnit(aliases, scope, "hide frame while solo")
    AddAliasesForUnit(aliases, scope, "hide frame when solo")
    AddAliasesForUnit(aliases, scope, "hide group frame while solo")
    AddAliasesForUnit(aliases, scope, "hide group frame when solo")
    RegisterGroupBoolean(scope, "showSolo", "showSolo", "Show while Solo", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "click casting", "klick zauber")
    AddAliasesForUnit(aliases, scope, "clique", "clique")
    RegisterGroupBoolean(scope, "clickCast", "clickCastEnabled", "Click Casting", true, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "blizzard fallback", "blizzard fallback")
    AddAliasesForUnit(aliases, scope, "fallback mode", "fallback modus")
    AddAliasesForUnit(aliases, scope, "disabled group frame behavior")
    AddAliasesForUnit(aliases, scope, "if this switch is off", "wenn dieser schalter aus ist")
    AddAliasesForUnit(aliases, scope, "when group frames are disabled", "wenn gruppenframes aus sind")
    AddAliasesForUnit(aliases, scope, "disabled group frame blizzard behavior", "blizzard verhalten wenn deaktiviert")
    AddAliasesForUnit(aliases, scope, "blizzard group frames when disabled", "blizzard gruppenframes wenn deaktiviert")
    AddAliasesForUnit(aliases, scope, "default group frames when disabled", "standard gruppenframes wenn deaktiviert")
    RegisterGroupEnum(scope, "blizzardFallbackMode", "blizzardFallbackMode", "Blizzard Fallback Mode", "AUTO", { "AUTO", "SHOW", "NONE" }, {
        auto = "AUTO",
        automatic = "AUTO",
        automatisch = "AUTO",
        default = "AUTO",
        standard = "AUTO",
        normal = "AUTO",
        blizzarddefault = "AUTO",
        ["blizzard default"] = "AUTO",
        ["blizzard standard"] = "AUTO",
        ["blizzard entscheidet"] = "AUTO",
        show = "SHOW",
        anzeigen = "SHOW",
        einblenden = "SHOW",
        sichtbar = "SHOW",
        force = "SHOW",
        erzwingen = "SHOW",
        forceblizzard = "SHOW",
        ["force blizzard"] = "SHOW",
        forceblizzardframes = "SHOW",
        ["blizzard anzeigen"] = "SHOW",
        ["blizzard einblenden"] = "SHOW",
        ["standardrahmen anzeigen"] = "SHOW",
        ["standard rahmen anzeigen"] = "SHOW",
        hide = "NONE",
        ausblenden = "NONE",
        verstecken = "NONE",
        none = "NONE",
        keiner = "NONE",
        keine = "NONE",
        nichts = "NONE",
        off = "NONE",
        aus = "NONE",
        hideall = "NONE",
        ["hide all"] = "NONE",
        ["alles ausblenden"] = "NONE",
        ["alle verstecken"] = "NONE",
        ["blizzard verstecken"] = "NONE",
        ["blizzard ausblenden"] = "NONE",
    }, "rebuild", aliases)

    --- One shared Blizzard frame, so the three scopes always carry the same value. It is
    --- still registered per scope because the Assistant addresses settings by
    --- gf_<scope>.<key>, but get/set are overridden to read and write all three rows at
    --- once -- a single-scope write would leave the value shadowed by whichever scope the
    --- engine reads first. The set also drives the tab directly: the generic group apply
    --- only refreshes MSUF's own frames, which this setting does not touch.
    local GroupDB = ctx.GroupDB
    local RAID_MANAGER_KINDS = { "party", "raid", "mythicraid" }
    local RAID_MANAGER_ALLOWED = { AUTO = true, SHOW = true, MOUSEOVER = true, HIDDEN = true }
    local function RaidManagerConf(kind)
        return type(GroupDB) == "function" and GroupDB(kind) or nil
    end
    local function ReadRaidManagerMode()
        for i = 1, #RAID_MANAGER_KINDS do
            local conf = RaidManagerConf(RAID_MANAGER_KINDS[i])
            local value = conf and conf.raidManagerMode
            if value ~= nil then
                --- "DEFAULT" is the pre-release spelling of AUTO and lands here as an
                --- unknown value, which is exactly the fallback we want.
                return RAID_MANAGER_ALLOWED[value] and value or "AUTO"
            end
        end
        return "AUTO"
    end
    local function WriteRaidManagerMode(value)
        if not RAID_MANAGER_ALLOWED[value] then value = "AUTO" end
        for i = 1, #RAID_MANAGER_KINDS do
            local conf = RaidManagerConf(RAID_MANAGER_KINDS[i])
            if conf then conf.raidManagerMode = value end
        end
        local gf = MSUF and MSUF.GF
        if gf and type(gf.ApplyBlizzardRaidManagerMode) == "function" then
            gf.ApplyBlizzardRaidManagerMode()
        end
    end

    aliases = {}
    AddAliasesForUnit(aliases, scope, "raid manager", "raid manager")
    AddAliasesForUnit(aliases, scope, "raid manager tab", "raid manager reiter")
    AddAliasesForUnit(aliases, scope, "blizzard raid manager", "blizzard raid manager")
    AddAliasesForUnit(aliases, scope, "raid tool", "raid werkzeug")
    AddAliasesForUnit(aliases, scope, "raid arrow", "raid pfeil")
    AddAliasesForUnit(aliases, scope, "raid manager arrow")
    AddAliasesForUnit(aliases, scope, "hide raid manager", "raid manager ausblenden")
    AddAliasesForUnit(aliases, scope, "raid manager visibility", "raid manager sichtbarkeit")
    if scope == "party" then
        aliases[#aliases + 1] = "party blizzard manager"
    elseif scope == "mythicraid" then
        aliases[#aliases + 1] = "mythic blizzard manager"
    end
    RegisterGroupEnum(scope, "raidManagerMode", "raidManagerMode", "Blizzard Raid Manager", "AUTO", { "AUTO", "SHOW", "MOUSEOVER", "HIDDEN" }, {
        auto = "AUTO",
        automatic = "AUTO",
        automatisch = "AUTO",
        default = "AUTO",
        standard = "AUTO",
        normal = "AUTO",
        blizzard = "AUTO",
        blizzarddefault = "AUTO",
        ["blizzard default"] = "AUTO",
        ["blizzard standard"] = "AUTO",
        show = "SHOW",
        anzeigen = "SHOW",
        einblenden = "SHOW",
        sichtbar = "SHOW",
        on = "SHOW",
        an = "SHOW",
        visible = "SHOW",
        alwaysvisible = "SHOW",
        ["always visible"] = "SHOW",
        ["immer sichtbar"] = "SHOW",
        ["immer anzeigen"] = "SHOW",
        mouseover = "MOUSEOVER",
        ["mouse over"] = "MOUSEOVER",
        hover = "MOUSEOVER",
        maus = "MOUSEOVER",
        mausueber = "MOUSEOVER",
        ["bei mouseover"] = "MOUSEOVER",
        ["show on mouseover"] = "MOUSEOVER",
        ["only on mouseover"] = "MOUSEOVER",
        ["nur bei mouseover"] = "MOUSEOVER",
        hidden = "HIDDEN",
        hide = "HIDDEN",
        off = "HIDDEN",
        aus = "HIDDEN",
        ausblenden = "HIDDEN",
        verstecken = "HIDDEN",
        versteckt = "HIDDEN",
        unsichtbar = "HIDDEN",
        alwayshidden = "HIDDEN",
        ["always hidden"] = "HIDDEN",
        ["immer ausblenden"] = "HIDDEN",
        ["immer versteckt"] = "HIDDEN",
    }, "visual", aliases, {
        get = function() return ReadRaidManagerMode() end,
        set = function(_, value) WriteRaidManagerMode(value) end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide during client scene", "client szene ausblenden")
    AddAliasesForUnit(aliases, scope, "hide in client scene")
    RegisterGroupBoolean(scope, "hideInClientScene", "hideInClientScene", "Hide During Client Scene", true, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide in housing", "housing ausblenden")
    AddAliasesForUnit(aliases, scope, "hide during housing")
    RegisterGroupBoolean(scope, "hideInHousing", "hideInHousing", "Hide in Housing", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline members", "offline spieler ausblenden")
    AddAliasesForUnit(aliases, scope, "offline members")
    RegisterGroupBoolean(scope, "hideOfflineEnabled", "hideOfflineEnabled", "Hide Offline Members", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline in combat", "offline im kampf ausblenden")
    AddAliasesForUnit(aliases, scope, "combat offline hide")
    RegisterGroupBoolean(scope, "hideOfflineInCombat", "hideOfflineInCombat", "Hide Offline in Combat", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide offline delay", "offline ausblenden verzoegerung")
    AddAliasesForUnit(aliases, scope, "hide offline after")
    AddAliasesForUnit(aliases, scope, "offline delay")
    RegisterGroupNumber(scope, "hideOfflineDelay", "hideOfflineDelay", "Hide Offline Delay", 0, 0, 120, 1, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "smooth fill", "weiche fuellung")
    AddAliasesForUnit(aliases, scope, "smooth health", "weiche leben")
    RegisterGroupBoolean(scope, "smoothFill", "smoothFill", "Smooth Health Fill", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "reverse fill", "fuellung umkehren")
    AddAliasesForUnit(aliases, scope, "reverse health fill", "leben umkehren")
    AddAliasesForUnit(aliases, scope, "fill backwards")
    AddAliasesForUnit(aliases, scope, "backwards fill")
    AddAliasesForUnit(aliases, scope, "right to left fill")
    AddAliasesForUnit(aliases, scope, "fill right to left")
    AddAliasesForUnit(aliases, scope, "normal fill")
    AddAliasesForUnit(aliases, scope, "left to right fill")
    RegisterGroupBoolean(scope, "reverseFill", "reverseFill", "Reverse Health Fill", false, "visual", aliases, {
        exactAliases = type(GroupReverseFillExactAliases) == "function" and GroupReverseFillExactAliases(scope) or nil,
        booleanAliases = type(GroupReverseFillBooleanAliases) == "function" and GroupReverseFillBooleanAliases(scope) or nil,
    })
end

-- Priority Frames inherit the active Party/Raid visual spec, so their public
-- Assistant surface is intentionally limited to the eight selection and
-- container controls exposed by Menu2. Character-local pins and keybindings
-- have different state owners and are not registered as profile settings.
function A.GroupFramesRegistry.RegisterPrioritySettings(ctx)
    if type(ctx) ~= "table" then return end

    local GroupDB = ctx.GroupDB
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    if type(GroupDB) ~= "function"
        or type(RegisterGroupBoolean) ~= "function"
        or type(RegisterGroupNumber) ~= "function"
        or type(RegisterGroupEnum) ~= "function"
    then
        return
    end

    local scope = "priority"
    local function Options(description, extra)
        local opts = {
            page = "gf_priority",
            description = description,
        }
        for key, value in pairs(extra or {}) do opts[key] = value end
        return opts
    end

    RegisterGroupBoolean(scope, "enabled", "enabled", "Enabled", false, "rebuild", {
        "priority frames", "priority frame", "pinned frames", "pinned frame",
        "enable priority frames", "disable priority frames", "show priority frames", "hide priority frames",
        "enable pinned frames", "disable pinned frames", "show pinned frames", "hide pinned frames",
        "extra group frames", "extra party frames", "extra raid frames",
    }, Options(
        "Shows a small duplicate strip for automatic tanks and manually pinned Party or Raid members.",
        {
            -- Normal group-frame enable toggles show a reload notice. Priority
            -- Frames own a combat-safe secure refresh and never need it.
            set = function(_, value) GroupDB(scope).enabled = value == true end,
        }
    ))

    RegisterGroupBoolean(scope, "autoTanks", "autoTanks", "Include Tanks Automatically", true, "rebuild", {
        "priority frame auto tanks", "priority frames auto tanks", "pinned frame auto tanks",
        "include tanks automatically in priority frames", "automatic tanks in priority frames",
        "auto pin tanks", "automatically pin tanks", "priority tank frames",
        "co tank priority frame", "co tank priority frames", "off tank priority frame", "off tank priority frames",
    }, Options(
        "Adds every current group member whose assigned group role is Tank before manual pins are filled."
    ))

    RegisterGroupNumber(scope, "maxFrames", "maxFrames", "Visible Slots", 5, 1, 5, 1, "rebuild", {
        "priority frame slots", "priority frames slots", "priority visible slots",
        "pinned frame slots", "pinned frames slots", "max priority frames", "maximum priority frames",
        "max pinned frames", "maximum pinned frames", "priority frame count", "priority frame limit",
    }, Options(
        "Sets the one-to-five visible Priority Frame limit; automatic tanks take slots before manual pins."
    ))

    RegisterGroupEnum(scope, "anchorMode", "anchorMode", "Placement", "RAID_RIGHT", {
        "RAID_RIGHT", "RAID_LEFT", "RAID_TOP", "RAID_BOTTOM", "FREE",
    }, {
        right = "RAID_RIGHT",
        ["right of group frames"] = "RAID_RIGHT",
        ["right of party frames"] = "RAID_RIGHT",
        ["right of raid frames"] = "RAID_RIGHT",
        left = "RAID_LEFT",
        ["left of group frames"] = "RAID_LEFT",
        ["left of party frames"] = "RAID_LEFT",
        ["left of raid frames"] = "RAID_LEFT",
        top = "RAID_TOP",
        above = "RAID_TOP",
        ["above group frames"] = "RAID_TOP",
        ["above party frames"] = "RAID_TOP",
        ["above raid frames"] = "RAID_TOP",
        bottom = "RAID_BOTTOM",
        below = "RAID_BOTTOM",
        ["below group frames"] = "RAID_BOTTOM",
        ["below party frames"] = "RAID_BOTTOM",
        ["below raid frames"] = "RAID_BOTTOM",
        free = "FREE",
        detached = "FREE",
        ["free position"] = "FREE",
    }, "geometry", {
        "priority frame placement", "priority frames placement", "pinned frame placement",
        "priority frame position mode", "priority strip placement", "attach priority frames",
    }, Options(
        "Attaches the strip beside the active group container or uses the dedicated free-position mover."
    ))

    RegisterGroupEnum(scope, "growth", "growth", "Growth", "DOWN", {
        "DOWN", "UP", "RIGHT", "LEFT",
    }, {
        down = "DOWN", downward = "DOWN", below = "DOWN",
        up = "UP", upward = "UP", above = "UP",
        right = "RIGHT", rightward = "RIGHT",
        left = "LEFT", leftward = "LEFT",
    }, "geometry", {
        "priority frame growth", "priority frames growth", "pinned frame growth",
        "priority strip growth", "priority frame growth direction", "priority strip direction",
    }, Options(
        "Controls the direction in which additional Priority Frames are laid out."
    ))

    RegisterGroupNumber(scope, "spacing", "spacing", "Spacing", 2, 0, 40, 1, "geometry", {
        "priority frame spacing", "priority frames spacing", "pinned frame spacing",
        "priority strip spacing", "space between priority frames", "gap between priority frames",
    }, Options(
        "Sets the pixel gap between frames inside the Priority Frame strip."
    ))

    RegisterGroupNumber(scope, "attachGap", "attachGap", "Attachment Gap", 8, 0, 100, 1, "geometry", {
        "priority frame attachment gap", "priority frames attachment gap", "priority attach gap",
        "priority strip attachment gap", "priority frame group gap", "distance from group frames",
    }, Options(
        "Sets the pixel distance between an attached Priority Frame strip and the active group container."
    ))

    RegisterGroupNumber(scope, "attachOffset", "attachOffset", "Alignment Offset", 0, -200, 200, 1, "geometry", {
        "priority frame alignment offset", "priority frames alignment offset", "priority attach offset",
        "priority strip alignment offset", "priority frame attached offset", "slide priority frames",
    }, Options(
        "Slides an attached Priority Frame strip along the edge of the active group container."
    ))
end

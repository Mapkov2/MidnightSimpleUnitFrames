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

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hide during client scene", "client szene ausblenden")
    AddAliasesForUnit(aliases, scope, "hide in client scene")
    RegisterGroupBoolean(scope, "hideInClientScene", "hideInClientScene", "Hide During Client Scene", true, "visual", aliases)

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
    RegisterGroupBoolean(scope, "smoothFill", "smoothFill", "Smooth Health Fill", true, "visual", aliases)

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

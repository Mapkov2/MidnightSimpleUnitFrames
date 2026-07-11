-- Assistant Global tooltip and module setting registry.
-- Loaded after MSUF_AssistantRegistry_Global.lua so the shared global context is available.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local ctx = A.GlobalRegistry and A.GlobalRegistry.TooltipModuleSettings
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
local GeneralDB = ctx.GeneralDB
local CallGlobal = ctx.CallGlobal

if not (Registry and type(Registry.RegisterSetting) == "function") then return end
if type(GeneralDB) ~= "function" or type(CallGlobal) ~= "function" then return end

local function RegisterTooltipModuleSettings()
    Registry:RegisterSetting({
        key = "general.unitTooltipProvider",
        label = "Unit Frame Tooltip Source",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "tooltipProvider",
        type = "enum",
        aliases = { "tooltip source", "unitframe tooltip source", "unit tooltip source", "group frame tooltip source", "game tooltip source", "gametooltip source", "tooltip quelle", "tooltip anbieter", "unitframe tooltip quelle", "einheiten tooltip quelle", "gruppen tooltip quelle", "game tooltip quelle", "msuf tooltip quelle" },
        values = { "GAME", "MSUF" },
        valueAliases = {
            game = "GAME",
            gametooltip = "GAME",
            blizzard = "GAME",
            addoncompatible = "GAME",
            ["addon compatible"] = "GAME",
            spiel = "GAME",
            standard = "GAME",
            ["blizzard tooltip"] = "GAME",
            ["game tooltip"] = "GAME",
            ["spiel tooltip"] = "GAME",
            msuf = "MSUF",
            custom = "MSUF",
            panel = "MSUF",
            ["msuf tooltip"] = "MSUF",
            ["eigenes panel"] = "MSUF",
            ["msuf panel"] = "MSUF",
        },
        get = function() return A.Workflow.ReadTooltipProvider() end,
        set = function(value) A.Workflow.WriteTooltipSettings(value, A.Workflow.ReadTooltipAnchor()) end,
        apply = function() A.Workflow.RefreshTooltipPreview() end,
        combatSafe = false,
    })

    Registry:RegisterSetting({
        key = "general.unitTooltipAnchor",
        label = "Unit Frame Tooltip Anchor",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "tooltipAnchor",
        type = "enum",
        aliases = { "tooltip anchor", "unitframe tooltip anchor", "unit tooltip anchor", "tooltip position", "tooltip location", "tooltip anker", "unitframe tooltip anker", "tooltip ort", "tooltip platzierung", "tooltip am cursor", "tooltip an der maus" },
        values = { "EXTERNAL", "FIXED", "CURSOR" },
        valueAliases = {
            external = "EXTERNAL",
            addon = "EXTERNAL",
            blizzard = "EXTERNAL",
            extern = "EXTERNAL",
            ["extern kontrolliert"] = "EXTERNAL",
            ["addon kontrolliert"] = "EXTERNAL",
            fixed = "FIXED",
            msuffixed = "FIXED",
            fest = "FIXED",
            fixiert = "FIXED",
            ["feste position"] = "FIXED",
            ["msuf fest"] = "FIXED",
            cursor = "CURSOR",
            mouse = "CURSOR",
            modern = "CURSOR",
            maus = "CURSOR",
            mauszeiger = "CURSOR",
            ["an der maus"] = "CURSOR",
            ["am cursor"] = "CURSOR",
        },
        get = function() return A.Workflow.ReadTooltipAnchor() end,
        set = function(value) A.Workflow.WriteTooltipSettings(A.Workflow.ReadTooltipProvider(), value) end,
        apply = function() A.Workflow.RefreshTooltipPreview() end,
        combatSafe = false,
    })

    Registry:RegisterSetting({
        key = "general.unitTooltipMode",
        label = "Show Unit Frame Tooltips",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "tooltipMode",
        type = "enum",
        aliases = { "show unitframe tooltips", "unitframe tooltips", "unit frame tooltips", "unit tooltips", "group frame tooltips", "tooltips", "show tooltips", "tooltip mode", "tooltip visibility", "tooltip anzeigen", "tooltips anzeigen", "tooltip modus", "tooltip sichtbarkeit", "unitframe tooltip anzeigen", "einheiten tooltips", "gruppen tooltips", "tooltip nur mit modifier", "tooltips nur mit modifier", "tooltip nur mit taste", "tooltips nur mit taste" },
        values = { "ALWAYS", "OOC", "MODIFIER", "NEVER" },
        valueAliases = {
            always = "ALWAYS",
            on = "ALWAYS",
            show = "ALWAYS",
            immer = "ALWAYS",
            anzeigen = "ALWAYS",
            sichtbar = "ALWAYS",
            ["immer anzeigen"] = "ALWAYS",
            ooc = "OOC",
            outofcombat = "OOC",
            ["out of combat"] = "OOC",
            ausserhalbkampf = "OOC",
            ["ausserhalb kampf"] = "OOC",
            ["ausserhalb des kampfes"] = "OOC",
            ["nicht im kampf"] = "OOC",
            modifier = "MODIFIER",
            key = "MODIFIER",
            alt = "MODIFIER",
            ctrl = "MODIFIER",
            shift = "MODIFIER",
            ["only with alt"] = "MODIFIER",
            ["only with ctrl"] = "MODIFIER",
            ["only with control"] = "MODIFIER",
            ["only with shift"] = "MODIFIER",
            ["with alt"] = "MODIFIER",
            ["with ctrl"] = "MODIFIER",
            ["with control"] = "MODIFIER",
            ["with shift"] = "MODIFIER",
            ["modifier key"] = "MODIFIER",
            taste = "MODIFIER",
            ["mit taste"] = "MODIFIER",
            ["modifier taste"] = "MODIFIER",
            ["nur mit alt"] = "MODIFIER",
            ["nur mit ctrl"] = "MODIFIER",
            ["nur mit strg"] = "MODIFIER",
            ["nur mit shift"] = "MODIFIER",
            ["nur mit umschalt"] = "MODIFIER",
            never = "NEVER",
            off = "NEVER",
            hide = "NEVER",
            disable = "NEVER",
            nie = "NEVER",
            niemals = "NEVER",
            aus = "NEVER",
            ausblenden = "NEVER",
            deaktivieren = "NEVER",
        },
        get = function() return A.Workflow.NormalizeTooltipMode(GeneralDB().unitTooltipMode) end,
        set = function(value) A.Workflow.WriteTooltipBehavior(value, GeneralDB().unitTooltipModifier or "ALT") end,
        apply = function() A.Workflow.RefreshTooltipPreview() end,
        combatSafe = false,
    })

    Registry:RegisterSetting({
        key = "general.unitTooltipModifier",
        label = "Tooltip Modifier Key",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "tooltipModifier",
        type = "enum",
        aliases = { "tooltip modifier", "tooltip modifier key", "unit tooltip modifier", "unitframe tooltip modifier", "tooltip taste", "tooltip modifier taste", "tooltip hotkey", "tooltip aktivierungstaste", "unitframe tooltip taste" },
        values = { "ALT", "CTRL", "SHIFT" },
        valueAliases = {
            alt = "ALT",
            option = "ALT",
            ["alt taste"] = "ALT",
            ctrl = "CTRL",
            control = "CTRL",
            strg = "CTRL",
            steuerung = "CTRL",
            ["strg taste"] = "CTRL",
            shift = "SHIFT",
            umschalt = "SHIFT",
            umschalttaste = "SHIFT",
            ["shift taste"] = "SHIFT",
        },
        get = function() return A.Workflow.NormalizeTooltipModifier(GeneralDB().unitTooltipModifier) end,
        set = function(value) A.Workflow.WriteTooltipBehavior(GeneralDB().unitTooltipMode or "MODIFIER", value) end,
        apply = function() A.Workflow.RefreshTooltipPreview() end,
        combatSafe = false,
    })

    Registry:RegisterSetting({
        key = "general.styleEnabled",
        label = "MSUF Style Module",
        category = "Modules / Style",
        unit = "global",
        frameType = "modules",
        attribute = "styleEnabled",
        type = "boolean",
        aliases = { "msuf style", "msuf style module", "midnight style", "midnight design", "style module", "module style", "style", "skin", "skins", "msuf skin", "msuf stil", "midnight stil", "stil modul", "style modul", "design modul", "msuf design", "msuf design modul", "midnight design modul", "skin modul", "modernes design" },
        get = function() return A.Workflow.ModuleStyleEnabled() end,
        set = function(value) A.Workflow.SetModuleStyleEnabled(value and true or false) end,
        apply = function() CallGlobal("MSUF_ApplyModules") end,
        combatSafe = true,
    })

    Registry:RegisterSetting({
        key = "general.dropdownStyleMode",
        label = "Dropdown Style",
        category = "Modules / Style",
        unit = "global",
        frameType = "modules",
        attribute = "dropdownStyle",
        type = "enum",
        aliases = { "dropdown style", "dropdown style mode", "dropdown module style", "menu dropdown style", "dropdown skin", "dropdown design", "dropdown stil", "menue dropdown stil", "menue dropdown design", "dropdown modus", "dropdown aussehen", "auswahlmenue stil", "auswahl menu stil", "menue auswahl stil" },
        values = { "msuf", "old" },
        valueAliases = {
            msuf = "msuf",
            modern = "msuf",
            superellipse = "msuf",
            midnight = "msuf",
            neu = "msuf",
            aktuell = "msuf",
            modernisiert = "msuf",
            old = "old",
            legacy = "old",
            blizzard = "old",
            classic = "old",
            alt = "old",
            klassisch = "old",
            standard = "old",
        },
        get = function() return A.Workflow.DropdownStyleMode() end,
        set = function(value) A.Workflow.SetDropdownStyleMode(value) end,
        apply = function() end,
        combatSafe = true,
    })
end

RegisterTooltipModuleSettings()

-- Assistant Gameplay combat-crosshair setting and action registry.
-- Loaded before MSUF_AssistantRegistry_Gameplay.lua; the gameplay registry passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GameplayRegistry = A.GameplayRegistry or {}

function A.GameplayRegistry.RegisterCrosshairSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Menu = ctx.Menu or M
    local RegisterGameplayBoolean = ctx.RegisterGameplayBoolean
    local RegisterGameplayNumber = ctx.RegisterGameplayNumber
    local ApplyGameplay = ctx.ApplyGameplay
    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(RegisterGameplayBoolean) ~= "function" or type(RegisterGameplayNumber) ~= "function" then return end
    if type(ApplyGameplay) ~= "function" then return end

    RegisterGameplayBoolean("enableCombatCrosshair", "enabled", "Combat Crosshair", false, {
        "combat crosshair enabled", "crosshair enabled", "fadenkreuz enabled",
        "kampf fadenkreuz", "fadenkreuz anzeigen", "combat fadenkreuz",
    }, {
        category = "Gameplay / Combat Crosshair",
        frameType = "combatCrosshair",
        reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR",
        matchLabel = false,
    })
    RegisterGameplayBoolean("enableCombatCrosshairMeleeRangeColor", "rangeColor", "Combat Crosshair Melee Range Color", false, {
        "crosshair melee range color", "combat crosshair melee range color", "crosshair range color", "crosshair in range color mode",
        "fadenkreuz reichweitenfarbe", "fadenkreuz reichweite farbe", "fadenkreuz nahkampf reichweite farbe", "fadenkreuz farbe nach reichweite",
    }, {
        category = "Gameplay / Combat Crosshair",
        frameType = "combatCrosshair",
        reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_RANGE_COLOR",
    })
    RegisterGameplayNumber("crosshairThickness", "thickness", "Combat Crosshair Thickness", 3, 1, 12, {
        "crosshair thickness", "combat crosshair thickness", "fadenkreuz thickness",
        "fadenkreuz dicke", "fadenkreuz staerke", "fadenkreuz strichstaerke",
    }, {
        category = "Gameplay / Combat Crosshair",
        frameType = "combatCrosshair",
        reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_THICKNESS",
    })
    RegisterGameplayNumber("crosshairSize", "size", "Combat Crosshair Size", 40, 20, 120, {
        "crosshair size", "combat crosshair size", "fadenkreuz size",
        "fadenkreuz groesse", "fadenkreuz grosse",
    }, {
        category = "Gameplay / Combat Crosshair",
        frameType = "combatCrosshair",
        reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_SIZE",
        step = 2,
    })
    RegisterGameplayNumber("nameplateMeleeSpellID", "spellID", "Crosshair Melee Range Spell", 0, 0, 999999, {
        "melee range spell", "crosshair melee spell", "crosshair spell id", "combat crosshair spell id", "range check spell",
        "fadenkreuz zauber", "fadenkreuz zauber id", "nahkampf zauber", "nahkampf reichweiten zauber", "reichweiten zauber",
    }, {
        category = "Gameplay / Combat Crosshair",
        frameType = "combatCrosshair",
        reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_SPELL",
    })
    Registry:RegisterAction({
        key = "set_crosshair_melee_spell",
        label = "Set Crosshair Melee Range Spell",
        type = "gameplay",
        aliases = {
            "set crosshair melee range spell",
            "set crosshair spell",
            "set melee range spell",
            "set range check spell",
            "fadenkreuz zauber setzen",
            "fadenkreuz zauber auf",
            "nahkampf reichweiten zauber setzen",
            "reichweiten zauber setzen",
        },
        combatSafe = false,
        captureSnapshot = true,
        run = function(args)
            local value = args and args.value
            if type(value) ~= "string" and type(value) ~= "number" then return false, "Which spell do you want me to use? A spell ID, spell link, or full spell name is enough." end
            if not (Menu and type(Menu.SetGameplayMeleeSpellID) == "function") then return false, "Open Gameplay first so I can set the melee spell." end
            local spellID = tonumber(Menu.SetGameplayMeleeSpellID(value)) or 0
            local requestedZero = tostring(value or ""):match("^%s*0%s*$") ~= nil
            if spellID <= 0 and not requestedZero then return false, "I don't recognize that melee range spell yet. A spell ID or full spell name is enough." end
            ApplyGameplay("MSUF_ASSISTANT_COMBAT_CROSSHAIR_SPELL")
            if spellID <= 0 then return true, "Done. Cleared the Crosshair melee range spell." end
            local name = Menu.GetGameplaySpellName and Menu.GetGameplaySpellName(spellID)
            if name and name ~= "" then return true, "Done. Set the Crosshair melee range spell to " .. name .. " (" .. tostring(spellID) .. ")." end
            return true, "Done. Set the Crosshair melee range spell to " .. tostring(spellID) .. "."
        end,
    })
    RegisterGameplayBoolean("meleeSpellPerClass", "perClass", "Crosshair Spell Per Class", false, {
        "crosshair spell per class", "melee range spell per class", "store melee spell per class",
        "fadenkreuz zauber pro klasse", "nahkampf zauber pro klasse",
    }, {
        category = "Gameplay / Combat Crosshair",
        frameType = "combatCrosshair",
        reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_SPELL_CLASS",
    })
    RegisterGameplayBoolean("meleeSpellPerSpec", "perSpec", "Crosshair Spell Per Spec", false, {
        "crosshair spell per spec", "melee range spell per spec", "store melee spell per spec",
        "fadenkreuz zauber pro spec", "fadenkreuz zauber pro spezialisierung", "nahkampf zauber pro spec",
    }, {
        category = "Gameplay / Combat Crosshair",
        frameType = "combatCrosshair",
        reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_SPELL_SPEC",
    })
end

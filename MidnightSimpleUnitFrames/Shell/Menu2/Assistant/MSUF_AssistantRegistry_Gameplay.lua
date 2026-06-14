-- Assistant Gameplay registry: exposes optional gameplay helper controls and diagnostics.
-- Actions should call feature-owned helpers so parser metadata does not own runtime state.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Gameplay registry domain.
-- Covers combat timer/crosshair, totems/statues, and related gameplay helpers. These settings
-- bridge into gameplay runtimes instead of editing frames directly from the assistant.
local Registry = C.Registry
local RegisterGameplayBoolean = C.RegisterGameplayBoolean
local RegisterGameplayNumber = C.RegisterGameplayNumber
local RegisterGameplayEnum = C.RegisterGameplayEnum
local RegisterGameplayString = C.RegisterGameplayString
local GameplayAliases = C.GameplayAliases
local GameplayDB = C.GameplayDB
local ApplyGameplay = C.ApplyGameplay

local GAMEPLAY_ANCHOR_VALUES = { "none", "player", "target", "focus" }
local GAMEPLAY_ANCHOR_ALIASES = {
    none = "none",
    off = "none",
    noanchor = "none",
    player = "player",
    target = "target",
    focus = "focus",
}
local FRAME_ANCHOR_VALUES = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local FRAME_ANCHOR_ALIASES = {
    topleft = "TOPLEFT",
    ["top left"] = "TOPLEFT",
    top = "TOP",
    topright = "TOPRIGHT",
    ["top right"] = "TOPRIGHT",
    left = "LEFT",
    center = "CENTER",
    centre = "CENTER",
    right = "RIGHT",
    bottomleft = "BOTTOMLEFT",
    ["bottom left"] = "BOTTOMLEFT",
    bottom = "BOTTOM",
    bottomright = "BOTTOMRIGHT",
    ["bottom right"] = "BOTTOMRIGHT",
}

RegisterGameplayBoolean("enableCombatTimer", "enabled", "Combat Timer", false, {
    "combat timer enabled", "combat timer display",
}, {
    category = "Gameplay / Combat Timer",
    frameType = "combatTimer",
    reason = "MSUF_ASSISTANT_COMBAT_TIMER",
    matchLabel = false,
})
RegisterGameplayEnum("combatTimerAnchor", "anchor", "Combat Timer Anchor", "none", GAMEPLAY_ANCHOR_VALUES, {
    "combat timer anchor", "combat timer attach to", "combat timer anchor frame",
}, {
    category = "Gameplay / Combat Timer",
    frameType = "combatTimer",
    reason = "MSUF_ASSISTANT_COMBAT_TIMER_ANCHOR",
    valueAliases = GAMEPLAY_ANCHOR_ALIASES,
})
RegisterGameplayNumber("combatFontSize", "fontSize", "Combat Timer Size", 24, 10, 64, {
    "combat timer size", "combat timer font size", "combat timer text size",
}, {
    category = "Gameplay / Combat Timer",
    frameType = "combatTimer",
    reason = "MSUF_ASSISTANT_COMBAT_TIMER_SIZE",
})
RegisterGameplayBoolean("lockCombatTimer", "locked", "Combat Timer Lock Position", false, {
    "combat timer lock", "lock combat timer", "combat timer locked",
}, {
    category = "Gameplay / Combat Timer",
    frameType = "combatTimer",
    reason = "MSUF_ASSISTANT_COMBAT_TIMER_LOCK",
})
RegisterGameplayBoolean("combatTimerClickThrough", "clickThrough", "Combat Timer Click Through", true, {
    "combat timer click through", "combat timer click-through", "combat timer mouse clicks", "combat timer mouse input",
}, {
    category = "Gameplay / Combat Timer",
    frameType = "combatTimer",
    reason = "MSUF_ASSISTANT_COMBAT_TIMER_CLICK_THROUGH",
})
RegisterGameplayNumber("combatOffsetX", "offsetX", "Combat Timer Offset X", 0, -800, 800, {
    "combat timer x", "combat timer x offset", "combat timer horizontal offset",
}, {
    category = "Gameplay / Combat Timer",
    frameType = "combatTimer",
    reason = "MSUF_ASSISTANT_COMBAT_TIMER_X",
})
RegisterGameplayNumber("combatOffsetY", "offsetY", "Combat Timer Offset Y", -200, -800, 800, {
    "combat timer y", "combat timer y offset", "combat timer vertical offset",
}, {
    category = "Gameplay / Combat Timer",
    frameType = "combatTimer",
    reason = "MSUF_ASSISTANT_COMBAT_TIMER_Y",
})

RegisterGameplayBoolean("enableCombatStateText", "enabled", "Combat Enter Leave Text", false, {
    "combat state text enabled", "combat enter leave text", "combat enter text display", "combat leave text display",
}, {
    category = "Gameplay / Combat Enter Leave",
    frameType = "combatState",
    reason = "MSUF_ASSISTANT_COMBAT_STATE",
    matchLabel = false,
})
RegisterGameplayBoolean("lockCombatState", "locked", "Combat Enter Leave Lock Position", false, {
    "combat state lock", "lock combat state", "combat enter leave lock", "lock combat enter leave text",
}, {
    category = "Gameplay / Combat Enter Leave",
    frameType = "combatState",
    reason = "MSUF_ASSISTANT_COMBAT_STATE_LOCK",
})
RegisterGameplayString("combatStateEnterText", "enterText", "Combat Enter Text", "+Combat", {
    "combat enter text", "enter combat text", "combat state enter text",
}, {
    category = "Gameplay / Combat Enter Leave",
    frameType = "combatState",
    reason = "MSUF_ASSISTANT_COMBAT_STATE_ENTER_TEXT",
})
RegisterGameplayString("combatStateLeaveText", "leaveText", "Combat Leave Text", "-Combat", {
    "combat leave text", "leave combat text", "combat state leave text",
}, {
    category = "Gameplay / Combat Enter Leave",
    frameType = "combatState",
    reason = "MSUF_ASSISTANT_COMBAT_STATE_LEAVE_TEXT",
})
RegisterGameplayNumber("combatStateFontSize", "fontSize", "Combat Enter Leave Text Size", 24, 10, 64, {
    "combat state text size", "combat enter leave text size", "combat state font size",
}, {
    category = "Gameplay / Combat Enter Leave",
    frameType = "combatState",
    reason = "MSUF_ASSISTANT_COMBAT_STATE_SIZE",
})
RegisterGameplayNumber("combatStateDuration", "duration", "Combat Enter Leave Duration", 1.5, 0.5, 5.0, {
    "combat state duration", "combat enter leave duration", "combat text duration",
}, {
    category = "Gameplay / Combat Enter Leave",
    frameType = "combatState",
    reason = "MSUF_ASSISTANT_COMBAT_STATE_DURATION",
    step = 0.5,
})
RegisterGameplayNumber("combatStateOffsetX", "offsetX", "Combat Enter Leave Offset X", 0, -800, 800, {
    "combat state x", "combat state x offset", "combat enter leave x", "combat text x offset",
}, {
    category = "Gameplay / Combat Enter Leave",
    frameType = "combatState",
    reason = "MSUF_ASSISTANT_COMBAT_STATE_X",
})
RegisterGameplayNumber("combatStateOffsetY", "offsetY", "Combat Enter Leave Offset Y", 80, -800, 800, {
    "combat state y", "combat state y offset", "combat enter leave y", "combat text y offset",
}, {
    category = "Gameplay / Combat Enter Leave",
    frameType = "combatState",
    reason = "MSUF_ASSISTANT_COMBAT_STATE_Y",
})

RegisterGameplayBoolean("enablePlayerTotems", "enabled", "Blizzard Totem Frame", false, {
    "blizzard totem frame enabled", "player totem frame enabled", "totem frame enabled", "statue frame enabled",
}, {
    category = "Gameplay / Totem Frame",
    frameType = "playerTotems",
    reason = "MSUF_ASSISTANT_PLAYER_TOTEMS",
    matchLabel = false,
})
RegisterGameplayNumber("playerTotemsIconSize", "size", "Totem Frame Icon Size", 24, 8, 64, GameplayAliases("totem frame", "icon size", "blizzard totem frame icon size", "statue frame icon size"), {
    category = "Gameplay / Totem Frame",
    frameType = "playerTotems",
    reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_SIZE",
})
RegisterGameplayNumber("playerTotemsOffsetX", "offsetX", "Totem Frame Offset X", 0, -200, 200, {
    "totem frame x", "totem frame x offset", "blizzard totem frame x", "statue frame x",
}, {
    category = "Gameplay / Totem Frame",
    frameType = "playerTotems",
    reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_X",
})
RegisterGameplayNumber("playerTotemsOffsetY", "offsetY", "Totem Frame Offset Y", -6, -200, 200, {
    "totem frame y", "totem frame y offset", "blizzard totem frame y", "statue frame y",
}, {
    category = "Gameplay / Totem Frame",
    frameType = "playerTotems",
    reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_Y",
})
RegisterGameplayEnum("playerTotemsAnchorFrom", "anchorFrom", "Totem Frame Anchor From", "TOPLEFT", FRAME_ANCHOR_VALUES, {
    "totem frame anchor from", "totem frame from", "blizzard totem frame anchor from",
}, {
    category = "Gameplay / Totem Frame",
    frameType = "playerTotems",
    reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_ANCHOR_FROM",
    valueAliases = FRAME_ANCHOR_ALIASES,
})
RegisterGameplayEnum("playerTotemsAnchorTo", "anchorTo", "Totem Frame Anchor To", "BOTTOMLEFT", FRAME_ANCHOR_VALUES, {
    "totem frame anchor to", "totem frame to", "blizzard totem frame anchor to",
}, {
    category = "Gameplay / Totem Frame",
    frameType = "playerTotems",
    reason = "MSUF_ASSISTANT_PLAYER_TOTEMS_ANCHOR_TO",
    valueAliases = FRAME_ANCHOR_ALIASES,
})

RegisterGameplayBoolean("enableFirstDanceTimer", "enabled", "First Dance Tracker", false, {
    "first dance tracker enabled", "first dance timer enabled", "rogue first dance tracker",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE",
    matchLabel = false,
})
RegisterGameplayBoolean("lockFirstDance", "locked", "First Dance Lock Position", false, {
    "first dance lock", "lock first dance", "first dance locked",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_LOCK",
})
RegisterGameplayBoolean("firstDanceClickThrough", "clickThrough", "First Dance Click Through", true, {
    "first dance click through", "first dance click-through", "first dance mouse input",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_CLICK_THROUGH",
})
RegisterGameplayBoolean("firstDanceShowIcon", "icon", "First Dance Icon Mode", true, {
    "first dance icon", "first dance icon mode", "first dance cooldown swipe",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_ICON",
})
RegisterGameplayBoolean("firstDanceShowReady", "showReady", "First Dance Show Ready", true, {
    "first dance show ready", "first dance ready visible", "first dance keep visible",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_READY",
})
RegisterGameplayNumber("firstDanceIconSize", "size", "First Dance Icon Size", 40, 16, 96, {
    "first dance size", "first dance icon size", "first dance tracker size",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_SIZE",
})
RegisterGameplayNumber("firstDanceOffsetX", "offsetX", "First Dance Offset X", 0, -800, 800, {
    "first dance x", "first dance x offset", "first dance tracker x",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_X",
})
RegisterGameplayNumber("firstDanceOffsetY", "offsetY", "First Dance Offset Y", 80, -800, 800, {
    "first dance y", "first dance y offset", "first dance tracker y",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_Y",
})

RegisterGameplayBoolean("enableCombatCrosshair", "enabled", "Combat Crosshair", false, {
    "combat crosshair enabled", "crosshair enabled", "fadenkreuz enabled",
}, {
    category = "Gameplay / Combat Crosshair",
    frameType = "combatCrosshair",
    reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR",
    matchLabel = false,
})
RegisterGameplayBoolean("enableCombatCrosshairMeleeRangeColor", "rangeColor", "Combat Crosshair Melee Range Color", false, {
    "crosshair melee range color", "combat crosshair melee range color", "crosshair range color", "crosshair in range color mode",
}, {
    category = "Gameplay / Combat Crosshair",
    frameType = "combatCrosshair",
    reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_RANGE_COLOR",
})
RegisterGameplayNumber("crosshairThickness", "thickness", "Combat Crosshair Thickness", 3, 1, 12, {
    "crosshair thickness", "combat crosshair thickness", "fadenkreuz thickness",
}, {
    category = "Gameplay / Combat Crosshair",
    frameType = "combatCrosshair",
    reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_THICKNESS",
})
RegisterGameplayNumber("crosshairSize", "size", "Combat Crosshair Size", 40, 20, 120, {
    "crosshair size", "combat crosshair size", "fadenkreuz size",
}, {
    category = "Gameplay / Combat Crosshair",
    frameType = "combatCrosshair",
    reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_SIZE",
    step = 2,
})
RegisterGameplayNumber("nameplateMeleeSpellID", "spellID", "Crosshair Melee Range Spell", 0, 0, 999999, {
    "melee range spell", "crosshair melee spell", "crosshair spell id", "combat crosshair spell id", "range check spell",
}, {
    category = "Gameplay / Combat Crosshair",
    frameType = "combatCrosshair",
    reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_SPELL",
})
Registry:RegisterAction({
    key = "set_crosshair_melee_spell",
    label = "Set Crosshair Melee Range Spell",
    type = "gameplay",
    combatSafe = false,
    captureSnapshot = true,
    run = function(args)
        local value = args and args.value
        if type(value) ~= "string" and type(value) ~= "number" then return false, "I need a spell ID, spell link, or resolvable spell name." end
        if not (M and type(M.SetGameplayMeleeSpellID) == "function") then return false, "Gameplay spell input helpers are not loaded yet." end
        local spellID = tonumber(M.SetGameplayMeleeSpellID(value)) or 0
        local requestedZero = tostring(value or ""):match("^%s*0%s*$") ~= nil
        if spellID <= 0 and not requestedZero then return false, "That melee range spell could not be resolved." end
        ApplyGameplay("MSUF_ASSISTANT_COMBAT_CROSSHAIR_SPELL")
        if spellID <= 0 then return true, "Done. Cleared the Crosshair melee range spell." end
        local name = M.GetGameplaySpellName and M.GetGameplaySpellName(spellID)
        if name and name ~= "" then return true, "Done. Set the Crosshair melee range spell to " .. name .. " (" .. tostring(spellID) .. ")." end
        return true, "Done. Set the Crosshair melee range spell to " .. tostring(spellID) .. "."
    end,
})
RegisterGameplayBoolean("meleeSpellPerClass", "perClass", "Crosshair Spell Per Class", false, {
    "crosshair spell per class", "melee range spell per class", "store melee spell per class",
}, {
    category = "Gameplay / Combat Crosshair",
    frameType = "combatCrosshair",
    reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_SPELL_CLASS",
})
RegisterGameplayBoolean("meleeSpellPerSpec", "perSpec", "Crosshair Spell Per Spec", false, {
    "crosshair spell per spec", "melee range spell per spec", "store melee spell per spec",
}, {
    category = "Gameplay / Combat Crosshair",
    frameType = "combatCrosshair",
    reason = "MSUF_ASSISTANT_COMBAT_CROSSHAIR_SPELL_SPEC",
})

Registry:RegisterAction({
    key = "preview_player_totems",
    label = "Preview Totem Frame",
    type = "gameplay",
    combatSafe = false,
    run = function()
        local fn = MSUF and MSUF.MSUF_PlayerTotems_TogglePreview
        if type(fn) ~= "function" then return false, "TotemFrame preview is not available right now." end
        fn()
        return true, "Done. Toggled the TotemFrame preview."
    end,
})

Registry:RegisterAction({
    key = "reset_player_totems_layout",
    label = "Reset Totem Frame Layout",
    type = "gameplay",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        local g = GameplayDB()
        g.playerTotemsIconSize = 24
        g.playerTotemsOffsetX = 0
        g.playerTotemsOffsetY = -6
        g.playerTotemsAnchorFrom = "TOPLEFT"
        g.playerTotemsAnchorTo = "BOTTOMLEFT"
        ApplyGameplay("MSUF_ASSISTANT_PLAYER_TOTEMS_RESET")
        return true, "Done. Reset TotemFrame layout."
    end,
})

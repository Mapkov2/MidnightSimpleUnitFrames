-- Review F16: Edit Mode shell strings exist in all twelve locale packs and are
-- translated in the ten non-English ones, including the arena-together label
-- picked by a conditional expression (scanners miss it) and the external
-- popup's settings button, which used to concatenate untranslatable pieces.
-- Quality program A-C6 (C6.4, C6.5): the HUD settings tip and provider anchor
-- label, the Edit Mode history labels and the Classic route to Blizzard's Edit
-- Mode are format strings over translated pieces, never English concatenation.
-- W-C6: so is the HUD Reset status ("Reset %s"), checked in German at run time.
-- Re-review R7 (Edit Mode): the toolbar's Motion and Settings buttons, the
-- preview animation status, the Exit, Undo and Redo tips, the copied-size
-- status and the one Edit Mode combat message (Kernel/MSUF_Util.lua) exist in
-- every pack; the unit, castbar and aura popup titles and the history labels
-- are whole-sentence keys ("%s Frame", "Move %s"), so each language orders
-- the words itself. The German Move history label is checked at run time.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local KEYS = {
    "Edit Arena 1-3 together", "Edit Arena 1-5 together", "Sync class", "Anchor class", "Text on bar",
    "No selection", "Opened settings", "Settings unavailable", "Preview animation unavailable",
    "Open %s settings",
    "Choose %s in the game menu", "%s settings", "%s Anchor", "%s %s: %s", "%s %s", "Reset %s",
    "Unit frame", "General layout", "Group frame", "Move", "Nudge", "Set", "Change",
    "Motion", "Settings", "Preview animation on", "Preview animation off",
    "Keep the current positions and exit Edit Mode.",
    "Undo the last MSUF change from Edit Mode or the in-game menu.",
    "Redo the last MSUF change from Edit Mode or the in-game menu.",
    "Copied frame size",
    "|cffffd700MSUF:|r Menu and Edit Mode are locked in combat. Leave combat to configure MSUF.",
    "%s Frame", "%s Castbar", "%s Auras", "%s: %s",
    "Change %s", "Move %s", "Nudge %s", "Set %s", "Toggle %s",
}
-- Pure format strings: every pack keeps the same placeholders.
local IDENTITY = { ["%s %s: %s"] = true, ["%s %s"] = true, ["%s: %s"] = true }
local ENGLISH = { enUS = true, enGB = true }
local PACKS = { "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local function Value(source, key)
    local prefix = 'L["' .. key .. '"] = "'
    local start = source:find(prefix, 1, true)
    if not start then return nil end
    local first = start + #prefix
    local last = source:find('"', first, true)
    return last and source:sub(first, last - 1) or nil
end

for _, pack in ipairs(PACKS) do
    local source = Read("MidnightSimpleUnitFrames/Locales/" .. pack .. ".lua")
    for _, key in ipairs(KEYS) do
        local value = Value(source, key)
        if Check(value ~= nil, pack .. ": missing " .. key) and not ENGLISH[pack] and not IDENTITY[key] then
            Check(value ~= key, pack .. ": " .. key .. " is not translated")
        end
        if value and key:find("%s", 1, true) then
            local _, want = key:gsub("%%s", "")
            local _, count = value:gsub("%%s", "")
            Check(count == want, pack .. ": " .. key .. " must keep exactly " .. want .. " %s")
        end
    end
end

local aura = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_AuraPopup.lua")
Check(aura:find('"Edit Arena 1-3 together"', 1, true) and aura:find('"Edit Arena 1-5 together"', 1, true),
    "AuraPopup no longer names both arena-together labels; update this smoke")
local external = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalPopup.lua")
Check(external:find('Tr("Open %s settings")', 1, true) ~= nil,
    "the external popup settings button does not translate its label")
Check(not external:find('"Open " ..', 1, true), "the external popup still concatenates its settings label")
-- The toolbar files in their MSUF_EditMode.xml order.
local hudFiles = {}
for _, name in ipairs({ "HUD_Kit", "HUD_Selection", "HUD_Dock", "HUD_Picker", "HUD" }) do
    hudFiles[#hudFiles + 1] = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_" .. name .. ".lua")
end
local hud = table.concat(hudFiles, "\n")
Check(hud:find('string.format(HelpText("%s settings"), selectedCfg.label or key)', 1, true)
    and not hud:find('.. " settings")', 1, true), "the HUD settings tip concatenates its label")
Check(hud:find('string.format(HelpText("%s Anchor"), providerLabel)', 1, true)
    and not hud:find('" Anchor")', 1, true), "the HUD cooldown button concatenates its provider anchor label")
Check(hud:find('string.format(HelpText("Reset %s"), ', 1, true)
    and not hud:find('HelpText("Reset") .. ', 1, true), "the HUD Reset status concatenates its label")
-- The literals the toolbar and the popups show, so a renamed one cannot slip
-- out of the packs.
for _, literal in ipairs({ '"Motion"', '"Settings"', '"Preview animation on"', '"Preview animation off"',
    '"Keep the current positions and exit Edit Mode."', '"Undo the last MSUF change from Edit Mode or the in-game menu."',
    '"Redo the last MSUF change from Edit Mode or the in-game menu."' }) do
    Check(hud:find(literal, 1, true), "the HUD no longer shows " .. literal .. "; update this smoke")
end
local unitPopup = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Popups.lua")
Check(unitPopup:find('SetHUDStatus("Copied frame size"', 1, true), "the unit popup no longer reports the copied size; update this smoke")
Check(unitPopup:find('string.format(Tr("%s Frame"), ', 1, true) and not unitPopup:find('.. " " .. Tr("Frame")', 1, true),
    "the unit popup title concatenates its words")
local castPopup = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_CastPopup.lua")
Check(castPopup:find('string.format(Quick.Tr("%s Castbar"), ', 1, true) and not castPopup:find('.. " " .. Quick.Tr("Castbar")', 1, true),
    "the castbar popup title concatenates its words")
Check(aura:find('string.format(Quick.Tr("%s Auras"), ', 1, true) and not aura:find('Quick.Tr("%s %s")', 1, true),
    "the aura popup title is not a whole-sentence key")
local undo = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Undo.lua")
for _, key in ipairs({ "Change %s", "Move %s", "Nudge %s", "Reset %s", "Set %s", "Toggle %s" }) do
    Check(undo:find('"' .. key .. '"', 1, true), "the Edit Mode history labels lost the sentence key " .. key)
end
Check(not undo:find('tr("%s %s: %s")', 1, true), "the Edit Mode history label still glues action, frame and key")
local util = Read("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
Check(util:find('"|cffffd700MSUF:|r Menu and Edit Mode are locked in combat. Leave combat to configure MSUF."', 1, true),
    "the Edit Mode combat message changed; update this smoke")
local blizzard = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Blizzard.lua")
Check(blizzard:find('translate("Choose %s in the game menu")', 1, true) ~= nil,
    "the Classic route to Blizzard's Edit Mode does not translate its hint")

-- The Reset status a German client shows after HUD Reset on the player frame
-- (real core and Options graphs, tools/tests/client_world.lua).
do
    local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
    local world = World.New(root, "Mainline", { locale = "deDE" }):Boot()
    local failure = world:FirstFailure()
    assert(not failure, "deDE boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local env, core = world.env, world.core
    core.UF.Apply = function() return true end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    core.FinalizeLocale()
    env.MSUF_InitProfiles()
    env.MSUF2.ApplyService.Flush = function() return true end
    local EM2 = env.MSUF_EM2
    if Check(EM2.State.Enter("player") == true, "deDE: Edit Mode did not open") then
        world.widgets:RunTimers()
        local status
        local setStatus = EM2.HUD.SetStatus
        EM2.HUD.SetStatus = function(text, kind, seconds) status = text; return setStatus(text, kind, seconds) end
        EM2.State.SetUnitKey("player")
        EM2.HUD.ResetCurrentPosition()
        EM2.HUD.SetStatus = setStatus
        local function Translated(key)
            local value = rawget(core.L, key)
            return type(value) == "string" and value ~= "" and value or key
        end
        local expected = string.format(Translated("Reset %s"), Translated("Player"))
        Check(Translated("Reset %s") ~= "Reset %s" and status == expected,
            "deDE: HUD Reset said " .. tostring(status) .. ", not " .. expected)
        -- The Move history label: German puts the verb last.
        local undo = EM2.Undo
        if Check(undo.BeginChange("unit", "player", "Move") == true, "deDE: the move transaction did not open") then
            env.MSUF_DB.player.offsetX = (tonumber(env.MSUF_DB.player.offsetX) or 0) + 3
            undo.CommitChange()
            local label = env.MSUF2.GetHistoryState().undoLabel
            local want = string.format(Translated("%s: %s"), string.format(Translated("Move %s"), Translated("Unit frame")), "player")
            Check(Translated("Move %s") ~= "Move %s" and label == want,
                "deDE: the move history label is " .. tostring(label) .. ", not " .. want)
        end
        EM2.State.Exit("test")
    end
end

if #failures > 0 then
    error("editmode_shell_locale_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_shell_locale_smoke: ok (" .. #KEYS .. " keys in 12 packs)")

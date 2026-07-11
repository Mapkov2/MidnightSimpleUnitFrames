-- Standalone regression for the Edit Mode castbar movement transaction.
local root = arg and arg[1] or "."
local layoutPath = root .. "/MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_Layout.lua"

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function Round(value)
    return value >= 0 and math.floor(value + 0.5) or -math.floor(-value + 0.5)
end

local state = {
    active = true,
    combat = false,
    selected = "player",
    popupOpen = false,
    popupUnit = "player",
    applies = {},
    undos = {},
    popupSyncs = {},
    moverSyncs = 0,
    focusSyncs = {},
    previewSyncs = {},
}

local applyHook

local function Reset(general)
    _G.MSUF_DB = { general = general or {} }
    state.active = true
    state.combat = false
    state.selected = "player"
    state.popupOpen = false
    state.popupUnit = "player"
    state.applies = {}
    state.undos = {}
    state.popupSyncs = {}
    state.moverSyncs = 0
    state.focusSyncs = {}
    state.previewSyncs = {}
    applyHook = nil
end

local prefixes = {
    player = "castbarPlayer",
    target = "castbarTarget",
    focus = "castbarFocus",
}
local defaults = {
    player = { 0, 5 },
    target = { 65, -15 },
    focus = { 65, -15 },
    boss = { 0, 0 },
}

_G.MSUF_GetCastbarPrefix = function(unit) return prefixes[unit] end
_G.MSUF_GetCastbarDefaultOffsets = function(unit)
    local value = defaults[unit]
    return value and value[1], value and value[2]
end
_G.MSUF_SyncCastbarPositionPopup = function(unit)
    state.popupSyncs[#state.popupSyncs + 1] = unit
end

local MSUF = {}
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

local chunk, loadError = loadfile(layoutPath)
Check(chunk ~= nil, loadError)
chunk("MidnightSimpleUnitFrames", MSUF)
Check(type(_G.MSUF_InstallEditLayoutUI) == "function", "layout installer was not exported")

local EM2 = {
    Util = {
        Round = Round,
        RefreshUFPreview = function(reason, unit)
            state.previewSyncs[#state.previewSyncs + 1] = { reason = reason, unit = unit }
        end,
        ApplySettingsForKeySafe = function(key)
            state.applies[#state.applies + 1] = key
            if applyHook then return applyHook(#state.applies, key) end
            return true
        end,
        ApplyAllSettingsSafe = function() return true end,
        IsConfigCombatLocked = function() return state.combat end,
        BlockConfigCombatLocked = function() return state.combat end,
        ThemeColor = function() return 1, 1, 1 end,
    },
    State = {
        IsActive = function() return state.active end,
        GetUnitKey = function() return state.selected end,
        SetUnitKey = function(key) state.selected = key end,
    },
    Undo = {
        PrepareChange = function(category, unit)
            local g = _G.MSUF_DB and _G.MSUF_DB.general or {}
            return {
                category = category,
                unit = unit,
                playerX = g.castbarPlayerOffsetX,
                targetX = g.castbarTargetOffsetX,
                focusX = g.castbarFocusOffsetX,
                bossX = g.bossCastbarOffsetX,
            }
        end,
        CommitPrepared = function(snapshot)
            state.undos[#state.undos + 1] = snapshot
            return true
        end,
    },
    CastPopup = {
        IsOpen = function() return state.popupOpen end,
        GetUnit = function() return state.popupUnit end,
        Sync = function() end,
    },
    Movers = {
        SyncAll = function() state.moverSyncs = state.moverSyncs + 1 end,
    },
    Focus = {
        NotifyPositionChanged = function(key, immediate)
            state.focusSyncs[#state.focusSyncs + 1] = { key = key, immediate = immediate }
        end,
        NudgeSelection = function() return false end,
    },
}
_G.MSUF_EM2 = EM2
_G.MSUF_InstallEditLayoutUI("MidnightSimpleUnitFrames", MSUF)
Check(EM2.Nudge and type(EM2.Nudge.Move) == "function", "Nudge.Move was not installed")

local function AssertSuccessfulMove(targetKey, dx, dy, xKey, yKey, expectedX, expectedY, unit)
    Check(EM2.Nudge.Move(dx, dy, targetKey) == true, targetKey .. " move failed")
    Equal(_G.MSUF_DB.general[xKey], expectedX, targetKey .. " X")
    Equal(_G.MSUF_DB.general[yKey], expectedY, targetKey .. " Y")
    Equal(state.selected, targetKey, targetKey .. " selection")
    Equal(#state.undos, 1, targetKey .. " undo count")
    Equal(state.undos[1].category, "castbar", targetKey .. " undo category")
    Equal(state.undos[1].unit, unit, targetKey .. " undo unit")
    Equal(#state.applies, 1, targetKey .. " apply count")
    Equal(state.applies[1], targetKey, targetKey .. " apply key")
    Equal(state.popupSyncs[#state.popupSyncs], unit, targetKey .. " popup sync")
    Equal(state.focusSyncs[#state.focusSyncs].key, targetKey, targetKey .. " focus sync")
    Equal(state.previewSyncs[#state.previewSyncs].unit, unit, targetKey .. " preview sync")
end

Reset({})
AssertSuccessfulMove("castbar_player", 3, -2,
    "castbarPlayerOffsetX", "castbarPlayerOffsetY", 3, 3, "player")

Reset({ castbarTargetOffsetX = -10, castbarTargetOffsetY = 20 })
AssertSuccessfulMove("castbar_target", -2, 4,
    "castbarTargetOffsetX", "castbarTargetOffsetY", -12, 24, "target")

Reset({ castbarTargetOffsetX = 70, castbarTargetOffsetY = -20 })
AssertSuccessfulMove("castbar_focus", 5, 5,
    "castbarFocusOffsetX", "castbarFocusOffsetY", 75, -15, "focus")
Equal(_G.MSUF_DB.general.castbarTargetOffsetX, 70, "focus move changed target X fallback")
Equal(_G.MSUF_DB.general.castbarTargetOffsetY, -20, "focus move changed target Y fallback")

Reset({ bossCastbarOffsetX = 2, bossCastbarOffsetY = -3 })
AssertSuccessfulMove("castbar_boss", -1, 2,
    "bossCastbarOffsetX", "bossCastbarOffsetY", 1, -1, "boss")

-- An explicit target must win over a different open popup.
Reset({
    castbarPlayerOffsetX = 10, castbarPlayerOffsetY = 10,
    castbarFocusOffsetX = 20, castbarFocusOffsetY = 20,
})
state.popupOpen = true
state.popupUnit = "player"
Check(EM2.Nudge.Move(2, 0, "castbar_focus") == true, "explicit focus move was captured by player popup")
Equal(_G.MSUF_DB.general.castbarPlayerOffsetX, 10, "player popup target moved unexpectedly")
Equal(_G.MSUF_DB.general.castbarFocusOffsetX, 22, "explicit focus target did not move")

-- Keyboard-style movement with no explicit target still uses the open popup.
Reset({ castbarTargetOffsetX = 5, castbarTargetOffsetY = 6 })
state.popupOpen = true
state.popupUnit = "target"
Check(EM2.Nudge.Move(1, -1) == true, "open-popup castbar move failed")
Equal(_G.MSUF_DB.general.castbarTargetOffsetX, 6, "open-popup target X")
Equal(_G.MSUF_DB.general.castbarTargetOffsetY, 5, "open-popup target Y")

-- Apply failure restores exact raw values and reapplies the old state.
Reset({ castbarPlayerOffsetX = 11, castbarPlayerOffsetY = 12 })
applyHook = function(call) return call ~= 1 end
Check(EM2.Nudge.Move(4, 4, "castbar_player") == false, "failed apply was reported as success")
Equal(_G.MSUF_DB.general.castbarPlayerOffsetX, 11, "apply failure did not roll back X")
Equal(_G.MSUF_DB.general.castbarPlayerOffsetY, 12, "apply failure did not roll back Y")
Equal(#state.applies, 2, "rollback did not reapply prior castbar state")

-- A synchronous apply that rewrites the DB fails readback and rolls back.
Reset({ bossCastbarOffsetX = 7, bossCastbarOffsetY = 8 })
applyHook = function(call)
    if call == 1 then _G.MSUF_DB.general.bossCastbarOffsetX = 999 end
    return true
end
Check(EM2.Nudge.Move(1, 1, "castbar_boss") == false, "readback mismatch was reported as success")
Equal(_G.MSUF_DB.general.bossCastbarOffsetX, 7, "readback failure did not roll back X")
Equal(_G.MSUF_DB.general.bossCastbarOffsetY, 8, "readback failure did not roll back Y")
Equal(#state.applies, 2, "readback rollback did not reapply prior state")

-- Combat, missing undo, invalid targets, invalid numbers, and domain overflow are fail-closed.
Reset({ castbarPlayerOffsetX = 1, castbarPlayerOffsetY = 2 })
state.combat = true
Check(EM2.Nudge.Move(1, 0, "castbar_player") == false, "combat move was accepted")
Equal(_G.MSUF_DB.general.castbarPlayerOffsetX, 1, "combat move mutated DB")
Equal(#state.undos, 0, "combat move created undo")
Equal(#state.applies, 0, "combat move applied")

Reset({ castbarPlayerOffsetX = 1, castbarPlayerOffsetY = 2 })
local undo = EM2.Undo
EM2.Undo = nil
Check(EM2.Nudge.Move(1, 0, "castbar_player") == false, "move without undo was accepted")
Equal(_G.MSUF_DB.general.castbarPlayerOffsetX, 1, "move without undo mutated DB")
EM2.Undo = undo

Reset({ castbarPlayerOffsetX = 1, castbarPlayerOffsetY = 2 })
Check(EM2.Nudge.Move(1, 0, "castbar_pet") == false, "unknown castbar target was accepted")
Check(EM2.Nudge.Move(0 / 0, 0, "castbar_player") == false, "NaN delta was accepted")
Check(EM2.Nudge.Move(math.huge, 0, "castbar_player") == false, "infinite delta was accepted")
_G.MSUF_DB.general.castbarPlayerOffsetX = 4096
Check(EM2.Nudge.Move(1, 0, "castbar_player") == false, "out-of-domain offset was accepted")
Equal(_G.MSUF_DB.general.castbarPlayerOffsetX, 4096, "out-of-domain move mutated DB")

print("PASS editmode castbar nudge: 4 movers, popup independence, undo/apply/sync/readback/rollback, fail-closed")

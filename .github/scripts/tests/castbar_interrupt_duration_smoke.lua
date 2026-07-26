-- Focused regression for the configurable interrupted-cast hold duration.
_G = _G or _ENV

local now = 100
local timers = {}

_G.GetTime = function() return now end
_G.GetTimePreciseSec = nil
_G.issecretvalue = function() return false end
_G.C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end,
}
_G.MSUF_DB = {
    general = { castbarInterruptFeedbackDuration = 2.3 },
    player = { showInterrupt = true },
}

local MSUF = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local getDuration = assert(_G.MSUF_GetInterruptFeedbackDuration)
assert(getDuration() == 2.3, "saved interrupt duration was not resolved")
_G.MSUF_DB.general.castbarInterruptFeedbackDuration = -1
assert(getDuration() == 0, "interrupt duration lower clamp failed")
_G.MSUF_DB.general.castbarInterruptFeedbackDuration = 8
assert(getDuration() == 5, "interrupt duration upper clamp failed")
_G.MSUF_DB.general.castbarInterruptFeedbackDuration = nil
assert(getDuration() == 0.5, "interrupt duration default failed")
_G.MSUF_DB.general.castbarInterruptFeedbackDuration = 2.3

_G.MSUF_GetReverseFillSafe = function() return false end
_G.MSUF_ApplyInterruptBarVisuals = function(frame, options) frame.interruptOptions = options end
_G.MSUF_UnregisterCastbar = function() end
_G.MSUF_SetTextIfChanged = function(text, value) text.value = value end

assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
timers = {}

local function NewPlayerFrame()
    return {
        statusBar = {},
        timeText = {},
        SetScript = function(self, script, callback) self[script] = callback end,
        Hide = function(self) self.hidden = true end,
    }
end

local player = NewPlayerFrame()
_G.MSUF_PlayerCastbar_ShowInterruptFeedback(player, "Interrupted")
assert(timers[1] and timers[1].delay == 2.3, "player interrupt timer ignored saved duration")
assert(player.interruptFeedbackEndTime == now + 2.3
    and player._msufPlayerInterruptHideDeadline == now + 2.3,
    "player interrupt deadlines ignored saved duration")

_G.MSUF_DB.general.castbarInterruptFeedbackDuration = 0.1
local nextPlayer = NewPlayerFrame()
_G.MSUF_PlayerCastbar_ShowInterruptFeedback(nextPlayer, "Interrupted")
assert(timers[2] and timers[2].delay == 0.1,
    "duration changes did not apply to the next interrupt without reload")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local driver = Read("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarDriver.lua")
assert(driver:find("local getFeedbackDuration = _G.MSUF_GetInterruptFeedbackDuration", 1, true),
    "target/focus/boss interrupt path does not use the shared config resolver")

local menu = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
local sliderWrite = assert(menu:find('SetG("castbarInterruptFeedbackDuration", duration, "MSUF2_CASTBAR_INTERRUPT_DURATION", { preview = true })', 1, true))
local sliderPreview = menu:find("M.PlayCastbarPreviewInterrupt()", sliderWrite, true)
local interruptButton = assert(menu:find('T.Button(section, "Interrupt"', 1, true))
local buttonPreview = menu:find("M.PlayCastbarPreviewInterrupt()", interruptButton, true)
assert(menu:find('"Interrupt display duration (sec)"', 1, true)
    and menu:find('0, 5, 0.1, "castbarInterruptFeedbackDuration", 0.5', 1, true)
    and sliderPreview and sliderPreview - sliderWrite < 240
    and buttonPreview and buttonPreview - interruptButton < 500,
    "interrupt duration slider contract is incomplete")

local defaults = Read("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
assert(defaults:find("g.castbarInterruptFeedbackDuration = 0.5", 1, true),
    "interrupt duration default is missing")

local schema = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema_Data.lua")
assert(schema:find("setting:general.castbarInterruptFeedbackDuration@opt_castbar", 1, true)
    and schema:find("'number', '0', '5', '0.1'", 1, true),
    "Assistant schema is missing the interrupt duration slider contract")

for _, locale in ipairs({ "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local localeSource = Read("MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua")
    assert(localeSource:find('["Interrupt display duration (sec)"]', 1, true)
        or localeSource:find('L["Interrupt display duration (sec)"]', 1, true),
        locale .. " is missing the interrupt duration label")
end

print("castbar_interrupt_duration_smoke: ok")

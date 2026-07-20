-- Focused regression for the configurable interrupted-cast hold duration.
_G = _G or _ENV

local now = 100
local timers = {}
_G.GetTime = function() return now end
_G.C_Timer = {
    NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback, Cancel = function() end }
        timers[#timers + 1] = timer
        return timer
    end,
    After = function() end,
}
_G.MSUF_DB = {
    general = { castbarInterruptFeedbackDuration = 2.3 },
    player = { showInterrupt = true },
}

assert(loadfile("MidnightSimpleUnitFrames_Castbars/Castbars/MSUF_CastbarUtils.lua"))(
    "MidnightSimpleUnitFrames_Castbars", {})

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
_G.INTERRUPTED = "Interrupted"

assert(loadfile("MidnightSimpleUnitFrames_Castbars/Castbars/MSUF_PlayerCastbarRuntime.lua"))()

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
assert(timers[1] and timers[1].delay == 2.3, "Player interrupt timer ignored the saved duration")
assert(player.interruptFeedbackEndTime == now + 2.3, "Player interrupt deadline ignored the saved duration")

_G.MSUF_DB.general.castbarInterruptFeedbackDuration = 0.1
local nextPlayer = NewPlayerFrame()
_G.MSUF_PlayerCastbar_ShowInterruptFeedback(nextPlayer, "Interrupted")
assert(timers[2] and timers[2].delay == 0.1, "live duration changes require a reload")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local driver = Read("MidnightSimpleUnitFrames_Castbars/Castbars/MSUF_CastbarDriver.lua")
assert(select(2, driver:gsub("MSUF_GetInterruptFeedbackDuration", "")) >= 2,
    "Target/Focus interrupt paths do not share the saved duration")

local boss = Read("MidnightSimpleUnitFrames_Castbars/Modules/MidnightSimpleUnitFrames_BossCastbars.lua")
assert(boss:find("MSUF_GetInterruptFeedbackDuration", 1, true), "Boss interrupt path does not use the shared duration")

local menu = Read("MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
assert(menu:find('W.Slider(behavior, "Interrupt display duration (sec)", 0, 5, 0.1', 1, true)
    and menu:find('SetG("castbarInterruptFeedbackDuration"', 1, true)
    and menu:find("InterruptCastPreview()", 1, true),
    "interrupt duration slider or synchronized preview is incomplete")

for _, locale in ipairs({ "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local localeSource = Read("MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua")
    for _, key in ipairs({ "Interrupt display duration (sec)", "Portrait zoom", "Spell-specific channel tick markers" }) do
        assert(localeSource:find('["' .. key .. '"]', 1, true)
            or localeSource:find('L["' .. key .. '"]', 1, true),
            locale .. " is missing locale key: " .. key)
    end
end

print("castbar_interrupt_duration_backport_smoke: ok")

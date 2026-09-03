local repo = assert(arg[1], "repo root required")

local signalCallbacks = {}
local signalled = {}
local cancelled = {}
local registrations = 0

TimerUtil = {
    CreateTimedSignalCallbackMap = function()
        return {
            RegisterCallback = function(_, callback)
                registrations = registrations + 1
                signalCallbacks[registrations] = callback
                return registrations
            end,
            SignalAfter = function(_, key, delay)
                signalled[#signalled + 1] = { key = key, delay = delay }
            end,
            CancelSignal = function(_, key)
                cancelled[#cancelled + 1] = key
            end,
        }
    end,
}

local schedulerFrame = {}
function schedulerFrame:SetScript(script, callback)
    assert(script == "OnUpdate")
    self.onUpdate = callback
end
function CreateFrame()
    return schedulerFrame
end
C_Timer = {
    After = function()
        error("12.1.5 native scheduler unexpectedly fell back to C_Timer.After")
    end,
}

local namespace = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))(
    "MidnightSimpleUnitFrames", namespace)

local scheduler = assert(namespace.Scheduler)
local fired = {}
assert(scheduler.ScheduleAfter("castbar", 0.4, function() fired[#fired + 1] = "stale" end))
assert(scheduler.ScheduleAfter("castbar", 0.1, function() fired[#fired + 1] = "latest" end))
assert(registrations == 1, "rescheduling one stable key registered another native callback")
assert(#signalled == 2 and signalled[1].key == signalled[2].key,
    "rescheduling did not reuse the native signal key")
signalCallbacks[signalled[2].key]()
assert(#fired == 1 and fired[1] == "latest", "reschedule did not replace the callback")
assert(scheduler.IsScheduled("castbar") == false, "fired key stayed pending")

assert(scheduler.ScheduleAfter("cancel", 0.2, function() fired[#fired + 1] = "cancelled" end))
assert(scheduler.CancelScheduled("cancel") == true, "pending key was not cancelled")
assert(#cancelled == 1, "native CancelSignal was not called")
signalCallbacks[signalled[#signalled].key]()
assert(#fired == 1, "cancelled callback still fired")

local cvarWrites = {}
local availableCVars = {
    tooltipShowAuraSpellIDs = "0",
    tooltipShowAuraCasterNames = "0",
}
C_CVar = {
    GetCVar = function(name) return availableCVars[name] end,
    SetCVar = function(name, value)
        cvarWrites[#cvarWrites + 1] = { name = name, value = value }
    end,
}
MSUF_DB = {
    general = {
        tooltipShowAuraSpellIDs = true,
        tooltipShowAuraCasterNames = true,
    },
}
local loginFrame = {}
function loginFrame:RegisterEvent(event) self.event = event end
function loginFrame:UnregisterEvent(event) assert(event == self.event) end
function loginFrame:SetScript(script, callback)
    assert(script == "OnEvent")
    self.onEvent = callback
end
CreateFrame = function() return loginFrame end
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Runtime/MSUF_TooltipSpellIDs.lua"))(
    "MidnightSimpleUnitFrames", namespace)
assert(loginFrame.event == "PLAYER_LOGIN" and type(loginFrame.onEvent) == "function",
    "tooltip CVar login owner was not installed")
loginFrame.onEvent(loginFrame)
assert(#cvarWrites == 2, "login did not restore both enabled aura tooltip CVars")
assert(cvarWrites[1].name == "tooltipShowAuraSpellIDs" and cvarWrites[1].value == "1")
assert(cvarWrites[2].name == "tooltipShowAuraCasterNames" and cvarWrites[2].value == "1")
assert(MSUF_ApplyTooltipCasterNames(false) == true)
assert(cvarWrites[#cvarWrites].name == "tooltipShowAuraCasterNames"
    and cvarWrites[#cvarWrites].value == "0", "explicit caster toggle did not write off")
availableCVars.tooltipShowAuraCasterNames = nil
assert(MSUF_ApplyTooltipCasterNames(true) == false,
    "missing 12.1.5 CVar was not rejected safely")

local function Read(relative)
    local file = assert(io.open(repo .. "/" .. relative, "rb"))
    local text = file:read("*a") or ""
    file:close()
    return text
end

local auras = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
for _, contract in ipairs({
    "SetEditModePreviewEnabled", "SetAuraGroupEnabled", "SetAuraSlotEnabled",
    "SetItemEnchantmentEnabled", "SetCasterName", "AddPandemicActiveAnimation",
}) do
    assert(auras:find(contract, 1, true), "missing 12.1.5 AuraContainer contract: " .. contract)
end
local effects = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
assert(effects:find("AddPandemicActiveAnimation", 1, true),
    "Pandemic pulse is not bound to the native animation lifecycle")
local tooltip = Read("MidnightSimpleUnitFrames/Runtime/MSUF_TooltipSpellIDs.lua")
assert(tooltip:find("tooltipShowAuraCasterNames", 1, true),
    "12.1.5 aura caster tooltip CVar is missing")

print("PTR 12.1.5 runtime smoke passed")

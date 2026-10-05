-- Edit Mode arrow-key nudge (Shell/EditMode/MSUF_EditMode_Layout_Nudge.lua):
-- the arrows are override bindings on hidden buttons while Edit Mode is open.
--
-- 1. Edit Mode exits at PLAYER_REGEN_DISABLED. The configuration lock already
--    refuses there (Kernel InCombat remembers the edge for the rest of the
--    frame), but InCombatLockdown() is still false and ClearOverrideBindings
--    is still allowed. Deferring the clear to PLAYER_REGEN_ENABLED left the
--    arrow keys (default movement and turning) bound to the hidden buttons for
--    the whole fight.
--
-- Loads the real MSUF_EditMode_State.lua and MSUF_EditMode_Layout_Nudge.lua,
-- with the Kernel's InCombat taken verbatim from Kernel/MSUF_Util.lua.
-- Usage: lua tools/tests/editmode_nudge_routing_smoke.lua <repoRoot>
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local EM_DIR = "MidnightSimpleUnitFrames/Shell/EditMode/"

local function Read(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"), "missing " .. rel)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

-- Client: the lockdown starts after the PLAYER_REGEN_DISABLED dispatch, and a
-- protected binding write under lockdown is blocked.
local now, lockdown = 100, false
GetTime = function() return now end
InCombatLockdown = function() return lockdown end
local bindings, blocked = {}, {}
ClearOverrideBindings = function(owner)
    if lockdown then blocked[#blocked + 1] = "ClearOverrideBindings"; return end
    for key, value in pairs(bindings) do if value.owner == owner then bindings[key] = nil end end
end
SetOverrideBindingClick = function(owner, _, key, buttonName)
    if lockdown then blocked[#blocked + 1] = "SetOverrideBindingClick"; return end
    bindings[key] = { owner = owner, button = buttonName }
end
IsAltKeyDown = function() return false end
IsControlKeyDown = function() return false end
IsShiftKeyDown = function() return false end
C_Timer = { After = function() end }

local created = {}
local Frame = {}
Frame.__index = Frame
function Frame:SetScript(name, handler) self.scripts[name] = handler end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:IsEventRegistered(event) return self.events[event] == true end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:SetSize() end
CreateFrame = function(_, name)
    local frame = setmetatable({ scripts = {}, events = {}, shown = true, name = name }, Frame)
    created[#created + 1] = frame
    if name then _G[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame")

-- Kernel InCombat and the configuration lock built on it (Kernel/MSUF_Util.lua).
local util = Read("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
local inCombatBody = assert(util:match("(local combatEdgeTime\nlocal function InCombat%(event%).-\nend)\n"),
    "Kernel/MSUF_Util.lua no longer defines InCombat(event) after combatEdgeTime")
local InCombat = assert(loadstring(inCombatBody .. "\nreturn InCombat", "Kernel InCombat"))()
assert(util:find("    local function IsConfigCombatLocked(event)\n        return InCombat(event) == true\n    end", 1, true),
    "the configuration lock must stay the edge-aware InCombat(event)")
MSUF_IsConfigCombatLocked = function(event) return InCombat(event) == true end

local ns = { ExportPublic = function(name, value) _G[name] = value; return value end }
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
RequireFixture.Install(root, ns)

MSUF_DB = { player = { offsetX = 0, offsetY = 0 }, general = {} }
MSUF_EM2 = {
    Util = {
        Round = function(v) return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5) end,
        RefreshUFPreview = function() end,
        ApplySettingsForKeySafe = function() return true end,
        ApplyAllSettingsSafe = function() return true end,
        ApplyGroupSettingsForKeySafe = function() return true end,
        -- Shell/EditMode/MSUF_EditMode_Core.lua Util.IsConfigCombatLocked/BlockConfigCombatLocked.
        IsConfigCombatLocked = function(event) return MSUF_IsConfigCombatLocked(event) and true or false end,
        BlockConfigCombatLocked = function() return MSUF_IsConfigCombatLocked() and true or false end,
        ShowConfigCombatLockMessage = function() end,
        ProfileIdentity = function() return "profile" end,
        IsCurrentProfile = function() return true end,
        SharedHistoryService = function() return nil end,
        SyncMovers = function() end,
    },
}
local EM2 = MSUF_EM2
for _, file in ipairs({ "MSUF_EditMode_State.lua", "MSUF_EditMode_Layout_Nudge.lua" }) do
    assert(loadfile(root .. "/" .. EM_DIR .. file))("MidnightSimpleUnitFrames", ns)
end

-- 1. Combat edge: Edit Mode's exit at PLAYER_REGEN_DISABLED releases the arrows.
assert(EM2.State.Enter("player") == true, "Edit Mode did not open")
assert(bindings.UP and bindings.DOWN and bindings.LEFT and bindings.RIGHT
    and bindings.RIGHT.button == "MSUF_EM2_NudgeRIGHT", "Edit Mode did not bind the arrow keys to its nudge buttons")
local combatFrame
for _, frame in ipairs(created) do
    if frame.events.PLAYER_REGEN_DISABLED and frame.scripts.OnEvent then combatFrame = frame end
end
assert(combatFrame, "Edit Mode registered no combat listener while open")
combatFrame.scripts.OnEvent(combatFrame, "PLAYER_REGEN_DISABLED")
lockdown = true
assert(not EM2.State.IsActive(), "Edit Mode did not exit at PLAYER_REGEN_DISABLED")
assert(next(bindings) == nil and #blocked == 0,
    "the arrow keys stayed bound to Edit Mode's nudge buttons into the fight (cleared only after combat)")
local owner = assert(MSUF_EM2_NudgeOwner, "nudge binding owner missing")
assert(not owner.__msufPendingClear, "a clear the edge already did was still queued for after combat")
-- Under a real lockdown the clear still waits for PLAYER_REGEN_ENABLED.
lockdown = false
now = now + 1
combatFrame.scripts.OnEvent(combatFrame, "PLAYER_REGEN_ENABLED")
assert(EM2.State.Enter("player") == true and bindings.RIGHT, "Edit Mode did not reopen after combat")
lockdown = true
now = now + 1
EM2.Nudge.Disable()
assert(bindings.RIGHT and #blocked == 0 and owner.__msufPendingClear == true and owner.events.PLAYER_REGEN_ENABLED,
    "a disable under lockdown must defer the clear to PLAYER_REGEN_ENABLED")
lockdown = false
owner.scripts.OnEvent(owner, "PLAYER_REGEN_ENABLED")
assert(next(bindings) == nil and not owner.__msufPendingClear, "the deferred clear did not run after combat")
EM2.State.Exit("test")

print("Edit Mode nudge routing: arrows released at the combat edge passed")

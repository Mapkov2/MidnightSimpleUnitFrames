--- Cross-addon interop guards.
---
--- Two unitframe addons routinely own the same Blizzard frame, and both defend
--- their ownership with the same idioms. This pins the two places where MSUF
--- has to yield instead of fighting:
---   1. a Blizzard frame parented into *another* addon's hidden frame is left
---      alone, so two SetParent hooks cannot bounce it until the stack blows,
---   2. "/rl" is only claimed while the token is still free.
--- Both guards must stay cheap: neither may add a frame, event or timer.
_G = _G or _ENV

local function ResolvePath(relative)
    local candidates = { "MidnightSimpleUnitFrames/" .. relative, relative }
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "r")
        if handle then
            handle:close()
            return candidates[i]
        end
    end
    error("cannot locate " .. relative)
end

--- ---------------------------------------------------------------------------
--- Frame stub. SetParent/IsShown are real enough that the recursion this file
--- guards against would actually happen if the guard were removed.
--- ---------------------------------------------------------------------------
local setParentCalls = 0
local function NewFrame(name, shown)
    local frame = { _name = name, _shown = shown and true or false }
    function frame:SetParent(parent) setParentCalls = setParentCalls + 1; self._parent = parent end
    function frame:GetParent() return self._parent end
    function frame:IsShown() return self._shown end
    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:SetAllPoints() end
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:UnregisterAllEvents() end
    function frame:SetScript() end
    function frame:IsProtected() return false end
    function frame:IsForbidden() return false end
    function frame:EnableMouse() end
    return frame
end

--- Chains like the real one: the post-hook runs after the original, so a hook
--- that calls the same method re-enters through every installed hook.
local function InstallPostHook(object, method, hook)
    local original = object[method]
    object[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

local UIParentStub = NewFrame("UIParent", true)
_G.UIParent = UIParentStub
_G.CreateFrame = function(_, name) return NewFrame(name, true) end
_G.InCombatLockdown = function() return false end
_G.hooksecurefunc = InstallPostHook
_G.MAX_BOSS_FRAMES = 5
_G.MSUF_DB = { general = {}, boss = {} }

--- ---------------------------------------------------------------------------
--- 1. Kernel Blizzard-frame ownership.
--- ---------------------------------------------------------------------------
local container = NewFrame("BossTargetFrameContainer", true)
_G.BossTargetFrameContainer = container
for i = 1, _G.MAX_BOSS_FRAMES do
    _G["Boss" .. i .. "TargetFrame"] = NewFrame("Boss" .. i .. "TargetFrame", true)
end

local MSUF = { UF = {} }
MSUF.ExportPublic = function(name, value) _G[name] = value; return value end

local chunk, err = loadfile(ResolvePath("Kernel/MSUF_BlizzardFrames.lua"))
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local UF = MSUF.UF
assert(type(UF.DisableBlizzardFrames) == "function",
    "the Blizzard ownership bridge must export DisableBlizzardFrames")

UF.DisableBlizzardFrames()

local msufHidden = container:GetParent()
assert(msufHidden ~= nil and msufHidden ~= UIParentStub,
    "the boss container must be reparented away from UIParent")
assert(msufHidden:IsShown() == false, "MSUF's holding parent must itself be hidden")

--- The hook's original job: a Blizzard layout pass that yanks the frame back
--- onto UIParent is still corrected. This is what must not regress.
container:SetParent(UIParentStub)
assert(container:GetParent() == msufHidden,
    "a restore onto UIParent must still be pulled back into MSUF's hidden parent")

--- Now a second addon claims the same frame with the identical idiom: lock the
--- parent to *its* hidden frame. Before the guard, MSUF answered every foreign
--- reparent with its own, and the two hooks recursed until the stack overflowed.
---
--- This is not a hypothetical shape. It is oUF's resetParent (Libs/oUF/
--- blizzard.lua), which out of combat reduces to exactly this, and oUF hides
--- BossTargetFrameContainer too -- so every oUF-based addon (NDui and friends)
--- brings it. ElvUI's UnitFrames LockParent is the same idea again.
local rivalHidden = NewFrame("RivalHiddenFrame", false)
InstallPostHook(container, "SetParent", function(self, parent)
    if parent ~= rivalHidden then
        self:SetParent(rivalHidden)
    end
end)

setParentCalls = 0
container:SetParent(UIParentStub)

assert(setParentCalls < 50, string.format(
    "MSUF and a rival SetParent hook recursed (%d calls): the hidden-parent guard is gone",
    setParentCalls))
assert(container:GetParent() == rivalHidden,
    "MSUF must yield to another addon's hidden parent instead of re-claiming the frame")
assert(container:GetParent():IsShown() == false,
    "yielding is only safe while the frame ends up hidden")

--- Yielding is specific to hidden parents: a *shown* foreign parent is still a
--- frame the player would see, so MSUF must keep correcting it.
local shownRival = NewFrame("ShownRivalFrame", true)
container._parent = shownRival
container:SetParent(shownRival)
assert(container:GetParent() ~= shownRival,
    "a shown parent must still be corrected -- the guard must not cover it")

--- ---------------------------------------------------------------------------
--- 2. "/rl" is only claimed while free.
--- ---------------------------------------------------------------------------
_G.SlashCmdList = {}
_G.hash_SlashCmdList = {}
_G.ReloadUI = function() end
_G.GetLocale = function() return "enUS" end
_G.C_AddOns = { GetAddOnMetadata = function() return "6.0-smoke" end }
_G.C_Timer = { After = function() end }
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_GetAllProfiles = function() return { "Default" } end
_G.MSUF_CreateProfile = function() return true end
_G.MSUF_SwitchProfile = function() return true end
_G.MSUF_DeleteProfile = function() return true end
_G.MSUF_ResetProfile = function() return true end
_G.MSUF_IsInEditMode = function() return false end
_G.MSUF_EnsureDB = function() end

--- A rival addon got there first, under its own SlashCmdList key -- exactly the
--- shape that does not collide at the key level and so used to go unnoticed.
_G.SlashCmdList["RIVALRELOADUI"] = function() end
_G.SLASH_RIVALRELOADUI1 = "/rl"
_G.SLASH_RIVALRELOADUI2 = "/reloadui"

local chatMSUF = { UF = {} }
chatMSUF.ExportPublic = function(name, value) _G[name] = value; return value end

chunk, err = loadfile(ResolvePath("Runtime/MSUF_SlashCommands.lua"))
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", chatMSUF)

assert(_G.SlashCmdList["MSUFRELOADUI"] == nil,
    "MSUF must not claim /rl when another addon already registered the token")
assert(_G.SLASH_MSUFRELOADUI1 == nil,
    "MSUF must not publish a SLASH_ token it did not claim")
assert(_G.SlashCmdList["RIVALRELOADUI"] ~= nil,
    "the rival registration must be left untouched")

--- The command still has to be documented: whoever owns /rl, it reloads the UI.
local Commands = chatMSUF.SlashCommands
assert(type(Commands) == "table", "the chat runtime must still publish its registry")
local documented = false
for i = 1, #Commands.external do
    if Commands.external[i].usage == "/rl" then documented = true end
end
assert(documented, "/rl must stay listed as a standalone command even when yielded")

--- ---------------------------------------------------------------------------
--- 3. MSUF 6.0 does not integrate with Masque.
--- ---------------------------------------------------------------------------
--- Masque remains free to serve other addons. MSUF must simply avoid declaring
--- the dependency, retaining a live support toggle, or acquiring its library.
local function ReadSource(path)
    local handle = assert(io.open(path, "rb"), "cannot open " .. path)
    local source = handle:read("*a")
    handle:close()
    return source
end

local toc = ReadSource("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc")
local optionalDeps = toc:match("## OptionalDeps:[^\r\n]*") or ""
assert(not optionalDeps:lower():find("masque", 1, true),
    "MSUF must not advertise Masque as an optional dependency")

local shippedRoots = {
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Options",
    "MidnightSimpleUnitFrames_Assistant",
}
local pipe = assert(io.popen("git ls-files -- " .. table.concat(shippedRoots, " "), "r"),
    "cannot enumerate shipped MSUF sources")
local forbiddenMasqueTokens = { "MSUF_Masque", "_msufMasque", "__MSQ" }
local shippedSourceCount = 0

for path in pipe:lines() do
    if path:match("%.lua$") or path:match("%.xml$") or path:match("%.toc$") then
        local source = ReadSource(path)
        shippedSourceCount = shippedSourceCount + 1
        local _, retiredSettingCount = source:gsub("masqueEnabled", "")
        if path == "MidnightSimpleUnitFrames/State/MSUF_Defaults.lua" then
            assert(retiredSettingCount == 2
                    and source:find("scope.masqueEnabled ~= nil", 1, true)
                    and source:find("scope.masqueEnabled = nil", 1, true),
                "State defaults may only inspect and purge the retired Masque setting")
        elseif path == "MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua" then
            assert(retiredSettingCount == 3
                    and source:find("db.gf_party.masqueEnabled = nil", 1, true)
                    and source:find("db.gf_raid.masqueEnabled = nil", 1, true)
                    and source:find("db.gf_mythicraid.masqueEnabled = nil", 1, true),
                "Group defaults may only purge the retired Masque setting")
        else
            assert(retiredSettingCount == 0,
                "retired Masque setting found outside the profile cleanup path in " .. path)
        end
        for i = 1, #forbiddenMasqueTokens do
            assert(not source:find(forbiddenMasqueTokens[i], 1, true),
                string.format("unsupported Masque token %q found in %s", forbiddenMasqueTokens[i], path))
        end
        assert(not source:match("LibStub%s*%(%s*['\"]Masque['\"]"),
            "Masque library acquisition found in " .. path)
    end
end

local pipeOk, pipeReason, pipeCode = pipe:close()
assert(pipeOk or pipeCode == 0, "git ls-files failed: " .. tostring(pipeReason or pipeCode))

local router = ReadSource("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRouter.lua")
assert(router:find("does not register its aura buttons with Masque", 1, true),
    "Assistant must describe Masque as unsupported by MSUF 6.0")

print(string.format(
    "PASS addon interop guards: boss settled in %d SetParent calls, /rl yielded, Masque absent across %d sources",
    setParentCalls, shippedSourceCount))

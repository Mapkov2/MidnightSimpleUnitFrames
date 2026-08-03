--- Classic-only ownership for Blizzard frames replaced by MSUF.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local Client = MSUF.Client
if not (Client and Client.IsClassic == true) then return end

MSUF.Compat = MSUF.Compat or {}
local Compat = MSUF.Compat
local state = Compat.ClassicFrameOwnership or {}
Compat.ClassicFrameOwnership = state

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

local function Protected(frame)
    return frame and frame.IsProtected and frame:IsProtected() or false
end

local function EnsureDeferredDriver()
    if state.driver then return state.driver end
    local driver = _G.CreateFrame("Frame")
    driver:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local pending = state.pending
        state.pending = {}
        for frame, action in pairs(pending or {}) do
            if action == true then
                if state.suppressed == true and frame.Hide then frame:Hide() end
            elseif state.suppressed ~= true and type(action) == "table"
                and type(action.restore) == "function" then
                action.restore(frame)
            end
        end
    end)
    state.driver = driver
    return driver
end

local function Defer(frame, action)
    state.pending = state.pending or {}
    state.pending[frame] = action
    EnsureDeferredDriver():RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function HideOwnedResourceFrame(frame)
    if state.suppressed == true and frame and frame.Hide then
        if InCombat() and Protected(frame) then
            Defer(frame, true)
        else
            frame:Hide()
        end
    end
end

function Compat.SetBlizzardClassResourcesSuppressed(suppress)
    suppress = suppress == true
    local wasSuppressed = state.suppressed == true
    state.suppressed = suppress

    local provider = MSUF.CPClient
    local definitions = provider and provider.BlizzardFrames or {}
    local found = false
    state.frames = state.frames or {}

    for i = 1, #definitions do
        local definition = definitions[i]
        local frame = definition and _G[definition.name]
        if frame then
            found = true
            if state.frames[definition.name] ~= frame then
                state.frames[definition.name] = frame
                if frame.HookScript then
                    frame:HookScript("OnShow", HideOwnedResourceFrame)
                end
            end

            if suppress then
                if InCombat() and Protected(frame) then
                    Defer(frame, true)
                elseif not frame.IsShown or frame:IsShown() then
                    frame:Hide()
                end
            elseif wasSuppressed and type(definition.restore) == "function" then
                if InCombat() and Protected(frame) then
                    Defer(frame, definition)
                else
                    definition.restore(frame)
                end
            end
        end
    end
    return found
end

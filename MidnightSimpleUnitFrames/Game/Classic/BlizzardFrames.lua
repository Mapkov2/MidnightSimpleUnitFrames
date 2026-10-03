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

--- Mists class bars inherit PlayerFrameBottomManagedFrameTemplate
--- (Blizzard_UnitFrame/Shared/PlayerFrameTemplates.xml: isManagedFrame and a
--- layoutParent). Their OnShow/OnHide add them to or remove them from
--- PlayerFrameBottomManagedFramesContainer and lay it out, which also
--- re-anchors the secure PetFrame. A Show() or Hide() from addon code runs that
--- layout tainted, in combat or out of it, so a managed bar is never shown or
--- hidden here: it is concealed (alpha 0, no mouse) while Blizzard keeps
--- showing and hiding it, and the release gives the alpha and the mouse back.
local function Managed(frame)
    return frame ~= nil and (frame.isManagedFrame == true or frame.layoutParent ~= nil)
end

--- A protected frame is not touched in combat lockdown; the change waits for
--- PLAYER_REGEN_ENABLED.
local function CombatDeferred(frame)
    return InCombat() and Protected(frame)
end

--- Conceals a managed frame. The alpha and the mouse are recorded once, so
--- repeated conceals never record the concealed state. A recorded alpha 0 (a
--- showAnim fade-in, e.g. Mists PriestBarFrame:CheckAndShow) is stored as 1,
--- the alpha those bars settle at, so the release never blanks them.
local function ConcealManagedFrame(frame)
    if not frame or Protected(frame) or not (frame.SetAlpha and frame.GetAlpha) then return end
    state.muted = state.muted or {}
    if state.muted[frame] == nil then
        local alpha = frame:GetAlpha()
        state.muted[frame] = (alpha and alpha > 0) and alpha or 1
    end
    frame:SetAlpha(0)
    state.mouse = state.mouse or {}
    if state.mouse[frame] == nil and frame.IsMouseEnabled and frame.EnableMouse then
        local mouse = frame:IsMouseEnabled() == true
        state.mouse[frame] = mouse
        if mouse then frame:EnableMouse(false) end
    end
end

local function RevealManagedFrame(frame)
    local muted = state.muted
    local alpha = muted and muted[frame]
    if alpha ~= nil then
        muted[frame] = nil
        frame:SetAlpha(alpha)
    end
    local mouse = state.mouse and state.mouse[frame]
    if mouse ~= nil then
        state.mouse[frame] = nil
        if mouse then frame:EnableMouse(true) end
    end
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
        if Managed(frame) then
            ConcealManagedFrame(frame)
        elseif CombatDeferred(frame) then
            Defer(frame, true)
        else
            frame:Hide()
        end
    end
end

--- A managed bar's fade-in (showAnim: alpha 0 to 1, then SetAlpha(1) when it
--- finishes) would reveal a concealed bar, so it is stopped while MSUF owns
--- the bar; the finish re-conceals in case it ran anyway.
local function StopOwnedFadeIn(anim)
    if state.suppressed ~= true then return end
    anim:Stop()
    ConcealManagedFrame(anim:GetParent())
end

local function ConcealOwnedFadeIn(anim)
    if state.suppressed == true then ConcealManagedFrame(anim:GetParent()) end
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
            local managed = Managed(frame)
            if state.frames[definition.name] ~= frame then
                state.frames[definition.name] = frame
                if frame.HookScript then
                    frame:HookScript("OnShow", HideOwnedResourceFrame)
                end
                local fadeIn = managed and frame.showAnim
                if fadeIn and fadeIn.HookScript then
                    fadeIn:HookScript("OnPlay", StopOwnedFadeIn)
                    fadeIn:HookScript("OnFinished", ConcealOwnedFadeIn)
                end
            end

            if suppress then
                if managed then
                    ConcealManagedFrame(frame)
                elseif CombatDeferred(frame) then
                    Defer(frame, true)
                elseif not frame.IsShown or frame:IsShown() then
                    frame:Hide()
                end
            elseif managed then
                -- Blizzard kept showing and hiding it: only the concealment ends.
                if state.pending then state.pending[frame] = nil end
                RevealManagedFrame(frame)
            elseif wasSuppressed and type(definition.restore) == "function" then
                if CombatDeferred(frame) then
                    Defer(frame, definition)
                else
                    definition.restore(frame)
                end
            end
        end
    end
    return found
end

--- Classic clients have no CompactArenaFrame: their arena UI is the legacy
--- LoadOnDemand Blizzard_ArenaUI (ArenaEnemyFrames + ArenaPrepFrames with
--- secure ArenaEnemyFrameN children). Treat the containers like the boss
--- container (reparent + hook) and the secure children like boss frames
--- (unregister + hide, never reparent). Only the MSUF arena slots
--- (_G.MSUF_MAX_ARENA_FRAMES) are hidden; Vanilla has 0 and is never touched.
--- The addon only loads when an arena match starts, so the pass also re-runs
--- once on its ADDON_LOADED. HandleFrame keeps the Kernel combat deferral.
local function HideLegacyArenaFrames(handleFrame, shouldHide)
    if _G.CompactArenaFrame or not shouldHide("arena") then return end
    local slots = tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 0
    -- MAX_ARENA_ENEMIES is defined only by LoadOnDemand Blizzard_ArenaUI, so it
    -- is nil at every login until that addon loads: never compare it bare. If
    -- Blizzard fields more opponents than MSUF has slots, stand down entirely.
    local blizzardSlots = tonumber(_G.MAX_ARENA_ENEMIES)
    if slots <= 0 or (blizzardSlots ~= nil and blizzardSlots > slots) then return end
    handleFrame(_G.ArenaEnemyFrames, nil, "arena")
    handleFrame(_G.ArenaPrepFrames, nil, "arena")
    for i = 1, slots do
        handleFrame(_G["ArenaEnemyFrame" .. i], true, "arena")
        handleFrame(_G["ArenaPrepFrame" .. i], true, "arena")
    end
end

local function LegacyArenaSuppressionPass(handleFrame, shouldHide)
    HideLegacyArenaFrames(handleFrame, shouldHide)
    if state.legacyArenaWatcher or _G.CompactArenaFrame or _G.ArenaEnemyFrames then return end
    if (tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 0) <= 0 or not shouldHide("arena") then return end
    local watcher = _G.CreateFrame("Frame")
    state.legacyArenaWatcher = watcher
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, addonName)
        if addonName ~= "Blizzard_ArenaUI" then return end
        self:UnregisterEvent("ADDON_LOADED")
        HideLegacyArenaFrames(handleFrame, shouldHide)
    end)
end

MSUF.BlizzardFrameSuppressionPasses = MSUF.BlizzardFrameSuppressionPasses or {}
table.insert(MSUF.BlizzardFrameSuppressionPasses, LegacyArenaSuppressionPass)

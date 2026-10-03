-- Cold lifecycle for the optional resource helpers; the disabled default owns
-- no events. Spec, form and displayed-power changes rebuild the helpers on
-- their own, also while Class Resources are off and the class power refresh
-- does not run for them. In combat the helpers only hide or show what they
-- drew; the rebuild follows at combat end.
local _, MSUF = ...
MSUF.CPBuilders = MSUF.CPBuilders or {}

-- The one list of switches that need a helper. The class power controller and
-- its config ask it too. Profiles saved under the former key names are moved to
-- the current ones by the profile translator (MSUF.ProfileNormalize in
-- State/MSUF_ProfileNormalize.lua) at login, switch and import.
function MSUF.CPBuilders.ResourceExtrasWanted(b)
    return type(b) == "table" and (b.showIgnorePain == true or b.showArcaneWindow == true
        or b.manaUpcomingCost == true or b.manaRegenPause == true or b.manaGainPulse == true
        or (type(b.resourceMarks) == "table" and #b.resourceMarks > 0)) or false
end

function MSUF.CPBuilders.ResourceExtras(E)
    local helpers = {}
    local events = CreateFrame("Frame")
    local disabled, queued = false, false
    local Refresh, Disable
    local function InCombat() return InCombatLockdown and InCombatLockdown() end
    local function RefreshHelper(key, wanted)
        if wanted and not helpers[key] and MSUF.CPBuilders[key] then helpers[key] = MSUF.CPBuilders[key](E) end
        local helper = helpers[key]
        if helper then if wanted then helper.Refresh() else helper.Disable() end end
    end
    local function AnyPending()
        for _, helper in pairs(helpers) do
            if helper.IsPending and helper.IsPending() then return true end
        end
        return false
    end
    Refresh = function()
        disabled = false
        if InCombat() then
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        local b = E.db.bars or {}
        events:UnregisterAllEvents()
        RefreshHelper("ExtraAuras", b.showIgnorePain == true or b.showArcaneWindow == true)
        RefreshHelper("ManaExtras", b.manaUpcomingCost == true or b.manaRegenPause == true or b.manaGainPulse == true)
        RefreshHelper("ResourceMarks", type(b.resourceMarks) == "table" and #b.resourceMarks > 0)
        if MSUF.CPBuilders.ResourceExtrasWanted(b) then
            events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
            events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
            if not E.SupportsEvent or E.SupportsEvent("PLAYER_SPECIALIZATION_CHANGED") then
                events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
            end
        end
        -- The Arcane window's global cooldown count follows spell haste.
        local auras = helpers.ExtraAuras
        if auras and auras.UsesHaste and auras.UsesHaste() then events:RegisterUnitEvent("UNIT_SPELL_HASTE", "player") end
        if AnyPending() then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    end
    Disable = function()
        disabled = true
        events:UnregisterAllEvents()
        for _, helper in pairs(helpers) do helper.Disable() end
        -- An aura sensor cannot be parked in combat; finish at combat end.
        if AnyPending() then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    end
    -- One frame later, so MSUF's power element has handled the same event.
    local function ColdChange()
        queued = false
        if disabled then return end
        if InCombat() then
            for _, helper in pairs(helpers) do
                if helper.PowerChanged then helper.PowerChanged() end
            end
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            Refresh()
        end
    end
    E.RequestRefresh = function()
        if queued or disabled then return end
        queued = true
        C_Timer.After(0, ColdChange)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            events:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if disabled then Disable() else Refresh() end
        elseif event == "UNIT_SPELL_HASTE" then
            if helpers.ExtraAuras then helpers.ExtraAuras.RefreshHaste() end
        else
            E.RequestRefresh()
        end
    end)
    return { Refresh = Refresh, Disable = Disable }
end

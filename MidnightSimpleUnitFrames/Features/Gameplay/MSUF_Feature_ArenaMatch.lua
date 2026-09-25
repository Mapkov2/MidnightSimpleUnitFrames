local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Features/Gameplay/MSUF_Feature_ArenaMatch.lua
--- Arena match helpers for the dedicated arena1..N unit frames
--- (N = MSUF.Client.MaxArenaOpponents: 3 on Mainline, 5 on TBC/Mists):
---   1. Prep-room opponent display: before the gates open the arena units do
---      not exist, so RegisterUnitWatch keeps the frames hidden. During the
---      preparation phase this module force-shows the frames (out of combat,
---      so Show() on the protected buttons is legal). The PTR display delegate
---      paints secret specs; older clients retain the plain spec path.
---   2. Stealthed-opponent placeholder: ARENA_OPPONENT_UPDATE "unseen" clears
---      the unit, which securely hides the real frame. A separate INSECURE
---      overlay (Blizzard's StealthedArenaUnitFrame pattern) marks the slot
---      while the match is engaged.
--- All work is event-driven; no OnUpdate, no polling.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

-- arena1..N (N = MSUF.Client.MaxArenaOpponents: 3 on Mainline, 5 on TBC/Mists).
-- Game/Shared/Initialize.lua publishes it as MSUF_MAX_ARENA_FRAMES; clamp it to
-- 0..5 and fall back to 3 when the client initializer did not run.
local MAX_ARENA = math.max(0, math.min(5, math.floor(tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3)))
local HAS_PVP_MATCH_STATE_CHANGED = _G.C_EventUtils
    and type(_G.C_EventUtils.IsEventValid) == "function"
    and _G.C_EventUtils.IsEventValid("PVP_MATCH_STATE_CHANGED") == true
local classicMatchEngaged = false

local function InCombat()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
end

local function ArenaConf()
    local db = _G.MSUF_DB
    return db and db.arena or nil
end

local function ArenaEnabled()
    local conf = ArenaConf()
    return not conf or conf.enabled ~= false
end

local function ArenaFrame(index)
    local uf = MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame("arena" .. index)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return (frames and frames["arena" .. index]) or _G["MSUF_arena" .. index]
end

local function MatchState()
    local getState = _G.C_PvP and _G.C_PvP.GetActiveMatchState
    if type(getState) ~= "function" then return nil end
    return getState()
end

local function MatchEngaged()
    local states = _G.Enum and _G.Enum.PvPMatchState
    local engaged = states and states.Engaged
    if engaged ~= nil and MatchState() == engaged then return true end
    return HAS_PVP_MATCH_STATE_CHANGED ~= true and classicMatchEngaged == true
end

local function MatchPreparing()
    local considered = _G.C_PvP and _G.C_PvP.IsMatchConsideredArena
    if type(considered) == "function" then
        if considered() ~= true then return false end

        -- Retail 12.1 reports the room/countdown as Waiting or StartUp. Neither
        -- state satisfies IsMatchActive/IsMatchEngaged, so using the live-match
        -- gate here suppresses every unitless preparation frame.
        local state = MatchState()
        local states = _G.Enum and _G.Enum.PvPMatchState
        local waiting = states and states.Waiting or 1
        local startUp = states and states.StartUp or 2
        return state == waiting or state == startUp
    end

    -- Classic has the arena/prep events and opponent-spec APIs, but no
    -- PVP_MATCH_STATE_CHANGED or C_PvP match-state API. The prep event arms
    -- this path; the first opponent update performs the engaged hand-off.
    local activeArena = _G.IsActiveBattlefieldArena
    return HAS_PVP_MATCH_STATE_CHANGED ~= true
        and type(activeArena) == "function" and activeArena() == true
        and classicMatchEngaged ~= true
end

local function InArenaMatch()
    local considered = _G.C_PvP and _G.C_PvP.IsMatchConsideredArena
    if type(considered) == "function" then
        if considered() ~= true then return false end
        local active = _G.C_PvP and _G.C_PvP.IsMatchActive
        local complete = _G.C_PvP and _G.C_PvP.IsMatchComplete
        return (type(active) == "function" and active() == true)
            or (type(complete) == "function" and complete() == true)
            or MatchEngaged()
    end
    local activeArena = _G.IsActiveBattlefieldArena
    return HAS_PVP_MATCH_STATE_CHANGED ~= true
        and type(activeArena) == "function" and activeArena() == true
end

------------------------------------------------------------------------
-- 1) Prep-room opponent display
------------------------------------------------------------------------

local prepActive = false

local function SyncPrepVisibility(opponentCount)
    opponentCount = math.floor(tonumber(opponentCount) or 0)
    if opponentCount < 0 then opponentCount = 0 end
    if opponentCount > MAX_ARENA then opponentCount = MAX_ARENA end
    local active = opponentCount > 0
    local previousCount = tonumber(_G.MSUF_ArenaPrepVisibilityCount) or 0
    if (_G.MSUF_ArenaPrepVisibilityActive == true) == active
        and previousCount == opponentCount then
        return false
    end

    -- arena1..N (N = MSUF.Client.MaxArenaOpponents: 3 on Mainline, 5 on
    -- TBC/Mists) do not exist during preparation. Their ordinary
    -- RegisterUnitWatch owner therefore keeps the protected buttons hidden and
    -- wins over a direct frame:Show(). Hand visibility to LoadConditions for
    -- this out-of-combat phase; it installs the existing secure
    -- "[nocombat] show" driver and restores RegisterUnitWatch when prep ends.
    _G.MSUF_ArenaPrepVisibilityActive = active and true or nil
    _G.MSUF_ArenaPrepVisibilityCount = active and opponentCount or nil
    local uf = MSUF.UF
    if uf and type(uf.RefreshVisibilityDrivers) == "function" then
        uf.RefreshVisibilityDrivers("arena")
    end
    return true
end

local function OpponentSpecInfo(index)
    local getSpec = _G.GetArenaOpponentSpec
    if type(getSpec) ~= "function" then return nil end
    local specID, gender = getSpec(index)
    local issecret = _G.issecretvalue
    if issecret and (issecret(specID) == true or issecret(gender) == true) then return nil end
    if not specID or specID <= 0 then return nil end
    local getInfo = _G.GetSpecializationInfoByID
    if type(getInfo) ~= "function" then return nil end
    local _, specName, _, icon, role, classToken, className = getInfo(specID, gender)
    return specName, icon, role, classToken, className
end

local function ClassColor(classToken)
    local getColor = _G.C_ClassColor and _G.C_ClassColor.GetClassColor
    if type(getColor) == "function" and classToken then
        local color = getColor(classToken)
        if color and color.r then return color.r, color.g, color.b end
    end
    return 0.85, 0.10, 0.10
end

local function SetPrepBar(bar, r, g, b)
    if not bar then return end
    if bar.SetMinMaxValues then bar:SetMinMaxValues(0, 1) end
    if bar.SetValue then bar:SetValue(1) end
    if bar.SetStatusBarColor then
        bar:SetStatusBarColor(r, g, b, 1)
        bar._msufR, bar._msufG, bar._msufB, bar._msufA = nil, nil, nil, nil
        bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = nil, nil, nil, nil
    end
    if bar.Show then bar:Show() end
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fill and fill.SetAlpha then
        fill:SetAlpha(1)
        fill._msufAlphaHealth = nil
        fill._msufAlphaStatusTexture = nil
    end
end

local function SetPrepNameClassColor(frame, r, g, b)
    local spec = frame and frame.MSUFSpec
    local textSpec = spec and spec.text
    if not (textSpec and textSpec.nameClassColor == true) then return end

    -- A prep opponent has no live unit identity, so the normal name-color
    -- resolver cannot read UnitClass and falls back to its blue unknown color.
    -- We already own a plain class token from GetArenaOpponentSpec; feed its
    -- resolved RGB through the same cached text setter used by live frames.
    local fallback = spec and spec.textColor
    local alpha = fallback and fallback.a or 1
    local text = MSUF.UFText
    if text and type(text.SetNameTextColor) == "function" then
        text.SetNameTextColor(frame, r, g, b, alpha)
        return
    end
    if frame.nameText and frame.nameText.SetTextColor then
        frame.nameText:SetTextColor(r, g, b, alpha)
    end
    if frame._msufNameDotsFS and frame._msufNameDotsFS.SetTextColor then
        frame._msufNameDotsFS:SetTextColor(r, g, b, alpha)
    end
    frame._msufNameTextR, frame._msufNameTextG = r, g
    frame._msufNameTextB, frame._msufNameTextA = b, alpha
end

local function SeedPrepFrameState(frame, classToken, className)
    frame._msufArenaPrepForced = true
    local state = frame._msufUnitState
    if type(state) ~= "table" then return end
    state.exists = true
    state.existsKnown = true
    state.dead = false
    state.connected = true
    state.connectedKnown = true
    state.identityIsPlayerRead = true
    state.isPlayer = true
    state.isPlayerKnown = true
    state.identityClassRead = classToken ~= nil
    state.className = className or classToken
    state.classToken = classToken
end

local function ApplyPrepFrame(frame, index)
    local util = _G.UnitFrameUtil
    local updateDisplay = util and util.UpdateArenaOpponentSpecDisplay
    if type(updateDisplay) == "function" then
        -- The delegate owns all secret spec/class decisions. Its hasSpec
        -- return can be secret, so only the plain roster count controls
        -- visibility and no class identity is cached on the frame.
        SeedPrepFrameState(frame)
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
        local bar = frame.hpBar or frame.Health
        SetPrepBar(bar, 1, 1, 1)
        local elements = frame._msufArenaPrepElements
        if not elements then
            elements = {}
            frame._msufArenaPrepElements = elements
        end
        elements.specNameText = frame.nameText
        elements.barTexture = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
        updateDisplay(elements, index)
        if frame.nameText then
            local updateName = util.UpdateArenaOpponentSpecDisplayName
            if type(updateName) == "function" then
                updateName(frame.nameText, index)
            end
            frame.nameText:Show()
        end
        local fallback = frame.MSUFSpec and frame.MSUFSpec.textColor
        SetPrepNameClassColor(frame, fallback and fallback.r or 1,
            fallback and fallback.g or 1, fallback and fallback.b or 1)
        return true
    end

    local specName, _, _, classToken, className = OpponentSpecInfo(index)
    if not specName then return false end
    SeedPrepFrameState(frame, classToken, className)
    frame:Show()
    if frame.SetAlpha then frame:SetAlpha(1) end
    if frame.nameText then
        frame.nameText:SetText(specName .. (className and (" - " .. className) or ""))
        frame.nameText:Show()
    end
    local r, g, b = ClassColor(classToken)
    SetPrepNameClassColor(frame, r, g, b)
    SetPrepBar(frame.hpBar or frame.Health, r, g, b)
    return true
end

local function ClearPrepFrame(frame)
    if not frame or frame._msufArenaPrepForced ~= true then return false end
    frame._msufArenaPrepForced = nil
    frame._msufUnitState = nil
    frame._msufAlphaLastFrame = nil
    frame._msufAlphaLastHP = nil
    frame._msufAlphaLastFG = nil
    return true
end

local function LiveUnitExists(unit)
    local secrets = MSUF.Secrets
    if secrets and type(secrets.UnitExistsPlain) == "function" then
        return secrets.UnitExistsPlain(unit) == true
    end
    local exists = _G.UnitExists and _G.UnitExists(unit)
    if _G.issecretvalue and _G.issecretvalue(exists) == true then return true end
    return exists == true
end

local function AnyLiveArenaUnit()
    for index = 1, MAX_ARENA do
        if LiveUnitExists("arena" .. index) then return true end
    end
    return false
end

local function SyncPrepDisplay()
    -- The prep room is out of combat by definition; never touch protected
    -- frame visibility once combat lockdown is up.
    if InCombat() then return end

    local numSpecs = tonumber(_G.GetNumArenaOpponentSpecs and _G.GetNumArenaOpponentSpecs()) or 0
    numSpecs = math.max(0, math.min(MAX_ARENA, math.floor(numSpecs)))
    local wantPrep = ArenaEnabled()
        and MatchPreparing()
        and numSpecs > 0
    local prepCount = wantPrep and numSpecs or 0

    -- Swap visibility ownership before writing the synthetic opponent data.
    -- Otherwise RegisterUnitWatch can immediately hide these unitless frames.
    local changed = SyncPrepVisibility(prepCount)
    for index = 1, MAX_ARENA do
        local frame = ArenaFrame(index)
        if frame then
            if index <= prepCount and not LiveUnitExists("arena" .. index) then
                changed = ApplyPrepFrame(frame, index) or changed
            else
                if ClearPrepFrame(frame) then
                    changed = true
                    -- Hand visibility back to the secure unit watch: without a
                    -- live unit the watch hides the frame on its own; with one
                    -- it repaints from real data via the identity lane.
                    if not LiveUnitExists("arena" .. index) and frame.Hide then
                        frame:Hide()
                    elseif frame.ForceUpdate then
                        frame:ForceUpdate("MSUF_ARENA_PREP_END")
                    end
                end
            end
        end
    end
    prepActive = wantPrep
    return changed
end

------------------------------------------------------------------------
-- 2) Stealthed-opponent placeholders (insecure overlays)
------------------------------------------------------------------------

local stealthOverlays = {}
local unseenSlots = {}

local function EnsureStealthOverlay(index)
    local overlay = stealthOverlays[index]
    if overlay then return overlay end
    local frame = ArenaFrame(index)
    if not frame then return nil end

    overlay = PixelLayoutRegion(CreateFrame("Frame", "MSUF_ArenaStealthOverlay" .. index, UIParent))
    overlay:SetFrameStrata("MEDIUM")
    overlay:Hide()

    overlay.bg = PixelLayoutRegion(overlay:CreateTexture(nil, "BACKGROUND"))
    overlay.bg:SetAllPoints(overlay)
    overlay.bg:SetColorTexture(0, 0, 0, 0.55)

    overlay.icon = PixelLayoutRegion(overlay:CreateTexture(nil, "ARTWORK"))
    overlay.icon:SetSize(18, 18)
    overlay.icon:SetPoint("LEFT", overlay, "LEFT", 4, 0)
    overlay.icon:SetTexture("Interface\\ICONS\\Ability_Stealth")

    overlay.text = PixelLayoutRegion(overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    overlay.text:SetPoint("LEFT", overlay.icon, "RIGHT", 6, 0)
    overlay.text:SetText(_G.ARENA_UNIT_STEALTHED or "Stealthed")

    stealthOverlays[index] = overlay
    return overlay
end

local function PositionStealthOverlay(overlay, index)
    local frame = ArenaFrame(index)
    if not frame then return false end
    overlay:ClearAllPoints()
    -- Anchoring an insecure overlay to a secure frame is safe; only the
    -- overlay is manipulated from Lua and it never intercepts mouse input.
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    return true
end

local function SyncStealthOverlays()
    local engaged = MatchEngaged()
    for index = 1, MAX_ARENA do
        local overlay = stealthOverlays[index]
        local wanted = ArenaEnabled()
            and engaged
            and unseenSlots[index] == true
            and not LiveUnitExists("arena" .. index)
        if wanted then
            overlay = EnsureStealthOverlay(index)
            if overlay and PositionStealthOverlay(overlay, index) then
                overlay:Show()
            end
        elseif overlay then
            overlay:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Event wiring (EventBus preferred; direct frame fallback)
------------------------------------------------------------------------

local function HandleArenaMatchEvent(event, arg1, arg2)
    if event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        if HAS_PVP_MATCH_STATE_CHANGED ~= true then classicMatchEngaged = false end
        SyncPrepDisplay()
        return
    end
    if event == "PVP_MATCH_STATE_CHANGED" then
        SyncPrepDisplay()
        SyncStealthOverlays()
        return
    end
    if event == "ARENA_OPPONENT_UPDATE" then
        local unit, reason = arg1, arg2
        local issecret = _G.issecretvalue
        if type(unit) == "string" and (not issecret or issecret(unit) ~= true) then
            local index = tonumber(unit:match("^arena(%d+)$"))
            if index then
                local plainReason = (not issecret or issecret(reason) ~= true) and reason or nil
                unseenSlots[index] = (plainReason == "unseen") or nil
                if HAS_PVP_MATCH_STATE_CHANGED ~= true then
                    if plainReason == "seen" or plainReason == "unseen" or plainReason == "destroyed" then
                        classicMatchEngaged = true
                    elseif plainReason == "cleared" then
                        local activeArena = _G.IsActiveBattlefieldArena
                        if type(activeArena) ~= "function" or activeArena() ~= true then
                            classicMatchEngaged = false
                        end
                    end
                end
            end
        end
        if prepActive then SyncPrepDisplay() end
        SyncStealthOverlays()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if HAS_PVP_MATCH_STATE_CHANGED ~= true then
            classicMatchEngaged = AnyLiveArenaUnit()
        end
        for index = 1, MAX_ARENA do
            unseenSlots[index] = nil
        end
        SyncPrepDisplay()
        SyncStealthOverlays()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat blocked a pending prep hand-off (round transition edge).
        SyncPrepDisplay()
        return
    end
end

local eventFrame
local function WireEvents()
    local register = _G.MSUF_EventBus_Register
    if type(register) == "function" then
        register("ARENA_PREP_OPPONENT_SPECIALIZATIONS", "MSUF_ARENA_MATCH_PREP", HandleArenaMatchEvent)
        if HAS_PVP_MATCH_STATE_CHANGED then
            register("PVP_MATCH_STATE_CHANGED", "MSUF_ARENA_MATCH_STATE", HandleArenaMatchEvent)
        end
        register("ARENA_OPPONENT_UPDATE", "MSUF_ARENA_MATCH_OPPONENT", HandleArenaMatchEvent)
        register("PLAYER_ENTERING_WORLD", "MSUF_ARENA_MATCH_WORLD", HandleArenaMatchEvent)
        register("PLAYER_REGEN_ENABLED", "MSUF_ARENA_MATCH_REGEN", HandleArenaMatchEvent)
        return
    end
    eventFrame = eventFrame or CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        HandleArenaMatchEvent(event, ...)
    end)
    eventFrame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
    if HAS_PVP_MATCH_STATE_CHANGED then eventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED") end
    eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Defensive: Client.UnsupportedUnits marks arena absent on Classic Era, whose
-- TOC still loads this module. The helpers stay exported, but no arena event
-- is subscribed there.
local client = MSUF.Client
if not (client and type(client.SupportsUnit) == "function" and client.SupportsUnit("arena1") == false) then
    WireEvents()
end

ExportPublic("MSUF_ArenaMatch_SyncPrepDisplay", SyncPrepDisplay)
ExportPublic("MSUF_ArenaMatch_SyncStealthOverlays", SyncStealthOverlays)

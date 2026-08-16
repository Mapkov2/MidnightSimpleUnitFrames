--- Features/Gameplay/MSUF_Feature_ArenaMatch.lua
--- Arena match helpers for the dedicated arena1-3 unit frames:
---   1. Prep-room opponent display: before the gates open the arena units do
---      not exist, so RegisterUnitWatch keeps the frames hidden. During the
---      preparation phase this module force-shows the frames (out of combat,
---      so Show() on the protected buttons is legal) and seeds a synthetic
---      class/spec identity from GetArenaOpponentSpec.
---   2. Stealthed-opponent placeholder: ARENA_OPPONENT_UPDATE "unseen" clears
---      the unit, which securely hides the real frame. A separate INSECURE
---      overlay (Blizzard's StealthedArenaUnitFrame pattern) marks the slot
---      while the match is engaged.
---   3. Trinket/CC readiness: a per-frame icon driven by
---      ARENA_CROWD_CONTROL_SPELL_UPDATE / ARENA_COOLDOWNS_UPDATE. Enemy
---      cooldown numbers are secret to addons in 12.x, so the swipe uses the
---      secret-safe DurationObject route when available.
--- All work is event-driven; no OnUpdate, no polling.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local MAX_ARENA = 3
local TRINKET_FALLBACK_ICON = 1322720 -- inv_jewelry_trinketpvp_01

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
    local isEngaged = _G.C_PvP and _G.C_PvP.IsMatchEngaged
    if type(isEngaged) == "function" then return isEngaged() == true end
    return false
end

local function InArenaMatch()
    local considered = _G.C_PvP and _G.C_PvP.IsMatchConsideredArena
    if type(considered) ~= "function" or considered() ~= true then return false end
    local active = _G.C_PvP and _G.C_PvP.IsMatchActive
    local complete = _G.C_PvP and _G.C_PvP.IsMatchComplete
    return (type(active) == "function" and active() == true)
        or (type(complete) == "function" and complete() == true)
        or MatchEngaged()
end

------------------------------------------------------------------------
-- 1) Prep-room opponent display
------------------------------------------------------------------------

local prepActive = false

local function OpponentSpecInfo(index)
    local getSpec = _G.GetArenaOpponentSpec
    if type(getSpec) ~= "function" then return nil end
    local specID, gender = getSpec(index)
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

local function ApplyPrepFrame(frame, index)
    local specName, _, _, classToken, className = OpponentSpecInfo(index)
    if not specName then return false end

    frame._msufArenaPrepForced = true
    local state = frame._msufUnitState
    if type(state) == "table" then
        state.exists = true
        state.existsKnown = true
        state.dead = false
        state.connected = true
        state.connectedKnown = true
        state.identityIsPlayerRead = true
        state.isPlayer = true
        state.isPlayerKnown = true
        state.identityClassRead = true
        state.className = className or classToken
        state.classToken = classToken
    end

    frame:Show()
    if frame.SetAlpha then frame:SetAlpha(1) end
    if frame.nameText then
        frame.nameText:SetText(specName .. (className and (" - " .. className) or ""))
        frame.nameText:Show()
    end
    SetPrepBar(frame.hpBar or frame.Health, ClassColor(classToken))
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

local function SyncPrepDisplay()
    -- The prep room is out of combat by definition; never touch protected
    -- frame visibility once combat lockdown is up.
    if InCombat() then return end

    local numSpecs = _G.GetNumArenaOpponentSpecs and _G.GetNumArenaOpponentSpecs() or 0
    local wantPrep = ArenaEnabled()
        and InArenaMatch()
        and not MatchEngaged()
        and (tonumber(numSpecs) or 0) > 0

    local changed = false
    for index = 1, MAX_ARENA do
        local frame = ArenaFrame(index)
        if frame then
            if wantPrep and index <= numSpecs and not LiveUnitExists("arena" .. index) then
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

    overlay = CreateFrame("Frame", "MSUF_ArenaStealthOverlay" .. index, UIParent)
    overlay:SetFrameStrata("MEDIUM")
    overlay:Hide()

    overlay.bg = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.bg:SetAllPoints(overlay)
    overlay.bg:SetColorTexture(0, 0, 0, 0.55)

    overlay.icon = overlay:CreateTexture(nil, "ARTWORK")
    overlay.icon:SetSize(18, 18)
    overlay.icon:SetPoint("LEFT", overlay, "LEFT", 4, 0)
    overlay.icon:SetTexture("Interface\\ICONS\\Ability_Stealth")

    overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
-- 3) Trinket / crowd-control readiness icons
------------------------------------------------------------------------

local trinketIcons = {}

local function EnsureTrinketIcon(index)
    local holder = trinketIcons[index]
    if holder then return holder end
    local frame = ArenaFrame(index)
    if not frame then return nil end

    holder = CreateFrame("Frame", "MSUF_ArenaTrinket" .. index, UIParent)
    holder:SetSize(20, 20)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()

    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints(holder)
    holder.icon:SetTexture(TRINKET_FALLBACK_ICON)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    holder.cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    holder.cooldown:SetAllPoints(holder)
    holder.cooldown:SetDrawEdge(false)

    trinketIcons[index] = holder
    return holder
end

local function PositionTrinketIcon(holder, index)
    local frame = ArenaFrame(index)
    if not frame then return false end
    holder:ClearAllPoints()
    holder:SetPoint("LEFT", frame, "RIGHT", 4, 0)
    return true
end

local function ShowTrinketEnabled()
    local conf = ArenaConf()
    return not conf or conf.showTrinket ~= false
end

local function UpdateTrinketCooldown(holder, index)
    local unit = "arena" .. index
    local cooldown = holder.cooldown
    if not cooldown then return end

    -- Secret-safe order: the DurationObject route accepts secret enemy
    -- cooldowns from tainted code; the numeric route stays as a fallback for
    -- contexts where the info is not restricted (e.g. spectators).
    local getDuration = _G.C_PvP and _G.C_PvP.GetArenaCrowdControlDuration
    if type(getDuration) == "function" and cooldown.SetCooldownFromDurationObject then
        local duration = getDuration(unit)
        if duration ~= nil then
            cooldown:SetCooldownFromDurationObject(duration)
            return
        end
    end
    local getInfo = _G.C_PvP and _G.C_PvP.GetArenaCrowdControlInfo
    if type(getInfo) == "function" then
        local spellID, startTimeMs, durationMs = getInfo(unit)
        local issecret = _G.issecretvalue
        if spellID and (not issecret or issecret(startTimeMs) ~= true) then
            local startTime = (tonumber(startTimeMs) or 0) / 1000
            local durationSec = (tonumber(durationMs) or 0) / 1000
            if durationSec > 0 then
                cooldown:SetCooldown(startTime, durationSec)
            else
                cooldown:Clear()
            end
            if spellID and holder.icon then
                local getTexture = _G.C_Spell and _G.C_Spell.GetSpellTexture
                local texture = type(getTexture) == "function" and getTexture(spellID) or nil
                if texture and (not issecret or issecret(texture) ~= true) then
                    holder.icon:SetTexture(texture)
                end
            end
        end
    end
end

-- One request per slot per match segment. The CC response events
-- (ARENA_CROWD_CONTROL_SPELL_UPDATE / ARENA_COOLDOWNS_UPDATE) must NEVER
-- re-request: request -> response event -> request would self-sustain and
-- fan out 1:3 per round-trip, which pegs the CPU the moment gates open.
local ccRequested = {}

local function SyncTrinketIcons(allowRequest)
    local active = ArenaEnabled() and ShowTrinketEnabled() and InArenaMatch()
    for index = 1, MAX_ARENA do
        local unit = "arena" .. index
        local holder = trinketIcons[index]
        local wanted = active and LiveUnitExists(unit)
        if wanted then
            holder = EnsureTrinketIcon(index)
            if holder and PositionTrinketIcon(holder, index) then
                holder:Show()
                if allowRequest and not ccRequested[index] then
                    local request = _G.C_PvP and _G.C_PvP.RequestCrowdControlSpell
                    if type(request) == "function" then
                        ccRequested[index] = true
                        request(unit)
                    end
                end
                UpdateTrinketCooldown(holder, index)
            end
        else
            ccRequested[index] = nil
            if holder then holder:Hide() end
        end
    end
end

------------------------------------------------------------------------
-- Event wiring (EventBus preferred; direct frame fallback)
------------------------------------------------------------------------

local function HandleArenaMatchEvent(event, arg1, arg2)
    if event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        SyncPrepDisplay()
        return
    end
    if event == "PVP_MATCH_STATE_CHANGED" then
        SyncPrepDisplay()
        SyncStealthOverlays()
        SyncTrinketIcons(true)
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
            end
        end
        if prepActive then SyncPrepDisplay() end
        SyncStealthOverlays()
        SyncTrinketIcons(true)
        return
    end
    if event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" or event == "ARENA_COOLDOWNS_UPDATE" then
        -- Response events refresh from the delivered data only; re-requesting
        -- here would close the request/response feedback loop.
        SyncTrinketIcons(false)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        for index = 1, MAX_ARENA do
            unseenSlots[index] = nil
            ccRequested[index] = nil
        end
        SyncPrepDisplay()
        SyncStealthOverlays()
        SyncTrinketIcons(true)
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
        register("PVP_MATCH_STATE_CHANGED", "MSUF_ARENA_MATCH_STATE", HandleArenaMatchEvent)
        register("ARENA_OPPONENT_UPDATE", "MSUF_ARENA_MATCH_OPPONENT", HandleArenaMatchEvent)
        register("ARENA_CROWD_CONTROL_SPELL_UPDATE", "MSUF_ARENA_MATCH_CC", HandleArenaMatchEvent)
        register("ARENA_COOLDOWNS_UPDATE", "MSUF_ARENA_MATCH_CD", HandleArenaMatchEvent)
        register("PLAYER_ENTERING_WORLD", "MSUF_ARENA_MATCH_WORLD", HandleArenaMatchEvent)
        register("PLAYER_REGEN_ENABLED", "MSUF_ARENA_MATCH_REGEN", HandleArenaMatchEvent)
        return
    end
    eventFrame = eventFrame or CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        HandleArenaMatchEvent(event, ...)
    end)
    eventFrame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
    eventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
    eventFrame:RegisterEvent("ARENA_CROWD_CONTROL_SPELL_UPDATE")
    eventFrame:RegisterEvent("ARENA_COOLDOWNS_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

WireEvents()

ExportPublic("MSUF_ArenaMatch_SyncPrepDisplay", SyncPrepDisplay)
ExportPublic("MSUF_ArenaMatch_SyncStealthOverlays", SyncStealthOverlays)
ExportPublic("MSUF_ArenaMatch_SyncTrinketIcons", function() SyncTrinketIcons(true) end)

--- Guardian Druid Ironfur duration tracker.
--- Each successful Ironfur cast owns one estimated lifetime marker. The
--- moving display is active-only and never reads restricted aura durations.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local modeBuilders = _G.MSUF_CP_MODE_BUILDERS
if type(modeBuilders) ~= "table" then
    modeBuilders = {}
    ExportPublic("MSUF_CP_MODE_BUILDERS", modeBuilders)
end

modeBuilders.IRONFUR = function(E)
    if E.PLAYER_CLASS ~= "DRUID" then return nil end

    local CP = E.CP
    local CPK = E.CPK
    local GetTime = E.GetTime or GetTime
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local EnsureMainText = E.EnsureMainText
    local ApplyFont = E.ApplyFont
    local GetVisual = E.GetVisual
    local CreateFrame = CreateFrame
    local C_SpellBook = C_SpellBook
    local tostring = tostring

    local IRONFUR_SPELL = 192081
    local URSOCS_ENDURANCE = 393611
    local GUARDIAN_OF_ELUNE = 155578
    local MANGLE_SPELL = 33917
    local FRENZIED_REGENERATION = 22842
    local GOE_BONUS = 3
    local GOE_WINDOW = 15
    local MOTION_INTERVAL = 1 / 30
    local MAX_TRACKED_CASTS = 32
    local HASH_WIDTH = 2

    local active = false
    local eventsBound = false
    local elapsed = 0
    local goeUntil = 0
    local tickEnds = {}
    local tickDurations = {}
    local tickCount = 0
    local hashes = {}
    local visibleHashCount = 0
    local seenGUID = {}
    local seenRing = {}
    local seenWrite, seenCount = 1, 0
    local cachedWidth, cachedHeight = 0, 0
    local layoutDirty = true
    local staticDirty = true
    local configDirty = true
    local showHashes = true
    local baseDuration = 7
    local guardianOfEluneKnown = false
    local cachedVisual
    local visualVersion = -1
    local lastCount = -1

    local eventFrame = CreateFrame("Frame")
    local motionFrame = CreateFrame("Frame")
    motionFrame:Hide()

    local function IsKnown(spellID)
        local known = C_SpellBook and C_SpellBook.IsSpellKnown
        return type(known) == "function" and known(spellID) == true
    end

    local function ClearSeenGUIDs()
        for i = 1, MAX_TRACKED_CASTS do
            local guid = seenRing[i]
            if guid then
                seenGUID[guid] = nil
                seenRing[i] = nil
            end
        end
        seenWrite, seenCount = 1, 0
    end

    local function CastGUIDSeen(guid)
        if not guid then return false end
        if seenGUID[guid] then return true end
        if seenCount >= MAX_TRACKED_CASTS then
            local old = seenRing[seenWrite]
            if old then seenGUID[old] = nil end
        else
            seenCount = seenCount + 1
        end
        seenRing[seenWrite] = guid
        seenGUID[guid] = true
        seenWrite = (seenWrite % MAX_TRACKED_CASTS) + 1
        return false
    end

    local function HideHashes(from)
        from = from or 1
        for i = from, visibleHashCount do
            local tex = hashes[i]
            if tex._msufIronfurShown then
                tex._msufIronfurShown = nil
                tex:Hide()
            end
        end
        if from <= visibleHashCount then visibleHashCount = from - 1 end
    end

    local function ClearState()
        for i = tickCount, 1, -1 do
            tickEnds[i] = nil
            tickDurations[i] = nil
        end
        tickCount = 0
        goeUntil = 0
        elapsed = 0
        lastCount = -1
        ClearSeenGUIDs()
        HideHashes(1)
        motionFrame:Hide()
    end

    local function ApplyState(bar, visual, count, force)
        local version = visual and visual.version or 0
        local visualChanged = visualVersion ~= version
        local countChanged = lastCount ~= count
        if not (force or visualChanged or countChanged) then return end

        if visualChanged or force then
            local r = visual and visual.baseR or 1
            local g = visual and visual.baseG or 0.49
            local b = visual and visual.baseB or 0.04
            bar:SetStatusBarColor(r, g, b, 1)
            if bar._bg then
                bar._bg:SetVertexColor(
                    visual and visual.bgR or 0,
                    visual and visual.bgG or 0,
                    visual and visual.bgB or 0,
                    visual and visual.bgAlpha or 0.3)
            end
        end
        bar:SetAlpha(count > 0 and (visual and visual.filledAlpha or 1)
            or (visual and visual.emptyAlpha or 0.3))

        local text = CP.text
        if visual and visual.showText == true then
            local created
            if not text and EnsureMainText then text, created = EnsureMainText() end
            if created and ApplyFont then ApplyFont() end
            if text then
                text:SetText(count > 0 and tostring(count) or "")
                text:SetShown(count > 0)
            end
        elseif text then
            text:Hide()
        end

        if CP_CheckAutoHide then CP_CheckAutoHide(count > 0 and 1 or 0, 1) end
        visualVersion, lastCount = version, count
    end

    local function Update()
        local bar = CP and CP.bars and CP.bars[1]
        if not (active and CP.visible and CP.renderMode == CPK.MODE.IRONFUR and bar) then
            HideHashes(1)
            motionFrame:Hide()
            return false
        end

        local now = GetTime()
        local i = 1
        while i <= tickCount do
            if tickEnds[i] <= now then
                tickEnds[i] = tickEnds[tickCount]
                tickDurations[i] = tickDurations[tickCount]
                tickEnds[tickCount] = nil
                tickDurations[tickCount] = nil
                tickCount = tickCount - 1
            else
                i = i + 1
            end
        end

        local forceState = false
        if staticDirty then
            staticDirty = false
            forceState = true
            bar:SetMinMaxValues(0, 1)
            bar:Show()
            for barIndex = 2, CP.maxBars or 1 do
                if CP.bars[barIndex] then CP.bars[barIndex]:Hide() end
            end
            for tickIndex = 1, #(CP.ticks or {}) do
                if CP.ticks[tickIndex] then CP.ticks[tickIndex]:Hide() end
            end
        end
        if configDirty then
            configDirty = false
            showHashes = not (E._cpDB.bars and E._cpDB.bars.guardianIronfurShowHashLines == false)
            baseDuration = IsKnown(URSOCS_ENDURANCE) and 9 or 7
            guardianOfEluneKnown = IsKnown(GUARDIAN_OF_ELUNE)
            cachedVisual = GetVisual and GetVisual() or CP.visual
            forceState = true
        end

        if showHashes and tickCount > 0 and layoutDirty then
            cachedWidth = (bar.GetWidth and bar:GetWidth()) or 0
            cachedHeight = (bar.GetHeight and bar:GetHeight()) or 0
            layoutDirty = false
        end
        local width, height = cachedWidth, cachedHeight
        local renderHashes = showHashes and width > 0 and height > 0
        local maxFraction, shown = 0, 0

        for tickIndex = 1, tickCount do
            local duration = tickDurations[tickIndex]
            local fraction = (tickEnds[tickIndex] - now) / duration
            if fraction > maxFraction then maxFraction = fraction end
            if renderHashes then
                shown = shown + 1
                local tex = hashes[shown]
                if not tex then
                    tex = bar:CreateTexture(nil, "OVERLAY", nil, 7)
                    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
                    tex:SetVertexColor(1, 1, 1, 0.9)
                    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
                    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
                    hashes[shown] = tex
                end
                local x = fraction * width
                if x > width - HASH_WIDTH then x = width - HASH_WIDTH end
                tex:ClearAllPoints()
                if tex._msufIronfurHeight ~= height then
                    tex._msufIronfurHeight = height
                    tex:SetSize(HASH_WIDTH, height)
                end
                tex:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
                if not tex._msufIronfurShown then
                    tex._msufIronfurShown = true
                    tex:Show()
                end
            end
        end
        if shown < visibleHashCount then HideHashes(shown + 1) end
        visibleHashCount = shown

        if forceState or lastCount ~= tickCount then
            ApplyState(bar, cachedVisual, tickCount, forceState)
        end
        bar:SetValue(maxFraction)
        if tickCount == 0 then motionFrame:Hide() end
        return tickCount > 0
    end

    motionFrame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < MOTION_INTERVAL then return end
        elapsed = elapsed % MOTION_INTERVAL
        Update()
    end)

    eventFrame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
        if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
            ClearState()
            Update()
            return
        end
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit ~= "player" then return end
        if spellID ~= IRONFUR_SPELL and spellID ~= MANGLE_SPELL and spellID ~= FRENZIED_REGENERATION then return end
        if CastGUIDSeen(castGUID) then return end
        local now = GetTime()
        if spellID == IRONFUR_SPELL then
            local duration = baseDuration
            local hasGoE = goeUntil > now and guardianOfEluneKnown
            if hasGoE then duration = duration + GOE_BONUS; goeUntil = 0 end
            if tickCount < MAX_TRACKED_CASTS then
                tickCount = tickCount + 1
            else
                local earliest = 1
                for i = 2, tickCount do
                    if tickEnds[i] < tickEnds[earliest] then earliest = i end
                end
                tickEnds[earliest] = tickEnds[tickCount]
                tickDurations[earliest] = tickDurations[tickCount]
            end
            tickEnds[tickCount] = now + duration
            tickDurations[tickCount] = duration
            motionFrame:Show()
            Update()
        elseif spellID == MANGLE_SPELL and guardianOfEluneKnown then
            goeUntil = now + GOE_WINDOW
        elseif spellID == FRENZIED_REGENERATION then
            goeUntil = 0
        end
    end)

    local function SetActive(want)
        want = want == true
        layoutDirty = true
        staticDirty = true
        configDirty = true
        visualVersion = -1
        lastCount = -1
        if active == want then
            if active then Update() end
            return
        end
        active = want
        if want then
            if not eventsBound then
                eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                eventFrame:RegisterEvent("PLAYER_DEAD")
                eventFrame:RegisterEvent("PLAYER_ALIVE")
                eventsBound = true
            end
            Update()
        else
            if eventsBound then
                eventFrame:UnregisterAllEvents()
                eventsBound = false
            end
            ClearState()
        end
    end

    return {
        Update = Update,
        SetActive = SetActive,
        InvalidateLayout = function() layoutDirty = true; staticDirty = true end,
        RefreshVisual = function()
            cachedVisual = GetVisual and GetVisual() or CP.visual
            visualVersion = -1
            lastCount = -1
            Update()
        end,
        IsActive = function() return active end,
    }
end

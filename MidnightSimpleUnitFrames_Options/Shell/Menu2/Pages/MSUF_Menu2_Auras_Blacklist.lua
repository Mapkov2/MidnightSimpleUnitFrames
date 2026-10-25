-- Auras: Blacklist responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.AurasParts
if not Parts then return end
local AuraCatalogToken = Parts.AuraCatalogToken
local ActionButton = Parts.ActionButton
local AddTooltip = Parts.AddTooltip
local ApplyUnit = Parts.ApplyUnit
local AuraControlMeta = Parts.AuraControlMeta
local BindDropdown = Parts.BindDropdown
local BindTextInput = Parts.BindTextInput
local CreateCustomDebuffBlacklistInfoButton = Parts.CreateCustomDebuffBlacklistInfoButton
local CreateFrame = Parts.CreateFrame
local Model = Parts.Model
local PixelLayoutRegion = Parts.PixelLayoutRegion
local QueueAurasPageRefresh = Parts.QueueAurasPageRefresh
local RegisterAuraControl = Parts.RegisterAuraControl
local RegisterAuraTextAction = Parts.RegisterAuraTextAction
local T = Parts.T
local Tr = Parts.Tr
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local min = Parts.min
local pairs = Parts.pairs
local tonumber = Parts.tonumber
local tostring = Parts.tostring
local type = Parts.type

-- hot path: kept whole (perf rule)
local function EnsureAuraCombatScanner()
    -- The scanner overlay is a shared singleton parked on M.
    local s = M._auraCombatScanner
    if not s then
        s = PixelLayoutRegion(CreateFrame("Frame", nil, UIParent))
        M._auraCombatScanner = s
        s:SetSize(372, 100)
        s:SetPoint("TOP", UIParent, "TOP", 0, -160)
        s:SetFrameStrata("DIALOG")
        s:SetMovable(true)
        s:EnableMouse(true)
        s:RegisterForDrag("LeftButton")
        s:SetScript("OnDragStart", function(self) self:StartMoving() end)
        s:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        s:SetClampedToScreen(true)
        if T.ApplyBackdrop then T.ApplyBackdrop(s, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
        s.title = T.Font(s, "GameFontHighlightSmall", "", T.colors.accent)
        s.title:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -10)
        s.count = T.Font(s, "GameFontDisableSmall", "", T.colors.muted)
        s.count:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -28)
        s.hint = T.Font(s, "GameFontDisableSmall", "", T.colors.muted)
        s.hint:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -42)
        s.hint:SetPoint("TOPRIGHT", s, "TOPRIGHT", -12, -42)
        s.hint:SetJustifyH("LEFT")
        s.hint:Hide()
        s.icons = {}
        for i = 1, 12 do
            local tex = PixelLayoutRegion(s:CreateTexture(nil, "ARTWORK"))
            tex:SetSize(20, 20)
            tex:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 12 + (i - 1) * 24, 10)
            tex:Hide()
            s.icons[i] = tex
        end
        s.stopBtn = ActionButton(s, "Stop scan", 96)
        s.stopBtn:SetPoint("TOPRIGHT", s, "TOPRIGHT", -10, -10)
        s.stopBtn._msuf2AllowCombatClick = true
        s.stopBtn._msuf2SkipHistoryCheckpoint = true
        s.Finish = function(reopen)
            if not s._scanning then return end
            s._scanning = nil
            s.Pause()
            M.auraBlacklistVerify = {
                unit = s._scope, lane = s._lane, status = "scan",
                liveCount = s._lastLive or 0, sessionCount = s._count or 0,
                secretCount = s._unreadable or 0,
            }
            if reopen and not (M.BlockCombatAction and M.BlockCombatAction()) then
                M.Open(s._returnPage)
            end
        end
        s.stopBtn:SetScript("OnClick", function()
            s.Finish(not (M.BlockCombatAction and M.BlockCombatAction()))
            return true
        end)
        s:SetScript("OnEvent", function(self)
            if self:IsShown() then self.Finish(true) end
        end)
        s.Scan = function(self, elapsed)
            self._accum = (self._accum or 0) + (tonumber(elapsed) or 0)
            if self._accum < 0.4 then return end
            self._accum = 0
            local live, unreadable, blocked
            if type(Model.LiveBlacklistAuraValues) == "function" then
                live, unreadable, blocked = Model.LiveBlacklistAuraValues(self._scope, self._lane)
            end
            if blocked then
                -- Access denial is temporary (encounter/M+/PvP); keep
                -- ticking cheaply so the scan resumes on its own.
                self._dots = ((self._dots or 0) % 3) + 1
                T.SetTranslatedText(self.title, Tr("Scanning auras - creating a list") .. string.rep(".", self._dots))
                self.hint:SetText("Blocked by Blizzard during this fight - resumes automatically. In instances, use the curated presets.")
                self.hint:Show()
                return
            end
            live = live or {}
            self._lastLive = #live
            self._unreadable = tonumber(unreadable) or 0
            local store = M.auraBlacklistCaptured
            if type(store) ~= "table" then store = {} M.auraBlacklistCaptured = store end
            local capKey = tostring(self._scope) .. "|" .. tostring(self._lane)
            local captured = store[capKey]
            if type(captured) ~= "table" then captured = {} store[capKey] = captured end
            for i = 1, #live do
                local entry = live[i]
                local cap = captured[entry.value]
                if type(cap) ~= "table" then
                    cap = { name = type(cap) == "string" and cap or nil }
                    captured[entry.value] = cap
                    self._count = (self._count or 0) + 1
                    self._recent[#self._recent + 1] = entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                end
                if type(entry.name) == "string" then cap.name = entry.name end
                if entry.icon ~= nil and cap.icon == nil then cap.icon = entry.icon end
            end
            local total = #self._recent
            for i = 1, #self.icons do
                local tex = self.icons[i]
                local icon = self._recent[total - i + 1]
                if icon then tex:SetTexture(icon) tex:Show() else tex:Hide() end
            end
            self._dots = ((self._dots or 0) % 3) + 1
            T.SetTranslatedText(self.title, Tr("Scanning auras - creating a list") .. string.rep(".", self._dots))
            if (self._unreadable or 0) > 0 then
                T.SetTranslatedText(self.count, M.Format("%d captured so far - %d hidden by Blizzard",
                    self._count or 0, self._unreadable))
                self.hint:SetText("Hidden auras are Blizzard-secret - no addon can block them. Everything blockable was captured.")
                self.hint:Show()
            else
                T.SetTranslatedText(self.count, M.Format("%d captured so far", self._count or 0))
                self.hint:Hide()
            end
        end
        s.Pause = function()
            s:SetScript("OnUpdate", nil)
            s:UnregisterEvent("PLAYER_REGEN_ENABLED")
            s:Hide()
        end
        s.Resume = function()
            if not s._scanning or not M.frame:IsShown() or M.IsConfigCombatLocked() then return end
            s:RegisterEvent("PLAYER_REGEN_ENABLED")
            s:SetScript("OnUpdate", s.Scan)
            s:Show()
        end
        M.MenuRuntime:SetQuiesceSettler("aura-scanner", s.Pause)
        M.frame:HookScript("OnShow", s.Resume)
        s.Pause()
    end
    return s
end
local function ByText(a, b) return tostring(a.text) < tostring(b.text) end
-- A dropdown entry for an aura captured this session but not on the unit now.
local function CapturedAuraEntry(id, cap)
    local capName = type(cap) == "table" and cap.name or (type(cap) == "string" and cap or nil)
    local label = (capName or "Spell") .. " (#" .. tostring(id) .. ")"
    return {
        value = id, name = capName, icon = type(cap) == "table" and cap.icon or nil,
        text = M.Format("%s - captured", label), captured = true,
    }
end
-- The live-scan value sources of one unit lane. Scanning is strictly
-- click-driven: only the Rescan/Block handlers call LiveAuraValues. Refreshes
-- and the dropdown read the cached last scan, so an open menu never scans the
-- unit on its own.
local function CreateLiveScanValues(unit, lane)
    local captureKey = unit .. "|" .. lane
    local function CapturedAuras(wipeStore)
        local store = M.auraBlacklistCaptured
        if type(store) ~= "table" then store = {} M.auraBlacklistCaptured = store end
        if wipeStore then store[captureKey] = nil end
        local captured = store[captureKey]
        if type(captured) ~= "table" then captured = {} store[captureKey] = captured end
        return captured
    end
    local function CountCaptured()
        local count = 0
        for _ in pairs(CapturedAuras(false)) do count = count + 1 end
        return count
    end
    local liveScanCache
    local function LiveAuraValues()
        local values, unreadable, blocked
        if type(Model.LiveBlacklistAuraValues) == "function" then
            values, unreadable, blocked = Model.LiveBlacklistAuraValues(unit, lane)
        end
        values = values or {}
        -- Every scan also feeds the session capture list, so short-lived
        -- combat debuffs stay pickable after they expire or combat ends.
        local captured = CapturedAuras(false)
        local liveSeen = {}
        for i = 1, #values do
            local entry = values[i]
            liveSeen[entry.value] = true
            local cap = captured[entry.value]
            if type(cap) ~= "table" then
                cap = { name = type(cap) == "string" and cap or nil }
                captured[entry.value] = cap
            end
            if type(entry.name) == "string" then cap.name = entry.name end
            if entry.icon ~= nil and cap.icon == nil then cap.icon = entry.icon end
        end
        local capturedOnly = {}
        for id, cap in pairs(captured) do
            if not liveSeen[id] then capturedOnly[#capturedOnly + 1] = CapturedAuraEntry(id, cap) end
        end
        table.sort(capturedOnly, ByText)
        for i = 1, #capturedOnly do values[#values + 1] = capturedOnly[i] end
        if #values == 0 then
            values = { { value = nil, text = Tr("No readable auras right now") } }
        end
        liveScanCache = values
        return values, tonumber(unreadable) or 0, blocked == true
    end
    local function CachedAuraValues()
        if liveScanCache then return liveScanCache end
        -- No scan ran in this menu session yet: show the session capture
        -- store as-is (a plain table read - no unit scan happens here).
        local values = {}
        for id, cap in pairs(CapturedAuras(false)) do values[#values + 1] = CapturedAuraEntry(id, cap) end
        if #values == 0 then
            return { { value = nil, text = Tr("No scan yet - click Rescan") } }
        end
        table.sort(values, ByText)
        return values
    end
    local function CurrentLiveAura()
        local values = CachedAuraValues()
        local selected = M.auraBlacklistLiveSpell
        for i = 1, #values do if values[i].value ~= nil and values[i].value == selected then return selected end end
        for i = 1, #values do if values[i].value ~= nil then return values[i].value end end
        return nil
    end
    return CapturedAuras, CountCaptured, LiveAuraValues, CachedAuraValues, CurrentLiveAura
end
-- A scan session pauses with the menu and resumes on its next open.
local function StartAuraCombatScan(unit, lane, CountCaptured)
    local s = EnsureAuraCombatScanner()
    s._scope, s._lane = unit, lane
    s._returnPage = M.activeKey
    s._recent = {}
    s._accum = 1
    s._dots = 0
    s._lastLive = 0
    local sessionCount = CountCaptured()
    s._count = sessionCount
    s.title:SetText("Scanning auras - creating a list")
    T.SetTranslatedText(s.count, M.Format("%d captured so far", sessionCount))
    if s.hint then s.hint:Hide() end
    for i = 1, #s.icons do s.icons[i]:Hide() end
    s._scanning = true
    s.Resume()
    return true
end
-- A live-scan button is a part of the manual input's composite control.
-- combatSafe: a read-only scan click needs no history checkpoint and works
-- during combat lockdown.
local function LiveScanButton(section, input, label, width, role, x, y, body, combatSafe)
    local button = ActionButton(section, label, width, role)
    button:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(button, input) end
    if combatSafe then
        button._msuf2SkipHistoryCheckpoint = true
        button._msuf2AllowCombatClick = true
    end
    AddTooltip(button, label, body)
    return button
end
local function BuildUnitBlacklistLiveScan(B)
    local ctx, unit, lane, section, inner, showPresets, input = B.ctx, B.unit, B.lane, B.section, B.inner, B.showPresets, B.input
    local liveY = showPresets and -122 or -134
    local liveW = max(140, min(floor(inner * 0.62), inner - 266))
    local CapturedAuras, CountCaptured, LiveAuraValues, CachedAuraValues, CurrentLiveAura = CreateLiveScanValues(unit, lane)
    local liveDrop = BindDropdown(ctx, section, "Active auras on this frame", 24, liveY, CachedAuraValues, liveW,
        CurrentLiveAura, function(value) M.auraBlacklistLiveSpell = value end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.live-aura-selection", "ephemeral"))
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(liveDrop, input) end
    AddTooltip(liveDrop, "Active auras on this frame",
        "Shows the result of the last scan: every readable aura with the exact ID it carried, plus everything captured earlier this session. Press Rescan to "
            .. "scan the current unit - blocking from this list always uses the aura's own ID. Secret auras cannot be listed.")
    local blockLive = LiveScanButton(section, input, "Block selected aura", 150, "primary", 36 + liveW, liveY - 24,
        "Blocks the selected aura using the exact ID it carries right now.")
    blockLive:SetScript("OnClick", function()
        local spellID = CurrentLiveAura()
        if not spellID then return false end
        local auraName, liveNow
        local liveValues = type(Model.LiveBlacklistAuraValues) == "function"
            and Model.LiveBlacklistAuraValues(unit, lane) or {}
        for i = 1, #liveValues do
            if liveValues[i].value == spellID then liveNow = true auraName = liveValues[i].name break end
        end
        if not auraName then
            local values = LiveAuraValues()
            for i = 1, #values do if values[i].value == spellID then auraName = values[i].name break end end
        end
        local changed = Model.AddBlacklistSpell(unit, spellID, lane)
        M.auraBlacklistLiveSpell = nil
        -- Captured entries may no longer be on the unit; only claim the
        -- live-verified state when the aura is actually visible right now.
        M.auraBlacklistVerify = liveNow
            and { unit = unit, lane = lane, status = "active", enteredID = spellID, name = auraName } or nil
        if changed then
            ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
            if B.refreshList then B.refreshList() end
            QueueAurasPageRefresh(ctx, "aura-blacklist-live-added")
        else
            B.renderVerify()
        end
        return changed and true or false
    end)
    B.refreshLiveBlock = function(blocked)
        local liveSel = CurrentLiveAura()
        W.SetControlEnabled(blockLive, liveSel ~= nil and not blocked[tostring(liveSel)])
    end
    -- Scanning only reads C_UnitAuras and repaints plain menu widgets, so
    -- this click is safe during combat lockdown; blocking stays gated.
    local rescan = LiveScanButton(section, input, "Rescan", 96, nil, 36 + liveW + 158, liveY - 24,
        "Re-reads the auras on the current unit and adds everything it sees to this session's captured list - works in combat too. Shift-click clears the "
            .. "captured list.", true)
    rescan:SetScript("OnClick", function()
        if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
            CapturedAuras(true)
        end
        M.auraBlacklistLiveSpell = nil
        local values, secretCount, blocked = LiveAuraValues()
        local liveCount = 0
        for i = 1, #values do
            if values[i].value ~= nil and not values[i].captured then liveCount = liveCount + 1 end
        end
        M.auraBlacklistVerify = {
            unit = unit, lane = lane, status = "scan", blocked = blocked or nil,
            liveCount = liveCount, sessionCount = CountCaptured(), secretCount = secretCount,
        }
        if liveDrop.SetValue then liveDrop:SetValue(CurrentLiveAura()) end
        if B.refreshList then B.refreshList() end
        return true
    end)
    local startScan = LiveScanButton(section, input, "Start combat scan", 170, nil, 24, liveY - 54,
        "Scanning auras - creating a list", true)
    startScan:SetScript("OnClick", function() return StartAuraCombatScan(unit, lane, CountCaptured) end)
end
local function BuildUnitBlacklistManualEntry(B)
    local ctx, unit, lane, section, inner, isDebuff, enemyDebuff = B.ctx, B.unit, B.lane, B.section, B.inner, B.isDebuff, B.enemyDebuff
    if not isDebuff or enemyDebuff then
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 130))
        local inputLabel = enemyDebuff and "Enemy debuff Spell ID, link, or name"
            or "Enter buff Spell ID, link, or name"
        local addLabel = enemyDebuff and "Add enemy debuff" or "Add custom buff"
        local input = BindTextInput(ctx, section, inputLabel, 24, -36, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.manual-input", "ephemeral"))
        B.input = input
        if enemyDebuff then CreateCustomDebuffBlacklistInfoButton(section, input, unit) end
        AddTooltip(input, "Spell ID vs. aura ID",
            "The aura on the unit can use a different Spell ID than the spell you cast. Enter the ID shown on the aura itself. After adding, MSUF checks the "
                .. "live unit and warns when only a same-named aura with a different ID is active.")
        local add = ActionButton(section, addLabel, enemyDebuff and 132 or 118, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -60)
        local verifyText = W.Text(section, "", 24, -92, inner - 214, T.colors.muted)
        if verifyText.SetMaxLines then verifyText:SetMaxLines(2) end
        local swapBtn = ActionButton(section, "", 180, "primary")
        swapBtn:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -86)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(swapBtn, input) end
        swapBtn:Hide()
        B.renderVerify = function()
            local state = M.auraBlacklistVerify
            local mine = state and state.unit == unit and state.lane == lane and state or nil
            if not mine then
                verifyText:SetText("")
            elseif mine.status == "scan" and mine.blocked then
                local c = T.colors.accent2 or T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                verifyText:SetText("Blizzard is blocking aura scanning right now (encounter, Mythic+, or PvP match). Use the curated presets - they cover "
                    .. "everything blockable in instanced content.")
            elseif mine.status == "scan" then
                local c = T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                if (mine.secretCount or 0) > 0 then
                    local scanText = "Scan complete: %d auras readable right now, %d captured this session. "
                        .. "%d more are hidden by Blizzard and cannot be blocked by any addon."
                    T.SetTranslatedText(verifyText, M.Format(scanText, mine.liveCount or 0, mine.sessionCount or 0, mine.secretCount))
                else
                    T.SetTranslatedText(verifyText, M.Format("Scan complete: %d auras readable right now, %d captured this session.",
                        mine.liveCount or 0, mine.sessionCount or 0))
                end
            elseif mine.status == "active" then
                local c = T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                T.SetTranslatedText(verifyText, M.Format("%s (#%d) is active on this frame right now - blacklist entry verified.",
                    tostring(mine.name or "Spell"), mine.enteredID or 0))
            else
                local c = T.colors.accent2 or T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                T.SetTranslatedText(verifyText,
                    M.Format("#%d is not active on this frame, but %s is currently active as #%d. The aura's ID can differ from your cast's Spell ID.",
                    mine.enteredID or 0, tostring(mine.suggestName or "Spell"), mine.suggestID or 0))
            end
            local showSwap = mine ~= nil and mine.status == "mismatch" and mine.suggestID ~= nil
            if showSwap and swapBtn._msuf2Label and swapBtn._msuf2Label.SetText then
                T.SetTranslatedText(swapBtn._msuf2Label, M.Format("Block #%d instead", mine.suggestID))
            end
            swapBtn:SetShown(showSwap)
            if B.nonPresetHint then B.nonPresetHint:SetShown(mine == nil) end
        end
        swapBtn:SetScript("OnClick", function()
            local state = M.auraBlacklistVerify
            local mine = state and state.unit == unit and state.lane == lane and state or nil
            if not (mine and mine.suggestID) then return false end
            if mine.enteredID and mine.enteredID ~= mine.suggestID then
                Model.RemoveBlacklistSpell(unit, mine.enteredID, lane)
            end
            Model.AddBlacklistSpell(unit, mine.suggestID, lane)
            M.auraBlacklistVerify = {
                unit = unit, lane = lane, status = "active",
                enteredID = mine.suggestID, name = mine.suggestName,
            }
            ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
            if B.refreshList then B.refreshList() end
            QueueAurasPageRefresh(ctx, "aura-blacklist-swap-suggested")
            return true
        end)
        BuildUnitBlacklistLiveScan(B)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputValue
            local spellID = type(Model.ResolveSpellInputID) == "function" and Model.ResolveSpellInputID(value) or nil
            local changed = Model.AddBlacklistSpell(unit, value, lane)
            if changed then
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
            end
            -- The aura left on the unit can carry a different SpellID than the
            -- cast the entry resolved to; compare against the live unit so the
            -- mismatch surfaces immediately instead of failing silently.
            M.auraBlacklistVerify = nil
            local verdict = spellID and type(Model.FindLiveBlacklistAura) == "function"
                and Model.FindLiveBlacklistAura(unit, spellID, lane) or nil
            if verdict then
                M.auraBlacklistVerify = {
                    unit = unit, lane = lane, status = verdict.status,
                    enteredID = spellID, name = verdict.name,
                    suggestID = verdict.suggestID, suggestName = verdict.suggestName,
                }
            end
            if changed then
                if B.refreshList then B.refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-manual-added")
            else
                B.renderVerify()
            end
            if input and input.SetText then input:SetText("") end
            inputValue = ""
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, input, addLabel,
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-manual", {
            actionKey = "aura_blacklist_add_spell", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "value",
        })
        if enemyDebuff then
            AddTooltip(add, "Add enemy debuff",
                "Adds one exact harmful aura to this Target, Focus, or Boss blacklist. Blizzard applies arbitrary SpellID filters only while the unit is not "
                    .. "assistable.")
        else
            AddTooltip(add, "Add custom buff", "Adds one exact buff to this frame's blacklist.")
        end
    end
end
local function BuildUnitBlacklistPresetsAndList(B)
    local ctx, unit, lane, section, inner, isDebuff, enemyDebuff, showPresets, combinedManualAndPresets =
        B.ctx, B.unit, B.lane, B.section, B.inner, B.isDebuff, B.enemyDebuff, B.showPresets, B.combinedManualAndPresets
    local refreshList
    local curatedOffset = combinedManualAndPresets and -174 or 0
    local presetW = max(130, min(floor(inner * 0.62), inner - 138))
    local spellW = max(160, min(floor(inner * 0.68), inner - 108))
    local function PresetValues()
        return type(Model.UnitBlacklistPresetValues) == "function"
            and Model.UnitBlacklistPresetValues(unit, lane) or Model.BlacklistPresetValues()
    end
    local function CurrentPreset()
        local fallback = type(Model.UnitBlacklistDefaultPreset) == "function"
            and Model.UnitBlacklistDefaultPreset(unit, lane) or "RAID_BUFFS"
        local key = M.auraBlacklistPreset or fallback
        local values = PresetValues()
        for i = 1, #values do if values[i].value == key then return key end end
        for i = 1, #values do if values[i].value then return values[i].value end end
        return fallback
    end
    local function SpellValues()
        return type(Model.UnitBlacklistSpellValues) == "function"
            and Model.UnitBlacklistSpellValues(unit, lane, CurrentPreset())
            or Model.BlacklistSpellValues(CurrentPreset())
    end
    local function CurrentSpell()
        local values = SpellValues()
        local blocked = M.AuraControls.BlockedSet(Model.BlacklistEntries(unit, lane))
        return M.AuraControls.FirstUnblockedSpell(values, M.auraBlacklistSpell, blocked)
    end
    local selectedSummary, addSet, addSpell
    if showPresets then
        BindDropdown(ctx, section, "Preset", 24, -36 + curatedOffset, PresetValues, presetW, CurrentPreset,
            function(value)
                M.auraBlacklistPreset = value
                M.auraBlacklistSpell = nil
                QueueAurasPageRefresh(ctx, "aura-blacklist-preset")
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.preset-selection", "ephemeral"))
        addSet = ActionButton(section, "Add entire set", 126, "primary")
        addSet:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + presetW, -60 + curatedOffset)
        addSet:SetScript("OnClick", function()
            local count = Model.AddBlacklistPresetGroup(unit, CurrentPreset(), lane)
            if count > 0 then
                M.auraBlacklistSpell = nil
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_PRESET_GROUP_ADD", true)
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-preset-group-added")
            end
            return count > 0
        end)
        RegisterAuraControl(ctx, addSet, "Add entire set", "button", "unit-workspace.lane." .. AuraCatalogToken(lane)
            .. ".blacklist.add-preset-set", "action", {
            actionKey = "aura_blacklist_add_preset", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "preset",
        })
        AddTooltip(addSet, "Add entire set", "Blocks every aura in the selected curated MSUF set.")
        selectedSummary = W.Text(section, "", 24, -92 + curatedOffset, inner, T.colors.muted)
        BindDropdown(ctx, section, "Spell", 24, -120 + curatedOffset, SpellValues, spellW, CurrentSpell,
            function(value) M.auraBlacklistSpell = value end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.spell-selection", "ephemeral"))
        addSpell = ActionButton(section, "Add spell", 96)
        addSpell:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + spellW, -144 + curatedOffset)
        addSpell:SetScript("OnClick", function()
            local changed = Model.AddBlacklistPresetSpell(unit, CurrentSpell(), lane)
            if changed then
                M.auraBlacklistSpell = nil
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_PRESET_ADD", true)
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-preset-spell-added")
            end
            return changed and true or false
        end)
        RegisterAuraControl(ctx, addSpell, "Add spell", "button", "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-preset-spell", "action", {
            actionKey = "aura_blacklist_add_spell", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "value",
        })
        AddTooltip(addSpell, "Add spell", "Blocks only the selected aura from the curated set.")
    else
        B.nonPresetHint = W.Text(section,
            "Enemy debuffs: hide only exact noisy SpellIDs. Selected Dots on target are handled automatically by that scope's Auto-blacklist toggle.",
            24, -104, inner, T.colors.muted)
    end
    local listOffset = showPresets and curatedOffset or (enemyDebuff and -48 or 44)
    local prepared = W.Text(section, "", 24, -186 + listOffset, inner, T.colors.accent)
    local searchValue = ""
    local searchInput = BindTextInput(ctx, section, "Search", 24, -210 + listOffset, inner,
        function() return searchValue end,
        function(value)
            searchValue = tostring(value or "")
            if refreshList then refreshList() end
        end,
        true, AuraControlMeta(ctx,
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.search", "ephemeral"))
    if searchInput and searchInput.HookScript then
        searchInput:HookScript("OnTextChanged", function(self)
            searchValue = self.GetText and tostring(self:GetText() or "") or ""
            if refreshList then refreshList() end
        end)
    end
    local emptyText = enemyDebuff and not showPresets and "No blocked enemy debuffs. Add an exact SpellID above."
        or (enemyDebuff and "No blocked spells. Add one above or use a preset.")
        or (isDebuff and "No blocked spells. Add one from the allowed presets above."
        or "No blocked spells. Add one above or use a preset.")
    local blockedList = M.AuraControls.BlockedSpellList(ctx, section, inner, listOffset, emptyText, {
        schemaScope = "auras",
        remove = function(spellID)
            if not Model.RemoveBlacklistSpell(unit, spellID, lane) then return end
            ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_REMOVE", true)
            if refreshList then refreshList() end
            QueueAurasPageRefresh(ctx, "aura-blacklist-removed")
        end,
        removePath = function(value)
            return "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.entry." .. AuraCatalogToken(value) .. ".remove"
        end,
    })
    refreshList = function()
        local entries = Model.BlacklistEntries(unit, lane)
        local blocked = M.AuraControls.BlockedSet(entries)
        if B.refreshLiveBlock then B.refreshLiveBlock(blocked) end
        if showPresets then
            M.AuraControls.PaintPresetSummary(selectedSummary, addSet, addSpell, SpellValues(), blocked, CurrentSpell)
        end
        blockedList.Paint(entries, searchValue, prepared)
        if B.renderVerify then B.renderVerify() end
    end
    B.refreshList = refreshList
    M.TrackRefresh(ctx, refreshList)
end
local function BuildCompactUnitAuraBlacklist(ctx, b, unit, lane)
    local isDebuff = lane == "debuff"
    local enemyDebuff = isDebuff and unit ~= "player"
    local showPresets = not isDebuff or type(Model.UnitBlacklistPresetValues) ~= "function"
        or #Model.UnitBlacklistPresetValues(unit, lane) > 0
    local combinedManualAndPresets = (not isDebuff or enemyDebuff) and showPresets
    local section = b:Section(isDebuff and "Debuff Blacklist" or "Buff Blacklist",
        combinedManualAndPresets and 620 or ((not isDebuff or enemyDebuff) and 538 or 446))
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local B = {
        ctx = ctx, b = b, unit = unit, lane = lane, section = section, inner = inner,
        isDebuff = isDebuff, enemyDebuff = enemyDebuff, showPresets = showPresets,
        combinedManualAndPresets = combinedManualAndPresets,
    }
    BuildUnitBlacklistManualEntry(B)
    BuildUnitBlacklistPresetsAndList(B)
end

local CreateNestedAuraBuilder = W.CreateNestedAuraBuilder

-- Search patterns that route every Custom container setting of this unit to the
-- container selector.

-- Explicit load-time exports for the following responsibility modules.
Parts.BuildCompactUnitAuraBlacklist = BuildCompactUnitAuraBlacklist
Parts.CreateNestedAuraBuilder = CreateNestedAuraBuilder

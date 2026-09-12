local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 binding layer: edit history.
-- Owns the undo/redo stacks, the history sessions and transactions, the
-- profile snapshot/restore path with its scoped runtime fanout, the history
-- display labels and the RequestUnitApply/SetUnitValue/RequestGeneralApply/
-- SetGeneralValue write helpers that checkpoint through it. Split from
-- MSUF_Menu2_Bindings.lua: it loads right after that file, picks the shared
-- aliases from M and publishes the same M.* names, so pages keep calling
-- M.CaptureHistory, M.Undo, M.RequestUnitApply and friends untouched.
local KS = M.KeySet
local ApplyService = M.ApplyService or _G.MSUF_Menu2_ApplyService
if type(ApplyService) ~= "table" then error("MSUF Menu2 ApplyService missing") end


local CLASSPOWER_FULL_RUNTIME = M.CLASSPOWER_FULL_RUNTIME
local UNIT_KEYS = M.UNIT_KEYS
local IsConfigCombatLocked = M.IsConfigCombatLocked
local DeepCopy = M.DeepCopy
local QueueMenuRefresh = M.QueueMenuRefresh
local CancelQueuedMenuRefresh = M.CancelQueuedMenuRefresh
local HISTORY_LIMIT = 500
local historyDepth = 0
local historyRestoring = false
local historySessionActive = false
local historySessionBaseSnapshot
local historySessionSnapshot
local historySessionDirty = false
local historyTransaction
local historySurfaces = {}
local historySurfaceMarkers = {}
local historySurfaceCount = 0
local deferredHistoryCommit
local function WipeTable(t)
    for k in pairs(t) do t[k] = nil end
end
local function EnsureHistoryStacks()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    return M.historyUndo, M.historyRedo
end
local function DeepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
local function DeepReplace(dst, src, seen)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    seen = seen or {}
    seen[src] = dst
    for k in pairs(dst) do
        if src[k] == nil then dst[k] = nil end
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if seen[v] then
                dst[k] = seen[v]
            else
                if type(dst[k]) ~= "table" then dst[k] = {} end
                DeepReplace(dst[k], v, seen)
            end
        else
            dst[k] = v
        end
    end
end
local function HistoryCharacterKey()
    if type(_G.MSUF_GetCharKey) == "function" then
        local value = _G.MSUF_GetCharKey()
        if type(value) == "string" and value ~= "" then return value end
    end
    if type(_G.UnitName) == "function" and type(_G.GetRealmName) == "function" then
        local name = _G.UnitName("player")
        local realm = _G.GetRealmName()
        if type(name) == "string" and name ~= "" and type(realm) == "string" then
            return name .. "-" .. realm
        end
    end
end
local function SnapshotProfileRouting()
    local key = HistoryCharacterKey()
    if not key then return nil end
    local gdb = _G.MSUF_GlobalDB
    local chars = type(gdb) == "table" and gdb.char or nil
    local char = type(chars) == "table" and chars[key] or nil
    local existed = type(char) == "table"
    local autoSwitch
    if existed then autoSwitch = char.specAutoSwitch end -- Preserve an explicit false value.
    return {
        key = key,
        existed = existed,
        specAutoSwitch = autoSwitch,
        specProfileMap = existed and DeepCopy(char.specProfileMap) or nil,
    }
end
local function SnapshotDB()
    -- Spec-profile routing is the only persisted options family outside the
    -- active profile DB. Keep its tiny per-character state in the same history
    -- transaction so Assistant/UI undo and redo remain truthful for every
    -- setting without copying the complete GlobalDB/profile collection.
    local externalAPI = (type(MSUF) == "table" and MSUF.EditModeAPI) or _G.MSUF_EditModeAPI
    local externalState = type(externalAPI) == "table"
        and type(externalAPI._CaptureHistorySnapshot) == "function"
        and externalAPI._CaptureHistorySnapshot() or nil
    return {
        _msuf2HistoryState = true,
        profileDB = DeepCopy(M.EnsureDB()),
        profileRouting = SnapshotProfileRouting(),
        externalEditMode = externalState,
    }
end
local function HistoryProfileDB(snapshot)
    if type(snapshot) == "table" and snapshot._msuf2HistoryState == true then return snapshot.profileDB end
    return snapshot -- Backward compatibility for a history entry created before this schema.
end
local function RestoreProfileRouting(snapshot)
    local routing = type(snapshot) == "table" and snapshot._msuf2HistoryState == true and snapshot.profileRouting or nil
    if type(routing) ~= "table" or type(routing.key) ~= "string" then return end
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return end
    if type(gdb.char) ~= "table" then gdb.char = {} end
    local char = gdb.char[routing.key]
    if type(char) ~= "table" then char = {}; gdb.char[routing.key] = char end
    if routing.existed then
        char.specAutoSwitch = routing.specAutoSwitch
        char.specProfileMap = DeepCopy(routing.specProfileMap)
    else
        char.specAutoSwitch = nil
        char.specProfileMap = nil
        if next(char) == nil then gdb.char[routing.key] = nil end
    end
end
local function CurrentHistorySnapshot()
    if historySessionActive and type(historySessionSnapshot) == "table" then return historySessionSnapshot end
    return SnapshotDB()
end
local function NotifyHistoryChanged(refreshMenu)
    if M.RefreshHistoryControls then M.RefreshHistoryControls() end
    if M.frame and M.frame.RefreshStatus then M.frame.RefreshStatus(M.frame) end
    if type(_G.MSUF_EM_RefreshHistoryControls) == "function" then
        _G.MSUF_EM_RefreshHistoryControls()
    end
    if refreshMenu == true then QueueMenuRefresh() end
end

-- A third-party element may register after native Edit Mode is already open.
-- Rebase only the current history cursor so the next transaction starts from
-- the newly registered element's real state; session discard remains owned by
-- the Edit Mode API's independent entry snapshot.
function M.SyncExternalHistoryState()
    if historyRestoring or historyDepth > 0 or historyTransaction then return false end
    if not historySessionActive then return false end
    historySessionSnapshot = SnapshotDB()
    NotifyHistoryChanged(false)
    return true
end
-- History labels arrive from three different worlds: hand-written page strings
-- ("Copy Unit Settings"), raw DB keys ("hpBarAlpha") and machine apply reasons
-- ("MSUF2_DASH_GLOBAL_SCALE"). Only the first kind reads like a sentence, so the
-- undo/redo surfaces run every label through one normalizer instead of showing
-- the token. Display only: the stored entry keeps its original label/source.
local HISTORY_LABEL_ACRONYMS = KS("MSUF", "UI", "HP", "NPC", "GCD", "RGB", "AOE", "PVP", "PVE", "XP", "ID")
local HISTORY_LABEL_WORDS = {
    MSUF2 = "MSUF",
    DASH = "Dashboard",
    CLASSPOWER = "Class Power",
    OOC = "Out of Combat",
    TOT = "Target of Target",
    GF = "Group",
    UF = "Unit Frame",
    BG = "Background",
}
local HISTORY_LABEL_OVERRIDES = {
    ["MSUF change"] = "Menu change",
    ["MSUF2 change"] = "Menu change",
    ["MSUF2 option"] = "Menu option",
}
local historyLabelCache = {}
local historyLabelCacheCount = 0
local function HistoryLabelWord(word)
    local upper = word:upper()
    local mapped = HISTORY_LABEL_WORDS[upper]
    if mapped then return mapped end
    if HISTORY_LABEL_ACRONYMS[upper] then return upper end
    return word:sub(1, 1):upper() .. word:sub(2):lower()
end
-- token is one run of [%w_]; only machine-shaped runs (snake, camel, ALLCAPS,
-- or a label that is a bare key with no spaces at all) get rewritten.
local function HistoryLabelToken(token, forceWords)
    local machine = token:find("_", 1, true) ~= nil
        or token:find("%l%u") ~= nil
        or token:match("^%u[%u%d]+$") ~= nil
    if not (machine or forceWords) then return token end
    local spaced = token:gsub("_+", " "):gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
    local out
    for word in spaced:gmatch("%w+") do
        local piece = HistoryLabelWord(word)
        out = out and (out .. " " .. piece) or piece
    end
    return out or token
end
function M.HistoryDisplayLabel(label)
    local text = tostring(label or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return "Menu change" end
    local cached = historyLabelCache[text]
    if cached then return cached end
    local out = HISTORY_LABEL_OVERRIDES[text]
    if not out then
        local body = text:gsub("^MSUF2?_+", "")
        if body == "" then body = text end
        local forceWords = body:find("%s") == nil
        out = body:gsub("[%w_]+", function(token) return HistoryLabelToken(token, forceWords) end)
        out = out:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if out == "" then out = text end
    end
    if historyLabelCacheCount > 300 then
        WipeTable(historyLabelCache)
        historyLabelCacheCount = 0
    end
    historyLabelCache[text] = out
    historyLabelCacheCount = historyLabelCacheCount + 1
    return out
end
local function FeedbackLabel(text, limit)
    text = tostring(text or "")
    limit = tonumber(limit) or 34
    if #text <= limit then return text end
    return text:sub(1, math.max(1, limit - 3)) .. "..."
end
local function CommandFeedback(text, kind, seconds)
    local fn = M.ShowStatusFeedback or M.ShowInlineFeedback
    if type(fn) == "function" then fn(text, kind or "info", seconds or 1.25) end
end
local function PushHistory(label, source, before, after)
    if DeepEqual(before, after) then return false end
    if historySessionActive and type(historySessionBaseSnapshot) ~= "table" then historySessionBaseSnapshot = before end
    local stack, redo = EnsureHistoryStacks()
    stack[#stack + 1] = {
        label = label or "MSUF2 change",
        source = source,
        before = before,
        after = after,
    }
    while #stack > HISTORY_LIMIT do
        table.remove(stack, 1)
    end
    WipeTable(redo)
    if historySessionActive then
        historySessionSnapshot = after
        historySessionDirty = true
    end
    NotifyHistoryChanged(false)
    if type(M.ShowHistoryFeedback) == "function" then
        M.ShowHistoryFeedback(FeedbackLabel(M.HistoryDisplayLabel(label), 30), 2.0)
    end
    return true
end
local function RebuildActivePage()
    local key = M.activeKey
    if key and M.frame and M.frame.IsShown and M.frame:IsShown() and M.InvalidatePage and M.SelectPage then
        M.InvalidatePage(key)
        M.activeKey = nil
        M.SelectPage(key)
    else
        NotifyHistoryChanged(true)
    end
end
local function NormalizeHistoryUnit(unit)
    if ApplyService.NormalizeUnit then return ApplyService.NormalizeUnit(unit) end
    unit = (unit == "tot") and "targettarget" or unit
    unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    if not UNIT_KEYS[unit] then return nil end
    return unit
end
local HISTORY_PAGE_RESET_UNITS = {
    uf_player = "player",
    uf_target = "target",
    uf_targettarget = "targettarget",
    uf_focustarget = "focustarget",
    uf_focus = "focus",
    uf_pet = "pet",
    uf_boss = "boss",
    uf_arena = "arena",
}
local HISTORY_PAGE_RESET_FEATURES = {
    opt_castbar = "castbar",
    classpower = "classpower",
    gameplay = "gameplay",
    modules = "modules",
}
local COLOR_CLASSPOWER_RUNTIME = { colors = true, playerHP = true }
local RequestHistoryAurasRuntime
local RequestHistoryGroupRuntime
local function HistoryUnitFromSource(source)
    if type(source) ~= "string" then return nil end
    local unit = source:match("^unit:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^apply:unit:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^edit_mode:unit:([^:]+)")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^unitPreview:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^status:reset:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    local pageKey = source:match("^page:reset:([^:]+)$")
    if pageKey then return NormalizeHistoryUnit(HISTORY_PAGE_RESET_UNITS[pageKey]) end
    pageKey = source:match("^([^:]+):")
    if pageKey then return NormalizeHistoryUnit(HISTORY_PAGE_RESET_UNITS[pageKey]) end
end
local function HistoryFeatureFromSource(source)
    if type(source) ~= "string" then return nil end
    local pageKey = source:match("^page:reset:([^:]+)$")
    if pageKey then return HISTORY_PAGE_RESET_FEATURES[pageKey] end
    local editCategory, editKey = source:match("^edit_mode:([^:]+):?([^:]*)")
    if editCategory == "castbar" then return "castbar", editKey end
    if editCategory == "aura" then return "auras", editKey end
    if editCategory == "gf" then return "group", editKey end
    if editCategory == "external" then return "external", editKey end
    local scope = source:match("^groupPreview:([^:]+):") or source:match("^group:([^:]+):")
    if scope then return "group", scope end
    scope = source:match("^auras:([^:]+):")
    if scope then return "auras", scope end
    if source:match("^classPowerPreview:") or source:match("^classpower:") then return "classpower" end
    pageKey = source:match("^([^:]+):")
    if not pageKey then return nil end
    if pageKey:match("^gf_") then return "group" end
    if pageKey:match("^auras3") then return "auras" end
    if pageKey == "opt_bars" then return "bars" end
    if pageKey == "opt_fonts" then return "fonts" end
    if pageKey == "opt_colors" then return "colors" end
    return HISTORY_PAGE_RESET_FEATURES[pageKey]
end
local function ApplyScopedFeatureRuntime(kind, reason, scope)
    kind = tostring(kind or "")
    reason = reason or "MSUF2_HISTORY_FEATURE"
    if kind == "external" then return true end
    if kind == "castbar" then
        if ApplyService.RequestCastbars then return ApplyService.RequestCastbars(reason, "history") ~= false end
        if M.RequestGeneralApply then return M.RequestGeneralApply(reason, { history = false, preview = true, applyAll = false, castbar = true, castbarTextures = true }) ~= false end
        local did = true, _G.MSUF_UpdateCastbarVisuals()
        _G.MSUF_UpdateBossCastbarPreview()
did = true
        return did
    end
    if kind == "classpower" then
        -- A ClassPower-owned setting can also decide whether the module has any
        -- work at all (notably Player Power's shared AUTO/MANA source).
        _G.MSUF_ApplyModules()
        if ApplyService.RequestClassPower then
            ApplyService.RequestClassPower(reason, CLASSPOWER_FULL_RUNTIME)
            return true
        end
        return true, _G.MSUF_ClassPower_Apply(CLASSPOWER_FULL_RUNTIME)
    end
    if kind == "auras" then
        return RequestHistoryAurasRuntime and RequestHistoryAurasRuntime(reason, scope) or false
    end
    if kind == "group" then
        return RequestHistoryGroupRuntime and RequestHistoryGroupRuntime(reason, scope) or false
    end
    if kind == "bars" and ApplyService.RequestBars then
        return ApplyService.RequestBars(reason, scope) ~= false
    end
    if kind == "fonts" and ApplyService.RequestFonts then
        return ApplyService.RequestFonts(reason, scope) ~= false
    end
    if kind == "colors" then
        local did = ApplyService.RequestColors and ApplyService.RequestColors(reason, scope) ~= false or false
        if RequestHistoryAurasRuntime then did = RequestHistoryAurasRuntime(reason, scope, true) or did end
        if ApplyService.RequestClassPower then
            ApplyService.RequestClassPower(reason, COLOR_CLASSPOWER_RUNTIME, { preview = true, applyAll = false, classpower = true })
            did = true
        end
        return did
    end
    if kind == "gameplay" then
        if M.ApplyGameplay then
            local result = M.ApplyGameplay()
            return result ~= false
        end
        if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
            local result = MSUF.MSUF_RequestGameplayApply(reason)
            return result ~= false
        end
        if MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
            local result = MSUF.MSUF_ApplyGameplayVisuals()
            return result ~= false
        end
        return false
    end
    if kind == "modules" then
        return true, _G.MSUF_ApplyModules()
    end
    return false
end
local function ApplyScopedHistoryRestore(reason, source)
    -- Both visible Player Power selectors deliberately use this stable source.
    -- Restore the owner and both previews, not just the page the user edited.
    if source == "classpower:playerPowerSource" then
        return M.ApplyPlayerPowerSource(reason)
    end
    local unit = HistoryUnitFromSource(source)
    local applyReason = reason or "MSUF2_HISTORY_UNIT"
    if unit then
        if unit == "player" and source == "page:reset:uf_player" then
            ApplyScopedFeatureRuntime("classpower", applyReason)
        end
        local opts = {
            history = false,
            preview = true,
            power = true,
            castbar = true,
            auras = true,
            classpowerApplied = unit == "player" and source == "page:reset:uf_player",
        }
        return M.RequestUnitApply(unit, applyReason, opts) ~= false
    end
    local feature, scope = HistoryFeatureFromSource(source)
    if feature then return ApplyScopedFeatureRuntime(feature, applyReason, scope) end
    return false
end

RequestHistoryAurasRuntime = function(reason, scope, visuals)
    if visuals and ApplyService.RequestAuraFonts then
        ApplyService.RequestAuraFonts(scope or "shared", reason or "MSUF2_HISTORY_AURAS")
        return true
    end
    if ApplyService.RequestAuras then
        ApplyService.RequestAuras(scope or "shared", reason or "MSUF2_HISTORY_AURAS")
        return true
    end
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras and type(auras.RequestApply) == "function" then
        auras.RequestApply()
        return true
    end
    return false
end

RequestHistoryGroupRuntime = function(reason, kind)
    kind = kind and tostring(kind) or nil
    if kind == "gf_party" then kind = "party" end
    if kind == "gf_raid" then kind = "raid" end
    if kind == "gf_mythicraid" then kind = "mythicraid" end
    if kind == "gf_priority" then kind = "priority" end
    if kind and kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid" and kind ~= "priority" then kind = nil end
    if kind and ApplyService.RequestGroup then
        ApplyService.RequestGroup(kind, "reset", reason or "MSUF2_HISTORY_GROUP")
        return true
    end
    if ApplyService.RequestGroupReset then
        ApplyService.RequestGroupReset(reason or "MSUF2_HISTORY_GROUP")
        return true
    end
    if ApplyService.RequestGroup then
        ApplyService.RequestGroup("group", "reset", reason or "MSUF2_HISTORY_GROUP")
        return true
    end
    if MSUF and MSUF.GF then
        if type(MSUF.GF.RefreshAll) == "function" then
            MSUF.GF.RefreshAll()
        else
            if type(MSUF.GF.RefreshVisuals) == "function" then MSUF.GF.RefreshVisuals() end
        end
        if type(MSUF.GF.RefreshPreviewLayout) == "function" then MSUF.GF.RefreshPreviewLayout() end
        return true
    end
    return false
end

local function FlushApplyServiceNow()
    if ApplyService.Flush then
        ApplyService.Flush()
        return true
    end
    return false
end

local function ApplyHistorySnapshot(snapshot, reason, source)
    if type(snapshot) ~= "table" then return false end
    local profileDB = HistoryProfileDB(snapshot)
    if type(profileDB) ~= "table" then return false end
    historyRestoring = true
    DeepReplace(M.EnsureDB(), profileDB)
    RestoreProfileRouting(snapshot)
    local externalAPI = (type(MSUF) == "table" and MSUF.EditModeAPI) or _G.MSUF_EditModeAPI
    if type(externalAPI) == "table" and type(externalAPI._RestoreHistorySnapshot) == "function"
        and type(snapshot.externalEditMode) == "table" then
        externalAPI._RestoreHistorySnapshot(snapshot.externalEditMode, reason or "history")
    end
    if historySessionActive then historySessionSnapshot = snapshot end
    historyRestoring = false
    if ApplyScopedHistoryRestore(reason, source) then
        FlushApplyServiceNow()
        M.MarkMenuDataDirty(reason or "history")
        RebuildActivePage()
        if type(_G.MSUF_EM_RefreshAfterHistoryRestore) == "function" then
            _G.MSUF_EM_RefreshAfterHistoryRestore(reason or "MSUF2_HISTORY", source)
        end
        return true
    end
    -- A restored profile snapshot may span UnitFrames, Auras3, ClassPower, GroupFrames, and
    -- Menu2 state, so restore fanout is centralized and explicit.
    M.RequestGeneralApply(reason or "MSUF2_HISTORY", { preview = true, alpha = true, castbar = true })
    if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
        MSUF.MSUF_RequestGameplayApply()
    elseif MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
        MSUF.MSUF_ApplyGameplayVisuals()
    end
    do
        local db = M.EnsureDB()
        local g = db and db.general
        local ui = type(g) == "table" and type(g.UIScale) == "table" and g.UIScale or nil
        if ui and ui.Enabled == true and type(_G.MSUF_SetGlobalUiScale) == "function" then
            _G.MSUF_SetGlobalUiScale(tonumber(ui.Scale) or 1, true)
        elseif ui and type(_G.MSUF_ResetGlobalUiScale) == "function" then
            _G.MSUF_ResetGlobalUiScale(true)
        end
        if M.ApplyMenuFrameScale and M.frame then
            M.ApplyMenuFrameScale(M.frame)
        elseif M.GetEffectiveMenuScale and M.frame and M.frame.SetScale and type(g) == "table" then
            local scale = M.GetEffectiveMenuScale(g.slashMenuScale)
            if type(scale) == "number" then M.frame:SetScale(scale) end
        end
    end
    RequestHistoryAurasRuntime(reason or "MSUF2_HISTORY_AURAS")
    if ApplyService.RequestClassPower then
        ApplyService.RequestClassPower("MSUF2_HISTORY_CLASSPOWER", CLASSPOWER_FULL_RUNTIME, {
            preview = false,
            applyAll = false,
            classpower = true,
        })
    end
    RequestHistoryGroupRuntime(reason or "MSUF2_HISTORY_GROUP")
    FlushApplyServiceNow()
    if type(_G.MSUF_ApplySpecProfileIfEnabled) == "function" then
        _G.MSUF_ApplySpecProfileIfEnabled("MSUF2_HISTORY_PROFILE_ROUTING")
    end
    M.ApplyLocaleSelection(M.GetLocaleSelection and M.GetLocaleSelection() or "auto")
    M.MarkMenuDataDirty(reason or "history")
    RebuildActivePage()
    if type(_G.MSUF_EM_RefreshAfterHistoryRestore) == "function" then
        _G.MSUF_EM_RefreshAfterHistoryRestore(reason or "MSUF2_HISTORY", source)
    end
    return true
end

-- Guided setup can span multiple menu sessions and reloads, while normal Menu2
-- history intentionally cannot. Keep one compact active-profile restore point
-- in guided-tour state and reuse the same proven restore fanout as Undo.
function M.CaptureGuidedTourRestorePoint()
    if IsConfigCombatLocked() then return nil end
    local snapshot = SnapshotDB()
    snapshot._msuf2GuidedProfileName = tostring(_G.MSUF_ActiveProfile or "Default")
    return snapshot
end

function M.RestoreGuidedTourRestorePoint(snapshot)
    if IsConfigCombatLocked() then return false end
    local expectedProfile = type(snapshot) == "table" and tostring(snapshot._msuf2GuidedProfileName or "") or ""
    local activeProfile = tostring(_G.MSUF_ActiveProfile or "Default")
    if expectedProfile == "" or activeProfile ~= expectedProfile then return false, "profile_mismatch" end
    return ApplyHistorySnapshot(snapshot, "MSUF2_GUIDED_TOUR_RESTORE", "guided_tour:restore_point")
end

function M.IsHistoryCapturing()
    return historyDepth > 0 or historyRestoring
end
function M.CaptureHistory(label, source, fn)
    if type(fn) ~= "function" then return nil end
    if M.BlockCombatAction() then return false end
    if historyDepth > 0 or historyRestoring then
        local result = fn()

        if result ~= false then
            if historyTransaction then
                historyTransaction.dirty = true
            elseif M.MarkMenuDataDirty then
                M.MarkMenuDataDirty("history")
            end
        end
        return result
    end
    if historyTransaction and source and historyTransaction.source ~= source then
        M.CommitHistoryTransaction()
        return M.CaptureHistory(label, source, fn)
    end
    local before = CurrentHistorySnapshot()
    historyDepth = historyDepth + 1
    local result = fn()
    historyDepth = historyDepth - 1

    if result == false then return result end
    local pushed = PushHistory(label, source, before, SnapshotDB())
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return result
end
function M.RunWithHistory(label, source, fn)
    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then return M.CaptureHistory(label, source, fn) end
    return type(fn) == "function" and fn() or nil
end
local function CopyStack(stack)
    local copy = {}
    for i = 1, #stack do copy[i] = stack[i] end
    return copy
end
local function RestoreStack(stack, saved)
    WipeTable(stack)
    for i = 1, #(saved or {}) do stack[i] = saved[i] end
end
local function DeferHistoryCommit(label, source, before)
    -- Combat can interrupt a drag/debounced control between its before/after
    -- snapshots. Preserve the earliest before-state without copying the DB or
    -- waking previews in combat; the next config interaction finalizes it.
    if deferredHistoryCommit then return true end
    deferredHistoryCommit = {
        label = label or "MSUF2 change",
        source = source or "external:change",
        before = before,
    }
    return true
end
function M.FlushDeferredHistory(afterSnapshot)
    if IsConfigCombatLocked() or not deferredHistoryCommit then return false end
    local pending = deferredHistoryCommit
    deferredHistoryCommit = nil
    afterSnapshot = type(afterSnapshot) == "table" and afterSnapshot or SnapshotDB()
    local pushed = PushHistory(pending.label, pending.source, pending.before, afterSnapshot)
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed, afterSnapshot
end
function M.DeferPreparedHistory(prepared)
    if historyRestoring or type(prepared) ~= "table" or prepared._msuf2PreparedHistory ~= true then return false end
    return DeferHistoryCommit(prepared.label, prepared.source, prepared.before)
end
function M.StartHistorySession(surface)
    if IsConfigCombatLocked() then return false end
    surface = tostring(surface or "menu")
    if historySurfaces[surface] then
        M.FlushDeferredHistory()
        return true
    end
    local entrySnapshot
    if deferredHistoryCommit or not historySessionActive or type(historySessionSnapshot) ~= "table" then
        entrySnapshot = SnapshotDB()
    else
        entrySnapshot = historySessionSnapshot
    end
    M.FlushDeferredHistory(entrySnapshot)
    local undo, redo = EnsureHistoryStacks()
    historySurfaces[surface] = true
    historySurfaceCount = historySurfaceCount + 1
    historySurfaceMarkers[surface] = {
        undo = CopyStack(undo),
        redo = CopyStack(redo),
        snapshot = entrySnapshot,
    }
    if not historySessionActive then
        historySessionActive = true
        historySessionBaseSnapshot = entrySnapshot
        historySessionSnapshot = historySessionBaseSnapshot
        historySessionDirty = false
    end
    NotifyHistoryChanged()
    return true
end
function M.EndHistorySession(surface)
    local combatLocked = IsConfigCombatLocked()
    surface = tostring(surface or "menu")
    if historyTransaction then
        local txSurface = type(historyTransaction.source) == "string" and historyTransaction.source:match("^edit_mode:")
            and "edit_mode" or "menu"
        if txSurface == surface or historySurfaceCount <= 1 then M.CommitHistoryTransaction() end
    end
    if historySurfaces[surface] then
        historySurfaces[surface] = nil
        historySurfaceMarkers[surface] = nil
        historySurfaceCount = math.max(0, historySurfaceCount - 1)
    end
    if historySurfaceCount == 0 then
        historySessionActive = false
        historySessionBaseSnapshot = nil
        historySessionSnapshot = nil
        historySessionDirty = false
    end
    if combatLocked then
        CancelQueuedMenuRefresh()
    else
        NotifyHistoryChanged()
    end
    return true
end
function M.CancelHistorySurface(surface, restoreState)
    if IsConfigCombatLocked() then return false end
    surface = tostring(surface or "menu")
    local marker = historySurfaceMarkers[surface]
    if not marker then return false end
    if historyTransaction then M.CancelHistoryTransaction() end
    if restoreState == true and type(marker.snapshot) == "table" then
        local profileDB = HistoryProfileDB(marker.snapshot)
        if type(profileDB) ~= "table" then return false end
        historyRestoring = true
        DeepReplace(M.EnsureDB(), profileDB)
        RestoreProfileRouting(marker.snapshot)
        historyRestoring = false
    end
    local undo, redo = EnsureHistoryStacks()
    RestoreStack(undo, marker.undo)
    RestoreStack(redo, marker.redo)
    historySessionSnapshot = restoreState == true and marker.snapshot or SnapshotDB()
    historySessionDirty = historySessionActive and type(historySessionBaseSnapshot) == "table"
        and not DeepEqual(historySessionBaseSnapshot, historySessionSnapshot) or false
    NotifyHistoryChanged(true)
    return true
end
function M.CheckpointHistory(label, source)
    if M.BlockCombatAction() then return false end
    -- Runtime apply helpers checkpoint under their own source while a bound
    -- slider transaction is live. They are nested effects of the same user
    -- gesture, not a new action, and must never close that transaction.
    if historyDepth > 0 or historyRestoring then return false end
    if historyTransaction and source and historyTransaction.source ~= source then M.CommitHistoryTransaction() end
    if not historySessionActive or historyTransaction then return false end
    local before = CurrentHistorySnapshot()
    local after = SnapshotDB()
    local pushed = PushHistory(label or "MSUF2 change", source or "menu:checkpoint", before, after)
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed
end
function M.BeginHistoryTransaction(label, source)
    if M.BlockCombatAction() then return false end
    if historyTransaction and source and historyTransaction.source ~= source then M.CommitHistoryTransaction() end
    if historyDepth > 0 or historyRestoring or not historySessionActive or historyTransaction then return false end
    historyTransaction = {
        label = label or "MSUF2 change",
        source = source or "menu:transaction",
        before = CurrentHistorySnapshot(),
    }
    historyDepth = historyDepth + 1
    return true
end
function M.PrepareHistoryChange(label, source)
    if M.BlockCombatAction() then return nil end
    if historyDepth > 0 or historyRestoring or historyTransaction then return nil end
    return {
        _msuf2PreparedHistory = true,
        label = label or "MSUF change",
        source = source or "external:change",
        before = CurrentHistorySnapshot(),
    }
end
function M.CommitPreparedHistory(prepared)
    if historyRestoring or type(prepared) ~= "table" or prepared._msuf2PreparedHistory ~= true then return false end
    if IsConfigCombatLocked() then
        M.DeferPreparedHistory(prepared)
        return false
    end
    local pushed = PushHistory(prepared.label, prepared.source, prepared.before, SnapshotDB())
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed
end
function M.CommitHistoryTransaction()
    local tx = historyTransaction
    if not tx then return false end
    historyTransaction = nil
    historyDepth = math.max(0, historyDepth - 1)
    if IsConfigCombatLocked() then
        DeferHistoryCommit(tx.label, tx.source, tx.before)
        return false
    end
    local pushed = PushHistory(tx.label, tx.source, tx.before, SnapshotDB())
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed
end
function M.CancelHistoryTransaction()
    if not historyTransaction then return false end
    historyTransaction = nil
    historyDepth = math.max(0, historyDepth - 1)
    return true
end
function M.ResetHistorySession()
    if M.BlockCombatAction() then return false end
    if not historySessionActive or type(historySessionBaseSnapshot) ~= "table" then return false end
    local ok = ApplyHistorySnapshot(historySessionBaseSnapshot, "MSUF2_HISTORY_RESET_SESSION")
    if ok then M.ClearHistory() end
    if ok then CommandFeedback("Session changes reset", "ok", 1.4) end
    return ok
end
function M.ClearHistory()
    if IsConfigCombatLocked() then return false end
    deferredHistoryCommit = nil
    local undo, redo = EnsureHistoryStacks()
    WipeTable(undo)
    WipeTable(redo)
    local clearedSnapshot = next(historySurfaces) and SnapshotDB() or nil
    for surface in pairs(historySurfaces) do
        historySurfaceMarkers[surface] = { undo = {}, redo = {}, snapshot = clearedSnapshot }
    end
    if historySessionActive then
        historySessionBaseSnapshot = clearedSnapshot or SnapshotDB()
        historySessionSnapshot = historySessionBaseSnapshot
        historySessionDirty = false
    end
    NotifyHistoryChanged()
    return true
end
function M.GetHistoryState()
    local undoStack, redoStack = EnsureHistoryStacks()
    local undo = undoStack[#undoStack]
    local redo = redoStack[#redoStack]
    return {
        canUndo = undo ~= nil,
        canRedo = redo ~= nil,
        canResetAll = historySessionActive and type(historySessionBaseSnapshot) == "table" and historySessionDirty,
        undoLabel = undo and M.HistoryDisplayLabel(undo.label) or nil,
        redoLabel = redo and M.HistoryDisplayLabel(redo.label) or nil,
        undoCount = #undoStack,
        redoCount = #redoStack,
        activeSurfaces = historySurfaceCount,
    }
end
function M.Undo()
    if M.BlockCombatAction() then return false end
    M.FlushDeferredHistory()
    local undo, redo = EnsureHistoryStacks()
    local entry = table.remove(undo)
    if not entry then return false end
    local ok = ApplyHistorySnapshot(entry.before, "MSUF2_HISTORY_UNDO", entry.source)
    if ok then
        redo[#redo + 1] = entry
        if historySessionActive and type(historySessionBaseSnapshot) == "table" then
            historySessionDirty = not DeepEqual(historySessionBaseSnapshot, entry.before)
        end
    else
        undo[#undo + 1] = entry
    end
    NotifyHistoryChanged()
    if ok then CommandFeedback("Undid " .. FeedbackLabel(M.HistoryDisplayLabel(entry.label)), "info", 1.25) end
    return ok
end
function M.Redo()
    if M.BlockCombatAction() then return false end
    M.FlushDeferredHistory()
    local undo, redo = EnsureHistoryStacks()
    local entry = table.remove(redo)
    if not entry then return false end
    local ok = ApplyHistorySnapshot(entry.after, "MSUF2_HISTORY_REDO", entry.source)
    if ok then
        undo[#undo + 1] = entry
        if historySessionActive and type(historySessionBaseSnapshot) == "table" then
            historySessionDirty = not DeepEqual(historySessionBaseSnapshot, entry.after)
        end
    else
        redo[#redo + 1] = entry
    end
    NotifyHistoryChanged()
    if ok then CommandFeedback("Redid " .. FeedbackLabel(M.HistoryDisplayLabel(entry.label)), "info", 1.25) end
    return ok
end
function M.RequestUnitApply(unit, reason, opts)
    if M.BlockCombatAction() then return false end
    if ApplyService.NormalizeUnit then
        unit = ApplyService.NormalizeUnit(unit)
    else
        unit = (unit == "tot") and "targettarget" or unit
        unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    end
    if not UNIT_KEYS[unit] then return end
    if not (opts and opts.history == false) then
        M.CheckpointHistory(reason or ("MSUF2_" .. tostring(unit)), "apply:unit:" .. tostring(unit) .. ":" .. tostring(reason or "change"))
    end
    local result = false
    if ApplyService.RequestUnit then result = ApplyService.RequestUnit(unit, reason, opts) end
    return result
end
function M.SetUnitValue(unit, key, value, reason, opts)
    if M.BlockCombatAction() then return false end
    if historyDepth == 0 and not historyRestoring then
        return M.CaptureHistory(tostring(key), "unit:" .. tostring(unit) .. ":" .. tostring(key), function()
            return M.SetUnitValue(unit, key, value, reason, opts)
        end)
    end
    local conf = M.GetUnitDB(unit)
    local sameValue = conf[key] == value
    if not sameValue then conf[key] = value end
    local directTextChanged = M.SyncDirectTextOffsets(conf, key)
    if sameValue and not directTextChanged then return false end
    M.RequestUnitApply(unit, reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end
function M.RequestGeneralApply(reason, opts)
    if M.BlockCombatAction() then return false end
    if not (opts and opts.history == false) then
        M.CheckpointHistory(reason or "MSUF2_GENERAL", "apply:general:" .. tostring(reason or "change"))
    end
    local result = false
    if ApplyService.RequestGeneral then result = ApplyService.RequestGeneral(reason, opts) end
    return result
end
function M.SetGeneralValue(key, value, reason, opts)
    if M.BlockCombatAction() then return false end
    if historyDepth == 0 and not historyRestoring then
        return M.CaptureHistory(tostring(key), "general:" .. tostring(key), function()
            return M.SetGeneralValue(key, value, reason, opts)
        end)
    end
    local g = M.GetGeneralDB()
    if g[key] == value then return false end
    g[key] = value
    if key == "menuLocale" then
        if M.ApplyLocaleSelection then M.ApplyLocaleSelection(value) end
        if opts and opts.noRuntime == true then return true end
    end
    M.RequestGeneralApply(reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end

-- The Reset sibling (MSUF_Menu2_Bindings_Reset.lua) loads next and reuses the
-- scoped runtime fanout, the ApplyService flush and the ClassPower colour mask
-- instead of re-declaring them.
M.ApplyScopedFeatureRuntime = ApplyScopedFeatureRuntime
M.FlushApplyServiceNow = FlushApplyServiceNow
M.COLOR_CLASSPOWER_RUNTIME = COLOR_CLASSPOWER_RUNTIME

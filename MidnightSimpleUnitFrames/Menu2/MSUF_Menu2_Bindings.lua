local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local pendingUnits = {}
local pendingGeneral
local pendingOpts = {}
local pendingPreview
local pendingAlpha
local pendingCastbar
local flushQueued = false

local HISTORY_LIMIT = 500
local historyDepth = 0
local historyRestoring = false
local historySessionActive = false
local historySessionBaseSnapshot
local historySessionSnapshot
local historySessionDirty = false
local historyTransaction
local refreshQueued = false

local UNIT_KEYS = {
    player = true,
    target = true,
    targettarget = true,
    focus = true,
    pet = true,
    boss = true,
}

local function WipeTable(t)
    for k in pairs(t) do t[k] = nil end
end

function M.EnsureDB()
    if type(_G.EnsureDB) == "function" then
        pcall(_G.EnsureDB)
    end
    _G.MSUF_DB = _G.MSUF_DB or {}
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    return _G.MSUF_DB
end

function M.GetUnitDB(unit)
    local db = M.EnsureDB()
    unit = (unit == "tot") and "targettarget" or unit
    if not UNIT_KEYS[unit] then unit = "player" end
    db[unit] = db[unit] or {}
    return db[unit], db
end

function M.GetGeneralDB()
    local db = M.EnsureDB()
    db.general = db.general or {}
    return db.general, db
end

function M.ShowPreserveHPColorWarning()
    local g = M.GetGeneralDB()
    if g.hidePreserveHPColorWarning == true then return false end

    local message = "Preserve HP color can replace the selected health bar texture with an internal preserve texture.\n\nSome colored or pre-gradient bar textures may look flat, dark, or different while this option is enabled."
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then
        if print then
            print("|cffffd700MSUF:|r Preserve HP color may not work correctly with some bar textures.")
        end
        return false
    end

    if not _G.StaticPopupDialogs.MSUF2_PRESERVE_HP_COLOR_WARNING then
        _G.StaticPopupDialogs.MSUF2_PRESERVE_HP_COLOR_WARNING = {
            text = "%s",
            button1 = _G.OKAY or "OK",
            button2 = "Don't show again",
            timeout = 0,
            whileDead = true,
            hideOnEscape = false,
            preferredIndex = 3,
            OnCancel = function()
                local gen = M.GetGeneralDB()
                gen.hidePreserveHPColorWarning = true
            end,
        }
    end

    _G.StaticPopup_Show("MSUF2_PRESERVE_HP_COLOR_WARNING", message)
    return true
end

function M.WarnPreserveHPColorIfNeeded(enabled)
    if enabled == true then
        return M.ShowPreserveHPColorWarning()
    end
    return false
end

local function CallGlobal(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then
        return pcall(fn, ...)
    end
    return false
end

local function IsConfigCombatLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then
        return _G.MSUF_IsConfigCombatLocked() and true or false
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return true end
    return (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false
end

function M.IsConfigCombatLocked()
    return IsConfigCombatLocked()
end

function M.ShowConfigCombatLockMessage()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    elseif print then
        print("|cffffd700MSUF:|r Menu and Edit Mode are locked in combat. Leave combat to configure MSUF.")
    end
end

function M.BlockCombatAction()
    if not IsConfigCombatLocked() then return false end
    M.ShowConfigCombatLockMessage()
    return true
end

local function BlockCombatAndRefresh(ctx)
    if not M.BlockCombatAction() then return false end
    if M.Refresh then M.Refresh(ctx) end
    return true
end

local function FlushApply()
    flushQueued = false

    local wantPreview = pendingPreview
    pendingPreview = nil

    local wantAlpha = pendingAlpha
    pendingAlpha = nil

    for unit in pairs(pendingUnits) do
        local opt = pendingOpts[unit] or {}
        local notifyUnit = (unit == "boss") and nil or unit
        if opt.notify ~= false then
            CallGlobal("MSUF_UFCore_NotifyConfigChanged", notifyUnit, true, true, opt.reason or "MSUF2")
        end
        if opt.text then
            CallGlobal("MSUF_ForceTextLayoutForUnitKey", unit)
        end
        if opt.power then
            if not (_G.InCombatLockdown and _G.InCombatLockdown()) then
                if not CallGlobal("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", unit, true) then
                    CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
                end
            end
            if unit == "player" then
                CallGlobal("MSUF_ClassPower_Refresh")
            end
        end
        if not CallGlobal("ApplySettingsForKey", unit) then
            CallGlobal("MSUF_ApplySettingsForKey_Immediate", unit)
        end
    end

    WipeTable(pendingUnits)
    WipeTable(pendingOpts)

    if pendingGeneral then
        local opt = pendingGeneral
        pendingGeneral = nil
        if opt.notify ~= false then
            CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, opt.reason or "MSUF2_GENERAL")
        end
        if opt.applyAll ~= false then
            if not CallGlobal("ApplyAllSettings") then
                CallGlobal("MSUF_ApplyAllSettings_Immediate")
            end
        end
    end
    if pendingCastbar then
        pendingCastbar = nil
        CallGlobal("MSUF_UpdateCastbarVisuals")
    end
    if wantAlpha then
        CallGlobal("MSUF_RefreshAllUnitAlphas")
    end
    if wantPreview then
        CallGlobal("MSUF_UFPreview_RequestRefresh", wantPreview)
    end
end

local function QueueFlush()
    if flushQueued then return end
    flushQueued = true
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("MSUF2_APPLY", FlushApply)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, FlushApply)
    else
        FlushApply()
    end
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return out
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

local function DeepReplace(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k in pairs(dst) do
        if src[k] == nil then dst[k] = nil end
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepReplace(dst[k], v)
        else
            dst[k] = v
        end
    end
end

local function SnapshotDB()
    return DeepCopy(M.EnsureDB())
end

local function CurrentHistorySnapshot()
    if historySessionActive and type(historySessionSnapshot) == "table" then
        return historySessionSnapshot
    end
    return SnapshotDB()
end

local function QueueMenuRefresh()
    if refreshQueued then return end
    refreshQueued = true
    local function Run()
        refreshQueued = false
        if M.frame and M.frame.IsShown and M.frame:IsShown() and M.Refresh then
            M.Refresh()
        end
    end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, Run)
    else
        Run()
    end
end

local function NotifyHistoryChanged()
    if M.RefreshHistoryControls then pcall(M.RefreshHistoryControls) end
    if M.frame and M.frame.RefreshStatus then pcall(M.frame.RefreshStatus, M.frame) end
    QueueMenuRefresh()
end

local function PushHistory(label, source, before, after)
    if DeepEqual(before, after) then return false end

    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}

    local stack = M.historyUndo
    stack[#stack + 1] = {
        label = label or "MSUF2 change",
        source = source,
        before = before,
        after = after,
    }
    while #stack > HISTORY_LIMIT do
        table.remove(stack, 1)
    end

    WipeTable(M.historyRedo)
    if historySessionActive then
        historySessionSnapshot = after
        historySessionDirty = true
    end
    NotifyHistoryChanged()
    return true
end

local function RebuildActivePage()
    local key = M.activeKey
    if key and M.frame and M.frame.IsShown and M.frame:IsShown() and M.InvalidatePage and M.SelectPage then
        M.InvalidatePage(key)
        M.activeKey = nil
        M.SelectPage(key)
    else
        NotifyHistoryChanged()
    end
end

local function ApplyHistorySnapshot(snapshot, reason)
    if type(snapshot) ~= "table" then return false end
    historyRestoring = true
    DeepReplace(M.EnsureDB(), snapshot)
    if historySessionActive then historySessionSnapshot = snapshot end
    historyRestoring = false

    M.RequestGeneralApply(reason or "MSUF2_HISTORY", { preview = true, alpha = true, castbar = true })
    if ns and type(ns.MSUF_RequestGameplayApply) == "function" then
        pcall(ns.MSUF_RequestGameplayApply)
    elseif ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then
        pcall(ns.MSUF_ApplyGameplayVisuals)
    end
    do
        local db = M.EnsureDB()
        local g = db and db.general
        local ui = type(g) == "table" and type(g.UIScale) == "table" and g.UIScale or nil
        if ui and ui.Enabled == true and type(_G.MSUF_SetGlobalUiScale) == "function" then
            pcall(_G.MSUF_SetGlobalUiScale, tonumber(ui.Scale) or 1, true)
        elseif ui and type(_G.MSUF_ResetGlobalUiScale) == "function" then
            pcall(_G.MSUF_ResetGlobalUiScale, true)
        end
        if M.ApplyMenuFrameScale and M.frame then
            pcall(M.ApplyMenuFrameScale, M.frame)
        elseif M.GetEffectiveMenuScale and M.frame and M.frame.SetScale and type(g) == "table" then
            pcall(M.frame.SetScale, M.frame, M.GetEffectiveMenuScale(g.slashMenuScale))
        end
    end
    local auras = ns and ns.MSUF_Auras2
    if auras and type(auras.RequestApply) == "function" then
        pcall(auras.RequestApply)
    elseif type(_G.MSUF_Auras2_RefreshAll) == "function" then
        pcall(_G.MSUF_Auras2_RefreshAll)
    end
    CallGlobal("MSUF_A2_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_A2_ForceCooldownTextRecolor")
    CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
    CallGlobal("MSUF_RefreshAllIdentityColors")
    CallGlobal("MSUF_RefreshAllPowerTextColors")
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    CallGlobal("MSUF_UpdateAllBarTextures")
    CallGlobal("MSUF_UpdateCastbarVisuals_Immediate")
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
    CallGlobal("MSUF_PortraitDecoration_RefreshAll")
    if ns and ns.GF then
        if type(ns.GF.RebuildAll) == "function" then pcall(ns.GF.RebuildAll) end
        if type(ns.GF.RefreshPreviewLayout) == "function" then pcall(ns.GF.RefreshPreviewLayout) end
        if type(ns.GF.RefreshVisuals) == "function" then pcall(ns.GF.RefreshVisuals) end
    end
    if M.ApplyLocaleSelection then M.ApplyLocaleSelection() end
    RebuildActivePage()
    return true
end

function M.IsHistoryCapturing()
    return historyDepth > 0 or historyRestoring
end

function M.CaptureHistory(label, source, fn)
    if type(fn) ~= "function" then return nil end
    if M.BlockCombatAction() then return false end
    if historyDepth > 0 or historyRestoring then return fn() end

    local before = CurrentHistorySnapshot()
    historyDepth = historyDepth + 1
    local ok, result = pcall(fn)
    historyDepth = historyDepth - 1
    if not ok then
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" then handler(result) else print(result) end
        return nil
    end
    if result == false then return result end
    PushHistory(label, source, before, SnapshotDB())
    return result
end

function M.StartHistorySession()
    if IsConfigCombatLocked() then return false end
    if historyTransaction then
        historyTransaction = nil
        historyDepth = math.max(0, historyDepth - 1)
    end
    historySessionActive = true
    historySessionBaseSnapshot = SnapshotDB()
    historySessionSnapshot = historySessionBaseSnapshot
    historySessionDirty = false
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    WipeTable(M.historyUndo)
    WipeTable(M.historyRedo)
    NotifyHistoryChanged()
end

function M.EndHistorySession()
    historySessionActive = false
    if historyTransaction then
        historyTransaction = nil
        historyDepth = math.max(0, historyDepth - 1)
    end
    historySessionBaseSnapshot = nil
    historySessionSnapshot = nil
    historySessionDirty = false
end

function M.CheckpointHistory(label, source)
    if M.BlockCombatAction() then return false end
    if historyDepth > 0 or historyRestoring or not historySessionActive or historyTransaction then return false end
    local before = CurrentHistorySnapshot()
    local after = SnapshotDB()
    return PushHistory(label or "MSUF2 change", source or "menu:checkpoint", before, after)
end

function M.BeginHistoryTransaction(label, source)
    if M.BlockCombatAction() then return false end
    if historyDepth > 0 or historyRestoring or not historySessionActive or historyTransaction then return false end
    historyTransaction = {
        label = label or "MSUF2 change",
        source = source or "menu:transaction",
        before = CurrentHistorySnapshot(),
    }
    historyDepth = historyDepth + 1
    return true
end

function M.CommitHistoryTransaction()
    local tx = historyTransaction
    if not tx then return false end
    historyTransaction = nil
    historyDepth = math.max(0, historyDepth - 1)
    return PushHistory(tx.label, tx.source, tx.before, SnapshotDB())
end

function M.CancelHistoryTransaction()
    if not historyTransaction then return false end
    historyTransaction = nil
    historyDepth = math.max(0, historyDepth - 1)
    NotifyHistoryChanged()
    return true
end

function M.ResetHistorySession()
    if M.BlockCombatAction() then return false end
    if not historySessionActive or type(historySessionBaseSnapshot) ~= "table" then return false end
    local ok = ApplyHistorySnapshot(historySessionBaseSnapshot, "MSUF2_HISTORY_RESET_SESSION")
    if ok then M.ClearHistory() end
    return ok
end

function M.ClearHistory()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    WipeTable(M.historyUndo)
    WipeTable(M.historyRedo)
    if historySessionActive then
        historySessionBaseSnapshot = SnapshotDB()
        historySessionSnapshot = historySessionBaseSnapshot
        historySessionDirty = false
    end
    NotifyHistoryChanged()
end

function M.GetHistoryState()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    local undo = M.historyUndo[#M.historyUndo]
    local redo = M.historyRedo[#M.historyRedo]
    return {
        canUndo = undo ~= nil,
        canRedo = redo ~= nil,
        canResetAll = historySessionActive and type(historySessionBaseSnapshot) == "table" and historySessionDirty,
        undoLabel = undo and undo.label or nil,
        redoLabel = redo and redo.label or nil,
        undoCount = #M.historyUndo,
        redoCount = #M.historyRedo,
    }
end

function M.Undo()
    if M.BlockCombatAction() then return false end
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    local entry = table.remove(M.historyUndo)
    if not entry then return false end
    M.historyRedo[#M.historyRedo + 1] = entry
    local ok = ApplyHistorySnapshot(entry.before, "MSUF2_HISTORY_UNDO")
    if ok and historySessionActive then historySessionDirty = #M.historyUndo > 0 end
    NotifyHistoryChanged()
    return ok
end

function M.Redo()
    if M.BlockCombatAction() then return false end
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    local entry = table.remove(M.historyRedo)
    if not entry then return false end
    M.historyUndo[#M.historyUndo + 1] = entry
    local ok = ApplyHistorySnapshot(entry.after, "MSUF2_HISTORY_REDO")
    if ok and historySessionActive then historySessionDirty = true end
    NotifyHistoryChanged()
    return ok
end

local function WidgetHistoryLabel(ctx, widget, fallback)
    local fs = widget and (widget._msuf2Title or widget._msuf2Label)
    if fs and fs.GetText then
        local text = fs:GetText()
        if text and text ~= "" then return text end
    end
    if widget and widget.GetText then
        local ok, text = pcall(widget.GetText, widget)
        if ok and text and text ~= "" then return text end
    end
    return fallback or tostring((ctx and ctx.key) or "MSUF2 option")
end

local function WidgetHistorySource(ctx, widget, suffix)
    local key = (ctx and ctx.key) or "page"
    local kind = widget and (widget._msuf2ControlKind or widget.GetObjectType and widget:GetObjectType()) or "control"
    return tostring(key) .. ":" .. tostring(kind) .. ":" .. tostring(suffix or WidgetHistoryLabel(ctx, widget))
end

function M.RequestUnitApply(unit, reason, opts)
    if M.BlockCombatAction() then return false end
    unit = (unit == "tot") and "targettarget" or unit
    if not UNIT_KEYS[unit] then return end
    M.CheckpointHistory(reason or ("MSUF2_" .. tostring(unit)), "apply:unit:" .. tostring(unit) .. ":" .. tostring(reason or "change"))
    pendingUnits[unit] = true
    local o = pendingOpts[unit]
    if not o then
        o = {}
        pendingOpts[unit] = o
    end
    o.reason = reason or o.reason or "MSUF2"
    if opts then
        if opts.text then o.text = true end
        if opts.power then o.power = true end
        if opts.castbar then pendingCastbar = true end
        if opts.notify == false then o.notify = false end
        if opts.preview ~= false then pendingPreview = opts.previewReason or reason or "MSUF2" end
        if opts.alpha then pendingAlpha = true end
    else
        pendingPreview = reason or "MSUF2"
    end
    QueueFlush()
end

function M.SetUnitValue(unit, key, value, reason, opts)
    if M.BlockCombatAction() then return false end
    if historyDepth == 0 and not historyRestoring then
        return M.CaptureHistory(tostring(key), "unit:" .. tostring(unit) .. ":" .. tostring(key), function()
            return M.SetUnitValue(unit, key, value, reason, opts)
        end)
    end
    local conf = M.GetUnitDB(unit)
    if conf[key] == value then return false end
    conf[key] = value
    M.RequestUnitApply(unit, reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end

function M.RequestGeneralApply(reason, opts)
    if M.BlockCombatAction() then return false end
    M.CheckpointHistory(reason or "MSUF2_GENERAL", "apply:general:" .. tostring(reason or "change"))
    if not pendingGeneral then pendingGeneral = {} end
    pendingGeneral.reason = reason or pendingGeneral.reason or "MSUF2_GENERAL"
    if opts and opts.applyAll == false then
        if pendingGeneral.applyAll == nil then pendingGeneral.applyAll = false end
    else
        pendingGeneral.applyAll = true
    end
    if opts and opts.notify == false then pendingGeneral.notify = false end
    if opts then
        if opts.castbar then pendingCastbar = true end
        if opts.preview ~= false then pendingPreview = opts.previewReason or reason or "MSUF2_GENERAL" end
        if opts.alpha then pendingAlpha = true end
    else
        pendingPreview = reason or "MSUF2_GENERAL"
    end
    QueueFlush()
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
    if key == "menuLocale" and M.ApplyLocaleSelection then M.ApplyLocaleSelection(value) end
    M.RequestGeneralApply(reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end

local UNIT_PAGE_RESETS = {
    uf_player = { unit = "player", label = "Player" },
    uf_target = { unit = "target", label = "Target" },
    uf_targettarget = { unit = "targettarget", label = "Target of Target" },
    uf_focus = { unit = "focus", label = "Focus" },
    uf_boss = { unit = "boss", label = "Boss Frames" },
    uf_pet = { unit = "pet", label = "Pet" },
}

local UNIT_CASTBAR_GENERAL_KEYS = {
    player = { "enablePlayerCastbar", "showPlayerCastTime", "castbarPlayerShowIcon", "castbarPlayerShowSpellName" },
    target = { "enableTargetCastbar", "showTargetCastTime", "castbarTargetShowIcon", "castbarTargetShowSpellName" },
    focus = { "enableFocusCastbar", "showFocusCastTime", "castbarFocusShowIcon", "castbarFocusShowSpellName" },
}

local PAGE_RESET_INFO = {
    gf_layout = {
        label = "Group Frames",
        kind = "group",
        summary = "Party, Raid, and Mythic Raid Group Frame layout, bars, auras, indicators, scope overrides and positions",
    },
    gf_bars = {
        label = "Group Frames",
        kind = "group",
        summary = "Party, Raid, and Mythic Raid Group Frame layout, bars, auras, indicators, scope overrides and positions",
    },
    gf_auras = {
        label = "Group Frames",
        kind = "group",
        summary = "Party, Raid, and Mythic Raid Group Frame layout, bars, auras, indicators, scope overrides and positions",
    },
    gf_indicators = {
        label = "Group Frames",
        kind = "group",
        summary = "Party, Raid, and Mythic Raid Group Frame layout, bars, auras, indicators, scope overrides and positions",
    },
    opt_bars = {
        label = "Bars",
        kind = "bars",
        summary = "shared bar textures, gradients, absorb display, outlines, highlight borders, power smoothing and all per-unit/group bar overrides",
    },
    opt_fonts = {
        label = "Fonts",
        kind = "fonts",
        summary = "shared font family, text style, name/power text coloring, name shortening and all per-unit/group font overrides",
    },
    auras2 = {
        label = "Unit Auras",
        kind = "auras",
        summary = "Auras 2.0 shared settings, per-unit aura overrides, filters, caps, layout, timer text and reminders",
    },
    opt_castbar = {
        label = "Castbar",
        kind = "castbar",
        summary = "global castbar behavior, textures, GCD, boss castbar and interrupt indicator settings",
    },
    opt_colors = {
        label = "Colors",
        kind = "colors",
        summary = "frame colors, class/NPC colors, power colors, castbar colors, aura colors and gameplay color settings",
    },
    opt_misc = {
        label = "Miscellaneous",
        kind = "misc",
        summary = "language/menu behavior, update pacing, tooltips, Blizzard-frame handling, minimap icon, sounds and range-fade settings",
    },
    classpower = {
        label = "Class Resources",
        kind = "classpower",
        summary = "class-resource layout, behavior, style, auto-hide, detached power bar and alternative mana settings",
    },
    gameplay = {
        label = "Gameplay",
        kind = "gameplay",
        summary = "gameplay enhancement settings such as combat text, crosshair and click-cast behavior",
    },
    modules = {
        label = "Modules",
        kind = "modules",
        summary = "optional style/module settings such as MSUF Style, dropdown style and rounded unitframes",
    },
    profiles = {
        label = "Profiles",
        kind = "profile",
        summary = "the entire active profile",
    },
}

for pageKey, info in pairs(UNIT_PAGE_RESETS) do
    PAGE_RESET_INFO[pageKey] = {
        label = info.label,
        kind = "unit",
        unit = info.unit,
        summary = info.label .. " unit-frame settings, including layout, text, portrait, power, status icons, transparency, load conditions and this unit's castbar toggles",
    }
end

local BARS_GENERAL_KEYS = {
    barTexture = true,
    barBackgroundTexture = true,
    enableGradient = true,
    enablePowerGradient = true,
    gradientStrength = true,
    gradientDirection = true,
    gradientDirRight = true,
    gradientDirLeft = true,
    gradientDirUp = true,
    gradientDirDown = true,
    showSelfHealPrediction = true,
    absorbBarTexture = true,
    healAbsorbBarTexture = true,
    bossTargetOutlineMode = true,
    bossTargetHighlightEnabled = true,
    highlightPrioEnabled = true,
    highlightPrioOrder = true,
}

local BARS_SCOPE_KEYS = {
    hlOverride = true,
    hpPowerTextOverride = true,
    absorbTextMode = true,
    absorbAnchorMode = true,
    absorbBarOpacity = true,
    healAbsorbBarOpacity = true,
    barOutlineThickness = true,
    highlightBorderThickness = true,
    hlAggroSize = true,
    aggroOutlineMode = true,
    dispelOutlineMode = true,
    purgeOutlineMode = true,
    hlDispelGlowEnabled = true,
    hlDispelGlowStyle = true,
    hlDispelGlowLines = true,
    hlDispelGlowFrequency = true,
    hlDispelGlowThickness = true,
    hlPrioEnabled = true,
    hlPrioOrder = true,
    enableGradient = true,
    enablePowerGradient = true,
    gradientStrength = true,
    gradientDirection = true,
    gradientDirRight = true,
    gradientDirLeft = true,
    gradientDirUp = true,
    gradientDirDown = true,
    powerSmoothFill = true,
}

local BARS_TABLE_KEYS = {
    barOutlineThickness = true,
    smoothPowerBar = true,
    realtimePowerText = true,
}

local FONT_GENERAL_KEYS = {
    fontKey = true,
    boldText = true,
    noOutline = true,
    textBackdrop = true,
    nameClassColor = true,
    npcNameRed = true,
    colorPowerTextByType = true,
}

local FONT_SCOPE_KEYS = {
    fontOverride = true,
    fontKey = true,
    boldText = true,
    noOutline = true,
    textBackdrop = true,
    nameClassColor = true,
    npcNameRed = true,
    colorPowerTextByType = true,
    fontOutline = true,
    useGlobalFontColor = true,
    fontR = true,
    fontG = true,
    fontB = true,
    nameColorMode = true,
    nameShortenEnabled = true,
    nameClipSide = true,
    nameMaxChars = true,
    nameNoEllipsis = true,
    shortenNames = true,
    shortenNameClipSide = true,
    shortenNameMaxChars = true,
    shortenNameShowDots = true,
}

local FONT_ROOT_KEYS = {
    shortenNames = true,
    shortenNameClipSide = true,
    shortenNameMaxChars = true,
    shortenNameShowDots = true,
}

local MISC_GENERAL_KEYS = {
    menuLocale = true,
    slashMenuSnapEnabled = true,
    hideAdvancedMenu = true,
    miscUpdatesPreset = true,
    frameUpdateInterval = true,
    castbarUpdateInterval = true,
    ufcoreFlushBudgetMs = true,
    ufcoreUrgentMaxPerFlush = true,
    showWelcomeMessage = true,
    versionCheckEnabled = true,
    disableUnitInfoTooltips = true,
    unitInfoTooltipStyle = true,
    unitTooltipProvider = true,
    unitTooltipAnchor = true,
    disableBlizzardUnitFrames = true,
    hardKillBlizzardPlayerFrame = true,
    showMinimapIcon = true,
    playTargetSelectLostSounds = true,
    rangeFadePortrait = true,
}

local MISC_UNIT_KEYS = {
    rangeFadeEnabled = true,
    rangeFadeCastbar = true,
    rangeFadeAuras = true,
    rangeFadeLayerMode = true,
    rangeFadeAlpha = true,
}

local CASTBAR_GENERAL_KEYS = {
    showGCDBar = true,
    showGCDBarTime = true,
    showGCDBarSpell = true,
    empowerColorStages = true,
    enableFocusKickIcon = true,
    focusKickIconWidth = true,
    focusKickIconHeight = true,
    focusKickTextSize = true,
    focusKickIconOffsetX = true,
    focusKickIconOffsetY = true,
    kickReadyShowTarget = true,
    kickReadyShowFocus = true,
    kickReadyShowBoss = true,
    kickReadyStyle = true,
    kickReadySize = true,
    kickReadyAutoSize = true,
    kickReadyAnchor = true,
    kickReadyOffsetX = true,
    kickReadyOffsetY = true,
}

local CASTBAR_EXCLUDED_KEYS = {
    castbarUpdateInterval = true,
}

local MODULES_GENERAL_KEYS = {
    styleEnabled = true,
    dropdownStyleMode = true,
    roundedUnitframes = true,
}

local COLOR_GENERAL_KEYS = {
    highlightEnabled = true,
    playerCastbarOverrideEnabled = true,
    playerCastbarOverrideMode = true,
    npcTypeTarget = true,
    npcTypeFocus = true,
    npcTypeBoss = true,
    npcTypeToT = true,
}

local COLOR_GAMEPLAY_KEYS = {
    combatStateColorSync = true,
}

local COLOR_BARS_KEYS = {
    classPowerComboPointColorMode = true,
}

local AURAS_GENERAL_PREFIXES = {
    "auras",
}

local AURAS_SHARED_COLOR_KEYS = {
    pandemicR = true,
    pandemicG = true,
    pandemicB = true,
}

local function StartsWith(value, prefix)
    return type(value) == "string" and type(prefix) == "string" and value:sub(1, #prefix) == prefix
end

local function AnyPrefix(key, prefixes)
    if type(key) ~= "string" then return false end
    for i = 1, #(prefixes or {}) do
        if StartsWith(key, prefixes[i]) then return true end
    end
    return false
end

local function ResetTableToDefaults(dst, src)
    if type(dst) ~= "table" then return end
    for key in pairs(dst) do
        dst[key] = nil
    end
    if type(src) ~= "table" then return end
    for key, value in pairs(src) do
        dst[key] = DeepCopy(value)
    end
end

local function ReplaceRootTable(db, defaults, key)
    if type(db) ~= "table" then return end
    db[key] = db[key] or {}
    ResetTableToDefaults(db[key], type(defaults) == "table" and defaults[key] or nil)
end

local function ResetKeySet(dst, src, keys)
    if type(dst) ~= "table" or type(keys) ~= "table" then return end
    for key in pairs(keys) do
        if type(src) == "table" and src[key] ~= nil then
            dst[key] = DeepCopy(src[key])
        else
            dst[key] = nil
        end
    end
end

local function ResetFilteredKeys(dst, src, filter)
    if type(dst) ~= "table" or type(filter) ~= "function" then return end
    for key in pairs(dst) do
        if filter(key) then
            dst[key] = nil
        end
    end
    if type(src) ~= "table" then return end
    for key, value in pairs(src) do
        if filter(key) then
            dst[key] = DeepCopy(value)
        end
    end
end

local function ResetRootFiltered(db, defaults, rootKey, filter)
    if type(db) ~= "table" then return end
    db[rootKey] = db[rootKey] or {}
    ResetFilteredKeys(db[rootKey], type(defaults) == "table" and defaults[rootKey] or nil, filter)
end

local function ResetUnitFiltered(db, defaults, unit, filter)
    if type(db) ~= "table" or type(unit) ~= "string" then return end
    db[unit] = db[unit] or {}
    ResetFilteredKeys(db[unit], type(defaults) == "table" and defaults[unit] or nil, filter)
end

local function EnsureTargetTargetAlias(db)
    if type(db) == "table" and type(db.targettarget) == "table" then
        db.tot = db.targettarget
    end
end

local function IsColorKey(key)
    if type(key) ~= "string" then return false end
    if COLOR_GENERAL_KEYS[key] == true then return true end
    local lower = string.lower(key)
    if lower:find("color", 1, true) then return true end
    if lower == "barmode" or lower == "darkmode" or lower == "darkbartone" or lower == "darkbgbrightness" then return true end
    if lower == "useclasscolors" or lower == "enablehealthgradient" or lower == "gradientstrength" then return true end
    if lower == "fontcolor" or lower == "highlightcolor" or lower == "usecustomfontcolor" then return true end
    if lower == "nameclasscolor" or lower == "npcnamered" then return true end
    local last = lower:sub(-1)
    if last == "r" or last == "g" or last == "b" or last == "a" then
        if lower:find("color", 1, true)
            or lower:find("font", 1, true)
            or lower:find("bg", 1, true)
            or lower:find("border", 1, true)
            or lower:find("outline", 1, true)
            or lower:find("gradient", 1, true)
            or lower:find("castbar", 1, true)
        then
            return true
        end
        if lower == "fontcolorcustomr" or lower == "fontcolorcustomg" or lower == "fontcolorcustomb" then return true end
    end
    return false
end

local function IsCastbarKey(key)
    if type(key) ~= "string" then return false end
    if CASTBAR_EXCLUDED_KEYS[key] == true then return false end
    if CASTBAR_GENERAL_KEYS[key] == true then return true end
    local lower = string.lower(key)
    if lower:find("castbar", 1, true) then return true end
    if lower:find("bosscast", 1, true) then return true end
    if lower:find("empower", 1, true) then return true end
    if lower == "enableplayercastbar" or lower == "enabletargetcastbar" or lower == "enablefocuscastbar" then return true end
    if lower == "castbarupdateinterval" then return true end
    if lower:find("spellnamefontsize", 1, true) or lower:find("timefontsize", 1, true) then return true end
    return false
end

local function IsClassPowerBarsKey(key)
    if type(key) ~= "string" then return false end
    return StartsWith(key, "classPower")
        or StartsWith(key, "detachedPowerBar")
        or StartsWith(key, "altMana")
        or key == "showClassPower"
        or key == "showChargedComboPoints"
        or key == "runeShowTime"
        or key == "showEleMaelstrom"
        or key == "showEbonMight"
        or key == "showShadowMana"
        or key == "showAltMana"
        or key == "classPowerComboPointColorMode"
end

local function IsBarsGeneralKey(key)
    return BARS_GENERAL_KEYS[key] == true or BARS_SCOPE_KEYS[key] == true
end

local function IsBarsScopeKey(key)
    return BARS_SCOPE_KEYS[key] == true
end

local function IsFontScopeKey(key)
    return FONT_SCOPE_KEYS[key] == true
end

local function IsGameplayColorKey(key)
    return COLOR_GAMEPLAY_KEYS[key] == true or IsColorKey(key)
end

local function ResetAurasSharedColors(db, defaults)
    if type(db) ~= "table" then return end
    db.auras2 = db.auras2 or {}
    db.auras2.shared = db.auras2.shared or {}
    local src = type(defaults) == "table" and type(defaults.auras2) == "table" and defaults.auras2.shared or nil
    ResetKeySet(db.auras2.shared, src, AURAS_SHARED_COLOR_KEYS)
end

local function FactoryDefaults()
    local create = (type(ns) == "table" and ns.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
    if type(create) ~= "function" then return nil end
    local ok, defaults = pcall(create)
    if ok and type(defaults) == "table" then return defaults end
    return nil
end

local function ResetUnitPage(db, defaults, unit)
    ReplaceRootTable(db, defaults, unit)
    if unit == "targettarget" then EnsureTargetTargetAlias(db) end
    local castbarKeys = UNIT_CASTBAR_GENERAL_KEYS[unit]
    if castbarKeys then
        db.general = db.general or {}
        local src = type(defaults) == "table" and defaults.general or nil
        for i = 1, #castbarKeys do
            local key = castbarKeys[i]
            db.general[key] = type(src) == "table" and DeepCopy(src[key]) or nil
        end
    end
end

local function ResetGroupFrames(db, defaults)
    local gf = ns and ns.GF
    if gf and type(gf.ResetAllToDefaults) == "function" then
        return gf.ResetAllToDefaults()
    end
    ReplaceRootTable(db, defaults, "gf_party")
    ReplaceRootTable(db, defaults, "gf_raid")
    ReplaceRootTable(db, defaults, "gf_mythicraid")
    return true
end

local function ResetBarsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", IsBarsGeneralKey)
    ResetRootFiltered(db, defaults, "bars", function(key) return BARS_TABLE_KEYS[key] == true end)
    for _, key in ipairs({ "player", "target", "targettarget", "focus", "pet", "boss", "gf_party", "gf_raid", "gf_mythicraid" }) do
        ResetUnitFiltered(db, defaults, key, IsBarsScopeKey)
    end
    EnsureTargetTargetAlias(db)
end

local function ResetFontsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return FONT_GENERAL_KEYS[key] == true end)
    ResetKeySet(db, defaults, FONT_ROOT_KEYS)
    for _, key in ipairs({ "player", "target", "targettarget", "focus", "pet", "boss", "gf_party", "gf_raid", "gf_mythicraid" }) do
        ResetUnitFiltered(db, defaults, key, IsFontScopeKey)
    end
    EnsureTargetTargetAlias(db)
end

local function ResetAurasPage(db, defaults)
    ReplaceRootTable(db, defaults, "auras2")
    ResetRootFiltered(db, defaults, "general", function(key) return AnyPrefix(key, AURAS_GENERAL_PREFIXES) end)
end

local function ResetCastbarPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key)
        return CASTBAR_GENERAL_KEYS[key] == true or (IsCastbarKey(key) and not IsColorKey(key))
    end)
end

local function ResetColorsPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", IsColorKey)
    ReplaceRootTable(db, defaults, "classColors")
    ReplaceRootTable(db, defaults, "npcColors")
    ResetRootFiltered(db, defaults, "gameplay", IsGameplayColorKey)
    ResetRootFiltered(db, defaults, "bars", function(key) return COLOR_BARS_KEYS[key] == true end)
    ResetAurasSharedColors(db, defaults)
end

local function ResetMiscPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return MISC_GENERAL_KEYS[key] == true end)
    for _, key in ipairs({ "target", "focus", "boss" }) do
        ResetUnitFiltered(db, defaults, key, function(unitKey) return MISC_UNIT_KEYS[unitKey] == true end)
    end
end

local function ResetClassPowerPage(db, defaults)
    ResetRootFiltered(db, defaults, "bars", IsClassPowerBarsKey)
end

local function ResetGameplayPage(db, defaults)
    ReplaceRootTable(db, defaults, "gameplay")
end

local function ResetModulesPage(db, defaults)
    ResetRootFiltered(db, defaults, "general", function(key) return MODULES_GENERAL_KEYS[key] == true end)
end

local function ApplyAfterPageReset(pageKey, info)
    local reason = "MSUF2_RESET_" .. tostring(pageKey or "PAGE")
    if info and info.unit and M.RequestUnitApply then
        M.RequestUnitApply(info.unit, reason, { preview = true, text = true, power = true, alpha = true, castbar = true })
    end
    if M.RequestGeneralApply then
        M.RequestGeneralApply(reason, { preview = true, alpha = true, castbar = true })
    end

    if info and info.kind == "gameplay" then
        if ns and type(ns.MSUF_RequestGameplayApply) == "function" then
            pcall(ns.MSUF_RequestGameplayApply)
        elseif ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then
            pcall(ns.MSUF_ApplyGameplayVisuals)
        end
    end

    local auras = ns and ns.MSUF_Auras2
    if info and (info.kind == "auras" or info.kind == "colors") then
        if auras and type(auras.RequestApply) == "function" then
            pcall(auras.RequestApply)
        elseif type(_G.MSUF_Auras2_RefreshAll) == "function" then
            pcall(_G.MSUF_Auras2_RefreshAll)
        end
        CallGlobal("MSUF_A2_InvalidateCooldownTextCurve")
        CallGlobal("MSUF_A2_ForceCooldownTextRecolor")
    end

    if info and (info.kind == "group" or info.kind == "bars" or info.kind == "fonts" or info.kind == "colors") then
        local gf = ns and ns.GF
        if gf then
            if type(gf.InvalidateConfCache) == "function" then pcall(gf.InvalidateConfCache) end
            if type(gf.RefreshVisuals) == "function" then pcall(gf.RefreshVisuals) end
            if type(gf.RebuildAll) == "function" then pcall(gf.RebuildAll) end
            if type(gf.RequestAuraRefresh) == "function" then pcall(gf.RequestAuraRefresh) end
        end
    end

    if info and info.kind == "classpower" then
        CallGlobal("MSUF_ClassPower_Refresh")
        CallGlobal("MSUF_ClassPower_RefreshTextures")
        CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    end

    if info and info.kind == "modules" then
        CallGlobal("MSUF_ApplyModules")
    end

    CallGlobal("MSUF_UpdateAllFonts_Immediate")
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    CallGlobal("MSUF_UpdateAllBarTextures")
    CallGlobal("MSUF_UpdateCastbarVisuals_Immediate")
    CallGlobal("MSUF_UpdateCastbarVisuals")
    CallGlobal("MSUF_RefreshAllIdentityColors")
    CallGlobal("MSUF_RefreshAllPowerTextColors")
    CallGlobal("MSUF_RefreshAllUnitAlphas")
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_PortraitDecoration_RefreshAll")

    if M.ApplyLocaleSelection then M.ApplyLocaleSelection() end
    if M.ApplyMenuFrameScale and M.frame then pcall(M.ApplyMenuFrameScale, M.frame) end

    if pageKey and M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown() then
        M.InvalidatePage(pageKey)
        M.activeKey = nil
        M.SelectPage(pageKey)
    else
        QueueMenuRefresh()
    end
end

local function ResetProfilePage()
    local name = _G.MSUF_ActiveProfile or "Default"
    if type(_G.MSUF_ResetProfile) ~= "function" then return false end
    pcall(_G.MSUF_ResetProfile, name)
    if M.ClearHistory then M.ClearHistory() end
    ApplyAfterPageReset("profiles", PAGE_RESET_INFO.profiles)
    if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
        _G.MSUF_ShowReloadRecommendedPopup("Profile reset")
    end
    return true
end

local function ResetPageImpl(pageKey)
    local info = PAGE_RESET_INFO[pageKey or ""]
    if not info then return false end
    if info.kind == "profile" then
        return ResetProfilePage()
    end

    local defaults = FactoryDefaults()
    if type(defaults) ~= "table" then
        print("|cffff0000MSUF:|r Reset failed: factory defaults are not available yet.")
        return false
    end

    local db = M.EnsureDB()
    if info.kind == "unit" then
        ResetUnitPage(db, defaults, info.unit)
    elseif info.kind == "group" then
        ResetGroupFrames(db, defaults)
    elseif info.kind == "bars" then
        ResetBarsPage(db, defaults)
    elseif info.kind == "fonts" then
        ResetFontsPage(db, defaults)
    elseif info.kind == "auras" then
        ResetAurasPage(db, defaults)
    elseif info.kind == "castbar" then
        ResetCastbarPage(db, defaults)
    elseif info.kind == "colors" then
        ResetColorsPage(db, defaults)
    elseif info.kind == "misc" then
        ResetMiscPage(db, defaults)
    elseif info.kind == "classpower" then
        ResetClassPowerPage(db, defaults)
    elseif info.kind == "gameplay" then
        ResetGameplayPage(db, defaults)
    elseif info.kind == "modules" then
        ResetModulesPage(db, defaults)
    else
        return false
    end

    EnsureTargetTargetAlias(db)
    ApplyAfterPageReset(pageKey, info)
    print("|cffffd700MSUF:|r " .. tostring(info.label or pageKey) .. " reset to defaults.")
    return true
end

function M.PageHasReset(pageKey)
    return PAGE_RESET_INFO[pageKey or ""] ~= nil
end

function M.GetPageResetInfo(pageKey)
    return PAGE_RESET_INFO[pageKey or ""]
end

function M.BuildPageResetWarning(pageKey)
    local info = PAGE_RESET_INFO[pageKey or ""]
    if not info then return nil end
    local title = info.label or ((M.pages and M.pages[pageKey] and M.pages[pageKey].title) or pageKey or "this menu")
    title = M.Tr and M.Tr(title) or title
    if info.kind == "profile" then
        local profileName = _G.MSUF_ActiveProfile or "Default"
        return string.format(
            "Reset %s to defaults?\n\nThis resets the entire active profile '%s' to the current MSUF factory defaults. Every menu in that profile will be affected.",
            tostring(title),
            tostring(profileName)
        )
    end
    return string.format(
        "Reset %s to defaults?\n\nThis resets %s for the active profile. Defaults are read from the current MSUF factory profile, so future default changes are used automatically.",
        tostring(title),
        tostring(info.summary or title)
    )
end

function M.ResetPageToDefaults(pageKey)
    if M.BlockCombatAction() then return false end
    local info = PAGE_RESET_INFO[pageKey or ""]
    if not info then return false end
    if info.kind == "profile" then
        return ResetPageImpl(pageKey)
    end
    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
        return M.CaptureHistory("Reset " .. tostring(info.label or pageKey), "page:reset:" .. tostring(pageKey), function()
            return ResetPageImpl(pageKey)
        end)
    end
    return ResetPageImpl(pageKey)
end

function M.ShowPageResetConfirm(pageKey)
    if M.BlockCombatAction() then return false end
    if not M.PageHasReset(pageKey) then return false end
    local message = M.BuildPageResetWarning(pageKey)
    if not message then return false end
    if not _G.StaticPopupDialogs then
        return M.ResetPageToDefaults(pageKey)
    end
    if not _G.StaticPopupDialogs.MSUF2_PAGE_RESET_CONFIRM then
        _G.StaticPopupDialogs.MSUF2_PAGE_RESET_CONFIRM = {
            text = "%s",
            button1 = _G.YES or "Yes",
            button2 = _G.NO or "No",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, data)
                if data and data.pageKey then
                    M.ResetPageToDefaults(data.pageKey)
                end
            end,
        }
    end
    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("MSUF2_PAGE_RESET_CONFIRM", message, nil, { pageKey = pageKey })
        return true
    end
    return M.ResetPageToDefaults(pageKey)
end

function M.AddRefresher(ctx, fn)
    if not (ctx and type(fn) == "function") then return end
    ctx.refreshers[#ctx.refreshers + 1] = fn
end

function M.Refresh(ctx)
    local refreshers = ctx and ctx.refreshers
    if not refreshers then
        local entry = M.activeKey and M.cache and M.cache[M.activeKey]
        refreshers = entry and entry.refreshers
    end
    if not refreshers then return end
    for i = 1, #refreshers do
        local fn = refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
end

function M.BindToggle(ctx, widget, getValue, setValue)
    if not widget then return end
    widget:SetScript("OnClick", function(self)
        if BlockCombatAndRefresh(ctx) then return end
        local nextValue = not (getValue() and true or false)
        local label = WidgetHistoryLabel(ctx, self)
        M.CaptureHistory(label, WidgetHistorySource(ctx, self, label), function()
            setValue(nextValue)
        end)
        self:SetChecked(nextValue)
    end)
    M.AddRefresher(ctx, function()
        widget:SetChecked(getValue() and true or false)
    end)
end

function M.BindSlider(ctx, slider, getValue, setValue)
    if not slider then return end
    local function BeginSliderHistory(self)
        if BlockCombatAndRefresh(ctx) then return end
        if self._msuf2Refreshing or self._msuf2HistoryTransaction then return end
        if not M.BeginHistoryTransaction then return end
        local label = WidgetHistoryLabel(ctx, self)
        if M.BeginHistoryTransaction(label, WidgetHistorySource(ctx, self, label)) then
            self._msuf2HistoryTransaction = true
        end
    end
    local function CommitSliderHistory(self)
        if not self._msuf2HistoryTransaction then return end
        self._msuf2HistoryTransaction = nil
        if M.CommitHistoryTransaction then M.CommitHistoryTransaction() end
    end
    slider:HookScript("OnMouseDown", BeginSliderHistory)
    slider:HookScript("OnMouseUp", CommitSliderHistory)
    slider:HookScript("OnHide", CommitSliderHistory)
    slider:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        if BlockCombatAndRefresh(ctx) then return end
        if self._msuf2Step and self._msuf2Step >= 1 then
            value = math.floor(value + 0.5)
        end
        local current = tonumber(getValue()) or 0
        if math.abs(current - value) < 0.0001 then return end
        local label = WidgetHistoryLabel(ctx, self)
        M.CaptureHistory(label, WidgetHistorySource(ctx, self, label), function()
            setValue(value)
        end)
    end)
    M.AddRefresher(ctx, function()
        local value = tonumber(getValue()) or 0
        slider._msuf2Refreshing = true
        slider:SetValue(value)
        if slider.editBox and slider._msuf2FormatValue then
            slider.editBox:SetText(slider._msuf2FormatValue(value))
        end
        if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        slider._msuf2Refreshing = nil
    end)
end

function M.BindSegment(ctx, segment, getValue, setValue)
    if not segment then return end
    for i = 1, #(segment.buttons or {}) do
        local btn = segment.buttons[i]
        btn:SetScript("OnClick", function(self)
            if BlockCombatAndRefresh(ctx) then return end
            if getValue() == self._msuf2Value then
                segment:SetValue(self._msuf2Value)
                return
            end
            local label = WidgetHistoryLabel(ctx, segment)
            M.CaptureHistory(label, WidgetHistorySource(ctx, segment, label), function()
                setValue(self._msuf2Value)
            end)
            segment:SetValue(self._msuf2Value)
        end)
    end
    M.AddRefresher(ctx, function()
        segment:SetValue(getValue())
    end)
end

function M.BindDropdown(ctx, dropdown, getValue, setValue)
    if not dropdown then return end
    dropdown:SetOnValueChanged(function(value)
        if BlockCombatAndRefresh(ctx) then
            if type(getValue) == "function" then dropdown:SetValue(getValue()) end
            return
        end
        if type(getValue) == "function" and getValue() == value then
            dropdown:SetValue(value)
            return
        end
        local label = WidgetHistoryLabel(ctx, dropdown)
        M.CaptureHistory(label, WidgetHistorySource(ctx, dropdown, label), function()
            setValue(value)
        end)
        if type(getValue) == "function" then
            dropdown:SetValue(getValue())
        else
            dropdown:SetValue(value)
        end
    end)
    M.AddRefresher(ctx, function()
        dropdown:SetValue(getValue())
    end)
end

function M.BindTextInput(ctx, editBox, getValue, setValue, commitOnBlur)
    if not editBox then return end
    editBox._msuf2CommitOnBlur = commitOnBlur and true or false
    editBox:SetOnValueCommitted(function(value)
        if BlockCombatAndRefresh(ctx) then return end
        if tostring(getValue() or "") == tostring(value or "") then return end
        local label = WidgetHistoryLabel(ctx, editBox)
        M.CaptureHistory(label, WidgetHistorySource(ctx, editBox, label), function()
            setValue(value or "")
        end)
    end)
    M.AddRefresher(ctx, function()
        if editBox:HasFocus() then return end
        editBox:SetText(tostring(getValue() or ""))
    end)
end

function M.BindColor(ctx, colorButton, getRGB, setRGB)
    if not colorButton then return end
    local function RefreshColor()
        if type(getRGB) ~= "function" then return end
        local r, g, b = getRGB()
        colorButton:SetRGB(r or 1, g or 1, b or 1)
    end
    colorButton:SetOnColorChanged(function(r, g, b)
        if BlockCombatAndRefresh(ctx) then
            RefreshColor()
            return
        end
        if type(getRGB) == "function" then
            local cr, cg, cb = getRGB()
            if math.abs((cr or 1) - (r or 1)) < 0.0001
                and math.abs((cg or 1) - (g or 1)) < 0.0001
                and math.abs((cb or 1) - (b or 1)) < 0.0001
            then
                RefreshColor()
                return
            end
        end
        local label = WidgetHistoryLabel(ctx, colorButton)
        M.CaptureHistory(label, WidgetHistorySource(ctx, colorButton, label), function()
            if type(setRGB) == "function" then setRGB(r, g, b) end
        end)
        RefreshColor()
    end)
    M.AddRefresher(ctx, RefreshColor)
end

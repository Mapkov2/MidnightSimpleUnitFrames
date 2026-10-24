local _, MSUF = ...
local M = MSUF.MSUF2
local H = MSUF.History
local KS = M.KeySet
local ApplyService = MSUF.ApplyService
local function WipeTable(t)
    for key in pairs(t) do t[key] = nil end
end
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
-- Labels a caller translated before it captured (a page reset names itself
-- "Reset %s" over the translated page title). The display path leaves them
-- alone: a second lookup would record the translation as a missing locale key.
local translatedHistoryLabels = {}
local translatedHistoryLabelCount = 0
function M.TranslatedHistoryLabel(label)
    if type(label) ~= "string" or label == "" or translatedHistoryLabels[label] then return label end
    if translatedHistoryLabelCount >= 300 then
        WipeTable(translatedHistoryLabels)
        translatedHistoryLabelCount = 0
    end
    translatedHistoryLabels[label] = true
    translatedHistoryLabelCount = translatedHistoryLabelCount + 1
    return label
end
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
--- The label as the history surfaces show it: machine-shaped keys become
--- words, and the result is translated (a label built from translated pieces
--- stays as it is).
function M.HistoryDisplayLabel(label)
    local text = tostring(label or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return M.Tr("Menu change") end
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
    if not translatedHistoryLabels[text] then out = M.Tr(out) end
    if historyLabelCacheCount > 300 then
        WipeTable(historyLabelCache)
        historyLabelCacheCount = 0
    end
    historyLabelCache[text] = out
    historyLabelCacheCount = historyLabelCacheCount + 1
    return out
end
-- Counted in UTF-8 characters: a translated label must not lose half a letter.
local function FeedbackLabel(text, limit)
    return M.ShortenUtf8(text, tonumber(limit) or 34)
end
-- translated = true: the text is a formatted, already translated message.
local function CommandFeedback(text, kind, seconds, translated)
    local fn = M.ShowStatusFeedback or M.ShowInlineFeedback
    if type(fn) == "function" then fn(text, kind or "info", seconds or 1.25, translated) end
end

local handlers = {}
function handlers.RequestHistoryApply(method, ...)
    local legacy = method == "RequestUnitDomains" and "RequestUnitApply" or "RequestGeneralApply"
    if M[legacy] ~= H[legacy] then return true, M[legacy](...) end
    return true, M[method](...)
end
handlers.HistoryDisplayLabel = M.HistoryDisplayLabel
function handlers.NotifyHistoryChanged()
    if M.RefreshHistoryControls then M.RefreshHistoryControls() end
    if M.frame and M.frame.RefreshStatus then M.frame.RefreshStatus(M.frame) end
end
function handlers.ProfileChange()
    if M.frame and M.frame:IsShown() then M.RequestRefresh(nil, "profile-change") end
end
function handlers.RepaintActivePage(reason)
    return M.RepaintPageAfterDataChange(M.activeKey, reason)
end
function handlers.ShowHistoryFeedback(label)
    if M.ShowHistoryFeedback then M.ShowHistoryFeedback(FeedbackLabel(M.HistoryDisplayLabel(label), 30), 2.0) end
end
function handlers.CommandFeedback(action, label)
    if action == "reset" then return CommandFeedback("Session changes reset", "ok", 1.4) end
    local key = action == "undo" and "Undid %s" or "Redid %s"
    CommandFeedback(M.Format(key, FeedbackLabel(M.HistoryDisplayLabel(label))), "info", 1.25, true)
end
function handlers.RefreshPlayerPowerSource()
    local preview = M._msuf2ClassPowerInlinePreview
    if preview and preview.Refresh then preview:Refresh() end
end
function handlers.RefreshUnitPreview(reason)
    MSUF.Require("MSUF_UFPreview_RequestRefresh", "Shell/Menu2/MSUF_Menu2_Bindings_History.lua")(reason)
end
function handlers.ApplyMenuScale()
    if M.ApplyMenuFrameScale and M.frame then
        M.ApplyMenuFrameScale(M.frame)
    elseif M.GetEffectiveMenuScale and M.frame and M.frame.SetScale then
        local g = H.EnsureDB().general
        local scale = M.GetEffectiveMenuScale(g.slashMenuScale)
        if type(scale) == "number" then M.frame:SetScale(scale) end
    end
end
function handlers.ApplyLocaleSelection()
    M.ApplyLocaleSelection(M.GetLocaleSelection and M.GetLocaleSelection() or "auto")
end
local menuSetters = {
    hideAdvancedMenu = function() M.RefreshAdvancedNavVisibility() end,
    showNavigationIcons = function() M.RefreshNavIconVisibility() end,
    menuFontKey = function()
        M.Theme.ClearMenuFontCache()
        M.Theme.RefreshMenuFonts()
    end,
    menuBackgroundOpacity = function()
        if M.Theme.RefreshMenuBackgroundOpacity then M.Theme.RefreshMenuBackgroundOpacity() end
    end,
}
function handlers.CaptureMenuSettings(g)
    local values = {}
    for key in pairs(menuSetters) do values[key] = g[key] end
    return values
end
function handlers.ResyncMenuSettings(before, g)
    if not before then return end
    for key, apply in pairs(menuSetters) do
        if before[key] ~= g[key] then apply() end
    end
end
H.AttachUI(function(name, ...)
    local handler = handlers[name] or M[name]
    if handler then return handler(...) end
end)
-- The core history surface the menu republishes on M under the same names.
for _, name in ipairs(M.WordList [[
    ApplyScopedFeatureRuntime BeginHistoryTransaction BeginPreparedHistory COLOR_CLASSPOWER_RUNTIME
    CancelHistorySurface CancelHistoryTransaction CaptureSetterOnlySettings CaptureGuidedTourRestorePoint
    CaptureHistory CheckpointHistory ClearHistory CommitHistoryTransaction CommitPreparedHistory
    DeferPreparedHistory EndHistorySession FlushApplyServiceNow FlushDeferredHistory GetHistoryState
    HistoryRetainedBytes IsHistoryCapturing IsHistoryTransactionActive PrepareHistoryChange
    RebaseHistoryForProfileChange Redo RegisterHistoryProvider RequestGeneralApply RequestGeneralDomains
    RequestUnitApply RequestUnitDomains ResetHistorySession RestoreGuidedTourRestorePoint
    ResyncSetterOnlySettings RunWithHistory StartHistorySession SyncExternalHistoryState Undo
    UnregisterHistoryProvider
]]) do M[name] = H[name] end
-- Preserve public request interception while normal writers stay typed.
function M.RequestUnitDomains(unit, reason, opts)
    if M.RequestUnitApply ~= H.RequestUnitApply then return M.RequestUnitApply(unit, reason, opts) end
    return H.RequestUnitDomains(unit, reason, opts)
end
function M.RequestGeneralDomains(reason, opts)
    if M.RequestGeneralApply ~= H.RequestGeneralApply then return M.RequestGeneralApply(reason, opts) end
    return H.RequestGeneralDomains(reason, opts)
end
-- Both surfaces retain the same stack tables, including across a late UI load.
H.GetHistoryState()
M.historyUndo, M.historyRedo = H.historyUndo, H.historyRedo
local function HistoryBusy() return H.IsHistoryCapturing() end
local function NormalizeHistoryUnit(unit) return ApplyService.NormalizeUnit(unit) end
function M.SetUnitValue(unit, key, value, reason, opts)
    if M.BlockCombatAction() then return false end
    if not NormalizeHistoryUnit(unit) then return false end
    if not HistoryBusy() then
        return M.CaptureHistory(tostring(key), "unit:" .. tostring(unit) .. ":" .. tostring(key), function()
            return M.SetUnitValue(unit, key, value, reason, opts)
        end, NormalizeHistoryUnit(unit))
    end
    local conf = M.GetUnitDB(unit)
    if not conf then return false end
    local sameValue = conf[key] == value
    if not sameValue then conf[key] = value end
    local directTextChanged = M.SyncDirectTextOffsets(conf, key)
    if sameValue and not directTextChanged then return false end
    M.RequestUnitDomains(unit, reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end
function M.SetGeneralValue(key, value, reason, opts)
    if M.BlockCombatAction() then return false end
    if not HistoryBusy() then
        return M.CaptureHistory(tostring(key), "general:" .. tostring(key), function()
            return M.SetGeneralValue(key, value, reason, opts)
        end, "general")
    end
    local g = M.GetGeneralDB()
    if g[key] == value then return false end
    g[key] = value
    if key == "menuLocale" then
        if M.ApplyLocaleSelection then M.ApplyLocaleSelection(value) end
        if opts and opts.noRuntime == true then return true end
    end
    M.RequestGeneralDomains(reason or ("MSUF2_" .. tostring(key)), opts)
    return true
end

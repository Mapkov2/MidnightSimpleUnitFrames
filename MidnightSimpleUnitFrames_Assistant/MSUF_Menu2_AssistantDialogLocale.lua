-- Deterministic DE/EN presentation adapter for the Menu2 Assistant.
--
-- Runtime contract:
--   * no events, timers, OnUpdate handlers, jobs, or warmups;
--   * no work while the MSUF menu is closed or combat is active;
--   * only explicit Submit/SubmitDeferred turns enter the adapter;
--   * canonical setting, action, button, page, and identifier text is preserved.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant
local Data = MSUF.AssistantDialogLocaleData
if type(A) ~= "table" or type(Data) ~= "table" then return end

local D = A.DialogLocale or {}
A.DialogLocale = D

if D.installed == true then return end

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Normalized(text, maxBytes)
    text = tostring(text or "")
    maxBytes = tonumber(maxBytes) or #text
    if #text > maxBytes then text = text:sub(1, maxBytes) end
    text = text:lower()
        :gsub("ä", "ae"):gsub("ö", "oe"):gsub("ü", "ue"):gsub("ß", "ss")
        :gsub("[%c%p]", " "):gsub("%s+", " ")
    return Trim(text)
end

local function ContainsPhrase(normalized, phrase)
    -- Locale phrases are normalized in the data file. Avoid normalizing the same
    -- constants again for every turn.
    phrase = tostring(phrase or "")
    if phrase == "" then return false end
    return (" " .. normalized .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

local function ClientLanguage()
    local locale = type(_G.GetLocale) == "function" and tostring(_G.GetLocale() or "") or ""
    return locale == "deDE" and "de" or tostring(Data.defaultLanguage or "en")
end

local function InCombat()
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

function D.IsMenuOpen()
    local frame = M and M.frame
    if not (frame and type(frame.IsShown) == "function") then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

function D.CanAdaptNow()
    if not D.IsMenuOpen() then return false end
    return not InCombat()
end

function D.DetectPromptLanguage(text, previousLanguage, clientLanguage)
    local previous = Data.supportedLanguages[previousLanguage] and previousLanguage
        or (Data.supportedLanguages[clientLanguage] and clientLanguage)
        or ClientLanguage()
    local normalized = Normalized(text, Data.maxPromptBytes)
    if normalized == "" or Data.neutralPrompts[normalized] == true then return previous, "context" end

    for _, language in ipairs({ "de", "en" }) do
        local phrases = Data.explicitLanguage[language] or {}
        for i = 1, #phrases do
            if ContainsPhrase(normalized, phrases[i]) then return language, "explicit" end
        end
    end

    local scores = { de = 0, en = 0 }
    for word in normalized:gmatch("%S+") do
        scores.de = scores.de + tonumber(Data.promptMarkers.de[word] or 0)
        scores.en = scores.en + tonumber(Data.promptMarkers.en[word] or 0)
    end
    if scores.de >= 3 and scores.de > scores.en then return "de", "prompt" end
    if scores.en >= 3 and scores.en > scores.de then return "en", "prompt" end
    return previous, "context"
end

local function EnsureStats()
    D.stats = D.stats or {
        turns = 0,
        deTurns = 0,
        enTurns = 0,
        fullyLocalized = 0,
        safelyWrapped = 0,
        englishPassthrough = 0,
        localizedBytes = 0,
    }
    return D.stats
end

function D.BeginTurn(text)
    if not D.CanAdaptNow() then return nil, InCombat() and "combat" or "menu_closed" end
    local language, reason = D.DetectPromptLanguage(text, D.currentLanguage, ClientLanguage())
    D.currentLanguage = language
    D.lastDetectionReason = reason
    local stats = EnsureStats()
    stats.turns = stats.turns + 1
    if language == "de" then stats.deTurns = stats.deTurns + 1 else stats.enTurns = stats.enTurns + 1 end
    return language, reason
end

function D.GetLanguage()
    return D.currentLanguage or ClientLanguage()
end

function D.ResetSession(language)
    D.currentLanguage = Data.supportedLanguages[language] and language or nil
    D.lastDetectionReason = nil
    D.stats = nil
end

local function TranslatePattern(line)
    local setting, oldValue, newValue = line:match("^Done%. I changed (.+) from (.+) to (.+)%.$")
    if setting then
        return "Erledigt. Ich habe " .. setting .. " von „" .. oldValue .. "“ auf „" .. newValue .. "“ geändert.", true
    end

    local count = line:match("^Done%. I changed (%d+) MSUF options:$")
    if count then return "Erledigt. Ich habe " .. count .. " MSUF-Optionen geändert:", true end

    local index
    index, setting, oldValue, newValue = line:match("^(%d+)%. (.+) from (.+) to (.+)%.$")
    if index then
        return index .. ". " .. setting .. " von „" .. oldValue .. "“ auf „" .. newValue .. "“.", true
    end

    count = line:match("^And (%d+) more%.$")
    if count then return "Dazu kommen " .. count .. " weitere.", true end

    setting, newValue = line:match("^Already set%. (.+) is already (.+)%. I refreshed it so the visible UI uses the current value%.$")
    if setting then
        return "Bereits eingestellt. " .. setting .. " steht schon auf „" .. newValue .. "“. Ich habe die sichtbare UI mit diesem Wert aktualisiert.", true
    end

    setting, newValue = line:match("^Already set%. (.+) is already (.+)%.$")
    if setting then return "Bereits eingestellt. " .. setting .. " steht schon auf „" .. newValue .. "“.", true end

    local label = line:match("^Done%. I ran (.+)%.$")
    if label then return "Erledigt. Ich habe " .. label .. " ausgeführt.", true end

    label = line:match("^Done%. Opened (.+)%.$")
    if label then return "Erledigt. " .. label .. " wurde geöffnet.", true end

    label = line:match("^Opened (.+) navigation section%.$")
    if label then return "Der Navigationsbereich " .. label .. " wurde geöffnet.", true end

    label = line:match("^Closed (.+) navigation section%.$")
    if label then return "Der Navigationsbereich " .. label .. " wurde geschlossen.", true end

    label = line:match("^Opened (.+)%.$")
    if label then return label .. " wurde geöffnet.", true end

    label = line:match("^Closed (.+)%.$")
    if label then return label .. " wurde geschlossen.", true end

    setting, newValue = line:match("^Current value: (.+) is (.+)%.$")
    if setting then return "Aktueller Wert: " .. setting .. " ist auf „" .. newValue .. "“ gesetzt.", true end

    local value = line:match("^Current value: (.+)%.$")
    if value then return "Aktueller Wert: " .. value .. ".", true end

    label = line:match("^I can apply (.+)%. Answer with 'yes', 'do it', 'apply', or 'cancel'%.$")
    if label then
        return "Ich kann " .. label .. " anwenden. Antworte mit 'yes', 'do it' oder 'apply'; mit 'cancel' brichst du ab.", true
    end

    local name = line:match("^Good morning, (.+)%. I am ready to help with MSUF%.$")
    if name then return "Guten Morgen, " .. name .. ". Ich bin bereit, dir mit MSUF zu helfen.", true end
    name = line:match("^Good afternoon, (.+)%. I am ready to help with MSUF%.$")
    if name then return "Guten Tag, " .. name .. ". Ich bin bereit, dir mit MSUF zu helfen.", true end
    name = line:match("^Good evening, (.+)%. I am ready to help with MSUF%.$")
    if name then return "Guten Abend, " .. name .. ". Ich bin bereit, dir mit MSUF zu helfen.", true end
    name = line:match("^Good night, (.+)%. I am ready to help with MSUF%.$")
    if name then return "Gute Nacht, " .. name .. ". Ich bin bereit, dir mit MSUF zu helfen.", true end

    label = line:match("^Yes%. MSUF runs without (.+)%. Removing or disabling that addon does not change MSUF settings%. You only lose the features supplied by that addon%.$")
    if label then
        return "Ja. MSUF läuft ohne " .. label .. ". Das Entfernen oder Deaktivieren dieses Addons ändert keine MSUF-Einstellungen; nur dessen eigene Funktionen entfallen.", true
    end

    label = line:match("^I understand that (.+) is failing beside MSUF%. I did not change any setting%.$")
    if label then
        return "Ich habe verstanden, dass " .. label .. " neben MSUF ausfällt. Ich habe keine Einstellung geändert.", true
    end

    label = line:match("^I cannot verify (.+) from MSUF's bundled offline knowledge%. Keep MSUF as the only owner of its unit and group frames, disable overlapping modules, and check that addon's current Retail/Midnight page%.$")
    if label then
        return "Ich kann " .. label .. " mit dem gebündelten Offline-Wissen von MSUF nicht prüfen. Lass MSUF allein seine Unit- und Gruppenframes verwalten, deaktiviere überschneidende Module und prüfe die aktuelle Retail-/Midnight-Seite dieses Addons.", true
    end

    label = line:match("^Assistant help for (.+):$")
    if label then return "Assistant-Hilfe für " .. label .. ":", true end
    label = line:match("^(.+) help$")
    if label and #label <= 80 then return "Hilfe: " .. label, true end

    local optionCount, taskCount = line:match("^I can handle (%d+) MSUF options plus (%d+) guided tasks or checks across (.+)%.$")
    if optionCount then
        local areas = line:match(" across (.+)%.$") or "the supported MSUF areas"
        return "Ich kann " .. optionCount .. " MSUF-Optionen und " .. taskCount .. " geführte Aufgaben oder Prüfungen abdecken. Bereiche (Originalnamen): " .. areas .. ".", true
    end

    optionCount, taskCount = line:match("^On this page I can handle (%d+) options and (%d+) guided tasks or checks%.$")
    if optionCount then
        return "Auf dieser Seite kann ich " .. optionCount .. " Optionen und " .. taskCount .. " geführte Aufgaben oder Prüfungen bearbeiten.", true
    end

    label = line:match("^Done%. (.+) check:$")
    if label then return "Erledigt. Prüfung: " .. label .. ":", true end

    label = line:match("^(.+) are disabled%.$")
    if label then return label .. " sind deaktiviert.", true end

    label = line:match("^(.+) are hidden or their max icon count is zero%.$")
    if label then return label .. " sind ausgeblendet oder ihre maximale Icon-Anzahl ist null.", true end

    label, newValue = line:match("^Last change I made: (.+) was already (.+)%.$")
    if label then return "Meine letzte Änderung: " .. label .. " stand bereits auf „" .. newValue .. "“.", true end

    return line, false
end

local function TranslateLine(line)
    local de = Data.de
    local exact = de.exact[line]
    if exact then return exact, true end

    local patterned, matched = TranslatePattern(line)
    if matched then return patterned, true end

    for prefix, replacement in pairs(de.labels) do
        if line:sub(1, #prefix) == prefix then
            return replacement .. line:sub(#prefix + 1), true
        end
    end
    return line, false
end

local function LooksTechnical(line)
    line = Trim(line)
    if line == "" then return true end
    if line:match("^%d+[%.)]%s") or line:match("^[%-%*|]") then return true end
    if line:match("^https?://") or line:match("^www%.") or line:match("^/") then return true end
    if line:match("^[%w_]+%.[%w_%.]+%s*=") then return true end
    return false
end

function D.LocalizeText(text, language, status, options)
    text = tostring(text or "")
    language = language or D.GetLanguage()
    if language ~= "de" or text == "" then return text, "passthrough" end
    options = options or {}

    if options.summary ~= true and #text > tonumber(Data.maxResponseBytes or 24000) then
        local lead = Data.de.fallbackLead[tostring(status or "info")] or Data.de.fallbackLead.info
        return lead .. "\n" .. Data.de.technicalLead .. "\n" .. text, "wrapped"
    end

    local translated = {}
    local changed = 0
    local naturalUnchanged = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local localized, matched = TranslateLine(line)
        translated[#translated + 1] = localized
        if matched then
            changed = changed + 1
        elseif not LooksTechnical(line) then
            naturalUnchanged = naturalUnchanged + 1
        end
    end
    local output = table.concat(translated, "\n")
    if options.summary == true then return output, changed > 0 and "localized" or "passthrough" end

    if naturalUnchanged == 0 and changed > 0 then return output, "localized" end

    local lead = Data.de.fallbackLead[tostring(status or "info")] or Data.de.fallbackLead.info
    return lead .. "\n" .. Data.de.technicalLead .. "\n" .. output, "wrapped"
end

local localizedResults = setmetatable({}, { __mode = "k" })

function D.LocalizeResult(result, language)
    if type(result) ~= "table" or localizedResults[result] then return result end
    language = language or D.GetLanguage()
    if language ~= "de" then
        EnsureStats().englishPassthrough = EnsureStats().englishPassthrough + 1
        localizedResults[result] = true
        return result
    end
    local status = result.status or result.result or "info"
    local mode
    result.text, mode = D.LocalizeText(result.text, language, status)
    if type(result.summary) == "string" then
        result.summary = D.LocalizeText(result.summary, language, status, { summary = true })
    end
    local stats = EnsureStats()
    if mode == "localized" then stats.fullyLocalized = stats.fullyLocalized + 1
    elseif mode == "wrapped" then stats.safelyWrapped = stats.safelyWrapped + 1
    else stats.englishPassthrough = stats.englishPassthrough + 1 end
    stats.localizedBytes = stats.localizedBytes + #tostring(result.text or "")
    localizedResults[result] = true
    return result
end

function D.GetCoverageReport()
    local stats = EnsureStats()
    local out = {
        version = Data.version,
        policy = "canonical-en-plus-deterministic-de-adapter",
        languages = { "en", "de" },
        canonicalTechnicalNamesPreserved = true,
        events = 0,
        timers = 0,
        onUpdates = 0,
        warmups = 0,
        menuOpenRequired = true,
        combatAllowed = false,
        responseFamilies = {
            "applied", "unchanged", "confirmation", "clarification", "choice",
            "navigation", "current-value", "undo-redo", "cancel", "busy", "combat",
            "knowledge-safe-wrapper",
        },
    }
    for key, value in pairs(stats) do out[key] = value end
    local localized = stats.fullyLocalized + stats.safelyWrapped
    out.germanAdapted = localized
    out.germanCoveragePercent = stats.deTurns > 0 and math.floor((localized * 1000 / stats.deTurns) + 0.5) / 10 or 0
    return out
end

local originalSubmit = A.Submit
local originalSubmitDeferred = A.SubmitDeferred
local AP = A.RuntimePrivate
local originalRecordAssistantResult = type(AP) == "table" and AP.RecordAssistantResult or nil
local originalShowLargeTextPanel = A.ShowLargeTextPanel

local INACTIVE_REPLY = {
    text = "Open the MSUF menu to use the Assistant. / Öffne das MSUF-Menü, um den Assistant zu verwenden.",
    status = "inactive",
    result = "inactive",
    summary = "Assistant inactive while the MSUF menu is closed.",
    reason = "menu_closed",
}

local COMBAT_REPLY = {
    text = "Assistant work is disabled during combat. / Assistant-Arbeit ist im Kampf deaktiviert.",
    -- Deliberately not the legacy `combat` status: the Dashboard used that status
    -- to append history, which would violate the zero-work combat contract.
    status = "inactive",
    result = "inactive",
    summary = "Assistant inactive during combat.",
    reason = "combat",
}

local function GatedReply()
    -- Menu visibility is checked first so a closed menu never calls combat APIs.
    local source = D.IsMenuOpen() and COMBAT_REPLY or INACTIVE_REPLY
    -- Keep the published constants private so a caller cannot alter later replies.
    return {
        text = source.text,
        status = source.status,
        result = source.result,
        summary = source.summary,
        reason = source.reason,
    }
end

if type(AP) == "table" and type(originalRecordAssistantResult) == "function" then
    AP.RecordAssistantResult = function(result)
        local language = D._activeSubmitLanguage or D._deferredLanguage
        if language and D.CanAdaptNow() then D.LocalizeResult(result, language) end
        return originalRecordAssistantResult(result)
    end
end

if type(originalShowLargeTextPanel) == "function" then
    A.ShowLargeTextPanel = function(spec)
        local language = D._activeSubmitLanguage or D._deferredLanguage
        if language == "de" and D.CanAdaptNow() and type(spec) == "table" then
            local localized = {}
            for key, value in pairs(spec) do localized[key] = value end
            for _, key in ipairs({ "title", "help", "status" }) do
                if type(localized[key]) == "string" then
                    localized[key] = D.LocalizeText(localized[key], language, "info")
                end
            end
            spec = localized
        end
        return originalShowLargeTextPanel(spec)
    end
end

if type(originalSubmit) == "function" then
    A.Submit = function(text)
        if not D.CanAdaptNow() then
            return GatedReply()
        end
        local language = D.BeginTurn(text)
        D._activeSubmitLanguage = language
        local ok, result = pcall(originalSubmit, text)
        D._activeSubmitLanguage = nil
        if not ok then error(result, 0) end
        return D.LocalizeResult(result, language)
    end
end

if type(originalSubmitDeferred) == "function" then
    A.SubmitDeferred = function(text, callback)
        if not D.CanAdaptNow() then
            return GatedReply()
        end
        local language = D.BeginTurn(text)
        D._activeSubmitLanguage = language
        D._deferredLanguage = language
        local function LocalizedCallback(result, ...)
            if D.CanAdaptNow() then D.LocalizeResult(result, language) end
            D._deferredLanguage = nil
            if type(callback) == "function" then return callback(result, ...) end
        end
        local ok, result = pcall(originalSubmitDeferred, text, LocalizedCallback)
        D._activeSubmitLanguage = nil
        if not ok then
            D._deferredLanguage = nil
            error(result, 0)
        end
        if type(result) == "table" and D.CanAdaptNow() then D.LocalizeResult(result, language) end
        if not (A.IsBusy and A.IsBusy()) then D._deferredLanguage = nil end
        return result
    end
end

D.installed = true

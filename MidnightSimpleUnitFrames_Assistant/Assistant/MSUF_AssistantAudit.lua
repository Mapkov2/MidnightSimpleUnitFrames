-- Assistant registry coverage audit.
--
-- Replaces the manual "Matrix-Audit" from MSUF_Assistant_Coverage.md with a
-- live, in-game comparison: every scalar key in the saved-variable DB is
-- checked against the assistant setting registry. Gaps (DB keys the assistant
-- cannot reach) and stale entries (registry keys with no DB backing) become
-- visible on demand instead of being tracked by hand.
--
-- Usage:
--   /msufcoverage                summary per scope in chat
--   /msufcoverage <scope>        detailed gap report in a copyable window
--   /msufcoverage all            full report for every scope
--   /msufcoverage stubs <scope>  generated registration stubs for the gaps
--   /msufcoverage smoke          in-game acceptance checklist
--   /msufcoverage smoke pass <id>|fail <id> <note>|block <id> <note>|reset
--   /msufcoverage gate           summary gate for smoke + manifest + coverage
--
-- The audit only reads; it never mutates the DB or the registry.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Audit = A.CoverageAudit or {}
A.CoverageAudit = Audit

local UNIT_SCOPES = { "player", "target", "targettarget", "focustarget", "focus", "pet", "boss" }
local GROUP_SCOPES = { "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }
local FLAT_SCOPES = { "general", "bars", "gameplay" }

-- DB keys that are bookkeeping, not user-facing settings. Extend via
-- A.CoverageAudit.ignore[scope][key] = true (scope "*" applies everywhere).
Audit.ignore = Audit.ignore or {
    ["*"] = {
        version = true,
        migrated = true,
    },
    -- Editor/preview runtime state and keys owned by curated assistant
    -- actions: generating settings for these would shadow the actions
    -- ("set global font color to yellow" is the set_global_font_color action).
    general = {
        auraFontSize = true,
        bossPreviewEnabled = true,
        editModeSnapToGrid = true,
        fontColor = true,
        -- Chrome and selector state the UI persists for itself. These are
        -- written by the widget that owns them (the tip cycler advances
        -- tipCycleIndex, the options window saves its own size, a scope tab
        -- records which unit is on screen), never chosen as a setting. Left
        -- visible they would compete with real controls in candidate scoring:
        -- "set the window width" is a frame width request, not a request to
        -- resize the options panel.
        hpPowerTextSelectedKey = true,
        msuf2WindowH = true,
        msuf2WindowW = true,
        tipCycleIndex = true,
    },
    -- Compatibility mirror retained in the bars table. The visible/global
    -- owner is general.highlightBorderThickness; scoped overrides are owned by
    -- barScope.*.highlightBorderThickness.
    bars = {
        highlightBorderThickness = true,
    },
    -- Player is never range-checked by the runtime (RANGE_KEYS deliberately
    -- excludes it), even if old profiles still carry copied rangeFade fields.
    player = {
        rangeFadeEnabled = true,
        rangeFadeAlpha = true,
        rangeFadeLayerMode = true,
        -- Unit frames read the canonical general toggle. This copied legacy
        -- field is not a distinct Player control.
        showSelfHealPrediction = true,
        -- Migration sentinel, not a value: the engine only ever compares it
        -- against the literal 2 (MSUF_UF_Core.lua:569) to decide whether a
        -- profile predates the gradient-override rewrite.
        gradientOverrideVersion = true,
    },
    target = {
        gradientOverrideVersion = true,
    },
    -- Legacy flat mirrors copied from unit-frame fields into the group scopes;
    -- the canonical group settings are powerHeight and the nested
    -- auras.buff/debuff tables that curated registrations control. Exact
    -- name-shortening ownership lives in AutoCoverage's reviewed ledger so an
    -- absent owner fails closed instead of being hidden by this ignore table.
    -- groupGrowth is secondary secure-header/import state, not the visible
    -- primary Growth control. Exposing it as an unconstrained string would let
    -- the Assistant write invalid layout state. Party's copied heal-prediction
    -- field is likewise inert; the reviewed owner is barScope.gf_party.
    gf_party = {
        auraIconSize = true, auraMaxIcons = true, powerBarHeight = true,
        groupGrowth = true, showSelfHealPrediction = true,
    },
    gf_raid = {
        auraIconSize = true, auraMaxIcons = true, powerBarHeight = true,
        groupGrowth = true,
    },
    gf_mythicraid = {
        auraIconSize = true, auraMaxIcons = true, powerBarHeight = true,
        groupGrowth = true,
    },
    -- Free Priority Frame coordinates are owned by the dedicated Edit Mode
    -- mover. They are persisted implementation state, not independent scalar
    -- controls; the public Assistant surface owns placement mode/gap/offset.
    gf_priority = {
        point = true, relativePoint = true, offsetX = true, offsetY = true,
    },
}

-- Coverage keys are compared case/punctuation-insensitively. Do not rewrite
-- semantic words here: fields such as portraitBackgroundColor and
-- portraitBgColor can coexist with different values. True storage mirrors
-- must be claimed explicitly through dbScopes/norms on the curated setting.
local function NormalizeCoverageKey(key)
    key = tostring(key or ""):lower():gsub("[^%w]", "")
    return key
end
Audit.NormalizeCoverageKey = NormalizeCoverageKey

local function IsCoveredKey(coveredSet, key)
    if type(coveredSet) ~= "table" then return nil end
    local direct = coveredSet[key]
    if direct then return direct end
    local norm = coveredSet._norm
    return norm and norm[NormalizeCoverageKey(key)] or nil
end
Audit.IsCoveredKey = IsCoveredKey

local function IsIgnored(scope, key)
    if type(key) ~= "string" or key == "" then return true end
    if key:sub(1, 1) == "_" then return true end
    local star = Audit.ignore["*"]
    if star and star[key] then return true end
    local scoped = Audit.ignore[scope]
    if scoped and scoped[key] then return true end
    -- AutoCoverage owns the exact reviewed compatibility-projection ledger.
    -- Resolve it dynamically because this audit module loads immediately
    -- before AutoCoverage in the LoD manifest.
    local auto = A.AutoCoverage
    return auto and type(auto.CompatibilityProjectionReason) == "function"
        and auto.CompatibilityProjectionReason(scope, key) ~= nil or false
end
Audit.IsIgnored = IsIgnored

local function ScopeDB(scope)
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    local tbl = db[scope]
    return type(tbl) == "table" and tbl or nil
end

local function AllScopes()
    local out = {}
    for i = 1, #UNIT_SCOPES do out[#out + 1] = UNIT_SCOPES[i] end
    for i = 1, #GROUP_SCOPES do out[#out + 1] = GROUP_SCOPES[i] end
    for i = 1, #FLAT_SCOPES do out[#out + 1] = FLAT_SCOPES[i] end
    return out
end

local VALID_SCOPE
local function IsValidScope(scope)
    if not VALID_SCOPE then
        VALID_SCOPE = {}
        local scopes = AllScopes()
        for i = 1, #scopes do VALID_SCOPE[scopes[i]] = true end
    end
    return VALID_SCOPE[scope] == true
end

-- Registry setting keys embed the DB key ("player.hpBarAlpha",
-- "gf_party.enabled", "general.globalUiScale"). Settings may additionally
-- carry unit + attribute; both paths are marked covered so keySuffix and
-- attr/dbKey mismatches do not produce false gaps.
local function SettingScope(setting)
    local key = type(setting.key) == "string" and setting.key or ""
    local prefix, rest = key:match("^([^.]+)%.(.+)$")
    local out = {}
    -- Curated aggregate controls may own more than the scope encoded in their
    -- public key. Example: the visible Raid style control intentionally writes
    -- both gf_raid and gf_mythicraid. Make that ownership explicit so raw DB
    -- mirrors are never exposed as separate AutoCoverage settings.
    local explicitScopes = type(setting.dbScopes) == "table" and setting.dbScopes or {}
    for i = 1, #explicitScopes do
        local target = setting.dbScopes[i]
        local scope = type(target) == "table" and (target.scope or target[1]) or nil
        local dbKey = type(target) == "table" and (target.dbKey or target.key or target[2]) or nil
        if IsValidScope(scope) and type(dbKey) == "string" and dbKey ~= "" then
            out[#out + 1] = { scope = scope, dbKey = dbKey, norms = target.norms }
        end
    end
    local replaceInferred = setting.dbScopesReplace == true and #out > 0
    if not replaceInferred and prefix and IsValidScope(prefix) then
        out[#out + 1] = { scope = prefix, dbKey = rest }
    end
    -- Three-segment keys ("fontScope.focus.npcNameRed", "barScope.player.X")
    -- wrap a per-scope DB key in a domain prefix. Treat the middle segment as
    -- the scope so these hand-written settings mark their DB keys covered and
    -- AutoCoverage never generates duplicates for them. The domain word is
    -- also prepended as a normalized variant because the raw DB key often
    -- carries it ("fontScope.focus.override" stores db.focus.fontOverride).
    local domainSeg, midScope, midKey = key:match("^([^.]+)%.([^.]+)%.(.+)$")
    if not replaceInferred and midScope then
        if midScope == "tot" then midScope = "targettarget" end
        if IsValidScope(midScope) and not midKey:find(".", 1, true) then
            local norms = { NormalizeCoverageKey(midKey) }
            local domain = domainSeg:match("^(%a+)[Ss]cope$")
            if domain then norms[#norms + 1] = NormalizeCoverageKey(domain .. midKey) end
            out[#out + 1] = { scope = midScope, dbKey = midKey, norms = norms }
        end
    end
    local unit = setting.unit
    local attr = setting.attribute
    if not replaceInferred and type(unit) == "string" and type(attr) == "string" and attr ~= "" then
        if unit == "tot" then unit = "targettarget" end
        local scope
        if setting.frameType == "group" then
            scope = "gf_" .. unit
        elseif IsValidScope(unit) then
            scope = unit
        end
        if scope and IsValidScope(scope) then
            out[#out + 1] = { scope = scope, dbKey = attr }
        end
    end
    return out
end

local function BuildCoveredSets()
    local covered = {}
    local unmapped = 0
    local generated = 0
    local registry = A.Registry
    local settings = type(registry) == "table" and registry.settings or nil
    if type(settings) ~= "table" then return covered, 0, 0, 0 end
    for i = 1, #settings do
        if i % 64 == 0 and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local setting = settings[i]
        if type(setting) == "table" then
            if setting.generated then generated = generated + 1 end
            local targets = SettingScope(setting)
            if #targets == 0 then
                unmapped = unmapped + 1
            else
                for t = 1, #targets do
                    local target = targets[t]
                    local scopeSet = covered[target.scope]
                    if not scopeSet then
                        scopeSet = { _norm = {} }
                        covered[target.scope] = scopeSet
                    end
                    -- Keep the hand-written entry when both cover the same key
                    -- so stale classification can skip generated fallbacks.
                    local prev = scopeSet[target.dbKey]
                    if not prev or (prev.generated and not setting.generated) then
                        scopeSet[target.dbKey] = setting
                    end
                    local norms = target.norms or { NormalizeCoverageKey(target.dbKey) }
                    for n = 1, #norms do
                        local prevNorm = scopeSet._norm[norms[n]]
                        if not prevNorm or (prevNorm.generated and not setting.generated) then
                            scopeSet._norm[norms[n]] = setting
                        end
                    end
                end
            end
        end
    end
    local auto = A.AutoCoverage
    if auto and type(auto.ApplyCanonicalPathOwnership) == "function" then
        auto.ApplyCanonicalPathOwnership(covered, registry)
    end
    return covered, #settings, unmapped, generated
end
Audit.BuildCoveredSets = BuildCoveredSets

local function AuditScope(scope, covered)
    local db = ScopeDB(scope)
    local result = {
        scope = scope,
        available = db ~= nil,
        total = 0,
        coveredCount = 0,
        gaps = {},
        nested = {},
        stale = {},
    }
    if not db then return result end
    local coveredSet = covered[scope] or {}
    for key, value in pairs(db) do
        if type(key) == "string" and not IsIgnored(scope, key) then
            local valueType = type(value)
            if valueType == "table" then
                result.nested[#result.nested + 1] = key
            elseif valueType == "boolean" or valueType == "number" or valueType == "string" then
                result.total = result.total + 1
                if IsCoveredKey(coveredSet, key) then
                    result.coveredCount = result.coveredCount + 1
                else
                    result.gaps[#result.gaps + 1] = { key = key, valueType = valueType, value = value }
                end
            end
        end
    end
    for dbKey, setting in pairs(coveredSet) do
        -- Generated fallbacks mirror the DB by construction; a missing value
        -- there is just an untouched default, not a stale registration.
        if dbKey ~= "_norm" and db[dbKey] == nil and not (type(setting) == "table" and setting.generated) then
            result.stale[#result.stale + 1] = dbKey
        end
    end
    table.sort(result.gaps, function(a, b) return a.key < b.key end)
    table.sort(result.nested)
    table.sort(result.stale)
    return result
end

function Audit.Run(scopeFilter)
    local covered, settingCount, unmapped, generated = BuildCoveredSets()
    local scopes = scopeFilter and { scopeFilter } or AllScopes()
    local results = {}
    for i = 1, #scopes do
        results[#results + 1] = AuditScope(scopes[i], covered)
    end
    return results, settingCount, unmapped, generated
end

local function Percent(part, total)
    if total <= 0 then return 100 end
    return math.floor((part / total) * 100 + 0.5)
end

-- Persist the latest summary so the external training harness can read it
-- from SavedVariables instead of re-deriving coverage on its own.
local function StoreSummary(results, settingCount, unmapped, generated)
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return end
    local store = { time = date("%Y-%m-%d %H:%M:%S"), settings = settingCount, unmapped = unmapped, generated = generated or 0, scopes = {} }
    for i = 1, #results do
        local r = results[i]
        store.scopes[r.scope] = {
            total = r.total,
            covered = r.coveredCount,
            gaps = #r.gaps,
            stale = #r.stale,
            nested = #r.nested,
        }
    end
    gdb.assistantCoverage = store
end

-- ---------------------------------------------------------------------------
-- Stub generation: turns gaps into ready-to-paste registration calls so
-- closing a gap is an edit, not archaeology.
-- ---------------------------------------------------------------------------
local function LabelFromKey(key)
    local label = key:gsub("(%l)(%u)", "%1 %2")
        :gsub("(%u)(%u%l)", "%1 %2")
        :gsub("(%a)(%d)", "%1 %2"):gsub("_", " ")
    label = label:gsub("^%l", string.upper)
    return label
end

local function NumberStubBounds(value)
    if value >= 0 and value <= 1 then return "0, 1", "0.05" end
    return "0, " .. tostring(math.max(100, math.ceil(math.abs(value)) * 2)), "1"
end

local function StubForGap(scope, gap)
    local key = gap.key
    local label = LabelFromKey(key)
    local aliasNoun = label:lower()
    local isGroup = scope:sub(1, 3) == "gf_"
    local groupScope = isGroup and scope:sub(4) or nil
    if gap.valueType == "boolean" then
        if isGroup then
            return ('RegisterGroupBoolean("%s", "%s", "%s", "%s", %s, "visual", MakeAliases("%s", "%s"), { category = "TODO" })')
                :format(groupScope, key, key, label, tostring(gap.value == true), groupScope, aliasNoun)
        end
        return ('RegisterUnitBooleanSetting(unit, "%s", "%s", "%s", %s, MakeAliases(unit, "%s"), { category = "TODO" })')
            :format(key, key, label, tostring(gap.value == true), aliasNoun)
    elseif gap.valueType == "number" then
        local bounds, step = NumberStubBounds(gap.value)
        if isGroup then
            return ('RegisterGroupNumber("%s", "%s", "%s", "%s", %s, %s, %s, "visual", MakeAliases("%s", "%s"), { category = "TODO" })')
                :format(groupScope, key, key, label, tostring(gap.value), bounds, step, groupScope, aliasNoun)
        end
        return ('RegisterUnitNumberSetting(unit, "%s", "%s", "%s", %s, %s, MakeAliases(unit, "%s"), { category = "TODO", step = %s })')
            :format(key, key, label, tostring(gap.value), bounds, aliasNoun, step)
    end
    return ('-- TODO string setting "%s.%s" (current: %q) - register via the matching domain helper')
        :format(scope, key, tostring(gap.value))
end

-- ---------------------------------------------------------------------------
-- Copyable report window.
-- ---------------------------------------------------------------------------
local function EnsureWindow()
    if Audit.window then return Audit.window end
    local frame = CreateFrame("Frame", "MSUF_AssistantCoverageWindow", UIParent, "BackdropTemplate")
    frame:SetSize(680, 460)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local T = M.Theme
    local bg = T and T.colors and T.colors.bg or { 0.05, 0.05, 0.08, 0.97 }
    local border = T and T.colors and T.colors.border or { 0.2, 0.2, 0.3, 0.8 }
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.97)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 0.8)

    local title = T and T.Font and T.Font(frame, "GameFontNormal", "MSUF Assistant Coverage", T.colors and T.colors.text or nil)
        or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    if not (T and T.Font) then title:SetText("MSUF Assistant Coverage") end
    if T and T.StyleFontString then T.StyleFontString(title, T.colors and T.colors.text or { 1, 1, 1, 1 }, 1) end
    frame.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(_G.ChatFontNormal)
    if T and T.StyleFontString then T.StyleFontString(edit, T.colors and T.colors.text or { 1, 1, 1, 1 }, 0) end
    edit:SetWidth(620)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only: revert any typing so the report stays copy-safe.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self._msuf2ReportText then
            self:SetText(self._msuf2ReportText)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    frame.edit = edit

    local frameName = frame:GetName()
    if type(_G.UISpecialFrames) == "table" and frameName then
        _G.UISpecialFrames[#_G.UISpecialFrames + 1] = frameName
    end

    Audit.window = frame
    return frame
end

local function ShowReport(titleText, text)
    local frame = EnsureWindow()
    frame.title:SetText(titleText)
    frame.edit._msuf2ReportText = text
    frame.edit:SetText(text)
    frame.edit:HighlightText()
    frame:Show()
end

-- ---------------------------------------------------------------------------
-- Report rendering.
-- ---------------------------------------------------------------------------
local function AppendScopeReport(lines, result, withStubs)
    lines[#lines + 1] = ("== %s =="):format(result.scope)
    if not result.available then
        lines[#lines + 1] = "  (DB table missing - scope not seeded on this character)"
        lines[#lines + 1] = ""
        return
    end
    lines[#lines + 1] = ("  scalar keys: %d | covered: %d (%d%%) | gaps: %d | stale registry keys: %d | nested tables: %d")
        :format(result.total, result.coveredCount, Percent(result.coveredCount, result.total), #result.gaps, #result.stale, #result.nested)
    if #result.gaps > 0 then
        lines[#lines + 1] = "  gaps (DB key exists, assistant cannot reach it):"
        for i = 1, #result.gaps do
            local gap = result.gaps[i]
            if withStubs then
                lines[#lines + 1] = "    " .. StubForGap(result.scope, gap)
            else
                lines[#lines + 1] = ("    %s (%s, current: %s)"):format(gap.key, gap.valueType, tostring(gap.value))
            end
        end
    end
    if #result.stale > 0 then
        lines[#lines + 1] = "  stale (registry claims key, DB has none - legacy or custom get/set):"
        for i = 1, #result.stale do
            lines[#lines + 1] = "    " .. result.stale[i]
        end
    end
    if #result.nested > 0 then
        lines[#lines + 1] = "  nested tables (audited by their own domain, not this matrix): " .. table.concat(result.nested, ", ")
    end
    lines[#lines + 1] = ""
end

local function PrintSummary(results, settingCount, unmapped, generated)
    print(("|cffffd700MSUF Assistant Coverage|r (%d registry settings, %d generated fallbacks, %d outside this matrix)")
        :format(settingCount, generated or 0, unmapped))
    for i = 1, #results do
        local r = results[i]
        if r.available then
            local color = #r.gaps == 0 and "|cff40d060" or "|cffffb020"
            print(("  %s%s|r: %d/%d (%d%%) covered, %d gaps, %d stale")
                :format(color, r.scope, r.coveredCount, r.total, Percent(r.coveredCount, r.total), #r.gaps, #r.stale))
        else
            print("  |cff808080" .. r.scope .. "|r: DB table missing")
        end
    end
    print("  Details: /msufcoverage <scope|all> - Stubs: /msufcoverage stubs <scope> - Generated: /msufcoverage generated <scope|all> - Fallbacks: /msufcoverage fill - Manifest: /msufcoverage manifest - Smoke: /msufcoverage smoke - Gate: /msufcoverage gate")
end

local function AppendGeneratedReport(lines, scope, covered)
    local coveredSet = covered[scope] or {}
    local keys = {}
    for dbKey, setting in pairs(coveredSet) do
        if dbKey ~= "_norm" and type(setting) == "table" and setting.generated then
            keys[#keys + 1] = dbKey
        end
    end
    table.sort(keys)
    lines[#lines + 1] = ("[%s] generated fallbacks: %d"):format(scope, #keys)
    for i = 1, #keys do
        local dbKey = keys[i]
        local setting = coveredSet[dbKey]
        local aliases = type(setting.aliases) == "table" and table.concat(setting.aliases, ", ") or ""
        lines[#lines + 1] = ("  %s -> %s"):format(tostring(setting.key or dbKey), tostring(setting.label or dbKey))
        if aliases ~= "" then lines[#lines + 1] = "    aliases: " .. aliases end
    end
    lines[#lines + 1] = ""
end

local function BuildGeneratedReport(scopeArg)
    scopeArg = tostring(scopeArg or "all"):lower()
    if scopeArg == "party" or scopeArg == "raid" or scopeArg == "mythicraid" then scopeArg = "gf_" .. scopeArg end
    if scopeArg == "tot" then scopeArg = "targettarget" end
    local covered, settingCount, unmapped, generated = Audit.BuildCoveredSets()
    local lines = {
        ("MSUF Assistant Generated Fallbacks - %s"):format(date("%Y-%m-%d %H:%M:%S")),
        ("registry settings: %d (%d generated fallbacks, %d outside the scope matrix)")
            :format(settingCount or 0, generated or 0, unmapped or 0),
        "Use /msufcoverage stubs <scope> for gap stubs, then promote important generated keys to hand-written registrations.",
        "",
    }
    if scopeArg == "all" then
        local scopes = AllScopes()
        for i = 1, #scopes do AppendGeneratedReport(lines, scopes[i], covered) end
    elseif IsValidScope(scopeArg) then
        AppendGeneratedReport(lines, scopeArg, covered)
    else
        lines[#lines + 1] = "Unknown scope '" .. tostring(scopeArg or "") .. "'. Use player, target, focus, pet, boss, party, raid, mythicraid, bars, general, gameplay, or all."
    end
    return table.concat(lines, "\n")
end

local function SmokeCase(id, phase, setup, command, expect)
    return { id = id, phase = phase, setup = setup, command = command, expect = expect }
end

-- Human-only evidence that cannot be proven by the headless release suite.
-- Parser permutations stay in AssistantTraining; this list exercises the real
-- WoW loader, rendered controls, combat lifecycle, and visible multi-turn UI.
local ACCEPTANCE_SMOKE_CASES = {
    SmokeCase("runtime_core_load", "M5", "Reload UI, then open the MSUF Dashboard.",
        "/dump MSUF_NS.Assistant.IsRuntimeLoaded()",
        "True immediately after login (the runtime loads with the core addon); the Dashboard shows the normal chat card with no Start Assistant button and no load errors."),
    SmokeCase("interactive_read_only", "M5", "Open the MSUF Dashboard and submit ten normal read-only questions one at a time.",
        "Ask: what is target frame width; where is raid ready check; what depends on target buffs; why is player power text hidden; how do profiles work; explain class resource width mode; where can I change castbar texture; why are party frames missing; what are your limits; answer in German what is aura filtering.",
        "All ten answers remain correct and no setting changes."),
    SmokeCase("idle_assistant_shutdown", "M5", "After starting the Assistant once, close the MSUF menu, stay out of combat, and wait 10 seconds without reopening it.",
        "/dump MSUF_NS.Assistant._menuRuntimeActive, next(MSUF_NS.Assistant._menuRuntimeTimers or {})",
        "_menuRuntimeActive is false and no menu-runtime timers remain (next returns nil): the Assistant schedules no background work while the menu is closed."),
    SmokeCase("catalog_all_pages", "M1", "Visit every MSUF page/sub-tab once after starting the Assistant.",
        "/run local r=MSUF_NS.MSUF2.GetRuntimeControlCoverageReport(); print(r.total,r.byClassification.unknown,r.collisions,r.unstableIds)",
        "All rendered interactive controls have stable identities: unknown=0, collisions=0, unstableIds=0."),
    SmokeCase("graph_read_only", "M3", "Note the current Target Buffs state first.",
        "what depends on target buffs",
        "Lists downstream relationships and inspected state; Target Buffs and every other setting remain unchanged."),
    SmokeCase("graph_diagnose", "M3", "Disable Target Buffs, but keep the Target frame enabled.",
        "why is target buffs disabled",
        "Explains the current blocker/relationship without silently enabling anything."),
    SmokeCase("german_multiturn", "M4", "Start a fresh Assistant conversation.",
        "wie kann ich den spieler namen ausblenden; then: open it; then: warum",
        "All three answers stay German, open the correct page, and the informational turns do not change Player Name."),
    SmokeCase("explicit_english_switch", "M4", "Continue after the German multi-turn case.",
        "answer in English what are your limits",
        "The response switches to English and remains honest about local/offline MSUF scope."),
    SmokeCase("combat_zero_work", "M5", "Start a visible answer/typewriter, then enter combat immediately.",
        "Enter combat, wait five seconds, leave combat without reopening MSUF.",
        "Menu closes; no answer, history entry, timer animation, queue flush, or Assistant output occurs during/after combat."),
    SmokeCase("menu_reopen_resume", "M5", "Prepare one queued safe change, enter combat, then leave combat.",
        "Reopen the MSUF menu once after combat.",
        "Queued work resumes only on that explicit reopen, in FIFO order, and executes exactly once."),
    SmokeCase("atomic_undo_redo", "M0", "Record Player width/height and Target width first.",
        "set player width 300 height 45 and target width 250; then: undo; then: redo",
        "The batch applies atomically; undo restores all old values; redo reapplies all values."),
    SmokeCase("problem_report_safe", "M0", "Disable Target Buffs.",
        "my target buffs are missing; then: explain option 1; then: cancel",
        "Diagnosis and explanation are read-only; cancellation leaves Target Buffs disabled."),
    SmokeCase("profile_question_safe", "M0", "Use any non-default active profile.",
        "my profiles are broken; then: why; then: cancel",
        "Shows diagnostic evidence and a review choice without resetting, copying, switching, or overwriting a profile."),
    SmokeCase("control_action", "M1", "Open Dashboard > Display & Recovery.",
        "explain Copy Support Link; then: run it",
        "Explains the real button/action first, then runs that exact action after the explicit command."),
}

local function SmokeStore()
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return nil end
    gdb.assistantAcceptance = gdb.assistantAcceptance or {}
    local store = gdb.assistantAcceptance
    store.version = 3
    store.updated = date("%Y-%m-%d %H:%M:%S")
    store.cases = type(store.cases) == "table" and store.cases or {}
    return store
end

local function SmokeCaseById(id)
    id = tostring(id or "")
    for i = 1, #ACCEPTANCE_SMOKE_CASES do
        if ACCEPTANCE_SMOKE_CASES[i].id == id then return ACCEPTANCE_SMOKE_CASES[i] end
    end
    return nil
end

local function SmokeCounts(store)
    local counts = { pass = 0, fail = 0, block = 0, pending = 0 }
    store = type(store) == "table" and store or {}
    local cases = type(store.cases) == "table" and store.cases or {}
    for i = 1, #ACCEPTANCE_SMOKE_CASES do
        local status = tostring((cases[ACCEPTANCE_SMOKE_CASES[i].id] or {}).status or "pending")
        if status == "pass" then
            counts.pass = counts.pass + 1
        elseif status == "fail" then
            counts.fail = counts.fail + 1
        elseif status == "block" then
            counts.block = counts.block + 1
        else
            counts.pending = counts.pending + 1
        end
    end
    return counts
end

local function BuildSmokeReport()
    local store = SmokeStore() or {}
    local saved = type(store.cases) == "table" and store.cases or {}
    local counts = SmokeCounts(store)
    local lines = {
        ("MSUF Assistant In-game Acceptance Smoke - %s"):format(date("%Y-%m-%d %H:%M:%S")),
        ("status: %d pass, %d fail, %d blocked, %d pending"):format(counts.pass, counts.fail, counts.block, counts.pending),
        "Record results with:",
        "  /msufcoverage smoke pass <id>",
        "  /msufcoverage smoke fail <id> <note>",
        "  /msufcoverage smoke block <id> <note>",
        "  /msufcoverage smoke reset",
        "",
    }
    for i = 1, #ACCEPTANCE_SMOKE_CASES do
        local item = ACCEPTANCE_SMOKE_CASES[i]
        local record = saved[item.id] or {}
        lines[#lines + 1] = ("[%s] %s phase %s"):format(tostring(record.status or "pending"), item.id, item.phase)
        lines[#lines + 1] = "  setup: " .. item.setup
        lines[#lines + 1] = "  run: " .. item.command
        lines[#lines + 1] = "  expect: " .. item.expect
        if record.note and record.note ~= "" then lines[#lines + 1] = "  note: " .. tostring(record.note) end
        if record.time and record.time ~= "" then lines[#lines + 1] = "  recorded: " .. tostring(record.time) end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "SavedVariables: MSUF_GlobalDB.assistantAcceptance"
    return table.concat(lines, "\n")
end

local function SetSmokeStatus(status, id, note)
    local item = SmokeCaseById(id)
    if not item then
        print("|cffffd700MSUF:|r unknown smoke id '" .. tostring(id or "") .. "'. Run /msufcoverage smoke for the list.")
        return
    end
    local store = SmokeStore()
    if not store then
        print("|cffffd700MSUF:|r MSUF_GlobalDB is not available; cannot store smoke result.")
        return
    end
    store.cases[item.id] = {
        status = status,
        note = tostring(note or ""),
        time = date("%Y-%m-%d %H:%M:%S"),
    }
    local counts = SmokeCounts(store)
    print(("|cffffd700MSUF:|r smoke %s recorded for %s (%d pass, %d fail, %d blocked, %d pending).")
        :format(status, item.id, counts.pass, counts.fail, counts.block, counts.pending))
end

local function ResetSmokeStatus()
    local store = SmokeStore()
    if store then store.cases = {} end
    print("|cffffd700MSUF:|r smoke acceptance results reset.")
end

local function ShippedManifestCount()
    local manifest = A.AutoCoverageManifest
    local defaults = type(manifest) == "table" and manifest.defaults or nil
    if type(defaults) ~= "table" then return 0 end
    local total = 0
    for _, scopeTable in pairs(defaults) do
        if type(scopeTable) == "table" then
            for _, value in pairs(scopeTable) do
                local t = type(value)
                if t == "boolean" or t == "number" or t == "string" then total = total + 1 end
            end
        end
    end
    return total
end

local function BuildAcceptanceGate()
    -- The gate gathers its own coverage evidence; only smoke needs a human.
    local runResults, runSettings, runUnmapped, runGenerated = Audit.Run(nil)
    StoreSummary(runResults, runSettings, runUnmapped, runGenerated)
    local gdb = _G.MSUF_GlobalDB
    local smoke = type(gdb) == "table" and gdb.assistantAcceptance or nil
    local coverage = type(gdb) == "table" and gdb.assistantCoverage or nil
    local manifest = type(gdb) == "table" and gdb.assistantAutoCoverageManifest or nil
    local counts = SmokeCounts(smoke)
    local manifestText = type(manifest) == "table" and tostring(manifest.text or "") or ""
    local exportOk = type(manifest) == "table"
        and (tonumber(manifest.total) or 0) > 0
        and manifestText:find("Manifest.defaults", 1, true) ~= nil
    -- A shipped, populated Manifest.defaults counts as evidence too - the file
    -- can be generated offline without ever running the in-game export.
    local shippedCount = ShippedManifestCount()
    local manifestOk = exportOk or shippedCount > 0
    local coverageOk = type(coverage) == "table" and (tonumber(coverage.settings) or 0) > 0 and type(coverage.scopes) == "table"
    local catalog = type(M.GetRuntimeControlCoverageReport) == "function" and M.GetRuntimeControlCoverageReport() or nil
    local catalogOk = type(catalog) == "table" and (tonumber(catalog.total) or 0) > 0
        and catalog.catalogComplete == true and catalog.targetValidationAvailable == true
        and (tonumber(catalog.unresolvedTargetCount) or 0) == 0
    local graph, graphError
    if type(A.GetSettingDependencyGraphCoverageReport) == "function" then
        graph, graphError = A.GetSettingDependencyGraphCoverageReport()
    end
    local graphOk = type(graph) == "table" and (tonumber(graph.coveragePercent) or 0) >= 70
        and (tonumber(graph.specificCoveragePercent) or 0) >= 70
        and type(graph.unresolved) == "table" and #graph.unresolved == 0
    local smokeOk = counts.pass == #ACCEPTANCE_SMOKE_CASES and counts.fail == 0 and counts.block == 0 and counts.pending == 0
    local complete = smokeOk and manifestOk and coverageOk and catalogOk and graphOk
    local notes = {}
    if not smokeOk then
        notes[#notes + 1] = ("Smoke incomplete: %d pass, %d fail, %d blocked, %d pending. Record via /msufcoverage smoke pass|fail|block <id>."):format(counts.pass, counts.fail, counts.block, counts.pending)
    end
    if not manifestOk then
        notes[#notes + 1] = "Manifest missing: neither shipped Manifest.defaults nor an in-game export found. Run /msufcoverage manifest in a freshly seeded profile."
    end
    if not coverageOk then
        notes[#notes + 1] = "Coverage summary missing. Run /msufcoverage after /msufcoverage fill."
    end
    if not catalogOk then
        notes[#notes + 1] = "Runtime control catalog incomplete. Visit every page/sub-tab, then require unknown=0, collisions=0, unstableIds=0, target validation available, and unresolvedTargetCount=0."
    end
    if not graphOk then
        notes[#notes + 1] = "Setting relationship graph needs at least 70% overall and non-root-specific connected-setting coverage plus zero unresolved endpoints; open MSUF before running the gate. " .. tostring(graphError or "")
    end
    return {
        time = date("%Y-%m-%d %H:%M:%S"),
        complete = complete,
        smoke = {
            pass = counts.pass,
            fail = counts.fail,
            block = counts.block,
            pending = counts.pending,
            total = #ACCEPTANCE_SMOKE_CASES,
        },
        manifest = {
            available = manifestOk,
            shipped = shippedCount,
            total = math.max(shippedCount, type(manifest) == "table" and (tonumber(manifest.total) or 0) or 0),
            time = type(manifest) == "table" and manifest.time or nil,
        },
        coverage = {
            available = coverageOk,
            settings = type(coverage) == "table" and (tonumber(coverage.settings) or 0) or 0,
            generated = type(coverage) == "table" and (tonumber(coverage.generated) or 0) or 0,
            time = type(coverage) == "table" and coverage.time or nil,
        },
        controls = {
            available = catalogOk,
            total = type(catalog) == "table" and (tonumber(catalog.total) or 0) or 0,
            unknown = type(catalog) == "table" and (tonumber(catalog.byClassification and catalog.byClassification.unknown) or 0) or 0,
            collisions = type(catalog) == "table" and (tonumber(catalog.collisions) or 0) or 0,
            unstable = type(catalog) == "table" and (tonumber(catalog.unstableIds) or 0) or 0,
        },
        graph = {
            available = graphOk,
            settings = type(graph) == "table" and (tonumber(graph.settings) or 0) or 0,
            edges = type(graph) == "table" and (tonumber(graph.edges) or 0) or 0,
            coveragePercent = type(graph) == "table" and (tonumber(graph.coveragePercent) or 0) or 0,
        },
        notes = notes,
    }
end

local function StoreAcceptanceGate(gate)
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" or type(gate) ~= "table" then return end
    gdb.assistantAcceptanceGate = gate
end

local function BuildAcceptanceGateReport()
    local gate = BuildAcceptanceGate()
    StoreAcceptanceGate(gate)
    local lines = {
        ("MSUF Assistant Acceptance Gate - %s"):format(gate.time),
        gate.complete and "status: PASS" or "status: NOT COMPLETE",
        ("smoke: %d/%d pass, %d fail, %d blocked, %d pending")
            :format(gate.smoke.pass, gate.smoke.total, gate.smoke.fail, gate.smoke.block, gate.smoke.pending),
        ("manifest: %s (%d scalar default key(s), %d shipped%s)")
            :format(gate.manifest.available and "present" or "missing", gate.manifest.total, gate.manifest.shipped or 0, gate.manifest.time and (", " .. gate.manifest.time) or ""),
        ("coverage: %s (%d registry settings, %d generated fallback(s)%s)")
            :format(gate.coverage.available and "present" or "missing", gate.coverage.settings, gate.coverage.generated, gate.coverage.time and (", " .. gate.coverage.time) or ""),
        ("controls: %s (%d rendered, %d unknown, %d collisions, %d unstable)")
            :format(gate.controls.available and "complete" or "incomplete", gate.controls.total, gate.controls.unknown, gate.controls.collisions, gate.controls.unstable),
        ("relationships: %s (%d settings, %d edges, %.2f%% connected)")
            :format(gate.graph.available and "ready" or "incomplete", gate.graph.settings, gate.graph.edges, gate.graph.coveragePercent),
        "",
    }
    if #gate.notes > 0 then
        lines[#lines + 1] = "next required evidence:"
        for i = 1, #gate.notes do lines[#lines + 1] = "- " .. gate.notes[i] end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "SavedVariables: MSUF_GlobalDB.assistantAcceptanceGate"
    return table.concat(lines, "\n"), gate
end

Audit.AcceptanceSmokeCases = ACCEPTANCE_SMOKE_CASES
Audit.BuildSmokeReport = BuildSmokeReport
Audit.SetSmokeStatus = SetSmokeStatus
Audit.ResetSmokeStatus = ResetSmokeStatus
Audit.BuildAcceptanceGate = BuildAcceptanceGate
Audit.StoreAcceptanceGate = StoreAcceptanceGate
Audit.BuildAcceptanceGateReport = BuildAcceptanceGateReport
Audit.BuildGeneratedReport = BuildGeneratedReport

local function RunCommand(msg)
    local rawMsg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = rawMsg:lower()
    if msg == "gate" or msg == "acceptance gate" or msg == "status gate" then
        local text, gate = BuildAcceptanceGateReport()
        ShowReport("MSUF Assistant Acceptance Gate", text)
        print("|cffffd700MSUF:|r acceptance gate " .. (gate.complete and "PASS" or "not complete") .. ".")
        return
    end
    if msg == "smoke" or msg == "acceptance" or msg == "acceptance smoke" then
        ShowReport("MSUF Assistant Acceptance Smoke", BuildSmokeReport())
        return
    end
    if msg == "smoke reset" or msg == "acceptance reset" then
        ResetSmokeStatus()
        ShowReport("MSUF Assistant Acceptance Smoke", BuildSmokeReport())
        return
    end
    -- Lua patterns have no alternation; match the word and validate it.
    local smokeAction, smokeRest = msg:match("^smoke%s+(%S+)%s+(.+)$")
    if smokeAction and not (smokeAction == "pass" or smokeAction == "fail" or smokeAction == "block") then
        smokeAction, smokeRest = nil, nil
    end
    if smokeAction and smokeRest then
        local id, note = smokeRest:match("^(%S+)%s*(.*)$")
        local rawNote = rawMsg:match("^%S+%s+%S+%s+%S+%s*(.*)$") or note
        SetSmokeStatus(smokeAction, id, rawNote)
        ShowReport("MSUF Assistant Acceptance Smoke", BuildSmokeReport())
        return
    end
    if msg == "manifest" or msg == "dump manifest" then
        local Auto = A.AutoCoverage
        if Auto and type(Auto.BuildManifestText) == "function" then
            local text, total = Auto.BuildManifestText()
            if type(Auto.StoreManifestExport) == "function" then Auto.StoreManifestExport(text, total) end
            ShowReport("MSUF Assistant AutoCoverage Manifest", text)
            print(("|cffffd700MSUF:|r manifest export contains %d scalar default key(s) and was saved to SavedVariables."):format(total or 0))
        else
            print("|cffffd700MSUF:|r auto-coverage manifest exporter not loaded.")
        end
        return
    end
    local generatedScope = msg:match("^generated%s+(%S+)$")
    if msg == "generated" or generatedScope then
        local scopeArg = generatedScope or "all"
        if scopeArg == "party" or scopeArg == "raid" or scopeArg == "mythicraid" then scopeArg = "gf_" .. scopeArg end
        if scopeArg == "tot" then scopeArg = "targettarget" end
        if scopeArg ~= "all" and not IsValidScope(scopeArg) then
            print("|cffffd700MSUF:|r unknown scope '" .. scopeArg .. "'. Valid: " .. table.concat(AllScopes(), ", ") .. ", all")
            return
        end
        ShowReport("MSUF Assistant Coverage - Generated", BuildGeneratedReport(scopeArg))
        return
    end
    if msg == "fill" then
        local Auto = A.AutoCoverage
        if Auto and type(Auto.Fill) == "function" then
            local added = Auto.Fill()
            print(("|cffffd700MSUF:|r auto-coverage fill registered %d generated setting(s)."):format(added))
            local results, settingCount, unmapped, generated = Audit.Run(nil)
            StoreSummary(results, settingCount, unmapped, generated)
            PrintSummary(results, settingCount, unmapped, generated)
        else
            print("|cffffd700MSUF:|r auto-coverage module not loaded.")
        end
        return
    end
    local wantStubs = false
    local scopeArg = msg
    local stubsScope = msg:match("^stubs%s+(%S+)$")
    if stubsScope or msg == "stubs" then
        wantStubs = true
        scopeArg = stubsScope or "all"
    end
    if scopeArg == "party" or scopeArg == "raid" or scopeArg == "mythicraid" then scopeArg = "gf_" .. scopeArg end
    if scopeArg == "tot" then scopeArg = "targettarget" end

    if scopeArg == "" then
        local results, settingCount, unmapped, generated = Audit.Run(nil)
        StoreSummary(results, settingCount, unmapped, generated)
        PrintSummary(results, settingCount, unmapped, generated)
        return
    end

    local filter = nil
    if scopeArg ~= "all" then
        if not IsValidScope(scopeArg) then
            print("|cffffd700MSUF:|r unknown scope '" .. scopeArg .. "'. Valid: " .. table.concat(AllScopes(), ", ") .. ", all")
            return
        end
        filter = scopeArg
    end

    local results, settingCount, unmapped, generated = Audit.Run(filter)
    StoreSummary(Audit.Run(nil))
    local lines = {
        ("MSUF Assistant Coverage Report - %s"):format(date("%Y-%m-%d %H:%M:%S")),
        ("registry settings: %d (%d generated fallbacks, %d outside the scope matrix: colors, workflows, actions, aura lanes)")
            :format(settingCount, generated or 0, unmapped),
        "note: the DB stores only customized values (nil-preserving defaults). Keys never touched",
        "on this character do not appear here; 'stale' usually means untouched default or custom get/set path.",
        "",
    }
    for i = 1, #results do
        AppendScopeReport(lines, results[i], wantStubs)
    end
    ShowReport(wantStubs and "MSUF Assistant Coverage - Stubs" or "MSUF Assistant Coverage", table.concat(lines, "\n"))
end

_G.SLASH_MSUFCOVERAGE1 = "/msufcoverage"
if _G.SlashCmdList == nil then
    -- Headless smoke stubs only; never reassign the live global. Writing the
    -- SlashCmdList global from addon code taints it, and Blizzard's secure
    -- ImportListToHash(SlashCmdList, hash_SlashCmdList) then carries that taint
    -- into every protected slash handler (e.g. /pvp -> C_PvP.TogglePVP()).
    _G.SlashCmdList = {}
end
_G.SlashCmdList.MSUFCOVERAGE = RunCommand

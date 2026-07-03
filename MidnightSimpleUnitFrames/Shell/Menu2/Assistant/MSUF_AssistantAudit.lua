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
local GROUP_SCOPES = { "gf_party", "gf_raid", "gf_mythicraid" }
local FLAT_SCOPES = { "general", "bars", "gameplay" }

-- DB keys that are bookkeeping, not user-facing settings. Extend via
-- A.CoverageAudit.ignore[scope][key] = true (scope "*" applies everywhere).
Audit.ignore = Audit.ignore or {
    ["*"] = {
        version = true,
        migrated = true,
    },
}

local function IsIgnored(scope, key)
    if type(key) ~= "string" or key == "" then return true end
    if key:sub(1, 1) == "_" then return true end
    local star = Audit.ignore["*"]
    if star and star[key] then return true end
    local scoped = Audit.ignore[scope]
    return (scoped and scoped[key]) and true or false
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
    if prefix and IsValidScope(prefix) then
        out[#out + 1] = { scope = prefix, dbKey = rest }
    end
    local unit = setting.unit
    local attr = setting.attribute
    if type(unit) == "string" and type(attr) == "string" and attr ~= "" then
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
        local setting = settings[i]
        if type(setting) == "table" then
            if setting.generated then generated = generated + 1 end
            local targets = SettingScope(setting)
            if #targets == 0 then
                unmapped = unmapped + 1
            else
                for t = 1, #targets do
                    local target = targets[t]
                    covered[target.scope] = covered[target.scope] or {}
                    -- Keep the hand-written entry when both cover the same key
                    -- so stale classification can skip generated fallbacks.
                    local prev = covered[target.scope][target.dbKey]
                    if not prev or (prev.generated and not setting.generated) then
                        covered[target.scope][target.dbKey] = setting
                    end
                end
            end
        end
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
                if coveredSet[key] then
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
        if db[dbKey] == nil and not (type(setting) == "table" and setting.generated) then
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
    local label = key:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub("_", " ")
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("MSUF Assistant Coverage")
    frame.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(_G.ChatFontNormal)
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
        if type(setting) == "table" and setting.generated then
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

local ACCEPTANCE_SMOKE_CASES = {
    {
        id = "p0_1_relative_noop_nudge",
        phase = "0.1",
        setup = "Set Target of Target Name Text Anchor to RIGHT first.",
        command = "move target of target name more to the right",
        expect = "Changes Target of Target Name X Offset; does not answer Already set. Undo reverts it.",
    },
    {
        id = "p0_1_anchor_still_sets",
        phase = "0.1",
        setup = "Set Target of Target Name Text Anchor to anything except RIGHT first.",
        command = "move target of target name to the right",
        expect = "Sets the anchor enum to RIGHT; no relative nudge.",
    },
    {
        id = "p0_1_explicit_set_still_noop",
        phase = "0.1",
        setup = "Set Target Name Anchor to RIGHT first.",
        command = "set target name anchor to right",
        expect = "Answers Already set; no relative nudge.",
    },
    {
        id = "p0_1_frame_move_unchanged",
        phase = "0.1",
        setup = "No special setup.",
        command = "move target frame up",
        expect = "Changes Target Y Position through the existing frame-move path.",
    },
    {
        id = "p0_2_target_leader_continuation",
        phase = "0.2",
        setup = "Run: enable target leader icon.",
        command = "now move target leader up",
        expect = "Changes Target Leader / Assist Y Offset, not Target Y Position. Undo reverts it.",
    },
    {
        id = "p0_2_stale_hp_context_falls_through",
        phase = "0.2",
        setup = "Run: set target hp bar opacity to 80%.",
        command = "now move target leader up",
        expect = "Does not use HP opacity context; falls through to the normal parser behavior.",
    },
    {
        id = "p0_2_no_prior_turn",
        phase = "0.2",
        setup = "Reload UI or clear Assistant context/history first.",
        command = "move target frame up",
        expect = "Existing frame move behavior; no continuation context required.",
    },
    {
        id = "p1_2_target_name_context_score",
        phase = "1.2",
        setup = "Talk about Target Name Text first, for example set target name anchor to TOP.",
        command = "move target name up",
        expect = "Changes Target Name Y Offset, not Target Y Position.",
    },
    {
        id = "p1_3_ambiguous_ordinal",
        phase = "1.3",
        setup = "Trigger any Assistant ambiguity list with numbered choices.",
        command = "the second one",
        expect = "Resolves against the pending candidate list instead of doing a fresh broad parse.",
    },
    {
        id = "p2_2_generated_review",
        phase = "2b",
        setup = "Run /msufcoverage generated all.",
        command = "/msufcoverage generated all",
        expect = "Copyable generated-fallback report opens for alias curation.",
    },
    {
        id = "p2_3_manifest_dump",
        phase = "2c",
        setup = "Use a freshly seeded profile/character DB.",
        command = "/msufcoverage manifest",
        expect = "Copyable Manifest.defaults block opens and MSUF_GlobalDB.assistantAutoCoverageManifest.text is populated.",
    },
}

local function SmokeStore()
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return nil end
    gdb.assistantAcceptance = gdb.assistantAcceptance or {}
    local store = gdb.assistantAcceptance
    store.version = 1
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
    local smokeOk = counts.pass == #ACCEPTANCE_SMOKE_CASES and counts.fail == 0 and counts.block == 0 and counts.pending == 0
    local complete = smokeOk and manifestOk and coverageOk
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
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList.MSUFCOVERAGE = RunCommand

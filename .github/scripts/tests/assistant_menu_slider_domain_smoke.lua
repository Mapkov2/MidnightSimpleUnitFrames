-- The reviewed write domains in AutoCoverage must stay identical to the Menu2
-- sliders they were transcribed from.
--
-- Generated fallback numbers ship read-only because a default value proves
-- nothing about a control's range, and MSUF_Assistant.lua refuses to write an
-- unreviewed domain. For fields whose options page binds an explicit range,
-- that range is evidence rather than inference, so Auto.REVIEWED_MENU_DOMAINS
-- transcribes it and the promotion pass unblocks every scope of that field.
--
-- A transcription is only trustworthy while it still matches its source. This
-- re-reads the options page, re-extracts each binding, and fails if any entry
-- drifted, disappeared, or became ambiguous -- so the range the Assistant will
-- write can never silently diverge from the slider the player sees.
_G = _G or _ENV

local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local function Exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local function ReadSource(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a") or ""
    handle:close()
    -- The editor saves CRLF; normalize so patterns behave the same locally and
    -- in CI.
    return (text:gsub("\r\n", "\n"))
end

local PAGE_DIR = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2"

-- Every page that currently binds a reviewed field, so a control that moves
-- between pages is still found. Listed explicitly because this test may not
-- shell out to enumerate the directory.
local PAGE_FILES = {
    "Pages/MSUF_Menu2_GlobalBars.lua",
    "Pages/MSUF_Menu2_GroupBars.lua",
    "Pages/MSUF_Menu2_UnitStatusSection.lua",
    "Pages/MSUF_Menu2_UnitText.lua",
}
local sourceByFile, sources = {}, {}
for i = 1, #PAGE_FILES do
    local relative = PAGE_FILES[i]
    local text = ReadSource(PAGE_DIR .. "/" .. relative)
    Check(text ~= nil, "options page not readable: " .. relative)
    sourceByFile[relative] = text
    sources[#sources + 1] = text
end
local blob = table.concat(sources, "\n")

-- A shared placement slider drives whichever field the descriptor selects, so
-- its range is verified by locating the slider itself rather than a key.
-- Slider helpers differ in how many identifiers precede the label
-- (`W.Slider(parent, "L", …)` vs `ScopeNumberSlider(ctx, parent, "L", …)`) and
-- whether a step literal follows min/max (`BindStatusPlacementSlider(card, "L",
-- 0, 30, x, …)` has none). Every accepted shape is spelled out; an entry that
-- matches none of them fails rather than being assumed.
-- Some builders compute the label into a variable before constructing the
-- slider, so there is no literal to match on. Those entries name the enclosing
-- helper instead: the function must still exist and still build exactly one
-- slider, with the range the ledger claims.
local function EnclosingSliderDomain(relative, funcName)
    local text = sourceByFile[relative]
    if not text then return nil, "page not in the scanned set: " .. tostring(relative) end
    local escaped = tostring(funcName):gsub("(%W)", "%%%1")
    local start = text:find("function%s+" .. escaped .. "%s*%(")
    if not start then
        return nil, "helper '" .. tostring(funcName) .. "' no longer exists in " .. relative
    end
    -- Bound the search at the next top-level `local function`, so a later
    -- helper's slider cannot be mistaken for this one's.
    local stop = text:find("\n%s*local function ", start + 1) or #text
    local body = text:sub(start, stop)
    local found
    for min, max, step in body:gmatch("Slider%([^%)]-,%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*,%s*([%d%.]+)") do
        local domain = { min = tonumber(min), max = tonumber(max), step = tonumber(step) }
        if found then
            if found.min ~= domain.min or found.max ~= domain.max or found.step ~= domain.step then
                return nil, "'" .. tostring(funcName) .. "' builds more than one slider with different ranges in " .. relative
            end
        else
            found = domain
        end
    end
    if not found then
        return nil, "'" .. tostring(funcName) .. "' no longer builds a slider in " .. relative
    end
    return found
end

local function SharedSliderDomain(relative, label, expectedStep)
    local text = sourceByFile[relative]
    if not text then return nil, "page not in the scanned set: " .. tostring(relative) end
    local escaped = tostring(label):gsub("(%W)", "%%%1")
    local head = 'Slider%(%s*[%w_%.]+%s*,%s*"' .. escaped .. '"%s*,%s*'
    local headWithCtx = 'Slider%(%s*[%w_%.]+%s*,%s*[%w_%.]+%s*,%s*"' .. escaped .. '"%s*,%s*'
    local number = "(%-?[%d%.]+)%s*,%s*"
    local found
    local function note(min, max, step)
        local domain = { min = tonumber(min), max = tonumber(max), step = step }
        if found then
            if found.min ~= domain.min or found.max ~= domain.max or found.step ~= domain.step then
                return "'" .. tostring(label) .. "' is built more than once with different ranges in " .. relative
            end
        else
            found = domain
        end
    end
    for _, prefix in ipairs({ head, headWithCtx }) do
        for min, max, step in text:gmatch(prefix .. number .. number .. "([%d%.]+)") do
            local conflict = note(min, max, tonumber(step))
            if conflict then return nil, conflict end
        end
    end
    if not found then
        -- Stepless shape: the widget rounds to whole numbers, so the ledger
        -- supplies the step and only min/max are verified here.
        for _, prefix in ipairs({ head, headWithCtx }) do
            for min, max in text:gmatch(prefix .. number .. "(%-?[%d%.]+)%s*,") do
                local conflict = note(min, max, expectedStep)
                if conflict then return nil, conflict end
            end
        end
    end
    if not found then
        return nil, "no slider labelled '" .. tostring(label) .. "' remains in " .. relative
    end
    return found
end

-- BindSlider(parent, "label", min, max, step, "key", default, ...)
local BINDING_PATTERN =
    'BindSlider%(%s*[%w_%.]+%s*,%s*"[^"]*"%s*,%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*,%s*([%d%.]+)%s*,%s*"([^"]+)"'

local bindings = {}
for minText, maxText, stepText, key in blob:gmatch(BINDING_PATTERN) do
    local domain = { min = tonumber(minText), max = tonumber(maxText), step = tonumber(stepText) }
    local existing = bindings[key]
    if existing then
        if existing.min ~= domain.min or existing.max ~= domain.max or existing.step ~= domain.step then
            existing.ambiguous = true
        end
    else
        bindings[key] = domain
    end
end
local bindingCount = 0
for _ in pairs(bindings) do bindingCount = bindingCount + 1 end
Check(bindingCount > 0, "no slider bindings were extracted; the helper signature changed")

-- Load the Assistant runtime and compare the ledger against those bindings.
local MSUF = { MSUF2 = {}, Assistant = {} }
_G.MSUF_NS, _G.MSUF2 = MSUF, MSUF.MSUF2
local loader = root .. "/tools/assistant_runtime_manifest_loader.lua"
dofile(Exists(loader) and loader or (root .. "/../tools/assistant_runtime_manifest_loader.lua"))
local dashboard = root .. "/tools/assistant_dashboard_smoke.lua"
dofile(Exists(dashboard) and dashboard or (root .. "/../../tools/assistant_dashboard_smoke.lua"))
local A = _G.MSUF_NS.Assistant
if A.AutoCoverage and A.AutoCoverage.EnsureFilled then pcall(A.AutoCoverage.EnsureFilled) end

local ledger = A.AutoCoverage and A.AutoCoverage.ReviewedMenuDomains
Check(type(ledger) == "table", "the reviewed menu-domain ledger must be exported")

local ledgerCount = 0
for leaf, reviewed in pairs(ledger) do
    ledgerCount = ledgerCount + 1
    local bound, shareError
    if type(reviewed.sharedSlider) == "table" and reviewed.sharedSlider.enclosing then
        bound, shareError = EnclosingSliderDomain(reviewed.sharedSlider.file,
            reviewed.sharedSlider.enclosing)
        Check(bound ~= nil, leaf .. ": " .. tostring(shareError))
    elseif type(reviewed.sharedSlider) == "table" then
        bound, shareError = SharedSliderDomain(reviewed.sharedSlider.file,
            reviewed.sharedSlider.label, reviewed.step)
        Check(bound ~= nil, leaf .. ": " .. tostring(shareError))
    else
        bound = bindings[leaf]
        Check(bound ~= nil,
            leaf .. " is in the reviewed ledger but no options slider binds it any more")
        Check(not bound.ambiguous,
            leaf .. " is bound by more than one slider with different ranges; it must not carry a"
            .. " single reviewed domain")
    end
    Check(reviewed.min == bound.min,
        leaf .. " min drifted: ledger " .. tostring(reviewed.min) .. ", menu " .. tostring(bound.min))
    Check(reviewed.max == bound.max,
        leaf .. " max drifted: ledger " .. tostring(reviewed.max) .. ", menu " .. tostring(bound.max))
    Check(reviewed.step == bound.step,
        leaf .. " step drifted: ledger " .. tostring(reviewed.step) .. ", menu " .. tostring(bound.step))
    Check(reviewed.min < reviewed.max, leaf .. " must describe a non-empty range")
end
Check(ledgerCount > 0, "the reviewed ledger must not be empty")

-- The ledger has to actually reach the generated settings, in every scope.
local promoted, byLeaf = 0, {}
for _, setting in ipairs(A.Registry:AllSettings()) do
    if type(setting) == "table" and setting.generatedMutationSafety == "reviewed-menu-domain" then
        promoted = promoted + 1
        local leaf = tostring(setting.key):match("([^.]+)$") or ""
        byLeaf[leaf] = (byLeaf[leaf] or 0) + 1
        local reviewed = ledger[leaf]
        Check(reviewed ~= nil, setting.key .. " claims a reviewed domain with no ledger entry")
        Check(setting.assistantMutationSafe == true, setting.key .. " must be writable")
        Check(setting.min == reviewed.min and setting.max == reviewed.max,
            setting.key .. " did not inherit the reviewed range")
        Check(setting.unsafeMutationReason == nil,
            setting.key .. " must not keep an unsafe-mutation reason once promoted")
        -- A 0..1 range is the fraction form the menu presents as a percentage.
        local expectPercent = reviewed.max <= 1
        Check((setting.percent == true) == expectPercent,
            setting.key .. " percent flag must follow its range")
    end
end
Check(promoted > 0, "the reviewed ledger promoted nothing")
for leaf in pairs(ledger) do
    Check((byLeaf[leaf] or 0) > 0,
        leaf .. " is reviewed but reached no generated setting; the field or its scopes moved")
end

-- A promoted control must survive the real write path, clamped to its range.
local sample = A.Registry:GetSetting("focus.absorbBarHeight")
Check(type(sample) == "table" and sample.assistantMutationSafe == true,
    "focus.absorbBarHeight must be writable through the reviewed ledger")
sample.set(6)
Check(tonumber(sample.get()) == 6, "a reviewed-domain write must round-trip")
sample.set(9999)
Check(tonumber(sample.get()) == sample.max, "a reviewed-domain write must clamp to max")
sample.set(-9999)
Check(tonumber(sample.get()) == sample.min, "a reviewed-domain write must clamp to min")

-- No color channel may ever be promoted by this route.
for _, setting in ipairs(A.Registry:AllSettings()) do
    if type(setting) == "table" and setting.assistantColorChannel == true then
        Check(setting.generatedMutationSafety ~= "reviewed-menu-domain",
            tostring(setting.key) .. ": a color channel must never gain a reviewed write domain")
    end
end

print("assistant_menu_slider_domain_smoke: PASS (" .. tostring(ledgerCount)
    .. " reviewed leaves, " .. tostring(promoted) .. " settings unblocked)")

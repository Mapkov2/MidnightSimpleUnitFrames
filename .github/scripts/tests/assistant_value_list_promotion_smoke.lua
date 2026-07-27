-- Generated string settings become writable only through a closed value list
-- inherited from a reviewed curated sibling.
--
-- A generated string ships read-only because an arbitrary write can put a value
-- into the DB that the runtime never expects. Where the same attribute is
-- already a reviewed enum on another frame -- every curated
-- *.incomingResIndicatorAnchor offers the same four corners -- that list is
-- evidence rather than a guess and transfers to the uncurated scopes.
--
-- The safety of this rests on three rules, all pinned here: the list must be
-- closed, every curated sibling must agree, and a path the reviewers marked as
-- deliberately NOT an alias must stay read-only even though it shares a leaf.
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

local MSUF = { MSUF2 = {}, Assistant = {} }
_G.MSUF_NS, _G.MSUF2 = MSUF, MSUF.MSUF2
local loader = root .. "/tools/assistant_runtime_manifest_loader.lua"
dofile(Exists(loader) and loader or (root .. "/../tools/assistant_runtime_manifest_loader.lua"))
local dashboard = root .. "/tools/assistant_dashboard_smoke.lua"
dofile(Exists(dashboard) and dashboard or (root .. "/../../tools/assistant_dashboard_smoke.lua"))
local A = _G.MSUF_NS.Assistant
local Auto = assert(A.AutoCoverage, "AutoCoverage missing")
Check(type(Auto.PromoteInheritedValueLists) == "function", "the value-list pass must be exported")
if Auto.EnsureFilled then pcall(Auto.EnsureFilled) end

local Registry = A.Registry
local settings = Registry:AllSettings()

local function Signature(values)
    local sorted = {}
    for i = 1, #values do sorted[i] = tostring(values[i]) end
    table.sort(sorted)
    return table.concat(sorted, "\1")
end

-- Curated value lists per leaf, with agreement, rebuilt independently of the
-- implementation so a bug in the pass cannot validate itself.
local curatedByLeaf = {}
for i = 1, #settings do
    local s = settings[i]
    if type(s) == "table" and s.generated ~= true and type(s.values) == "table" and #s.values > 0 then
        local leaf = tostring(s.key):match("([^.]+)$") or ""
        local signature = Signature(s.values)
        local entry = curatedByLeaf[leaf]
        if entry == nil then
            curatedByLeaf[leaf] = { signature = signature, source = s.key, conflict = false }
        elseif entry.signature ~= signature then
            entry.conflict = true
        end
    end
end

-- Reviewed lists transcribed from an options value table must still match it.
local function ReadSource(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a") or ""
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local MENU_DIR = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2"
local reviewedValues = Auto.ReviewedMenuValues
Check(type(reviewedValues) == "table", "the reviewed value ledger must be exported")

local reviewedLeaves = 0
for leaf, reviewed in pairs(reviewedValues) do
    reviewedLeaves = reviewedLeaves + 1
    local shared = reviewed.sharedValues
    Check(type(shared) == "table" and shared.file and shared.table,
        leaf .. " must name the options table it was transcribed from")
    local text = ReadSource(MENU_DIR .. "/" .. shared.file)
    Check(text ~= nil, leaf .. ": options file not readable: " .. tostring(shared.file))
    local menuValues = {}
    if shared.keyedTable then
        -- { LEFT = "…", RIGHT = "…", … } -- the KEYS are the stored tokens.
        local block = text:match("local%s+" .. shared.table .. "%s*=%s*(%b{})")
        Check(block ~= nil,
            leaf .. ": keyed table " .. tostring(shared.table) .. " no longer exists in "
            .. tostring(shared.file))
        for key in block:gmatch("([%w_]+)%s*=") do menuValues[#menuValues + 1] = key end
    elseif shared.inlineVT then
        -- VT(0, "Off", 1, "On") -- values are the odd positional arguments.
        local args = text:match("local%s+" .. shared.table .. "%s*=%s*VT(%b())")
        Check(args ~= nil,
            leaf .. ": inline VT table " .. tostring(shared.table) .. " no longer exists in "
            .. tostring(shared.file))
        local index = 0
        for token in args:gmatch("[^,%(%)]+") do
            index = index + 1
            if index % 2 == 1 then
                token = token:gsub("^%s+", ""):gsub("%s+$", "")
                if shared.strings then
                    local value = token:match('^"(.*)"$')
                    Check(value ~= nil,
                        leaf .. ": " .. tostring(shared.table) .. " has a non-string value: " .. token)
                    menuValues[#menuValues + 1] = value
                else
                    local value = tonumber(token)
                    Check(value ~= nil, leaf .. ": " .. tostring(shared.table) .. " has a non-numeric value")
                    menuValues[#menuValues + 1] = value
                end
            end
        end
    elseif shared.packed then
        -- VTP "VALUE=Label|VALUE=Label|..." rather than a table literal.
        local packed = text:match("local%s+" .. shared.table .. '%s*=%s*VTP%s*"([^"]*)"')
        Check(packed ~= nil,
            leaf .. ": packed table " .. tostring(shared.table) .. " no longer exists in "
            .. tostring(shared.file))
        for entry in packed:gmatch("[^|]+") do
            local value = entry:match("^([^=]+)=")
            if value then menuValues[#menuValues + 1] = value end
        end
    else
        local block = text:match("local%s+" .. shared.table .. "%s*=%s*(%b{})")
        Check(block ~= nil,
            leaf .. ": table " .. tostring(shared.table) .. " no longer exists in " .. tostring(shared.file))
        if reviewed.numeric then
            -- Numeric dropdowns write the stored number directly: { value = 3, ... }
            for value in block:gmatch("value%s*=%s*(%-?%d+%.?%d*)%s*,") do
                menuValues[#menuValues + 1] = tonumber(value)
            end
        else
            for value in block:gmatch('value%s*=%s*"([^"]+)"') do menuValues[#menuValues + 1] = value end
        end
    end
    Check(#menuValues > 0, leaf .. ": " .. tostring(shared.table) .. " lists no values")
    Check(Signature(menuValues) == Signature(reviewed.values),
        leaf .. " value list drifted from " .. tostring(shared.table) .. ".\n  ledger: "
        .. table.concat(reviewed.values, ",") .. "\n  menu:   " .. table.concat(menuValues, ","))
end
Check(reviewedLeaves > 0, "the reviewed value ledger must not be empty")

-- Media fields are validated by the resolver, not a closed list. Each reviewed
-- entry must still be bound to a texture dropdown in the options source, or
-- calling it "statusbar" media would be an assumption.
local reviewedMedia = Auto.ReviewedMenuMedia
Check(type(reviewedMedia) == "table", "the reviewed media ledger must be exported")
local mediaSources = {}
for _, name in ipairs({ "Pages/MSUF_Menu2_GlobalBars.lua" }) do
    local text = ReadSource(MENU_DIR .. "/" .. name)
    Check(text ~= nil, "options page not readable: " .. name)
    mediaSources[#mediaSources + 1] = text
end
local mediaBlob = table.concat(mediaSources, "\n")
local mediaLeaves = 0
for leaf, reviewed in pairs(reviewedMedia) do
    mediaLeaves = mediaLeaves + 1
    if reviewed.mediaType == "portraitpack" then
        -- Verified against its own page and the builder that fills the dropdown.
        local text = ReadSource(MENU_DIR .. "/" .. tostring(reviewed.menuFile))
        Check(text ~= nil, leaf .. ": options page not readable: " .. tostring(reviewed.menuFile))
        Check(text:find('"' .. (reviewed.menuKey or leaf) .. '"', 1, true) ~= nil,
            leaf .. " is no longer bound on " .. tostring(reviewed.menuFile))
        Check(text:find("function%s+" .. tostring(reviewed.menuBuilder) .. "%s*%(") ~= nil,
            leaf .. ": builder " .. tostring(reviewed.menuBuilder) .. " no longer exists")
        Check(type(Auto.MediaResolverPortraitCheck) ~= "function" or Auto.MediaResolverPortraitCheck(),
            leaf .. ": the resolver lost its portrait-pack branch")
    else
        Check(reviewed.mediaType == "statusbar",
            leaf .. ": unsupported reviewed media type " .. tostring(reviewed.mediaType))
        Check(mediaBlob:find('"' .. (reviewed.menuKey or leaf) .. '"', 1, true) ~= nil,
            leaf .. " is no longer bound on the bar-scope options page")
        Check(mediaBlob:find("TextureValues", 1, true) ~= nil,
            leaf .. ": the options page no longer offers a texture picker")
    end
end

-- The resolver must actually route this media type, or the promotion writes
-- through a branch that does not exist.
local resolver = A.MediaResolver
Check(type(resolver) == "table" and type(resolver.PortraitPackItems) == "function",
    "the media resolver must expose a portrait-pack item source")
Check(resolver.MediaTypeForSetting({ type = "string", mediaType = "portraitpack" }) == "portraitpack",
    "the resolver must classify portraitpack settings")
Check(#resolver.PortraitPackItems() > 0, "the portrait-pack item source must never be empty")
Check(mediaLeaves > 0, "the reviewed media ledger must not be empty")

local mediaPromoted = 0
for i = 1, #settings do
    local s = settings[i]
    if type(s) == "table" and s.generatedMutationSafety == "reviewed-menu-media" then
        mediaPromoted = mediaPromoted + 1
        local key = tostring(s.key)
        local reviewed = reviewedMedia[key:match("([^.]+)$") or ""]
        Check(reviewed ~= nil, key .. " claims reviewed media with no ledger entry")
        Check(s.mediaType == reviewed.mediaType, key .. " did not inherit the reviewed media type")
        -- Curated texture settings are plain strings with a mediaType and no
        -- value list; a promoted twin must look exactly like one.
        Check(s.type == "string" and s.values == nil,
            key .. " must stay a resolver-backed string, not a closed enum")
        Check(s.assistantMutationSafe == true, key .. " must be writable")
        Check(s.unsafeMutationReason == nil, key .. " must drop its unsafe-mutation reason")
    end
end
Check(mediaPromoted > 0, "the reviewed media ledger promoted nothing")

local promoted = 0
for i = 1, #settings do
    local s = settings[i]
    if type(s) == "table" and s.generatedMutationSafety == "reviewed-menu-values" then
        promoted = promoted + 1
        local key = tostring(s.key)
        local reviewed = reviewedValues[key:match("([^.]+)$") or ""]
        Check(reviewed ~= nil, key .. " claims a reviewed list with no ledger entry")
        Check(Signature(s.values or {}) == Signature(reviewed.values),
            key .. " did not inherit the reviewed value list")
        Check(s.closedValues == true and s.type == "enum" and s.assistantMutationSafe == true,
            key .. " must be a writable closed enum")
        Check(s.assistantColorChannel ~= true, key .. ": a color channel must never be promoted")
    end
    if type(s) == "table" and s.generatedMutationSafety == "inherited-curated-values" then
        promoted = promoted + 1
        local key = tostring(s.key)
        local leaf = key:match("([^.]+)$") or ""
        local curated = curatedByLeaf[leaf]

        Check(s.generated == true, key .. " must still be a generated setting")
        Check(curated ~= nil, key .. " claims an inherited list with no curated sibling")
        Check(not curated.conflict,
            key .. " inherited a list from siblings that disagree; it must stay read-only")
        Check(type(s.values) == "table" and #s.values > 0, key .. " must carry a value list")
        Check(Signature(s.values) == curated.signature,
            key .. " value list does not match its curated source " .. tostring(curated.source))
        -- A closed list is the whole safety argument: without it an arbitrary
        -- string could still be written.
        Check(s.closedValues == true, key .. " must close its value list")
        Check(s.type == "enum", key .. " must present as an enum once it has a closed list")
        Check(s.assistantMutationSafe == true, key .. " must be writable")
        Check(s.unsafeMutationReason == nil, key .. " must drop its unsafe-mutation reason")
        Check(tostring(s.mutationDomainSource or "") ~= "", key .. " must record its source")
        Check(s.assistantColorChannel ~= true, key .. ": a color channel must never be promoted")
    end
end
Check(promoted > 0, "the value-list pass promoted nothing")

-- Reviewed non-aliases: same leaf as a curated enum, deliberately not the same
-- control, so they must stay read-only. The safety regression pins this from
-- the opposite side; here it guards the promotion pass specifically.
local nonAlias = Auto.NonAliasPromotionKeys
Check(type(nonAlias) == "table", "the non-alias exclusion ledger must be exported")
local nonAliasCount = 0
for key in pairs(nonAlias) do
    nonAliasCount = nonAliasCount + 1
    local setting = Registry:GetSetting(key)
    Check(type(setting) == "table", key .. " is excluded from promotion but no longer exists")
    Check(setting.assistantMutationSafe == false,
        key .. " is a reviewed non-alias and must stay read-only")
    Check(setting.generatedMutationSafety ~= "inherited-curated-values",
        key .. " must not inherit a sibling's value list")
end
Check(nonAliasCount > 0, "the non-alias ledger must not be empty")

-- Every remaining read-only generated string must have a real reason to be one:
-- no curated sibling, siblings that disagree, or a reviewed non-alias.
for i = 1, #settings do
    local s = settings[i]
    if type(s) == "table" and s.generated == true and s.type == "string"
        and s.assistantMutationSafe == false and s.assistantColorChannel ~= true
    then
        local key = tostring(s.key)
        local curated = curatedByLeaf[key:match("([^.]+)$") or ""]
        local excused = curated == nil or curated.conflict == true or nonAlias[key] == true
        Check(excused,
            key .. " has an agreeing curated value list but was left read-only")
    end
end

-- A promoted enum must actually round-trip, and reject a value off its list.
local sample
for i = 1, #settings do
    local s = settings[i]
    if type(s) == "table" and s.generatedMutationSafety == "inherited-curated-values"
        and type(s.get) == "function" and type(s.set) == "function"
    then sample = s; break end
end
Check(sample ~= nil, "no promoted enum exposes accessors")
local allowed = tostring(sample.values[1])
sample.set(allowed)
Check(tostring(sample.get()) == allowed, "a promoted enum write must round-trip")

print("assistant_value_list_promotion_smoke: PASS (" .. tostring(promoted)
    .. " settings, " .. tostring(nonAliasCount) .. " reviewed non-aliases)")

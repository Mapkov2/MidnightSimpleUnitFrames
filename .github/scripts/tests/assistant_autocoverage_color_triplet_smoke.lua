-- Generated color channels must be recognised from evidence, not vocabulary.
--
-- AutoCoverage used to decide "is this DB key one channel of a color?" from a
-- fixed list of stem words. Every real color whose name happened to miss those
-- words (castbarText, unifiedBar, playerCastbarOverride, classPowerRampStart,
-- the group fontR/G/B, and the whole targetedSpellsText* family) was therefore
-- published as an independent unbounded number and answered a color request
-- with a generic "no reviewed min/max" refusal instead of pointing at the color
-- picker.
--
-- The reviewed rule is now: a stem counts as a color when the manifest carries
-- its complete R+G+B sibling set in the same scope. This pins that rule, the
-- surviving word-list fallback, and the two invariants that make a channel
-- safe: a channel is never writable, and never inherits a curated domain.
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

-- Part A: the word-list fallback still classifies keys the manifest never saw.
-- Loaded standalone so no triplet index exists yet and only the fallback runs.
do
    local MSUF = { MSUF2 = {}, Assistant = {} }
    _G.MSUF_NS, _G.MSUF2 = MSUF, MSUF.MSUF2
    MSUF.Assistant.Registry = { byKey = {}, AllSettings = function() return {} end,
        GetSetting = function() return nil end }
    local chunk = assert(loadfile(root
        .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_AutoCoverage.lua"))
    chunk("MidnightSimpleUnitFrames", MSUF)
    local IsChannel = MSUF.Assistant.AutoCoverage.IsColorChannelKey
    Check(type(IsChannel) == "function", "IsColorChannelKey must stay exported")

    Check(IsChannel("aggroBorderR") == "R", "a stem-word color must still be detected")
    Check(IsChannel("healAbsorbBarColorA") == "A", "the alpha channel must still be detected")
    -- No triplet index and no stem word: unknown until the manifest proves it.
    Check(IsChannel("castbarTextR") == nil, "an unproven stem must not be guessed from nothing")
    -- A trailing capital that is not a channel suffix.
    Check(IsChannel("showHP") == nil, "a word ending in a capital is not a channel")
    Check(IsChannel("barWidth") == nil, "a key without a channel suffix is not a channel")
    -- An explicit scope with no learned stems must not error.
    Check(IsChannel("castbarTextR", "general") == nil, "an unknown scope must fall back safely")
end

-- Part B: the real registry, after a full manifest-backed fill.
do
    local realMSUF = { MSUF2 = {}, Assistant = {} }
    _G.MSUF_NS, _G.MSUF2 = realMSUF, realMSUF.MSUF2
    local loader = root .. "/tools/assistant_runtime_manifest_loader.lua"
    dofile(Exists(loader) and loader or (root .. "/../tools/assistant_runtime_manifest_loader.lua"))
    local dashboard = root .. "/tools/assistant_dashboard_smoke.lua"
    dofile(Exists(dashboard) and dashboard or (root .. "/../../tools/assistant_dashboard_smoke.lua"))
    local A = _G.MSUF_NS.Assistant
    if A.AutoCoverage and A.AutoCoverage.EnsureFilled then pcall(A.AutoCoverage.EnsureFilled) end
    local settings = A.Registry:AllSettings()

    -- Index every generated number so sibling sets can be reconstructed.
    local byScopeStem, channels = {}, 0
    for i = 1, #settings do
        local s = settings[i]
        if type(s) == "table" and s.generated == true and s.type == "number" then
            if s.assistantColorChannel == true then channels = channels + 1 end
            local scope, leaf = tostring(s.key):match("^([^.]+)%.(.+)$")
            local suffix = leaf and leaf:match("([RGB])$")
            if scope and suffix and leaf:sub(-2, -2):match("[%l%d]") then
                local stem = leaf:sub(1, #leaf - 1)
                local bucket = byScopeStem[scope .. "\1" .. stem]
                if not bucket then bucket = {}; byScopeStem[scope .. "\1" .. stem] = bucket end
                bucket[suffix] = s
            end
        end
    end
    Check(channels > 0, "the real registry must classify some generated color channels")

    -- THE regression: a complete R+G+B sibling set is a color, always.
    local unflagged = {}
    for id, bucket in pairs(byScopeStem) do
        if bucket.R and bucket.G and bucket.B then
            for _, suffix in ipairs({ "R", "G", "B" }) do
                if bucket[suffix].assistantColorChannel ~= true then
                    unflagged[#unflagged + 1] = tostring(bucket[suffix].key)
                end
            end
        end
        local _ = id
    end
    table.sort(unflagged)
    Check(#unflagged == 0,
        "every proven R+G+B triplet must be flagged as a color channel; unflagged: "
        .. table.concat(unflagged, ", "))

    -- The exact families the word list used to miss. Named so a future rewrite
    -- of the detection cannot quietly drop them again.
    for _, key in ipairs({
        "general.castbarTextR",
        "general.unifiedBarG",
        "general.playerCastbarOverrideB",
        "bars.classPowerRampStartR",
        "bars.classPowerRampEndB",
        "gf_party.fontR",
        "gf_raid.fontG",
        "gf_party.targetedSpellsTextUrgentR",
        "gf_raid.targetedSpellsTextSafeG",
        "gf_mythicraid.targetedSpellsTextWarningB",
    }) do
        local s = A.Registry:GetSetting(key)
        Check(type(s) == "table", key .. " must still exist as a generated setting")
        Check(s.assistantColorChannel == true, key .. " must be classified as a color channel")
        Check(s.assistantMutationSafe == false, key .. " must stay read-only")
        Check(s.generatedMutationSafety == "color-channel-component",
            key .. " must carry the color-channel safety tag")
        Check(tostring(s.unsafeMutationReason or ""):find("whole color", 1, true) ~= nil,
            key .. " must point at the whole-color path")
        -- The example in that message has to be typeable English, not a raw
        -- scope token like "gf_party".
        Check(tostring(s.unsafeMutationReason or ""):find("gf_", 1, true) == nil,
            key .. " must not print a raw scope token in its example")
    end

    -- Invariants: a channel is never writable and never inherits a domain.
    local writable, promotedChannel = {}, {}
    for i = 1, #settings do
        local s = settings[i]
        if type(s) == "table" and s.assistantColorChannel == true then
            if s.assistantMutationSafe ~= false then writable[#writable + 1] = tostring(s.key) end
            if s.generatedMutationSafety == "inherited-curated-domain" then
                promotedChannel[#promotedChannel + 1] = tostring(s.key)
            end
        end
    end
    Check(#writable == 0, "no color channel may be writable: " .. table.concat(writable, ", "))
    Check(#promotedChannel == 0,
        "no color channel may inherit a curated domain: " .. table.concat(promotedChannel, ", "))

    io.write("real registry color channels = " .. tostring(channels) .. "\n")
end

print("assistant_autocoverage_color_triplet_smoke: PASS")

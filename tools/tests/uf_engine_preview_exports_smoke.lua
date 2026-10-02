-- uf_engine_preview_exports_smoke.lua <repoRoot> <flavor>
--
-- The menu previews used to carry their own copies of three engine rules:
-- name shortening, the dark-mode bar color and the class resource pip
-- auto-fit width. The engine now exports each rule so a preview can call it:
--   UF.Config.ResolveNameShortening(db, general, conf, unit, out)
--   UF.Config.ResolveDarkColor(general, out)
--   UF.Shared.ClassPowerAutoFitWidth(count, slot, gap, snap, region)
-- This smoke boots the flavor's real load graph and pins that each export
-- produces exactly what the engine itself compiles: the spec text fields of
-- every compiled unit, the settings cache's dark bar color, and the
-- ClassPower layout's auto_pips formula (count * slot + (count - 1) * gap,
-- slot at least 1, gap 0..8, both snapped when a snap function is given).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": "
    .. tostring(failure and failure.message))
local env = world.env
local UF = world.core.UF
local Config, Shared = UF.Config, UF.Shared
Check(type(Config.ResolveNameShortening) == "function", "UF.Config.ResolveNameShortening is not exported")
Check(type(Config.ResolveDarkColor) == "function", "UF.Config.ResolveDarkColor is not exported")
Check(type(Shared.ClassPowerAutoFitWidth) == "function", "UF.Shared.ClassPowerAutoFitWidth is not exported")

-- The compiler's own DB (profile bootstrap may replace the global table once).
Config.Refresh()
local db = Config.GetDB()
local general = db.general

local SHORTEN_FIELDS = { "nameShorten", "nameShortenMax", "nameShortenSide", "nameShortenDots", "nameShortenMaskPx" }
local function CheckNameShortening(label)
    Config.Refresh()
    local checked = 0
    for unit, spec in pairs(Config.specs) do
        local key = UF.ConfigKeyForUnit(unit)
        local conf = db[key]
        if spec.text and conf then
            local out = {}
            Config.ResolveNameShortening(db, general, conf, unit, out)
            for _, field in ipairs(SHORTEN_FIELDS) do
                Check(out[field] == spec.text[field], string.format("%s: %s.%s is %s, the spec has %s",
                    label, unit, field, tostring(out[field]), tostring(spec.text[field])))
            end
            checked = checked + 1
        end
    end
    Check(checked > 0, label .. ": no compiled unit spec to compare")
    return checked
end

local function CheckDarkColor(label)
    Config.Refresh()
    local cache = Config.GetSettingsCache()
    local out = {}
    Config.ResolveDarkColor(general, out)
    Check(out.r == cache.darkBarR and out.g == cache.darkBarG and out.b == cache.darkBarB and out.a == 1,
        string.format("%s: dark color %s/%s/%s, the settings cache has %s/%s/%s", label,
            tostring(out.r), tostring(out.g), tostring(out.b),
            tostring(cache.darkBarR), tostring(cache.darkBarG), tostring(cache.darkBarB)))
end

local units = CheckNameShortening("factory")
CheckDarkColor("factory")
db.shortenNames = true
general.shortenNameMaxChars = 55
general.shortenNameClipSide = "right"
general.shortenNameFrontMaskPx = -3
general.shortenNameShowDots = false
db.target = db.target or {}
db.target.fontOverride = true
db.target.nameShortenEnabled = false
db.target.nameMaxChars = 2
db.target.nameNoEllipsis = true
CheckNameShortening("customized")
general.darkBarGray = 35
CheckDarkColor("gray percent")
general.darkBarR, general.darkBarG, general.darkBarB = 0.2, 0.3, 0.4
CheckDarkColor("custom dark color")

local AutoFit = Shared.ClassPowerAutoFitWidth
Check(AutoFit(5, 12, 2) == 68, "5 pips of 12 px with 2 px gaps are not 68 px")
Check(AutoFit(3, 0, 20) == 3 * 1 + 2 * 8, "slot is not clamped to 1 and gap to 8")
Check(AutoFit(4, 10, -4) == 40, "a negative gap is not clamped to 0")
local snapped = {}
local function Snap(region, value)
    snapped[#snapped + 1] = { region, value }
    return value + 0.5
end
local region = {}
Check(AutoFit(2, 10, 3, Snap, region) == (10.5 * 2) + 3.5, "snap does not reach slot and gap")
Check(#snapped == 2 and snapped[1][1] == region and snapped[1][2] == 3 and snapped[2][2] == 10,
    "snap is not called with the region for the gap, then the slot")
snapped = {}
Check(AutoFit(2, 10, 0, Snap, region) == 21 and #snapped == 1, "a zero gap must not be snapped")

-- The unit preview sizes an auto_pips class resource with this export too
-- (review R7: its own copy capped the count at 10, so an 18-pip Sweeping
-- Strikes preview was narrower than the live bar). The preview's width helper
-- is a file local; it is reached through the preview refresh's upvalues.
local Preview = world.core.UFPreview
Check(type(Preview) == "table" and type(Preview.Refresh) == "function", "the unit preview did not install")
local seen = {}
local function FindUpvalue(value, name, depth)
    if depth > 8 or seen[value] then return nil end
    seen[value] = true
    if type(value) == "function" then
        local i = 1
        while true do
            local upName, upValue = debug.getupvalue(value, i)
            if not upName then break end
            if upName == name and type(upValue) == "function" then return upValue end
            if type(upValue) == "function" or type(upValue) == "table" then
                local found = FindUpvalue(upValue, name, depth + 1)
                if found then return found end
            end
            i = i + 1
        end
    elseif type(value) == "table" then
        for _, item in pairs(value) do
            if type(item) == "function" or (type(item) == "table" and depth < 3) then
                local found = FindUpvalue(item, name, depth + 1)
                if found then return found end
            end
        end
    end
    return nil
end
local PreviewWidth = FindUpvalue(Preview.Refresh, "PreviewClassPowerWidth", 0)
Check(type(PreviewWidth) == "function", "the preview class resource width helper was not found")
local previewChecks = 0
for _, shape in ipairs({ "CIRCLE", "DIAMOND", "HEX" }) do
    for count = 1, 18 do
        for _, height in ipairs({ 2, 7, 12, 30 }) do
            for _, gap in ipairs({ -2, 0, 3, 8, 12 }) do
                local bars = { classPowerShape = shape, classPowerWidthMode = "auto_pips", classPowerGap = gap }
                local wanted = AutoFit(count, height, gap)
                if wanted < 1 then wanted = 1 elseif wanted > 800 then wanted = 800 end
                local got = PreviewWidth(bars, 240, height, count)
                Check(got == wanted, string.format("preview auto-fit for %d %s pips of %d px, gap %d is %s, live %s",
                    count, shape, height, gap, tostring(got), tostring(wanted)))
                previewChecks = previewChecks + 1
            end
        end
    end
end
Check(PreviewWidth({ classPowerShape = "CIRCLE", classPowerWidthMode = "auto_pips", classPowerGap = 2 }, 240, 10, 18)
    == 18 * 10 + 17 * 2, "an 18-pip preview is not as wide as the live bar")

print(string.format("uf_engine_preview_exports_smoke: ok (%s, %d unit specs, %d preview auto-fit widths)",
    flavor, units, previewChecks))

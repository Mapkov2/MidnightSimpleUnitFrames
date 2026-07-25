-- Contract smoke for the Auras3 duration-text style (formatter + native binding).
--
-- Covers the PTR AuraContainer contract for long-term and permanent auras:
--   * Permanent (zero-duration) auras and fully expired ones render nothing.
--     Blizzard's ApplyDurationText only calls SetDuration/SetEnabled, so without
--     the binding's zero/expired fallbacks a pooled button keeps the previous
--     aura's countdown (the "0.1" that raid buffs and poisons showed).
--   * Long durations promote to hours/days on Blizzard's own 1.5x boundaries
--     (Blizzard_AuraContainerShared's max-interval curve) instead of four-digit
--     minute counts, while MSUF keeps its 60 s minute boundary below that.
--   * The text update interval is capped at the finest rendered granularity, so
--     no aura formats a string every frame.
--   * One formatter + one binding per style signature, reused across the pool.
--
-- The style builder is a file-local in a 5k-line chunk, so it is extracted from
-- source and executed against stubs: this asserts behavior, not source text.

local failures = 0
local function check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL: " .. tostring(message))
    end
end

local function read(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local body = handle:read("*a")
    handle:close()
    -- The editor writes CRLF; normalize so "\n" patterns behave like CI.
    return (body:gsub("\r\n", "\n"))
end

local ADDON = "MidnightSimpleUnitFrames/"
if not read(ADDON .. "MidnightSimpleUnitFrames.toc") then ADDON = "" end

local SOURCE_PATH = ADDON .. "Auras3/MSUF_Auras3_UnitFrames.lua"
local source = read(SOURCE_PATH)
check(source ~= nil, "cannot read " .. SOURCE_PATH)
if not source then print("aura_duration_binding_smoke: FAILED"); os.exit(1) end

-------------------------------------------------------------------------------
--  Extract the style builder pair
-------------------------------------------------------------------------------

local startIndex = source:find("local function BuildAuraDurationBinding(", 1, true)
check(startIndex ~= nil, "BuildAuraDurationBinding not found")
local returnIndex = startIndex and source:find("    return style\n", startIndex, true)
check(returnIndex ~= nil, "BuildAuraDurationStyle must end with 'return style'")
local stopIndex = returnIndex and source:find("\nend\n", returnIndex, true)
check(stopIndex ~= nil, "BuildAuraDurationStyle is not closed")
if not (startIndex and returnIndex and stopIndex) then
    print("aura_duration_binding_smoke: FAILED")
    os.exit(1)
end

local body = source:sub(startIndex, stopIndex + 4)

-------------------------------------------------------------------------------
--  Stubs
-------------------------------------------------------------------------------

local formatters, bindings = {}, {}

local function NewFormatter()
    local formatter = { breakpoints = {} }
    function formatter:AddBreakpoint(breakpoint)
        self.breakpoints[#self.breakpoints + 1] = breakpoint
    end
    formatters[#formatters + 1] = formatter
    return formatter
end

local function NewBinding()
    local binding = { calls = 0 }
    function binding:SetFormatter(formatter) self.formatter = formatter; self.calls = self.calls + 1 end
    function binding:SetZeroDurationText(text) self.zeroText = text end
    function binding:SetExpiredText(text) self.expiredText = text end
    function binding:SetUpdateInterval(interval) self.interval = interval end
    function binding:SetEnabled(enabled) self.enabled = enabled end
    bindings[#bindings + 1] = binding
    return binding
end

_G.C_StringUtil = { CreateNumericRuleFormatter = NewFormatter }
_G.C_DurationUtil = { CreateDurationTextBinding = NewBinding }
_G.MSUF_DB = { general = {} }

local preamble = [[
local ClampNumber, DEFAULT_SHARED, NumericRuleFormatRounding = ...
local table_concat, table_sort = table.concat, table.sort
local _durationFormatterCache
local function EscapeFormatLiteral(text) return (tostring(text or ""):gsub("%%", "%%%%")) end
local function Clamp01(value, fallback)
    value = tonumber(value) or fallback or 0
    if value < 0 then return 0 elseif value > 1 then return 1 end
    return value
end
local function Round(value) return math.floor((tonumber(value) or 0) + 0.5) end
local function ColorEscape(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
local function LocalizedTimeSuffix(key, fallback)
    if key == "MSUF_AURA_TIMER_MINUTE_SUFFIX" then return "M" end
    if key == "MSUF_AURA_TIMER_HOUR_SUFFIX" then return "H" end
    if key == "MSUF_AURA_TIMER_DAY_SUFFIX" then return "D" end
    return fallback
end
local MSUF = {}
]]
local epilogue = [[
return {
    BuildAuraDurationStyle = BuildAuraDurationStyle,
    ResetCache = function() _durationFormatterCache = nil end,
}
]]

local function ClampNumber(value, fallback, min, max)
    value = tonumber(value)
    if value == nil then value = fallback end
    if min and value < min then value = min end
    if max and value > max then value = max end
    return value
end
local DEFAULT_SHARED = { cooldownDecimalSeconds = 3 }
local function NumericRuleFormatRounding(_name, fallback) return fallback end

local loader = loadstring or load
local chunk, loadError = loader(preamble .. body .. epilogue, "@duration_style")
check(chunk ~= nil, "extracted style builder does not compile: " .. tostring(loadError))
if not chunk then print("aura_duration_binding_smoke: FAILED"); os.exit(1) end
local api = chunk(ClampNumber, DEFAULT_SHARED, NumericRuleFormatRounding)
check(type(api.BuildAuraDurationStyle) == "function", "BuildAuraDurationStyle not exported")

-------------------------------------------------------------------------------
--  Reference evaluator: the highest breakpoint whose threshold <= value wins.
-------------------------------------------------------------------------------

local function Evaluate(formatter, seconds)
    local best
    for _, breakpoint in ipairs(formatter.breakpoints) do
        if seconds >= breakpoint.threshold and (best == nil or breakpoint.threshold > best.threshold) then
            best = breakpoint
        end
    end
    if not best then return nil end
    local value = seconds
    local component = best.components and best.components[1]
    if component and component.div then value = value / component.div end
    local step = (component and component.step) or best.step or 1
    value = math.floor(value / step) * step
    if best.min and value < best.min then value = best.min end
    return (string.format(best.format, value))
end

-------------------------------------------------------------------------------
--  Decimal lane: permanent/expired blanking, unit promotion, interval
-------------------------------------------------------------------------------

local lane = { cooldownDecimalSeconds = 3 }
local style = api.BuildAuraDurationStyle(lane)
check(type(style) == "table", "style record missing")
check(style and style.formatter ~= nil, "style must carry a native formatter")
check(style and style.binding ~= nil, "style must carry a native duration binding")

local binding = style and style.binding
check(binding and binding.zeroText == "", "permanent auras must render empty text (SetZeroDurationText)")
check(binding and binding.expiredText == "", "expired auras must render empty text (SetExpiredText)")
check(binding and binding.formatter == style.formatter, "binding must carry the style formatter")
check(binding and binding.interval == 0.1, "decimal lanes update at 0.1 s, got " .. tostring(binding and binding.interval))
check(binding and binding.enabled == true, "template binding must be enabled before Assign")

local formatter = style and style.formatter
local cases = {
    { 2.5, "2.5", "sub-second decimals" },
    { 0.05, "0.1", "decimal floor" },
    { 45, "45", "whole seconds" },
    { 59.9, "59", "seconds round down" },
    { 60, "1M", "minute boundary" },
    { 3599, "59M", "just under an hour" },
    { 3600, "60M", "hour-long raid buff stays in minutes like Blizzard" },
    { 5400, "90M", "1.5 h is the last minute value" },
    { 5401, "1H", "hours promote at 1 + 1.5x" },
    { 7200, "2H", "two hours" },
    { 129600, "36H", "1.5 d is the last hour value" },
    { 129601, "1D", "days promote at 1 + 1.5x" },
    { 604800, "7D", "week-long aura" },
}
for _, case in ipairs(cases) do
    local got = formatter and Evaluate(formatter, case[1])
    check(got == case[2], string.format("%s: %ss -> %s (expected %s)", case[3], tostring(case[1]), tostring(got), case[2]))
end

-- No breakpoint may render a bare four-digit minute count for long auras.
local minuteBreakpoints, hourBreakpoints, dayBreakpoints = 0, 0, 0
for _, breakpoint in ipairs(formatter and formatter.breakpoints or {}) do
    local component = breakpoint.components and breakpoint.components[1]
    local div = component and component.div
    if div == 60 then minuteBreakpoints = minuteBreakpoints + 1
    elseif div == 3600 then hourBreakpoints = hourBreakpoints + 1
    elseif div == 86400 then dayBreakpoints = dayBreakpoints + 1 end
end
check(minuteBreakpoints >= 1, "missing minute breakpoint")
check(hourBreakpoints == 1, "expected exactly one hour breakpoint, got " .. hourBreakpoints)
check(dayBreakpoints == 1, "expected exactly one day breakpoint, got " .. dayBreakpoints)

-------------------------------------------------------------------------------
--  Caching: one formatter/binding per signature, memoized on the lane
-------------------------------------------------------------------------------

local formatterCount, bindingCount = #formatters, #bindings
check(api.BuildAuraDurationStyle(lane) == style, "lane must memoize its style record")
check(#formatters == formatterCount, "cached lane rebuilt a formatter")
check(#bindings == bindingCount, "cached lane rebuilt a binding")

local sibling = { cooldownDecimalSeconds = 3 }
local siblingStyle = api.BuildAuraDurationStyle(sibling)
check(siblingStyle == style, "lanes with the same style signature must share one style record")
check(#formatters == formatterCount, "identical signature rebuilt a formatter")
check(#bindings == bindingCount, "identical signature rebuilt a binding")

-------------------------------------------------------------------------------
--  Non-decimal lane: coarser update interval, whole-second floor
-------------------------------------------------------------------------------

local wholeLane = { cooldownDecimalSeconds = 0 }
local wholeStyle = api.BuildAuraDurationStyle(wholeLane)
check(wholeStyle ~= style, "a different decimal window must build its own style")
check(wholeStyle and wholeStyle.binding and wholeStyle.binding.interval == 0.25,
    "whole-second lanes update at 0.25 s, got " .. tostring(wholeStyle and wholeStyle.binding and wholeStyle.binding.interval))
check(wholeStyle and wholeStyle.binding.zeroText == "", "whole-second lanes must blank permanent auras too")
check(wholeStyle and Evaluate(wholeStyle.formatter, 0.4) == "1", "whole-second lanes floor at 1")
check(wholeStyle and Evaluate(wholeStyle.formatter, 3600) == "60M", "whole-second lanes keep minute text")

-------------------------------------------------------------------------------
--  Native option plumbing and locale coverage
-------------------------------------------------------------------------------

check(source:find("_durationTextOptions.binding = style.binding", 1, true) ~= nil,
    "the aura button must receive the template binding via the PTR `binding` option")
check(source:find("_durationTextOptions.binding = nil", 1, true) ~= nil,
    "the shared option table must be cleared after SetDurationText")
check(source:find("BuildAuraDurationFormatter", 1, true) == nil,
    "stale BuildAuraDurationFormatter reference left behind")

local locales = { "deDE", "enGB", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
for _, locale in ipairs(locales) do
    local text = read(ADDON .. "Locales/" .. locale .. ".lua") or ""
    for _, key in ipairs({ "MSUF_AURA_TIMER_MINUTE_SUFFIX", "MSUF_AURA_TIMER_HOUR_SUFFIX", "MSUF_AURA_TIMER_DAY_SUFFIX" }) do
        check(text:find('L["' .. key .. '"]', 1, true) ~= nil, locale .. " is missing " .. key)
    end
end

if failures > 0 then
    print(string.format("aura_duration_binding_smoke: FAILED (%d)", failures))
    os.exit(1)
end
print("aura_duration_binding_smoke: ok")

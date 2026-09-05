-- Public slot compilation preserves native arguments, including live styles.
local root = arg and arg[1] or "."
local source = arg and arg[2] or root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua"
local function Forbidden() error("secret value inspected in Lua") end
local meta = { __eq = Forbidden, __lt = Forbidden, __le = Forbidden, __tostring = Forbidden,
    __add = Forbidden, __sub = Forbidden, __mul = Forbidden, __div = Forbidden, __index = Forbidden }
local secretCur, secretMax, secretPct = setmetatable({}, meta), setmetatable({}, meta), setmetatable({}, meta)
local shortCur, shortMax, fullCur, fullMax = {}, {}, {}, {}
local function IsSecret(v)
    return rawequal(v, secretCur) or rawequal(v, secretMax) or rawequal(v, secretPct)
end
_G.issecretvalue = IsSecret
local shape = {
    CURRENT = { "cur" }, FULLVALUE = { "cur" }, MAX = { "max" }, PERCENT = { "pct" },
    CURMAX = { "cur", "max" }, MAXCUR = { "max", "cur" },
    CURPERCENT = { "cur", "pct" }, PERCENTCUR = { "pct", "cur" },
    CURMAXPERCENT = { "cur", "max", "pct" }, PERCENTMAXCUR = { "pct", "max", "cur" },
    MAXPERCENT = { "max", "pct" }, PERCENTMAX = { "pct", "max" },
    PERCENTCURMAX = { "pct", "cur", "max" },
}
local cases = {
    { cur = secretCur, max = secretMax, pct = secretPct },
    { cur = "12345", max = 45678, pct = 37.5 },
    { cur = 0/0, max = math.huge, pct = -math.huge },
    {},
    { cur = secretCur, max = "90000", pct = secretPct },
}
local function Finite(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return 0 end
    return n
end
local function Same(a, b)
    if IsSecret(a) or IsSecret(b) or type(a) == "table" or type(b) == "table" then return rawequal(a, b) end
    return a == b
end
local function Expected(v, kind, short, available, options)
    if kind == "pct" or not available then return IsSecret(v) and v or Finite(v) end
    if rawequal(v, secretCur) then return short and shortCur or fullCur end
    if rawequal(v, secretMax) then return short and shortMax or fullMax end
    return (short and "short:" or "full:") .. tostring(Finite(v)) .. (short and options and options.name or "")
end

local checks = 0
for _, available in ipairs({ true, false }) do
    _G.AbbreviateNumbers, _G.AbbreviateLargeNumbers, _G.ShortenNumber, _G.BreakUpLargeNumbers = nil, nil, nil, nil
    local nativeCalls, nativeOptions, callback, options = 0, nil, nil, nil
    local function Native(v, opts, short)
        nativeCalls = nativeCalls + 1
        nativeOptions = opts
        return Expected(v, "cur", short, true, opts)
    end
    local Text = {
        UnitPowerType = function() return 0 end, tonumber = tonumber, type = type,
        format = string.format, floor = math.floor, max = math.max, REVERSE_HEALTH_MODE = {},
        AbbreviateNumbers = available and function(v, opts) return Native(v, opts, true) end or nil,
        BreakUpLargeNumbers = available and function(v, opts) return Native(v, opts, false) end or nil,
    }
    local ns = { UFText = Text, Apply = {}, NumberFormat = { Register = function(fn) callback = fn end } }
    assert(loadfile(source))("MidnightSimpleUnitFrames", ns)
    for mode, order in pairs(shape) do
        for _, short in ipairs({ true, false }) do
            for _, decimals in ipairs({ 0, 1 }) do
                for _, hidePercent in ipairs({ true, false }) do
                    local fs = { writes = 0, IsShown = function() return true end }
                    function fs:SetFormattedText(pattern, ...)
                        self.writes = self.writes + 1
                        self.pattern, self.args, self.argCount = pattern, { ... }, select("#", ...)
                    end
                    local frame = { hpTextCenter = fs }
                    local spec = { showHealthText = true, showPowerText = false }
                    local text = { healthLeft = "NONE", healthCenter = mode, healthRight = "NONE",
                        healthDelimiter = " / ", healthShortNumbers = short,
                        healthPercentDecimals = decimals, hidePercentSymbol = hidePercent,
                        powerLeft = "NONE", powerCenter = "NONE", powerRight = "NONE" }
                    local rt = Text.CompileTextRuntime(frame, spec, text)
                    local slot = assert(rt.healthSlots[1])
                    assert(slot.short == short and type(slot.secretWriter) == "function")
                    local writer = slot.secretWriter
                    for _, newOptions in ipairs({ false, { name = "A" }, { name = "B" } }) do
                        options = newOptions or nil
                        callback(options) -- existing writer must see this without recompilation
                        for _, values in ipairs(cases) do
                            for _, explicitFlags in ipairs({ false, true }) do
                                local expected, patterns, numericCalls = {}, {}, 0
                                for i, key in ipairs(order) do
                                    if i > 1 then expected[#expected+1] = " / "; patterns[#patterns+1] = "%s" end
                                    expected[#expected+1] = Expected(values[key], key, short, available, options)
                                    patterns[#patterns+1] = key == "pct"
                                        and ((decimals == 1 and "%.1f" or "%d") .. (hidePercent and "" or "%%"))
                                        or (available and "%s" or "%d")
                                    if key ~= "pct" and available then numericCalls = numericCalls + 1 end
                                end
                                local before = nativeCalls
                                fs._aText, fs._aTextPlain = secretCur, true
                                local cs, ms, ps
                                if explicitFlags then cs, ms, ps = IsSecret(values.cur), IsSecret(values.max), IsSecret(values.pct) end
                                writer(slot, values.cur, values.max, values.pct, false, nil, cs, ms, ps)
                                assert(fs._aText == nil and fs._aTextPlain == nil, "secret output entered the plain text cache")
                                assert(fs.pattern == table.concat(patterns), mode .. ": pattern changed")
                                assert(fs.argCount == #expected, mode .. ": argument arity changed")
                                for i, value in ipairs(expected) do assert(Same(value, fs.args[i]), mode .. ": native argument changed") end
                                assert(nativeCalls == before + numericCalls, "unused value was formatted")
                                if numericCalls > 0 then assert(rawequal(nativeOptions, short and options or nil), "live number-style options changed") end
                                checks = checks + 1
                            end
                        end
                    end
                    text.healthCenter = "NONE"
                    Text.CompileTextRuntime(frame, spec, text)
                    assert(frame._msufTextRuntime.healthSlotCount == 0, "disabled slot survived recompilation")
                end
            end
        end
    end
end
print("worldboss13_secret_writer_smoke: ok (" .. checks .. " native-call parity cases)")

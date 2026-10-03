-- castbar_secret_world.lua -- the real Mainline core with every secret-capable
-- castbar value secret, as strict as the 12.x client.
--
-- The castbar smokes model a plain client. On Midnight most of what a castbar
-- reads can be secret, and secrets also come out of objects: the duration
-- objects, the cooldown and GCD tables, the colour objects the curve and class
-- APIs return. This world boots the whole shipped Mainline core graph
-- (tools/tests/client_world.lua, which also builds MSUF.Client from the matrix)
-- with the strict secrets of tools/tests/classpower_secrets.lua installed:
-- type() answers the kind, issecretvalue() knows it, and arithmetic, ordering,
-- concatenation, length, indexing, calling and secret == secret raise.
--
-- Secret in this world (per the 12.1 API documentation, then stricter):
--   * UnitCastingInfo / UnitChannelInfo: name, text, texture, start, end,
--     castID, notInterruptible, spellID. NeverSecret stays plain: isTradeskill,
--     castBarID, delayTimeMs, isEmpowered, numEmpowerStages.
--   * UNIT_SPELLCAST_* payloads: castGUID, spellID, interruptedBy (castBarID
--     and the unit token stay plain).
--   * UnitCastingDuration / UnitChannelDuration / C_Spell.GetSpellCooldownDuration:
--     every getter of the duration object (remaining, total, start, end,
--     elapsed, IsZero, IsActive, HasExpired); HasSecretValues stays plain.
--   * C_Spell.GetSpellCooldown: startTime, duration, modRate (isEnabled and
--     isActive are NeverSecret).
--   * GetUnitEmpowerStageCount / StageDuration / HoldAtMaxTime.
--   * UnitSpellTargetName / UnitSpellTargetClass, UnitNameFromGUID,
--     UnitClassFromGUID, the RGB of C_ClassColor.GetClassColor(secret).
--   * C_CurveUtil.Evaluate*FromBoolean results for a secret boolean.
--   * UnitAttackSpeed (WoW Forever, SecretWhenUnitStatsRestricted).
--   * FontString:GetText()/GetStringWidth() after a secret text was set.
-- Concatenating a secret string with a string or number is allowed and
-- yields a secret string, as in the client; every other operation raises.
-- C sinks accept secrets: SetText, SetFormattedText, SetValue, SetMinMaxValues,
-- SetStatusBarColor, SetVertexColor, SetTextColor, SetTexture, SetTimerDuration,
-- SetVertexColorFromBoolean, SetAlphaFromBoolean, SetCooldownFromDurationObject,
-- the DurationTextBinding setters. AllowedWhenUntainted arguments raise when an
-- addon passes a secret (Duration:SetTimeFromStart/End, ColorCurve:Evaluate...).
--
-- Watch(paths) closes the gaps Lua 5.1 leaves (no __eq against nil, a number
-- or a string; a table key never raises): a line hook records every executed
-- line of the watched files that compares (==, ~=) or negates (not) a local
-- holding a secret, a field of a local table holding one (`state.spellName ~=
-- nil`), uses one as a table key, or boolean-tests a secret boolean in any form
-- (`if x then`, `x and`, `or x`). The guards of the classpower_secrets line
-- watcher apply: issecretvalue(name) on the line, or a `flag or` / `flag and`
-- (also `not flag and` / `not flag or`) short-circuit with a plain local flag.
--
-- Plain Lua 5.1, repo root as the first argument of New.

local SecretWorld = {}
SecretWorld.__index = SecretWorld

local STEP = 1 / 60
SecretWorld.STEP = STEP

local function Normalize(path) return (tostring(path):gsub("\\", "/")) end

--------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------

local Secrets

-- Budget mode (world.budget): one secret per kind, reused, so a measurement
-- counts only what the addon allocates.
local reusedSecrets
local function S(kind)
    kind = kind or "number"
    if reusedSecrets then
        local secret = reusedSecrets[kind]
        if not secret then secret = Secrets.New(kind); reusedSecrets[kind] = secret end
        return secret
    end
    return Secrets.New(kind)
end
local function IsSecret(value) return Secrets.IsSecret(value) end
local function AnySecret(...)
    for index = 1, select("#", ...) do
        if IsSecret((select(index, ...))) then return true end
    end
    return false
end

-- AllowedWhenUntainted: addon code handing a secret to such an argument raises.
local function RejectSecrets(api, ...)
    if AnySecret(...) then error(api .. ": secret argument from tainted code", 3) end
end

--------------------------------------------------------------------------
-- Duration objects (LuaDurationObjectAPIDocumentation.lua)
--------------------------------------------------------------------------

local Duration = {}
Duration.__index = Duration

local function NewDuration(world, secret, startTime, total)
    return setmetatable({ world = world, secret = secret == true, startTime = startTime or 0,
        total = total or 0 }, Duration)
end

function Duration:Remaining()
    local remaining = self.startTime + self.total - self.world.clock
    return remaining > 0 and remaining or 0
end
function Duration:HasSecretValues() return self.secret end
function Duration:GetRemainingDuration(modifier)
    RejectSecrets("Duration:GetRemainingDuration", modifier)
    if self.secret then return S() end
    return self:Remaining()
end
function Duration:GetTotalDuration() if self.secret then return S() end return self.total end
function Duration:GetElapsedDuration() if self.secret then return S() end return self.total - self:Remaining() end
function Duration:GetStartTime() if self.secret then return S() end return self.startTime end
function Duration:GetEndTime() if self.secret then return S() end return self.startTime + self.total end
function Duration:GetRemainingPercent() if self.secret then return S() end return self.total > 0 and self:Remaining() / self.total or 0 end
function Duration:IsZero() if self.secret then return S("boolean") end return self.total <= 0 end
function Duration:IsActive() if self.secret then return S("boolean") end return self:Remaining() > 0 end
function Duration:HasExpired() if self.secret then return S("boolean") end return self:Remaining() <= 0 end
function Duration:HasStarted() if self.secret then return S("boolean") end return self.world.clock >= self.startTime end
function Duration:GetModRate() return 1 end
function Duration:Assign(other)
    self.secret, self.startTime, self.total = other.secret, other.startTime, other.total
end
function Duration:Copy() return NewDuration(self.world, self.secret, self.startTime, self.total) end
function Duration:Reset() self.secret, self.startTime, self.total = false, 0, 0 end
function Duration:SetTimeFromStart(startTime, total, modRate)
    RejectSecrets("Duration:SetTimeFromStart", startTime, total, modRate)
    self.secret, self.startTime, self.total = false, startTime, total
end
function Duration:SetTimeFromEnd(endTime, total, modRate)
    RejectSecrets("Duration:SetTimeFromEnd", endTime, total, modRate)
    self.secret, self.startTime, self.total = false, endTime - total, total
end
SecretWorld.Duration = Duration

--------------------------------------------------------------------------
-- Watcher
--------------------------------------------------------------------------

local function SourceLines(path)
    local file = assert(io.open(path, "rb"), "missing source: " .. path)
    local raw = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local lines = {}
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end

local function Escape(name) return (name:gsub("%W", "%%%0")) end

-- The expression before a use, as tokens: names and keywords, numbers,
-- strings, operators (==, ~=, <=, >=, .., ... and single characters). A
-- comment ends the line.
local function Tokens(text)
    local tokens, position = {}, 1
    while position <= #text do
        local char = text:sub(position, position)
        if char:find("%s") then
            position = position + 1
        elseif text:find("^%-%-", position) then
            break
        elseif char == "\"" or char == "'" then
            local finish = position + 1
            while finish <= #text and text:sub(finish, finish) ~= char do
                if text:sub(finish, finish) == "\\" then finish = finish + 1 end
                finish = finish + 1
            end
            tokens[#tokens + 1] = { kind = "string", value = text:sub(position + 1, finish - 1) }
            position = finish + 1
        elseif char:find("[%a_]") then
            local word = text:match("^[%a_][%w_]*", position)
            tokens[#tokens + 1] = { kind = "name", text = word }
            position = position + #word
        elseif char:find("%d") then
            local number = text:match("^%d+%.?%d*", position)
            tokens[#tokens + 1] = { kind = "number", value = tonumber(number) }
            position = position + #number
        else
            local operator = text:match("^[=~<>]=", position) or text:match("^%.%.%.?", position) or char
            tokens[#tokens + 1] = { kind = "op", text = operator }
            position = position + #operator
        end
    end
    return tokens
end

local KEYWORD = { ["and"] = true, ["or"] = true, ["not"] = true, ["true"] = true, ["false"] = true, ["nil"] = true,
    ["if"] = true, ["then"] = true, ["else"] = true, ["elseif"] = true, ["local"] = true, ["return"] = true,
    ["while"] = true, ["do"] = true, ["until"] = true, ["function"] = true, ["end"] = true, ["for"] = true,
    ["in"] = true, ["repeat"] = true }
-- Tokens after which an operand starts a new (sub)expression.
local OPERAND_START = { ["("] = true, ["{"] = true, ["["] = true, ["="] = true, [","] = true, ["and"] = true,
    ["or"] = true, ["return"] = true, ["if"] = true, ["elseif"] = true, ["while"] = true, ["until"] = true,
    ["then"] = true, ["do"] = true, ["else"] = true }
local LITERAL = { ["true"] = true, ["false"] = false }

local function TokenText(token) return token and (token.text or token.kind) end

-- A plain operand at tokens[index]: a non-secret local, or such a local
-- compared (==, ~=) with a literal. Returns its value and the next index.
local function PlainOperand(tokens, index, locals)
    local token = tokens[index]
    if not (token and token.kind == "name" and not KEYWORD[token.text]) then return end
    local value = locals[token.text]
    if value == nil or IsSecret(value) then return end
    local operator, literal = tokens[index + 1], tokens[index + 2]
    if operator and operator.kind == "op" and (operator.text == "==" or operator.text == "~=") then
        if not literal then return end
        local plain
        if literal.kind == "number" or literal.kind == "string" then
            plain = literal.value
        elseif literal.kind == "name" and (LITERAL[literal.text] ~= nil or literal.text == "nil") then
            plain = LITERAL[literal.text]
        else
            return
        end
        local equal = rawequal(value, plain)
        if operator.text == "==" then return equal, index + 3 end
        return not equal, index + 3
    end
    return value, index + 1
end

-- True when the expression before a use short-circuits it, by Lua's
-- precedence: a plain operand (see PlainOperand), optionally negated with
-- `not`, that is true before `or` (and not the right side of an `and`), or
-- false before `and` with no `or` of the same depth after it, and the use
-- inside that operator's right side (no bracket closes in between). `i == 1 or x ~= nil` with i == 2 does not
-- short-circuit; a bare `i or` with a number would have.
local function ShortCircuited(prefix, locals)
    local tokens = Tokens(prefix)
    local depths, depth = {}, 0
    for index = 1, #tokens do
        local text = TokenText(tokens[index])
        if text == ")" or text == "}" or text == "]" then depth = depth - 1 end
        depths[index] = depth
        if text == "(" or text == "{" or text == "[" then depth = depth + 1 end
    end
    for index = 1, #tokens do
        local before = tokens[index - 1]
        if index == 1 or OPERAND_START[TokenText(before)] then
            local negated, start = false, index
            if TokenText(tokens[index]) == "not" then negated, start = true, index + 1 end
            local value, nextIndex = PlainOperand(tokens, start, locals)
            local operator = nextIndex and tokens[nextIndex]
            local word = operator and operator.kind == "name" and operator.text
            -- After `and` the operand ends a conjunction: `a and b or use`
            -- is `(a and b) or use`, which b alone does not decide.
            if word == "or" and TokenText(before) == "and" then word = nil end
            if word == "and" or word == "or" then
                if negated then value = not value end
                local level, inside = depths[nextIndex], true
                for after = nextIndex + 1, #tokens do
                    local text = TokenText(tokens[after])
                    if depths[after] < level then inside = false break end
                    if word == "and" and text == "or" and depths[after] == level then inside = false break end
                end
                if inside and word == "or" and value then return true end
                if inside and word == "and" and not value then return true end
            end
        end
    end
    return false
end
SecretWorld.ShortCircuited = ShortCircuited

local USE_PATTERNS = { "%%f[%%w_.]%s%%s*[=~]=", "[=~]=%%s*%s%%f[^%%w_]", "%%f[%%w_]not%%s+%s%%f[^%%w_]",
    "%%f[%%w_]not%%s*%%(%%s*%s%%s*%%)" }

-- A secret boolean's truth is its value, so the client refuses any boolean
-- test of it, not only `not`.
-- Each pattern captures the position of the name; the text before it is what
-- may short-circuit the test.
local BOOLEAN_PATTERNS = { "%%f[%%w_]if%%s+()%s%%s+then", "%%f[%%w_.]()%s%%s+and%%f[^%%w_]", "%%f[%%w_.]()%s%%s+or%%f[^%%w_]",
    "%%f[%%w_]and%%s+()%s%%s*[%%)%%s]", "%%f[%%w_]and%%s+()%s$", "%%f[%%w_]or%%s+()%s%%s*[%%)%%s]", "%%f[%%w_]or%%s+()%s$" }

local function Misuses(line, name, locals, value)
    local n = Escape(name)
    -- Guards: issecretvalue and its aliases, and SwingTimer's Public
    -- (`not issecretvalue`).
    if line:find("issecretvalue%(%s*" .. n .. "%s*%)") or line:find("IsSecretValue%(%s*" .. n .. "%s*%)")
        or line:find("[Ii]s[Ss]ecret%(%s*" .. n .. "%s*%)") or line:find("%f[%w_]Public%(%s*" .. n .. "%s*%)") then
        return false
    end
    -- A secret table key raises in the client; Lua 5.1 indexes with it silently.
    if line:find("%[%s*" .. n .. "%s*%]") then return true end
    for index = 1, #USE_PATTERNS do
        local start = line:find(USE_PATTERNS[index]:format(n))
        if start and not ShortCircuited(line:sub(1, start - 1), locals) then return true end
    end
    if type(value) == "boolean" then
        for index = 1, #BOOLEAN_PATTERNS do
            local _, _, position = line:find(BOOLEAN_PATTERNS[index]:format(n))
            if position and not ShortCircuited(line:sub(1, position - 1), locals) then return true end
        end
    end
    return false
end
SecretWorld.Misuses = Misuses
--- The secret helper of the last world built (the watcher's IsSecret).
function SecretWorld.CurrentSecrets() return Secrets end

--- Records every executed line of the given files that compares or
--- truth-tests a secret local or a secret field of a local table. Returns
--- stop(): it removes the hook and returns the violations as
--- "file:line: text" strings (each line once), and the coverage: per file
--- name, the set of first lines (linedefined) of every function that ran.
function SecretWorld:Watch(paths)
    local watched = {}
    for index = 1, #paths do
        local path = Normalize(paths[index])
        watched["@" .. path] = { lines = SourceLines(path), name = path:match("[^/]+$"), seen = {}, covered = {} }
    end
    local violations = {}
    local getinfo, getlocal = debug.getinfo, debug.getlocal
    debug.sethook(function(_, lineNumber)
        local info = getinfo(2, "S")
        local source = info and info.source
        local entry = source and (watched[source] or watched[Normalize(source)])
        if not entry then return end
        entry.covered[info.linedefined] = true
        local text = entry.lines[lineNumber]
        if not text or entry.seen[lineNumber] then return end
        local locals, index = {}, 1
        while true do
            local name, value = getlocal(2, index)
            if not name then break end
            if name:sub(1, 1) ~= "(" then locals[name] = value end
            index = index + 1
        end
        local function Flag()
            entry.seen[lineNumber] = true
            violations[#violations + 1] = ("%s:%d: %s"):format(entry.name, lineNumber, text:match("^%s*(.-)%s*$"))
        end
        for name, value in pairs(locals) do
            if IsSecret(value) then
                if Misuses(text, name, locals, value) then Flag() return end
            elseif rawequal(type(value), "table") and text:find(name .. ".", 1, true) then
                for field in text:gmatch("%f[%w_]" .. Escape(name) .. "%.([%a_][%w_]*)") do
                    local fieldValue = rawget(value, field)
                    if IsSecret(fieldValue) and Misuses(text, name .. "." .. field, locals, fieldValue) then
                        Flag()
                        return
                    end
                end
            end
        end
    end, "l")
    return function()
        debug.sethook()
        local coverage = {}
        for _, entry in pairs(watched) do coverage[entry.name] = entry.covered end
        return violations, coverage
    end
end

--- The line that defines the named function in a castbar file, for coverage
--- checks ("local function Name(", "function X:Name(", "Name = function(").
function SecretWorld:FunctionLine(fileName, functionName)
    for index = 1, #self.corePaths do
        local path = self.corePaths[index]
        if path:match("[^/]+$") == fileName then
            local lines = SourceLines(path)
            local name = Escape(functionName)
            for number = 1, #lines do
                local line = lines[number]
                if line:find("function%s+[%w_.:]*%f[%w_]" .. name .. "%s*%(")
                    or line:find("%f[%w_]" .. name .. "%s*=%s*function%s*%(") then
                    return number
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- The world
--------------------------------------------------------------------------

-- Fields of the cast tuple that stay plain (NeverSecret in UnitDocumentation).
local function V(secret, value, kind) if secret then return S(kind) end return value end

local function CastTuple(world, cast)
    local secret = world.secretCasts
    cast.guid = cast.guid or (cast.name .. "-guid")
    return V(secret, cast.name, "string"), V(secret, cast.name, "string"), V(secret, 135812), V(secret, cast.startMS),
        V(secret, cast.endMS), cast.tradeskill == true, V(secret, cast.guid, "string"),
        V(secret, cast.notInterruptible == true, "boolean"), V(secret, cast.spellID), cast.castBarID, cast.delayMS or 0
end

local function ChannelTuple(world, cast)
    local secret = world.secretCasts
    return V(secret, cast.name, "string"), V(secret, cast.name, "string"), V(secret, 136208), V(secret, cast.startMS),
        V(secret, cast.endMS), false, V(secret, cast.notInterruptible == true, "boolean"), V(secret, cast.spellID),
        cast.empowered == true, cast.empowered and 3 or 0, cast.castBarID
end

local function InstallClient(world, env)
    local clock = function() return world.clock end
    env.GetTime = clock
    env.GetTimePreciseSec = clock

    -- Deadline-ordered timers: C_Timer.After, NewTimer and NewTicker. Queue
    -- entries and handles are pooled, so in budget mode the harness allocates
    -- nothing; NewTimer/NewTicker (the client allocates their handles) are
    -- counted instead.
    -- Fields are reset to false, never nil: a cleared key that the collector
    -- marks dead makes its table grow again when it is set.
    local timers, pool, poolCount = world.timers, {}, 0
    local function Queue(delay, fn, handle, period)
        world.timerSequence = world.timerSequence + 1
        local entry
        if poolCount > 0 then
            entry = pool[poolCount]
            pool[poolCount] = false
            poolCount = poolCount - 1
        else
            entry = { due = 0, fn = false, handle = false, period = false, sequence = 0 }
        end
        entry.due, entry.fn, entry.handle, entry.period = world.clock + (delay or 0), fn, handle or false, period or false
        entry.sequence = world.timerSequence
        world.timerCount = world.timerCount + 1
        timers[world.timerCount] = entry
    end
    world.ReleaseTimer = function(entry)
        entry.fn, entry.handle, entry.period = false, false, false
        poolCount = poolCount + 1
        pool[poolCount] = entry
    end
    world.QueueTimer = Queue
    local handlePool, handleCount = {}, 0
    local function Handle(iterations)
        local handle
        if handleCount > 0 then
            handle = handlePool[handleCount]
            handlePool[handleCount] = false
            handleCount = handleCount - 1
        else
            -- The client allocates this handle; its bytes are the harness's
            -- (world.harnessBytes), the call is counted as an object native.
            local before = collectgarbage("count")
            handle = { cancelled = false, remaining = false,
                Cancel = function(self) self.cancelled = true end,
                IsCancelled = function(self) return self.cancelled == true end }
            world.harnessBytes = world.harnessBytes + (collectgarbage("count") - before) * 1024
        end
        handle.cancelled, handle.remaining = false, iterations or false
        return handle
    end
    env.C_Timer = {
        After = function(delay, fn) world.counts.After = world.counts.After + 1; Queue(delay, fn) end,
        NewTimer = function(delay, fn)
            world.counts.NewTimer = world.counts.NewTimer + 1
            local handle = Handle(1)
            Queue(delay, fn, handle, nil)
            return handle
        end,
        NewTicker = function(delay, fn, iterations)
            world.counts.NewTicker = world.counts.NewTicker + 1
            local handle = Handle(iterations)
            Queue(delay, fn, handle, delay)
            return handle
        end,
    }
    env.TimerUtil = nil
    -- The Kernel scheduler isolates each callback with secureexecuterange. An
    -- error is recorded, not raised, exactly once, so the smoke reports it.
    env.secureexecuterange = function(list, fn, ...)
        for index = 1, #list do
            local ok, message = pcall(fn, index, list[index], ...)
            if not ok then world.errors[#world.errors + 1] = tostring(message) end
        end
    end

    env.issecretvalue = _G.issecretvalue
    env.issecure = function() return false end
    env.UnitClass = function(unit)
        if unit == "player" then return world.playerClass, world.playerClass, 8 end
        return "Warrior", "WARRIOR", 1
    end
    -- WoW Forever: the swing API (upstream/forever SwingTimerDocumentation.lua).
    -- PLAYER_SWING carries plain values; the attack speeds are
    -- SecretWhenUnitStatsRestricted, and the range answers are kept secret here
    -- although the documentation marks none.
    env.Enum = rawget(env, "Enum") or {}
    env.Enum.PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 }
    env.C_SwingTimer = {
        EnableRangeCheck = function(swingType, enable) RejectSecrets("C_SwingTimer.EnableRangeCheck", swingType, enable) end,
        IsTargetWithinSwingRange = function() return S("boolean") end,
    }
    env.UnitAttackSpeed = function() return S(), S(), S() end
    env.UnitExists = function(unit) return world.exists[unit] == true end
    env.UnitIsDeadOrGhost = function(unit) return world.dead[unit] == true end
    env.UnitIsUnconscious = function() return false end
    env.UnitIsConnected = function() return true end
    env.UnitHasVehicleUI = function() return false end
    env.UnitAffectingCombat = function() return world.combat == true end
    env.UnitGUID = function(unit) return unit and (unit .. "-guid") or nil end
    env.UnitIsPlayer = function() return false end
    env.UnitCanAttack = function() return true end

    env.UnitCastingInfo = function(unit)
        local cast = world.casting[unit]
        if not cast then return nil end
        return CastTuple(world, cast)
    end
    env.UnitChannelInfo = function(unit)
        local cast = world.channeling[unit]
        if not cast then return nil end
        return ChannelTuple(world, cast)
    end
    local function UnitDuration(cast)
        if not cast then return nil end
        world.counts.UnitDuration = world.counts.UnitDuration + 1
        local startTime, total = cast.startMS / 1000, (cast.endMS - cast.startMS) / 1000
        if world.budget then
            local reused = cast.durationObject or NewDuration(world, false, 0, 0)
            cast.durationObject = reused
            reused.secret, reused.startTime, reused.total = world.secretCasts, startTime, total
            return reused
        end
        return NewDuration(world, world.secretCasts, startTime, total)
    end
    env.UnitCastingDuration = function(unit) return UnitDuration(world.casting[unit]) end
    env.UnitChannelDuration = function(unit) return UnitDuration(world.channeling[unit]) end
    env.GetUnitEmpowerStageCount = function(unit)
        local cast = world.channeling[unit] or world.casting[unit]
        if not (cast and cast.empowered) then return 0 end
        return world.secretCasts and S() or 3
    end
    env.GetUnitEmpowerStageDuration = function(unit, index)
        local cast = world.channeling[unit] or world.casting[unit]
        if not (cast and cast.empowered) or index < 0 or index > 2 then return 0 end
        return world.secretCasts and S() or 400
    end
    env.GetUnitEmpowerHoldAtMaxTime = function() return world.secretCasts and S() or 1000 end
    env.UnitShouldDisplaySpellTargetName = function() return true end
    env.UnitSpellTargetName = function() return S("string") end
    env.UnitSpellTargetClass = function() return S("string") end
    env.UnitNameFromGUID = function(guid) if IsSecret(guid) then return S("string") end return "Kicker" end
    env.UnitClassFromGUID = function(guid)
        if IsSecret(guid) then return S("string"), S("string"), S() end
        return "Rogue", "ROGUE", 4
    end
    env.SPELL_INTERRUPTED_BY = "%s interrupted"
    env.INTERRUPTED = "Interrupted"

    local reusedColors = {}
    local Color
    local function NewColor(r, g, b, a)
        if world.budget then
            local key = (IsSecret(r) and "secret" or tostring(r)) .. ":" .. (IsSecret(g) and "" or tostring(g))
                .. ":" .. (IsSecret(b) and "" or tostring(b))
            local color = reusedColors[key]
            if not color then color = Color(r, g, b, a); reusedColors[key] = color end
            return color
        end
        return Color(r, g, b, a)
    end
    Color = function(r, g, b, a)
        local color = { r = r, g = g, b = b, a = a or 1 }
        function color:GetRGB() return self.r, self.g, self.b end
        function color:GetRGBA() return self.r, self.g, self.b, self.a end
        function color:WrapTextInColorCode(text)
            if AnySecret(text, self.r) then return S("string") end
            return "|cff000000" .. text .. "|r"
        end
        function color:GenerateHexColor() return "ffffffff" end
        return color
    end
    env.CreateColor = Color
    env.C_ClassColor = {
        GetClassColor = function(className)
            world.counts.GetClassColor = world.counts.GetClassColor + 1
            if IsSecret(className) then return NewColor(S(), S(), S(), 1) end
            return NewColor(0.9, 0.8, 0.5, 1)
        end,
    }
    env.C_CurveUtil = {
        EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
            if AnySecret(value, ifTrue, ifFalse) then return S() end
            return value and ifTrue or ifFalse
        end,
        EvaluateColorFromBoolean = function(value, ifTrue, ifFalse)
            world.counts.EvaluateColorFromBoolean = world.counts.EvaluateColorFromBoolean + 1
            if IsSecret(value) then return NewColor(S(), S(), S(), S()) end
            return value and ifTrue or ifFalse
        end,
        CreateCurve = function()
            return { AddPoint = function() end, SetType = function() end,
                Evaluate = function(_, x) RejectSecrets("Curve:Evaluate", x); return 0 end }
        end,
        CreateColorCurve = function()
            return { AddPoint = function() end, SetType = function() end,
                Evaluate = function(_, x) RejectSecrets("ColorCurve:Evaluate", x); return Color(1, 1, 1, 1) end }
        end,
    }

    -- Spell API. The interrupt (Counterspell) and the GCD dummy share the
    -- world's cooldown model.
    env.C_Spell = {
        -- Both return a new object in the client (counted); budget mode reuses one.
        GetSpellCooldown = function(spellID)
            world.counts.GetSpellCooldown = world.counts.GetSpellCooldown + 1
            local cooldown = world.cooldowns[spellID]
            local active = cooldown ~= nil and cooldown.startTime + cooldown.total > world.clock
            local secret = world.secretCooldowns
            local info = world.budget and world.reusedCooldownInfo[spellID] or {}
            if world.budget then world.reusedCooldownInfo[spellID] = info end
            info.startTime = secret and S() or (active and cooldown.startTime or 0)
            info.duration = secret and S() or (active and cooldown.total or 0)
            info.isEnabled, info.isActive = true, active
            info.modRate = secret and S() or 1
            return info
        end,
        GetSpellCooldownDuration = function(spellID)
            world.counts.GetSpellCooldownDuration = world.counts.GetSpellCooldownDuration + 1
            local cooldown = world.cooldowns[spellID]
            local active = cooldown ~= nil and cooldown.startTime + cooldown.total > world.clock
            local duration = world.budget and world.reusedCooldownDurations[spellID] or NewDuration(world, false, 0, 0)
            if world.budget then world.reusedCooldownDurations[spellID] = duration end
            duration.secret = world.secretCooldowns
            duration.startTime, duration.total = active and cooldown.startTime or 0, active and cooldown.total or 0
            return duration
        end,
        GetSpellInfo = function(spellID)
            if IsSecret(spellID) then return { name = S("string"), castTime = S(), iconID = S() } end
            local info = world.budget and world.reusedSpellInfo[spellID]
                or { name = "Spell " .. tostring(spellID), iconID = 1 }
            if world.budget then world.reusedSpellInfo[spellID] = info end
            info.castTime = world.castTimes[spellID] or 0
            return info
        end,
        GetSpellName = function(spellID) if IsSecret(spellID) then return S("string") end return "Spell " .. spellID end,
        GetSpellTexture = function(spellID) if IsSecret(spellID) then return S(), S() end return 1, 1 end,
        DoesSpellExist = function() return true end,
        IsCurrentSpell = function() return world.secretCasts and S("boolean") or false end,
    }
    env.C_SpellBook = { IsSpellKnownOrInSpellBook = function() return true end }
    env.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 62 end,
    }
    env.C_NamePlate = { GetNamePlateForUnit = function() return nil end }
    env.GetNetStats = function() return 0, 0, 40, 60 end
    env.GetCVar = function(name)
        if name == "SpellQueueWindow" then return "400" end
        return nil
    end
    env.GetCVarBool = function() return false end
    env.SetCVar = function() end

    -- Duration, text binding and formatter objects.
    env.C_DurationUtil = {
        CreateDuration = function() return NewDuration(world, false, 0, 0) end,
        CreateDurationTextBinding = function()
            local binding = { enabled = false }
            function binding:SetFontString(fs) self.fontString = fs end
            function binding:SetUpdateInterval() end
            function binding:SetTextFormat(format, properties) self.format, self.properties = format, properties end
            function binding:SetDuration(duration) self.duration = duration end
            function binding:SetEnabled(enabled) self.enabled = enabled == true end
            function binding:Disable() self.enabled = false end
            function binding:SetExpiredText() end
            function binding:SetZeroDurationText() end
            function binding:UpdateFontString()
                if self.fontString and self.duration then
                    self.fontString.text = self.duration.secret and S("string") or "1.0"
                end
            end
            return binding
        end,
    }
    env.C_StringUtil = {
        CreateNumericRuleFormatter = function() return { SetBreakpoints = function() end } end,
        TruncateWhenZero = function(value) if IsSecret(value) then return S("string") end return tostring(value) end,
        WrapString = function(infix, prefix, suffix)
            if AnySecret(infix, prefix, suffix) then return S("string") end
            return (prefix or "") .. (infix or "") .. (suffix or "")
        end,
    }
    env.Enum = rawget(env, "Enum") or {}
    env.Enum.DurationTextBindingProperty = { RemainingDuration = 0, ElapsedDuration = 1, TotalDuration = 2 }
    env.Enum.NumericRuleFormatRounding = { Nearest = 0, Floor = 1, Ceil = 2 }
    env.Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
    env.Enum.StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 }
    env.MAX_BOSS_FRAMES = 5
end

-- Widget methods the shared stubs lack, written as client C sinks.
local function InstallWidgets(world)
    local Methods = world.widgets.Methods
    local plainSetText = Methods.SetText
    function Methods:SetText(text)
        world.counts.SetText = world.counts.SetText + 1
        return plainSetText(self, text)
    end
    function Methods:SetFormattedText(format, ...)
        world.counts.SetText = world.counts.SetText + 1
        if AnySecret(format, ...) then self.text = S("string") return end
        self.text = string.format(format, ...)
    end
    local plainStringWidth = Methods.GetStringWidth
    function Methods:GetStringWidth()
        if IsSecret(self.text) then return S() end
        return plainStringWidth(self)
    end
    -- Budget mode: the stubs' setters that build a table per call reuse one
    -- per widget, and points come from a per-widget pool.
    if world.budget then
        local function Reuse(widget, field, a, b, c, d)
            local t = rawget(widget, field)
            if not t then t = {}; widget[field] = t end
            t[1], t[2], t[3], t[4] = a, b, c, d
            return t
        end
        local fourTuple = { SetStatusBarColor = "color", SetVertexColor = "vertexColor", SetTextColor = "textColor",
            SetShadowColor = "shadowColor", SetBackdropColor = "backdropColor",
            SetBackdropBorderColor = "backdropBorderColor", SetSwipeColor = "swipeColor" }
        for method, field in pairs(fourTuple) do
            Methods[method] = function(self, r, g, b, a) Reuse(self, field, r, g, b, a) end
        end
        function Methods:SetColorTexture(r, g, b, a)
            Reuse(self, "colorTexture", r, g, b, a)
            Reuse(self, "vertexColor", r, g, b, a)
        end
        function Methods:SetTexCoord(a, b, c, d) Reuse(self, "texCoord", a, b, c, d) end
        function Methods:SetShadowOffset(x, y) Reuse(self, "shadowOffset", x, y) end
        function Methods:SetOffset(x, y) Reuse(self, "offset", x, y) end
        function Methods:SetPoint(point, relativeTo, relativePoint, x, y)
            if type(relativeTo) == "string" or type(relativeTo) == "number" then
                relativeTo, relativePoint, x, y = self.parent, point, relativeTo, relativePoint
            end
            local pool = rawget(self, "pointPool")
            if not pool then pool = {}; self.pointPool = pool end
            local entry = pool[#pool]
            if entry then pool[#pool] = nil else entry = {} end
            entry.point, entry.relativeTo, entry.relativePoint = point, relativeTo, relativePoint or point
            entry.x, entry.y = x or 0, y or 0
            self.points[#self.points + 1] = entry
        end
        function Methods:ClearAllPoints()
            local pool = rawget(self, "pointPool")
            if not pool then pool = {}; self.pointPool = pool end
            for index = #self.points, 1, -1 do
                pool[#pool + 1] = self.points[index]
                self.points[index] = nil
            end
            self.allPoints = false
        end
    end
    -- A bar bound to a secret duration reads its range and value back secret.
    local function SecretTimer(bar) local timer = bar.timerDuration return timer ~= nil and timer.secret == true end
    local plainSetValue = Methods.SetValue
    function Methods:SetValue(value)
        world.counts.SetValue = world.counts.SetValue + 1
        return plainSetValue(self, value)
    end
    function Methods:GetValue()
        if SecretTimer(self) then return S() end
        return self.value or 0
    end
    function Methods:GetMinMaxValues()
        if SecretTimer(self) then return S(), S() end
        return self.minimum or 0, self.maximum or 1
    end
    function Methods:SetTimerDuration(duration, interpolation, direction)
        world.counts.SetTimerDuration = world.counts.SetTimerDuration + 1
        -- The bar snapshots the duration's contents (a value type); budget
        -- mode keeps the reference.
        if world.budget then self.timerDuration = duration
        else self.timerDuration = duration and duration:Copy() or nil end
        self.timerDirection = direction
    end
    function Methods:ClearTimerDuration() self.timerDuration = nil end
    function Methods:SetVertexColorFromBoolean(value, ifTrue, ifFalse)
        self.vertexBoolean, self.vertexIfTrue, self.vertexIfFalse = value, ifTrue, ifFalse
    end
    function Methods:SetAlphaFromBoolean(value, ifTrue, ifFalse)
        self.alphaBoolean, self.alphaIfTrue, self.alphaIfFalse = value, ifTrue, ifFalse
    end
    -- A Cooldown frame runs its OnCooldownDone when the bound duration ends
    -- (the harness knows the end of a secret duration; addon code does not).
    function Methods:SetCooldownFromDurationObject(duration)
        self.cooldownDuration = duration
        self.cooldownEnd = duration.startTime + duration.total
        self.cooldownArmed = duration.total > 0
        world.cooldownFrames[self] = true
    end
    function Methods:Clear() self.cooldownArmed = false end
    function Methods:SetDrawBling() end
    function Methods:EnableKeyboard() end
    function Methods:SetPropagateKeyboardInput() end
    function Methods:SetRotatesTexture() end
    function Methods:SetFixedFrameStrata() end
    function Methods:SetFixedFrameLevel() end
    function Methods:SetRoundLayoutToNearestPixel() end
    function Methods:SetSnapToPixelGrid() end
    function Methods:SetTexelSnappingBias() end
    function Methods:SetExpiredText() end
    function Methods:GetBottom() return self.bottom or 0 end
    function Methods:GetLeft() return self.left or 0 end
    function Methods:GetEffectiveScale() return 1 end
    function Methods:SetMaskTexture() end
    function Methods:SetCountdownFormatter() end
    -- The client runs OnShow/OnHide when the visibility flips.
    function Methods:Show()
        if self.shown then return end
        self.shown = true
        local script = self.scripts.OnShow
        if script then script(self) end
    end
    function Methods:Hide()
        if not self.shown then return end
        self.shown = false
        local script = self.scripts.OnHide
        if script then script(self) end
    end
    function Methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
end

--- options:
---   flavor       "Mainline" (default) or "Forever"
---   playerClass  the player's class token (default "MAGE")
---   setup        function(env, world) run after the client model, before boot
---   budget       reuse every object a native would return and every secret,
---                so allocation measurements see only the addon's own
function SecretWorld.New(root, options)
    options = options or {}
    root = Normalize(root):gsub("/$", "")
    Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
    -- Before any addon or harness file captures type/tonumber/tostring.
    Secrets.Install()
    -- The one operation the client allows that the shared helper refuses:
    -- concatenating a secret string with a string or number yields a secret
    -- string (the unit text formatter relies on it). Everything else stays
    -- strict.
    local secretMeta = getmetatable(Secrets.New("string"))
    local rawtype = rawget(_G, "__msufRawType") or type
    secretMeta.__concat = function(left, right)
        for _, operand in ipairs({ left, right }) do
            if not Secrets.IsSecret(operand) then
                local kind = rawtype(operand)
                if kind ~= "string" and kind ~= "number" then error("attempt to concatenate a secret value", 2) end
            end
        end
        return Secrets.New("string")
    end
    local ClientWorld = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
    local base = ClientWorld.New(root, options.flavor or "Mainline")
    local world = setmetatable({
        root = root,
        base = base,
        env = base.env,
        core = base.core,
        widgets = base.widgets,
        clock = 100,
        timers = {},
        casting = {},
        channeling = {},
        cooldowns = {},
        castTimes = {},
        dead = {},
        combat = false,
        exists = { player = true, target = true, focus = true },
        secretCasts = true,
        secretCooldowns = true,
        counts = setmetatable({}, { __index = function() return 0 end }),
        errors = {},
        timerSequence = 0,
        timerCount = 0,
        harnessBytes = 0,
        cooldownFrames = {},
        Secrets = Secrets,
        playerClass = options.playerClass or "MAGE",
        budget = options.budget == true,
        reusedCooldownInfo = {},
        reusedCooldownDurations = {},
        reusedSpellInfo = {},
    }, SecretWorld)
    reusedSecrets = world.budget and {} or nil
    for index = 1, 5 do world.exists["boss" .. index] = true end
    for index = 1, 3 do world.exists["arena" .. index] = true end
    InstallClient(world, world.env)
    InstallWidgets(world)
    if world.budget then
        -- tostring of a secret is a secret string; reuse one.
        local plainToString = world.env.tostring
        world.env.tostring = function(value)
            if IsSecret(value) then return S("string") end
            return plainToString(value)
        end
    end
    if options.setup then options.setup(world.env, world) end

    local corePaths = ClientWorld.Graph(root, ClientWorld.CoreTOC(base.client.tocSuffix or options.flavor or "Mainline"),
        "enUS", base.client.isForever and "camelot" or nil)
    base.corePaths = corePaths
    base:LoadGraph("MidnightSimpleUnitFrames", corePaths, base.core)
    local failure = base:FirstFailure()
    if failure then error("castbar secret world: " .. failure.file .. ": " .. failure.message, 2) end
    world.corePaths = corePaths
    return world
end

--- Lua VM instructions fn executes inside addon files (MidnightSimpleUnitFrames/),
--- harness code excluded: a call/return hook keeps a stack of "is this frame
--- addon code", and the count hook adds an instruction only while the top is.
function SecretWorld:AddonInstructions(fn, ...)
    local prefix = "@" .. self.root .. "/MidnightSimpleUnitFrames/"
    local stack, top, count = {}, 0, 0
    local cache = {}
    local getinfo = debug.getinfo
    local function IsAddon(source)
        local known = cache[source]
        if known == nil then
            known = source:sub(1, #prefix) == prefix
            cache[source] = known
        end
        return known
    end
    -- The frame that runs fn itself is harness code.
    top = 1
    stack[1] = false
    debug.sethook(function(event)
        if event == "count" then
            if stack[top] then count = count + 1 end
        elseif event == "call" then
            local info = getinfo(2, "S")
            top = top + 1
            stack[top] = info ~= nil and IsAddon(info.source)
        else
            -- "return" and "tail return" each close one frame.
            if top > 1 then top = top - 1 end
        end
    end, "cr", 1)
    fn(...)
    debug.sethook()
    return count
end

--- Source paths of every castbar file this client loads (Castbars/**, the
--- castbar parts of Game/**).
function SecretWorld:CastbarPaths()
    local list = {}
    for index = 1, #self.corePaths do
        local path = self.corePaths[index]
        if path:find("/Castbars/", 1, true) or path:find("/Game/Forever/SwingTimer.lua", 1, true) then
            list[#list + 1] = path
        end
    end
    return list
end

--- Runs every timer due at the current clock, earliest deadline first (ties
--- in arming order). A timer armed while this pass runs waits for the next
--- rendered frame, as in the client (the clock does not move inside one frame).
function SecretWorld:RunDue()
    local last = self.timerSequence
    local timers = self.timers
    for _ = 1, 20000 do
        local best, bestIndex
        for index = 1, self.timerCount do
            local timer = timers[index]
            if timer.sequence <= last and timer.due <= self.clock + 1e-9
                and (not best or timer.due < best.due or (timer.due == best.due and timer.sequence < best.sequence)) then
                best, bestIndex = timer, index
            end
        end
        if not best then return end
        timers[bestIndex] = timers[self.timerCount]
        timers[self.timerCount] = false
        self.timerCount = self.timerCount - 1
        local fn, handle, period = best.fn, best.handle, best.period
        self.ReleaseTimer(best)
        if not (handle and handle.cancelled) then
            local ok, message = pcall(fn, handle or nil)
            if not ok then self.errors[#self.errors + 1] = tostring(message) end
            if handle then
                if handle.remaining then handle.remaining = handle.remaining - 1 end
                if period and not handle.cancelled and (not handle.remaining or handle.remaining > 0) then
                    self.QueueTimer(period, fn, handle, period)
                end
            end
        end
    end
    local sources = {}
    for index = 1, math.min(5, self.timerCount) do
        local info = debug.getinfo(self.timers[index].fn, "S")
        sources[#sources + 1] = info.short_src .. ":" .. info.linedefined
    end
    error("timer storm: " .. table.concat(sources, ", "))
end

local function CastbarScript(fn)
    local source = debug.getinfo(fn, "S").source
    return source:find("/Castbars/", 1, true) or source:find("MSUF_Scheduler.lua", 1, true)
        or source:find("SwingTimer.lua", 1, true)
end

--- One rendered frame: due timers, Cooldown completions, then every shown
--- castbar or scheduler OnUpdate script, then due timers again.
function SecretWorld:Frame()
    self:RunDue()
    for frame in pairs(self.cooldownFrames) do
        if frame.cooldownArmed and self.clock >= frame.cooldownEnd then
            frame.cooldownArmed = false
            local done = frame.scripts.OnCooldownDone
            if done then
                local ok, message = pcall(done, frame)
                if not ok then self.errors[#self.errors + 1] = tostring(message) end
            end
        end
    end
    local frames = self.widgets.frames
    for index = 1, #frames do
        local frame = frames[index]
        local onUpdate = rawget(frame, "scripts") and frame.scripts.OnUpdate
        if onUpdate and frame.shown and CastbarScript(onUpdate) then
            local ok, message = pcall(onUpdate, frame, STEP)
            if not ok then self.errors[#self.errors + 1] = tostring(message) end
        end
    end
    self:RunDue()
end

function SecretWorld:Advance(seconds)
    local target = self.clock + seconds
    repeat
        self:Frame()
        if self.clock >= target - 1e-9 then break end
        self.clock = math.min(target, self.clock + STEP)
    until false
end

function SecretWorld:StartCast(unit, name, seconds, castBarID, extra)
    local startMS = math.floor(self.clock * 1000)
    local cast = { name = name, startMS = startMS, endMS = startMS + seconds * 1000, spellID = 133,
        castBarID = castBarID }
    for key, value in pairs(extra or {}) do cast[key] = value end
    self.casting[unit] = cast
    return cast
end

function SecretWorld:StartChannel(unit, name, seconds, castBarID, extra)
    local startMS = math.floor(self.clock * 1000)
    local cast = { name = name, startMS = startMS, endMS = startMS + seconds * 1000, spellID = 15407,
        castBarID = castBarID }
    for key, value in pairs(extra or {}) do cast[key] = value end
    self.channeling[unit] = cast
    return cast
end

--- A UNIT_SPELLCAST_* payload as the client builds it: the unit token and
--- castBarID plain, castGUID / spellID / interruptedBy secret.
function SecretWorld:Payload(event, unit, castBarID, interrupted)
    local guid, spell = S("string"), S()
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        return unit, guid, spell, interrupted and S("string") or nil, castBarID
    end
    if event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        return unit, guid, spell, S("boolean"), interrupted and S("string") or nil, castBarID
    end
    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        return unit
    end
    return unit, guid, spell, castBarID
end

--- The frame created under a name (the shared stubs do not publish names).
function SecretWorld:Named(name)
    local frames = self.widgets.frames
    for index = 1, #frames do
        if frames[index].frameName == name then return frames[index] end
    end
end

--- Delivers an event to one frame the way the client does: its OnEvent script
--- first, then every HookScript handler.
function SecretWorld:Fire(frame, event, ...)
    -- HookScript chains into the script in the shared stubs.
    local scripts = rawget(frame, "scripts")
    local script = scripts and scripts.OnEvent
    if script then script(frame, event, ...) end
end

--- Delivers an event to every castbar frame registered for it.
function SecretWorld:Broadcast(event, ...)
    local frames = self.widgets.frames
    local snapshot = {}
    for index = 1, #frames do snapshot[index] = frames[index] end
    for index = 1, #snapshot do
        local frame = snapshot[index]
        local events = rawget(frame, "events")
        local scripts = rawget(frame, "scripts")
        if events and events[event] and scripts and scripts.OnEvent and CastbarScript(scripts.OnEvent) then
            self:Fire(frame, event, ...)
        end
    end
end

return SecretWorld

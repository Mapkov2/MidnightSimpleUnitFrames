-- Sparse profile fields. Used only for explicit edits, imports and profile/context
-- transitions; no frame, timer or gameplay event belongs to this data layer.
local _, MSUF = ...
local F = {}
MSUF.ProfileFields = F
-- The one registry of profile roots variants and sync work on, each with the
-- sync module that owns it (general is split per key by ProfileSync, and
-- suiteModules belongs to its providers). A feature that keeps settings in a
-- new profile root adds the root here, or variants and sync miss its edits.
local ROOT_MODULES = {
    bars="unitframes", shortenNames="unitframes", player="unitframes", target="unitframes",
    targettarget="unitframes", focus="unitframes", focustarget="unitframes", pet="unitframes",
    pettarget="unitframes", boss="unitframes", arena="unitframes",
    gf_party="groupframes", gf_raid="groupframes", gf_mythicraid="groupframes", gf_priority="groupframes",
    classColors="colors", npcColors="colors", gameplay="gameplay", swingTimers="gameplay",
    auras2="auras", auras3="auras", classPowerPerSpec="resources", classPowerPresets="resources",
}
for i=1,5 do ROOT_MODULES["boss"..i], ROOT_MODULES["arena"..i] = "unitframes", "unitframes" end
local ROOTS = { general=true, suiteModules=true }
for root in pairs(ROOT_MODULES) do ROOTS[root] = true end
-- Roots that hold one value instead of a table; their path is the root alone.
local SCALAR_ROOTS = { shortenNames=true }
F.RootModules, F.ScalarRoots = ROOT_MODULES, SCALAR_ROOTS

-- The one owner registry for keys under profile.general. Partial profile
-- exports and imports (Unit Frames, Castbars, Colors) carry exactly the keys
-- their owner names, and profile sync asks the same owner. An owner names the
-- partial export kinds that carry its keys and the sync module that owns them:
--   unitframes     Unit Frames export (also the owner of undeclared plain keys)
--   castbars       Castbars export
--   colors         Colors export
--   castbarColors  Colors export; synced with the castbars
--   auraColors     Unit Frames and Colors exports; synced with the auras
--   profile        no partial export: the menu, the slash menu, integrations,
--                  Blizzard Edit Mode and the global UI scale stay with their
--                  profile and travel only with a full profile export
local GENERAL_OWNERS = {
    unitframes = { kinds = { unitframe = true }, sync = "unitframes" },
    castbars = { kinds = { castbar = true }, sync = "castbars" },
    colors = { kinds = { colors = true }, sync = "colors" },
    castbarColors = { kinds = { colors = true }, sync = "castbars" },
    auraColors = { kinds = { unitframe = true, colors = true }, sync = "auras" },
    profile = { kinds = {} },
}
local GENERAL_OWNER = {}
local function DeclareGeneral(owner, words)
    for key in words:gmatch("%S+") do GENERAL_OWNER[key] = owner end
end
DeclareGeneral("profile", [[
    UIScale locale menuLocale menuFontKey hideAdvancedMenu showGameMenuButton slashMenuScale
    slashMenuSnapEnabled disableScaling globalUiScalePreset globalUiScaleValue
    blizzardEditModeIntegration blizzardEditModeSnapshot dandersEditModeIntegration
    detailsEditModeIntegration dominosEditModeIntegration ellesmereEditModeIntegration
    grid2EditModeIntegration nsrtNicknameIntegration
]])
DeclareGeneral("auraColors", "aurasOwnBuffHighlightColor aurasOwnDebuffHighlightColor aurasStackCountColor")
DeclareGeneral("castbarColors", [[
    castbarInterruptColor castbarInterruptibleColor castbarNonInterruptibleColor empowerColorStages
]])
-- Unit frame settings whose names read like colours to the fallback rule.
DeclareGeneral("unitframes", [[
    useBarBorder portraitFillBorder dispelBorderTrigger fontSlug fontTextAlpha editModeBgAlpha
    hpBarAlpha powerBarAlpha hpBgAlpha powerBarBgAlpha alphaExcludeTextPortrait alphaExcludePredictionBars
]])
DeclareGeneral("colors", [[
    absorbBarColorMigrationV2 barBgClassColor barBgColorMode barBgMatchHPColor barMode
    bossTargetHighlightColor classBarBgR classBarBgG classBarBgB colorHealthTextByHealth
    colorPowerTextByType darkBarTone darkBgBrightness darkBgCustomColor darkMode
    enableHealthGradient fontColor fontColorCustomR fontColorCustomG fontColorCustomB
    gradientStrength healthBarGradientColorR healthBarGradientColorG healthBarGradientColorB
    healthGradientHighR healthGradientHighG healthGradientHighB healthGradientLowR
    healthGradientLowG healthGradientLowB healthGradientMidR healthGradientMidG healthGradientMidB
    healthLossColorR healthLossColorG healthLossColorB highlightColor kickNotReadyColor kickReadyColor
    nameClassColor nameNpcClassColor npcClassColorBar npcColorMode npcNameRed npcTypeColorBar
    npcTypeColorText portraitBgColorR portraitBgColorG portraitBgColorB portraitBgColorA
    portraitBorderColorR portraitBorderColorG portraitBorderColorB portraitBorderColorA
    powerBarGradientColorR powerBarGradientColorG powerBarGradientColorB powerLossColorR
    powerLossColorG powerLossColorB tempMaxHealthColorR tempMaxHealthColorG tempMaxHealthColorB
    useClassColors useCustomFontColor
]])

-- Every key whose name holds castbar, bossCast, arenaCast or empower is a
-- castbars key (castbarColors when it is a colour) without a row of its own.
-- Any other undeclared key (a migration stamp, a key a menu writes but no
-- default seeds) is decided by the name rule the exports used before this
-- registry; general_key_ownership_smoke requires a row for every seeded key
-- that rule would not place in unitframes or castbars.
local function FallbackGeneralOwner(key)
    local lower = key:lower()
    if lower:find("menu", 1, true) or lower:find("slash", 1, true) or lower:find("integration", 1, true)
        or lower:find("blizzardeditmode", 1, true) then return "profile" end
    local castbar = lower:find("castbar", 1, true) or lower:find("bosscast", 1, true)
        or lower:find("arenacast", 1, true) or lower:find("empower", 1, true)
        or lower:find("spellnamefontsize", 1, true) or lower:find("timefontsize", 1, true)
    local color = lower:find("color", 1, true) or lower == "barmode" or lower == "darkmode"
        or lower == "darkbartone" or lower == "darkbgbrightness" or lower == "enablehealthgradient"
        or lower == "gradientstrength" or lower == "npcnamered"
    if not color then
        local last = lower:sub(-1)
        if last == "r" or last == "g" or last == "b" or last == "a" then
            color = lower:find("font", 1, true) or lower:find("bg", 1, true) or lower:find("border", 1, true)
                or lower:find("outline", 1, true) or lower:find("gradient", 1, true)
        end
    end
    if castbar then return color and "castbarColors" or "castbars" end
    return color and "colors" or "unitframes"
end
F.FallbackGeneralOwner = FallbackGeneralOwner

-- The owner of profile.general[key]: its declaration, else the fallback rule.
function F.GeneralOwner(key)
    if type(key) ~= "string" then return nil end
    return GENERAL_OWNER[key] or FallbackGeneralOwner(key)
end
function F.IsDeclaredGeneralKey(key)
    return GENERAL_OWNER[key] ~= nil
end
-- Whether a partial export kind ("unitframe", "castbar", "colors") carries the key.
function F.GeneralKeyInKind(key, kind)
    local owner = GENERAL_OWNERS[F.GeneralOwner(key)]
    return owner ~= nil and owner.kinds[kind] == true
end
-- The profile sync module that owns the key, nil for a profile-local key.
function F.GeneralSyncOwner(key)
    local owner = GENERAL_OWNERS[F.GeneralOwner(key)]
    return owner and owner.sync
end
-- A unit frame's own on/off switch (player.enabled, boss.enabled, ...). Variants
-- record and apply it like any field; the Factory keeps a frame a variant
-- switches attached while it is off, so it comes back without a reload.
local UNIT_ROOTS = { player=true, target=true, targettarget=true, focus=true, focustarget=true,
    pet=true, pettarget=true, boss=true, arena=true }
for i=1,5 do UNIT_ROOTS["boss"..i], UNIT_ROOTS["arena"..i] = true, true end
function F.UnitSwitchRoot(path)
    if type(path) == "table" and #path == 2 and path[2] == "enabled" and UNIT_ROOTS[path[1]] == true then
        return path[1]
    end
end
local function Scalar(value)
    local kind = type(value)
    return kind == "boolean" or (kind == "string" and #value <= 8192)
        or (kind == "number" and value == value and value > -math.huge and value < math.huge)
end
-- Numeric keys are list indexes and spell IDs (aura lists, spell indicators).
-- Spell IDs pass 1,000,000 on current clients, so the bound is the signed
-- 32-bit range the client's IDs live in.
local MAX_NUMERIC_KEY = 2147483647
local function Key(value)
    return (type(value) == "string" and #value > 0 and #value <= 128)
        or (type(value) == "number" and value >= 1 and value <= MAX_NUMERIC_KEY and value == math.floor(value))
end

function F.Path(path)
    if type(path) ~= "table" or getmetatable(path) ~= nil or #path > 12 or not ROOTS[path[1]]
        or #path < (SCALAR_ROOTS[path[1]] and 1 or 2) then return false end
    for i = 1, #path do
        if not Key(path[i]) or (type(path[i]) == "string" and path[i]:match("^_")) then return false end
    end
    for key in pairs(path) do
        if type(key) ~= "number" or key < 1 or key > #path or key ~= math.floor(key) then return false end
    end
    return true
end

function F.ID(path)
    local result = {}
    for i = 1, #path do
        local text = tostring(path[i])
        result[i] = type(path[i]):sub(1,1) .. #text .. ":" .. text
    end
    return table.concat(result, "|")
end

function F.Read(db, path)
    local value
    if F.ProfileRoot then value=F.ProfileRoot(db,path[1],false) else value=db[path[1]] end
    for i = 2, #path do
        if type(value) ~= "table" then return nil end
        value = value[path[i]]
    end
    return value
end

function F.Write(db, path, value)
    if #path==1 then db[path[1]]=value; return end
    local owner
    if F.ProfileRoot then owner=F.ProfileRoot(db,path[1],value~=nil)
    else
        owner=db[path[1]]
        if type(owner)~="table" and value~=nil then owner={}; db[path[1]]=owner end
    end
    if type(owner)~="table" then return end
    for i = 2, #path - 1 do
        local child = owner[path[i]]
        if type(child) ~= "table" then
            if value == nil then return end
            child = {}; owner[path[i]] = child
        end
        owner = child
    end
    owner[path[#path]] = value
end

function F.Copy(value, depth, seen, budget)
    if value == nil or Scalar(value) then return value, true end
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or (depth or 0) >= (budget and budget.maxDepth or 12) then return nil, false end
    seen, budget = seen or {}, budget or { count=0 }
    if seen[value] then return nil, false end
    seen[value] = true
    local out = {}
    for key, entry in pairs(value) do
        budget.count = budget.count + 1
        if not Key(key) or budget.count > (budget.limit or 16384) then seen[value]=nil; return nil, false end
        local copy, valid = F.Copy(entry, (depth or 0)+1, seen, budget)
        if not valid then seen[value]=nil; return nil, false end
        out[key] = copy
    end
    seen[value] = nil
    return out, true
end

-- Complete saved/native profile snapshots are not sparse imported patches.
-- Native Edit Mode settings legitimately use enum keys such as zero. A failed
-- copy also returns why: "number" (not finite), "value" (cannot be saved),
-- "cycle" (a table inside itself) or "limits".
function F.CopySnapshot(value, budget)
    budget=budget or {count=0,limit=131072,maxDepth=32,bytes=0,maxBytes=8388608}
    budget.bytes=budget.bytes or 0
    local why
    local function Copy(entry,depth,seen)
        local kind=type(entry)
        if kind=="string" then
            budget.bytes=budget.bytes+#entry
            if budget.bytes>(budget.maxBytes or 8388608) then why="limits"; return nil,false end
            return entry,true
        end
        if entry==nil or kind=="boolean" or kind=="number" and Scalar(entry) then return entry,true end
        if kind=="number" then why="number"; return nil,false end
        if kind~="table" or getmetatable(entry)~=nil then why="value"; return nil,false end
        if seen[entry] then why="cycle"; return nil,false end
        if depth>=(budget.maxDepth or 32) then why="limits"; return nil,false end
        seen[entry]=true
        local out={}
        for key,item in pairs(entry) do
            local keyKind=type(key)
            if keyKind~="string" and keyKind~="boolean" and not (keyKind=="number" and Scalar(key)) then
                why=keyKind=="number" and "number" or "value"; return nil,false
            end
            if keyKind=="string" then budget.bytes=budget.bytes+#key end
            budget.count=budget.count+1
            if budget.count>(budget.limit or 131072) or budget.bytes>(budget.maxBytes or 8388608) then why="limits"; return nil,false end
            local copied,valid=Copy(item,depth+1,seen)
            if not valid then return nil,false end
            out[key]=copied
        end
        seen[entry]=nil
        return out,true
    end
    local copy,valid=Copy(value,0,{})
    return copy,valid,why
end

function F.Equal(a, b, depth)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    if (depth or 0) >= 12 then return false end
    for key, value in pairs(a) do if not F.Equal(value,b[key],(depth or 0)+1) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- Imported patches are copied before use and cannot contain expressions,
-- metatables, cyclic values, non-finite numbers or overlapping parent paths.
function F.ValidatePatch(patch)
    if type(patch) ~= "table" or #patch > 512 then return nil, "too many fields" end
    local clean, ids = {}, {}
    for key in pairs(patch) do
        if type(key) ~= "number" or key < 1 or key > #patch or key ~= math.floor(key) then return nil, "invalid field list" end
    end
    for i = 1, #patch do
        local entry = patch[i]
        if type(entry) ~= "table" or getmetatable(entry) ~= nil or not F.Path(entry.path) then return nil, "invalid setting path" end
        local path = F.Copy(entry.path)
        local id = F.ID(path)
        if ids[id] then return nil, "duplicate setting path" end
        ids[id] = true
        local value, valid = F.Copy(entry.value)
        if not valid or (value == nil and entry.remove ~= true)
            or (value ~= nil and entry.remove == true) then return nil, "invalid setting value" end
        clean[i] = { path=path, value=value, remove=entry.remove == true }
    end
    for _, entry in ipairs(clean) do
        local prefix = {}
        for i = 1, #entry.path - 1 do
            prefix[i] = entry.path[i]
            if ids[F.ID(prefix)] then return nil, "overlapping setting paths" end
        end
    end
    table.sort(clean, function(a,b) return F.ID(a.path) < F.ID(b.path) end)
    return clean
end

-- Diff only known settings roots. Metadata, migrations and session caches never
-- become variant fields. Numeric table keys retain their type in saved patches.
function F.Diff(before, after)
    local patch, path, failed, skipped = {}, {}, false, 0
    local function Visit(a,b,depth)
        if failed or F.Equal(a,b) then return end
        if depth > 12 or #patch >= 512 then failed=true; return end
        if type(a) == "table" and type(b) == "table" then
            local keys = {}
            for key in pairs(a) do keys[key]=true end
            for key in pairs(b) do keys[key]=true end
            for key in pairs(keys) do
                if Key(key) and not (type(key)=="string" and key:match("^_")) then
                    path[depth+1]=key; Visit(a[key],b[key],depth+1); path[depth+1]=nil
                elseif not Key(key) and not F.Equal(a[key],b[key]) then
                    -- A change under a key a field path cannot name (an enum
                    -- zero, a long string) is counted, never dropped silently.
                    skipped = skipped + 1
                end
            end
        elseif depth >= 2 then
            local value, valid = F.Copy(b)
            if not valid then failed=true; return end
            patch[#patch+1] = { path=F.Copy(path), value=value, remove=b==nil }
        end
    end
    for root in pairs(ROOTS) do
        path[1]=root
        if SCALAR_ROOTS[root] then
            local a, b = before[root], after[root]
            if a ~= b and type(a) ~= "table" and type(b) ~= "table" and (b == nil or Scalar(b)) then
                patch[#patch+1] = { path={ root }, value=b, remove=b==nil }
            end
        else
            Visit(before[root] or {}, after[root] or {}, 1)
        end
    end
    if failed then return nil, "variant exceeds field limits" end
    local clean, why = F.ValidatePatch(patch)
    return clean, why, skipped
end

function F.Overlaps(path, other)
    for i = 1, math.min(#path,#other) do if path[i] ~= other[i] then return false end end
    return true
end

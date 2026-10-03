-- group_raid_header_blizzard_smoke.lua <repoRoot>
--
-- The real UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua against Blizzard's
-- real Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua, read per client
-- branch (live, forever, classic, classic_anniversary, classic_era) from the UI
-- mirror at _local_workflows/references/wow-ui-source. Without the mirror (the
-- self-contained CI gate) only the attribute contracts below are checked.
--
-- 1. Flat raid header, member joins in combat. SecureGroupHeader re-lays itself
--    out on GROUP_ROSTER_UPDATE in lockdown, where MSUF's SetupHeader defers,
--    and shows at most unitsPerColumn * maxColumns units (configureChildren).
--    maxColumns must therefore carry the configured cap, not the live count:
--    with a count-sized cap the eleventh member of a ten-member raid got no
--    frame (INDEX), or pushed an existing member out (GROUP, ROLE, NAME).
-- 2. Mythic "Hide groups 5-8" with preserved groups and the raid-wide role
--    fill: the role fill ignores the block cap but must keep subgroups 5-8
--    (the bench) out of the name lists; they used to take the slots of active
--    raiders in subgroups 1-4.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local HEADERS = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"
local MIRROR = root .. "/_local_workflows/references/wow-ui-source"
local SGH_PATH = "Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua"
local BRANCHES = { "live", "forever", "classic", "classic_anniversary", "classic_era" }

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function MirrorPresent()
    for _, path in ipairs({ MIRROR .. "/.git/HEAD", MIRROR .. "/.git" }) do
        local file = io.open(path, "rb")
        if file then
            file:close()
            return true
        end
    end
    return false
end

-- One `git cat-file --batch` for every branch: each git start in the mirror
-- costs about a second.
local function ReadBranches()
    local names = {}
    for index, branch in ipairs(BRANCHES) do names[index] = "upstream/" .. branch .. ":" .. SGH_PATH end
    local feed = package.config:sub(1, 1) == "\\"
        and ('cmd /d /c "echo ' .. table.concat(names, "&echo ") .. '"')
        or ("printf '%s\\n' " .. table.concat(names, " "))
    local pipe = assert(io.popen(feed .. '|git -C "' .. MIRROR .. '" cat-file --batch', "rb"))
    local out = pipe:read("*a")
    pipe:close()
    local runs, position = {}, 1
    for index, name in ipairs(names) do
        local kind, size, body = out:match("^%x+ (%a+) (%d+)\n()", position)
        Check(kind == "blob", "the Blizzard UI mirror has no " .. name)
        local source = out:sub(body, body + size - 1)
        Check(source:find("function SecureGroupHeader_Update", 1, true) ~= nil, name .. " has no SecureGroupHeader_Update")
        runs[index] = { label = BRANCHES[index], source = source }
        position = body + size + 1
    end
    return runs
end

-- The client's string/table extensions SecureGroupHeaders.lua captures at load.
string.trim = string.trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
table.wipe = table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local Frame = {}
Frame.__index = Frame
function Frame:SetAttribute(key, value) self._attr[key] = value end
function Frame:GetAttribute(key) return self._attr[key] end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() return self._shown end
function Frame:GetName() return self._name end
function Frame:GetParent() return self._parent end
function Frame:SetParent(parent) self._parent = parent end
function Frame:SetWidth(width) self._w = width end
function Frame:SetHeight(height) self._h = height end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:SetSize(width, height) self._w, self._h = width, height end
function Frame:GetRect() return nil end
function Frame:GetCenter() return 0, 0 end
function Frame:GetEffectiveScale() return 1 end
local function Noop() end
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "EnableMouse", "SetClampedToScreen", "RegisterEvent",
    "UnregisterAllEvents", "HookScript", "SetScript", "SetAlpha" }) do
    Frame[name] = Noop
end

-- One isolated client: its own globals, roster and MSUF namespace, with the real
-- Headers.lua (and the real SecureGroupHeaders.lua when given) loaded into it.
local function NewWorld(sghSource, conf, liveKind, mythic)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local world = { env = env, conf = conf, roster = {}, combat = false }
    env.InCombatLockdown = function() return world.combat end
    env.issecretvalue = function() return false end
    env.scrub = function(...) return ... end
    env.GetFrameHandle = function(frame) return frame end
    env.GetManagedEnvironment = function() return {} end
    env.CallRestrictedClosure = Noop
    env.CLASS_SORT_ORDER = { "WARRIOR", "PRIEST" }
    env.strsplit = function(separator, text)
        local out = {}
        for piece in (text .. separator):gmatch("(.-)" .. separator:gsub("%p", "%%%0")) do out[#out + 1] = piece end
        return unpack(out)
    end
    local function NewFrame(name, parent)
        local frame = setmetatable({ _attr = {}, _shown = false, _name = name, _parent = parent, _w = 0, _h = 0 }, Frame)
        if name then env[name] = frame end
        return frame
    end
    env.CreateFrame = function(frameType, name, parent)
        local frame = NewFrame(name, parent)
        if frameType == "Button" then frame._w, frame._h = 80, 32 end
        return frame
    end
    env.UIParent = NewFrame("UIParent")
    env.UIParent._shown = true

    local roster = world.roster
    env.GetNumGroupMembers = function() return #roster end
    env.GetNumSubgroupMembers = function() return 4 end
    env.IsInRaid = function() return true end
    env.IsInGroup = function() return true end
    env.GetRaidRosterInfo = function(index)
        local member = roster[index]
        if not member then return nil end
        return member.name, 0, member.group, 80, "Warrior", member.class, "zone", true, false, nil, nil, member.role
    end
    env.UnitExists = function() return true end
    env.UnitName = function(unit) return unit end
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.UnitGroupRolesAssigned = function(unit)
        local member = roster[tonumber(unit:match("%d+") or 0)]
        return member and member.role or "NONE"
    end
    env.GetPartyAssignment = function() return false end
    env.UnitGUID = function(unit) return unit end

    local MSUF = {
        Client = { IsClassic = false, Family = "Mainline" },
        Secrets = { UnitMissing = function() return false end },
    }
    local GF = {
        GetLiveGroupKind = function() return liveKind end,
        GetLiveRaidKind = function() return liveKind end,
        IsMythicRaidContext = function() return mythic == true end,
        GetAnchorPoint = function() return "TOPLEFT" end,
        GetConf = function() return conf end,
        GroupFilterAllowsSubgroup = function(filter) return filter == nil end,
    }
    MSUF.GF = GF
    MSUF.UF = { IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end }
    local provided = {
        MSUF_PixelLayoutRegion = function(region) return region end,
        MSUF_SetRoundLayoutToNearestPixel = Noop,
    }
    MSUF.Require = function(name) return provided[name] end
    env.MSUF_UF_PointFraction = function() return 0, 1 end
    env.MSUF_UF_ClampBoxAxis = function() return 0 end

    if sghSource then
        local sgh = assert(loadstring(sghSource, "=SecureGroupHeaders.lua"))
        setfenv(sgh, env)
        sgh()
    end
    local headers = assert(loadfile(HEADERS))
    setfenv(headers, env)
    headers("MidnightSimpleUnitFrames", MSUF)
    world.GF = GF

    -- What OnShow / OnEvent(GROUP_ROSTER_UPDATE) run on a visible header.
    function world:Update(header)
        if not header:IsShown() then header:Show() end
        env.SecureGroupHeader_Update(header)
    end
    -- Roster names with a shown frame on `header`.
    function world:Shown(header, out)
        out = out or {}
        for index = 1, 40 do
            local child = header:GetAttribute("child" .. index)
            if not child then break end
            local unit = child._shown and child:GetAttribute("unit")
            if unit then out[roster[tonumber(unit:match("%d+"))].name] = true end
        end
        return out
    end
    return world
end

local function Add(roster, name, group, role, class)
    roster[#roster + 1] = { name = name, group = group, role = role or "DAMAGER", class = class or "WARRIOR" }
end

local function Missing(world, shown)
    local missing = {}
    for _, member in ipairs(world.roster) do
        if not shown[member.name] then missing[#missing + 1] = member.name end
    end
    return table.concat(missing, " ")
end

------------------------------------------------------------------ 1. combat join
local function FlatConf(mode)
    return {
        enabled = true, width = 80, height = 32, spacing = 1, growth = "DOWN",
        unitsPerColumn = 5, maxColumns = 8, preserveRaidGroups = false,
        sortMode = mode, showPlayer = true,
    }
end

local function CombatJoin(label, sghSource, mode)
    local world = NewWorld(sghSource, FlatConf(mode), "raid", false)
    for index = 1, 10 do Add(world.roster, "Member" .. index, index <= 5 and 1 or 2) end
    local header = world.GF.SetupHeader("raid", "raid")
    Check(header ~= nil and header._msufRaidGroupIndex == nil, label .. ": no flat raid header")
    Check(header:GetAttribute("unitsPerColumn") == 5 and header:GetAttribute("maxColumns") == 8,
        label .. ": a ten-member raid wrote maxColumns=" .. tostring(header:GetAttribute("maxColumns"))
        .. " instead of the configured cap 8; Blizzard's in-combat relayout cannot grow past it")
    if sghSource then
        world:Update(header)
        local shown = world:Shown(header)
        Check(Missing(world, shown) == "", label .. ": out of combat, no frame for " .. Missing(world, shown))
    end

    -- Lockdown: an eleventh member joins subgroup 1. MSUF must defer; only the
    -- header's own GROUP_ROSTER_UPDATE relayout runs.
    world.combat = true
    Add(world.roster, "Joiner", 1, "HEALER", "PRIEST")
    Check(world.GF.SetupHeader("raid", "raid") == nil, label .. ": SetupHeader did not defer in combat")
    if sghSource then
        world:Update(header)
        local shown = world:Shown(header)
        Check(Missing(world, shown) == "", label .. ": in combat, no frame for " .. Missing(world, shown))
    end
    world.combat = false

    -- The configured cap still binds: two columns of five show ten of eleven.
    world.conf.maxColumns = 2
    world.GF.SetupHeader("raid", "raid")
    Check(header:GetAttribute("maxColumns") == 2, label .. ": the configured column cap was not written")
    if sghSource then
        world:Update(header)
        local count = 0
        for _ in pairs(world:Shown(header)) do count = count + 1 end
        Check(count == 10, label .. ": maxColumns=2 showed " .. count .. " frames instead of 10")
    end
end

------------------------------------------------------------------ 2. mythic bench
local function MythicConf(maxColumns)
    return {
        enabled = true, width = 80, height = 32, spacing = 1, growth = "DOWN", groupGrowth = "RIGHT",
        unitsPerColumn = 5, maxColumns = maxColumns, preserveRaidGroups = true,
        sortMode = "ROLE", sortRolesAcrossRaid = true, roleOrder = "TANK,HEALER,DAMAGER",
        hideMythicGroupsFiveToEight = true, showPlayer = true,
    }
end

-- 20 active raiders in subgroups 1-4, five bench members in subgroup 5.
local function MythicRoster(roster)
    Add(roster, "TankA", 1, "TANK"); Add(roster, "TankB", 1, "TANK"); Add(roster, "HealA", 1, "HEALER")
    Add(roster, "Dps01", 1); Add(roster, "Dps02", 1)
    Add(roster, "HealB", 2, "HEALER"); for i = 3, 6 do Add(roster, ("Dps%02d"):format(i), 2) end
    Add(roster, "HealC", 3, "HEALER"); for i = 7, 10 do Add(roster, ("Dps%02d"):format(i), 3) end
    Add(roster, "HealD", 4, "HEALER"); for i = 11, 14 do Add(roster, ("Dps%02d"):format(i), 4) end
    Add(roster, "BenchTank", 5, "TANK"); Add(roster, "BenchHeal", 5, "HEALER")
    Add(roster, "BenchDps1", 5); Add(roster, "BenchDps2", 5); Add(roster, "BenchDps3", 5)
end

-- Names listed by, and (with the real header) shown in, the allowed blocks.
local function RoleFill(world)
    world.GF.SetupHeader("raid", "mythicraid")
    local listed, shown = {}, {}
    for groupIndex = 1, 8 do
        local header = world.GF.raidGroupHeaders[groupIndex]
        if header and header._msufPreservedGroupAllowed == true then
            Check(header:GetAttribute("sortMethod") == "NAMELIST", "block " .. groupIndex .. " is not a role-fill name list")
            for name in tostring(header:GetAttribute("nameList") or ""):gmatch("[^,]+") do listed[name] = true end
            if world.env.SecureGroupHeader_Update then
                world:Update(header)
                world:Shown(header, shown)
            end
        end
    end
    return listed, shown
end

local function BenchAndMissing(world, names)
    local bench, missing = {}, {}
    for _, member in ipairs(world.roster) do
        if member.group > 4 and names[member.name] then bench[#bench + 1] = member.name end
        if member.group <= 4 and not names[member.name] then missing[#missing + 1] = member.name end
    end
    return table.concat(bench, " "), table.concat(missing, " ")
end

local function MythicBench(label, sghSource)
    local world = NewWorld(sghSource, MythicConf(8), "mythicraid", true)
    MythicRoster(world.roster)
    local listed, shown = RoleFill(world)
    local bench, missing = BenchAndMissing(world, listed)
    Check(bench == "", label .. ": Hide groups 5-8 listed bench members " .. bench)
    Check(missing == "", label .. ": active raiders missing from the role fill: " .. missing)
    if sghSource then
        bench, missing = BenchAndMissing(world, shown)
        Check(bench == "" and missing == "", label .. ": real header shows bench [" .. bench
            .. "], hides active [" .. missing .. "]")
    end

    -- The role fill still ignores the block cap: outside Mythic, four blocks
    -- take raiders of every subgroup in role order (the tanks of subgroup 5 first).
    world = NewWorld(sghSource, MythicConf(4), "raid", false)
    MythicRoster(world.roster)
    listed = RoleFill(world)
    Check(listed.BenchTank and listed.BenchHeal, label .. ": the raid-wide role fill lost subgroup 5 outside Mythic")
    local count = 0
    for _ in pairs(listed) do count = count + 1 end
    Check(count == 20, label .. ": four blocks of five listed " .. count .. " names")
end

------------------------------------------------------------------ run
local runs = MirrorPresent() and ReadBranches() or { { label = "attributes only (no Blizzard UI mirror)" } }
for _, run in ipairs(runs) do
    for _, mode in ipairs({ "INDEX", "GROUP", "ROLE", "NAME" }) do
        CombatJoin(run.label .. " " .. mode, run.source, mode)
    end
    MythicBench(run.label .. " mythic", run.source)
end
print(("group_raid_header_blizzard_smoke: ok (%s)"):format(#runs > 1 and (#runs .. " Blizzard branches") or runs[1].label))

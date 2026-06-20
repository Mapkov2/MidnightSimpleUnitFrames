-- Assistant GroupFrames spell indicator state helper core.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSpellIndicators_Core.lua; keeps DB mutation helpers isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildSpellIndicatorStateHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local GroupDB = ctx.GroupDB
    local ApplyGroup = ctx.ApplyGroup
    local SpellRuntime = ctx.SpellRuntime
    if type(GroupDB) ~= "function" or type(ApplyGroup) ~= "function" then return nil end
    if type(SpellRuntime) ~= "function" then return nil end

    local function SpellDB(scope)
        local conf = GroupDB(scope)
        if type(conf.spellIndicators) ~= "table" then conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 } end
        local si = conf.spellIndicators
        if si.spec == nil or si.spec == "" then si.spec = "auto" end
        if type(si.specs) ~= "table" then si.specs = {} end
        if si.layer == nil then si.layer = 9 end
        return si
    end

    local function EnsureSpec(scope, specKey)
        local si = SpellDB(scope)
        if not specKey or specKey == "auto" or specKey == "multi" then return si end
        local runtime = SpellRuntime()
        if runtime and type(runtime.EnsureSpecConfig) == "function" then runtime.EnsureSpecConfig(si, specKey) else si.specs[specKey] = si.specs[specKey] or {} end
        return si
    end

    local function SpellEntry(scope, specKey, auraName, create)
        if not (specKey and auraName and auraName ~= "") then return nil end
        local si = EnsureSpec(scope, specKey)
        si.specs[specKey] = si.specs[specKey] or {}
        if create and type(si.specs[specKey][auraName]) ~= "table" then si.specs[specKey][auraName] = { enabled = true, onlyOwn = true } end
        return si.specs[specKey][auraName], si.specs[specKey]
    end

    local function Placed(entry, create)
        if not entry then return nil end
        if create and type(entry.placed) ~= "table" then entry.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true } end
        return type(entry.placed) == "table" and entry.placed or nil
    end

    local function FrameEffect(entry, create)
        if not entry then return nil end
        if create and type(entry.frame) ~= "table" then entry.frame = { type = "none" } end
        return type(entry.frame) == "table" and entry.frame or nil
    end

    local function ApplySpell(scope)
        local runtime = SpellRuntime()
        if runtime and type(runtime.InvalidateRuntimeCaches) == "function" then runtime.InvalidateRuntimeCaches() end
        ApplyGroup(scope, "visual")
    end

    local function CopyTable(src)
        if type(src) ~= "table" then return src end
        local out = {}
        for k, v in pairs(src) do out[k] = CopyTable(v) end
        return out
    end

    return {
        SpellDB = SpellDB,
        EnsureSpec = EnsureSpec,
        SpellEntry = SpellEntry,
        Placed = Placed,
        FrameEffect = FrameEffect,
        ApplySpell = ApplySpell,
        CopyTable = CopyTable,
    }
end

-- Review F2: turning an Edit Mode integration off and on again (Misc page
-- toggle, or a profile switch between profiles with different
-- *EditModeIntegration values) must register its elements again, and the next
-- off must unregister them again. The element registrar from
-- ExternalProviders.CreateElementRegistrar keeps the adapter's table, so the
-- adapter has to wipe that table in place instead of rebinding it.
-- Real ExternalProvider.lua plus the real Grid2 and DandersFrames adapters.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Frame()
    return {
        RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end,
        GetWidth = function() return 100 end, GetHeight = function() return 50 end,
        IsVisible = function() return true end,
    }
end

-- Public API stub: tracks live registrations per owner like PublicAPI.lua.
local live = {}
local function Count(owner)
    local n = 0
    for _ in pairs(live[owner] or {}) do n = n + 1 end
    return n
end
local function FreshEnvironment(general)
    live = {}
    _G.MSUF_EM2 = { Registry = {} }
    _G.MSUF_GetGeneralDB = function() return general end
    _G.hooksecurefunc = function() end
    _G.UIParent = { SetScale = function() end }
    _G.CreateFrame = function() return Frame() end
    _G.C_Timer = { After = function(_, fn) fn() end }
    _G.InCombatLockdown = function() return false end
    _G.MSUF_EditModeAPI = {
        RegisterElement = function(owner, element)
            live[owner] = live[owner] or {}
            if live[owner][element.id] then return false, "element_already_registered" end
            live[owner][element.id] = true
            return true
        end,
        UnregisterOwner = function(owner) live[owner] = nil; return true end,
        RegisterSessionListener = function() return true end,
        RefreshOwner = function() return true end,
    }
end

local function Load(path, namespace)
    local chunk = assert(loadfile(root .. "/" .. path))
    chunk("MidnightSimpleUnitFrames", namespace)
end

local function Namespace()
    return { ExportPublic = function(name, value) _G[name] = value; return value end }
end

local function Cycle(label, owner, setEnabled, expected)
    Check(Count(owner) == expected, label .. ": " .. Count(owner) .. " elements after load, expected " .. expected)
    setEnabled(false)
    Check(Count(owner) == 0, label .. ": elements stayed registered after turning the integration off")
    setEnabled(true)
    Check(Count(owner) == expected, label .. ": " .. Count(owner)
        .. " elements after turning the integration off and on, expected " .. expected)
    setEnabled(false)
    Check(Count(owner) == 0, label .. ": elements stayed registered after the second off")
    setEnabled(true)
    Check(Count(owner) == expected, label .. ": " .. Count(owner) .. " elements after the second on")
end

-- Grid2: one main layout element.
do
    local general = { grid2EditModeIntegration = true }
    FreshEnvironment(general)
    _G.Grid2Layout = {
        db = { profile = { Positions = {} } }, frame = Frame(),
        SavePosition = function() end, RestorePosition = function() end,
        RestorePositions = function() end, RestoreHeaderPosition = function() end,
        GetFramePosition = function() return "CENTER", 0, 0 end,
        IterateHeaders = function() return function() return nil end end,
        ReloadLayout = function() end,
    }
    local ns = Namespace()
    Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua", ns)
    Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Grid2.lua", ns)
    Cycle("Grid2", "MSUF.Grid2", _G.MSUF_Grid2EditMode_SetEnabled, 1)
    _G.Grid2Layout = nil
end

-- DandersFrames: party, raid and four pinned sets.
do
    local general = { dandersEditModeIntegration = true }
    FreshEnvironment(general)
    local db = { anchorX = 0, anchorY = 0, raidAnchorX = 0, raidAnchorY = 0, frameScale = 1 }
    _G.DandersFrames = {
        GetDB = function() return db end, GetRaidDB = function() return db end,
        UpdateContainerPosition = function() end, UpdateRaidContainerPosition = function() end,
        container = Frame(), raidContainer = Frame(),
    }
    local ns = Namespace()
    Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua", ns)
    Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Danders.lua", ns)
    Cycle("DandersFrames", "MSUF.DandersFrames", _G.MSUF_DandersEditMode_SetEnabled, 6)
    _G.DandersFrames = nil
end

if #failures > 0 then
    error("editmode_integration_toggle_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_integration_toggle_smoke: ok (Grid2 and DandersFrames re-register after off/on)")

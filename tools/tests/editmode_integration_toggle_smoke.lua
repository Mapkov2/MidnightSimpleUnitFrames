-- Review F2: turning an Edit Mode integration off and on again (Misc page
-- toggle, or a profile switch between profiles with different
-- *EditModeIntegration values) must register its elements again, and the next
-- off must unregister them again. The element registrar from
-- ExternalProviders.CreateElementRegistrar keeps the adapter's table, so the
-- adapter has to wipe that table in place instead of rebinding it.
-- The fixture follows the client's order: no profile exists while the files
-- load (the SavedVariables load after every file ran), the saved one arrives
-- before PLAYER_LOGIN, and the adapter reads its switch at login. Before the
-- fix round the adapters activated while they loaded, so an integration the
-- player had turned off came on.
-- Real ExternalProvider.lua plus the real Grid2 and DandersFrames adapters.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

-- Frames record their events and OnEvent script, so the login can reach them.
local frames = {}
local function Frame()
    local frame = {
        events = {},
        RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterEvent = function(self, event) self.events[event] = nil end,
        SetScript = function(self, _, fn) self.onEvent = fn end,
        GetWidth = function() return 100 end, GetHeight = function() return 50 end,
        IsVisible = function() return true end,
    }
    frames[#frames + 1] = frame
    return frame
end

-- Public API stub: tracks live registrations per owner like PublicAPI.lua.
local live = {}
local function Count(owner)
    local n = 0
    for _ in pairs(live[owner] or {}) do n = n + 1 end
    return n
end
-- The profile's general table: nil while the files load, as in the client.
local saved
local function FreshEnvironment()
    live, frames, saved = {}, {}, nil
    _G.MSUF_EM2 = { Registry = {} }
    _G.MSUF_GetGeneralDB = function() return saved end
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

-- The SavedVariables step, then PLAYER_LOGIN.
local function Login(general)
    saved = general
    for _, frame in ipairs(frames) do
        if frame.events.PLAYER_LOGIN and frame.onEvent then frame.onEvent(frame, "PLAYER_LOGIN") end
    end
end

local function Load(path, namespace)
    local chunk = assert(loadfile(root .. "/" .. path))
    chunk("MidnightSimpleUnitFrames", namespace)
end

local function Namespace()
    return { ExportPublic = function(name, value) _G[name] = value; return value end }
end

local function Cycle(label, owner, setEnabled, expected)
    Check(Count(owner) == expected, label .. ": " .. Count(owner) .. " elements at the start, expected " .. expected)
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

-- Grid2: one main layout element. The saved profile has the integration off:
-- nothing registers at load or at login, the Misc toggle turns it on.
do
    FreshEnvironment()
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
    Check(Count("MSUF.Grid2") == 0, "Grid2: elements registered while the files loaded, before the saved profile")
    local general = { grid2EditModeIntegration = false }
    Login(general)
    Check(Count("MSUF.Grid2") == 0, "Grid2: the integration the player turned off was activated at login")
    _G.MSUF_Grid2EditMode_SetEnabled(true)
    Check(general.grid2EditModeIntegration == true, "Grid2: the toggle did not save the switch")
    Cycle("Grid2", "MSUF.Grid2", _G.MSUF_Grid2EditMode_SetEnabled, 1)
    _G.Grid2Layout = nil
end

-- DandersFrames: party, raid and four pinned sets. The saved profile has the
-- integration on: it registers at login.
do
    FreshEnvironment()
    local db = { anchorX = 0, anchorY = 0, raidAnchorX = 0, raidAnchorY = 0, frameScale = 1 }
    _G.DandersFrames = {
        GetDB = function() return db end, GetRaidDB = function() return db end,
        UpdateContainerPosition = function() end, UpdateRaidContainerPosition = function() end,
        container = Frame(), raidContainer = Frame(),
    }
    local ns = Namespace()
    Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua", ns)
    Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Danders.lua", ns)
    Check(Count("MSUF.DandersFrames") == 0,
        "DandersFrames: elements registered while the files loaded, before the saved profile")
    Login({ dandersEditModeIntegration = true })
    Cycle("DandersFrames", "MSUF.DandersFrames", _G.MSUF_DandersEditMode_SetEnabled, 6)
    _G.DandersFrames = nil
end

-- Details! (one window) and Dominos (one bar): off at login stays off, on at
-- login registers.
for _, case in ipairs({
    { label = "Details!", owner = "MSUF.Details", setting = "detailsEditModeIntegration",
        file = "MSUF_EditMode_Details.lua", setter = "MSUF_DetailsEditMode_SetEnabled", global = "Details",
        fake = function()
            return { GetInstance = function() return nil end, GetNumInstances = function() return 1 end,
                RegisterEvent = function() end, UnregisterEvent = function() end }
        end },
    { label = "Dominos", owner = "MSUF.Dominos", setting = "dominosEditModeIntegration",
        file = "MSUF_EditMode_Dominos.lua", setter = "MSUF_DominosEditMode_SetEnabled", global = "Dominos",
        fake = function()
            return { RegisterCallback = function() end, UnregisterCallback = function() end,
                Frame = { Get = function() return nil end, GetAll = function() return pairs({ [1] = {} }) end } }
        end },
}) do
    for _, enabled in ipairs({ false, true }) do
        FreshEnvironment()
        _G[case.global] = case.fake()
        local ns = Namespace()
        Load("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua", ns)
        Load("MidnightSimpleUnitFrames/Shell/EditMode/" .. case.file, ns)
        Check(Count(case.owner) == 0, case.label .. ": elements registered while the files loaded, before the saved profile")
        Login({ [case.setting] = enabled })
        Check(Count(case.owner) == (enabled and 1 or 0), case.label .. ": " .. Count(case.owner)
            .. " elements after a login with the integration " .. (enabled and "on" or "off"))
        if enabled then Cycle(case.label, case.owner, _G[case.setter], 1) end
        _G[case.global] = nil
    end
end

if #failures > 0 then
    error("editmode_integration_toggle_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_integration_toggle_smoke: ok (Grid2, DandersFrames, Details! and Dominos read the switch at login"
    .. " and re-register after off/on)")

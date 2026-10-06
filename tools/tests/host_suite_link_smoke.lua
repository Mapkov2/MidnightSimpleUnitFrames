-- host_suite_link_smoke.lua [repoRoot]
--
-- MSUF's link to the Suite (Kernel/MSUF_SuiteLink.lua): every MSUF call into
-- the Suite gives the same answers and the same Suite calls for
--   * no Suite (the documented "absent" answers),
--   * an older Suite (the namespace paths MSUF read before), and
--   * a Suite with MSUFSuite.API v1, which is preferred: with the old paths
--     removed from its namespace every answer stays the same, and the API
--     table is resolved once (one MSUFSuite.API read for 100 calls);
--   * an API table with version 0 is ignored (old paths).
--
-- Plain Lua 5.1. Repo root as arg 1, default ".".

local root = ((arg and arg[1]) or "."):gsub("\\", "/"):gsub("/$", "")
local checks = 0

local function Check(condition, message)
    if not condition then error(message, 2) end
    checks = checks + 1
end

local function Read(path)
    local handle = assert(io.open(path, "rb"), path .. " is missing")
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local function Load(path, ...)
    return assert(loadstring(Read(path), "@" .. path))(...)
end

local function Show(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return "{" .. table.concat(keys, ",") .. "}"
end

------------------------------------------------------------------ B. Suite link
local log
local function Logger(name, result)
    return function(...)
        log[#log + 1] = name .. "(" .. table.concat({ tostring((...)), tostring((select(2, ...))) }, ",") .. ")"
        return result
    end
end

-- An older Suite's namespace: the paths MSUF read before.
local function OldSuite()
    local overview = { version = "1.0", total = 3, enabled = 2, needsSetup = false }
    local profiles = { Available = Logger("Available", true), Export = Logger("Export", "MSUFS3:x"),
        ExportModule = Logger("ExportModule", "MSUFM2:y"), Import = Logger("Import", true),
        ImportModule = Logger("ImportModule", true), ImportModuleIntoNew = Logger("ImportModuleIntoNew", true) }
    local suite = {
        Database = { StageFactoryReset = Logger("StageFactoryReset", true) },
        GetOverview = function() log[#log + 1] = "GetOverview"
            return overview end,
        Changelog = { entries = { { version = "1.0" } } },
        Installer = { Open = Logger("Open", true), MaybeShow = Logger("MaybeShow"),
            IsFirstRunPending = Logger("IsFirstRunPending", false), IsOpen = Logger("IsOpen", true) },
        OnMSUFProfileLifecycle = Logger("OnMSUFProfileLifecycle", false),
        OnMSUFProfileChanged = Logger("OnMSUFProfileChanged"),
        CooldownManager = { GetAnchorFrame = Logger("GetAnchorFrame", "anchor") },
        Options = { BuildColorsCategory = Logger("BuildColorsCategory") },
        SuiteProfiles = profiles,
        SuiteOrder = { "minimap", "bags", "ghost" },
        SuiteCatalog = { minimap = { title = "Minimap" }, bags = { title = "Bags" } },
        Client = { AddOnEnabled = function(name) log[#log + 1] = "AddOnEnabled(" .. name .. ")"
            return true end },
    }
    return suite, Logger("ApplyFonts")
end

-- A Suite with API v1, built over the same owners as MSUF_Suite/Core/API.lua.
local function NewSuite(version, stripPaths)
    local owners, applyFonts = OldSuite()
    local suite, profiles = owners, owners.SuiteProfiles
    local api = { version = version,
        StageFactoryReset = suite.Database.StageFactoryReset, GetOverview = suite.GetOverview,
        GetChangelog = function() return owners.Changelog end,
        OpenInstaller = suite.Installer.Open, MaybeShowInstaller = suite.Installer.MaybeShow,
        IsInstallerPending = suite.Installer.IsFirstRunPending, IsInstallerOpen = suite.Installer.IsOpen,
        OnMSUFProfileChanged = suite.OnMSUFProfileChanged, OnMSUFProfileLifecycle = suite.OnMSUFProfileLifecycle,
        ApplyFontsFromMSUF = applyFonts,
        HasCooldownAnchor = function() return true end, GetCooldownAnchorFrame = suite.CooldownManager.GetAnchorFrame,
        HasColorsCategory = function() return true end, BuildColorsCategory = suite.Options.BuildColorsCategory,
        Profiles = profiles,
        GetProfileModules = function()
            local modules = {}
            for _, id in ipairs(owners.SuiteOrder) do
                local spec = owners.SuiteCatalog[id]
                if spec then modules[#modules + 1] = { id = id, title = spec.title } end
            end
            return modules
        end,
        IsSkinAddOnEnabled = function() return owners.Client.AddOnEnabled("MSUF_Suite_Skin") == true end,
    }
    if stripPaths then
        suite = {}
        applyFonts = nil
    end
    suite.API = api
    return suite, applyFonts
end

-- Every link call MSUF makes, its answers and the Suite calls behind them.
local function Drive(Link)
    log = {}
    local answers = {}
    local function Note(name, ...) answers[#answers + 1] = name .. "=" .. Show((...)) .. "," .. tostring((select(2, ...))) end
    Note("CanStageFactoryReset", Link.CanStageFactoryReset())
    Note("StageFactoryReset", Link.StageFactoryReset())
    Note("GetOverview", Link.GetOverview())
    local changelog = Link.GetChangelog()
    Note("GetChangelog", changelog and changelog.entries and changelog.entries[1].version)
    Note("CanOpenInstaller", Link.CanOpenInstaller())
    Note("OpenInstaller", Link.OpenInstaller())
    Note("MaybeShowInstaller", Link.MaybeShowInstaller())
    Note("InstallerBusy", Link.InstallerBusy())
    Note("NotifyProfileLifecycle", Link.NotifyProfileLifecycle("delete", "A", "B"))
    Note("NotifyProfileChanged", Link.NotifyProfileChanged("A", "switch"))
    Note("ApplyFonts", Link.ApplyFonts())
    Note("HasCooldownAnchor", Link.HasCooldownAnchor())
    Note("GetCooldownAnchorFrame", Link.GetCooldownAnchorFrame("EssentialCooldownViewer"))
    Note("HasColorsCategory", Link.HasColorsCategory())
    Note("BuildColorsCategory", Link.BuildColorsCategory("ctx", "builder"))
    local profiles = Link.Profiles()
    Note("Profiles", profiles ~= nil)
    if profiles then
        Note("Available", profiles.Available())
        Note("Export", profiles.Export())
        Note("ExportModule", profiles.ExportModule("minimap"))
        Note("Import", profiles.Import("New", "MSUFS3:x"))
        Note("ImportModule", profiles.ImportModule("MSUFM2:y"))
        Note("ImportModuleIntoNew", profiles.ImportModuleIntoNew("New", "MSUFM2:y"))
    end
    local modules = {}
    for _, module in ipairs(Link.ProfileModules()) do modules[#modules + 1] = module.id .. ":" .. module.title end
    Note("ProfileModules", table.concat(modules, " "))
    Note("ModuleTitle", Link.ModuleTitle("bags"), Link.ModuleTitle("ghost"))
    Note("SkinAddOnEnabled", Link.SkinAddOnEnabled())
    return table.concat(answers, "\n"), table.concat(log, " ")
end

local function FreshLink(suite, applyFonts)
    _G.MSUFSuite, _G.MSUFSuite_ApplyFontsFromMSUF = suite, applyFonts
    local ns = {}
    Load(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_SuiteLink.lua", "MidnightSimpleUnitFrames", ns)
    return ns.SuiteLink
end

-- No Suite: the documented absent answers, and nothing is called.
do
    local Link = FreshLink(nil, nil)
    log = {}
    Check(Link.CanStageFactoryReset() == false and Link.StageFactoryReset() == false and Link.GetOverview() == nil
        and Link.GetChangelog() == nil and Link.CanOpenInstaller() == false and Link.OpenInstaller() == nil
        and not Link.InstallerBusy()
        and Link.NotifyProfileLifecycle("delete", "A") == true and Link.HasCooldownAnchor() == false
        and Link.GetCooldownAnchorFrame("EssentialCooldownViewer") == nil and Link.HasColorsCategory() == false
        and Link.BuildColorsCategory({}, {}) == nil and Link.Profiles() == nil and #Link.ProfileModules() == 0
        and Link.ModuleTitle("bags") == nil and Link.SkinAddOnEnabled() == false,
        "without a Suite the link must answer absent")
    Link.MaybeShowInstaller()
    Link.NotifyProfileChanged("A", "switch")
    Link.ApplyFonts()
end

local oldAnswers, oldCalls = Drive(FreshLink(OldSuite()))
Check(oldCalls:find("StageFactoryReset(nil,nil)", 1, true) and oldCalls:find("ApplyFonts", 1, true)
    and oldCalls:find("GetAnchorFrame(EssentialCooldownViewer", 1, true), "the old Suite paths were not called")
local newAnswers, newCalls = Drive(FreshLink(NewSuite(1, false)))
Check(newAnswers == oldAnswers and newCalls == oldCalls,
    "a Suite with API v1 must answer as the old paths:\n" .. newAnswers .. "\n--\n" .. oldAnswers
    .. "\n" .. newCalls .. "\n--\n" .. oldCalls)
local apiAnswers, apiCalls = Drive(FreshLink(NewSuite(1, true)))
Check(apiAnswers == oldAnswers and apiCalls == oldCalls,
    "with API v1 the link must not read the old paths:\n" .. apiAnswers .. "\n--\n" .. oldAnswers)
local zeroAnswers, zeroCalls = Drive(FreshLink(NewSuite(0, false)))
Check(zeroAnswers == oldAnswers and zeroCalls == oldCalls, "an API table below version 1 must be ignored")

-- The API table is resolved once.
do
    local suite, applyFonts = NewSuite(1, true)
    local api, reads = suite.API, 0
    suite.API = nil
    setmetatable(suite, { __index = function(_, key)
        if key == "API" then reads = reads + 1
            return api end
    end })
    local Link = FreshLink(suite, applyFonts)
    log = {}
    for _ = 1, 100 do Link.GetOverview() end
    Check(reads == 1, "the Suite API was read " .. reads .. " times for 100 calls")
end
_G.MSUFSuite, _G.MSUFSuite_ApplyFontsFromMSUF = nil, nil

print(("host_suite_link_smoke: ok (%d checks)"):format(checks))

-- MSUF's link to the optional MSUF Suite: every call MSUF makes into the
-- Suite goes through MSUF.SuiteLink. A Suite with its documented API
-- (MSUFSuite.API, version 1 or newer) answers through that table; an older
-- Suite is reached by the paths into its namespace MSUF used before, kept
-- here unchanged. Without the Suite every function answers "absent" (nil,
-- false or the documented default) and changes nothing.
--
-- The Suite loads after MSUF (it depends on it), so nothing is resolved
-- while this file loads. Once found, the API table is kept; until then each
-- call looks again (one table read). Every caller is cold: menus, profile
-- switches, font applies, setup and the cooldown anchor retries.
local _, MSUF = ...
local rawget, type = rawget, type

local SUITE_API_VERSION = 1
local Link = {}
MSUF.SuiteLink = Link

local api

local function Suite()
    local suite = rawget(_G, "MSUFSuite")
    if type(suite) == "table" then return suite end
    return nil
end

-- The Suite's API table when it is version 1 or newer, else nil.
local function API()
    if api then return api end
    local suite = Suite()
    local candidate = suite and suite.API
    if type(candidate) == "table" and type(candidate.version) == "number"
        and candidate.version >= SUITE_API_VERSION then
        api = candidate
    end
    return api
end

-- The function at suite[owner][name] of an older Suite, else nil.
local function LegacyFunction(owner, name)
    local suite = Suite()
    local holder = suite and suite[owner]
    local fn = type(holder) == "table" and holder[name] or nil
    if type(fn) == "function" then return fn end
    return nil
end

------------------------------------------------------------------ dashboard
function Link.CanStageFactoryReset()
    return API() ~= nil or LegacyFunction("Database", "StageFactoryReset") ~= nil
end

-- -> ok, reason; false when the Suite cannot stage a reset.
function Link.StageFactoryReset()
    local current = API()
    if current then return current.StageFactoryReset() end
    local stage = LegacyFunction("Database", "StageFactoryReset")
    if stage then return stage() end
    return false
end

function Link.GetOverview()
    local current = API()
    if current then return current.GetOverview() end
    local suite = Suite()
    local getOverview = suite and suite.GetOverview
    if type(getOverview) == "function" then return getOverview() end
    return nil
end

function Link.GetChangelog()
    local current = API()
    if current then return current.GetChangelog() end
    local suite = Suite()
    return suite and suite.Changelog or nil
end

------------------------------------------------------------------ setup
function Link.CanOpenInstaller()
    return API() ~= nil or LegacyFunction("Installer", "Open") ~= nil
end

-- -> whatever the installer answers (true when its window opened), nil
-- without one.
function Link.OpenInstaller()
    local current = API()
    if current then return current.OpenInstaller() end
    local open = LegacyFunction("Installer", "Open")
    if open then return open() end
    return nil
end

function Link.MaybeShowInstaller()
    local current = API()
    if current then return current.MaybeShowInstaller() end
    local maybeShow = LegacyFunction("Installer", "MaybeShow")
    if maybeShow then maybeShow() end
    return nil
end

-- Truthy while the Suite's setup is pending or open.
function Link.InstallerBusy()
    local current = API()
    if current then return current.IsInstallerPending() or current.IsInstallerOpen() end
    local suite = Suite()
    local installer = suite and suite.Installer
    if not installer then return nil end
    return (installer.IsFirstRunPending and installer.IsFirstRunPending())
        or (installer.IsOpen and installer.IsOpen())
end

------------------------------------------------------------------ MSUF state
-- -> whether the Suite allows the lifecycle step; true without a Suite.
function Link.NotifyProfileLifecycle(kind, source, target)
    local current = API()
    if current then return current.OnMSUFProfileLifecycle(kind, source, target) end
    local suite = Suite()
    if suite and type(suite.OnMSUFProfileLifecycle) == "function" then
        return suite.OnMSUFProfileLifecycle(kind, source, target)
    end
    return true
end

function Link.NotifyProfileChanged(name, reason)
    local current = API()
    if current then
        current.OnMSUFProfileChanged(name, reason)
        return
    end
    local suite = Suite()
    if suite and type(suite.OnMSUFProfileChanged) == "function" then suite.OnMSUFProfileChanged(name, reason) end
end

function Link.ApplyFonts()
    local current = API()
    if current then
        current.ApplyFontsFromMSUF()
        return
    end
    local apply = rawget(_G, "MSUFSuite_ApplyFontsFromMSUF")
    if type(apply) == "function" then apply() end
end

------------------------------------------------------------------ cooldown anchor
function Link.HasCooldownAnchor()
    local current = API()
    if current then return current.HasCooldownAnchor() == true end
    return LegacyFunction("CooldownManager", "GetAnchorFrame") ~= nil
end

function Link.GetCooldownAnchorFrame(viewerName)
    local current = API()
    if current then return current.GetCooldownAnchorFrame(viewerName) end
    local getAnchorFrame = LegacyFunction("CooldownManager", "GetAnchorFrame")
    if getAnchorFrame then return getAnchorFrame(viewerName) end
    return nil
end

------------------------------------------------------------------ options
function Link.HasColorsCategory()
    local current = API()
    if current then return current.HasColorsCategory() == true end
    return LegacyFunction("Options", "BuildColorsCategory") ~= nil
end

function Link.BuildColorsCategory(ctx, builder)
    local current = API()
    if current then return current.BuildColorsCategory(ctx, builder) end
    local build = LegacyFunction("Options", "BuildColorsCategory")
    if build then return build(ctx, builder) end
    return nil
end

------------------------------------------------------------------ profiles
-- { Available, Export, ExportModule, Import, ImportModule, ImportModuleIntoNew }
-- of the Suite, else nil.
function Link.Profiles()
    local current = API()
    if current then return current.Profiles end
    local suite = Suite()
    local profiles = suite and suite.SuiteProfiles
    if type(profiles) == "table" then return profiles end
    return nil
end

-- { { id, title }, ... } in Suite order; empty without a Suite.
function Link.ProfileModules()
    local current = API()
    if current then return current.GetProfileModules() end
    local modules, suite = {}, Suite()
    local catalog = suite and suite.SuiteCatalog
    for _, id in ipairs(suite and suite.SuiteOrder or {}) do
        local spec = catalog and catalog[id]
        if spec then modules[#modules + 1] = { id = id, title = spec.title } end
    end
    return modules
end

-- The title of one Suite module, nil when the Suite does not know it.
function Link.ModuleTitle(id)
    local modules = Link.ProfileModules()
    for index = 1, #modules do
        if modules[index].id == id then return modules[index].title end
    end
    return nil
end

-- Whether the Suite's nameplates draw MSUF's interrupt-ready indicator
-- (MSUF.KickReady consumers): Suites whose API has HasNameplateKickReady.
-- Older Suites with nameplates cannot, so MSUF hides that switch for them.
function Link.HasNameplateKickReady()
    local current = API()
    local has = current and current.HasNameplateKickReady
    if has then return has() == true end
    return false
end

function Link.SkinAddOnEnabled()
    local current = API()
    if current then return current.IsSkinAddOnEnabled() == true end
    local suite = Suite()
    local client = suite and suite.Client
    return (client and client.AddOnEnabled and client.AddOnEnabled("MSUF_Suite_Skin") == true) or false
end

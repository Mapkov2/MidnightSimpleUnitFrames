-- Embedded MSUFUnitFrames hosts share WoW's _G, but all framework state must
-- remain owned by the addon namespace that loaded the library.
local root = arg and arg[1] or "."
local libraryRoot = root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/"

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Read(path)
    local file, openError = io.open(path, "rb")
    Check(file ~= nil, openError)
    local source = file:read("*a")
    file:close()
    return source
end

local libraryFiles = {
    "init.lua",
    "MSUF_UF_Secrets.lua",
    "MSUF_UF_Apply.lua",
    "MSUF_UF_Metadata.lua",
    "MSUF_UF_Layers.lua",
    "MSUF_UF_Core.lua",
    "MSUF_UF_Runtime.lua",
    "api.lua",
    "finalize.lua",
}

-- Keep the standalone smoke on the real XML contract instead of a convenient
-- subset that could miss a cross-host global export in a later library file.
local xml = Read(libraryRoot .. "MSUFUnitFrames.xml")
local xmlFiles = {}
for file in xml:gmatch('<Script%s+file="([^"]+)"%s*/>') do
    xmlFiles[#xmlFiles + 1] = file
end
Check(#xmlFiles == #libraryFiles, "MSUFUnitFrames.xml script count drifted")
for index = 1, #libraryFiles do
    Check(xmlFiles[index] == libraryFiles[index],
        ("MSUFUnitFrames.xml order mismatch at %d: expected %s, got %s"):format(
            index, libraryFiles[index], tostring(xmlFiles[index])))
end

-- This framework is embedded without LibStub. Check both the source contract
-- and runtime behavior so a soft/optional lookup cannot silently creep in.
local libStubTouches = 0
local function TouchLibStub()
    libStubTouches = libStubTouches + 1
    error("embedded MSUFUnitFrames touched LibStub", 2)
end
_G.LibStub = setmetatable({}, {
    __call = TouchLibStub,
    __index = TouchLibStub,
    __newindex = TouchLibStub,
})
for index = 1, #libraryFiles do
    local file = libraryFiles[index]
    local source = Read(libraryRoot .. file)
    Check(not source:match("%f[%w_]LibStub%f[^%w_]"),
        file .. " contains a LibStub dependency")
end

local metadata = {
    HostA = {
        ["X-MSUF-UnitFrames"] = "HostAUnitFrames",
        ["X-MSUF-UnitFrames-Global"] = "WrongHostAGlobal",
        ["X-MSUF-UnitFrames-Prefix"] = "HostA",
    },
    HostB = {
        ["X-MSUF-UnitFrames"] = "HostBUnitFrames",
        ["X-MSUF-UnitFrames-Global"] = "WrongHostBGlobal",
        ["X-MSUF-UnitFrames-Prefix"] = "HostB",
    },
    HostCollision = {
        ["X-MSUF-UnitFrames"] = "HostAUnitFrames",
    },
    HostReserved = {
        ["X-MSUF-UnitFrames"] = "MSUFUnitFrames",
    },
    HostNoGlobal = {
        ["X-MSUF-UnitFrames-Prefix"] = "HostNoGlobal",
    },
}
local metadataReads = {}
_G.C_AddOns = {
    GetAddOnMetadata = function(addonName, key)
        metadataReads[key] = (metadataReads[key] or 0) + 1
        local values = metadata[addonName]
        return values and values[key] or nil
    end,
}
_G.GetAddOnMetadata = nil
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end
_G.IsLoggedIn = function() return true end
_G.UnitExists = function() return true end
_G.UIParent = {}

local createdFrames = {}
local function NewFrame(name, parent, template)
    local frame = {
        name = name,
        parent = parent,
        template = template,
        attributes = {},
        registeredEvents = {},
        scripts = {},
        hooks = {},
    }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:RegisterForClicks(value) self.clicks = value end
    function frame:SetScript(script, func) self.scripts[script] = func end
    function frame:HookScript(script, func) self.hooks[script] = func end
    function frame:IsVisible() return true end
    function frame:RegisterEvent(event) self.registeredEvents[event] = true end
    function frame:RegisterUnitEvent(event, ...)
        self.registeredEvents[event] = { ... }
    end
    function frame:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function frame:UnregisterAllEvents() self.registeredEvents = {} end
    function frame:CallMethod(method, ...)
        return self[method](self, ...)
    end
    return frame
end

_G.CreateFrame = function(_, name, parent, template)
    local frame = NewFrame(name, parent, template)
    createdFrames[#createdFrames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
_G.RegisterUnitWatch = function(frame) frame.unitWatch = true end

local msufSentinel = {}
local namespaceSentinel = {}
local legacyCoreSentinel = {}
local legacyExportSentinel = {}
_G.MSUF = msufSentinel
_G.MSUF_NS = namespaceSentinel
_G.MSUF_UFCore = legacyCoreSentinel
_G.MSUFUnitFrames = nil
_G.HostAUnitFrames = nil
_G.HostBUnitFrames = nil
_G.WrongHostAGlobal = nil
_G.WrongHostBGlobal = nil

local legacyExportNames = {
    "MSUF_UnitFrames",
    "MSUF_UnitFramesList",
    "MSUF_ForEachUnitFrame",
    "MSUF_GetUnitFrameScreenCacheKey",
    "MSUF_GetUnitFrameScreenCacheBucket",
    "MSUF_CacheUnitFrameScreenPosition",
    "MSUF_ApplyCachedUnitFrameScreenPosition",
    "MSUF_UFCore_NotifyConfigChanged",
    "MSUF_RefreshAllFrames",
    "MSUF_RefreshAllFrameColors",
    "MSUF_RefreshAllIdentityColors",
    "MSUF_RefreshAllPowerTextColors",
    "MSUF_ForceTextLayoutForUnitKey",
    "MSUF_RefreshAllUnitAlphas",
    "MSUF_ApplyBarOutlineThickness_All",
    "MSUF_ApplyPowerBarBorder_All",
    "MSUF_ApplyReverseFillBars",
    "MSUF_RefreshPredictionBars",
    "MSUF_RefreshTempMaxHealth",
    "MSUF_ApplyAllAlpha",
    "MSUF_ApplyPowerBarEmbedLayout_All",
    "MSUF_ApplyPowerBarEmbedLayout",
    "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey",
    "MSUF_ApplyUnitFrameKey_Immediate",
    "MSUF_RequestUnitFrameReanchorAfterCombat",
}
for index = 1, #legacyExportNames do
    _G[legacyExportNames[index]] = legacyExportSentinel
end

local function LoadFile(file, addonName, namespace)
    local chunk, loadError = loadfile(libraryRoot .. file)
    Check(chunk ~= nil, loadError)
    return chunk(addonName, namespace)
end

local function LoadHost(addonName, namespace)
    namespace = namespace or {}
    for index = 1, #libraryFiles do
        LoadFile(libraryFiles[index], addonName, namespace)
    end
    return namespace, namespace.MSUFUnitFrames
end

local function LoadInit(addonName, namespace)
    return LoadFile("init.lua", addonName, namespace)
end

local namespaceA, frameworkA = LoadHost("HostA")
local namespaceB, frameworkB = LoadHost("HostB")
Check(type(frameworkA) == "table" and type(frameworkB) == "table",
    "one of the embedded hosts did not receive a framework")
Check(frameworkA ~= frameworkB, "two hosts shared the framework instance")
Check(namespaceA.UF ~= namespaceB.UF, "two hosts shared the UF runtime")
Check(namespaceA.GF ~= namespaceB.GF, "two hosts shared the GF runtime")
Check(namespaceA.UF.elements ~= namespaceB.UF.elements,
    "two hosts shared the element registry")
Check(namespaceA.UF.Elements ~= namespaceB.UF.Elements,
    "two hosts shared the compatibility element registry")
Check(namespaceA.UF.elementTraits ~= namespaceB.UF.elementTraits,
    "two hosts shared element traits")
Check(frameworkA.objects ~= frameworkB.objects, "two hosts shared the object registry")
Check(frameworkA.headers ~= frameworkB.headers, "two hosts shared the header registry")
Check(frameworkA.Private == nil and frameworkB.Private == nil,
    "finalize.lua exposed private instance state")
Check(frameworkA.addonName == "HostA" and frameworkB.addonName == "HostB",
    "host identity crossed framework instances")
Check(frameworkA.globalName == "HostAUnitFrames"
    and frameworkB.globalName == "HostBUnitFrames",
    "X-MSUF-UnitFrames did not define the framework globals")
Check(_G.HostAUnitFrames == frameworkA and _G.HostBUnitFrames == frameworkB,
    "project-specific globals point at the wrong framework")
Check(_G.WrongHostAGlobal == nil and _G.WrongHostBGlobal == nil,
    "the non-contract X-MSUF-UnitFrames-Global metadata was consumed")
Check(metadataReads["X-MSUF-UnitFrames"] and metadataReads["X-MSUF-UnitFrames"] >= 2,
    "X-MSUF-UnitFrames metadata was not read")
Check(metadataReads["X-MSUF-UnitFrames-Global"] == nil,
    "library queried X-MSUF-UnitFrames-Global instead of the oUF-shaped contract")

local styleA = function() end
local styleB = function() end
frameworkA:RegisterStyle("Shared", styleA)
frameworkB:RegisterStyle("Shared", styleB)
Check(frameworkA:GetActiveStyle() == "Shared"
    and frameworkB:GetActiveStyle() == "Shared",
    "initial active styles crossed hosts")
frameworkA:RegisterStyle("OnlyA", function() end)
frameworkA:SetActiveStyle("OnlyA")
Check(frameworkA:GetActiveStyle() == "OnlyA", "HostA active style did not change")
Check(frameworkB:GetActiveStyle() == "Shared", "HostA active style changed HostB")
local stylesA, stylesB = {}, {}
for name, style in frameworkA:IterateStyles() do stylesA[name] = style end
for name, style in frameworkB:IterateStyles() do stylesB[name] = style end
Check(stylesA.Shared == styleA and stylesB.Shared == styleB,
    "same-named styles did not stay host-local")
Check(stylesA.OnlyA ~= nil and stylesB.OnlyA == nil,
    "HostA-only style leaked into HostB")

local elementA = { Apply = function() end }
local elementB = { Apply = function() end }
frameworkA:RegisterElement("SharedExternal", elementA)
frameworkB:RegisterElement("SharedExternal", elementB)
Check(frameworkA.elements.SharedExternal == elementA
    and namespaceA.UF.Elements.SharedExternal == elementA,
    "HostA external element missed its registries")
Check(frameworkB.elements.SharedExternal == elementB
    and namespaceB.UF.Elements.SharedExternal == elementB,
    "HostB external element missed its registries")
Check(frameworkA.elements.SharedExternal ~= frameworkB.elements.SharedExternal,
    "same-named external elements crossed hosts")

local serviceA, serviceB = {}, {}
frameworkA:SetService("Owner", serviceA)
frameworkB:SetService("Owner", serviceB)
Check(frameworkA:GetService("Owner") == serviceA
    and frameworkB:GetService("Owner") == serviceB,
    "service registries crossed hosts")
frameworkA:SetHostValue("Marker", "A")
frameworkB:SetHostValue("Marker", "B")
Check(frameworkA:GetHostValue("Marker") == "A"
    and frameworkB:GetHostValue("Marker") == "B",
    "host values crossed framework instances")

local createCount, applyCount, enableCount, updateCount = 0, 0, 0, 0
frameworkA:RegisterElement("SpawnProbe", {
    Create = function() createCount = createCount + 1 end,
    Apply = function() applyCount = applyCount + 1 end,
    Enable = function() enableCount = enableCount + 1 return true end,
    Disable = function() end,
    Update = function() updateCount = updateCount + 1 end,
    GetEvents = function() return { "UNIT_HEALTH" } end,
    UpdateOnApply = true,
})
frameworkA:RegisterStyle("SpawnStyle", function(_, unit)
    return {
        unit = unit,
        enabled = true,
        elements = { SpawnProbe = true },
    }
end)
frameworkA:SetActiveStyle("SpawnStyle")

local spawned = frameworkA:Spawn("target", "HostAProbeFrame")
Check(spawned == _G.HostAProbeFrame and spawned.MSUFUnitFrames == frameworkA,
    "Spawn did not retain host ownership")
Check(spawned:GetAttribute("unit") == "target"
    and spawned:GetAttribute("*type1") == "target"
    and spawned:GetAttribute("*type2") == "togglemenu"
    and spawned.unitWatch == true,
    "Spawn did not configure the secure unit button contract")
Check(spawned.template == "SecureUnitButtonTemplate, PingableUnitFrameTemplate",
    "Spawn did not use the pingable secure unit-frame templates")
Check(createCount == 1 and applyCount == 1 and enableCount == 1 and updateCount >= 1,
    "Spawn did not apply the registered external element")
Check(spawned.registeredEvents.UNIT_HEALTH ~= nil,
    "external element events were not routed by the core")
Check(frameworkA.objects[#frameworkA.objects] == spawned,
    "Spawn did not publish the object in its host-local registry")
Check(namespaceA.UF.elementTraits.SpawnProbe.apply == true
    and namespaceA.UF.elementTraits.SpawnProbe.events == true
    and namespaceA.UF.elementTraits.SpawnProbe.forceUpdate == true,
    "external element capabilities were not compiled")
local beforeForce = updateCount
spawned:ForceUpdate("EMBED_SMOKE")
Check(updateCount == beforeForce + 1,
    "external force-update capability was not compiled into the frame plan")

local duplicateOK = pcall(frameworkA.Spawn, frameworkA, "target", "HostAProbeFrame")
Check(duplicateOK == false, "Spawn accepted an occupied explicit frame name")
local foreignAttachOK = pcall(frameworkB.AttachFrame, frameworkB, spawned)
Check(foreignAttachOK == false, "another host adopted an owned frame")

local factoryCalls = 0
frameworkA:Factory(function(instance)
    Check(instance == frameworkA, "Factory received the wrong host instance")
    factoryCalls = factoryCalls + 1
end)
Check(factoryCalls == 1, "logged-in Factory callback was not immediate")

local header = frameworkA:SpawnHeader(
    "HostAProbeHeader", nil, { showParty = true, point = "TOP" })
Check(header == _G.HostAProbeHeader
    and header.MSUFUnitFrames == frameworkA
    and header:GetAttribute("showParty") == true
    and header:GetAttribute("point") == "TOP"
    and header:GetAttribute("initialConfigFunction") ~= nil,
    "SpawnHeader did not keep ownership and secure attributes")
Check(frameworkA.headers[#frameworkA.headers] == header,
    "SpawnHeader did not publish the host-local header")

Check(_G.MSUF == msufSentinel and _G.MSUF_NS == namespaceSentinel,
    "generic host rebound the MSUF namespace globals")
Check(_G.MSUF_UFCore == legacyCoreSentinel,
    "generic host replaced the legacy UFCore global")
for index = 1, #legacyExportNames do
    local name = legacyExportNames[index]
    Check(_G[name] == legacyExportSentinel,
        "generic host published legacy global " .. name)
end

-- A duplicate metadata global must fail before changing the attempted host
-- namespace or the original global.
local collisionNamespace = {}
local collisionOK, collisionError = pcall(LoadInit, "HostCollision", collisionNamespace)
Check(collisionOK == false, "duplicate X-MSUF-UnitFrames global was accepted")
Check(tostring(collisionError):find("existing global", 1, true) ~= nil,
    "duplicate-global error was not descriptive")
Check(_G.HostAUnitFrames == frameworkA, "duplicate host replaced HostA's global")
Check(next(collisionNamespace) == nil,
    "duplicate-global failure partially initialized the host namespace")

-- MSUFUnitFrames is reserved for the canonical MSUF host even when it has not
-- yet been published by that host.
local reservedNamespace = {}
local reservedOK, reservedError = pcall(LoadInit, "HostReserved", reservedNamespace)
Check(reservedOK == false, "foreign host claimed the canonical MSUFUnitFrames global")
Check(tostring(reservedError):find("project-specific", 1, true) ~= nil,
    "reserved-global error was not descriptive")
Check(_G.MSUFUnitFrames == nil and next(reservedNamespace) == nil,
    "reserved-global failure left partial state")

local noGlobalNamespace, noGlobalFramework = LoadHost("HostNoGlobal")
Check(noGlobalFramework.globalName == nil, "metadata-free host invented a public global")
Check(_G.HostNoGlobal == nil and noGlobalNamespace.MSUFUnitFrames == noGlobalFramework,
    "metadata-free host was not namespace-only")
Check(_G.MSUF_UFCore == legacyCoreSentinel,
    "metadata-free host changed the legacy UFCore global")
Check(libStubTouches == 0, "embedded hosts touched LibStub")

print("PASS unitframes embed isolation: XML order, shared _G, local styles/elements, guarded globals, no LibStub")

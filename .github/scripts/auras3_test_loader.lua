-- Test-only compatibility for pre-split Auras3 harnesses. Production load order
-- remains in XML; this adapter makes legacy loadfile(entry) exercise that exact
-- contiguous factory group before its entry point. Source-based contracts read
-- the same group, retaining all assertions across file moves.
local Loader = {}
local compileSource = loadstring or load
-- The WoW Lua dialect forwards arguments through xpcall; PUC Lua 5.1 does
-- not. Model that client contract in the harness, never in addon hot paths.
do
    _G.debugstack = _G.debugstack or function(start)
        return debug.traceback("", (start or 1) + 1)
    end
    local native = xpcall
    local ok, forwarded = native(function(value) return value end, function(err) return err end, true)
    if ok and forwarded ~= true then
        local unpack, select = unpack, select
        _G.xpcall = function(fn, handler, ...)
            local count = select("#", ...)
            if count == 0 then return native(fn, handler) end
            local args = { ... }
            return native(function() return fn(unpack(args, 1, count)) end, handler)
        end
    end
end
local originalLoadfile, originalOpen = loadfile, io.open
local sourceRoot
local xmlRelative = "MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Auras.xml"
local families = {
    ["MSUF_Auras3_UnitFrames.lua"] = "MSUF_Auras3_Runtime_",
    ["MSUF_Auras3_SpellIndicators.lua"] = "MSUF_Auras3_SpellIndicators_",
    ["MSUF_Auras3_EditMode.lua"] = "MSUF_Auras3_EditMode_",
    ["MSUF_Auras3_Menu_Model.lua"] = "MSUF_Auras3_Menu_",
}

local function Normalize(path)
    path = tostring(path):gsub("\\", "/")
    local absolute = path:sub(1, 1) == "/"
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
            parts[#parts] = nil
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return (absolute and "/" or "") .. table.concat(parts, "/")
end

local function SourcePath(path)
    if not sourceRoot or type(path) ~= "string" then return path end
    local normalized = Normalize(path)
    local relative = normalized:match("(MidnightSimpleUnitFrames/Auras3/.*)$")
    return relative and sourceRoot .. "/" .. relative or path
end

function Loader.SetSourceRoot(root)
    sourceRoot = root and Normalize(root):gsub("/$", "") or nil
end

local function Read(path)
    local file = assert(originalOpen(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

-- One slicer for every function body this loader lifts out of a shipped file.
-- It ends each slice at the function's own `end` and a miss is fatal, naming
-- the declaration and the file: a renamed function used to drop a contract
-- here without a word, quietly reducing what the aura suite covers.
local Slice = assert(originalLoadfile(".github/scripts/msuf_source_slice.lua"),
    "auras3_test_loader: .github/scripts/msuf_source_slice.lua is missing; run from the repository root")()

-- Ownership/inventory checks need one physical file, not a legacy module group.
function Loader.ReadSource(path) return Read(SourcePath(path)) end

function Loader.Group(path)
    if type(path) ~= "string" then return nil end
    path = Normalize(path)
    local entry = path:match("([^/]+)$")
    local directory = path:match("^(.*)/")
    if entry == "MSUF_Profiles.lua" or entry == "MSUF_Menu2_Window.lua"
        or entry == "MSUF_Menu2_ClassPowerPreview.lua" or entry == "MSUF_Menu2_Widgets.lua" then
        local file = originalOpen(path, "rb")
        if not file then return nil end
        file:close()
    end
    if entry == "MSUF_Defaults.lua" then
        local root = assert(path:match("^(.-)MidnightSimpleUnitFrames/State/"))
        local toc = Read(root .. "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc")
        local group = {}
        for line in toc:gmatch("[^\r\n]+") do
            local relative = line:gsub("\\", "/"):match("^%s*(State/[^%s]+%.lua)")
            if relative and (relative == "State/MSUF_Defaults.lua" or relative == "State/MSUF_AuraDefaults.lua"
                or relative:match("^State/Defaults/")) then
                group[#group + 1] = root .. "MidnightSimpleUnitFrames/" .. relative
            end
        end
        assert(#group > 0, "defaults group absent from core TOC")
        return group
    end
    if entry == "MSUF_Profiles.lua" then
        return { directory .. "/MSUF_ProfileRuntime.lua", directory .. "/MSUF_ProfileNormalize.lua", path }
    elseif entry == "MSUF_Menu2_Window.lua" then
        return { directory .. "/MSUF_Menu2_PageLifecycle.lua", path }
    elseif entry == "MSUF_Menu2_Widgets.lua" then
        -- W.Color and W.ParseHexColor: the color picker module loads right after.
        return { path, directory .. "/MSUF_Menu2_ColorPicker.lua" }
    elseif entry == "MSUF_Menu2_ClassPowerPreview.lua" then
        return { directory .. "/MSUF_Menu2_ClassPowerPreview_Lifecycle.lua",
            directory .. "/MSUF_Menu2_ClassPowerPreview_Interaction.lua", path }
    end
    if entry == "MSUF_Menu2_Auras.lua" and path:find("MidnightSimpleUnitFrames_Options/", 1, true) then
        local directory = path:match("^(.*)/")
        return { directory .. "/MSUF_Menu2_AuraSettings.lua", directory .. "/MSUF_Menu2_AuraControls.lua", path }
    end
    local family = families[entry]
    if not family then return nil end
    local root = path:match("^(.-)MidnightSimpleUnitFrames/Auras3/")
    if root == nil then return nil end
    local xmlPath = root .. xmlRelative
    local xmlFile = originalOpen(xmlPath, "rb")
    if not xmlFile then
        xmlPath = xmlPath:gsub("MSUF_UFCore_Auras%.xml$", "MSUF_UFCore_Elements.xml")
        xmlFile = originalOpen(xmlPath, "rb")
    end
    if not xmlFile then return nil end -- Frozen pre-refactor source is standalone.
    local xml = xmlFile:read("*a")
    xmlFile:close()
    local xmlDirectory = xmlPath:match("^(.*)/")
    local group = {}
    for relative in xml:gmatch('<Script%s+file="([^"]+)"%s*/>') do
        local script = Normalize(xmlDirectory .. "/" .. relative)
        local filename = script:match("([^/]+)$")
        if script == path then
            group[#group + 1] = script
            return group
        elseif filename:sub(1, #family) == family then
            group[#group + 1] = script
        else
            group = {}
        end
    end
    return nil
end

-- The shipped Kernel namespace API (Bootstrap's ExportPublic with the global
-- keep policy, Public/PublicGlobals, and Require/Optional), run from the owners
-- into a harness namespace that has none (tools/tests/require_fixture.lua).
-- With a file's source, providers that file requires and the harness does not
-- load get forwarders that raise when used without a provider (DeferRequired).
local RequireFixture
local InstallKernel

-- The Kernel owners every core TOC loads ahead of its consumers (in this order).
-- A consumer a harness loads without one of them gets that real owner, found by
-- the names it exports: nothing is mirrored here. A provider the harness already
-- supplied is kept. An owner that builds frames when it loads (`lazy`) loads on
-- the first use of one of its names instead of with its consumer, so a world
-- that never reaches it creates no frame for it.
local KERNEL_OWNERS = {
    { file = "Shell/EditMode/MSUF_EditMode_Geometry.lua" },
    { file = "Kernel/MSUF_Util.lua", needs = "Shell/EditMode/MSUF_EditMode_Geometry.lua" },
    { file = "Kernel/MSUF_EventBus.lua", lazy = true },
    -- The font stack's early owner: it needs event-capable frames at load.
    { file = "Kernel/MSUF_Libs.lua", fonts = true, lazy = true },
    { file = "Runtime/MSUF_BorderStyles.lua" },
}
local ownerByFile, ownerByExport = {}, nil
local loadedOwners = setmetatable({}, { __mode = "k" })

local function OwnerFor(name)
    if not ownerByExport then
        ownerByExport = {}
        for _, owner in ipairs(KERNEL_OWNERS) do
            ownerByFile[owner.file] = owner
            local text = Read(SourcePath("MidnightSimpleUnitFrames/" .. owner.file))
            for exported in text:gmatch('ExportPublic%(%s*"([%w_]+)"') do
                ownerByExport[exported] = ownerByExport[exported] or owner
            end
        end
    end
    return ownerByExport[name]
end

-- A live value a harness published for a name (a global, or an owned registry
-- entry); the empty forwarders DeferRequired parks do not count.
local function IsForwarder(value)
    if type(value) ~= "table" or next(value) ~= nil then return false end
    local meta = getmetatable(value)
    return type(meta) == "table" and meta.__call ~= nil and meta.__index ~= nil and meta.__newindex ~= nil
end

local function LoadOwner(namespace, env, owner)
    local done = loadedOwners[namespace]
    if not done then done = {}; loadedOwners[namespace] = done end
    if done[owner.file] then return end
    done[owner.file] = true
    if owner.needs then LoadOwner(namespace, env, ownerByFile[owner.needs]) end
    local relative = "MidnightSimpleUnitFrames/" .. owner.file
    local text = Read(SourcePath(relative))
    local aliasMSUF, aliasNS = rawget(env, "MSUF"), rawget(env, "MSUF_NS")
    InstallKernel(namespace, env, text, relative)
    -- Providers the harness supplied before this owner loaded stay in place.
    local registry, kept = namespace.PublicGlobals, {}
    for exported in text:gmatch('ExportPublic%(%s*"([%w_]+)"') do
        local global, owned = rawget(env, exported), rawget(registry, exported)
        if global ~= nil or (owned ~= nil and not IsForwarder(owned)) then
            kept[#kept + 1] = { exported, global, not IsForwarder(owned) and owned or nil }
        end
    end
    if owner.fonts then
        assert(originalLoadfile("tools/tests/runtime_media_fixture.lua"))().LoadFonts(".", namespace, originalLoadfile, env)
    else
        local chunk = assert(originalLoadfile(SourcePath(relative)))
        if env ~= _G then setfenv(chunk, env) end
        chunk("MidnightSimpleUnitFrames", namespace)
    end
    for i = 1, #kept do
        local name, global, owned = kept[i][1], kept[i][2], kept[i][3]
        if global ~= nil then rawset(env, name, global) end
        if owned ~= nil then
            rawset(registry, name, owned)
            if type(namespace.Public) == "table" then namespace.Public[name:gsub("^MSUF_", "")] = owned end
        end
    end
    rawset(env, "MSUF", aliasMSUF)
    rawset(env, "MSUF_NS", aliasNS)
end

-- One named owner from the list above, with the owners it needs.
local function LoadKernelOwner(namespace, file, env)
    OwnerFor("")
    LoadOwner(namespace, env or _G, assert(ownerByFile[file], "auras3_test_loader: unknown Kernel owner " .. file))
end

-- A name resolves to a live provider; the empty forwarder an earlier file's
-- DeferRequired parked in the registry (require_fixture.lua) is not one.
local function IsProvided(namespace, name)
    local value = namespace.Optional(name)
    if value == nil then return false end
    if type(value) == "table" and next(value) == nil then
        local meta = getmetatable(value)
        if type(meta) == "table" and meta.__call and meta.__index and meta.__newindex then return false end
    end
    return true
end

local function EnsureOwners(namespace, env, source)
    local seen = {}
    for name in source:gmatch("Require%(%s*\"([%w_]+)\"") do
        if not seen[name] and not IsProvided(namespace, name) then
            seen[name] = true
            local owner = OwnerFor(name)
            if owner and not owner.lazy then LoadOwner(namespace, env, owner) end
        end
    end
end

-- The forwarder for a name a lazy owner provides: the first use loads the
-- owner, which replaces the registry entry, and every use reaches the live value.
local function ForwardLazily(namespace, env, name, owner)
    local registry = namespace.PublicGlobals
    local proxy
    local function Live()
        LoadOwner(namespace, env, owner)
        local live = rawget(env, name)
        if live == nil or live == proxy then live = rawget(registry, name) end
        if live == nil or live == proxy then
            error("fixture: " .. name .. " was used, but its owner " .. owner.file .. " does not export it", 3)
        end
        return live
    end
    proxy = setmetatable({}, {
        __index = function(_, key) return Live()[key] end,
        __newindex = function(_, key, value) Live()[key] = value end,
        __call = function(_, ...) return Live()(...) end,
    })
    rawset(registry, name, proxy)
end

function InstallKernel(namespace, env, source, path)
    if type(namespace) ~= "table" then return end
    env = env or _G
    RequireFixture = RequireFixture or assert(originalLoadfile("tools/tests/require_fixture.lua"))()
    if not (type(namespace.ExportPublic) == "function" and type(namespace.PublicGlobals) == "table"
        and type(namespace.Require) == "function" and type(namespace.Optional) == "function") then
        RequireFixture.InstallKernel(".", namespace, env, originalLoadfile, true)
    end
    if source then
        EnsureOwners(namespace, env, source)
        for _, name in ipairs(RequireFixture.DeferRequired(namespace, source, path, env)) do
            local owner = OwnerFor(name)
            if owner and owner.lazy then ForwardLazily(namespace, env, name, owner) end
        end
    end
end

local function UsesKernel(source)
    for _, key in ipairs({ "MSUF.Require", "MSUF.Optional", "MSUF.ExportPublic", "MSUF.Public", "MSUF.ExportCompat",
        "MSUF.ExportGlobal", "ns.Require", "ns.Optional", "ns.ExportPublic", "ns.Public" }) do
        if source:find(key, 1, true) then return true end
    end
    return false
end

local function SharedSourceFunction(path, name, preamble)
    local source = Read(SourcePath(path))
    local body = Slice.Function(source, "local function " .. name, path)
    return assert(compileSource((preamble or "") .. body .. "\nreturn " .. name))()
end

-- Additional earlier owners needed by consumers after removing production
-- test fallbacks. Bodies are read from the actual owners; none are mirrored.
local function PrepareDirectContracts(source, namespace)
    if type(namespace) ~= "table" then return end
    _G.issecretvalue = _G.issecretvalue or function() return false end
    _G.wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.canaccesstable = _G.canaccesstable or function() return true end
    local function Uses(text) return source:find(text, 1, true) ~= nil end
    -- Both aura backends lay their dispel overlay strip out through the shared
    -- border runtime (Runtime/MSUF_BorderStyles.lua, loaded early by every TOC).
    if Uses("MSUF.BorderStyles.LayoutEdgeStrip") or Uses("MSUF.BorderStyles and MSUF.BorderStyles.LayoutEdgeStrip") then
        local styles = namespace.BorderStyles
        if not (type(styles) == "table" and type(styles.LayoutEdgeStrip) == "function") then
            LoadKernelOwner(namespace, "Runtime/MSUF_BorderStyles.lua")
        end
    end
    local function Bind(owner, name, preamble, ...)
        local text = Read(SourcePath(owner))
        local body = Slice.Function(text, "local function " .. name, owner)
        return assert(compileSource((preamble or "") .. body .. "\nreturn " .. name))(...)
    end
    local function BindPublic(owner, prefix, name, target)
        local source = Read(SourcePath(owner))
        local body = Slice.Function(source, "function " .. prefix .. "." .. name, owner)
        assert(compileSource("local " .. prefix .. " = ...\n" .. body))(target)
    end
    -- An external Edit Mode provider takes the controller's registrar and setter from
    -- MSUF.Require("MSUF_EM2").ExternalProviders; the owner's own bodies stand in for it.
    if Uses("_G.MSUF_EM2.ExternalProviders.Create")
        or (Uses('Require("MSUF_EM2"') and Uses("ExternalProviders.CreateElementRegistrar")) then
        _G.MSUF_EM2 = _G.MSUF_EM2 or {}
        _G.MSUF_EM2.ExternalProviders = _G.MSUF_EM2.ExternalProviders or {}
        local target = _G.MSUF_EM2.ExternalProviders
        for _, name in ipairs({"CreateEnabledSetter", "CreateElementRegistrar", "ActivateAtLogin"}) do
            if not target[name] then BindPublic("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua", "External", name, target) end
        end
    end
    if Uses("CreateAnimationStarter") then
        namespace.MSUF2 = namespace.MSUF2 or {}
        local menu = namespace.MSUF2
        menu.PreviewHelpers = menu.PreviewHelpers or {}
        if not menu.PreviewHelpers.CreateAnimationStarter then
            BindPublic("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua", "H", "CreateAnimationStarter", menu.PreviewHelpers)
        end
    end
    if Uses("MSUF_IsGroupUnitToken") and not _G.MSUF_IsGroupUnitToken then
        _G.MSUF_IsGroupUnitToken = Bind("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua", "IsGroupUnitToken")
    end
    if Uses("= MSUF.Translate") and not namespace.Translate then
        local text = Read(SourcePath("MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"))
        local body = Slice.Function(text, "function MSUF.Translate", "MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua")
        assert(compileSource("local MSUF = ...\nlocal L = MSUF.L or _G.MSUF_L or {}\n" .. body))(namespace)
    end
    if (source:match("= MSUF%.ExportPublic[ \t]*[\r\n]") or source:match("= ns%.ExportPublic[ \t]*[\r\n]")) and not namespace.ExportPublic then
        -- The whole Bootstrap owner: ExportPublic reads its global keep policy.
        InstallKernel(namespace)
    end
    if Uses("= MSUF.UF.GetFrame") then
        namespace.UF = namespace.UF or {}
        if not namespace.UF.GetFrame then
            namespace.UF.frames = namespace.UF.frames or {}
            local text = Read(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"))
            local body = Slice.Function(text, "function UF.GetFrame", "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
            assert(compileSource("local UF = ...\nlocal issecretvalue = _G.issecretvalue or function() return false end\n" .. body))(namespace.UF)
        end
    end
    -- Partial UF/Edit Mode/Menu consumers need the same early request owner as the core TOCs.
    if Uses("UF.Preview") then
        local fixture = assert(originalLoadfile("tools/tests/preview_namespace_fixture.lua"))()
        fixture.Install(".", namespace, _G, originalLoadfile)
    end
    if Uses("MSUF.Secrets") then
        assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua")))("MSUF", namespace)
    end
    if Uses("MSUF.MSUF_Auras3.GetDurationBarColor") then
        namespace.MSUF_Auras3 = namespace.MSUF_Auras3 or {}
        if not namespace.MSUF_Auras3.GetDurationBarColor then
            local owner = "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"
            local text = Read(SourcePath(owner))
            local rootDB = Slice.Function(text, "local function RootDB", owner)
            local clamp = Slice.Function(text, "local function DurationColorComponent", owner)
            local body = Slice.Function(text, "function A3.GetDurationBarColor", owner)
            local preamble = "local A3, MSUF = ...\n" .. rootDB .. "\n" .. clamp .. "\n"
            assert(compileSource(preamble .. body))(namespace.MSUF_Auras3, namespace)
        end
    end
    if Uses("Layers.BorderOffset") then
        assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua")))("MSUF", namespace)
    end
    if Uses("Layers.BaseFrameLevel") then
        namespace.UF = namespace.UF or {}
        namespace.UF.Layers = namespace.UF.Layers or {}
        if not namespace.UF.Layers.BaseFrameLevel then
            local text = Read(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua"))
            local body = Slice.Function(text, "function Layers.BaseFrameLevel", "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua")
            assert(compileSource("local Layers = ...\n" .. body))(namespace.UF.Layers)
        end
    end
    if Uses("= Apply.Text") or Uses("= Apply.Shown") or Uses("= Apply.Texture") or Uses("= Apply.ColorTexture") then
        namespace.Apply = namespace.Apply or {}
        local text = Read(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Apply.lua"))
        for _, name in ipairs({ "Text", "Shown", "ShownPlain", "Texture", "ColorTexture" }) do
            if not namespace.Apply[name] then
                local body = Slice.Function(text, "function Apply." .. name, "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Apply.lua")
                assert(compileSource("local Apply = ...\nlocal issecretvalue = _G.issecretvalue or function() return false end\nlocal IsSecret = issecretvalue\n" .. body))(namespace.Apply)
            end
        end
    end
    if Uses("MSUF.UFBarTextCommon.HealthModeNeedsIdentity") then
        namespace.UFBarTextCommon = namespace.UFBarTextCommon or {}
        namespace.UFBarTextCommon.HealthModeNeedsIdentity = Bind("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua", "HealthModeNeedsIdentity")
    end
    if Uses("MSUF.UF.Clamp01") then
        namespace.UF = namespace.UF or {}
        namespace.UF.Clamp01 = namespace.UF.Clamp01 or Bind("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua", "Clamp01")
    end
    if Uses("UF.IsUnitToken") then
        namespace.UF = namespace.UF or {}
        namespace.UF.IsUnitToken = namespace.UF.IsUnitToken or Bind("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua", "IsUnitToken", "local issecretvalue = _G.issecretvalue\n")
    end
    if Uses("UF.ReadConnectedCached") or Uses("UF.ReadDeadCached") then
        namespace.UF = namespace.UF or {}
        local text = Read(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"))
        local parts = { "local UF = ...\nlocal issecretvalue = _G.issecretvalue\n" }
        for _, name in ipairs({ "IsUnitToken", "FreshUnitState", "IdentityDispatchState", "ReadConnectedCached", "ReadDeadCached" }) do
            parts[#parts + 1] = Slice.Function(text, "local function " .. name, "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
        end
        parts[#parts + 1] = "UF.ReadConnectedCached = UF.ReadConnectedCached or ReadConnectedCached\nUF.ReadDeadCached = UF.ReadDeadCached or ReadDeadCached"
        assert(compileSource(table.concat(parts, "\n")))(namespace.UF)
    end
    if Uses("Text.ApplyNameTextColor") or Uses("Text.ApplyInlineTextColor") then
        local text = namespace.UFText
        if text then
            for _, name in ipairs({ "ApplyNameTextColor", "ApplyInlineTextColor" }) do
                text[name] = text[name] or Bind("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua", name, "local Text = ...\nlocal SECRET_NATIVE_CLASS_COLOR = 2\nlocal NameTextColor, InlineTextColor = Text.NameTextColor, Text.InlineTextColor\nlocal SetNameTextColor, SetInlineTextColor = Text.SetNameTextColor, Text.SetInlineTextColor\nlocal function ApplySecretClassTextColor(primary, secondary, class, alpha) local color = C_ClassColor.GetClassColor(class); if not color then return false end; local r,g,b = color:GetRGB(); if primary then primary:SetTextColor(r,g,b,alpha) end; if secondary then secondary:SetTextColor(r,g,b,alpha) end; return true end\n", text)
            end
        end
    end
    if Uses("UF.IsBossUnit") then
        namespace.UF = namespace.UF or {}
        namespace.UF.IsBossUnit = namespace.UF.IsBossUnit or Bind("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua", "IsBossUnit")
    end
    if Uses("GF.GetLiveGroupKind") or Uses("GF.GetAnchorPoint") then
        namespace.GF = namespace.GF or {}
        -- GetAnchorPoint and ANCHOR_POINTS live in the geometry part of the group DB.
        local owners = {
            GetLiveGroupKind = "MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua",
            GetAnchorPoint = "MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Geometry.lua",
        }
        for _, name in ipairs({ "GetLiveGroupKind", "GetAnchorPoint" }) do
            if not namespace.GF[name] then
                local owner = owners[name]
                local text = Read(SourcePath(owner))
                local body = Slice.Function(text, "function GF." .. name, owner)
                local points = text:match("local ANCHOR_POINTS = %b{}") or ""
                assert(compileSource("local GF = ...\n" .. points .. "\n" .. body))(namespace.GF)
            end
        end
    end
    if Uses("_G.MSUF_UF_ScheduleApplyCommit") then
        local owner = "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"
        local text = Read(SourcePath(owner))
        local commit = Slice.Function(text, "local function ApplyDirtyCommit", owner)
        _G.MSUF_UF_ScheduleApplyCommit = Bind(owner, "ScheduleApplyCommit", "local MSUF = ...\n" .. commit .. "\n", namespace)
    end
    if Uses("_G.MSUF_GetSharedMedia") then
        _G.MSUF_GetSharedMedia = Bind("MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua", "GetLSM", "local MSUF = ...\n", namespace)
    end
    if Uses("_G.MSUF_EnsureCastbarGeneralDB") then
        _G.MSUF_EnsureCastbarGeneralDB = Bind("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua", "EnsureGeneralDB", "local ExportPublic = ...\n", namespace.ExportPublic or function(name, value) _G[name] = value; return value end)
    end
    if Uses("MSUF.DefaultsStageFactories") or Uses("A3.NormalizeProfileDB") or Uses("MSUF.MSUF_CreateCanonicalPlayerDefensiveAuraContainer") then
        local manifest = assert(originalLoadfile("tools/tests/client_manifest.lua"))()
        namespace.Client = namespace.Client or { IsClassic = false }
        local flavor = namespace.Client.IsClassic and "Vanilla" or "Mainline"
        manifest.LoadSelected(".", flavor, namespace, {
            "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Schema.lua", "State/Defaults/MSUF_Defaults_Shell.lua",
            "State/Defaults/MSUF_Defaults_Bars.lua", "State/Defaults/MSUF_Defaults_Units.lua",
        }, originalLoadfile)
    end
    -- The explicit optional-dependency helper (Kernel/MSUF_Require.lua), loaded
    -- from its owner into a harness namespace that has no kernel.
    if Uses("MSUF.Optional(") and not namespace.Optional then
        InstallKernel(namespace)
    end
    if Uses("MSUF_NormalizeFontKey") or Uses("MSUF.MSUF_GetGlobalFontSettings()")
        or Uses("A3.NormalizeProfileDB") or Uses("MSUF.DefaultsStageFactories") then
        local fixture = assert(originalLoadfile("tools/tests/runtime_media_fixture.lua"))()
        fixture.LoadFonts(".", namespace, originalLoadfile)
    end
    -- The Auras3 core's strata helpers, bound from their owner for harnesses
    -- that stand in for the core with a hand-built A3 table.
    local auras3 = namespace.MSUF_Auras3
    if (Uses("A3.SyncFrameStrata(") or Uses("A3.ReadParentFrameStrata(")) and type(auras3) == "table"
        and auras3.SyncFrameStrata == nil then
        local owner = "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"
        local preamble = "local AuraStrataIsSecret = _G.issecretvalue\n"
        auras3.ReadParentFrameStrata = auras3.ReadParentFrameStrata or Bind(owner, "ReadParentFrameStrata", preamble)
        auras3.SyncFrameStrata = Bind(owner, "SyncFrameStrata", preamble)
    end
    -- The Auras3 core's unit lane-key schema, built from its owner for harnesses
    -- that load the menu or runtime schema without the core.
    if Uses("A3.LaneKeySchema") and type(auras3) == "table" and auras3.LaneKeySchema == nil then
        local owner = "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"
        local text = Read(SourcePath(owner))
        local parts = {
            Slice.Function(text, "local function DeepCopy", owner),
            Slice.Function(text, "local function LaneKeySchemaRows", owner),
            Slice.Function(text, "local function BuildLaneKeySchema", owner),
            "return BuildLaneKeySchema()",
        }
        auras3.LaneKeySchema = assert(compileSource("local MSUF = ...\n" .. table.concat(parts, "\n")))(namespace)
    end
    -- The core's Custom Aura container constants, read from their owner.
    if (Uses("A3.CUSTOM_CONTAINER_COUNT") or Uses("A3.PRESET_CUSTOM_CONTAINER_INDEX")) and type(auras3) == "table"
        and auras3.CUSTOM_CONTAINER_COUNT == nil then
        local owner = "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"
        local text = Read(SourcePath(owner))
        for _, name in ipairs({ "CUSTOM_CONTAINER_COUNT", "PRESET_CUSTOM_CONTAINER_INDEX" }) do
            local value = text:match("\nlocal " .. name .. " = (%d+)")
            assert(value, "auras3_test_loader: " .. name .. " is missing from " .. owner)
            auras3[name] = tonumber(value)
        end
    end
    if Uses("local Shape = A3.IconShape") then
        assert(originalLoadfile("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_IconShape.lua"))("MidnightSimpleUnitFrames", namespace)
    end
    -- Chunks that paint preview auras take the shipped painter, which the Core TOC loads before them.
    if (Uses(").MockAuraPainter") or Uses("Auras.MockAuraPainter")) and type(auras3) == "table" and not auras3.MockAuraPainter then
        assert(originalLoadfile("tools/tests/aura_mock_painter_fixture.lua"))().Install(".", namespace)
    end
    if Uses("A3.NormalizeProfileDB") and not namespace.MSUF_MaterializeUnitAuraLaneOwners then
        if not namespace.ProfilePolicy then
            assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua")))("MSUF", namespace)
        end
        assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/State/MSUF_StateHelpers.lua")))("MSUF", namespace)
            assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")))("MSUF", namespace)
    end
    local M = namespace.MSUF2
    if M and (Uses("M.TranslateText") or Uses("M.Tr")) and not M.Tr then
        local text = Read(SourcePath("MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"))
        local body = Slice.Function(text, "function MSUF.Translate", "MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua")
        local provider = { L = namespace.L or _G.MSUF_L or {} }
        assert(compileSource("local MSUF = ...\nlocal L = MSUF.L\n" .. body))(provider)
        M.Tr = provider.Translate
    end
    if M and Uses("M.SetFixedPreviewExpandedPreference") and not M.SetFixedPreviewExpandedPreference then
        BindPublic("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets_PreviewDock.lua", "M", "SetFixedPreviewExpandedPreference", M)
    end
    if M and Uses("M.ApplyLocaleSelection") and not M.ApplyLocaleSelection then
        local text = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua"))
        local parts = { "local MSUF = ...\nlocal M = MSUF.MSUF2" }
        for _, name in ipairs({ "ClientLocale", "IsSupportedLocale" }) do
            parts[#parts + 1] = Slice.Function(text, "local function " .. name, "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua")
        end
        for _, name in ipairs({ "GetLocaleSelection", "ResolveLocaleSelection", "ShowLocaleReloadRequired", "ApplyLocaleSelection" }) do
            parts[#parts + 1] = Slice.Function(text, "function M." .. name, "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua")
        end
        assert(compileSource(table.concat(parts, "\n")))(namespace)
    end
    if M and Uses("M.MarkMenuDataDirty") and not M.MarkMenuDataDirty then
        local text = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window_PageNavigation.lua"))
        local reader = Slice.Function(text, "local function CurrentMenuDataRevision", "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window_PageNavigation.lua")
        local writer = Slice.Function(text, "function M.MarkMenuDataDirty", "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window_PageNavigation.lua")
        assert(compileSource("local M = ...\n" .. reader .. "\n" .. writer))(M)
    end
    if M then
        local support = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua"))
        for _, name in ipairs({ "Lines", "KeySetFromWords", "FindPageEntry", "PageKeyForWidget" }) do
            if Uses("M." .. name) and not M[name] then
                local body = Slice.Function(support, "function M." .. name, "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua")
                assert(compileSource("local M = ...\n" .. body))(M)
            end
        end
        local catalog = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlCatalog.lua"
        for _, name in ipairs({ "NormalizeControlPath", "PortableControlToken", "AuraCatalogToken", "GroupAuraSettingKeys" }) do
            if Uses("M." .. name) and not M[name] then M[name] = Bind(catalog, name) end
        end
        if Uses("M.AccessibleNumber") and not M.AccessibleNumber then
            M.AccessibleNumber = Bind("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua", "AccessibleNumber")
        end
        if Uses("M.ApplyService.CallGlobal") then
            M.ApplyService = M.ApplyService or {}
            if not M.ApplyService.CallGlobal then
                local text = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ApplyService.lua"))
                local body = Slice.Function(text, "function Apply.CallGlobal", "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ApplyService.lua")
                M.ApplyService.Invoke = M.ApplyService.Invoke or M.InvokeBoundary or _G.MSUF_InvokeBoundary
                assert(compileSource("local Apply = ...\n" .. body))(M.ApplyService)
            end
        end
        if Uses("= M.Format") and not M.Format then
            local text = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua"))
            local body = Slice.Function(text, "M.Format = function", "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua")
            if not M.Tr then
                local locale = Read(SourcePath("MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"))
                local tr = Slice.Function(locale, "function MSUF.Translate", "MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua")
                local provider = { L = namespace.L or _G.MSUF_L or {} }
                assert(compileSource("local MSUF = ...\nlocal L = MSUF.L\n" .. tr))(provider)
                M.Tr = provider.Translate
            end
            assert(compileSource("local M = ...\n" .. body))(M)
        end
        if Uses("W.ThemedControlCard") or Uses("W.ToggleBadge") or Uses("W.SetTileVisual") then
            M.Widgets = M.Widgets or {}
            local owner = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua"
            for _, name in ipairs({ "ThemedControlCard", "ToggleBadge", "SetTileVisual" }) do
                if not M.Widgets[name] then M.Widgets[name] = Bind(owner, name, "local W, T = ...\n", M.Widgets, M.Theme) end
            end
        end
        if Uses("M.TrimText") and not M.TrimText then M.TrimText = Bind("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua", "TrimText") end
        if Uses("PreviewHelpers.ReadPreviewBarsBool") then
            M.PreviewHelpers = M.PreviewHelpers or {}
            M.PreviewHelpers.ReadPreviewBarsBool = M.PreviewHelpers.ReadPreviewBarsBool or Bind("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua", "ReadPreviewBarsBool")
        end
        if Uses("M.Widgets.SetTextLayout") or Uses("M.Widgets.ResolveContextColorOption") then
            M.Widgets = M.Widgets or {}
            local owners = {
                SetTextLayout = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua",
                ResolveContextColorOption = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets_ContextColors.lua",
            }
            for _, name in ipairs({ "SetTextLayout", "ResolveContextColorOption" }) do
                M.Widgets[name] = M.Widgets[name] or Bind(owners[name], name)
            end
        end
        if Uses("PreviewHelpers.ExactPreviewDelta") then
            M.PreviewHelpers = M.PreviewHelpers or {}
            M.PreviewHelpers.ExactPreviewDelta = Bind("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua", "ExactPreviewDelta")
        end
    end
end

local function NeedsDirectContracts(source)
    if (source:match("= MSUF%.ExportPublic[ \t]*[\r\n]") or source:match("= ns%.ExportPublic[ \t]*[\r\n]")) then return true end
    for _, key in ipairs({ "CreateAnimationStarter", "_G.MSUF_EM2.ExternalProviders.Create", "ExternalProviders.CreateElementRegistrar", "MSUF_IsGroupUnitToken", "Text.ApplyNameTextColor", "Text.ApplyInlineTextColor", "MSUF.Secrets", "Layers.BorderOffset", "= Apply.ColorTexture", "_G.issecretvalue", "_G.wipe", "M.Lines", "M.KeySetFromWords", "M.FindPageEntry", "M.PageKeyForWidget", "MSUF_NormalizeFontKey", "A3.NormalizeProfileDB", "M.TranslateText", "M.Tr", "= MSUF.Translate", "= MSUF.UF.GetFrame", "MSUF.Secrets.PlainBool",
        "MSUF.MSUF_Auras3.GetDurationBarColor", "Layers.BaseFrameLevel", "= Apply.Text", "= Apply.Shown", "= Apply.Texture", "MSUF.UF.Clamp01", "MSUF.UFBarTextCommon.HealthModeNeedsIdentity", "UF.IsBossUnit", "GF.GetLiveGroupKind", "GF.GetAnchorPoint", "_G.MSUF_UF_ScheduleApplyCommit", "_G.MSUF_GetSharedMedia", "_G.MSUF_EnsureCastbarGeneralDB", "M.AuraCatalogToken", "M.GroupAuraSettingKeys", "M.TrimText", "PreviewHelpers.ReadPreviewBarsBool", "M.Widgets.SetTextLayout", "M.Widgets.ResolveContextColorOption", "M.NormalizeControlPath", "M.PortableControlToken", "M.AccessibleNumber",
        "M.ApplyService.CallGlobal", "= M.Format", "W.ThemedControlCard", "W.ToggleBadge", "W.SetTileVisual", "PreviewHelpers.ExactPreviewDelta",
        "MSUF.Optional(", "MSUF.MSUF_GetGlobalFontSettings()", "A3.SyncFrameStrata(", "A3.ReadParentFrameStrata(",
        "A3.LaneKeySchema", "A3.CUSTOM_CONTAINER_COUNT", "A3.PRESET_CUSTOM_CONTAINER_INDEX", ").MockAuraPainter", "Auras.MockAuraPainter" }) do
        if source:find(key, 1, true) then return true end
    end
    return false
end

local function PrepareSharedDependencies(path, namespace)
    if type(namespace) ~= "table" then return end
    if path:match("MSUF_Menu2_State%.lua$") or path:match("MSUF_EditMode_HUD_Dock%.lua$") then
        if not _G.MSUF_GetCharKey then
            local source = Read(SourcePath("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))
            local body = Slice.Function(source, "function MSUF_GetCharKey", "MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
            local api = "local function UnitName(unit) return _G.UnitName and _G.UnitName(unit) or 'Unknown' end\n"
                .. "local function GetRealmName() return _G.GetRealmName and _G.GetRealmName() or 'Realm' end\n"
            assert(compileSource(api .. body))()
        end
    end
    if path:match("MSUF_UF_Shared%.lua$") or path:match("MSUF_UF_Group_Config%.lua$") then
        if not (namespace.UF and namespace.UF.ResolveBarGradient) then
            assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")))("MidnightSimpleUnitFrames", namespace)
        end
    end
    if path:match("MSUF_EditMode_Core%.lua$") or path:match("MSUF_AnchorPicker%.lua$") then
        if not namespace.Translate then
            local source = Read(SourcePath("MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"))
            local body = Slice.Function(source, "function MSUF.Translate", "MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua")
            assert(compileSource("local MSUF = ...\nlocal L = MSUF.L or _G.MSUF_L or {}\n" .. body))(namespace)
        end
    end
    if path:match("MSUF_Menu2_UnitPreview_Render%.lua$") or path:match("MSUF_Menu2_GroupPreview_Render%.lua$")
        or path:match("MSUF_Menu2_ClassPowerPreview%.lua$") or path:match("MSUF_Menu2_UnitPreview_View_Chrome%.lua$") then
        local M = namespace.MSUF2 or _G.MSUF2 or {}
        namespace.MSUF2 = M
        M.PreviewHelpers = M.PreviewHelpers or {}
        local owner = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"
        M.PreviewHelpers.HealthBackgroundColorMode = M.PreviewHelpers.HealthBackgroundColorMode or SharedSourceFunction(owner, "PreviewBackgroundColorMode")
        M.PreviewHelpers.SetCanvasToolsShown = M.PreviewHelpers.SetCanvasToolsShown or SharedSourceFunction(owner, "SetCanvasToolsShown")
    end
end

local function DependencyChunk(path, ...)
    if path:match("/MSUFUnitFrames/init%.lua$") then return originalLoadfile(path, ...) end
    local source = Read(path)
    local product = path:find("MidnightSimpleUnitFrames/", 1, true) or path:find("MidnightSimpleUnitFrames_Options/", 1, true)
    -- Every shipped file runs after the Kernel in its TOC; a harness namespace
    -- without one gets the real Kernel API before the file's main chunk.
    local kernel = product and UsesKernel(source) and not (path:match("/Kernel/MSUF_Bootstrap%.lua$")
        or path:match("/Kernel/MSUF_Require%.lua$"))
    if product and (source:find("MSUF.Geometry", 1, true) or source:find("MSUF.Castbars.UNIT_CASTBAR", 1, true)
        or source:find("MSUF.EditModeKinds", 1, true)) then
        local chunk, message = originalLoadfile(path, ...)
        if not chunk then return nil, message end
        return function(addon, namespace)
            if kernel then InstallKernel(namespace, getfenv and getfenv(1) or _G, source, path) end
            assert(originalLoadfile("tools/tests/editmode_prerequisites.lua"))().Install(".", namespace, nil, originalLoadfile)
            PrepareSharedDependencies(path, namespace)
            return chunk(addon, namespace)
        end
    end
    local direct = NeedsDirectContracts(source)
    if not direct and not kernel and not (path:match("MSUF_UF_Shared%.lua$") or path:match("MSUF_UF_Group_Config%.lua$")
        or path:match("MSUF_EditMode_Core%.lua$") or path:match("MSUF_AnchorPicker%.lua$")
        or path:match("MSUF_Menu2_State%.lua$") or path:match("MSUF_EditMode_HUD_Dock%.lua$")
        or path:match("MSUF_Menu2_UnitPreview_Render%.lua$") or path:match("MSUF_Menu2_GroupPreview_Render%.lua$")
        or path:match("MSUF_Menu2_ClassPowerPreview%.lua$") or path:match("MSUF_Menu2_UnitPreview_View_Chrome%.lua$")) then
        return originalLoadfile(path, ...)
    end
    local chunk, message = originalLoadfile(path, ...)
    if not chunk then return nil, message end
    return function(addon, namespace, ...)
        local dependencyNamespace = namespace or _G.MSUF_NS or _G.MSUF
        if kernel then InstallKernel(namespace, getfenv and getfenv(1) or _G, source, path) end
        PrepareSharedDependencies(path, dependencyNamespace)
        if direct then PrepareDirectContracts(source, dependencyNamespace) end
        if setfenv and getfenv then setfenv(chunk, getfenv(1)) end
        return chunk(addon, namespace, ...)
    end
end

function Loader.PrepareDependencies(path, namespace)
    PrepareSharedDependencies(path, namespace)
    PrepareDirectContracts(Read(SourcePath(path)), namespace)
end

function Loader.LoadFile(path, ...)
    path = SourcePath(path)
    if path:match("MSUF_EditMode_Core%.lua$") or path:match("MSUF_EditMode_Layout%.lua$")
        or path:match("MSUF_EditMode_HUD_Selection%.lua$") then
        local chunk, message = DependencyChunk(path, ...)
        if not chunk then return nil, message end
        return function(addon, namespace)
            local source = Read("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
            local body = Slice.Function(source, "local function RequestGroupGeometryApply", "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
            _G.MSUF_RequestGroupGeometryApply = assert(compileSource("local MSUF = ...\n" .. body .. "\nreturn RequestGroupGeometryApply"))(namespace)
            return chunk(addon, namespace)
        end
    end
    if path:match("MSUF_Menu2_UnitPreview_Model%.lua$") then
        local chunk, message = DependencyChunk(path, ...)
        if not chunk then return nil, message end
        return function(addon, namespace)
            local M = namespace.MSUF2 or _G.MSUF2
            if M and not M.ProfileSystemNeedsInit then
                local source = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings.lua")
                local body = Slice.Function(source, "local function ProfileSystemNeedsInit", "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Bindings.lua")
                M.ProfileSystemNeedsInit = assert(compileSource(body .. "\nreturn ProfileSystemNeedsInit"))()
            end
            return chunk(addon, namespace)
        end
    end
    local group = Loader.Group(path)
    if not group or #group == 1 then return DependencyChunk(path, ...) end
    local chunks = {}
    for i = 1, #group do
        local loader = path:match("MSUF_Defaults%.lua$") and originalLoadfile or DependencyChunk
        local chunk, message = loader(group[i], ...)
        if not chunk then return nil, message end
        chunks[i] = chunk
    end
    return function(...)
        if path:match("MSUF_Auras3_UnitFrames%.lua$") then
            local _, namespace = ...
            if namespace and not (namespace.MSUF_Auras3 and namespace.MSUF_Auras3.CompileCustomAuraAliases) then
                local root = assert(Normalize(path):match("^(.-)MidnightSimpleUnitFrames/Auras3/")):gsub("/$", "")
                Loader.LoadAliasCatalog(root ~= "" and root or ".", namespace)
            end
        end
        if path:match("MSUF_Defaults%.lua$") then
            for i = 1, #chunks do setfenv(chunks[i], getfenv(1)) end
        end
        for i = 1, #chunks - 1 do chunks[i](...) end
        return chunks[#chunks](...)
    end
end

-- Test environments do not process the enclosing XML. Load the actual alias
-- prerequisites from that XML, including the old resolver in frozen baselines.
function Loader.LoadAliasCatalog(root, namespace)
    root = sourceRoot or root
    namespace.MSUF_Auras3 = namespace.MSUF_Auras3 or {}
    namespace.MSUF_Auras3.AuraSpellIDAliases = namespace.MSUF_Auras3.AuraSpellIDAliases or {}
    _G.GetLocale = _G.GetLocale or function() return "enUS" end
    local tocPath = root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc"
    local tocFile = originalOpen(tocPath, "rb")
    if tocFile then
        local toc = tocFile:read("*a"); tocFile:close()
        for line in toc:gmatch("[^\r\n]+") do
            if line:find("MSUF_Auras3_AliasData_", 1, true) and not line:match("^%s*#") then
                local allowed = line:match("%[AllowLoadTextLocale%s+([^%]]+)%]")
                local selected = not allowed
                if allowed then
                    for locale in allowed:gmatch("%a+") do
                        if locale == _G.GetLocale() then selected = true end
                    end
                end
                if selected then
                    local relative = assert(line:match("^%s*(%S+%.lua)"))
                    assert(originalLoadfile(Normalize(root .. "/MidnightSimpleUnitFrames/" .. relative)))("MidnightSimpleUnitFrames", namespace)
                end
            end
        end
    end
    local xmlPath = root .. "/" .. xmlRelative
    local probe = originalOpen(xmlPath, "rb")
    if probe then probe:close()
    else xmlPath = xmlPath:gsub("MSUF_UFCore_Auras%.xml$", "MSUF_UFCore_Elements.xml") end
    local xml = Read(xmlPath)
    local directory = xmlPath:match("^(.*)/")
    for relative in xml:gmatch('<Script%s+file="([^"]+)"%s*/>') do
        if relative:find("MSUF_Auras3_AliasData_", 1, true)
            or relative:find("MSUF_Auras3_AuraAliases.lua", 1, true)
            or relative:find("MSUF_Auras3_AuraNameResolver.lua", 1, true) then
            assert(originalLoadfile(Normalize(directory .. "/" .. relative)))("MidnightSimpleUnitFrames", namespace)
        end
    end
end

function Loader.ReadGroup(path)
    path = SourcePath(path)
    local group = Loader.Group(path)
    if not group or #group == 1 then return Read(path) end
    local sources = {}
    for i = 1, #group do
        local source = Read(group[i])
        -- Preserve each factory file's local scope when a harness compiles a
        -- group source. Keep the entry unwrapped for existing test-only suffixes.
        if i < #group then source = "do\n" .. source .. "\nend\n" end
        sources[#sources + 1] = source
    end
    return table.concat(sources, "\n")
end

-- The older Edit Mode harness exposes selected private locals through a suffix.
-- Inject those assignments at the owning factory's return instead: the addon
-- itself gains no testing exports, and the function under test is unchanged.
function Loader.SourceWithExports(path, exports)
    path = SourcePath(path)
    local group = Loader.Group(path) or { path }
    local sources, remaining = {}, {}
    for symbol, destination in pairs(exports) do remaining[symbol] = destination end
    for i = 1, #group do
        local source, injected = Read(group[i]), {}
        for symbol, destination in pairs(remaining) do
            if source:find("local function " .. symbol .. "(", 1, true) then
                injected[#injected + 1] = "MSUF.MSUF_Auras3." .. destination .. " = " .. symbol
                remaining[symbol] = nil
            end
        end
        if #injected > 0 then
            table.sort(injected)
            local assignments = "\n" .. table.concat(injected, "\n") .. "\n"
            if i == #group then
                source = source .. assignments
            else
                local at
                for position in source:gmatch("()\nreturn {") do at = position end
                assert(at, "test export factory return missing: " .. group[i])
                source = source:sub(1, at - 1) .. assignments .. source:sub(at)
            end
        end
        if i < #group then source = "do\n" .. source .. "\nend\n" end
        sources[#sources + 1] = source
    end
    assert(next(remaining) == nil, "private test export was not found in its XML group")
    return table.concat(sources, "\n")
end

local function SourceFile(source)
    local offset, closed = 1, false
    local file = {}
    function file:read(format)
        assert(not closed, "attempt to use a closed source file")
        if format == "*a" then
            local value = source:sub(offset)
            offset = #source + 1
            return value
        elseif format == "*l" or format == nil then
            if offset > #source then return nil end
            local ending = source:find("\n", offset, true)
            local value = source:sub(offset, ending and ending - 1 or #source)
            offset = ending and ending + 1 or #source + 1
            return value:gsub("\r$", "")
        elseif type(format) == "number" then
            if offset > #source then return nil end
            local value = source:sub(offset, offset + format - 1)
            offset = offset + #value
            return value
        end
        error("unsupported Auras3 test source read: " .. tostring(format))
    end
    function file:lines() return function() return self:read("*l") end end
    function file:close() closed = true; return true end
    return file
end

-- MSUF_SetFontChecked is the Kernel-owned guarded SetFont that aura, castbar
-- and preview text apply through. Harnesses that never load MSUF_Libs.lua get
-- its real definition here, so the helper cannot drift from production.
local function InstallSetFontChecked()
    if _G.MSUF_SetFontChecked ~= nil then return end
    local libs = Read(SourcePath("MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua"))
    local helper = Slice.Function(libs, "local function MSUF_SetFontChecked",
        "MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua")
    _G.MSUF_SetFontChecked = assert(compileSource(helper .. "\nreturn MSUF_SetFontChecked"))()
end

-- The shared protected-call boundaries live in Kernel/MSUF_Boundary.lua and
-- are consumed as globals by files that harnesses load standalone. Publish the
-- real module through a throwaway namespace so the helpers cannot drift.
local function InstallBoundary()
    if _G.MSUF_ReportError ~= nil then return end
    local chunk = assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua")))
    local ns = {}
    ns.ExportPublic = function(name, value) _G[name] = value; return value end
    chunk("MidnightSimpleUnitFrames", ns)
end

function Loader.Install()
    InstallSetFontChecked()
    InstallBoundary()
    local geometryNS = {}
    assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Geometry.lua")))(
        "MidnightSimpleUnitFrames", geometryNS)
    _G.MSUF_RoundOffset = geometryNS.Geometry.RoundOffset
    _G.MSUF_UF_FrameRectToUI = geometryNS.Geometry.VisibleRect
    -- Pure shared rules are provided by earlier TOC owners. Standalone
    -- consumers get the exact source bodies, without loading unrelated UI.
    for _, rule in ipairs({
        { "Kernel/MSUF_Libs.lua", "MSUF_ComposeFontFlags", "MSUF_ComposeFontFlags" },
        { "State/MSUF_Defaults.lua", "MSUF_ResolveFontShadowMetrics", "MSUF_ResolveFontShadowMetrics" },
        { "Kernel/MSUF_Util.lua", "GetGeneralDB", "MSUF_GetGeneralDB" },
        { "Auras3/MSUF_Auras3_Core.lua", "TableHasAnyKey", "MSUF_AuraTableHasAnyKey" },
        { "UnitFrames/Engine/Group/MSUF_UF_Group_SpellRegistry.lua", "CopyTable", "MSUF_GF_CopySpellConfig" },
        { "Kernel/MSUF_Util.lua", "IsGlobalCooldownAnchorEnabled", "MSUF_GlobalCooldownAnchorEnabled", "local CooldownAnchorSupported = function() return _G.MSUF_CooldownAnchorSupported() end\n" },
        { "Castbars/MSUF_CastbarAnchors.lua", "CastbarFrameInset", "MSUF_CastbarFrameInset" },
        { "Castbars/MSUF_CastbarUtils.lua", "CastTimeUnitKey", "MSUF_CastTimeUnitKey" },
        { "UnitFrames/Effects/MSUF_UF_RoundedSurface.lua", "ClampEdgeSize", "MSUF_ClampRoundedEdgeSize" },
        { "UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua", "NormalizeRaidManagerMode", "MSUF_NormalizeRaidManagerMode" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "NormalizePlayerHPShape", "MSUF_UF_NormalizePlayerHPShape" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "NormalizeDetachedPowerShape", "MSUF_UF_NormalizeDetachedPowerShape" },
        { "Auras3/MSUF_Auras3_Core.lua", "SpellIDFromKey", "MSUF_AuraSpellIDFromKey" },
        { "Auras3/MSUF_Auras3_Core.lua", "ButtonAnchor", "MSUF_AuraButtonAnchor" },
        { "Castbars/MSUF_CastbarVisuals.lua", "NormalizeJustify", "MSUF_NormalizeCastbarTextJustify" },
        { "Castbars/MSUF_CastbarVisuals.lua", "NormalizeSpellNameTruncate", "MSUF_NormalizeCastbarTruncate" },
        { "Kernel/MSUF_Util.lua", "CooldownAnchorSupported", "MSUF_CooldownAnchorSupported", "local MSUF = _G.MSUF_NS or {}\n" },
        { "Kernel/MSUF_Util.lua", "IsPlayerInCombat", "MSUF_IsPlayerInCombat" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "NormalizeShapeAlign", "MSUF_UF_NormalizeShapeAlign" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "ShapeOutlineAlpha", "MSUF_UF_ShapeOutlineAlpha" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "OutlineModeEnabled", "MSUF_UF_OutlineModeEnabled" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "NormalizeClassPowerShape", "MSUF_UF_NormalizeClassPowerShape" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "MaskHas", "MSUF_UF_MaskHas" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "ClampBoxAxis", "MSUF_UF_ClampBoxAxis" },
        { "Castbars/MSUF_CastbarVisuals.lua", "NormalizeTextPosition", "MSUF_NormalizeCastbarTextPosition" },
        { "Auras3/MSUF_Auras3_Core.lua", "AnchorOffset", "MSUF_AuraAnchorOffset" },
        { "Auras3/MSUF_Auras3_Core.lua", "PaddingInset", "MSUF_AuraPaddingInset" },
        { "Auras3/MSUF_Auras3_Core.lua", "NormalizeDispelTrigger", "MSUF_NormalizeDispelBorderTrigger" },
        { "Castbars/MSUF_CastbarVisuals.lua", "NormalizeIconPosition", "MSUF_NormalizeCastbarIconPosition" },

        { "Auras3/MSUF_Auras3_Core.lua", "NormalizeDebuffTypeBorderMode", "MSUF_NormalizeAuraDebuffTypeBorderMode" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "PointFraction", "MSUF_UF_PointFraction" },
        -- Built on the debuff-type rule above, which the core binds as a sibling local.
        { "Auras3/MSUF_Auras3_Core.lua", "NormalizeDispelBorderMode", "MSUF_NormalizeLegacyDispelBorderMode", "local NormalizeDebuffTypeBorderMode = _G.MSUF_NormalizeAuraDebuffTypeBorderMode\n" },
        { "Auras3/MSUF_Auras3_Core.lua", "ReadParentFrameStrata", "MSUF_AuraReadParentFrameStrata", "local function AuraStrataIsSecret(value) return _G.issecretvalue and _G.issecretvalue(value) == true or false end\n" },
        { "Auras3/MSUF_Auras3_Core.lua", "SyncFrameStrata", "MSUF_AuraSyncFrameStrata", "local function AuraStrataIsSecret(value) return _G.issecretvalue and _G.issecretvalue(value) == true or false end\n" },
        { "Kernel/MSUF_Util.lua", "NormalizeFrameStrata", "MSUF_NormalizeFrameStrata", "local function IsSecretValue(value) return _G.issecretvalue and _G.issecretvalue(value) == true or false end\n" },
    }) do
        local owner = "MidnightSimpleUnitFrames/" .. rule[1]
        if rule[2] == "MSUF_ResolveFontShadowMetrics" then
            local moved = "MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Migrations.lua"
            local file = originalOpen(moved, "rb")
            if file then file:close(); owner = moved end
        end
        local body = Slice.Function(Read(SourcePath(owner)), "local function " .. rule[2], owner)
        _G[rule[3]] = assert(compileSource((rule[4] or "") .. body .. "\nreturn " .. rule[2]))()
    end
    local shared = Read(SourcePath("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"))
    local axis = Slice.Function(shared, "local function ClampBoxAxis", "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua")
    _G.MSUF_UF_ClampAnchorOffsetOnScreen = SharedSourceFunction("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua", "ClampAnchorOffsetOnScreen", "local PointFraction = _G.MSUF_UF_PointFraction\n" .. axis .. "\n")
    _G.loadfile = Loader.LoadFile
    io.open = function(path, mode)
        if mode == nil or mode == "r" or mode == "rb" then
            path = SourcePath(path)
            local group = not path:match("MSUF_Defaults%.lua$") and Loader.Group(path)
            if group and #group > 1 then return SourceFile(Loader.ReadGroup(path)) end
        end
        return originalOpen(path, mode)
    end
end

return Loader

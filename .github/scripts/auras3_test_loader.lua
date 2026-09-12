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
local xmlRelative = "MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml"
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

-- Ownership/inventory checks need one physical file, not a legacy module group.
function Loader.ReadSource(path) return Read(SourcePath(path)) end

function Loader.Group(path)
    if type(path) ~= "string" then return nil end
    path = Normalize(path)
    local entry = path:match("([^/]+)$")
    local directory = path:match("^(.*)/")
    if entry == "MSUF_Profiles.lua" or entry == "MSUF_Menu2_Window.lua"
        or entry == "MSUF_Menu2_ClassPowerPreview.lua" then
        local file = originalOpen(path, "rb")
        if not file then return nil end
        file:close()
    end
    if entry == "MSUF_Profiles.lua" then
        return { directory .. "/MSUF_ProfileRuntime.lua", path }
    elseif entry == "MSUF_Menu2_Window.lua" then
        return { directory .. "/MSUF_Menu2_PageLifecycle.lua", path }
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

local function SharedSourceFunction(path, name, preamble)
    local source = Read(SourcePath(path))
    local body = assert(source:match("local function " .. name .. "%b().-\r?\nend"), name)
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
    local function Bind(owner, name, preamble, ...)
        local text = Read(SourcePath(owner))
        local body = assert(text:match("local function " .. name .. "%b().-\r?\nend"), name)
        return assert(compileSource((preamble or "") .. body .. "\nreturn " .. name))(...)
    end
    local function BindPublic(owner, prefix, name, target)
        local source = Read(SourcePath(owner))
        local body = assert(source:match("function " .. prefix .. "%." .. name .. "%b().-\r?\nend"), name)
        assert(compileSource("local " .. prefix .. " = ...\n" .. body))(target)
    end
    if Uses("_G.MSUF_EM2.ExternalProviders.Create") then
        _G.MSUF_EM2 = _G.MSUF_EM2 or {}
        _G.MSUF_EM2.ExternalProviders = _G.MSUF_EM2.ExternalProviders or {}
        local target = _G.MSUF_EM2.ExternalProviders
        for _, name in ipairs({"CreateEnabledSetter", "CreateElementRegistrar"}) do
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
        local body = assert(text:match("function MSUF.Translate%b().-\r?\nend"))
        assert(compileSource("local MSUF = ...\nlocal L = MSUF.L or _G.MSUF_L or {}\n" .. body))(namespace)
    end
    if (source:match("= MSUF%.ExportPublic[ \t]*[\r\n]") or source:match("= ns%.ExportPublic[ \t]*[\r\n]")) and not namespace.ExportPublic then
        local text = Read(SourcePath("MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua"))
        local body = assert(text:match("function MSUF.MSUF_ExportPublic%b().-\r?\nend"))
        namespace.Public, namespace.PublicGlobals = {}, {}
        namespace.Compat = namespace.Compat or {}
        namespace.Compat.LegacyGlobals = namespace.Compat.LegacyGlobals or {}
        local key = assert(text:match("local function PublicKey%b().-\r?\nend"))
        assert(compileSource("local MSUF = ...\n" .. key .. "\n" .. body))(namespace)
        namespace.ExportPublic = namespace.MSUF_ExportPublic
    end
    if Uses("= MSUF.UF.GetFrame") then
        namespace.UF = namespace.UF or {}
        if not namespace.UF.GetFrame then
            namespace.UF.frames = namespace.UF.frames or {}
            local text = Read(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"))
            local body = assert(text:match("function UF.GetFrame%b().-\r?\nend"))
            assert(compileSource("local UF = ...\nlocal issecretvalue = _G.issecretvalue or function() return false end\n" .. body))(namespace.UF)
        end
    end
    if Uses("MSUF.Secrets") then
        assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua")))("MSUF", namespace)
    end
    if Uses("MSUF.MSUF_Auras3.GetDurationBarColor") then
        namespace.MSUF_Auras3 = namespace.MSUF_Auras3 or {}
        if not namespace.MSUF_Auras3.GetDurationBarColor then
            local common = Read(SourcePath("MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Common.lua"))
            local clamp = assert(common:match("local function Clamp01%b().-\r?\n    end"))
            local text = Read(SourcePath("MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Storage.lua"))
            local body = assert(text:match("function Model.GetDurationBarColor%b().-\r?\n    end"))
            assert(compileSource("local Model = ...\n" .. clamp .. "\n" .. body))(namespace.MSUF_Auras3)
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
            local body = assert(text:match("function Layers.BaseFrameLevel%b().-\r?\nend"))
            assert(compileSource("local Layers = ...\n" .. body))(namespace.UF.Layers)
        end
    end
    if Uses("= Apply.Text") or Uses("= Apply.Shown") or Uses("= Apply.Texture") or Uses("= Apply.ColorTexture") then
        namespace.Apply = namespace.Apply or {}
        local text = Read(SourcePath("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Apply.lua"))
        for _, name in ipairs({ "Text", "Shown", "Texture", "ColorTexture" }) do
            if not namespace.Apply[name] then
                local body = assert(text:match("function Apply." .. name .. "%b().-\r?\nend"))
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
            parts[#parts + 1] = assert(text:match("local function " .. name .. "%b().-\r?\nend"))
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
        local text = Read(SourcePath("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))
        for _, name in ipairs({ "GetLiveGroupKind", "GetAnchorPoint" }) do
            if not namespace.GF[name] then
                local body = assert(text:match("function GF." .. name .. "%b().-\r?\nend"))
                local points = text:match("local ANCHOR_POINTS = %b{}") or ""
                assert(compileSource("local GF = ...\n" .. points .. "\n" .. body))(namespace.GF)
            end
        end
    end
    if Uses("_G.MSUF_UF_ScheduleApplyCommit") then
        local owner = "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"
        local text = Read(SourcePath(owner))
        local commit = assert(text:match("local function ApplyDirtyCommit%b().-\r?\nend"))
        _G.MSUF_UF_ScheduleApplyCommit = Bind(owner, "ScheduleApplyCommit", "local MSUF = ...\n" .. commit .. "\n", namespace)
    end
    if Uses("_G.MSUF_GetSharedMedia") then
        _G.MSUF_GetSharedMedia = Bind("MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua", "GetLSM", "local MSUF = ...\n", namespace)
    end
    if Uses("_G.MSUF_EnsureCastbarGeneralDB") then
        _G.MSUF_EnsureCastbarGeneralDB = Bind("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua", "EnsureGeneralDB", "local ExportPublic = ...\n", namespace.ExportPublic or function(name, value) _G[name] = value; return value end)
    end
    if Uses("A3.NormalizeProfileDB") and not namespace.MSUF_MaterializeUnitAuraLaneOwners then
        assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/State/MSUF_StateHelpers.lua")))("MSUF", namespace)
            assert(originalLoadfile(SourcePath("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")))("MSUF", namespace)
    end
    if Uses("MSUF_NormalizeFontKey") and not _G.MSUF_NormalizeFontKey then
        local text = Read(SourcePath("MidnightSimpleUnitFrames/Runtime/MSUF_FontRegistry.lua"))
        local keys = assert(text:match("local MSUF_INTERNAL_LSM_FONT_KEYS = %b{}"))
        _G.MSUF_NormalizeFontKey = Bind("MidnightSimpleUnitFrames/Runtime/MSUF_FontRegistry.lua", "MSUF_NormalizeFontKey", keys .. "\n")
    end
    local M = namespace.MSUF2
    if M and (Uses("M.TranslateText") or Uses("M.Tr")) and not M.Tr then
        local text = Read(SourcePath("MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"))
        local body = assert(text:match("function MSUF.Translate%b().-\r?\nend"))
        local provider = { L = namespace.L or _G.MSUF_L or {} }
        assert(compileSource("local MSUF = ...\nlocal L = MSUF.L\n" .. body))(provider)
        M.Tr = provider.Translate
    end
    if M and Uses("M.SetFixedPreviewExpandedPreference") and not M.SetFixedPreviewExpandedPreference then
        BindPublic("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua", "M", "SetFixedPreviewExpandedPreference", M)
    end
    if M and Uses("M.ApplyLocaleSelection") and not M.ApplyLocaleSelection then
        local text = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua"))
        local parts = { "local MSUF = ...\nlocal M = MSUF.MSUF2" }
        for _, name in ipairs({ "ClientLocale", "IsSupportedLocale" }) do
            parts[#parts + 1] = assert(text:match("local function " .. name .. "%b().-\r?\nend"))
        end
        for _, name in ipairs({ "GetLocaleSelection", "ResolveLocaleSelection", "ShowLocaleReloadRequired", "ApplyLocaleSelection" }) do
            parts[#parts + 1] = assert(text:match("function M%." .. name .. "%b().-\r?\nend"))
        end
        assert(compileSource(table.concat(parts, "\n")))(namespace)
    end
    if M and Uses("M.MarkMenuDataDirty") and not M.MarkMenuDataDirty then
        local text = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window_PageNavigation.lua"))
        local reader = assert(text:match("local function CurrentMenuDataRevision%b().-\r?\nend"))
        local writer = assert(text:match("function M.MarkMenuDataDirty%b().-\r?\nend"))
        assert(compileSource("local M = ...\n" .. reader .. "\n" .. writer))(M)
    end
    if M then
        local support = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua"))
        for _, name in ipairs({ "Lines", "KeySetFromWords", "FindPageEntry", "PageKeyForWidget" }) do
            if Uses("M." .. name) and not M[name] then
                local body = assert(support:match("function M." .. name .. "%b().-\r?\nend"), name)
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
                local body = assert(text:match("function Apply.CallGlobal%b().-\r?\nend"))
                M.ApplyService.Invoke = M.ApplyService.Invoke or M.InvokeBoundary or _G.MSUF_InvokeBoundary
                assert(compileSource("local Apply = ...\n" .. body))(M.ApplyService)
            end
        end
        if Uses("= M.Format") and not M.Format then
            local text = Read(SourcePath("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua"))
            local body = assert(text:match("M.Format = function%b().-\r?\nend"))
            if not M.Tr then
                local locale = Read(SourcePath("MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua"))
                local tr = assert(locale:match("function MSUF.Translate%b().-\r?\nend"))
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
            local owner = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Widgets.lua"
            for _, name in ipairs({ "SetTextLayout", "ResolveContextColorOption" }) do
                M.Widgets[name] = M.Widgets[name] or Bind(owner, name)
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
    for _, key in ipairs({ "CreateAnimationStarter", "_G.MSUF_EM2.ExternalProviders.Create", "MSUF_IsGroupUnitToken", "Text.ApplyNameTextColor", "Text.ApplyInlineTextColor", "MSUF.Secrets", "Layers.BorderOffset", "= Apply.ColorTexture", "_G.issecretvalue", "_G.wipe", "M.Lines", "M.KeySetFromWords", "M.FindPageEntry", "M.PageKeyForWidget", "MSUF_NormalizeFontKey", "A3.NormalizeProfileDB", "M.TranslateText", "M.Tr", "= MSUF.Translate", "= MSUF.UF.GetFrame", "MSUF.Secrets.PlainBool",
        "MSUF.MSUF_Auras3.GetDurationBarColor", "Layers.BaseFrameLevel", "= Apply.Text", "= Apply.Shown", "= Apply.Texture", "MSUF.UF.Clamp01", "MSUF.UFBarTextCommon.HealthModeNeedsIdentity", "UF.IsBossUnit", "GF.GetLiveGroupKind", "GF.GetAnchorPoint", "_G.MSUF_UF_ScheduleApplyCommit", "_G.MSUF_GetSharedMedia", "_G.MSUF_EnsureCastbarGeneralDB", "M.AuraCatalogToken", "M.GroupAuraSettingKeys", "M.TrimText", "PreviewHelpers.ReadPreviewBarsBool", "M.Widgets.SetTextLayout", "M.Widgets.ResolveContextColorOption", "M.NormalizeControlPath", "M.PortableControlToken", "M.AccessibleNumber",
        "M.ApplyService.CallGlobal", "= M.Format", "W.ThemedControlCard", "W.ToggleBadge", "W.SetTileVisual", "PreviewHelpers.ExactPreviewDelta" }) do
        if source:find(key, 1, true) then return true end
    end
    return false
end

local function PrepareSharedDependencies(path, namespace)
    if type(namespace) ~= "table" then return end
    if path:match("MSUF_Menu2_State%.lua$") or path:match("MSUF_EditMode_HUD%.lua$") then
        if not _G.MSUF_GetCharKey then
            local source = Read(SourcePath("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))
            local body = assert(source:match("function MSUF_GetCharKey%b().-\r?\nend"))
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
            local body = assert(source:match("function MSUF.Translate%b().-\r?\nend"))
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
    local direct = NeedsDirectContracts(source)
    if not direct and not (path:match("MSUF_UF_Shared%.lua$") or path:match("MSUF_UF_Group_Config%.lua$")
        or path:match("MSUF_EditMode_Core%.lua$") or path:match("MSUF_AnchorPicker%.lua$")
        or path:match("MSUF_Menu2_State%.lua$") or path:match("MSUF_EditMode_HUD%.lua$")
        or path:match("MSUF_Menu2_UnitPreview_Render%.lua$") or path:match("MSUF_Menu2_GroupPreview_Render%.lua$")
        or path:match("MSUF_Menu2_ClassPowerPreview%.lua$") or path:match("MSUF_Menu2_UnitPreview_View_Chrome%.lua$")) then
        return originalLoadfile(path, ...)
    end
    local chunk, message = originalLoadfile(path, ...)
    if not chunk then return nil, message end
    return function(addon, namespace, ...)
        local dependencyNamespace = namespace or _G.MSUF_NS or _G.MSUF
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
    if path:match("MSUF_EditMode_Core%.lua$") or path:find("Shell/UI/EditMode/MSUF_EditMode_", 1, true) then
        local chunk, message = DependencyChunk(path, ...)
        if not chunk then return nil, message end
        return function(addon, namespace)
            local source = Read("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
            local body = assert(source:match("local function RequestGroupGeometryApply%b().-\r?\nend"))
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
                local body = assert(source:match("local function ProfileSystemNeedsInit%b().-\r?\nend"))
                M.ProfileSystemNeedsInit = assert(compileSource(body .. "\nreturn ProfileSystemNeedsInit"))()
            end
            return chunk(addon, namespace)
        end
    end
    local group = Loader.Group(path)
    if not group or #group == 1 then return DependencyChunk(path, ...) end
    local chunks = {}
    for i = 1, #group do
        local chunk, message = DependencyChunk(group[i], ...)
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
    local xmlPath = root .. "/" .. xmlRelative
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
    local helper = assert(libs:match("local function MSUF_SetFontChecked%b().-\r?\nend"),
        "MSUF_SetFontChecked definition not found in MSUF_Libs.lua")
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
    -- Pure shared rules are provided by earlier TOC owners. Standalone
    -- consumers get the exact source bodies, without loading unrelated UI.
    for _, rule in ipairs({
        { "Kernel/MSUF_Libs.lua", "MSUF_ComposeFontFlags", "MSUF_ComposeFontFlags" },
        { "State/MSUF_Defaults.lua", "MSUF_ResolveFontShadowMetrics", "MSUF_ResolveFontShadowMetrics" },
        { "Kernel/MSUF_Util.lua", "GetGeneralDB", "MSUF_GetGeneralDB" },
        { "Auras3/MSUF_Auras3_Core.lua", "TableHasAnyKey", "MSUF_AuraTableHasAnyKey" },
        { "UnitFrames/Engine/Group/MSUF_UF_Group_SpellRegistry.lua", "CopyTable", "MSUF_GF_CopySpellConfig" },
        { "Kernel/MSUF_Util.lua", "IsGlobalCooldownAnchorEnabled", "MSUF_GlobalCooldownAnchorEnabled", "local CooldownAnchorSupported = function() return _G.MSUF_CooldownAnchorSupported() end\n" },
        { "Kernel/MSUF_Util.lua", "RoundOffset", "MSUF_RoundOffset" },
        { "Castbars/MSUF_CastbarAnchors.lua", "CastbarFrameInset", "MSUF_CastbarFrameInset" },
        { "Castbars/MSUF_CastbarUtils.lua", "CastTimeUnitKey", "MSUF_CastTimeUnitKey" },
        { "UnitFrames/Effects/MSUF_UF_RoundedFrames.lua", "ClampEdgeSize", "MSUF_ClampRoundedEdgeSize" },
        { "UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua", "NormalizeRaidManagerMode", "MSUF_NormalizeRaidManagerMode" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "NormalizePlayerHPShape", "MSUF_UF_NormalizePlayerHPShape" },
        { "UnitFrames/Engine/MSUF_UF_Shared.lua", "NormalizeDetachedPowerShape", "MSUF_UF_NormalizeDetachedPowerShape" },
        { "Auras3/MSUF_Auras3_Core.lua", "SpellIDFromKey", "MSUF_AuraSpellIDFromKey" },
        { "Auras3/MSUF_Auras3_Core.lua", "ButtonAnchor", "MSUF_AuraButtonAnchor" },
        { "Castbars/MSUF_CastbarVisuals.lua", "NormalizeJustify", "MSUF_NormalizeCastbarTextJustify" },
        { "Castbars/MSUF_CastbarVisuals.lua", "NormalizeSpellNameTruncate", "MSUF_NormalizeCastbarTruncate" },
        { "Kernel/MSUF_Util.lua", "CooldownAnchorSupported", "MSUF_CooldownAnchorSupported" },
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
        { "Kernel/MSUF_Util.lua", "FrameRectToUI", "MSUF_UF_FrameRectToUI" },
        { "Auras3/MSUF_Auras3_Core.lua", "NormalizeDispelBorderMode", "MSUF_NormalizeLegacyDispelBorderMode" },
        { "Auras3/MSUF_Auras3_Core.lua", "ReadParentFrameStrata", "MSUF_AuraReadParentFrameStrata", "local function AuraStrataIsSecret(value) return _G.issecretvalue and _G.issecretvalue(value) == true or false end\n" },
        { "Auras3/MSUF_Auras3_Core.lua", "SyncFrameStrata", "MSUF_AuraSyncFrameStrata", "local function AuraStrataIsSecret(value) return _G.issecretvalue and _G.issecretvalue(value) == true or false end\n" },
        { "Kernel/MSUF_Util.lua", "NormalizeFrameStrata", "MSUF_NormalizeFrameStrata", "local function IsSecretValue(value) return _G.issecretvalue and _G.issecretvalue(value) == true or false end\n" },
    }) do
        local source = Read(SourcePath("MidnightSimpleUnitFrames/" .. rule[1]))
        local body = source:match("local function " .. rule[2] .. "%b().-\nend")
        if body then
            _G[rule[3]] = assert(compileSource((rule[4] or "") .. body .. "\nreturn " .. rule[2]))()
        end
    end
    local shared = Read(SourcePath("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"))
    local axis = assert(shared:match("local function ClampBoxAxis%b().-\r?\nend"))
    _G.MSUF_UF_ClampAnchorOffsetOnScreen = SharedSourceFunction("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua", "ClampAnchorOffsetOnScreen", "local PointFraction = _G.MSUF_UF_PointFraction\n" .. axis .. "\n")
    _G.loadfile = Loader.LoadFile
    io.open = function(path, mode)
        if mode == nil or mode == "r" or mode == "rb" then
            path = SourcePath(path)
            local group = Loader.Group(path)
            if group and #group > 1 then return SourceFile(Loader.ReadGroup(path)) end
        end
        return originalOpen(path, mode)
    end
end

return Loader

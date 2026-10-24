-- Real UFText providers for narrow group, profile and catalog fixtures.
return function(namespace, root, previewRules)
    root = assert(root, "group fixture repository root required"):gsub("\\", "/"):gsub("/$", "")
    if not root:match("^%a:/") and root:sub(1, 1) ~= "/" then
        local command = package.config:sub(1, 1) == "\\" and "cd" or "pwd"
        local process = assert(io.popen(command), "group text fixture cannot resolve its working directory")
        local current = assert(process:read("*l"), "group text fixture working directory is empty")
        process:close()
        root = current:gsub("\\", "/") .. "/" .. root
    end
    local World = dofile(root .. "/tools/tests/client_world.lua")
    local client = namespace.Client
    local flavor = client and client.IsForever and "Forever" or client and client.Flavor or "Mainline"
    local world = World.New(root, flavor)
    -- Native boundary stays the fixture's UnitName, including later replacements.
    world.env.UnitName = function(unit) return _G.UnitName(unit) end
    local paths = World.Graph(root, World.CoreTOC(world.client.tocSuffix or flavor), "enUS",
        world.client.isForever and "camelot" or nil)
    local prefix = {}
    local lastProvider = previewRules and "/MSUF_CP_Controller_Colors.lua" or "/MSUF_UF_Text_Runtime.lua"
    local textReady, sceneReady, groupReady = false, not previewRules, not previewRules
    for _, path in ipairs(paths) do
        prefix[#prefix + 1] = path
        if path:find(lastProvider, 1, true) then textReady = true end
        if path:find("/MSUF_UF_UnitScene.lua", 1, true) then sceneReady = true end
        if path:find("/MSUF_UF_Group_Preview.lua", 1, true) then groupReady = true end
        if textReady and sceneReady and groupReady then break end
    end
    -- Legacy loadfile adapters rebind dependency chunks to the fixture globals.
    -- This isolated graph must execute each complete provider in its own world.
    function world:LoadFile(path, addon, ns)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local chunk = assert(loadstring(source, "@" .. path))
        setfenv(chunk, self.env)
        self.loading = path
        local ok, message = pcall(chunk, addon, ns)
        self.loading = nil
        return ok, message
    end
    world:LoadGraph("MidnightSimpleUnitFrames", prefix, world.core)
    local failure = world:FirstFailure()
    assert(not failure, "group text fixture provider failed: " .. tostring(failure and failure.message))
    namespace.UFText = world.core.UFText
    for _, name in ipairs({ "FormatValue", "FormatPercentValue", "FormatHealthString", "FormatPowerString", "TruncateName",
        "PercentFromValues", "MissingHealthFromValues", "ReadDisplayName" }) do
        assert(type(namespace.UFText[name]) == "function", "group fixture lacks real UFText." .. name)
    end
    if previewRules then
        -- Catalog previews bind the same shipped rule providers as the client.
        -- Keep their live registries isolated in this fixture world.
        namespace.UF.Config = world.core.UF.Config
        namespace.UF.UnitScene = world.core.UF.UnitScene
        namespace.UF.Shared = world.core.UF.Shared
        namespace.UF.Elements = world.core.UF.Elements
        namespace.GF = namespace.GF or {}
        namespace.GF.NewPreviewScene = world.core.GF.NewPreviewScene
        for name, provider in pairs(world.core) do
            if type(name) == "string" and name:match("^ClassPower") then namespace[name] = provider end
        end
        namespace.UF.elements = namespace.UF.elements or {}
        namespace.UF.elements.Portrait = world.core.UF.elements.Portrait
        namespace.UF.elements.Health = world.core.UF.elements.Health
        namespace.UFVisuals = world.core.UFVisuals
        namespace.ClassPowerColors = world.core.ClassPowerColors
        namespace.ExportPublic("MSUF_CP_CONST", world.core.Require("MSUF_CP_CONST", "catalog fixture"))
        namespace.Castbars.Visuals = world.core.Castbars.Visuals
        assert(type(namespace.ClassPowerColors.ResolveSlotColor) == "function", "catalog resource rule provider missing")
        assert(type(namespace.Castbars.Visuals.PaintIconBorder) == "function", "catalog castbar rule provider missing")
    end
    return namespace.UFText
end

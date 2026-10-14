-- Real UFText providers for narrow group, profile and catalog fixtures.
return function(namespace, root)
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
    for _, path in ipairs(paths) do
        prefix[#prefix + 1] = path
        if path:find("/MSUF_UF_Text_Runtime.lua", 1, true) then break end
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
    return namespace.UFText
end

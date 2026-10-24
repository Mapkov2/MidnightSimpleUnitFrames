-- Complete exported operations reaching every optional-callable boundary.
local Paths = {}
local function Upvalue(fn, name, replacement)
    for i = 1, 60 do
        local key, value = debug.getupvalue(fn, i)
        if not key then break end
        if key == name then
            if replacement ~= nil then debug.setupvalue(fn, i, replacement) end
            return value
        end
    end
end
local function FindUpvalue(fn, name, seen)
    seen = seen or {}
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    local value = Upvalue(fn, name)
    if value ~= nil then return value end
    for i = 1, 60 do
        local key, child = debug.getupvalue(fn, i)
        if not key then break end
        local found = FindUpvalue(child, name, seen)
        if found ~= nil then return found end
    end
end
function Paths.New(world, root, flavor, canonical)
    local rawType, rawTonumber, rawTostring, rawSecret = type, tonumber, tostring, issecretvalue
    local rawLoad, rawDofile, rawOpen = loadfile, dofile, io.open
    local function HarnessPath(path)
        if canonical and path:sub(1, #root + 1) == root .. "/" then
            local suffix = path:sub(#root + 2)
            if suffix:sub(1, 6) == "tools/" or suffix:sub(1, 8) == ".github/" then
                return canonical .. "/" .. suffix
            end
        end
        return path
    end
    _G.loadfile = function(path) return rawLoad(HarnessPath(path)) end
    _G.dofile = function(path) return rawDofile(HarnessPath(path)) end
    io.open = function(path, mode) return rawOpen(HarnessPath(path), mode) end
    -- The unit-frame files bind the cooldown anchor providers when they load: the counting stand-ins go
    -- in after the real owner exported and before the first consumer loads.
    local anchor
    local lookups, callbacks = 0, 0
    -- One function object each, so the copies the files bound at load are the ones the native
    -- registry (NativeFunctions) attributes.
    local function Resolver() lookups = lookups + 1; return anchor end
    local function UsableSize() lookups = lookups + 1; return anchor:GetWidth(), anchor:GetHeight() end
    local function Providers(env)
        env.MSUF_GetEffectiveCooldownFrame, env.MSUF_GetUsableCooldownAnchorSize = Resolver, UsableSize
    end
    local w = world.New(root, flavor, { beforeFile = function(path, env)
        if path:find("Elements/MSUF_UF_Elements_Power.lua", 1, true) or path:find("Engine/MSUF_UF_Factory.lua", 1, true) then
            Providers(env)
        end
    end })
    _G.loadfile, _G.dofile, io.open = rawLoad, rawDofile, rawOpen
    -- Each sandbox captures its own strict primitives; do not nest the
    -- fixture replacements across fresh worlds in the surrounding Lua VM.
    _G.type, _G.tonumber, _G.tostring, _G.issecretvalue = rawType, rawTonumber, rawTostring, rawSecret
    local e, u, f, g = w.env, w.UF, w.single, w.group
    local status, text = w.h.world.core.UFStatusRuntime, w.h.world.core.UFText
    e.UnitName = function() return "Player" end
    anchor = e.CreateFrame("Frame", nil, e.UIParent)
    anchor:SetPoint("CENTER", e.UIParent, "CENTER", 0, 0)
    anchor.GetObjectType = function() return "Frame" end
    e.CustomAnchor = anchor
    Providers(e)
    u.spawned, u.unitOrder, u.frames = true, { "target" }, { target = f }
    local cases = {}
    local function Add(name, run, prepare, iterations)
        cases[#cases + 1] = { name = name, run = run, prepare = prepare or function() end, iterations = iterations or 100 }
    end
    for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer", "CustomAnchor", "MissingAnchor" }) do
        Add("resolve:" .. name, function() return u.Factory.ResolveNamedAnchor(name) end)
        if name ~= "CustomAnchor" and name ~= "MissingAnchor" then
            Add("refresh:" .. name, function() return u.Factory.RefreshExternalAnchor(name) end,
                function() f.MSUFSpec.anchorFrameName = name end)
        end
    end
    Add("anchor:cycle", function() return u.Factory.AnchorDependsOn(anchor, f) end)
    Add("anchor:candidate", function() return u.Factory.IsAnchorCandidateAllowed(anchor, "target") end)
    Add("anchor:proxy", function() return e.MSUF_UpdateAllExternalAnchorProxies() end,
        function() f.MSUFSpec.anchorFrameName = "EssentialCooldownViewer"; u.Factory.RefreshExternalAnchor("EssentialCooldownViewer") end)
    Add("anchor:snapshot", function() return e.MSUF_SnapshotFrameToUIParentCenter(anchor, true) end)
    Add("spawn:secure", function() return u.CreateSecureUnitButton(nil, e.UIParent) end)
    Add("spawn:ping", function() return u.ConfigurePlayerResourcePing(f, "player") end,
        function() e.MSUF_DB.general.playerResourcePingEnabled = true; f.GetTargetInfo = function() return "original" end end)
    local resolver = function() callbacks = callbacks + 1; return "Player", "Realm" end
    Add("text:resolver", function() return text.SetDisplayNameResolver(resolver) end)
    Add("text:invalid-resolver", function() return text.SetDisplayNameResolver(false) end)
    Add("text:name-identity", function() return text.UpdateName(f, "MSUF_UNIT_IDENTITY", "target") end)
    Add("text:group-preview", function() return text.UpdateName(g, "MSUF_FORCE_UPDATE", "raid1") end)
    local drain
    e.C_Timer.NewTicker = function(_, callback) drain = callback; return { Cancel = function() end } end
    Add("text:drain", function()
        u.Elements.HealthText.MarkValueDirty(f)
        assert(drain, "dirty queue did not arm the native ticker")
        drain()
    end)
    Upvalue(status.UpdateLeader, "UnitIsGroupLeader", function() return true end)
    f.LeaderIndicator = f:CreateTexture()
    local cfg = { leader = { enabled = true, style = "CUSTOM" }, kind = "raid" }
    local gf = w.h.world.core.GF
    gf.GetLeaderTexture = function() callbacks = callbacks + 1; return "leader", 0, 1, 0, 1 end
    Add("status:leader-group", function() return status.UpdateLeader(f, cfg) end)
    Add("status:leader-global", function() return status.UpdateLeader(f, cfg) end,
        function() gf.GetLeaderTexture = false; e.MSUF_GetLeaderStatusIconTexture = gf.GetAssistTexture or resolver end)
    Add("status:gone-health", function()
        f._msufStatusTextValue, f._msufStatusTextLayout = "DEAD", cfg
        f._msufHealthStateNotify, f._msufGroupStateRefresh = nil, nil
        f._msufStatusTextHealthRefresh = nil
        return status.UpdateStatusText(f, { statusText = { enabled = false } }, "UNIT_CONNECTION")
    end, function()
        f.statusIndicatorText = f:CreateFontString()
        f._msufUpdateGroupVisualsGoneState = function() callbacks = callbacks + 1 end
    end)
    Add("width:observe", function() return e.MSUF_EnsureCooldownWidthObservers(true) end, function()
        e.MSUF_DB.general.castbarPlayerMatchWidth = "essential"
        e.MSUF_DB.general.enablePlayerCastbar = true
    end)
    local pending = {}
    Add("width:refresh", function()
        e.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer")
        while #pending > 0 do table.remove(pending, 1)() end
    end, function()
        e.C_Timer.After = function(_, callback) pending[#pending + 1] = callback end
        e.MSUF_DB.general.castbarPlayerMatchWidth = "essential"
        e.MSUF_DB.general.enablePlayerCastbar = true
        e.MSUF_DB.bars.detachedPowerBarWidthMode = "cooldown"
        e.MSUF_DB.target.powerBarDetached = true
        e.MSUF_DB.target.showPowerBar = true
        f.MSUFSpec.power.detachedWidthFrameName = "EssentialCooldownViewer"
        u.Elements.Power.RefreshDetachedExternalWidth = function() callbacks = callbacks + 1 end
        e.MSUF_RefreshCastbarCooldownWidthSource = function() callbacks = callbacks + 1 end
    end)
    local nativeResolver, nativeSize = e.MSUF_GetEffectiveCooldownFrame, e.MSUF_GetUsableCooldownAnchorSize
    local nativeCenter = anchor.GetCenter
    for _, mode in ipairs({ "hidden", "disabled", "missing", "offset-scale", "provider-change", "public" }) do
        Add("anchor:" .. mode, function()
            if mode == "provider-change" then
                local source = e.CreateFrame("Frame", nil, e.UIParent)
                source:SetPoint("CENTER", e.UIParent, "CENTER", 10, 20)
                e.MSUF_GetEffectiveCooldownFrame = function() lookups = lookups + 1; return source end
            end
            if mode == "public" then return e.MSUF_RefreshExternalUnitFrameAnchor("EssentialCooldownViewer") end
            return u.Factory.RefreshExternalAnchor("EssentialCooldownViewer")
        end, function()
            f.MSUFSpec.anchorFrameName = "EssentialCooldownViewer"
            f.MSUFSpec.enabled = mode ~= "disabled"
            anchor.GetCenter = mode == "hidden" and function() return nil, nil end or nativeCenter
            e.MSUF_GetEffectiveCooldownFrame = mode == "missing" and function() return nil end or nativeResolver
            e.EssentialCooldownViewer = nil
            e.MSUF_GetUsableCooldownAnchorSize = mode == "missing" and function() return nil end or nativeSize
            f.MSUFSpec.x, f.MSUFSpec.y = mode == "offset-scale" and 31 or 0, mode == "offset-scale" and -17 or 0
            anchor:SetScale(mode == "offset-scale" and 1.3 or 1)
        end)
    end
    for _, mode in ipairs({ "custom", "missing", "unit-apply", "group", "group-preview" }) do
        Add("layout:" .. mode, function()
            if mode == "group" then return w.GF.RefreshHeaderLayout() end
            if mode == "group-preview" then return w.GF.RefreshHeaderLayout() end
            if mode == "unit-apply" then return u.Factory.Apply("target") end
            return u.Factory.ForceReanchor("target")
        end, function()
            e.MSUF_GetEffectiveCooldownFrame, e.MSUF_GetUsableCooldownAnchorSize = nativeResolver, nativeSize
            anchor.GetCenter = nativeCenter
            local name = mode == "missing" and "MissingAnchor" or "CustomAnchor"
            e.MSUF_DB.target.anchorFrameName = name
            e.MSUF_DB.target.enabled = true
            local conf = w.GF.GetConf("raid")
            conf.anchorToFrame, conf.x, conf.y = name, 21, -13
            if mode == "group-preview" then g._msufGFIsPreviewFrame = true end
            u.Config.Refresh()
            if mode == "unit-apply" then u.frames.target = nil; e[u.FrameName("target")] = false end
        end, 10)
    end
    local atlasCache
    Add("status:atlas-cold", function()
        local cache = atlasCache
        for key in pairs(cache) do cache[key] = nil end
        return status.UpdateLeader(f, cfg)
    end, function()
        atlasCache = assert(FindUpvalue(status.UpdateLeader, "atlasKnown"), "atlas cache not reached")
        cfg.leader.style, gf.GetLeaderTexture, e.MSUF_GetLeaderStatusIconTexture = "DEFAULT", false, false
        e.C_Texture = { GetAtlasInfo = function() callbacks = callbacks + 1; return { width = 16, height = 16 } end }
    end)
    for _, kind in ipairs({ "absent", "table", "callable-table", "function" }) do
        local value = kind == "table" and {} or kind == "callable-table" and setmetatable({}, { __call = resolver })
            or kind == "function" and resolver or nil
        Add("resolver:" .. kind, function() return text.SetDisplayNameResolver(value) end)
        Add("round-layout:" .. kind, function() return u.CreateSecureUnitButton(nil, e.UIParent) end,
            function() e.MSUF_SetRoundLayoutToNearestPixel = value end)
        Add("ping-method:" .. kind, function()
            f._msufPlayerPingOriginalsCaptured = nil
            f.GetTargetInfo = value
            return u.ConfigurePlayerResourcePing(f, "player")
        end)
        Add("gone-callback:" .. kind, function()
            f._msufStatusTextValue, f._msufStatusTextLayout = "DEAD", cfg
            return status.UpdateStatusText(f, { statusText = { enabled = false } }, "UNIT_CONNECTION")
        end, function() f._msufUpdateGroupVisualsGoneState = value end)
        Add("visibility:" .. kind, function()
            u.Elements.HealthText.MarkValueDirty(f)
            assert(drain, "dirty queue did not arm")
            drain()
        end, function() u.FrameVisibleForEvent = value end)
        Add("anchor-resolver:" .. kind, function() return u.Factory.ResolveNamedAnchor("EssentialCooldownViewer") end,
            function() e.MSUF_GetEffectiveCooldownFrame = kind == "function" and nativeResolver or value end)
        Add("anchor-size:" .. kind, function() return u.Factory.ResolveNamedAnchor("EssentialCooldownViewer") end,
            function() e.MSUF_GetUsableCooldownAnchorSize = kind == "function" and nativeSize or value end)
        Add("anchor-center:" .. kind, function() return e.MSUF_UpdateAllExternalAnchorProxies() end,
            function() anchor.GetCenter = kind == "function" and nativeCenter or value end)
        Add("width-callback:" .. kind, function()
            e.MSUF_ScheduleCooldownWidthRefresh("EssentialCooldownViewer")
            while #pending > 0 do table.remove(pending, 1)() end
        end, function()
            u.Elements.Power.RefreshDetachedExternalWidth = value
            e.MSUF_RefreshCastbarCooldownWidthSource = value
        end)
    end
    for _, mode in ipairs({ "missing", "empty", "configured-hidden", "preview-hidden", "default-unit", "missing-default", "empty-default", "configured-hidden-default", "nil-frame" }) do
        Add("name:" .. mode, function()
            local unit = mode == "default-unit" and nil or "target"
            if mode == "default-unit" or mode:find("default", 1, true) then unit = nil end
            if mode == "nil-frame" then return text.UpdateName(nil, "MSUF_FORCE_UPDATE", unit) end
            return text.UpdateName(f, "MSUF_FORCE_UPDATE", unit)
        end, function()
            f.MSUFUnitKey = "target"
            if mode == "missing" or mode == "missing-default" then f.MSUFUnitKey = nil end
            if mode == "empty" or mode == "empty-default" then f.MSUFUnitKey = "" end
            f._msufTextRuntime.showName = mode ~= "configured-hidden" and mode ~= "configured-hidden-default" and mode ~= "preview-hidden"
            f._msufPreviewNameText = mode == "preview-hidden" and "Preview" or nil
        end)
    end
    local lateFrame, lateHandler
    for _, region in ipairs(w.h.widgets.frames) do
        local handler = region:GetScript("OnEvent")
        if region.events.EDIT_MODE_LAYOUTS_UPDATED and region.events.PLAYER_REGEN_DISABLED and handler
            and debug.getinfo(handler, "S").source:find("MSUF_UF_Factory.lua", 1, true) then
            assert(not lateHandler, "duplicate late-anchor event owner")
            lateFrame, lateHandler = region, handler
        end
    end
    assert(lateHandler, "missing late-anchor event owner")
    for _, kind in ipairs({ "absent", "table", "callable-table", "function" }) do
        local value = kind == "table" and {} or kind == "callable-table" and setmetatable({}, { __call = resolver })
            or kind == "function" and nativeResolver or nil
        Add("late-anchor:" .. kind, function() return lateHandler(lateFrame, "ADDON_LOADED", "ForeignAnchorProvider") end,
            function()
                e.MSUF_DB.general.anchorName = "EssentialCooldownViewer"
                e.MSUF_GetEffectiveCooldownFrame = value
                e.MSUF_GetUsableCooldownAnchorSize = nativeSize
                anchor.GetCenter = nativeCenter
            end)
    end
    local function NativeFunctions()
        local result = {}
        local builtins = { type = true, tonumber = true, tostring = true, pairs = true, ipairs = true, next = true,
            assert = true, error = true, pcall = true, xpcall = true, select = true, unpack = true, print = true,
            setmetatable = true, getmetatable = true, rawget = true, rawset = true, rawequal = true,
            loadstring = true, setfenv = true, getfenv = true, collectgarbage = true, newproxy = true }
        local function Register(owner, exclude)
            for key, fn in pairs(owner) do
                if type(fn) == "function" and not (exclude and exclude[key]) then
                    local source = debug.getinfo(fn, "S").source
                    if not source:find("/MidnightSimpleUnitFrames/", 1, true) then result[fn] = true end
                end
            end
        end
        Register(e, builtins)
        Register(w.h.widgets.Methods)
        Register(e.C_Timer)
        Register(e.C_Texture)
        Register(gf)
        Register(u.Elements.Power)
        Register(anchor)
        return result
    end
    return w, cases, function() return lookups + callbacks end, function() lookups, callbacks = 0, 0 end, NativeFunctions
end
return Paths

_G = _G or _ENV

table.wipe = table.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
_G.wipe = _G.wipe or table.wipe

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local root = "MidnightSimpleUnitFrames/"
if not exists(root .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua") then
    root = ""
end

local function loadAddon(path, MSUF)
    local chunk, err = loadfile(root .. path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local function fontString(shown)
    local fs = { shown = shown ~= false }
    function fs:IsShown() return self.shown == true end
    function fs:SetShown(value) self.shown = value == true end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    function fs:SetText(value) self.text = value end
    function fs:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
    function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    function fs:SetFont(...) self.font = { ... } end
    function fs:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
    function fs:SetPoint(...) self.points = { ... } end
    function fs:SetJustifyH(value) self.justifyH = value end
    function fs:SetWidth(value) self.width = value end
    return fs
end

local function region(parent)
    local r = { parent = parent, shown = false }
    function r:IsShown() return self.shown == true end
    function r:SetShown(value) self.shown = value == true end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:SetAlpha(value) self.alpha = value end
    function r:SetColorTexture(r1, g1, b1, a1) self.colorTexture = { r1, g1, b1, a1 } end
    function r:SetVertexColor(r1, g1, b1, a1) self.vertexColor = { r1, g1, b1, a1 } end
    function r:ClearAllPoints() self.points = {} end
    function r:SetPoint(...) self.points = { ... } end
    function r:SetAllPoints(target) self.allPoints = target or true end
    function r:SetHeight(value) self.height = value end
    function r:SetWidth(value) self.width = value end
    function r:SetSize(w, h) self.width, self.height = w, h or w end
    function r:SetFrameLevel(value) self.frameLevel = value end
    function r:GetFrameLevel() return self.frameLevel or 0 end
    function r:SetFrameStrata(value) self.frameStrata = value end
    function r:GetWidth() return self.width or 0 end
    function r:GetHeight() return self.height or 0 end
    function r:SetParent(value) self.parent = value end
    function r:SetDrawLayer(layer, sub) self.drawLayer, self.subLayer = layer, sub end
    function r:GetParent() return self.parent end
    function r:EnableMouse() end
    function r:SetClampedToScreen(value) self.clampedToScreen = value end
    function r:SetBackdrop(value) self.backdrop = value end
    function r:SetBackdropColor(...) self.backdropColor = { ... } end
    function r:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
    function r:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function r:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    function r:SetScript(scriptType, script) self.scripts = self.scripts or {}; self.scripts[scriptType] = script; if scriptType == "OnEvent" then self.script = script end end
    function r:CreateTexture()
        local tex = region(self)
        self.createdTextures = (self.createdTextures or 0) + 1
        return tex
    end
    function r:CreateFontString()
        return fontString(true)
    end
    return r
end

local function frame()
    local f = region(nil)
    function f:CreateTexture()
        local tex = region(self)
        self.createdTextures = (self.createdTextures or 0) + 1
        return tex
    end
    return f
end

local function smokeTextRuntime()
    local MSUF = {}
    MSUF.UF = { elements = {}, RegisterElement = function(name, element) MSUF.UF.elements[name] = element end }
    MSUF.Secrets = { IsSecret = function() return false end, IsNil = function(value) return value == nil end }
    MSUF.Apply = {}
    MSUF.UFText = {
        tonumber = tonumber,
        type = type,
        format = string.format,
        floor = math.floor,
        max = math.max,
        abs = math.abs,
        GetTime = function() return 1 end,
        UnitHealth = function() return 100 end,
        UnitHealthMax = function() return 100 end,
        UnitPower = function() return 50 end,
        UnitPowerMax = function() return 100 end,
        UnitPowerType = function() return 0 end,
        UnitHealthPercent = function() return 100 end,
        UnitPowerPercent = function() return 50 end,
        IsSecret = function() return false end,
        IsNil = function(value) return value == nil end,
    }
    _G.MSUF_NS = MSUF
    loadAddon("UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua", MSUF)
    loadAddon("UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua", MSUF)

    local Text = MSUF.UFText
    local rtFns = assert(Text.RuntimeHotFunctions, "text runtime hot functions missing")
    local f = {
        unit = "player",
        hpTextLeft = fontString(true),
        powerTextLeft = fontString(true),
    }
    local spec = {
        showHealthText = true,
        showPowerText = true,
        power = { enabled = true },
        text = {
            healthLeft = "CURRENT",
            powerLeft = "CURRENT",
            healthThrottle = 0.1,
            powerThrottle = 0.1,
        },
    }
    local rt = Text.CompileTextRuntime(f, spec, spec.text)
    assert(rt.healthHot == rtFns.healthHot, "health hot function was not compiled")
    assert(rt.healthDirty == rtFns.healthDirty, "health dirty function was not compiled")
    assert(rt.powerHot == rtFns.powerHot, "power hot function was not compiled")
    assert(rt.powerDirty == rtFns.powerDirty, "power dirty function was not compiled")
end

local function smokeGroupRuntime()
    local MSUF = {}
    MSUF.UF = { elements = {}, RegisterElement = function(name, element) MSUF.UF.elements[name] = element end }
    MSUF.GF = {}
    MSUF.Secrets = { IsSecret = function() return false end, IsNil = function(value) return value == nil end, UnitMissing = function() return false end }
    MSUF.UFStatusRuntime = {}
    for _, key in ipairs({
        "UpdateRaidMarker", "UpdateLeaderPair", "UpdateReadyCheck", "UpdateSummon",
        "UpdateIncomingRes", "UpdatePhase", "UpdateStatusText", "UpdateRaidGroup", "UpdateRole",
    }) do
        MSUF.UFStatusRuntime[key] = function() end
    end

    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.MSUF_DB = { general = {}, gf_party = {} }
    _G.GetTime = function() return 1 end
    _G.GetNumGroupMembers = function() return 5 end
    _G.GetRaidRosterInfo = function() return nil end
    _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
    _G.UnitGUID = function(unit) return unit end
    _G.UnitHealthPercent = function() return 100 end
    _G.UnitThreatSituation = function() return 1 end
    _G.CreateFrame = function(_, _, parent)
        local holder = frame()
        holder.parent = parent
        return holder
    end

    MSUF.GF.GetConf = function()
        return {
            healthFadeEnabled = true,
            targetIndicator = true,
            hlFocusEnabled = true,
            ciEnabled = true,
            ciSlotBR = "aggro",
            statusText = true,
            statusGhostText = true,
            statusAFKText = true,
        }
    end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Visuals.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Indicators.lua", MSUF)

    local f = frame()
    f.unit = "party1"
    f.hpBar = region(f)
    f.hpText = fontString(true)
    f.hpTextLeft = fontString(true)
    f.hpTextCenter = fontString(true)
    f.hpTextRight = fontString(true)
    f.bg = region(f)
    f.hpBarBG = region(f)
    f.MSUFSpec = MSUF.GF.CompileSpec("party", f, "party1")

    MSUF.UF.elements.GroupStatusRuntime.Apply(f)
    assert(type(f.MSUFSpec.status.runtimeDispatch) == "table", "status runtimeDispatch missing")

    MSUF.UF.elements.GroupVisuals.Apply(f)
    assert(type(f.MSUFSpec.group.runtimeOnHealth) == "function", "group runtimeOnHealth missing")
    assert(type(f.MSUFSpec.group.runtimeOnTarget) == "function", "group runtimeOnTarget missing")
    assert(type(f.MSUFSpec.group.runtimeOnFocus) == "function", "group runtimeOnFocus missing")
    assert(type(f.MSUFSpec.group.runtimeOnRangeAlpha) == "function", "group runtimeOnRangeAlpha missing")

    MSUF.UF.elements.GroupCornerIndicators.Apply(f)
    assert(type(f.MSUFSpec.cornerIndicators.runtimeThreat) == "function", "corner runtimeThreat missing")
end

local function smokeGroupHeaderLayoutCountFallback()
    local MSUF = {}
    MSUF.GF = {}
    MSUF.Secrets = { IsSecret = function() return false end, UnitMissing = function() return false end }

    local groupCount = 0
    local seenCounts = {}
    local unpackValues = table.unpack or unpack

    local function testFrame(name, parent)
        local f = frame()
        f.name = name
        f.parent = parent
        f.children = {}
        f.attributes = {}
        function f:SetParent(value) self.parent = value end
        function f:GetParent() return self.parent end
        function f:IsShown() return self.shown == true end
        function f:SetAttribute(key, value) self.attributes[key] = value end
        function f:GetAttribute(key) return self.attributes[key] end
        function f:GetChildren() return unpackValues(self.children) end
        if parent and parent.children then
            parent.children[#parent.children + 1] = f
        end
        return f
    end

    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.UIParent = testFrame("UIParent")
    _G.InCombatLockdown = function() return false end
    _G.GetNumGroupMembers = function() return groupCount end
    _G.GetNumSubgroupMembers = function() return 0 end
    _G.CreateFrame = function(_, name, parent)
        return testFrame(name, parent)
    end

    local conf = {
        growth = "DOWN",
        showPlayer = true,
        showSolo = false,
        unitsPerColumn = 5,
        maxColumns = 8,
        point = "CENTER",
        offsetX = 0,
        offsetY = 0,
    }
    MSUF.GF.EnsureDB = function() end
    MSUF.GF.GetConf = function() return conf end
    MSUF.GF.GetScaledFrameMetrics = function() return 80, 32, 1 end
    MSUF.GF.GetGridMetrics = function(_, count)
        seenCounts[#seenCounts + 1] = count
        return 0, 0, count, count
    end
    local scanCalls = {}
    MSUF.GF.ScheduleScan = function(key, kind)
        scanCalls[#scanCalls + 1] = { key = key, kind = kind }
    end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua", MSUF)

    groupCount = 0
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 10, "unknown raid count should use bounded fallback")
    assert(#scanCalls == 1, "new raid header should scan once")

    groupCount = 4
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 4, "positive raid count should pass through")
    assert(#scanCalls == 1, "unchanged raid header should not scan without roster force")

    groupCount = 0
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 4, "small last-known raid count should be reused")

    groupCount = 25
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 25, "large positive raid count should pass through")

    conf.preserveRaidGroups = true
    conf.maxColumns = 4
    groupCount = 23
    MSUF.GF.SetupHeader("raid", "raid")
    assert(MSUF.GF.headers.raid.attributes.maxColumns == 5, "raid header columns must expand to show all non-empty raid groups")
    conf.preserveRaidGroups = false
    conf.maxColumns = 8

    groupCount = 0
    MSUF.GF.SetupHeader("raid", "raid")
    assert(seenCounts[#seenCounts] == 10, "large stale raid count should clamp to bounded fallback")

    local scanCallsBeforeForce = #scanCalls
    MSUF.GF._forceScanHeaders = true
    MSUF.GF.SetupHeader("raid", "raid")
    assert(#scanCalls == scanCallsBeforeForce + 1, "roster-forced raid header should rescan unchanged children")
end

local function smokeGroupRuntimeRosterModes()
    local MSUF = {}
    MSUF.GF = { headers = {} }
    MSUF.Secrets = { IsSecret = function() return false end }

    local inGroup = true
    local inRaid = false
    local partyConf = { enabled = true, showSolo = true, showPlayer = true }
    local raidConf = { enabled = true }
    local setupCalls = {}
    local retireCalls = {}
    local actions = {}
    local forceScanSeen = false
    local eventFrame
    local combat = false

    local function eventHost()
        local f = frame()
        f.events = {}
        function f:SetScript(_, script) self.script = script end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        return f
    end

    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.InCombatLockdown = function() return combat end
    _G.IsInGroup = function() return inGroup end
    _G.IsInRaid = function() return inRaid end
    _G.CreateFrame = function()
        eventFrame = eventHost()
        return eventFrame
    end

    MSUF.GF.EnsureDB = function() end
    MSUF.GF.GetConf = function(kind)
        if kind == "party" then return partyConf end
        return raidConf
    end
    MSUF.GF.GetLiveRaidKind = function() return "raid" end
    MSUF.GF.InvalidateCompiledSpecs = function() end
    MSUF.GF.ApplyBlizzardGroupFrameOwnership = function() end
    MSUF.GF.SetupHeader = function(key, kind)
        setupCalls[#setupCalls + 1] = { key = key, kind = kind, forced = MSUF.GF._forceRecreateHeaders == true }
        actions[#actions + 1] = "setup:" .. key
        forceScanSeen = forceScanSeen or MSUF.GF._forceScanHeaders == true
        local header = { _msufGFKind = kind, shown = false }
        function header:Show() self.shown = true end
        function header:Hide() self.shown = false end
        MSUF.GF.headers[key] = header
        return header
    end
    MSUF.GF.RetireHeader = function(key)
        retireCalls[#retireCalls + 1] = key
        actions[#actions + 1] = "retire:" .. key
        MSUF.GF.headers[key] = nil
        return true
    end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua", MSUF)
    assert(eventFrame and eventFrame.script, "group runtime event frame missing")

    raidConf.offsetX, raidConf.offsetY = 10, 20
    combat = true
    assert(MSUF.GF.EM2_NudgePreview("gf_raid", 5, 5) == true, "combat group nudge should be consumed")
    assert(raidConf.offsetX == 10 and raidConf.offsetY == 20, "combat group nudge must not change offsets")
    combat = false

    eventFrame.script(eventFrame, "PLAYER_LOGIN")
    assert(setupCalls[#setupCalls].key == "party", "party should be active while grouped")
    assert(setupCalls[#setupCalls].forced == false, "initial grouped setup should not be forced")

    inGroup = false
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(setupCalls[#setupCalls].key == "party", "solo party should stay active when showSolo is enabled")
    assert(setupCalls[#setupCalls].forced == true, "party to solo must force a secure header relayout")

    partyConf.showSolo = false
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(retireCalls[#retireCalls] == "party", "solo party should retire when showSolo is disabled")

    partyConf.showSolo = true
    inGroup = true
    inRaid = true
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(setupCalls[#setupCalls].key == "raid", "raid should be active after party to raid")
    assert(setupCalls[#setupCalls].forced == true, "party to raid must force a secure header relayout")

    inRaid = false
    local actionStart = #actions
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(setupCalls[#setupCalls].key == "party", "party should be active after raid to party")
    assert(setupCalls[#setupCalls].forced == true, "raid to party must force a secure header relayout")
    assert(actions[actionStart + 1] == "retire:raid", "raid should retire before party setup")
    assert(actions[actionStart + 2] == "setup:party", "party should setup after raid retire")
    assert(forceScanSeen == true, "roster rebuilds should force secure-child scans")
    assert(MSUF.GF._forceScanHeaders == nil, "forced secure-child scan should clear after rebuild")

    combat = true
    local setupBeforeCombatRoster = #setupCalls
    eventFrame.script(eventFrame, "GROUP_ROSTER_UPDATE")
    assert(#setupCalls == setupBeforeCombatRoster, "combat roster should not rebuild immediately")
    assert(MSUF.GF._pendingGroupRuntime == "roster", "combat roster should defer group runtime")
    assert(MSUF.GF._forceScanHeaders == true, "combat roster should keep force scan pending")

    combat = false
    eventFrame.script(eventFrame, "PLAYER_REGEN_ENABLED")
    assert(#setupCalls > setupBeforeCombatRoster, "deferred combat roster should rebuild after combat")
    assert(MSUF.GF._forceScanHeaders == nil, "deferred combat roster scan should clear after rebuild")
end

local function smokeGroupEM2CombatFallback()
    local MSUF = {}
    MSUF.UF = { frames = {} }
    MSUF.GF = {
        _previewActive = {},
        _previewLayoutFrame = {},
        GetConf = function(kind)
            if kind == "party" then
                return {
                    enabled = true,
                    showSolo = true,
                    showPlayer = true,
                    offsetX = -400,
                    offsetY = 0,
                    width = 120,
                    height = 40,
                    anchorPoint = "CENTER",
                }
            end
            return { enabled = false }
        end,
        GetGridMetrics = function()
            return 0, 0, 120, 40
        end,
        GetPositionCount = function() return 1 end,
    }

    local nativeShow, nativeHide, nativeAnchor, nativeRefresh = 0, 0, 0, 0
    function MSUF.GF.SetPreviewAnchor() nativeAnchor = nativeAnchor + 1; return true end
    function MSUF.GF.ShowPreview() nativeShow = nativeShow + 1; return false end
    function MSUF.GF.HidePreview() nativeHide = nativeHide + 1; return true end
    function MSUF.GF.RefreshPreviewLayout() nativeRefresh = nativeRefresh + 1; return false end

    local registered = {}
    local initFrame
    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.MSUF_EM2 = {
        Registry = {
            Register = function(cfg) registered[cfg.key] = cfg end,
        },
        State = {
            IsActive = function() return true end,
            GetUnitKey = function() return "gf_party" end,
        },
        Movers = {
            Show = function() end,
            SyncAll = function() end,
        },
        Ticker = {
            IsDragging = function() return false end,
        },
    }
    _G.C_Timer = { After = function(_, fn) fn() end }
    _G.UIParent = frame()
    _G.UIParent:SetSize(1920, 1080)
    _G.InCombatLockdown = function() return true end
    _G.MSUF_IsConfigCombatLocked = function() return true end
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return true end
    _G.GetNumSubgroupMembers = function() return 0 end
    _G.GetNumGroupMembers = function() return 0 end
    _G.CreateFrame = function(_, _, parent)
        local f = frame()
        f:SetParent(parent)
        initFrame = initFrame or f
        return f
    end
    _G.hooksecurefunc = function() end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua", MSUF)
    assert(initFrame and initFrame.script, "group EM2 init frame missing")
    initFrame.script(initFrame, "PLAYER_LOGIN")

    local cfg = registered.gf_party
    assert(cfg and type(cfg.getFrame) == "function", "group EM2 party mover not registered")
    local fallback = cfg.getFrame()
    assert(fallback == nil or fallback:IsShown() == false, "combat edit mode must not move or show a group drag proxy")
    assert(nativeShow == 0, "combat edit mode must not create native group preview")
    assert(nativeHide > 0, "combat edit mode should hard-hide stale group previews")
    assert(nativeAnchor == 0, "combat edit mode must not retarget native preview anchors")
    assert(nativeRefresh == 0, "combat edit mode must not refresh native group preview")
end

local function smokeGroupEM2LiveRaidUsesRuntimeAnchor()
    local MSUF = {}
    MSUF.UF = { frames = {} }

    local liveAnchor = frame()
    liveAnchor:SetSize(320, 160)
    liveAnchor:Show()
    function liveAnchor:GetLeft() return 100 end
    function liveAnchor:GetRight() return 420 end
    function liveAnchor:GetTop() return 700 end
    function liveAnchor:GetBottom() return 540 end

    MSUF.GF = {
        anchors = { raid = liveAnchor },
        headers = {},
        _previewActive = {},
        _previewLayoutFrame = {},
        GetLiveRaidKind = function() return "raid" end,
        GetConf = function(kind)
            if kind == "raid" then
                return {
                    enabled = true,
                    offsetX = -500,
                    offsetY = 0,
                    width = 80,
                    height = 32,
                    anchorPoint = "CENTER",
                }
            end
            return { enabled = false }
        end,
        GetGridMetrics = function()
            return 0, 0, 320, 160
        end,
        GetPositionCount = function() return 23 end,
    }

    local nativeShow, nativeHide, nativeAnchor, visibility = 0, 0, 0, 0
    function MSUF.GF.SetPreviewAnchor() nativeAnchor = nativeAnchor + 1; return true end
    function MSUF.GF.ShowPreview() nativeShow = nativeShow + 1; return true end
    function MSUF.GF.HidePreview() nativeHide = nativeHide + 1; return true end
    function MSUF.GF.RefreshPreviewLayout() return true end
    function MSUF.GF.UpdateGroupVisibility() visibility = visibility + 1; return true end

    local registered = {}
    local initFrame
    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.MSUF_EM2 = {
        Registry = {
            Register = function(cfg) registered[cfg.key] = cfg end,
            Get = function(key) return registered[key] end,
        },
        State = {
            IsActive = function() return true end,
            GetUnitKey = function() return "gf_raid" end,
            SetUnitKey = function() end,
        },
        Movers = {
            Show = function() end,
            SyncAll = function() end,
            Get = function() return frame() end,
        },
        Ticker = {
            IsDragging = function() return false end,
            BeginDrag = function() end,
            EndDrag = function() return true end,
        },
    }
    _G.C_Timer = { After = function(_, fn) fn() end }
    _G.UIParent = frame()
    _G.UIParent:SetSize(1920, 1080)
    _G.InCombatLockdown = function() return false end
    _G.MSUF_IsConfigCombatLocked = function() return false end
    _G.IsInRaid = function() return true end
    _G.IsInGroup = function() return true end
    _G.GetNumSubgroupMembers = function() return 0 end
    _G.GetNumGroupMembers = function() return 23 end
    _G.CreateFrame = function(_, _, parent)
        local f = frame()
        f:SetParent(parent)
        initFrame = initFrame or f
        return f
    end
    _G.hooksecurefunc = function() end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua", MSUF)
    assert(initFrame and initFrame.script, "group EM2 init frame missing")
    initFrame.script(initFrame, "PLAYER_LOGIN")

    local cfg = registered.gf_raid
    assert(cfg and type(cfg.getFrame) == "function", "group EM2 raid mover not registered")
    local dragFrame = cfg.getFrame()
    assert(dragFrame ~= liveAnchor, "live raid edit mode should use a non-secure drag proxy")
    assert(dragFrame._msufGFLiveAnchor == liveAnchor, "live raid drag proxy should track the runtime anchor")
    assert(dragFrame.scripts and dragFrame.scripts.OnMouseUp, "live raid drag proxy should use frame-safe mouse-up clicks")
    assert(not dragFrame.scripts.OnClick, "live raid drag proxy must not install Button-only OnClick")
    assert(nativeShow == 0, "live raid edit mode should not build dummy raid preview")
    assert(nativeHide > 0, "live raid edit mode should clear dummy raid preview state")
    assert(nativeAnchor > 0, "live raid edit mode should clear native preview anchors")
    assert(visibility > 0, "live raid edit mode should keep live secure headers visible")
end

local function smokeCastbarPreviewHardHide()
    _G.MSUF_DB = {
        general = {
            castbarPlayerPreviewEnabled = true,
            playerCastbarTestMode = true,
            targetCastbarTestMode = true,
            focusCastbarTestMode = true,
            bossCastbarTestMode = true,
        },
    }
    _G.MSUF_NS = {}
    _G.MSUF_InCombat = false
    _G.InCombatLockdown = function() return false end
    _G.UnitAffectingCombat = function() return false end

    local function castbarPreview()
        local f = frame()
        f.MSUF_testMode = true
        f._msufTestActive = true
        f.MSUF_testStart = 1
        f.MSUF_testDur = 4
        f.statusBar = region(f)
        local tex = region(f.statusBar)
        function f.statusBar:GetStatusBarTexture() return tex end
        f.timeText = fontString(true)
        f.latencyBar = region(f)
        f:Show()
        return f
    end

    _G.MSUF_PlayerCastbarPreview = castbarPreview()
    _G.MSUF_TargetCastbarPreview = castbarPreview()
    _G.MSUF_FocusCastbarPreview = castbarPreview()
    _G.MSUF_BossCastbarPreview = castbarPreview()
    _G.MSUF_BossCastbarPreview2 = castbarPreview()

    loadAddon("Castbars/MSUF_CastbarPreviews.lua", _G.MSUF_NS)
    assert(type(_G.MSUF_HideAllCastbarPreviews) == "function", "castbar hard-hide helper missing")
    _G.MSUF_HideAllCastbarPreviews()

    local g = _G.MSUF_DB.general
    assert(g.castbarPlayerPreviewEnabled == false, "castbar preview flag should clear")
    assert(g.playerCastbarTestMode == false and g.bossCastbarTestMode == false, "castbar test flags should clear")
    assert(_G.MSUF_PlayerCastbarPreview:IsShown() == false, "player castbar preview should hide")
    assert(_G.MSUF_TargetCastbarPreview:IsShown() == false, "target castbar preview should hide")
    assert(_G.MSUF_FocusCastbarPreview:IsShown() == false, "focus castbar preview should hide")
    assert(_G.MSUF_BossCastbarPreview:IsShown() == false, "boss castbar preview should hide")
    assert(_G.MSUF_BossCastbarPreview2:IsShown() == false, "extra boss castbar preview should hide")
end

smokeTextRuntime()
smokeGroupRuntime()
smokeGroupHeaderLayoutCountFallback()
smokeGroupRuntimeRosterModes()
smokeGroupEM2LiveRaidUsesRuntimeAnchor()
smokeGroupEM2CombatFallback()
smokeCastbarPreviewHardHide()

print("perf runtime smoke ok")

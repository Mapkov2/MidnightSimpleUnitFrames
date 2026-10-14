-- Exercise real UF lifecycle and CP forwarding, with native script edges.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/classpower_world.lua")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
local function Start(flavor, enabled, lite)
    local affecting, reads, font = false, 0, "Fonts\\FRIZQT__.TTF"
    local t = World.Start(root, flavor == "Forever" and "Mainline" or flavor, "ROGUE", 1, World.PT.ENERGY, {
        showClassPower = false, playerHPBarEnabled = enabled,
        playerHPBarIndependentVisibility = true, playerHPBarUsePlayerText = false,
        playerHPBarWidthMode = "custom", playerHPBarWidth = 180,
    }, { beforeLoad = function(env, S)
        MSUF_NS.Client.IsForever = flavor == "Forever"
        Secrets.Install()
        UnitAffectingCombat = function() return affecting end
        InCombatLockdown = function() return env.inCombat end
        UnitHealth = function() reads = reads + 1
    return S.health end
        UnitHealthPercent = function() return S.percent or 50 end
        CurveConstants = { ScaleTo100 = {} }
        MSUF_GetFontPath = function() return font end
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"))(
            "MidnightSimpleUnitFrames", MSUF_NS)
    end })
    MSUF_DB.general.perfLiteClassPowerEvents = lite
    t.CP.RefreshPublic()
    t.Reads = function() return reads end
    t.Affecting = function(value) affecting = value end
    t.Font = function(value) font = value end
    return t
end
local checked = 0
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    for _, lite in ipairs({ true, false }) do
    local t = Start(flavor, true, lite)
    local UF = MSUF_NS.UF
    local element = assert(UF.elements and UF.elements.PlayerHP, "UF must own the PlayerHP element")
    local state = assert(element.State, "UF must own the PlayerHP state")
    local frame, player = assert(state.frame), MSUF_player
    assert(UF.attachedFrames[frame] and frame:IsElementEnabled("PlayerHP"), "UF must own the attached active host")
    assert(not t.eventFrame:IsEventRegistered("UNIT_HEALTH"), "CP must release PlayerHP health delivery")
    assert(frame:IsEventRegistered("UNIT_HEALTH"), "UF must bind health delivery")
    local route = frame.UNIT_HEALTH
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
        "PLAYER_DEAD", "PLAYER_ALIVE" }) do
        t.S.health, t.S.healthMax = 321 + checked, 1200
        local before = t.Reads()
        t.env:FireEvent(event, event:find("^UNIT_") and "player" or nil)
        assert(t.Reads() == before + 1, event .. " delivered duplicate/missing health updates")
        assert(state._hp == t.S.health and state._maxHP == 1200, "UF event did not paint health")
        checked = checked + 1
    end
    MSUF_DB.player = { enabled = false, powerBarDetached = true, showHP = true }
    player:Hide()
    player._msufCoreSpecEnabled, player._msufDetached = false, true
    UF.DetachFrame(player)
    t.CP.PlayerHPRefreshPublic()
    t.S.health = 287
    t.env:FireEvent("UNIT_HEALTH", "player")
    assert(state.visible and state._hp == 287 and frame:GetParent() == UIParent,
        "disabled/hidden/detached Player frame disabled Extra Health")
    assert(frame.UNIT_HEALTH == route, "reapply changed optimized route identity")
    player:SetScale(1.5)
    t.CP.PlayerHPRefreshPublic()
    assert(frame:GetScale() == 1.5 and state.borderHost:GetScale() == 1.5, "independent resource scale drift")
    t.Font("Fonts\\ARIALN.TTF")
    t.CP.ApplyFontsPublic()
    assert(state.right.fontPath == "Fonts\\ARIALN.TTF", "font change missed UF-owned text")
    MSUF_DB.bars = { showClassPower = false, playerHPBarEnabled = true,
        playerHPBarIndependentVisibility = true, playerHPBarUsePlayerText = false,
        playerHPBarWidthMode = "custom", playerHPBarWidth = 237, playerHPBarTextRight = "MAX" }
    t.CP.RefreshPublic()
    assert(frame:GetWidth() == 237 and state.right.text == "1.2K", "profile change lost geometry/text")
    MSUF_DB.bars.showClassPower = true
    t.CP.RefreshPublic()
    assert(state.visible and frame:IsElementEnabled("PlayerHP"), "ClassPower enablement stole Extra Health")
    if flavor == "Mainline" or flavor == "Forever" then
        local cdm = t.env:CreateFrame("Frame", "PlayerHealthSceneCDM", UIParent)
        cdm:SetSize(260, 10)
        EssentialCooldownViewer = cdm
        MSUF_GetEffectiveCooldownFrame = function() return cdm end
        MSUF_GetUsableCooldownAnchorSize = function() return 260, 10 end
        MSUF_IsCooldownAnchorSupported = function() return true end
        MSUF_CDM_GetScaledWidth = function() return 260 end
        MSUF_DB.bars.classPowerWidthMode, MSUF_DB.bars.classPowerAnchorToCooldown = "cooldown", true
        MSUF_DB.bars.playerHPBarWidthMode = "class"
        t.CP.RefreshPublic()
        local _, source = frame:GetPoint()
        local _, cdmSource = t.CP.container:GetPoint()
        assert(source == t.CP.container and cdmSource == cdm, "Extra Health lost ClassPower/CDM anchor ownership")
        MSUF_DB.bars.playerHPBarWidthMode = "custom"
        MSUF_GetEffectiveCooldownFrame, MSUF_IsCooldownAnchorSupported, MSUF_CDM_GetScaledWidth = nil, nil, nil
        EssentialCooldownViewer = nil
    end
    MSUF_DB.bars.showClassPower = false
    t.CP.RefreshPublic()
    assert(state.visible, "ClassPower disablement stole Extra Health")
    MSUF_DB.general.perfLiteClassPowerEvents = false
    MSUF_DB.bars.showClassPower = true
    t.CP.RefreshPublic()
    local beforeNonLite = t.Reads()
    t.env:FireEvent("UNIT_HEALTH", "player")
    assert(t.Reads() == beforeNonLite + 1, "non-lite ClassPower duplicated PlayerHP health delivery")
    MSUF_DB.general.perfLiteClassPowerEvents = true
    MSUF_DB.bars.showClassPower = false
    t.CP.RefreshPublic()
    local stop = Secrets.Watch({ root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_PlayerHP.lua",
        root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_PlayerHP.lua" }, { strict = true })
    t.S.health, t.S.healthMax, t.S.percent = Secrets.New("number"), Secrets.New("number"), Secrets.New("number")
    t.env:FireEvent("UNIT_MAXHEALTH", "player")
    assert(rawequal(state.bar.value, t.S.health) and rawequal(state.bar.maximum, t.S.healthMax), "secrets missed native sinks")
    assert(state._hp == nil and state._maxHP == nil, "secret health was cached")
    assert(#stop() == 0, "strict Watch found a secret operation")
    t.S.health, t.S.healthMax, t.S.percent = 250, 1000, 25
    t.Affecting(true) -- The combat event edge precedes lockdown.
    assert(not InCombatLockdown())
    MSUF_DB.bars.playerHPBarWidth = 300
    t.CP.PlayerHPRefreshPublic()
    assert(state.pending and frame:GetWidth() == 237, "combat edge allowed layout writes")
    t.env.inCombat = true
    MSUF_DB.bars.playerHPBarEnabled = false
    t.CP.PlayerHPRefreshPublic()
    assert(frame:IsElementEnabled("PlayerHP") and state.visible, "combat disable tore down the live resource")
    t.Affecting(false)
    t.env:LeaveCombat()
    assert(not state.pending and not state.visible and not frame:IsElementEnabled("PlayerHP"), "deferred disable was lost")
    assert(not frame:IsEventRegistered("UNIT_HEALTH"), "disabled resource retained health subscription")
    MSUF_DB.bars.playerHPBarEnabled = true
    t.CP.PlayerHPRefreshPublic()
    assert(state.frame == frame and frame:GetWidth() == 300, "deferred apply duplicated the resource")
    frame:DisableElement("PlayerHP")
    assert(not state.visible, "UF disable did not own teardown")
    frame:EnableElement("PlayerHP")
    assert(state.visible and frame:IsEventRegistered("UNIT_HEALTH"), "UF enable did not own activation")
    t.module.Disable()
    assert(not state.visible and not state.borderHost:IsShown(), "teardown left the outline")
    local cold = Start(flavor, false, lite)
    local coldState = assert(MSUF_NS.UF.PlayerHP.State)
    assert(coldState.frame == nil, "disabled option created a resource")
    cold.Affecting(true)
    MSUF_DB.bars.playerHPBarEnabled = true
    cold.CP.PlayerHPRefreshPublic()
    assert(coldState.pending and coldState.frame == nil, "combat edge created the health surface")
    cold.Affecting(false)
    cold.env:LeaveCombat()
    assert(coldState.frame and coldState.visible and not coldState.pending, "deferred creation was lost")
    cold.module.Disable()
    -- A registered settings caller observes the real event edge while both
    -- native combat APIs still answer false; it applies within that dispatch.
    local edge = Start(flavor, false, lite)
    local edgeState = MSUF_NS.UF.PlayerHP.State
    local caller = edge.env:CreateFrame("Frame", nil, UIParent)
    caller:RegisterEvent("PLAYER_REGEN_DISABLED")
    caller:SetScript("OnEvent", function(_, event)
        assert(not InCombatLockdown() and not UnitAffectingCombat("player"), "edge fixture already entered lockdown")
        assert(MSUF_NS.Util.InCombat(event), "event did not announce combat")
        MSUF_DB.bars.playerHPBarEnabled = true
        edge.CP.PlayerHPRefreshPublic()
    end)
    edge.env:FireEvent("PLAYER_REGEN_DISABLED")
    assert(edgeState.pending and edgeState.frame == nil, "event-derived combat allowed creation")
    edge.env:LeaveCombat()
    assert(edgeState.frame and edgeState.visible and not edgeState.pending, "event-derived deferred creation was lost")
    edge.module.Disable()
    end
end
print("player_health_element_lifecycle_smoke: OK (five clients, " .. checked .. " single-delivery event cases, lite/non-lite)")

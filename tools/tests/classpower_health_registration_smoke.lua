-- Health delivery belongs to each real consumer, in either binding policy.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/classpower_world.lua")
local clients = {
    Mainline = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
        "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" },
    Mists = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "DEATHKNIGHT", "MONK" },
}
local legacy = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
clients.Forever, clients.Vanilla, clients.TBC = legacy, legacy, legacy
local checked, consumers, modes = 0, {}, {}
local events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" }
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    for _, class in ipairs(clients[flavor]) do
        for spec = 1, 4 do
            local primary = class == "WARRIOR" and 1 or class == "DRUID" and (spec == 2 and 3 or spec == 3 and 1 or 0)
                or (class == "ROGUE" or class == "MONK") and 3 or class == "DEATHKNIGHT" and 6 or 0
            local health, maximum, stagger = 0, 0, 0
            local t = World.Start(root, flavor == "Forever" and "Mainline" or flavor, class, spec, primary, {
                playerHPBarEnabled = true, playerHPBarIndependentVisibility = true, playerHPBarUsePlayerText = false,
                playerHPBarWidthMode = "custom", playerHPBarWidth = 180, showEleMaelstrom = true, showShadowMana = true,
                showGuardianIronfur = true, showSweepingStrikes = true,
            }, { beforeLoad = function(_, S)
                MSUF_NS.Client.IsForever = flavor == "Forever"
                UnitHealth = function() health = health + 1 return S.health end
                UnitHealthMax = function() maximum = maximum + 1 return S.healthMax end
                UnitStagger = function() stagger = stagger + 1 return S.stagger end
                UnitHealthPercent = function() return 50 end
                CurveConstants = { ScaleTo100 = {} }
            end })
            local UF, CP = MSUF_NS.UF, t.CP
            local state = assert(UF.PlayerHP.State)
            local callback, host = t.eventFrame:GetScript("OnEvent"), state.frame
            for mode, descriptor in pairs(MSUF_CP_CONST.ModeDescriptors) do
                assert(descriptor.health == (mode == MSUF_CP_CONST.CPK.MODE.STAGGER), "unreviewed health-dependent mode")
            end
            for _, lite in ipairs({ true, false }) do
                for _, php in ipairs({ true, false }) do
                    for _, cp in ipairs({ true, false }) do
                        MSUF_DB.general.perfLiteClassPowerEvents = lite
                        MSUF_DB.bars.playerHPBarEnabled, MSUF_DB.bars.showClassPower = php, cp
                        CP.RefreshPublic()
                        local wanted = CP.visible == true and CP.modeProfile.health == true
                        assert(not wanted or CP.renderMode == MSUF_CP_CONST.CPK.MODE.STAGGER, "consumer routing drift")
                        consumers[flavor .. "/" .. class .. "/" .. spec] = wanted or consumers[flavor .. "/" .. class .. "/" .. spec]
                        modes[flavor .. "/" .. tostring(CP.renderMode)] = true
                        for _, event in ipairs(events) do
                            assert(t.eventFrame:IsEventRegistered(event) == wanted,
                                flavor .. "/" .. class .. "/" .. spec .. "/" .. event .. " CP registration disagrees with its consumer")
                            assert(host:IsEventRegistered(event) == php, "UF registration disagrees with Extra Health option")
                            health, maximum, stagger = 0, 0, 0
                            t.S.health, t.S.healthMax = 400 + checked % 97, 1000 + checked % 71
                            t.env:FireEvent(event, "player")
                            local count = (php and 1 or 0) + (wanted and 1 or 0)
                            assert(health == (php and 1 or 0) and maximum == count and stagger == (wanted and 1 or 0),
                                "duplicate/missing health consumer delivery")
                            if php then assert(state._hp == t.S.health and state._maxHP == t.S.healthMax, "PHP did not paint") end
                            if wanted then assert(CP.bars[1].maximum == t.S.healthMax, "Stagger maximum did not repaint") end
                            checked = checked + 1
                        end
                        assert(t.eventFrame:GetScript("OnEvent") == callback, "controller closure identity changed")
                    end
                end
            end
            -- Spec transitions use the real structural event, not a fabricated mode profile.
            MSUF_DB.bars.showClassPower = true
            MSUF_DB.bars.playerHPBarEnabled = true
            t.S.spec = spec == 1 and 2 or 1
            t.env:FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
            t.env:RunTimers()
            local wanted = CP.visible == true and CP.modeProfile.health == true
            assert(t.eventFrame:IsEventRegistered("UNIT_HEALTH") == wanted, "structural transition left stale health bindings")
            local player = MSUF_player
            player:Hide()
            player._msufCoreSpecEnabled, player._msufDetached = false, true
            MSUF_DB.player = { enabled = false, powerBarDetached = true }
            UF.DetachFrame(player)
            CP.PlayerHPRefreshPublic()
            assert(state.visible and host:GetParent() == UIParent, "Player frame gating stole Extra Health")
            host:Hide()
            for _, event in ipairs(events) do
                assert(not host:IsEventRegistered(event), "hidden PHP retained a value subscription")
                assert(t.eventFrame:IsEventRegistered(event) == wanted, "hidden PHP stole CP health delivery")
                health, maximum, stagger = 0, 0, 0
                t.S.health, t.S.healthMax = 250, 1250
                t.env:FireEvent(event, "player")
                assert(health == 0 and maximum == (wanted and 1 or 0) and stagger == (wanted and 1 or 0),
                    "hidden PHP still painted or CP delivery was lost")
            end
            host:Show()
            assert(state._hp == 250 and state._maxHP == 1250, "PHP reshow missed the hidden health changes")
            for _, event in ipairs(events) do assert(host:IsEventRegistered(event), "reshow did not restore PHP delivery") end
            t.module.Disable()
        end
    end
end
assert(consumers["Mainline/MONK/1"] and not consumers["Mists/MONK/1"], "Mainline Stagger and Mists Chi routing drift")
local count = 0
for _ in pairs(modes) do count = count + 1 end
print("classpower_health_registration_smoke: OK (" .. checked .. " deliveries, " .. count .. " client/mode routes)")

-- Fixed raid slots must retain role-dependent Power ownership without GUIDs.
local root = assert(arg[1], "root required"):gsub("\\", "/"):gsub("/$", "")
local flavor, mode = arg[2] or "Mainline", "candidate"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
local failures, rosterGUIDReads = 0, 0
for _, icon in ipairs({true, false}) do
    for _, hiddenGUID in ipairs({false, true}) do
        local roles = { raid3 = "HEALER", raid4 = "DAMAGER" }
        local guids = { raid3 = "Player-Healer", raid4 = "Player-DPS" }
        local secret = false
        local secretGUID = Secrets.New("string")
        local h = Harness.New(root, flavor, { beforeBoot = function(w)
            w.env.issecretvalue = Secrets.IsSecret
            w.env.UnitGroupRolesAssigned = function(unit) return roles[unit] or "DAMAGER" end
            local original = w.env.UnitGUID
            w.env.UnitGUID = function(unit)
                if debug.getinfo(2, "S").source:find("MSUF_UF_Group_Runtime.lua", 1, true) then
                    rosterGUIDReads = rosterGUIDReads + 1
                end
                if secret and (unit == "raid3" or unit == "raid4") then return secretGUID end
                return guids[unit] or original(unit)
            end
        end })
        local GF, UF = h.GF, h.UF
        GF.EnsureDB()
        local conf = GF.GetConf("raid")
        conf.enabled, conf.showPowerText, conf.roleIcon = true, true, icon
        conf.powerShowHealer, conf.powerShowDamager = true, false
        conf.height, conf.powerHeight, conf.nameBarEnabled, conf.nameBarHeight = 20, 8, true, 18
        GF.InvalidateCompiledSpecs("raid")
        GF.RefreshHeaderLayout()
        h:SetRaid(10)
        h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers()
        local healer, dps = assert(GF.FrameForUnit("raid3")), assert(GF.FrameForUnit("raid4"))
        assert(healer.MSUFSpec.power.enabled == true and dps.MSUFSpec.power.enabled == false)
        local stripHeight = GF.CompileSpec("raid").group.nameBarHeight
        local width, height = healer:GetWidth(), healer:GetHeight()
        local counts = { overlay = 0, apply = 0, lifecycle = 0, staleEntry = 0, compile = 0 }
        local originalOverlay, originalApply = GF.RefreshFrameRoleOverlay, UF.ApplyElementsToFrame
        local originalRefresh, originalCompile = UF.RefreshGroupFrameState, GF.CompileSpec
        local measuring = false
        GF.RefreshFrameRoleOverlay = function(...)
            if measuring then counts.overlay = counts.overlay + 1 end
            return originalOverlay(...)
        end
        UF.ApplyElementsToFrame = function(...)
            if measuring then counts.apply = counts.apply + 1 end
            return originalApply(...)
        end
        GF.CompileSpec = function(...)
            if measuring then counts.compile = counts.compile + 1 end
            return originalCompile(...)
        end
        UF.RefreshGroupFrameState = function(frame, ...)
            if measuring then
                counts.lifecycle = counts.lifecycle + 1
                if frame == healer or frame == dps then
                    local expected = roles[frame.MSUFUnitKey] == "HEALER"
                    if frame.MSUFSpec.power.enabled ~= expected then counts.staleEntry = counts.staleEntry + 1 end
                end
            end
            return originalRefresh(frame, ...)
        end
        h:EnterCombat()
        secret = hiddenGUID
        guids.raid3, guids.raid4 = guids.raid4, guids.raid3
        roles.raid3, roles.raid4 = roles.raid4, roles.raid3
        measuring = true
        h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers()
        measuring = false
        local valid = healer.MSUFSpec.power.enabled == false and dps.MSUFSpec.power.enabled == true
            and healer.MSUFSpec.showPowerText == false and dps.MSUFSpec.showPowerText == true
            and healer._msufActiveElements.Power ~= true and dps._msufActiveElements.Power == true
            and healer._msufActiveElements.PowerText ~= true and dps._msufActiveElements.PowerText == true
            and healer.hpBar._msufHealthPowerInset == 0 and dps.hpBar._msufHealthPowerInset == 8
            and healer.MSUFGFNameBar:GetHeight() == math.min(stripHeight, healer.MSUFSpec.height - 1)
            and dps.MSUFGFNameBar:GetHeight() == math.min(stripHeight, dps.MSUFSpec.height - 8 - 1)
        if not valid then
            failures = failures + 1
            for _, frame in ipairs({healer, dps}) do
                print(string.format("state %s power=%s text=%s activePower=%s activeText=%s inset=%s strip=%s specHeight=%s powerHeight=%s",
                    frame.MSUFUnitKey, tostring(frame.MSUFSpec.power.enabled), tostring(frame.MSUFSpec.showPowerText),
                    tostring(frame._msufActiveElements.Power), tostring(frame._msufActiveElements.PowerText),
                    tostring(frame.hpBar._msufHealthPowerInset), tostring(frame.MSUFGFNameBar:GetHeight()),
                    tostring(frame.MSUFSpec.height), tostring(frame.MSUFSpec.power.height)))
            end
        end
        assert(#h.violations == 0, tostring(h.violations[1]))
        assert(healer:GetWidth() == width and healer:GetHeight() == height, "secure owner size changed")
        assert(counts.staleEntry == 0, "role overlay must precede the lifecycle paint")
        assert(counts.apply == 2 and counts.lifecycle == 10, "role change duplicated or lost work")
        local firstApply, firstLifecycle = counts.apply, counts.lifecycle
        measuring = true
        h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers()
        measuring = false
        assert(counts.apply == firstApply, "unchanged repeated roster re-applied elements")
        assert(#h.violations == 0, tostring(h.violations[1]))
        print(string.format("%s %s icon=%s secretGUID=%s %s: applies=%d lifecycle=%d stale-entry=%d overlay-total=%d compile-total=%d repeated-applies=%d",
            flavor, mode, tostring(icon), tostring(hiddenGUID), valid and "PASS" or "FAIL",
            firstApply, firstLifecycle, counts.staleEntry, counts.overlay, counts.compile, counts.apply-firstApply))
        h:LeaveCombat(); h:RunTimers()
        assert(not GF._pendingGroupRuntime, "regen did not catch up")
        roles.raid3, roles.raid4 = roles.raid4, roles.raid3
        h:Event("GROUP_ROSTER_UPDATE"); h:RunTimers()
        assert(healer.MSUFSpec.power.enabled and not dps.MSUFSpec.power.enabled,
            "out-of-combat setup lost same-token role ownership")
        assert(healer._msufActiveElements.Power and not dps._msufActiveElements.Power,
            "out-of-combat setup failed to apply role ownership")
        assert(#h.violations == 0, tostring(h.violations[1]))
        assert(#h.callMethodErrors == 0, tostring(h.callMethodErrors[1]))
        for _, err in ipairs(h.eventErrors) do
            assert(not err:find("Engine/Elements/", 1, true), err)
        end
    end
end
assert(failures == 0, tostring(failures) .. " stale role overlay cases")
assert(rosterGUIDReads == 0, "roster runtime still reads GUIDs")
print("group_role_overlay_secret_roster_smoke: PASS (" .. flavor .. ")")

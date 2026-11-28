-- The first unit-page refresh must measure the enabled runtime castbar scene.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mainline = flavor == "Mainline" or flavor == "Forever"
local mw = MW.Open(root, flavor, { open = false, tocMetadata = mainline, beforeCore = function(world)
    -- The permissive widget world synthesizes unknown globals. The real client
    -- has no global for this private helper, so a lost lexical binding is nil.
    local meta = getmetatable(world.env)
    local fallback = meta.__index
    world.env.CastbarShowTargetName = nil
    meta.__index = function(env, name)
        if name == "CastbarShowTargetName" then return nil end
        return fallback(env, name)
    end
    if mainline then MW.InstallNativeUnitInputs(world) end
    world.env.GetPhysicalScreenSize = function() return 2560, 1440 end
    world.env.GetScreenHeight = function() return 768 / world.env.UIParent:GetEffectiveScale() end
    world.widgets.Methods.GetEffectiveScale = function(frame)
        local scale = 1
        while type(frame) == "table" and rawget(frame, "__env") ~= nil do
            scale = scale * (rawget(frame, "scale") or 1)
            frame = rawget(frame, "parent")
        end
        return scale
    end
end })
local core, menu = mw.core, mw.M
local general = menu.EnsureDB().general
if flavor == "Mainline" or flavor == "Forever" then
    local env = mw.world.env
    local previousProvider, previousViewer, previousContainer = env.MSUF_GetSuiteCooldownAnchor,
        env.UtilityCooldownViewer, env.UtilityCooldownViewer_AnchorContainer
    local suite, native, legacy = env.CreateFrame("Frame"), env.CreateFrame("Frame"), env.CreateFrame("Frame")
    suite:SetSize(144, 28)
    native:SetSize(222, 28)
    legacy:SetSize(333, 28)
    env.UtilityCooldownViewer, env.UtilityCooldownViewer_AnchorContainer = native, legacy
    env.MSUF_GetSuiteCooldownAnchor = function(name)
        if name == "UtilityCooldownViewer" then return suite end
    end
    core.Castbars.Backend.Set("player", "MSUF", general)
    local oldMatch, oldWidth = general.castbarPlayerMatchWidth, general.castbarPlayerBarWidth
    local oldAnchor, oldDetached = general.castbarPlayerAnchorToUtility, general.castbarPlayerDetached
    local oldX, oldY = general.castbarPlayerOffsetX, general.castbarPlayerOffsetY
    general.castbarPlayerMatchWidth, general.castbarPlayerBarWidth = "utility", 144
    general.castbarPlayerAnchorToUtility, general.castbarPlayerDetached = true, true
    general.castbarPlayerOffsetX, general.castbarPlayerOffsetY = 0, 0
    local function CheckWidth(expected)
        local width = core.Castbars.Anchors.GetCastbarDesiredSize("player", general)
        local previewWidth = core.UFPreviewCastbar.ReadSize("player", general)
        assert(width == expected and previewWidth == expected,
            ("Utility width mismatch: live %s, preview %s, expected %s"):format(width, previewWidth, expected))
    end
    CheckWidth(144)
    local bar = env.CreateFrame("Frame")
    local function CheckAnchor(expectedPoint, expectedTarget, expectedTargetPoint)
        assert(core.Castbars.Anchors.ApplyPlayerCastbarPosition(bar, general))
        local point, anchor, relativePoint, x, y = bar:GetPoint(1)
        assert(point == expectedPoint and anchor == expectedTarget and relativePoint == expectedTargetPoint and x == 0 and y == 0,
            "Player Cast Bar lost its Utility anchor or fallback")
    end
    CheckAnchor("TOP", suite, "BOTTOM")
    suite:ClearAllPoints()
    suite:SetPoint("CENTER", env.UIParent, "CENTER", 45, -55)
    CheckAnchor("TOP", suite, "BOTTOM")
    suite:SetWidth(86)
    CheckWidth(86)
    suite:SetWidth(32)
    CheckWidth(32)
    suite:Hide()
    CheckWidth(333)
    CheckAnchor("TOP", legacy, "BOTTOM")
    legacy:Hide()
    CheckWidth(222)
    CheckAnchor("TOP", native, "BOTTOM")
    native:Hide()
    CheckWidth(144)
    CheckAnchor("CENTER", env.UIParent, "CENTER")
    suite:Show()
    CheckAnchor("TOP", suite, "BOTTOM")
    general.castbarPlayerMatchWidth, general.castbarPlayerBarWidth = oldMatch, oldWidth
    general.castbarPlayerAnchorToUtility, general.castbarPlayerDetached = oldAnchor, oldDetached
    general.castbarPlayerOffsetX, general.castbarPlayerOffsetY = oldX, oldY
    env.MSUF_GetSuiteCooldownAnchor, env.UtilityCooldownViewer, env.UtilityCooldownViewer_AnchorContainer =
        previousProvider, previousViewer, previousContainer
end
local cases = {
    { "player", "player", "castbarPlayer" },
    { "target", "target", "castbarTarget", "castbarTargetShowTargetName" },
    { "focus", "focus", "castbarFocus", "castbarFocusShowTargetName" },
    { "boss", "boss1", "bossCastbar", "showBossCastTargetName" },
    { "arena", "arena1", "arenaCastbar", "showArenaCastTargetName" },
}
local checked = 0
for _, entry in ipairs(cases) do
    local key, unit, prefix, targetKey = unpack(entry)
    if core.Client.SupportsUnit(unit) then
        core.Castbars.Backend.Set(key, "MSUF", general)
        general[prefix .. "Detached"] = true
        general[prefix .. "OffsetX"], general[prefix .. "OffsetY"] = 244.5, -86
        if targetKey then general[targetKey] = false end
        assert(menu.Open("uf_" .. key) ~= false, "unit page did not open: " .. key)
        mw:RunTimers()
        local preview, box = core.UFPreview, assert(core.UFPreview.active)
        local state = assert(box._msufPreviewScene)
        assert(state.complete and state.castPreviewVisible, "enabled castbar was not measured: " .. key)
        assert(box._castScene and box._castScene:Frame():IsShown(), "runtime castbar scene missing: " .. key)
        if targetKey then
            local before = state.maxX - state.minX
            general[targetKey] = true
            local detailPrefix = key == "boss" and "bossCast" or key == "arena" and "arenaCast" or prefix
            general[detailPrefix .. "TargetNameOffsetX"] = 450
            general[detailPrefix .. "TargetNameOffsetY"] = 400
            preview.Refresh(box, "castbar-target-footprint")
            assert(state.complete and state.maxX - state.minX > before,
                "target-name setting did not expand the castbar footprint: " .. key)
        end
        box._animationEnabled, box._animationElapsed = true, .5
        preview.Refresh(box, "castbar-animation")
        assert(preview.RefreshAnimation(box), "castbar animation did not refresh: " .. key)
        checked = checked + 1
        menu.HideSlashMenuAndMinibar(mw.win)
    end
end
if core.Client.IsRetail then
    local db = menu.EnsureDB()
    local C = core.Castbars
    db.bars.roundedFramesEnabled, general.roundedFramesEnabled = false, false
    assert(core.UF.Factory.SpawnAll(), "unit-frame factory did not spawn")
    local function CheckSpan(bar, owner, outset, offsetX, offsetY, context)
        local lp, lo, lr, lx, ly = bar:GetPoint(1)
        local rp, ro, rr, rx, ry = bar:GetPoint(2)
        local anchor = outset > 0 and owner.MSUFBorderOverlay or owner
        assert(lp == "BOTTOMLEFT" and rp == "BOTTOMRIGHT" and lo == anchor and ro == anchor
            and lr == "TOPLEFT" and rr == "TOPRIGHT", context .. " does not follow both unit-frame corners")
        local scale = owner:GetEffectiveScale() / bar:GetEffectiveScale()
        local step = 768 / 1440 / owner:GetEffectiveScale()
        local zoom = owner._msufBorderPreviewZoom or 1
        if outset > 0 then
            local livePixels = math.max(1, math.floor(outset / (step * zoom) + .5))
            outset = math.max(1, math.floor(livePixels * zoom + .5)) * step
        end
        assert(math.abs(lx - offsetX + outset * scale) < 0.001
            and math.abs(rx - offsetX - outset * scale) < 0.001,
            context .. " does not match the painted outline")
        assert(math.abs(ly - offsetY) < 0.001 and ly == ry, context .. " moved off the saved offset")
    end
    for _, key in ipairs({ "player", "target", "focus" }) do
        local prefix = "castbar" .. key:gsub("^%l", string.upper)
        C.Backend.Set(key, "MSUF", general)
        db.bars.showBarBorder, db.bars.barOutlineThickness, db.bars.barOutlineTexture = true, 2, ""
        general[prefix .. "Detached"] = false
        general[prefix .. "MatchWidth"] = "unitframe"
        general[prefix .. "OffsetX"], general[prefix .. "OffsetY"] = 0.25, -27.25
        general[prefix .. "BarHeight"] = 17
        C.Config.Invalidate()
        core.UF.Config.Refresh()
        assert(core.UF.Apply(key), key .. " live layout did not apply")
        local liveOwner = assert(core.UF.GetFrame(key), key .. " live unit frame not built")
        -- The widget fixture synthesizes missing members. These are optional
        -- runtime fields and no legacy outline frame is present in this case.
        liveOwner._msufBarOutline = false
        local liveBar = key == "player" and C.Manager.InitSafePlayerCastbar() or C.Driver.CastbarDriver_ApplyBackendState(key)
        liveBar = assert(C.Frames[key] or liveBar, key .. " live castbar not built")
        local reanchor = C.Anchors["Reanchor" .. key:gsub("^%l", string.upper) .. "CastBarBase"]
        reanchor()
        CheckSpan(liveBar, liveOwner, 2, 0, -27, key .. " live")
        assert(menu.Open("uf_" .. key) ~= false, "unit width preview did not open: " .. key)
        mw:RunTimers()
        local preview, box = core.UFPreview, assert(core.UFPreview.active)
        local state = assert(box._msufPreviewScene)
        local slot = box.mock.cast
        local owner = box.mock._body
        local edge = assert(owner.MSUFBorderEdges.top, "normal border was not built")
        assert(edge:IsShown(), "normal border is hidden")
        for _, zoom in ipairs({ 0.85, 1.15 }) do
            box._manualZoom = zoom
            preview.Refresh(box, "test-castbar-unit-width")
            local left, leftOwner, _, leftX = edge:GetPoint(1)
            assert(left == "TOPLEFT" and leftOwner == owner.MSUFBorderOverlay and leftX == -owner.MSUFBorderOverlay._msufBorderBands[2], "unit outline geometry changed")
            CheckSpan(slot, owner, 2, 0, -27 * state.scale, key .. " preview at zoom " .. zoom)
            assert(box._castScene.opts.matchParent, key .. " visible castbar did not follow its slot")
        end
        if key == "target" then
            C.Previews.PositionTargetCastbarPreview()
            local editPreview = assert(C.Frames.targetPreview, "Edit Mode castbar preview not built")
            db.bars.barOutlineThickness = 5
            assert(core.UF.RefreshBorders(key), "live outline did not refresh")
            mw:RunTimers()
            preview.Refresh(box, "test-castbar-thicker-outline")
            CheckSpan(liveBar, liveOwner, 5, 0, -27, "thicker live outline")
            CheckSpan(editPreview, liveOwner, 5, 0, -27, "thicker Edit Mode outline")
            CheckSpan(slot, owner, 5, 0, -27 * state.scale, "thicker preview outline")
            local setDispel = core.PublicGlobals.MSUF_SetDispelBorderTestMode
            setDispel(true, "shared")
            mw:RunTimers()
            assert(liveOwner._msufBorderVisualSource == "dispel", "highlight border did not repaint")
            CheckSpan(liveBar, liveOwner, 5, 0, -27, "live dispel highlight")
            setDispel(false, "shared")
            mw:RunTimers()
            local previousCastOutline = general.castbarOutlineThickness
            general.castbarOutlineThickness = 4
            C.Config.Invalidate()
            C.Style.ApplyCastbarOutline(liveBar)
            preview.Refresh(box, "test-castbar-own-outline")
            assert(liveBar._msufOutlineT == 4 and box._castScene:Frame()._msufOutlineT == 4,
                "configured castbar outline did not apply in both views")
            CheckSpan(liveBar, liveOwner, 5, 0, -27, "live castbar outline")
            CheckSpan(slot, owner, 5, 0, -27 * state.scale, "preview castbar outline")
            general.castbarOutlineThickness = previousCastOutline
            C.Config.Invalidate()
            db.bars.barOutlineTexture = "BORDER:GLOW"
            assert(core.UF.RefreshBorders(key), "textured outline did not refresh")
            mw:RunTimers()
            preview.Refresh(box, "test-castbar-textured-outline")
            assert(liveOwner.MSUFBorderTexturePieces and owner.MSUFBorderTexturePieces, "textured outline was not painted")
            local _, _, _, textureX = owner.MSUFBorderTexturePieces[1]:GetPoint(1)
            assert(textureX == -owner.MSUFBorderOverlay._msufBorderBands[7.5], "unexpected textured outline outset")
            CheckSpan(liveBar, liveOwner, 7.5, 0, -27, "textured live outline")
            CheckSpan(slot, owner, 7.5, 0, -27 * state.scale, "textured preview outline")
            local previousShape = db.target.frameBarShape
            db.target.frameBarShape, db.bars.roundedFramesEnabled = "ROUNDED", true
            core.PublicGlobals.MSUF_ApplyRoundedUnitframes()
            mw:RunTimers()
            assert(liveOwner._msufRUFModernBorderSuppressed == true and not liveBar:GetPoint(2),
                "rounded outline kept the square width anchors")
            db.target.frameBarShape, db.bars.roundedFramesEnabled = previousShape, false
            core.PublicGlobals.MSUF_ApplyRoundedUnitframes()
            mw:RunTimers()
            CheckSpan(liveBar, liveOwner, 7.5, 0, -27, "restored textured outline")
            mw.world.widgets:SetCombat(true)
            local setPoint = liveBar.SetPoint
            liveBar.SetPoint = function() error("castbar layout write during combat") end
            assert(not C.Anchors.ApplyCastbarEffectiveSizeUnit(key, general), "combat width sync was not deferred")
            db.bars.barOutlineThickness = 0
            assert(core.UF.RefreshBorders(key) == false, "combat outline geometry did not defer")
            general[prefix .. "OffsetY"] = -31.25
            C.Config.Invalidate()
            reanchor()
            CheckSpan(liveBar, liveOwner, 7.5, 0, -27, "combat")
            liveBar.SetPoint = setPoint
            mw.world.widgets:SetCombat(false)
            mw.world:FireEvent("PLAYER_REGEN_ENABLED")
            mw:RunTimers()
            preview.Refresh(box, "test-castbar-borderless")
            CheckSpan(liveBar, liveOwner, 0, 0, -31, "deferred offset")
            CheckSpan(slot, owner, 0, 0, -31 * state.scale, "deferred preview offset")
            general[prefix .. "OffsetY"] = -27.25
            C.Config.Invalidate()
            reanchor()
            preview.Refresh(box, "test-castbar-restored-offset")
            CheckSpan(liveBar, liveOwner, 0, 0, -27, "borderless live")
            CheckSpan(slot, owner, 0, 0, -27 * state.scale, "borderless preview")

            mw.world.widgets:SetCombat(true)
            liveBar.SetPoint = function() error("castbar width mode wrote anchors during combat") end
            general[prefix .. "MatchWidth"], general[prefix .. "BarWidth"] = "manual", 140
            C.Config.Invalidate()
            reanchor()
            C.Anchors.UpdateCastbarWidthSourceSync(general)
            CheckSpan(liveBar, liveOwner, 0, 0, -27, "combat width mode")
            liveBar.SetPoint = setPoint
            mw.world.widgets:SetCombat(false)
            mw.world:FireEvent("PLAYER_REGEN_ENABLED")
            mw:RunTimers()
            assert(not liveBar:GetPoint(2) and math.abs(liveBar:GetWidth() - 140) <= 1,
                "deferred manual width left both anchors in place")
            general[prefix .. "MatchWidth"] = "unitframe"
            C.Config.Invalidate()
            reanchor()
        end
        assert(general[prefix .. "MatchWidth"] == "unitframe" and general[prefix .. "BarHeight"] == 17
            and general[prefix .. "OffsetX"] == 0.25 and general[prefix .. "OffsetY"] == -27.25,
            key .. " preview changed stored geometry")
        general[prefix .. "Detached"] = true
        C.Config.Invalidate()
        reanchor()
        preview.Refresh(box, "test-detached-castbar-width")
        assert(slot:GetPoint(1) == "CENTER" and not slot:GetPoint(2), key .. " detached preview has stale width anchors")
        assert(liveBar:GetPoint(1) == "CENTER" and not liveBar:GetPoint(2), key .. " detached bar has stale width anchors")
        general[prefix .. "Detached"], general[prefix .. "MatchWidth"] = false, "manual"
        general[prefix .. "BarWidth"] = 140
        C.Config.Invalidate()
        reanchor()
        preview.Refresh(box, "test-manual-castbar-width")
        assert(not slot:GetPoint(2) and not liveBar:GetPoint(2), key .. " manual bar still follows its unit frame")
        menu.HideSlashMenuAndMinibar(mw.win)
    end
end
if mainline then
    local cb, uf = core.Castbars, core.UF
    local db = menu.EnsureDB()
    for _, key in ipairs({ "boss", "arena" }) do
        local unit, prefix = key .. "1", key .. "Castbar"
        if core.Client.SupportsUnit(unit) then
            general[prefix .. "Detached"], general[prefix .. "MatchWidth"] = false, "unitframe"
            general[prefix .. "OffsetX"], general[prefix .. "OffsetY"] = 2, -6
            general[prefix .. "Width"] = 126
            cb.Backend.Set(key, "MSUF", general)
            cb.Config.Invalidate()
            local pool = assert(cb.Pools.kinds[key])
            local bars = assert(pool.Ensure())
            local bar, owner = assert(bars[1]), assert(uf.frames[unit])
            local bounds = assert(uf.GetNormalOutlineBounds(owner))
            -- Give the HP and embedded resource different bottoms and the owner a
            -- fractional left. These make a duplicated HP delta or HP-bottom
            -- attachment distinguishable from the painted outline.
            owner.GetRect = function() return 100.25, 50.25, 126, 30 end
            owner.GetScaledRect = function() return 100.25, 50.25, 126, 30 end
            owner.hpBar.GetRect = function() return 100.6, 56, 125.8, 24 end
            owner.hpBar.GetScaledRect = function() return 100.6, 56, 125.8, 24 end
            owner._msufBossPhysicalGeometryApplied = true
            owner.MSUFSpec.power.enabled, owner.MSUFSpec.power.embed, owner.MSUFSpec.power.detached = true, true, false
            owner._msufPowerResourceMissing = nil
            owner.targetPowerBar.GetRect = function() return 100.6, 50, 125.8, 6 end
            uf.elements.Borders.RefreshPixelGeometry(owner)
            local function Check(barFrame, reference, context, x, y, zoom)
                local p, a, rp, dx, dy = barFrame:GetPoint(1)
                local q, b, rq, ex, ey = barFrame:GetPoint(2)
                assert(a == reference and b == reference and p == "TOPLEFT" and q == "TOPRIGHT"
                    and rp == "BOTTOMLEFT" and rq == "BOTTOMRIGHT", key .. " " .. context .. " is not on both painted bottom corners")
                local step = bounds.pixelSize * bounds.effectiveScale / bar:GetEffectiveScale()
                local function nearest(value)
                    local rw = step
                    return math.floor(math.abs(value) / rw + .5) * rw * (value < 0 and -1 or 1)
                end
                local wantX, wantY = nearest(x) * zoom, (nearest(y) - cb.Pools.UNITFRAME_GAP * step) * zoom
                assert(math.abs(dx - wantX) < .001 and math.abs(ex - dx) < .001 and math.abs(dy - wantY) < .001
                    and math.abs(ey - dy) < .001, key .. " " .. context .. " lost its saved offset or three-pixel gap")
            end
            bar:UpdateAnchorBase()
            Check(bar, bounds, "runtime", 2, -6, 1)
            local hud = pool.preview:Create(1)
            pool.preview:Position(hud, 1)
            Check(hud, bounds, "edit preview", 2, -6, 1)
            assert(menu.Open("uf_" .. key) ~= false)
            mw:RunTimers()
            local box = core.UFPreview.active
            local oldScale = box:GetScale()
            box:SetScale(.8)
            box._manualZoom = 4
            core.UFPreview.Refresh(box, "pool-outline-zoom")
            local state = box._msufPreviewScene
            Check(state.mock.cast, uf.GetNormalOutlineBounds(state.mock._body), "menu preview", 2, -6, state.scale)
            box:SetScale(oldScale)
            local xp, yp = core.UFPreviewCastbar.PoolOutlineOrigin(key, general, 2, -6)
            local _, _, _, dx, dy = bar:GetPoint(1)
            local ratio = bar:GetEffectiveScale() / bounds.effectiveScale
            assert(math.abs(xp - bounds.leftOffset - dx * ratio) < .001
                and math.abs(yp - bounds.bottomOffset - dy * ratio) < .001, key .. " footprint used the HP bottom")
            menu.HideSlashMenuAndMinibar(mw.win)
            local setPoint = bar.SetPoint
            mw.world.widgets:SetCombat(true)
            bar.SetPoint = function() error(key .. " combat changed anchors") end
            general[prefix .. "OffsetY"] = -8
            cb.Config.Invalidate()
            bar:UpdateAnchorBase()
            assert(bar._msufPoolOutlineDeferred, key .. " did not defer geometry during combat")
            Check(bar, bounds, "combat", 2, -6, 1)
            bar.SetPoint = setPoint
            mw.world.widgets:SetCombat(false)
            mw.world:FireEvent("PLAYER_REGEN_ENABLED")
            mw:RunTimers()
            Check(bar, bounds, "regen", 2, -8, 1)
            general[prefix .. "OffsetY"] = -6
            -- The old positive manual width and the standalone screen centre are
            -- still single-point anchors after leaving automatic mode.
            -- Native layout can still report the previous dual-anchor width
            -- during a mode switch. Persist the manual width on the released bar.
            local getWidth = bar.GetWidth
            bar:SetWidth(77)
            local reported = cb.Pools.Snap(bar, 126)
            bar.GetWidth = function() return reported end
            general[prefix .. "MatchWidth"] = nil
            cb.Config.Invalidate()
            bar:UpdateAnchorBase()
            bar.GetWidth = getWidth
            assert(bar:GetPoint(1) ~= "CENTER" and not bar:GetPoint(2) and math.abs(bar:GetWidth() - 126) < 1)
            general[prefix .. "Detached"] = true
            cb.Config.Invalidate()
            bar:UpdateAnchorBase()
            assert(bar:GetPoint(1) == "CENTER" and not bar:GetPoint(2))
            assert(general[prefix .. "OffsetX"] == 2 and general[prefix .. "OffsetY"] == -6)
        end
    end
end
-- Cold reload and pool creation after the secure owner exists take different
-- routes. Drive actual lifecycle events and the next-frame queue on both.
local function CheckCombatPoolStartup(combatReload)
    local cold = MW.Open(root, flavor, { open = false, keepFlush = true, tocMetadata = true, beforeCore = function(world)
        MW.InstallNativeUnitInputs(world)
        world.widgets.Methods.IsProtected = function(frame) return frame.MSUFSpec ~= nil end
        world.widgets:SetCombat(combatReload)
    end })
    local w, ns = cold.world, cold.core
    local cfg, cb = cold.M.EnsureDB().general, ns.Castbars
    cfg.bossCastbarDetached, cfg.bossCastbarMatchWidth = false, "unitframe"
    cb.Backend.Set("boss", "MSUF", cfg)
    cb.Config.Invalidate()
    if combatReload then
        w:FireEvent("ADDON_LOADED", "MidnightSimpleUnitFrames")
        w:FireEvent("PLAYER_LOGIN")
        w:FireEvent("PLAYER_ENTERING_WORLD", true, false)
        cold:RunTimers()
        assert(not ns.UF.Factory.SpawnAll() and not ns.UF.frames.boss1, "combat spawned a protected owner")
    else
        assert(ns.UF.Factory.SpawnAll() and not cb.Pools.kinds.boss.Castbars(), "pool already existed")
        w.widgets:SetCombat(true)
    end
    local bar = assert(cb.Pools.kinds.boss.Ensure()[1])
    local p, relative = bar:GetPoint(1)
    if combatReload then
        assert(p == "TOPRIGHT" and relative == w.env.UIParent, "combat reload lost the missing-owner fallback")
    else
        local owner = ns.UF.frames.boss1
        assert(p == "TOPLEFT" and (relative == owner or relative == owner.MSUFNormalOutlineBounds)
            and bar:GetPoint(2) == "TOPRIGHT", "new combat castbar kept the driver placeholder")
        local original = bar.SetPoint
        bar.SetPoint = function() error("repeated combat anchor write on a recently created pool") end
        bar:UpdateAnchorBase()
        bar.SetPoint = original
    end
    w.widgets:SetCombat(false)
    w:FireEvent("PLAYER_REGEN_ENABLED")
    for _ = 1, 4 do
        cold:RunTimers()
        local scheduler = ns.Scheduler.frame
        local tick = scheduler and scheduler:GetScript("OnUpdate")
        if tick then tick(scheduler, .017) end
    end
    local owner = assert(ns.UF.frames.boss1)
    p, relative = bar:GetPoint(1)
    assert(p == "TOPLEFT" and relative == owner.MSUFNormalOutlineBounds and bar:GetPoint(2) == "TOPRIGHT",
        "regen left the boss castbar on its temporary anchor")
end
if mainline then
    CheckCombatPoolStartup(true)
    CheckCombatPoolStartup(false)
end
assert(checked > 0, "no supported unit castbars exercised")
print("PASS enabled castbar footprint " .. flavor .. ": " .. checked .. " unit types, target text and animation")

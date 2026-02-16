-- Core/MSUF_Portraits.lua — Portrait system (3D portraits + boss portrait layout)
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber = type, tonumber

function MSUF_UpdateBossPortraitLayout(f, conf)
    if not f or not f.portrait or not conf then  return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local size = math.max(16, h - 4)
    local portrait = f.portrait
    portrait:ClearAllPoints()
    portrait:SetSize(size, size)
    local anchor = f.hpBar or f
    if f._msufPowerBarReserved then
        anchor = f
    end
    if mode == "LEFT" then
        portrait:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
        portrait:Show()
    elseif mode == "RIGHT" then
        portrait:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
        portrait:Show()
    else
        portrait:Hide()
    end
 end
local MSUF_PORTRAIT_MIN_INTERVAL = 0.06 -- seconds; small enough to feel instant
local MSUF_PORTRAIT_BUDGET_USED = false
local MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = false
local function MSUF_ResetPortraitBudgetNextFrame()
    if MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED then  return end
    MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = true
    C_Timer.After(0, function()
        MSUF_PORTRAIT_BUDGET_USED = false
        MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = false
     end)
 end
local function MSUF_ApplyPortraitLayoutIfNeeded(f, conf)
    if not f or not conf then  return end
    local portrait = f.portrait
    if not portrait then  return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    if ns.Cache.StampChanged(f, "PortraitLayout", mode, h) then
        f._msufPortraitLayoutStamp = 1
        MSUF_UpdateBossPortraitLayout(f, conf)
    end
 end
local function MSUF_UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait)
    if not f or not f.portrait or not conf then  return end
    local mode = conf.portraitMode or "OFF"

    -- Render mode: "2D" (default/legacy), "3D" (external module), "CLASS" (class icon).
    local render = conf.portraitRender
    if render ~= "3D" and render ~= "CLASS" then
        render = "2D"
    end
    if f._msufPortraitRenderStamp ~= render then
        f._msufPortraitRenderStamp = render
        if mode ~= "OFF" then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
        end
    end
    if f._msufPortraitModeStamp ~= mode then
        f._msufPortraitModeStamp = mode
        if mode ~= "OFF" then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
    end
    end
    if mode == "OFF" then
        f.portrait:Hide()
        return
    end
    -- In Edit Mode (or Boss Test Mode), show a placeholder portrait even if the unit doesn't exist,
    -- so users can position/size it reliably.
    local allowPreview = false
    if not existsForPortrait then
        local inCombat = (F.InCombatLockdown and F.InCombatLockdown()) and true or false
        if not inCombat and (MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode)) then
            allowPreview = true
        end
    end
    if not existsForPortrait and not allowPreview then
        f.portrait:Hide()
        return
    end
    MSUF_ApplyPortraitLayoutIfNeeded(f, conf)
    if f._msufPortraitDirty then
        local now = (F.GetTime and F.GetTime()) or 0
        local nextAt = tonumber(f._msufPortraitNextAt) or 0
        if (now >= nextAt) and (not MSUF_PORTRAIT_BUDGET_USED) then
            local portrait = f.portrait
            if render == "CLASS" then
                -- Important: only render class icon for *player* units.
                -- Boss/NPC targets can still return a class token via UnitClass(), but should keep their 2D portrait.
                local useClassIcon = false
                if not existsForPortrait then
                    -- EditMode/BossTest placeholder: show player's class icon.
                    useClassIcon = true
                elseif F.UnitIsPlayer and (F.UnitIsPlayer(unit) == true) then
                    useClassIcon = true
                end

                if useClassIcon then
                    local u = existsForPortrait and unit or "player"
                    local class = (F.UnitClassBase and F.UnitClassBase(u)) or (F.UnitClass and select(2, F.UnitClass(u)))
                    local coords = (class and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]) or nil
                    if coords and portrait.SetTexture and portrait.SetTexCoord then
                        portrait:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                        portrait:SetTexCoord(coords[1] or 0, coords[2] or 1, coords[3] or 0, coords[4] or 1)
                    else
                        -- Fallback: render a normal portrait if we can't resolve class coords.
                        if portrait.SetTexCoord then
                            portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                        end
                        if existsForPortrait and SetPortraitTexture then
                            SetPortraitTexture(portrait, unit)
                        elseif portrait.SetTexture then
                            portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                        end
                    end
                else
                    -- NPC/Boss: keep normal 2D portrait even when "Class Icon" render is selected.
                    if portrait.SetTexCoord then
                        portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                    end
                    if existsForPortrait and SetPortraitTexture then
                        SetPortraitTexture(portrait, unit)
                    elseif portrait.SetTexture then
                        portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                    end
                end
            else
                -- 2D (and legacy 3D fallback): standard portrait texture with a small crop.
                if portrait.SetTexCoord then
                    portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                end
                if existsForPortrait and SetPortraitTexture then
                    SetPortraitTexture(portrait, unit)
                elseif portrait.SetTexture then
                    portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                end
            end
            f._msufPortraitDirty = nil
            f._msufPortraitNextAt = now + MSUF_PORTRAIT_MIN_INTERVAL
            MSUF_PORTRAIT_BUDGET_USED = true
            MSUF_ResetPortraitBudgetNextFrame()
        else
            if not f._msufPortraitRetryScheduled and C_Timer and C_Timer.After then
                f._msufPortraitRetryScheduled = true
                local delay = 0
                if now < nextAt then
                    delay = nextAt - now
                    if delay < 0 then delay = 0 end
                end
                C_Timer.After(delay, function()
                    if not f then  return end
                    f._msufPortraitRetryScheduled = nil
                    if not f._msufPortraitDirty then  return end
                    ns.UF.RequestUpdate(f, false, false, "PortraitRetry")
                 end)
            end
            MSUF_ResetPortraitBudgetNextFrame()
    end
    end
    f.portrait:Show()
 end

-- Export for UFCore's spec-driven Portrait element (avoids forcing full legacy updates on portrait events).
_G.MSUF_UpdatePortraitIfNeeded = MSUF_UpdatePortraitIfNeeded

-- Hot-path gate: portraits should not be touched every UF update. We only re-render when:
--  - portrait settings (mode/render) change
--  - portrait layout (height) changes
--  - the unit identity changes (target/focus)
--  - the frame is explicitly marked dirty (e.g. unit appeared/disappeared)
local function MSUF_MaybeUpdatePortrait(f, unit, conf, existsForPortrait)
    if not f or not f.portrait or not conf then  return end

    local mode = conf.portraitMode or "OFF"
    local render = conf.portraitRender
    if render ~= "3D" and render ~= "CLASS" then
        render = "2D"
    end

    -- Fast OFF gate (still guarantees a hide if something left it shown).
    if mode == "OFF" and f._msufPortraitModeStamp == "OFF" and (not f._msufPortraitDirty) then
        local p = f.portrait
        if p and p.IsShown and p:IsShown() then
            p:Hide()
        end
        return
    end

    local need = false

    -- Settings change
    if f._msufPortraitModeStamp ~= mode or f._msufPortraitRenderStamp ~= render then
        need = true
    end

    -- Layout change (height impacts portrait size/anchor)
    local h = tonumber(conf.height) or (f.GetHeight and f:GetHeight()) or 0
    if f._msufPortraitLayoutModeStamp ~= mode or f._msufPortraitLayoutHStamp ~= h then
        f._msufPortraitLayoutModeStamp = mode
        f._msufPortraitLayoutHStamp = h
        need = true
    end

    -- Identity-based gate: only re-render once per unit swap (GUID change).
    -- This avoids repeated portrait work during UNIT_MODEL_CHANGED / UNIT_PORTRAIT_UPDATE spam,
    -- while still updating correctly when the underlying unit token points to a new unit.
    local doGuidGate = false
    if unit == "target" or unit == "focus" or unit == "targettarget" then
        doGuidGate = true
    elseif unit ~= "player" and type(unit) == "string" and unit:sub(1, 4) == "boss" then
        doGuidGate = true
    end

    if existsForPortrait and doGuidGate then
        local guid = (F.UnitGUID and F.UnitGUID(unit)) or nil
        if guid ~= f._msufPortraitLastGuid then
            f._msufPortraitLastGuid = guid
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
            need = true
        end
    end

    if f._msufPortraitDirty then
        need = true
    end

    if not need then
        return
    end

    MSUF_UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait)
end

-- Export so UFCore can use the same gating (and avoid repeated work on UNIT_MODEL_CHANGED spam).
_G.MSUF_MaybeUpdatePortrait = MSUF_MaybeUpdatePortrait
-- then multiplies by maxChars to get a clip width. Never measures secret unit names. to get a clip width. Never measures secret unit names.

local addonName, ns = ...
ns = ns or {}

-- Shared Lib initialization (loaded BEFORE Options and Main)
-- Goal: stable ns.LSM reference regardless of load order / refactors.

local function TryInitLSM()
    if ns.LSM then return true end

    local libStub = _G.LibStub
    if not libStub then return false end

    local ok, lsm = pcall(libStub, "LibSharedMedia-3.0", true)
    -- LibStub("LibSharedMedia-3.0", true) returns nil if not available.
    if ok and lsm then
        ns.LSM = lsm
        _G.MSUF_LSM = lsm

        -- Inform Main (which caches LSM in a local upvalue) that LSM is now ready.
        if type(_G.MSUF_OnLSMReady) == "function" then
            _G.MSUF_OnLSMReady(lsm)
        end

        return true
    end
    return false
end

local function EnsureLSMCallbacks()
    local LSM = ns.LSM
    if not LSM then return end
    if _G.MSUF_LSM_CallbacksRegistered then return end
    _G.MSUF_LSM_CallbacksRegistered = true

    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediatype, key)
        if mediatype == "font" then
            if type(_G.MSUF_RebuildFontChoices) == "function" then
                _G.MSUF_RebuildFontChoices()
            end

            if _G.MSUF_DB and _G.MSUF_DB.general and _G.MSUF_DB.general.fontKey == key then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if type(_G.UpdateAllFonts) == "function" then
                            _G.UpdateAllFonts()
                        end
                    end)
                elseif type(_G.UpdateAllFonts) == "function" then
                    _G.UpdateAllFonts()
                end
            end

        elseif mediatype == "statusbar" then
            if type(_G.MSUF_RebuildStatusbarChoices) == "function" then
                _G.MSUF_RebuildStatusbarChoices()
            end
        end
    end)
end

-- -----------------------------------------------------------------------------
-- Bundled fonts (Media/Fonts)
-- -----------------------------------------------------------------------------

local function RegisterBundledFonts()
    if _G.MSUF_BUNDLED_FONTS_REGISTERED then return end

    local LSM = ns.LSM
    if not LSM or type(LSM.Register) ~= "function" then
        return
    end

    local base = "Interface/AddOns/" .. tostring(addonName) .. "/Media/Fonts/"
    local fonts = {
        { key = "EXPRESSWAY", name = "Expressway Regular (MSUF)", file = "Expressway Regular.ttf" },
        { key = "EXPRESSWAY_BOLD", name = "Expressway Bold (MSUF)", file = "Expressway Bold.ttf" },
        { key = "EXPRESSWAY_SEMIBOLD", name = "Expressway SemiBold (MSUF)", file = "Expressway SemiBold.ttf" },
        { key = "EXPRESSWAY_EXTRABOLD", name = "Expressway ExtraBold (MSUF)", file = "Expressway ExtraBold.ttf" },
        { key = "EXPRESSWAY_CONDENSED_LIGHT", name = "Expressway Condensed Light (MSUF)", file = "Expressway Condensed Light.otf" },
    }

    for _, info in ipairs(fonts) do
        local path = base .. info.file
        pcall(LSM.Register, LSM, "font", info.key, path)
        if info.name then
            pcall(LSM.Register, LSM, "font", info.name, path)
        end
    end

    -- Bundled bar/castbar textures (Media/Bars).
    -- Registered here to be load-order-safe.
    local baseBars = "Interface/AddOns/" .. tostring(addonName) .. "/Media/Bars/"
    local function Reg(name, file)
        pcall(LSM.Register, LSM, "statusbar", name, baseBars .. file)
    end

    Reg("MSUF Charcoal",   "Charcoal.tga")
    Reg("MSUF Minimalist", "Minimalist.tga")
    Reg("MSUF Slickrock",  "Slickrock.tga")
    Reg("MSUF Smooth",     "MSUF_Smooth.tga")
    Reg("MSUF Smooth v2",  "Smoothv2.tga")
    Reg("MSUF Smoother",   "smoother.tga")

    -- DB migration: eliminate broken legacy selections ("MSUF Flat"/"MSUF Smooth")
    local function MigrateLegacyBarKeys()
        local db = _G.MSUF_DB
        if type(db) ~= "table" or type(db.general) ~= "table" then return end
        local g = db.general
        local changed = false

        -- Migrate old Midnight texture names to new MSUF names (renaming only)
        local map = {
            ["Midnight Charcoal"] = "MSUF Charcoal",
            ["Midnight Minimalist"] = "MSUF Minimalist",
            ["Midnight Slickrock"] = "MSUF Slickrock",
            ["Midnight Smooth"] = "MSUF Smooth",
            ["Midnight Smooth v2"] = "MSUF Smooth v2",
            ["Midnight Smoother"] = "MSUF Smoother",
        }
        if type(g.barTexture) == "string" and map[g.barTexture] then
            g.barTexture = map[g.barTexture]
            changed = true
        end
        if type(g.castbarTexture) == "string" and map[g.castbarTexture] then
            g.castbarTexture = map[g.castbarTexture]
            changed = true
        end
        if g.barTexture == "MSUF Flat" then
            g.barTexture = "Solid"
            changed = true
        elseif g.barTexture == "MSUF Smooth" then
            g.barTexture = "MSUF Smooth"
            changed = true
        end

        if g.castbarTexture == "MSUF Flat" then
            g.castbarTexture = "Solid"
            changed = true
        elseif g.castbarTexture == "MSUF Smooth" then
            g.castbarTexture = "MSUF Smooth"
            changed = true
        end

        if changed then
            if type(_G.MSUF_UpdateAllBarTextures) == "function" then
                pcall(_G.MSUF_UpdateAllBarTextures)
            end
            if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
                pcall(_G.MSUF_UpdateCastbarVisuals)
            end
        end
    end

    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, MigrateLegacyBarKeys)
    else
        MigrateLegacyBarKeys()
    end

    _G.MSUF_BUNDLED_FONTS_REGISTERED = true
end

-- Initial attempt (works when libs are already available)
if TryInitLSM() then
    EnsureLSMCallbacks()
    RegisterBundledFonts()
else
    -- Load-order-safe fallback: retry when other addons load / on login.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if TryInitLSM() then
            EnsureLSMCallbacks()
            RegisterBundledFonts()
            f:UnregisterEvent("ADDON_LOADED")
            f:UnregisterEvent("PLAYER_LOGIN")
            f:SetScript("OnEvent", nil)
        end
    end)
end


-- -----------------------------------------------------------------------------
-- LoD module helpers (Castbars/GamePlay/etc.)
-- -----------------------------------------------------------------------------

-- Export the core namespace for LoadOnDemand sub-addons.
_G.MSUF_NS = _G.MSUF_NS or ns

-- Safe helper to load a LoD sub-addon at runtime.
-- Returns true if the addon is loaded after the call.
function _G.MSUF_EnsureAddonLoaded(addonName)
    if type(addonName) ~= "string" or addonName == "" then
        return false
    end

    local function IsLoaded()
        if _G.C_AddOns and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
            return _G.C_AddOns.IsAddOnLoaded(addonName)
        end
        if type(_G.IsAddOnLoaded) == "function" then
            return _G.IsAddOnLoaded(addonName)
        end
        return false
    end

    if IsLoaded() then
        return true
    end

    local loader
    if _G.C_AddOns and type(_G.C_AddOns.LoadAddOn) == "function" then
        loader = _G.C_AddOns.LoadAddOn
    elseif type(_G.LoadAddOn) == "function" then
        loader = _G.LoadAddOn
    end

    if type(loader) ~= "function" then
        return false
    end

    pcall(loader, addonName)
    return IsLoaded()
end



-- -----------------------------------------------------------------------------
-- Global UI Scale (combat-safe gate)
-- -----------------------------------------------------------------------------
-- Fixes: /reload in combat (or any in-combat scale apply) causing ADDON_ACTION_BLOCKED
-- by deferring Global UI scale changes until PLAYER_REGEN_ENABLED.
--
-- Important: We intentionally wrap MSUF_SetGlobalUiScale in-place so ANY caller becomes
-- combat-safe without needing to edit every callsite (SlashMenu / Options / etc.).
--
function _G.MSUF_InstallGlobalScaleGate()
    if _G.MSUF_GlobalScaleGateInstalled then return end
    _G.MSUF_GlobalScaleGateInstalled = true

    local function TryWrap()
        local fn = _G.MSUF_SetGlobalUiScale
        if type(fn) ~= "function" then
            return false
        end

        -- Already wrapped?
        if _G.MSUF_SetGlobalUiScale_GATED and fn == _G.MSUF_SetGlobalUiScale_GATED then
            return true
        end

        -- Preserve raw implementation (first one wins)
        if type(_G.MSUF_SetGlobalUiScale_RAW) ~= "function" then
            _G.MSUF_SetGlobalUiScale_RAW = fn
        end

        -- Create/ensure the deferred-apply frame once.
        if not _G.MSUF_GlobalScaleGateFrame then
            local gf = CreateFrame("Frame")
            _G.MSUF_GlobalScaleGateFrame = gf
            gf:RegisterEvent("PLAYER_REGEN_ENABLED")
            gf:SetScript("OnEvent", function()
                local args = _G.MSUF_PendingGlobalScaleArgs
                _G.MSUF_PendingGlobalScaleArgs = nil

                if not args then return end
                if InCombatLockdown and InCombatLockdown() then
                    -- Still not safe (edge case): keep pending.
                    _G.MSUF_PendingGlobalScaleArgs = args
                    return
                end

                local raw = _G.MSUF_SetGlobalUiScale_RAW
                if type(raw) == "function" then
                    -- Unpack pending args and apply once after combat.
                    pcall(raw, unpack(args))
                end
            end)
        end

        -- Gate wrapper: defer in combat, else passthrough.
        _G.MSUF_SetGlobalUiScale_GATED = function(...)
            local scale = select(1, ...)
            if scale == nil then return end

            if InCombatLockdown and InCombatLockdown() then
                -- Last-call-wins: overwrite pending args.
                _G.MSUF_PendingGlobalScaleArgs = { ... }
                return
            end

            local raw = _G.MSUF_SetGlobalUiScale_RAW
            if type(raw) == "function" then
                return raw(...)
            end
        end

        _G.MSUF_SetGlobalUiScale = _G.MSUF_SetGlobalUiScale_GATED
        return true
    end

    -- Install immediately if possible; otherwise retry on common init events.
    if TryWrap() then
        return
    end

    if not _G.MSUF_GlobalScaleInstallFrame then
        local f = CreateFrame("Frame")
        _G.MSUF_GlobalScaleInstallFrame = f
        f:RegisterEvent("ADDON_LOADED")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function()
            if TryWrap() then
                f:UnregisterEvent("ADDON_LOADED")
                f:UnregisterEvent("PLAYER_LOGIN")
                f:UnregisterEvent("PLAYER_ENTERING_WORLD")
                f:SetScript("OnEvent", nil)
            end
        end)
    end
end

-- Convenience helper (optional): apply global scale safely even if gate isn't installed yet.
function _G.MSUF_ApplyGlobalScale_IfSafe(scale, quiet)
    if not _G.MSUF_GlobalScaleGateInstalled then
        _G.MSUF_InstallGlobalScaleGate()
    end

    if type(_G.MSUF_SetGlobalUiScale) == "function" then
        _G.MSUF_SetGlobalUiScale(scale, quiet)
    end
end

-- Ensure gate is installed as early as possible (before any C_Timer.After(0) scale applies fire).
if _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(0, function()
        _G.MSUF_InstallGlobalScaleGate()
    end)
else
    _G.MSUF_InstallGlobalScaleGate()
end


-- Auto-load Castbars LoD addon on login when any castbar feature is enabled.
-- (Keeps the core addon slim, but still "just works" out of the box.)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if type(_G.EnsureDB) == "function" then
            _G.EnsureDB()
        end

        local g = _G.MSUF_DB and _G.MSUF_DB.general or nil
        if not g then
            return
        end

        local need = false
        if g.enablePlayerCastbar ~= false then need = true end
        if g.enableTargetCastbar ~= false then need = true end
        if g.enableFocusCastbar ~= false then need = true end
        if g.enableBossCastbar == true then need = true end

        if need then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        end
    end)
end



-- Auto-load Gameplay LoD addon on login when any gameplay feature is enabled.
-- (Prevents "feature looks enabled but does nothing until you toggle twice" after /reload or relog.)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if type(_G.EnsureDB) == "function" then
            _G.EnsureDB()
        end

        local g = _G.MSUF_DB and _G.MSUF_DB.gameplay or nil
        if not g then
            return
        end

        local need = false
        if g.enableCombatTimer == true then need = true end
        if g.enableCombatStateText == true then need = true end
        if g.enableFirstDanceTimer == true then need = true end
        if g.enableCombatCrosshair == true then need = true end

        if need then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Gameplay")

            -- Apply immediately so event wiring is active without opening the Gameplay menu.
            local ns2 = _G.MSUF_NS
            if ns2 and type(ns2.MSUF_RequestGameplayApply) == "function" then
                ns2.MSUF_RequestGameplayApply()
            elseif type(_G.MSUF_RequestGameplayApply) == "function" then
                _G.MSUF_RequestGameplayApply()
            end
        end
    end)
end


-- -----------------------------------------------------------------------------
-- Range checking removed for maximum performance (user request).
-- Keep a stub so any legacy calls are harmless.
function _G.MSUF_EnsureLibRangeCheck()
    return nil
end

--- Applies an active profile to runtime owners, after the full core TOC loads.
--- Profile storage/import code calls Apply after committing the new DB.
local _, MSUF = ...
local pendingApply, deferFrame

local function MSUF_ProfileIO_SafeMSUFScale()
    local g = type(MSUF_DB) == "table" and type(MSUF_DB.general) == "table" and MSUF_DB.general or nil
    local scale = tonumber(g and g.msufUiScale) or 1
    if scale < 0.25 then
        scale = 1
    elseif scale > 2.0 then
        scale = 2.0
    end
    return scale
end
local function MSUF_ProfileIO_RunFrameScaleApply()
    _G.MSUF_ApplyMsufScale(MSUF_ProfileIO_SafeMSUFScale())
end
local function MSUF_ProfileIO_ApplyCastbarRuntime(reason)
    _G.MSUF_Castbars_OnSettingsChanged(reason)
    _G.MSUF_ApplyAllCastbarsAndSync()
end

--- The coordinated UF apply already owns unit-frame text, while the explicit
--- class-power/castbar passes below own their fonts. Keep one font-runtime pass
--- for external consumers and Auras3. Imports refresh their aura payload before
--- this hook, so they skip the otherwise required profile-switch aura refresh.
local function MSUF_ProfileIO_ApplyExternalFontFollowers(skipAuras)
    _G.MSUF_UpdateAllFonts_Immediate(nil, true, true, true, skipAuras == true)
end

local MSUF_ProfileIO_PostProfileRuntimeApply
local function MSUF_ProfileIO_CheckLocaleReload()
    local namespace = _G.MSUF_NS or _G.MSUF
    if not (namespace and type(namespace.SetLocale) == "function") then return false end
    local configured = type(namespace.ResolveConfiguredLocale) == "function"
        and namespace.ResolveConfiguredLocale(_G.MSUF_DB)
        or (_G.GetLocale and _G.GetLocale())
    local _, reloadRequired = namespace.SetLocale(configured)
    if reloadRequired ~= true then return false end

    local menu = namespace.MSUF2 or _G.MSUF2
    if menu and type(menu.ShowLocaleReloadRequired) == "function" then
        menu.ShowLocaleReloadRequired()
    elseif _G.print then
        _G.print("|cffffd700MSUF:|r Menu language changed with the profile. Reload the UI to apply it.")
    end
    return true
end
local function MSUF_ProfileIO_InCombatLockdown()
    return _G.InCombatLockdown()
end

--- One fanout point after profile mutations. If protected frame work is unsafe
--- in combat, the expensive/restricted part is deferred but cheap visual state
--- such as scale and Blizzard-frame ownership is still nudged immediately.
local function MSUF_ProfileIO_DeferPostProfileRuntimeApply(reason, applyAll)
    if not MSUF_ProfileIO_InCombatLockdown() then
        return false
    end
    pendingApply = {
        reason = reason or "PROFILE_APPLY",
        applyAll = applyAll == true,
    }
    local f = deferFrame
    if not f then
        f = _G.CreateFrame("Frame")
        deferFrame = f
        f:SetScript("OnEvent", function(self, event)
            if event ~= "PLAYER_REGEN_ENABLED" then return end
            if MSUF_ProfileIO_InCombatLockdown() then return end
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local pending = pendingApply
            pendingApply = nil
            if pending then
                MSUF_ProfileIO_PostProfileRuntimeApply(pending.reason or "PROFILE_APPLY_AFTER_COMBAT", pending.applyAll == true)
            end
        end)
    end
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    MSUF.UF.DisableBlizzardFrames()
    MSUF_ProfileIO_RunFrameScaleApply()
    return true
end
--- Runtime dependency order after a profile becomes active. The sequence
--- below is the only place this order is written down; each step assumes the
--- earlier ones already ran on the new MSUF_DB:
---   1. Blizzard frame ownership, then the MSUF frame scale.
---   2. Small profile-scoped switches (target sounds, NSRT nicknames) and the
---      external Edit Mode adapters (Ellesmere, Grid2, Details, Dominos,
---      Danders, Blizzard) plus the stored Blizzard Edit Mode snapshot.
---   3. Cached-view invalidation: group-frame conf cache, number-format
---      upvalues, unit-frame compiled configs. These must precede any rebuild
---      or the rebuild reads the previous profile's cached tables.
---   4. The coordinated unit-frame apply, then modules, group frames, class power,
---      embedded power bar layout, castbars, font followers.
---   5. Locale reload check last, because it may prompt a UI reload.
--- Do not reorder or rename the string-named globals here without checking
--- every consumer: providers load later in the core TOC and are required.
MSUF_ProfileIO_PostProfileRuntimeApply = function(reason, applyAll)
    reason = reason or "PROFILE_APPLY"
    if MSUF_ProfileIO_DeferPostProfileRuntimeApply(reason, applyAll) then
        return
    end
    MSUF.UF.DisableBlizzardFrames()
    MSUF_ProfileIO_RunFrameScaleApply()
    _G.MSUF_TargetSoundDriver_ApplySetting()
    _G.MSUF_NSRTNicknames_ApplySetting()
    local activeGeneral = _G.MSUF_DB and _G.MSUF_DB.general
    _G.MSUF_EllesmereEditMode_SetEnabled(not (type(activeGeneral) == "table" and activeGeneral.ellesmereEditModeIntegration == false))
    _G.MSUF_Grid2EditMode_SetEnabled(not (type(activeGeneral) == "table" and activeGeneral.grid2EditModeIntegration == false))
    _G.MSUF_DetailsEditMode_SetEnabled(not (type(activeGeneral) == "table" and activeGeneral.detailsEditModeIntegration == false))
    _G.MSUF_DominosEditMode_SetEnabled(not (type(activeGeneral) == "table" and activeGeneral.dominosEditModeIntegration == false))
    _G.MSUF_DandersEditMode_SetEnabled(not (type(activeGeneral) == "table" and activeGeneral.dandersEditModeIntegration == false))
    _G.MSUF_BlizzardEditMode_SetEnabled(not (type(activeGeneral) == "table" and activeGeneral.blizzardEditModeIntegration == false))
    --- The profile carries the last committed Blizzard Edit Mode arrangement
    --- (general.blizzardEditModeSnapshot); re-apply it for the new profile.
    _G.MSUF_BlizzardEditMode_ApplyProfileSnapshot()
    --- Group-frame config tables are cached by identity. Drop those references
    --- before the runtime rebuild reads the newly active profile root.
    _G.MSUF_GF_InvalidateConfCache()

    --- The number-abbreviation style is held as an upvalue in every text
    --- consumer, so it must be re-resolved from the new profile before the
    --- rebuild below formats anything.
    MSUF.NumberFormat.Refresh()

    local UF = MSUF and MSUF.UF
    local metadata = UF and UF.Metadata
    local coordinatedApplyMask = metadata and metadata.coordinatedApplyMask
    _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason, coordinatedApplyMask)
    _G.MSUF_ApplyModules()
    _G.MSUF_GF_RebuildAll()
    _G.MSUF_ClassPower_Apply({ full = true, cdm = true })
    _G.MSUF_ApplyPowerBarEmbedLayout_All()
    MSUF_ProfileIO_ApplyCastbarRuntime(reason)
    MSUF_ProfileIO_ApplyExternalFontFollowers(applyAll == true)
    MSUF_ProfileIO_CheckLocaleReload()
end

MSUF.ProfileRuntime = { Apply = MSUF_ProfileIO_PostProfileRuntimeApply }

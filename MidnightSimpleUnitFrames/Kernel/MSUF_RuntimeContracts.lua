--- Final core TOC boundary. These providers are required by profile/font apply;
--- resolve them once after their defining files, never in a hot dispatch wrapper.
local _, MSUF = ...
local globals = {
    "MSUF_ApplyMsufScale",
    "MSUF_TargetSoundDriver_ApplySetting", "MSUF_NSRTNicknames_ApplySetting",
    "MSUF_EllesmereEditMode_SetEnabled", "MSUF_Grid2EditMode_SetEnabled",
    "MSUF_DetailsEditMode_SetEnabled", "MSUF_DominosEditMode_SetEnabled",
    "MSUF_DandersEditMode_SetEnabled", "MSUF_BlizzardEditMode_SetEnabled",
    "MSUF_BlizzardEditMode_ApplyProfileSnapshot", "MSUF_GF_InvalidateConfCache",
    "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll",
    "MSUF_ClassPower_Apply", "MSUF_ApplyPowerBarEmbedLayout_All",
    "MSUF_Castbars_OnSettingsChanged", "MSUF_ApplyAllCastbarsAndSync",
    "MSUF_UpdateAllFonts_Immediate", "MSUF_UpdateCastbarVisuals_Immediate",
    "MSUF_ApplyCastbarVisualsForUnit",
}
for i = 1, #globals do
    local name = globals[i]
    if type(_G[name]) ~= "function" then
        error("MSUF core load incomplete: required function " .. name .. " missing")
    end
end
local methods = {
    { "UF", "DisableBlizzardFrames" }, { "UF", "RefreshElements" },
    { "GF", "RefreshFonts" }, { "GF", "RefreshColors" }, { "GF", "RefreshVisuals" },
    { "NumberFormat", "Refresh" }, { "ProfileRuntime", "Apply" },
}
for i = 1, #methods do
    local owner, name = methods[i][1], methods[i][2]
    if type(MSUF[owner]) ~= "table" or type(MSUF[owner][name]) ~= "function" then
        error("MSUF core load incomplete: required function " .. owner .. "." .. name .. " missing")
    end
end

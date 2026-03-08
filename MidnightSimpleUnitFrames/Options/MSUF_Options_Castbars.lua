-- ---------------------------------------------------------------------------
-- MSUF_Options_Castbars.lua
-- Split from MSUF_Options_Core.lua — Castbar tab BUILD code.
-- Zero feature regression: same widgets, same DB keys, same behaviors.
-- ---------------------------------------------------------------------------
local addonName, addonNS = ...
ns = (_G and _G.MSUF_NS) or addonNS or ns or {}
if _G then _G.MSUF_NS = ns end

-- ---------------------------------------------------------------------------
-- Localization helper (keys are English UI strings; fallback = key)
-- ---------------------------------------------------------------------------
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(t, k) return k end })
end
local isEn = (ns and ns.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end

function ns.MSUF_Options_Castbar_Build(panel, castbarGroupHost, castbarGroup, castbarEnemyGroup, castbarFocusGroup, castbarPlayerGroup, castbarTargetGroup, castbarBossGroup, ctx)
    if not panel or not castbarEnemyGroup then return end
    -- -----------------------------------------------------------------
    -- Compat helpers (resolve from ctx / ns / _G; never assume globals)
    -- -----------------------------------------------------------------
    local CreateLabeledCheckButton = ctx and ctx.CreateLabeledCheckButton
    local CreateLabeledSlider      = (ctx and ctx.CreateLabeledSlider) or (ns and (ns.MSUF_CreateLabeledSlider or ns.CreateLabeledSlider)) or _G.CreateLabeledSlider
    local MSUF_SetLabeledSliderValue   = (ctx and ctx.MSUF_SetLabeledSliderValue) or (ns and ns.MSUF_SetLabeledSliderValue) or _G.MSUF_SetLabeledSliderValue
    local MSUF_SetLabeledSliderEnabled = (ctx and ctx.MSUF_SetLabeledSliderEnabled) or (ns and ns.MSUF_SetLabeledSliderEnabled) or _G.MSUF_SetLabeledSliderEnabled
    local MSUF_InitSimpleDropdown      = _G.MSUF_InitSimpleDropdown
    local MSUF_SyncSimpleDropdown      = _G.MSUF_SyncSimpleDropdown
    local MSUF_ExpandDropdownClickArea = (ns and ns.MSUF_ExpandDropdownClickArea) or _G.MSUF_ExpandDropdownClickArea
    local MSUF_MakeDropdownScrollable  = (ns and ns.MSUF_MakeDropdownScrollable) or _G.MSUF_MakeDropdownScrollable
    local MSUF_SetDropDownEnabled      = (ns and ns.MSUF_SetDropDownEnabled) or _G.MSUF_SetDropDownEnabled
    local MSUF_GetLSM       = (ns and ns.MSUF_GetLSM) or _G.MSUF_GetLSM
    local MSUF_EnsureCastbars = (ns and ns.MSUF_EnsureCastbars) or _G.MSUF_EnsureCastbars
    local MSUF_KillMenuPreviewBar = _G.MSUF_KillMenuPreviewBar
    local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
    if type(CreateLabeledCheckButton) ~= "function" then return end
    if type(MSUF_ExpandDropdownClickArea) ~= "function" then MSUF_ExpandDropdownClickArea = function() end end
    if type(MSUF_MakeDropdownScrollable) ~= "function" then MSUF_MakeDropdownScrollable = function() end end
    local function EnsureDB() if type(_G.EnsureDB) == "function" then _G.EnsureDB() end end
    -- Forward-declare locals filled below (widget references)
    local castbarTitle, castbarFocusButton
    local castbarInterruptShakeCheck, castbarShakeIntensitySlider
    local castbarUnifiedDirCheck, castbarFillDirDrop, castbarFillDirLabel
    local castbarOpositeDirectionTarget, castbarChannelTicksCheck
    local castbarGCDBarCheck, castbarGCDTimeCheck, castbarGCDSpellCheck
    local castbarGlowCheck, castbarLatencyCheck
    local empowerColorStagesCheck, empowerStageBlinkCheck, empowerStageBlinkTimeSlider
    local castbarGeneralTitle, castbarGeneralLine, castbarTexColorTitle, castbarTexColorLine
    local castbarTextureLabel, castbarTexturePreview, castbarTextureInfo
    -- -----------------------------------------------------------------
    -- BUILD (extracted from MSUF_Options_Core.lua — zero behavior change)
    -- -----------------------------------------------------------------
    castbarTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    castbarTitle:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -120)
-- Castbar submenu trimmed (UI cleanup):
-- Removed: BACK, Player, Target, Boss subpages
-- Kept: Focus Kick options (toggle via button) + Castbar Edit Mode button
castbarFocusButton = CreateFrame("Button", "MSUF_CastbarFocusButton", castbarGroupHost or castbarGroup, "UIPanelButtonTemplate")
castbarFocusButton:SetSize(120, 22)
castbarFocusButton:ClearAllPoints()
castbarFocusButton:SetPoint("TOPLEFT", castbarGroupHost or castbarGroup, "TOPLEFT", 16, -150)
castbarFocusButton:SetText(TR("Focus Kick"))
castbarFocusButton:SetFrameLevel(((castbarGroupHost or castbarGroup):GetFrameLevel() or 0) + 10)
if MSUF_SkinMidnightActionButton then
    MSUF_SkinMidnightActionButton(castbarFocusButton)
elseif MSUF_SkinMidnightTabButton then
    -- fallback: keep it in the same family as our tabs
    MSUF_SkinMidnightTabButton(castbarFocusButton)
end
local fkfs = castbarFocusButton.GetFontString and castbarFocusButton:GetFontString() or nil
if fkfs and fkfs.SetTextColor then fkfs:SetTextColor(1, 0.82, 0) end
function MSUF_SetActiveCastbarSubPage(page)
    if castbarEnemyGroup then castbarEnemyGroup:Hide() end
    if castbarPlayerGroup then castbarPlayerGroup:Hide() end
    if castbarTargetGroup then castbarTargetGroup:Hide() end
    if castbarBossGroup then castbarBossGroup:Hide() end
    if castbarFocusGroup then castbarFocusGroup:Hide() end
    if page == "focus" then
        if castbarFocusGroup then castbarFocusGroup:Show() end
    else
        if castbarEnemyGroup then castbarEnemyGroup:Show() end
    end
 end
_G.MSUF_SetActiveCastbarSubPage = MSUF_SetActiveCastbarSubPage
-- Default: show general castbar options
MSUF_SetActiveCastbarSubPage("enemy")
-- Toggle focus kick options without needing a BACK button
castbarFocusButton:SetScript("OnClick", function()
    if castbarFocusGroup and castbarFocusGroup:IsShown() then
        MSUF_SetActiveCastbarSubPage("enemy")
    else
        MSUF_SetActiveCastbarSubPage("focus")
    end
 end)
    if not _G["MSUF_FocusKickHeaderRight"] then
        local fkHeader = castbarFocusGroup:CreateFontString("MSUF_FocusKickHeaderRight", "ARTWORK", "GameFontNormal")
        fkHeader:SetPoint("TOPLEFT", castbarFocusGroup, "TOPLEFT", 300, -220)
        fkHeader:SetText(TR("Focus Kick Icon"))
    end
    if MSUF_InitFocusKickIconOptions then MSUF_InitFocusKickIconOptions() end
    castbarGeneralTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarGeneralTitle:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -170)
    castbarGeneralLine = castbarEnemyGroup:CreateTexture(nil, "ARTWORK")
    castbarGeneralLine:SetColorTexture(1, 1, 1, 0.15)
    castbarGeneralLine:SetHeight(1)
    castbarGeneralLine:SetPoint("TOPLEFT", castbarGeneralTitle, "BOTTOMLEFT", 0, -4)
    castbarGeneralLine:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)
    castbarInterruptShakeCheck = CreateLabeledCheckButton(
        "MSUF_CastbarInterruptShakeCheck",
        "Shake on interrupt",
        castbarEnemyGroup,
        16, -200
    )
local function MSUF_SyncCastbarsTabToggles()
    EnsureDB(); local g = (MSUF_DB and MSUF_DB.general) or {}
    local function CB(cb, v)  if cb then cb:SetChecked(v and true or false) end  end
    local function NUM(key, def, minV, maxV, roundInt)
        local v = tonumber(g[key]); if type(v) ~= "number" then v = def end
        if minV and v < minV then v = minV end; if maxV and v > maxV then v = maxV end
        if roundInt then v = math.floor(v + 0.5) end
         return v
    end
    local function SL(sl, key, def, minV, maxV, enabled, roundInt)
        if not sl then  return end
        MSUF_SetLabeledSliderValue(sl, NUM(key, def, minV, maxV, roundInt))
        MSUF_SetLabeledSliderEnabled(sl, enabled and true or false)
     end
    local shake = (g.castbarInterruptShake == true)
    CB(castbarInterruptShakeCheck, shake)
    SL(castbarShakeIntensitySlider, "castbarShakeStrength", 8, 0, 30, shake, true)
    CB(castbarUnifiedDirCheck, (g.castbarUnifiedDirection == true))
    if castbarFillDirDrop then
        local dir = g.castbarFillDirection or "RTL"
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(castbarFillDirDrop, dir) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(castbarFillDirDrop, (dir == "LTR") and "Left to right" or "Right to left (default)") end
        MSUF_SetDropDownEnabled(castbarFillDirDrop, castbarFillDirLabel, true)
    end
    CB(castbarOpositeDirectionTarget, (g.castbarOpositeDirectionTarget ~= false))
    CB(castbarChannelTicksCheck, (g.castbarShowChannelTicks ~= false))
    CB(castbarGCDBarCheck, (g.showGCDBar ~= false))
    local gcdOn = (g.showGCDBar ~= false)
    if castbarGCDTimeCheck then
        castbarGCDTimeCheck:SetEnabled(gcdOn and true or false)
        CB(castbarGCDTimeCheck, (g.showGCDBarTime ~= false))
    end
    if castbarGCDSpellCheck then
        castbarGCDSpellCheck:SetEnabled(gcdOn and true or false)
        CB(castbarGCDSpellCheck, (g.showGCDBarSpell ~= false))
    end
    CB(castbarGlowCheck, (g.castbarShowGlow ~= false))
    CB(castbarLatencyCheck, (g.castbarShowLatency ~= false))
    local emp = (g.empowerColorStages ~= false)
    CB(empowerColorStagesCheck, emp)
    local blink = emp and (g.empowerStageBlink ~= false)
    if empowerStageBlinkCheck then empowerStageBlinkCheck:SetEnabled(emp and true or false); CB(empowerStageBlinkCheck, blink) end
    SL(empowerStageBlinkTimeSlider, "empowerStageBlinkTime", 0.25, 0.05, 1.00, blink, false)
 end
if castbarGroup and castbarGroup.HookScript then castbarGroup:HookScript("OnShow", MSUF_SyncCastbarsTabToggles) end
if castbarEnemyGroup and castbarEnemyGroup.HookScript then
    castbarEnemyGroup:HookScript("OnShow", MSUF_SyncCastbarsTabToggles)
end
    _G.MSUF_Options_BindGeneralBoolCheck(castbarInterruptShakeCheck, "castbarInterruptShake", nil, MSUF_SyncCastbarsTabToggles, nil)
    castbarShakeIntensitySlider = CreateLabeledSlider(
        "MSUF_CastbarShakeIntensitySlider",
        "Shake intensity",
        castbarEnemyGroup,
        0, 30, 1,         -- strength
        175, -200          -- Next to the toggles
    )
    if _G and _G.MSUF_Options_BindGeneralNumberSlider then _G.MSUF_Options_BindGeneralNumberSlider(castbarShakeIntensitySlider, "castbarShakeStrength", { def = 8, min = 0, max = 30, int = true }) end
local castbarTextureDrop
local LSM = MSUF_GetLSM()
if LSM then
    castbarTextureLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTextureLabel:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 90)
    castbarTextureLabel:SetText(TR("Castbar texture (SharedMedia)"))
    castbarTextureDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_CastbarTextureDropdown", castbarEnemyGroup) or CreateFrame("Frame", "MSUF_CastbarTextureDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate"))
    MSUF_ExpandDropdownClickArea(castbarTextureDrop)
    castbarTextureDrop:SetPoint("TOPLEFT", castbarTextureLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(castbarTextureDrop, 180)
    castbarTextureDrop._msufButtonWidth = 180
    castbarTextureDrop._msufTweakBarTexturePreview = true
    MSUF_MakeDropdownScrollable(castbarTextureDrop, 12)
    castbarTexturePreview = CreateFrame("StatusBar", nil, castbarEnemyGroup)
    castbarTexturePreview:SetSize(180, 10)
    castbarTexturePreview:SetPoint("TOPLEFT", castbarTextureDrop, "BOTTOMLEFT", 20, -6)
    castbarTexturePreview:SetMinMaxValues(0, 1)
    castbarTexturePreview:SetValue(1)
    castbarTexturePreview:Hide()
    MSUF_KillMenuPreviewBar(castbarTexturePreview)
    local function CastbarTexturePreview_Update(texName)
        local texPath
        local LSM = MSUF_GetLSM()
        if LSM and texName and texName ~= "" then
            local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", texName)
            if ok and tex then texPath = tex end
        end
        if not texPath and MSUF_GetCastbarTexture then texPath = MSUF_GetCastbarTexture() end
        if not texPath then texPath = "Interface\\TARGETINGFRAME\\UI-StatusBar" end
        castbarTexturePreview:SetStatusBarTexture(texPath)
     end
    local function CastbarTextureDropdown_Initialize(self, level)
        EnsureDB()
        local info = UIDropDownMenu_CreateInfo()
        local current = MSUF_DB.general.castbarTexture
        local LSM = MSUF_GetLSM()
        if LSM then
            local list = LSM:List("statusbar") or {}
            table.sort(list, function(a, b)  return a:lower() < b:lower() end)
                        for _, name in ipairs(list) do
                info.text  = name
                info.value = name
                -- small texture swatch on the left
                local swatchTex = nil
                local LSM2 = MSUF_GetLSM()
                if LSM2 then
                    local ok2, tex2 = pcall(LSM2.Fetch, LSM2, "statusbar", name)
                    if ok2 and tex2 then swatchTex = tex2 end
                end
                if swatchTex then
                    info.icon = swatchTex
                    info.iconInfo = {
                        tCoordLeft = 0, tCoordRight = 0.85,
                        tCoordTop  = 0, tCoordBottom = 1,
                        iconWidth  = 80,
                        iconHeight = 12,
                    }
                else
                    info.icon = nil
                    info.iconInfo = nil
                end
                info.func  = function(btn)
                    EnsureDB()
                    MSUF_DB.general.castbarTexture = btn.value
                    UIDropDownMenu_SetSelectedValue(castbarTextureDrop, btn.value)
                    UIDropDownMenu_SetText(castbarTextureDrop, btn.value)
            local fnTex = (_G and _G.MSUF_UpdateCastbarTextures_Immediate) or MSUF_UpdateCastbarTextures
            if type(fnTex) == "function" then fnTex() end
                    if MSUF_UpdateCastbarVisuals then
                        MSUF_EnsureCastbars(); local fnVis = (_G and _G.MSUF_UpdateCastbarVisuals_Immediate) or MSUF_UpdateCastbarVisuals; if type(fnVis) == "function" then fnVis() end
                    end
                    if CastbarTexturePreview_Update then CastbarTexturePreview_Update(btn.value) end
                 end
                info.checked = (name == current)
                UIDropDownMenu_AddButton(info, level)
            end
        end
     end
      UIDropDownMenu_Initialize(castbarTextureDrop, CastbarTextureDropdown_Initialize)
    EnsureDB()
    local texKey = MSUF_DB and MSUF_DB.general and MSUF_DB.general.castbarTexture
    if type(texKey) ~= "string" or texKey == "" then
        texKey = "Blizzard"
        MSUF_DB.general.castbarTexture = texKey
    end
    UIDropDownMenu_SetSelectedValue(castbarTextureDrop, texKey)
    UIDropDownMenu_SetText(castbarTextureDrop, texKey)
    CastbarTexturePreview_Update(texKey)
else
    castbarTextureInfo = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    castbarTextureInfo:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 90)
    castbarTextureInfo:SetWidth(320)
    castbarTextureInfo:SetJustifyH("LEFT")
    castbarTextureInfo:SetText(TR("Install the addon 'SharedMedia' (LibSharedMedia-3.0) to select castbar textures. Without it, the default UI castbar texture is used."))
end
    castbarTexColorTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTexColorTitle:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 250)
    castbarTexColorTitle:SetText(TR("Texture and Empowered Cast"))
    castbarTexColorLine = castbarEnemyGroup:CreateTexture(nil, "ARTWORK")
    castbarTexColorLine:SetColorTexture(1, 1, 1, 0.15)  -- gleiche Farbe wie "General"
    castbarTexColorLine:SetHeight(1)
    castbarTexColorLine:SetPoint("TOPLEFT", castbarTexColorTitle, "BOTTOMLEFT", 0, -4)
    castbarTexColorLine:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)
    castbarFillDirLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarFillDirLabel:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 160)
    castbarFillDirLabel:SetText(TR("Castbar fill direction"))
    -- Step 8: Castbar checks helper (short + no-regression)
    local function CB(frameName, label, x, y, dbKey, applyFn, anchorFn)
        local cb = CreateLabeledCheckButton(frameName, label, castbarEnemyGroup, x or 16, y or 0)
        if anchorFn then anchorFn(cb) end
        _G.MSUF_Options_BindGeneralBoolCheck(cb, dbKey, applyFn, MSUF_SyncCastbarsTabToggles, true)
         return cb
    end
    castbarUnifiedDirCheck = CB("MSUF_CastbarUnifiedDirectionCheck", "Always use fill direction for all casts", 16, 185, "castbarUnifiedDirection", "castbarFillDirection", function(cb)  cb:ClearAllPoints(); cb:SetPoint("BOTTOMLEFT", castbarFillDirLabel, "TOPLEFT", 0, 4)  end)
    castbarFillDirDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_CastbarFillDirectionDropdown", castbarEnemyGroup) or CreateFrame("Frame", "MSUF_CastbarFillDirectionDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate"))
    MSUF_ExpandDropdownClickArea(castbarFillDirDrop)
    castbarFillDirDrop:SetPoint("TOPLEFT", castbarFillDirLabel, "BOTTOMLEFT", -16, -4)
    local castbarFillDirOptions = {
        { key = "RTL", label = "Right to left (default)" },
        { key = "LTR", label = "Left to right" },
    }
    local function MSUF_GetCastbarFillDir()
        EnsureDB()
        local g = MSUF_DB.general or {}
        return g.castbarFillDirection or "RTL"
    end
    MSUF_InitSimpleDropdown(castbarFillDirDrop, castbarFillDirOptions, MSUF_GetCastbarFillDir, function(dir)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarFillDirection = dir
        if MSUF_UpdateCastbarFillDirection then MSUF_UpdateCastbarFillDirection() end
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
     end, nil, 180)
    castbarFillDirDrop:HookScript("OnShow", function()
        MSUF_SyncSimpleDropdown(castbarFillDirDrop, castbarFillDirOptions, MSUF_GetCastbarFillDir)
     end)
    -- Step 16: Apply dispatch handles castbar updates (castbarVisuals/castbarTicks/castbarGlow/castbarLatency)
    -- Able to have the two cast bars be oposite each other
    castbarOpositeDirectionTarget = CB("MSUF_CastbarOpositeDirectionTarget", "Use opposite fill direction for target", 16, 0, "castbarOpositeDirectionTarget", "castbarOpositeDirectionTarget", function(cb)  cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", castbarFillDirDrop, "BOTTOMLEFT", 16, -10)  end)
    -- Channeled casts: show 5 tick lines
    castbarChannelTicksCheck = CB("MSUF_CastbarChannelTicksCheck", "Show channel tick lines (5)", 16, 0, "castbarShowChannelTicks", "castbarTicks", function(cb)  if castbarFillDirDrop then cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", castbarOpositeDirectionTarget, "BOTTOMLEFT", 0, -10) end  end)
-- GCD bar (player): show a short bar for instant casts that trigger the global cooldown
    local function _MSUF_ApplyGCDBarToggle(v)
        v = (v and true) or false
        -- Persisted already by the binding; this is just a runtime apply hook.
        -- If Castbars LoD is not loaded yet, keep it silent: the DB value will be picked up on load.
        if _G and type(_G.MSUF_EnsureAddonLoaded) == "function" then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        end
        if _G and type(_G.MSUF_SetGCDBarEnabled) == "function" then
            _G.MSUF_SetGCDBarEnabled(v)
        end
     end
    castbarGCDBarCheck = CB(
        "MSUF_CastbarGCDBarCheck",
        "Show GCD bar for instant casts",
        16, 0,
        "showGCDBar",
        _MSUF_ApplyGCDBarToggle,
        function(cb)
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", castbarChannelTicksCheck, "BOTTOMLEFT", 0, -8)
         end
    )
    -- GCD bar sub-options (visual only)
    local function _MSUF_ApplyGCDBarVisuals()
        -- DB is already persisted; this just forces the active GCD bar (if any) to stop so new settings apply immediately.
        if _G and type(_G.MSUF_EnsureAddonLoaded) == "function" then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        end
        if _G and type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
            local f = _G.MSUF_PlayerCastBar or _G.MSUF_PlayerCastbar
            if f then _G.MSUF_PlayerGCDBar_Stop(f) end
        end
     end
    castbarGCDTimeCheck = CB(
        "MSUF_CastbarGCDTimeCheck",
        "GCD bar: show time text",
        16, 0,
        "showGCDBarTime",
        _MSUF_ApplyGCDBarVisuals,
        function(cb)
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", castbarGCDBarCheck, "BOTTOMLEFT", 18, -6)
         end
    )
    castbarGCDSpellCheck = CB(
        "MSUF_CastbarGCDSpellCheck",
        "GCD bar: show spell name + icon",
        16, 0,
        "showGCDBarSpell",
        _MSUF_ApplyGCDBarVisuals,
        function(cb)
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", castbarGCDTimeCheck, "BOTTOMLEFT", 0, -6)
         end
    )
-- Castbar glow / spark (Blizzard-style)
    castbarGlowCheck = CB("MSUF_CastbarGlowCheck", "Show castbar glow effect", 16, 0, "castbarShowGlow", "castbarGlow")
-- Latency indicator (end-of-cast spell queue / net latency zone)
    castbarLatencyCheck = CB("MSUF_CastbarLatencyCheck", "Show latency indicator", 16, 0, "castbarShowLatency", "castbarLatency")
    empowerColorStagesCheck = CB("MSUF_EmpowerColorStagesCheck", "Add color to stages (Empowered casts)", 16, 130, "empowerColorStages", "castbarVisuals", function(cb)  cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", castbarUnifiedDirCheck, "TOPLEFT", 300, 0)  end)
    empowerStageBlinkCheck = CB("MSUF_EmpowerStageBlinkCheck", "Add stage blink (Empowered casts)", 16, 130, "empowerStageBlink", "castbarVisuals", function(cb)  cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", empowerColorStagesCheck, "BOTTOMLEFT", 0, -10)  end)
empowerStageBlinkTimeSlider = CreateLabeledSlider(
    "MSUF_EmpowerStageBlinkTimeSlider",
    "Stage blink time (sec)",
    castbarEnemyGroup,
    0.05, 1.00, 0.01,
    16, 130
)
empowerStageBlinkTimeSlider:ClearAllPoints()
empowerStageBlinkTimeSlider:SetPoint("TOPLEFT", empowerStageBlinkCheck, "BOTTOMLEFT", 0, -26)
empowerStageBlinkTimeSlider:SetWidth(260)
if _G and _G.MSUF_Options_BindGeneralNumberSlider then _G.MSUF_Options_BindGeneralNumberSlider(empowerStageBlinkTimeSlider, "empowerStageBlinkTime", { def = 0.25, min = 0.05, max = 1.0 }) end
empowerStageBlinkTimeSlider:SetScript("OnShow", function(self)
    if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
 end)
    -- Castbar menu mockup layout (Behavior / Style / Empowered)
    do
        -- Panel
        local panel = _G["MSUF_CastbarMenuPanel"]
        if not panel then
            panel = CreateFrame("Frame", "MSUF_CastbarMenuPanel", castbarEnemyGroup, "BackdropTemplate")
            panel:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -175); panel:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0); panel:SetHeight(620); panel:EnableMouse(false)
            local tex = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8"
            panel:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
            panel:SetBackdropColor(0, 0, 0, 0.20); panel:SetBackdropBorderColor(1, 1, 1, 0.15)
            -- Split lines
            local vLine = panel:CreateTexture(nil, "ARTWORK"); vLine:SetColorTexture(1, 1, 1, 0.12); vLine:SetWidth(1); vLine:SetPoint("TOP", panel, "TOP", 0, -16); vLine:SetPoint("BOTTOM", panel, "BOTTOM", 0, 150)
            local hLine = panel:CreateTexture(nil, "ARTWORK"); hLine:SetColorTexture(1, 1, 1, 0.12); hLine:SetHeight(1); hLine:SetPoint("LEFT", panel, "LEFT", 16, 0); hLine:SetPoint("RIGHT", panel, "RIGHT", -16, 0); hLine:SetPoint("BOTTOM", panel, "BOTTOM", 0, 150)
            -- Columns + empowered area
            local leftCol = CreateFrame("Frame", "MSUF_CastbarMenuPanelLeft", panel); leftCol:EnableMouse(false)
            leftCol:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16); leftCol:SetPoint("RIGHT", vLine, "LEFT", -16, 0); leftCol:SetPoint("BOTTOM", hLine, "TOP", 0, 12)
            local rightCol = CreateFrame("Frame", "MSUF_CastbarMenuPanelRight", panel); rightCol:EnableMouse(false)
            rightCol:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -16); rightCol:SetPoint("LEFT", vLine, "RIGHT", 16, 0); rightCol:SetPoint("BOTTOM", hLine, "TOP", 0, 12)
            local emp = CreateFrame("Frame", "MSUF_CastbarMenuPanelEmpowered", panel); emp:EnableMouse(false)
            emp:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 12); emp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12); emp:SetPoint("TOP", hLine, "BOTTOM", 0, -12)
            -- Headers
            local behaviorHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); behaviorHeader:SetPoint("TOP", leftCol, "TOP", 0, 8); behaviorHeader:SetText(TR("Behavior"))
            local styleHeader    = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); styleHeader:SetPoint("TOP", rightCol, "TOP", 0, 8); styleHeader:SetText(TR("Style"))
            local empHeader      = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); empHeader:SetPoint("TOPLEFT", emp, "TOPLEFT", 0, 0); empHeader:SetText(TR("Empowered casts"))
        end
        local leftCol  = _G["MSUF_CastbarMenuPanelLeft"]
        local rightCol = _G["MSUF_CastbarMenuPanelRight"]
        local emp      = _G["MSUF_CastbarMenuPanelEmpowered"]
        -- Small UI helpers (Step 10): reduce anchor boilerplate, zero behavior change.
        local function H(x)  if x and x.Hide then x:Hide() end  end
        local function W(x, w)  if x and x.SetWidth then x:SetWidth(w) end  end
        local function T(x, s)  if x and x.SetText then x:SetText(s) end  end
        local function A(x, p, rel, rp, ox, oy)
            if not (x and rel and x.ClearAllPoints and x.SetPoint) then  return end
            x:ClearAllPoints()
            x:SetPoint(p, rel, rp, ox or 0, oy or 0)
         end
        -- Hide old section titles/lines (we use the new panel headers)
        H(castbarGeneralTitle); H(castbarGeneralLine); H(castbarTexColorTitle); H(castbarTexColorLine)
        -- Behavior (left)
        A(castbarInterruptShakeCheck, "TOPLEFT", leftCol, "TOPLEFT", 0, -20)
        A(castbarShakeIntensitySlider, "TOPLEFT", leftCol, "TOPLEFT", 0, -55); W(castbarShakeIntensitySlider, 260)
        A(castbarUnifiedDirCheck, "TOPLEFT", leftCol, "TOPLEFT", 0, -115)
        A(castbarFillDirLabel, "TOPLEFT", castbarUnifiedDirCheck, "BOTTOMLEFT", 0, -14)
        A(castbarFillDirDrop, "TOPLEFT", castbarFillDirLabel, "BOTTOMLEFT", -16, -4)
        -- keep alignment with dropdown padding (-16) by offsetting back +16
        A(castbarOpositeDirectionTarget, "TOPLEFT", castbarFillDirDrop, "BOTTOMLEFT", 16, -10)
        A(castbarChannelTicksCheck, "TOPLEFT", castbarOpositeDirectionTarget, "BOTTOMLEFT", 0, -10)
        A(castbarGCDBarCheck, "TOPLEFT", castbarChannelTicksCheck, "BOTTOMLEFT", 0, -8)
        -- Style (right)
        A(castbarTextureLabel, "TOPLEFT", rightCol, "TOPLEFT", 0, -20); T(castbarTextureLabel, "Castbar texture")
        A(castbarTextureDrop, "TOPLEFT", castbarTextureLabel, "BOTTOMLEFT", -16, -4)
        A(castbarTexturePreview, "TOPLEFT", castbarTextureDrop, "BOTTOMLEFT", 20, -6)
        A(castbarTextureInfo, "TOPLEFT", rightCol, "TOPLEFT", 0, -20); W(castbarTextureInfo, 320)
        -- Placeholders (disabled for now)
        if rightCol and not _G["MSUF_CastbarBackgroundTextureLabel"] then
local bgLabel = rightCol:CreateFontString("MSUF_CastbarBackgroundTextureLabel", "ARTWORK", "GameFontNormal")
bgLabel:SetText(TR("Castbar background texture"))
local bgDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_CastbarBackgroundTextureDropdown", castbarEnemyGroup) or CreateFrame("Frame", "MSUF_CastbarBackgroundTextureDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate"))
MSUF_ExpandDropdownClickArea(bgDrop)
UIDropDownMenu_SetWidth(bgDrop, 180)
bgDrop._msufButtonWidth = 180
bgDrop._msufTweakBarTexturePreview = true
if type(MSUF_MakeDropdownScrollable) == "function" then MSUF_MakeDropdownScrollable(bgDrop, 12) end
local function BgPreview_Update(key)
    local texPath
    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then texPath = _G.MSUF_ResolveStatusbarTextureKey(key) end
    if not texPath or texPath == "" then
        texPath = "Interface\\TargetingFrame\\UI-StatusBar"
    end
    local prev = _G.MSUF_CastbarBackgroundTexturePreview
    if not prev then
        prev = CreateFrame("StatusBar", "MSUF_CastbarBackgroundTexturePreview", castbarEnemyGroup)
        prev:SetMinMaxValues(0, 1)
        prev:SetValue(1)
        prev:SetSize(180, 10)
        _G.MSUF_CastbarBackgroundTexturePreview = prev
    end
    prev:SetParent(castbarEnemyGroup)
    prev:SetStatusBarTexture(texPath)
    prev:Hide()
    MSUF_KillMenuPreviewBar(prev)
     return prev
end
local function BgDrop_Init(self, level)
    EnsureDB()
    local info = UIDropDownMenu_CreateInfo()
    local g2 = (MSUF_DB and MSUF_DB.general) or {}
    local current = g2.castbarBackgroundTexture
    if type(current) ~= "string" or current == "" then current = g2.castbarTexture end
    if type(current) ~= "string" or current == "" then
        current = "Blizzard"
    end
    local function AddEntry(name, value)
        info.text = name
        info.value = value
        local swatchTex
        if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then swatchTex = _G.MSUF_ResolveStatusbarTextureKey(value) end
        if swatchTex then
            info.icon = swatchTex
            info.iconInfo = {
                tCoordLeft = 0, tCoordRight = 0.85,
                tCoordTop  = 0, tCoordBottom = 1,
                iconWidth  = 80,
                iconHeight = 12,
            }
        else
            info.icon = nil
            info.iconInfo = nil
        end
        info.func = function(btn)
            EnsureDB()
            MSUF_DB.general.castbarBackgroundTexture = btn.value
            UIDropDownMenu_SetSelectedValue(bgDrop, btn.value)
            UIDropDownMenu_SetText(bgDrop, btn.value)
            local fnTex = (_G and _G.MSUF_UpdateCastbarTextures_Immediate) or MSUF_UpdateCastbarTextures
            if type(fnTex) == "function" then fnTex() end
            if type(MSUF_UpdateCastbarVisuals) == "function" then
                MSUF_EnsureCastbars(); local fnVis = (_G and _G.MSUF_UpdateCastbarVisuals_Immediate) or MSUF_UpdateCastbarVisuals; if type(fnVis) == "function" then fnVis() end
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then pcall(_G.MSUF_UpdateBossCastbarPreview) end
            local prev = BgPreview_Update(btn.value)
            if prev then
                prev:ClearAllPoints()
                prev:SetPoint("TOPLEFT", bgDrop, "BOTTOMLEFT", 20, -6)
            end
         end
        info.checked = (value == current)
        info.notCheckable = false
        UIDropDownMenu_AddButton(info, level)
     end
    local LSM = MSUF_GetLSM()
    if LSM and type(LSM.List) == "function" then
        local list = LSM:List("statusbar") or {}
        table.sort(list, function(a, b)  return a:lower() < b:lower() end)
        for _, name in ipairs(list) do
            AddEntry(name, name)
        end
    else
        -- No SharedMedia: show built-in always-available textures
        local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES or {}
        local ordered = {
            "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills",
            "Outline", "TooltipBorder", "DialogBG", "Parchment",
        }
        local seen = {}
        for _, k in ipairs(ordered) do
            if builtins[k] then
                seen[k] = true
                AddEntry(k, k)
            end
        end
        for k in pairs(builtins) do
            if not seen[k] then AddEntry(k, k) end
        end
    end
 end
UIDropDownMenu_Initialize(bgDrop, BgDrop_Init)
EnsureDB()
local g3 = (MSUF_DB and MSUF_DB.general) or {}
local sel = g3.castbarBackgroundTexture
if type(sel) ~= "string" or sel == "" then sel = g3.castbarTexture end
if type(sel) ~= "string" or sel == "" then
    sel = "Blizzard"
end
g3.castbarBackgroundTexture = sel
UIDropDownMenu_SetSelectedValue(bgDrop, sel)
UIDropDownMenu_SetText(bgDrop, sel)
local prev = BgPreview_Update(sel)
if prev then
    prev:ClearAllPoints()
    prev:SetPoint("TOPLEFT", bgDrop, "BOTTOMLEFT", 20, -6)
end
            local outlineSlider = CreateLabeledSlider(
                "MSUF_CastbarOutlineThicknessSlider",
                "Outline thickness",
                castbarEnemyGroup,
                0, 6, 1,
                0, 0
            )
            outlineSlider:SetAlpha(1)
            local function _ApplyCastbarOutlineAndRefresh()
                if type(_G.MSUF_Options_Apply) == "function" then _G.MSUF_Options_Apply("castbarVisuals") end
                if type(_G.MSUF_ApplyCastbarOutlineToAll) == "function" then _G.MSUF_ApplyCastbarOutlineToAll(true) end
                if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then pcall(_G.MSUF_UpdateBossCastbarPreview) end
             end
            if _G and _G.MSUF_Options_BindGeneralNumberSlider then
                _G.MSUF_Options_BindGeneralNumberSlider(outlineSlider, "castbarOutlineThickness", { def = 1, min = 0, max = 6, int = true, apply = _ApplyCastbarOutlineAndRefresh })
            end
            -- Position placeholders under the texture dropdown (or under info text if LSM missing)
            bgLabel:ClearAllPoints()
            bgLabel:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -95)
            bgDrop:ClearAllPoints()
            bgDrop:SetPoint("TOPLEFT", bgLabel, "BOTTOMLEFT", -16, -4)
            outlineSlider:ClearAllPoints()
            outlineSlider:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -155)
            outlineSlider:SetWidth(260)
        end
        -- Glow effect belongs to Style (right column)
        do
            local outlineSlider = _G["MSUF_CastbarOutlineThicknessSlider"]
            if outlineSlider then
                A(castbarGlowCheck, "TOPLEFT", outlineSlider, "BOTTOMLEFT", 0, -18)
            else
                A(castbarGlowCheck, "TOPLEFT", rightCol, "TOPLEFT", 0, -210)
            end
        end
        -- Latency indicator belongs to Style (right column)
        do
            local outlineSlider = _G["MSUF_CastbarOutlineThicknessSlider"]
            if castbarGlowCheck then
                A(castbarLatencyCheck, "TOPLEFT", castbarGlowCheck, "BOTTOMLEFT", 0, -8)
            elseif outlineSlider then
                A(castbarLatencyCheck, "TOPLEFT", outlineSlider, "BOTTOMLEFT", 0, -18)
            else
                A(castbarLatencyCheck, "TOPLEFT", rightCol, "TOPLEFT", 0, -230)
            end
        end
                -- Spell name shortening (Style / right column)
        do
            local header = _G["MSUF_CastbarSpellNameShortenHeader"]
            if rightCol and not header then
                header = rightCol:CreateFontString("MSUF_CastbarSpellNameShortenHeader", "ARTWORK", "GameFontNormal")
                header:SetText(TR("Name shortening"))
            end
	            -- NOTE: This used to be an On/Off dropdown. We intentionally use a simple
	            -- On/Off button now (green when enabled, red when disabled).
	            -- When toggling from ON -> OFF we force a /reload (name shortening changes can
	            -- affect text clipping/layout and should be applied from a clean UI state).
	            local toggleBtn = _G["MSUF_CastbarSpellNameShortenToggle"]
	            if rightCol and not toggleBtn then
	                toggleBtn = CreateFrame("Button", "MSUF_CastbarSpellNameShortenToggle", castbarEnemyGroup, "UIPanelButtonTemplate")
	                toggleBtn:SetSize(120, 22)
	                toggleBtn:SetText(TR("Off"))
	                if MSUF_SkinMidnightActionButton then
	                    -- Remove default blue highlights and keep our flat style.
	                    MSUF_SkinMidnightActionButton(toggleBtn, { textR = 1, textG = 1, textB = 1 })
	                end
	                -- If an older build already created the dropdown, keep it hidden.
	                local oldDrop = _G["MSUF_CastbarSpellNameShortenDropdown"]
	                if oldDrop then
	                    oldDrop:Hide()
	                    oldDrop:SetAlpha(0)
	                    oldDrop:EnableMouse(false)
	                end
	            end
            local maxSlider = _G["MSUF_CastbarSpellNameMaxLenSlider"]
            if rightCol and not maxSlider then
                maxSlider = CreateLabeledSlider(
                    "MSUF_CastbarSpellNameMaxLenSlider",
                    "Max name length",
                    castbarEnemyGroup,
                    6, 30, 1,
                    0, 0
                )
            end
            local resSlider = _G["MSUF_CastbarSpellNameReservedSlider"]
            if rightCol and not resSlider then
                resSlider = CreateLabeledSlider(
                    "MSUF_CastbarSpellNameReservedSlider",
                    "Reserved space",
                    castbarEnemyGroup,
                    0, 30, 1,
                    0, 0
                )
            end
            local function FixSliderLabel(slider)
                if not slider or not slider.GetName then  return end
                local n = slider:GetName()
                local text = n and _G and _G[n .. "Text"]
                if text then
                    text:ClearAllPoints()
                    text:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, 18)
                    if text.SetJustifyH then text:SetJustifyH("LEFT") end
                end
             end
            -- Positioning under the latency toggle (fits the empty area in the Style column)
            if header and rightCol then
                header:ClearAllPoints()
                if castbarLatencyCheck then
                    header:SetPoint("TOPLEFT", castbarLatencyCheck, "BOTTOMLEFT", 0, -18)
                elseif castbarGlowCheck then
                    header:SetPoint("TOPLEFT", castbarGlowCheck, "BOTTOMLEFT", 0, -18)
                else
                    header:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -270)
                end
                header:Show()
            end
	            if toggleBtn and header then
	                toggleBtn:ClearAllPoints()
	                toggleBtn:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	                toggleBtn:Show()
	            end
	            if maxSlider and toggleBtn then
                maxSlider:ClearAllPoints()
	                maxSlider:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -30)
                maxSlider:SetWidth(260)
                FixSliderLabel(maxSlider)
                maxSlider:Show()
            end
            if resSlider and maxSlider then
                resSlider:ClearAllPoints()
                resSlider:SetPoint("TOPLEFT", maxSlider, "BOTTOMLEFT", 0, -48)
                resSlider:SetWidth(260)
                FixSliderLabel(resSlider)
                resSlider:Show()
            end
            local function ApplyVisualRefresh()
                MSUF_EnsureCastbars()
                if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
                if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                    _G.MSUF_UpdateBossCastbarPreview()
                end
             end
            local function SyncEnabledStates()
                EnsureDB()
                local g = (MSUF_DB and MSUF_DB.general) or {}
                local cur = tonumber(g.castbarSpellNameShortening) or 0
                local enabled = (cur > 0)
                if maxSlider then MSUF_SetLabeledSliderEnabled(maxSlider, enabled) end
                if resSlider then MSUF_SetLabeledSliderEnabled(resSlider, enabled) end
             end
	            -- Button init + DB apply (On/Off only; always shortens at END)
	            if toggleBtn then
	                local function SetRegionColor(self, rr, gg, bb, aa)
	                    if not self then  return end
	                    local name = self.GetName and self:GetName()
	                    local left  = self.Left  or (name and _G[name .. "Left"]) or nil
	                    local mid   = self.Middle or (name and _G[name .. "Middle"]) or nil
	                    local right = self.Right or (name and _G[name .. "Right"]) or nil
	                    if left  then left:SetTexture("Interface\\Buttons\\WHITE8x8"); left:SetVertexColor(rr, gg, bb, aa or 1) end
	                    if mid   then mid:SetTexture("Interface\\Buttons\\WHITE8x8"); mid:SetVertexColor(rr, gg, bb, aa or 1) end
	                    if right then right:SetTexture("Interface\\Buttons\\WHITE8x8"); right:SetVertexColor(rr, gg, bb, aa or 1) end
	                    local nt = self.GetNormalTexture and self:GetNormalTexture()
	                    if nt then
	                        nt:SetTexture("Interface\\Buttons\\WHITE8x8")
	                        nt:SetVertexColor(rr, gg, bb, aa or 1)
	                        nt:SetTexCoord(0, 1, 0, 1)
	                    end
	                 end
	                local function SyncToggleVisual()
	                    EnsureDB()
	                    local g = (MSUF_DB and MSUF_DB.general) or {}
	                    local cur = tonumber(g.castbarSpellNameShortening) or 0
	                    -- Migrate old enum values (1/2) to simple On (1)
	                    if cur > 0 then cur = 1 else cur = 0 end
	                    g.castbarSpellNameShortening = cur
	                    if cur == 1 then
	                        toggleBtn:SetText(TR("On"))
	                        -- green
	                        SetRegionColor(toggleBtn, 0.10, 0.45, 0.10, 0.95)
	                    else
	                        toggleBtn:SetText(TR("Off"))
	                        -- red
	                        SetRegionColor(toggleBtn, 0.55, 0.12, 0.12, 0.95)
	                    end
	                    SyncEnabledStates()
	                 end
	                -- Initial sync
	                SyncToggleVisual()
	                toggleBtn:SetScript("OnClick", function()
	                    EnsureDB()
	                    local g = (MSUF_DB and MSUF_DB.general) or {}
	                    local prev = tonumber(g.castbarSpellNameShortening) or 0
	                    if prev > 0 then prev = 1 else prev = 0 end
	                    local newV = (prev == 1) and 0 or 1
	                    g.castbarSpellNameShortening = newV
	                    -- ON -> OFF requires a hard reload
	                    if prev == 1 and newV == 0 then
	                        if ReloadUI then ReloadUI() end
	                         return
	                    end
	                    SyncToggleVisual()
	                    ApplyVisualRefresh()
	                 end)
	            end
            if _G and _G.MSUF_Options_BindGeneralNumberSlider then
                _G.MSUF_Options_BindGeneralNumberSlider(maxSlider, "castbarSpellNameMaxLen", { def = 30, min = 6, max = 30, int = true, apply = ApplyVisualRefresh })
                _G.MSUF_Options_BindGeneralNumberSlider(resSlider, "castbarSpellNameReservedSpace", { def = 8, min = 0, max = 30, int = true, apply = ApplyVisualRefresh })
            end
            -- When Off: sliders must be greyed out immediately
            SyncEnabledStates()
        end
-- Empowered (bottom)
        if empowerColorStagesCheck and emp then
            empowerColorStagesCheck:ClearAllPoints()
            empowerColorStagesCheck:SetPoint("TOPLEFT", emp, "TOPLEFT", 0, -22)
        end
        if empowerStageBlinkCheck and empowerColorStagesCheck then
            empowerStageBlinkCheck:ClearAllPoints()
            empowerStageBlinkCheck:SetPoint("TOPLEFT", empowerColorStagesCheck, "BOTTOMLEFT", 0, -10)
        end
        if empowerStageBlinkTimeSlider and emp then
            empowerStageBlinkTimeSlider:ClearAllPoints()
            empowerStageBlinkTimeSlider:SetPoint("TOPLEFT", emp, "TOPLEFT", 300, -24)
            empowerStageBlinkTimeSlider:SetWidth(260)
        end
    end
    -- -----------------------------------------------------------------
    -- Store castbar-specific widgets on panel for LoadFromDB
    -- -----------------------------------------------------------------
    panel.castbarShakeIntensitySlider = castbarShakeIntensitySlider
end -- ns.MSUF_Options_Castbar_Build

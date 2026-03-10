-- ---------------------------------------------------------------------------
-- MSUF_Options_Fonts.lua  (Phase 5: Rewrite using ns.UI.*)
--
-- Font settings: global font, text sizes, style, colors, name shortening.
-- Boxed two-column layout preserved.
-- ---------------------------------------------------------------------------
local addonName, ns = ...
local TR = ns.TR
local UI = ns.UI
local EnsureDB = ns.EnsureDB
local floor = math.floor

function ns.MSUF_Options_Fonts_Build(panel, fontGroup)
    if not panel or not fontGroup then return end
    if fontGroup._msufBuilt then return end
    fontGroup._msufBuilt = true

    -- Search registration
    if _G.MSUF_Search_RegisterRoots then
        _G.MSUF_Search_RegisterRoots({ "fonts" }, { "MSUF_FontsMenuPanelLeft", "MSUF_FontsMenuPanelRight" }, "Fonts")
    end

    local function G() EnsureDB(); return MSUF_DB.general end
    local function UpdateFonts()
        local fn = _G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts or _G.UpdateAllFonts or (ns and ns.MSUF_UpdateAllFonts)
        if type(fn) == "function" then fn() end
    end
    local function RequestLayoutAll(reason)
        local fn = ns.MSUF_Options_RequestLayoutAll or _G.MSUF_Options_RequestLayoutAll
        if type(fn) == "function" then fn(reason); return end
        if type(_G.ApplyAllSettings) == "function" then pcall(_G.ApplyAllSettings) end
    end
    local function EnsureCastbars()
        if type(_G.MSUF_EnsureAddonLoaded) == "function" then pcall(_G.MSUF_EnsureAddonLoaded, "MidnightSimpleUnitFrames_Castbars")
        elseif _G.C_AddOns and type(_G.C_AddOns.LoadAddOn) == "function" then pcall(_G.C_AddOns.LoadAddOn, "MidnightSimpleUnitFrames_Castbars") end
    end

    local TEX_W8 = "Interface\\Buttons\\WHITE8x8"

    ---------------------------------------------------------------------------
    -- Boxed layout
    ---------------------------------------------------------------------------
    local function MakeBox(name, titleText)
        local box = CreateFrame("Frame", name, fontGroup, "BackdropTemplate")
        if box.SetBackdrop then
            box:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, tile = true, tileSize = 16, edgeSize = 2, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            box:SetBackdropColor(0, 0, 0, 0.35); box:SetBackdropBorderColor(1, 1, 1, 0.25)
        end
        box:SetFrameLevel(fontGroup:GetFrameLevel() + 1)
        box._title = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        box._title:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -12); box._title:SetText(titleText)
        box._line = box:CreateTexture(nil, "ARTWORK")
        box._line:SetColorTexture(1, 1, 1, 0.18); box._line:SetHeight(1)
        box._line:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -34); box._line:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -34)
        return box
    end

    local left  = MakeBox("MSUF_FontsMenuPanelLeft", "Font Settings")
    left:SetSize(320, 560); left:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 0, -110)
    local right = MakeBox("MSUF_FontsMenuPanelRight", "Font color & style")
    right:SetSize(320, 560); right:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, 0)

    ---------------------------------------------------------------------------
    -- LEFT: Global font dropdown
    ---------------------------------------------------------------------------
    local secGlobal = UI.Label({ parent = left, text = TR("Global font"), font = "GameFontNormal", anchor = left, anchorPoint = "TOPLEFT", x = 14, y = -44 })

    -- Build SharedMedia font choices
    local fontChoices = {}
    local function RebuildFontChoices()
        fontChoices = {}
        for _, info in ipairs(_G.MSUF_FONT_LIST or _G.FONT_LIST or {}) do
            fontChoices[#fontChoices + 1] = { key = info.key, label = info.name, path = info.path }
        end
        local LSM = (ns and ns.LSM) or _G.MSUF_LSM
        if LSM then
            if LSM.Register then
                for _, d in ipairs(fontChoices) do
                    if d.key and d.key ~= "" and d.path and d.path ~= "" then
                        if LSM.Fetch then
                            local ok, v = pcall(LSM.Fetch, LSM, "font", d.key, true)
                            if not (ok and v) then pcall(LSM.Register, LSM, "font", d.key, d.path) end
                        end
                    end
                end
            end
            local used = {}; for _, e in ipairs(fontChoices) do used[e.key] = true end
            local names = LSM:List("font"); table.sort(names)
            for _, name in ipairs(names) do
                if not used[name] then fontChoices[#fontChoices + 1] = { key = name, label = name }; used[name] = true end
            end
        end
    end
    RebuildFontChoices()

    local fontDrop = UI.Dropdown({
        name = "MSUF_FontDropdown", parent = left,
        anchor = secGlobal, x = -16, y = -8, width = 260, maxVisible = 12,
        itemHeight = 22,
        items = function()
            if #fontChoices == 0 then RebuildFontChoices() end
            local getFP = _G.MSUF_GetFontPreviewObject
            local out = {}
            for i = 1, #fontChoices do
                local c = fontChoices[i]
                out[i] = {
                    key = c.key,
                    label = c.label,
                    fontObject = type(getFP) == "function" and getFP(c.key) or nil,
                }
            end
            return out
        end,
        get = function() return G().fontKey or "FRIZQT" end,
        set = function(v)
            G().fontKey = v; UpdateFonts()
            if C_Timer and C_Timer.After then C_Timer.After(0, UpdateFonts) end
        end,
    })

    ---------------------------------------------------------------------------
    -- LEFT: Text sizes (2x2 grid with editbox + ±)
    ---------------------------------------------------------------------------
    local secSizes = UI.Label({ parent = left, text = TR("Text sizes"), font = "GameFontNormal", anchor = fontDrop, x = 14, y = -18 })

    local sizeHelp = left:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sizeHelp:SetJustifyH("LEFT"); sizeHelp:SetWidth(290)
    sizeHelp:SetText("Global defaults. Frames inherit unless overridden in Unitframes > Text.")
    sizeHelp:SetPoint("TOPLEFT", secSizes, "BOTTOMLEFT", 0, -4)

    -- Size slider factory (110px, compact labels)
    local function MakeSizeSlider(name, label, dbKey, anchor, ox, oy, min, max, default)
        local sl = UI.Slider({
            name = name, parent = left,
            anchor = anchor, anchorPoint = "TOPLEFT", x = ox, y = oy,
            width = 110, min = min or 8, max = max or 32, step = 1, default = default or 14,
            get = function() return G()[dbKey] or default or 14 end,
            set = function(v)
                G()[dbKey] = floor(v + 0.5)
                UpdateFonts()
                if dbKey == "castbarSpellNameFontSize" then
                    EnsureCastbars()
                    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
                end
            end,
            formatText = function() return label end,
        })
        -- Compact: hide Low/High, resize editbox + buttons
        local n = sl:GetName()
        if n then
            local low = _G[n .. "Low"]; if low then low:Hide() end
            local high = _G[n .. "High"]; if high then high:Hide() end
            local text = _G[n .. "Text"]
            if text then text:ClearAllPoints(); text:SetPoint("BOTTOM", sl, "TOP", 0, 6); text:SetJustifyH("CENTER") end
        end
        if sl.editBox then sl.editBox:SetSize(44, 18) end
        if sl.minusButton then sl.minusButton:SetSize(18, 18) end
        if sl.plusButton then sl.plusButton:SetSize(18, 18) end
        return sl
    end

    local colGap = 30
    local firstRowYOffset = -42
    local secondRowYOffset = -118
    local nameSizeSlider    = MakeSizeSlider("MSUF_NameFontSizeSlider", "Name", "nameFontSize", sizeHelp, 0, firstRowYOffset, 8, 32, 14)
    local hpSizeSlider      = MakeSizeSlider("MSUF_HealthFontSizeSlider", "HP", "hpFontSize", sizeHelp, 110 + colGap, firstRowYOffset, 8, 32, 14)
    local powerSizeSlider   = MakeSizeSlider("MSUF_PowerFontSizeSlider", "Power", "powerFontSize", nameSizeSlider, 0, secondRowYOffset, 8, 32, 14)
    local castbarSizeSlider = MakeSizeSlider("MSUF_CastbarSpellNameFontSizeSlider", "Castbar", "castbarSpellNameFontSize", powerSizeSlider, 110 + colGap, 0, 0, 30, 0)
    -- Fix castbar position: same row as Power
    castbarSizeSlider:ClearAllPoints()
    castbarSizeSlider:SetPoint("TOPLEFT", powerSizeSlider, "TOPRIGHT", colGap, 0)

    -- Override info (per-unit overrides indicator)
    local function MakeOverrideInfo(parent, key)
        local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetWidth(120); fs:SetJustifyH("CENTER"); fs:SetText("")
        fs:EnableMouse(true)
        fs:SetScript("OnEnter", function(self)
            if self._fullList and self._fullList ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(TR("Overrides"), 1, 0.9, 0.4)
                GameTooltip:AddLine(self._fullList, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        fs:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return fs
    end

    local nameOvr  = MakeOverrideInfo(left, "nameOvr")
    local hpOvr    = MakeOverrideInfo(left, "hpOvr")
    local powerOvr = MakeOverrideInfo(left, "powerOvr")
    nameOvr:SetPoint("TOP", nameSizeSlider.editBox, "BOTTOM", 0, -2)
    hpOvr:SetPoint("TOP", hpSizeSlider.editBox, "BOTTOM", 0, -2)
    powerOvr:SetPoint("TOP", powerSizeSlider.editBox, "BOTTOM", 0, -2)

    local function UpdateOverrideInfo()
        EnsureDB()
        local keys = { "player", "target", "targettarget", "focus", "pet", "boss" }
        local pretty = { player = "Player", target = "Target", targettarget = "ToT", focus = "Focus", pet = "Pet", boss = "Boss" }
        local function List(field)
            local out = {}
            for _, k in ipairs(keys) do
                local c = MSUF_DB[k]
                if c and c[field] ~= nil then out[#out + 1] = pretty[k] or k end
            end
            return out
        end
        local function Fmt(list)
            if #list == 0 then return "Overrides: -", nil end
            if #list == 1 then return "Overrides: " .. list[1], list[1] end
            return "Overrides: " .. list[1] .. " +" .. (#list - 1), table.concat(list, ", ")
        end
        local s, f
        s, f = Fmt(List("nameFontSize"));  nameOvr:SetText(s);  nameOvr._fullList = f or ""
        s, f = Fmt(List("hpFontSize"));    hpOvr:SetText(s);    hpOvr._fullList = f or ""
        s, f = Fmt(List("powerFontSize")); powerOvr:SetText(s); powerOvr._fullList = f or ""
    end
    left:HookScript("OnShow", function() UpdateOverrideInfo() end)
    UpdateOverrideInfo()

    -- Reset overrides button
    if not StaticPopupDialogs["MSUF_RESET_FONT_OVERRIDES"] then
        StaticPopupDialogs["MSUF_RESET_FONT_OVERRIDES"] = {
            text = "Reset all font size overrides?\n\nThis clears per-unit overrides for Name/Health/Power AND per-castbar overrides for Cast Name/Time so everything inherits the global defaults.",
            button1 = YES, button2 = NO, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function()
                EnsureDB()
                for _, k in ipairs({ "player", "target", "targettarget", "focus", "pet", "boss" }) do
                    local c = MSUF_DB[k]
                    if c then c.nameFontSize = nil; c.hpFontSize = nil; c.powerFontSize = nil end
                end
                local gg = G()
                for _, u in ipairs({ "player", "target", "focus" }) do
                    local pfx = type(_G.MSUF_GetCastbarPrefix) == "function" and _G.MSUF_GetCastbarPrefix(u) or nil
                    if pfx then gg[pfx .. "SpellNameFontSize"] = nil; gg[pfx .. "TimeFontSize"] = nil end
                end
                gg.bossCastSpellNameFontSize = nil; gg.bossCastTimeFontSize = nil
                UpdateFonts(); EnsureCastbars()
                if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
                UpdateOverrideInfo()
            end,
        }
    end

    local resetBtn = UI.Button({
        name = "MSUF_ResetFontOverridesBtn", parent = left,
        text = TR("Reset overrides"), width = 280, height = 20,
        onClick = function() StaticPopup_Show("MSUF_RESET_FONT_OVERRIDES") end,
    })
    resetBtn:ClearAllPoints(); resetBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 14, 14)

    ---------------------------------------------------------------------------
    -- RIGHT: Text style
    ---------------------------------------------------------------------------
    local secStyle = UI.Label({ parent = right, text = TR("Text style"), font = "GameFontNormal", anchor = right, anchorPoint = "TOPLEFT", x = 14, y = -44 })

    local boldCheck = UI.Check({
        name = "MSUF_BoldTextCheck", parent = right,
        anchor = secStyle, x = -2, y = -8, maxTextWidth = 278,
        label = TR("Use bold text (THICKOUTLINE)"),
        get = function() return G().boldText and true or false end,
        set = function(v) G().boldText = v; UpdateFonts() end,
    })

    local noOutlineCheck = UI.Check({
        name = "MSUF_NoOutlineCheck", parent = right,
        anchor = boldCheck, x = 0, y = -10, maxTextWidth = 278,
        label = TR("Disable black outline around text"),
        get = function() return G().noOutline and true or false end,
        set = function(v) G().noOutline = v; UpdateFonts() end,
    })

    local textBackdropCheck = UI.Check({
        name = "MSUF_TextBackdropCheck", parent = right,
        anchor = noOutlineCheck, x = 0, y = -10, maxTextWidth = 278,
        label = TR("Add text shadow (backdrop)"),
        get = function() return G().textBackdrop and true or false end,
        set = function(v) G().textBackdrop = v; UpdateFonts() end,
    })

    ---------------------------------------------------------------------------
    -- RIGHT: Name colors
    ---------------------------------------------------------------------------
    local secColors = UI.Label({ parent = right, text = TR("Name colors"), font = "GameFontNormal", anchor = textBackdropCheck, x = 2, y = -18 })
    local colorsLine = right:CreateTexture(nil, "ARTWORK")
    colorsLine:SetColorTexture(1, 1, 1, 0.20); colorsLine:SetHeight(1)
    colorsLine:SetPoint("TOPLEFT", secColors, "BOTTOMLEFT", -16, -4); colorsLine:SetWidth(286)

    local nameClassColorCheck = UI.Check({
        name = "MSUF_NameClassColorCheck", parent = right,
        anchor = colorsLine, x = 14, y = -8, maxTextWidth = 278,
        label = TR("Color player names by class"),
        get = function() return G().nameClassColor and true or false end,
        set = function(v) G().nameClassColor = v; if _G.MSUF_RefreshAllIdentityColors then _G.MSUF_RefreshAllIdentityColors() end end,
    })

    local npcNameRedCheck = UI.Check({
        name = "MSUF_NPCNameRedCheck", parent = right,
        anchor = nameClassColorCheck, x = 0, y = -10, maxTextWidth = 278,
        label = TR("Color NPC/boss names using NPC colors"),
        get = function() return G().npcNameRed and true or false end,
        set = function(v) G().npcNameRed = v; if _G.MSUF_RefreshAllIdentityColors then _G.MSUF_RefreshAllIdentityColors() end end,
    })

    local powerColorCheck = UI.Check({
        name = "MSUF_PowerTextColorByTypeCheck", parent = right,
        anchor = npcNameRedCheck, x = 0, y = -10, maxTextWidth = 278,
        label = TR("Color power text by power type"),
        get = function() return G().colorPowerTextByType and true or false end,
        set = function(v) G().colorPowerTextByType = v; if _G.MSUF_RefreshAllPowerTextColors then _G.MSUF_RefreshAllPowerTextColors() end; UpdateFonts() end,
    })

    ---------------------------------------------------------------------------
    -- RIGHT: Name display / shortening
    ---------------------------------------------------------------------------
    local secNames = UI.Label({ parent = right, text = TR("Name display"), font = "GameFontNormal", anchor = powerColorCheck, x = 2, y = -18 })
    local namesLine = right:CreateTexture(nil, "ARTWORK")
    namesLine:SetColorTexture(1, 1, 1, 0.20); namesLine:SetHeight(1)
    namesLine:SetPoint("TOPLEFT", secNames, "BOTTOMLEFT", -16, -4); namesLine:SetWidth(286)

    -- Forward-declare for cross-widget enable/disable
    local shortenMaxSlider, shortenMaskSlider, shortenClipDrop

    local function SyncShortenEnabled()
        local on = MSUF_DB.shortenNames and true or false
        if shortenMaxSlider then shortenMaxSlider:SetAlpha(on and 1 or 0.45) end
        if shortenMaskSlider then shortenMaskSlider:SetAlpha(on and 1 or 0.45) end
        if shortenClipDrop then shortenClipDrop:SetEnabled(on) end
    end

    local shortenCheck = UI.Check({
        name = "MSUF_ShortenNamesCheck", parent = right,
        anchor = namesLine, x = 14, y = -8, maxTextWidth = 278,
        label = TR("Shorten unit names (except Player)"),
        get = function() EnsureDB(); return MSUF_DB.shortenNames and true or false end,
        set = function(v)
            EnsureDB(); MSUF_DB.shortenNames = v
            SyncShortenEnabled()
            RequestLayoutAll("SHORTEN_NAMES"); UpdateFonts()
            if ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
        end,
    })

    local shortenClipLabel = UI.Label({ parent = right, text = TR("Truncation style"), font = "GameFontNormal", anchor = shortenCheck, x = 16, y = -10 })

    shortenClipDrop = UI.Dropdown({
        name = "MSUF_ShortenNameClipSideDrop", parent = right,
        anchor = shortenClipLabel, x = -16, y = -2, width = 200,
        items = {
            { key = "LEFT",  label = "Keep end (show last letters)" },
            { key = "RIGHT", label = "Keep start (show first letters)" },
        },
        get = function() return G().shortenNameClipSide or "LEFT" end,
        set = function(v)
            G().shortenNameClipSide = v
            if MSUF_DB.shortenNames then UpdateFonts(); if ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end end
        end,
    })

    shortenMaxSlider = UI.Slider({
        name = "MSUF_ShortenNameMaxCharsSlider", parent = right, compact = true,
        anchor = shortenClipDrop, x = 16, y = -12, width = 180,
        label = TR("Max name length"), min = 6, max = 30, step = 1, default = 6,
        lowText = "6", highText = "30",
        get = function() return G().shortenNameMaxChars or 6 end,
        set = function(v)
            G().shortenNameMaxChars = floor(v + 0.5)
            if MSUF_DB.shortenNames then UpdateFonts(); if ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end end
        end,
    })

    shortenMaskSlider = UI.Slider({
        name = "MSUF_ShortenNameFrontMaskSlider", parent = right, compact = true,
        anchor = shortenMaxSlider, x = 0, y = -20, width = 180,
        label = TR("Reserved space"), min = 0, max = 40, step = 1, default = 8,
        lowText = "0", highText = "40",
        get = function() return G().shortenNameFrontMaskPx or 8 end,
        set = function(v)
            G().shortenNameFrontMaskPx = floor(v + 0.5)
            if MSUF_DB.shortenNames then UpdateFonts(); if ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end end
        end,
    })

    -- Info button
    local infoBtn = CreateFrame("Button", "MSUF_ShortenNameInfoButton", right)
    infoBtn:SetSize(16, 16)
    infoBtn:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
    infoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    infoBtn:SetPoint("TOPLEFT", shortenMaskSlider, "BOTTOMLEFT", 0, -6)
    infoBtn:SetScript("OnClick", function(self)
        if GameTooltip:IsOwned(self) and GameTooltip:IsShown() then GameTooltip:Hide(); return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TR("Name Shortening"))
        local side = G().shortenNameClipSide or "LEFT"
        if side == "RIGHT" then
            GameTooltip:AddLine("Keep start: shows the first letters (clips the end).", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Keep end: shows the last letters (clips the beginning).", 1, 1, 1, true)
            GameTooltip:AddLine("Reserved space protects the clipped edge (avoids overlaps).", 0.95, 0.95, 0.95, true)
        end
        GameTooltip:Show()
    end)

    -- Initial enable/disable state
    SyncShortenEnabled()

    ---------------------------------------------------------------------------
    -- Color list export (backward compat)
    ---------------------------------------------------------------------------
    local colorList = {
        { key="white",r=1,g=1,b=1,label="White" }, { key="black",r=0,g=0,b=0,label="Black" },
        { key="red",r=1,g=0,b=0,label="Red" }, { key="green",r=0,g=1,b=0,label="Green" },
        { key="blue",r=0,g=0,b=1,label="Blue" }, { key="yellow",r=1,g=1,b=0,label="Yellow" },
        { key="cyan",r=0,g=1,b=1,label="Cyan" }, { key="magenta",r=1,g=0,b=1,label="Magenta" },
        { key="orange",r=1,g=0.5,b=0,label="Orange" }, { key="purple",r=0.6,g=0,b=0.8,label="Purple" },
        { key="pink",r=1,g=0.6,b=0.8,label="Pink" }, { key="turquoise",r=0,g=0.9,b=0.8,label="Turquoise" },
        { key="grey",r=0.5,g=0.5,b=0.5,label="Grey" }, { key="brown",r=0.6,g=0.3,b=0.1,label="Brown" },
        { key="gold",r=1,g=0.85,b=0.1,label="Gold" },
    }
    panel.__MSUF_COLOR_LIST = colorList
    _G.MSUF_COLOR_LIST = colorList

    ---------------------------------------------------------------------------
    -- Panel stores (Core compat)
    ---------------------------------------------------------------------------
    panel.__MSUF_FontChoices = fontChoices
    panel.__MSUF_RebuildFontChoices = RebuildFontChoices
    panel.fontDrop = fontDrop
    panel.nameFontSizeSlider = nameSizeSlider
    panel.hpFontSizeSlider = hpSizeSlider
    panel.powerFontSizeSlider = powerSizeSlider
    panel.castbarSpellNameFontSizeSlider = castbarSizeSlider
    panel.boldCheck = boldCheck
    panel.noOutlineCheck = noOutlineCheck
    panel.textBackdropCheck = textBackdropCheck
    panel.nameClassColorCheck = nameClassColorCheck
    panel.npcNameRedCheck = npcNameRedCheck
    panel.powerTextColorByTypeCheck = powerColorCheck
    panel.shortenNamesCheck = shortenCheck
    panel.shortenNameClipSideDrop = shortenClipDrop
    panel.shortenNameMaxCharsSlider = shortenMaxSlider
    panel.shortenNameFrontMaskSlider = shortenMaskSlider
end

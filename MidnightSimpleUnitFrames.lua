local addonName, ns = ...

------------------------------------------------------
-- OPTIONAL: LibSharedMedia-3.0
------------------------------------------------------
local LSM = nil
if LibStub then
    LSM = LibStub("LibSharedMedia-3.0", true)
end

------------------------------------------------------
-- INTERNAL FONT LIST (Fallback)
------------------------------------------------------
local FONT_LIST = {
    {
        key  = "EXPRESSWAY",
        name = "Expressway (addon)",
        path = "Interface\\AddOns\\MidnightSimpleUnitFrames\\media\\Expressway.ttf",
    },
    {
        key  = "FRIZQT",
        name = "Friz Quadrata (default)",
        path = "Fonts\\FRIZQT__.TTF",
    },
    {
        key  = "ARIALN",
        name = "Arial (default)",
        path = "Fonts\\ARIALN.TTF",
    },
}
-- vordefinierte Font-Farben für das Dropdown
local MSUF_FONT_COLORS = {
    white     = {1.0, 1.0, 1.0},
    black     = {0.0, 0.0, 0.0},
    red       = {1.0, 0.0, 0.0},
    green     = {0.0, 1.0, 0.0},
    blue      = {0.0, 0.0, 1.0},
    yellow    = {1.0, 1.0, 0.0},
    cyan      = {0.0, 1.0, 1.0},
    magenta   = {1.0, 0.0, 1.0},
    orange    = {1.0, 0.5, 0.0},
    purple    = {0.6, 0.0, 0.8},
    pink      = {1.0, 0.6, 0.8},
    turquoise = {0.0, 0.9, 0.8},
    grey      = {0.5, 0.5, 0.5},
    brown     = {0.6, 0.3, 0.1},
    gold      = {1.0, 0.85, 0.1},
}

local function GetInternalFontPathByKey(key)
    if not key then return nil end
    for _, info in ipairs(FONT_LIST) do
        if info.key == key or info.name == key then
            return info.path
        end
    end
    return nil
end

------------------------------------------------------
-- SAVEDVARIABLES
------------------------------------------------------
local function EnsureDB()
    if not MSUF_DB then
        MSUF_DB = {}
    end

    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    if g.fontKey == nil then
        g.fontKey = "EXPRESSWAY"
    end
    if g.anchorName == nil then
        g.anchorName = "EssentialCooldownViewer"
    end
    if g.anchorToCooldown == nil then
        g.anchorToCooldown = true
    end
    if g.darkMode == nil then
        g.darkMode = true
    end
    if g.useClassColors == nil then
        g.useClassColors = false
    end
    if g.boldText == nil then
        g.boldText = false
    end
    if g.nameClassColor == nil then
        g.nameClassColor = true
    end
    if g.fontColor == nil then
    g.fontColor = "white"
    end


    local function fill(key, defaults)
        MSUF_DB[key] = MSUF_DB[key] or {}
        local t = MSUF_DB[key]
        for k, v in pairs(defaults) do
            if t[k] == nil then
                t[k] = v
            end
        end
    end

    local textDefaults = {
        nameOffsetX   = 4,
        nameOffsetY   = -4,
        hpOffsetX     = -4,
        hpOffsetY     = -4,
        powerOffsetX  = -4,
        powerOffsetY  = 4,
    }

    fill("player", {
        width     = 275,
        height    = 40,
        offsetX   = -275,
        offsetY   = -210,
        showName  = true,
        showHP    = true,
        showPower = true,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.player[k] == nil then MSUF_DB.player[k] = v end
    end

    fill("target", {
        width     = 275,
        height    = 40,
        offsetX   = 275,
        offsetY   = -210,
        showName  = true,
        showHP    = true,
        showPower = true,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.target[k] == nil then MSUF_DB.target[k] = v end
    end

    fill("focus", {
        width     = 220,
        height    = 30,
        offsetX   = 275,
        offsetY   = -160,
        showName  = true,
        showHP    = false,
        showPower = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.focus[k] == nil then MSUF_DB.focus[k] = v end
    end

    fill("boss", {
        width     = 220,
        height    = 30,
        offsetX   = 400,
        offsetY   = -100,
        spacing   = -36,
        showName  = true,
        showHP    = true,
        showPower = true,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.boss[k] == nil then MSUF_DB.boss[k] = v end
    end
end

------------------------------------------------------
-- FONT PATH + FLAGS
------------------------------------------------------
local function MSUF_GetFontPath()
    EnsureDB()
    local key = MSUF_DB.general.fontKey

    if LSM and key then
        local path = LSM:Fetch("font", key, true)
        if path then
            return path
        end
    end

    local internalPath = GetInternalFontPathByKey(key)
    if internalPath then
        return internalPath
    end

    return FONT_LIST[1].path
end

local function MSUF_GetFontFlags()
    EnsureDB()
    if MSUF_DB.general.boldText then
        return "THICKOUTLINE"
    else
        return "OUTLINE"
    end
end

------------------------------------------------------
-- PROFILE SERIALIZATION
------------------------------------------------------
local function MSUF_SerializeDB()
    EnsureDB()

    local function valToStr(v)
        local tv = type(v)
        if tv == "number" then
            return tostring(v)
        elseif tv == "boolean" then
            return v and "true" or "false"
        elseif tv == "string" then
            return string.format("%q", v)
        else
            return "nil"
        end
    end

    local function keyToStr(k)
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
            return k
        else
            return "[" .. string.format("%q", k) .. "]"
        end
    end

    local function serTable(t, indent)
        indent = indent or ""
        local indent2 = indent .. "  "
        local lines = {}
        table.insert(lines, "{\n")
        for k, v in pairs(t) do
            local kStr = keyToStr(k)
            if type(v) == "table" then
                table.insert(lines, indent2 .. kStr .. " = " .. serTable(v, indent2) .. ",\n")
            else
                table.insert(lines, indent2 .. kStr .. " = " .. valToStr(v) .. ",\n")
            end
        end
        table.insert(lines, indent .. "}")
        return table.concat(lines)
    end

    local body = serTable(MSUF_DB, "")
    return "return " .. body
end

local function MSUF_ImportFromString(str)
    if not str or not str:match("%S") then
        print("|cffff0000MSUF:|r Import failed (empty string).")
        return
    end

    local func, err = loadstring(str)
    if not func then
        func, err = loadstring("return " .. str)
    end
    if not func then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(err))
        return
    end

    local ok, tbl = pcall(func)
    if not ok then
        print("|cffff0000MSUF:|r Import failed: " .. tostring(tbl))
        return
    end
    if type(tbl) ~= "table" then
        print("|cffff0000MSUF:|r Import failed: not a table.")
        return
    end

    MSUF_DB = tbl
    EnsureDB()
    print("|cff00ff00MSUF:|r Profile imported.")
end

------------------------------------------------------
-- UNIT → CONFIG KEY
------------------------------------------------------
local function GetConfigKeyForUnit(unit)
    if unit == "player" or unit == "target" or unit == "focus" then
        return unit
    elseif unit and unit:match("^boss%d+$") then
        return "boss"
    end
    return nil
end

------------------------------------------------------
-- ANCHOR SELECTION
------------------------------------------------------
local function MSUF_GetAnchorFrame()
    EnsureDB()
    local g = MSUF_DB.general
    if g.anchorName then
        local f = _G[g.anchorName]
        if f then
            return f
        end
    end
    return UIParent
end

------------------------------------------------------
-- HIDE BLIZZARD UNITFRAMES
------------------------------------------------------
local function KillFrame(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:Hide()
    frame:SetScript("OnShow", frame.Hide)
end

local function HideDefaultFrames()
    KillFrame(PlayerFrame)
    KillFrame(TargetFrame)
    KillFrame(FocusFrame)
    KillFrame(TargetFrameToT)
end

------------------------------------------------------
-- GLOBAL UNITFRAMES TABLE
------------------------------------------------------
local UnitFrames = {}
-- Shorten name UTF-8 safe (wirklich!)
local function MSUF_ShortenName(name, maxChars)
    if not name then return "" end

    -- Wenn der Name kurz genug ist, nichts tun
    local len = strlenutf8(name)
    if len <= maxChars then
        return name
    end

    local byteLen   = #name
    local charCount = 0
    local cutPos    = byteLen

    local i = 1
    while i <= byteLen do
        charCount = charCount + 1

        -- Sobald wir über maxChars sind, merken wir uns die Cut-Position
        if charCount > maxChars then
            cutPos = i - 1
            break
        end

        local b = name:byte(i)
        if b <= 0x7F then          -- 1-Byte-Char (ASCII)
            i = i + 1
        elseif b >= 0xC0 and b <= 0xDF then   -- 2-Byte-UTF-8
            i = i + 2
        elseif b >= 0xE0 and b <= 0xEF then   -- 3-Byte-UTF-8
            i = i + 3
        elseif b >= 0xF0 and b <= 0xF7 then   -- 4-Byte-UTF-8
            i = i + 4
        else
            -- Fallback: falls irgendwas Komisches kommt, nur 1 Byte weiter
            i = i + 1
        end
    end

    local truncated = name:sub(1, cutPos)
    return truncated .. "…"
end


------------------------------------------------------
-- POSITIONING
------------------------------------------------------
local function PositionUnitFrame(f, unit)
    EnsureDB()
    local key = GetConfigKeyForUnit(unit)
    if not key then return end

    local conf = MSUF_DB[key]
    if not conf then return end

    local anchor = MSUF_GetAnchorFrame()
    f:ClearAllPoints()

    local ecv = _G["EssentialCooldownViewer"]

    if MSUF_DB.general.anchorToCooldown and ecv and anchor == ecv then
        local gapY = conf.offsetY or -20

        if key == "player" then
            f:SetPoint("RIGHT", ecv, "LEFT", -20 + (conf.offsetX or 0), gapY)
            return
        elseif key == "target" then
            f:SetPoint("LEFT", ecv, "RIGHT", 20 + (conf.offsetX or 0), gapY)
            return
        elseif key == "focus" then
            f:SetPoint("TOP", ecv, "BOTTOM", (conf.offsetX or 0), gapY)
            return
        end
    end

    if key == "boss" then
        local index = tonumber(unit:match("^boss(%d+)$")) or 1
        local x = conf.offsetX
        local spacing = conf.spacing or -36
        local y = conf.offsetY + (index - 1) * spacing
        f:SetPoint("CENTER", anchor, "CENTER", x, y)
    else
        f:SetPoint("CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
    end
end

------------------------------------------------------
-- APPLY TEXT LAYOUT
------------------------------------------------------
local function ApplyTextLayout(f, conf)
    if not f or not f.textFrame then return end
    local tf = f.textFrame

    local nX = conf.nameOffsetX   or 4
    local nY = conf.nameOffsetY   or -4
    local hX = conf.hpOffsetX     or -4
    local hY = conf.hpOffsetY     or -4
    local pX = conf.powerOffsetX  or -4
    local pY = conf.powerOffsetY  or 4

    if f.nameText then
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint("TOPLEFT", tf, "TOPLEFT", nX, nY)
    end

    if f.hpText then
        f.hpText:ClearAllPoints()
        f.hpText:SetPoint("TOPRIGHT", tf, "TOPRIGHT", hX, hY)
    end

    if f.powerText then
        f.powerText:ClearAllPoints()
        f.powerText:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", pX, pY)
    end
end

------------------------------------------------------
-- UPDATE LOGIC
------------------------------------------------------
local function UpdateSimpleUnitFrame(self)
    EnsureDB()

    local unit   = self.unit
    local exists = UnitExists(unit)

    --------------------------------------------------
    -- BOSS FRAMES
    --------------------------------------------------
    if self.isBoss then
        if not exists then
            if not InCombatLockdown() then
                self:Hide()
            end
            if self.hpBar then
                self.hpBar:SetMinMaxValues(0, 1)
                self.hpBar:SetValue(0)
            end
            if self.nameText  then self.nameText:SetText("")  end
            if self.hpText    then self.hpText:SetText("")    end
            if self.powerText then
                self.powerText:SetText("")
                self.powerText:Hide()
            end
            return
        else
            if not self:IsShown() and not InCombatLockdown() then
                self:Show()
            end
        end
    end

    --------------------------------------------------
    -- NO UNIT (Target/Focus)
    --------------------------------------------------
    if not exists then
        if unit ~= "player" and not InCombatLockdown() then
            self:Hide()
        end
        if self.hpBar then
            self.hpBar:SetMinMaxValues(0, 1)
            self.hpBar:SetValue(0)
        end
        if self.nameText  then self.nameText:SetText("")  end
        if self.hpText    then self.hpText:SetText("")    end
        if self.powerText then
            self.powerText:SetText("")
            self.powerText:Hide()
        end
        return
    else
        if not self:IsShown() and not InCombatLockdown() then
            self:Show()
        end
    end

    --------------------------------------------------
    -- HP BAR VALUE
    --------------------------------------------------
    local maxHP = UnitHealthMax(unit)
    if maxHP then
        self.hpBar:SetMinMaxValues(0, maxHP)
    end

    local hp = UnitHealth(unit)
    if hp then
        self.hpBar:SetValue(hp)
    end

    --------------------------------------------------
    -- BAR COLOR (Dark / Class Color)
    --------------------------------------------------
    local darkMode      = MSUF_DB.general.darkMode
    local useClassColor = MSUF_DB.general.useClassColors

    local barR, barG, barB

    if useClassColor and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then
            barR, barG, barB = color.r, color.g, color.b
        else
            if darkMode then
                barR, barG, barB = 0, 0, 0
            else
                barR, barG, barB = 0, 1, 0
            end
        end
    else
        if darkMode then
            barR, barG, barB = 0, 0, 0
        else
            barR, barG, barB = 0, 1, 0
        end
    end

    self.hpBar:SetStatusBarColor(barR, barG, barB, 1)

    if self.bg then
        if darkMode then
            self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
        else
            self.bg:SetColorTexture(0.4, 0.4, 0.4, 0.9)
        end
    end

    --------------------------------------------------
      --------------------------------------------------
    -- NAME (nur Text, Farbe kommt global)
    --------------------------------------------------
    local name = UnitName(unit)
    if self.showName ~= false and name then
        self.nameText:SetText(name)
    else
        self.nameText:SetText("")
    end
    -- WICHTIG: keine Farbe hier setzen!
    -- Die Namensfarbe kommt zentral aus UpdateAllFonts()



    --------------------------------------------------
    -- HP TEXT (abgekürzt)
    --------------------------------------------------
    if self.showHPText ~= false and hp then
        local hpStr = AbbreviateLargeNumbers(hp)
        self.hpText:SetText(hpStr or "")
    else
        self.hpText:SetText("")
    end

    --------------------------------------------------
    -- POWER TEXT (Player/Focus/Boss/Spieler-Targets)
    --------------------------------------------------
    local showPower = self.showPowerText
    if showPower == nil then
        showPower = true
    end

    if showPower then
        if unit == "player" or unit == "focus" or self.isBoss or UnitIsPlayer(unit) then
            local p    = UnitPower(unit) or 0
            local pMax = UnitPowerMax(unit) or 0
            self.powerText:SetFormattedText("%d / %d", p, pMax)
            self.powerText:Show()
        else
            self.powerText:SetText("")
            self.powerText:Hide()
        end
    else
        self.powerText:SetText("")
        self.powerText:Hide()
    end
end

------------------------------------------------------
-- APPLY SETTINGS TO FRAMES
------------------------------------------------------
local function ApplySettingsForKey(key)
    EnsureDB()
    local conf = MSUF_DB[key]
    if not conf then return end

    local function applyToFrame(unit)
        local f = UnitFrames[unit]
        if not f then return end

        f:SetSize(conf.width, conf.height)
        f.showName      = conf.showName
        f.showHPText    = conf.showHP
        f.showPowerText = conf.showPower

        PositionUnitFrame(f, unit)
        ApplyTextLayout(f, conf)
        UpdateSimpleUnitFrame(f)
    end

    if key == "player" or key == "target" or key == "focus" then
        applyToFrame(key)
    elseif key == "boss" then
        for i = 1, 5 do
            applyToFrame("boss" .. i)
        end
    end
end

local function ApplyAllSettings()
    ApplySettingsForKey("player")
    ApplySettingsForKey("target")
    ApplySettingsForKey("focus")
    ApplySettingsForKey("boss")
end

------------------------------------------------------
-- UPDATE ALL FONTS (z.B. bei Fontwechsel/Bold)
------------------------------------------------------
local function UpdateAllFonts()
    local path  = MSUF_GetFontPath()
    local flags = MSUF_GetFontFlags()

    EnsureDB()
    local g = MSUF_DB.general

    -- globale Font-Farbe aus dem Dropdown
    local key   = (g.fontColor or "white"):lower()
    local color = MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white
    local fr, fg, fb = color[1], color[2], color[3]

    for _, f in pairs(UnitFrames) do
        --------------------------------------------------
        -- NAME: Font immer, Farbe je nach Option
        --------------------------------------------------
        if f.nameText then
            f.nameText:SetFont(path, 14, flags)

            local nr, ng, nb = fr, fg, fb
            if g.nameClassColor and f.unit and UnitIsPlayer(f.unit) then
                -- Klassenfarbe für Spieler-Namen
                local _, class = UnitClass(f.unit)
                local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                if c then
                    nr, ng, nb = c.r, c.g, c.b
                end
            end
            f.nameText:SetTextColor(nr, ng, nb, 1)
        end

        --------------------------------------------------
        -- HP-TEXT: immer FontColor
        --------------------------------------------------
        if f.hpText then
            f.hpText:SetFont(path, 14, flags)
            f.hpText:SetTextColor(fr, fg, fb, 1)
        end

        --------------------------------------------------
        -- RESOURCE-TEXT: immer FontColor
        --------------------------------------------------
        if f.powerText then
            f.powerText:SetFont(path, 14, flags)
            f.powerText:SetTextColor(fr, fg, fb, 1)
        end
    end
end

------------------------------------------------------
-- CREATE UNITFRAME
------------------------------------------------------
local function CreateSimpleUnitFrame(unit)
    EnsureDB()

    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key] or {}

    local f = CreateFrame("Button", "MSUF_" .. unit, UIParent, "SecureUnitButtonTemplate")
    f.unit = unit

    if unit == "player" or unit == "target" then
        local w = conf.width  or 275
        local h = conf.height or 40
        f:SetSize(w, h)
        f.showName      = conf.showName  ~= false
        f.showHPText    = conf.showHP    ~= false
        f.showPowerText = conf.showPower ~= false
        f.isBoss        = false

    elseif unit == "focus" then
        local w = conf.width  or 220
        local h = conf.height or 30
        f:SetSize(w, h)
        f.showName      = conf.showName  ~= false
        f.showHPText    = conf.showHP    or false
        f.showPowerText = conf.showPower or false
        f.isBoss        = false

    elseif unit:match("^boss%d+$") then
        local w = conf.width  or 220
        local h = conf.height or 30
        f:SetSize(w, h)
        f.showName      = conf.showName  ~= false
        f.showHPText    = conf.showHP    ~= false
        f.showPowerText = conf.showPower ~= false
        f.isBoss        = true
        f:Hide()
    end

    PositionUnitFrame(f, unit)

    f:RegisterForClicks("AnyUp")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    f.bg = bg

    local hpBar = CreateFrame("StatusBar", nil, f)
    hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    hpBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    hpBar:SetMinMaxValues(0, 1)
    hpBar:SetValue(0)
    hpBar:SetFrameLevel(f:GetFrameLevel() + 1)
    f.hpBar = hpBar

    -- Gradient-Overlay für HP-Bar (kompatibel mit allen Clients)
    local hpGradient = hpBar:CreateTexture(nil, "ARTWORK")
    hpGradient:SetAllPoints(hpBar)
    hpGradient:SetTexture("Interface\\Buttons\\WHITE8x8")

    -- Sichere Gradient-API für alle Versionen
    if hpGradient.SetGradientAlpha then
        -- ältere API (z.B. 9.x Classic)
        hpGradient:SetGradientAlpha("HORIZONTAL",
            0, 0, 0, 0,      -- links: komplett unsichtbar
            0, 0, 0, 0.45    -- rechts: leicht abgedunkelt
        )
    elseif hpGradient.SetGradient then
        -- moderne API (Retail 10.0+ / 12.0+)
        hpGradient:SetGradient("HORIZONTAL",
            CreateColor(0, 0, 0, 0),       -- links transparent
            CreateColor(0, 0, 0, 0.45)     -- rechts Schatten
        )
    else
        -- letzter Fallback (sollte nie passieren)
        hpGradient:SetColorTexture(0, 0, 0, 0.45)
    end

    hpGradient:SetBlendMode("BLEND")
    f.hpGradient = hpGradient

    local textFrame = CreateFrame("Frame", nil, f)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    f.textFrame = textFrame

    local fontPath = MSUF_GetFontPath()
    local flags    = MSUF_GetFontFlags()

    local nameText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetFont(fontPath, 14, flags)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1, 1)
    f.nameText = nameText

    local hpText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hpText:SetFont(fontPath, 14, flags)
    hpText:SetJustifyH("RIGHT")
    hpText:SetTextColor(1, 1, 1, 0.9)
    f.hpText = hpText

    local powerText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    powerText:SetFont(fontPath, 14, flags)
    powerText:SetJustifyH("RIGHT")
    powerText:SetTextColor(1, 1, 1, 0.9)
    f.powerText = powerText

    ApplyTextLayout(f, conf)

    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UNIT_NAME_UPDATE")
    f:RegisterEvent("UNIT_POWER_UPDATE")
    f:RegisterEvent("UNIT_MAXPOWER")
    f:RegisterEvent("UNIT_HEALTH")
    f:RegisterEvent("UNIT_MAXHEALTH")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_FOCUS_CHANGED")
    f:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")

    f:SetScript("OnEvent", function(self, event, arg1)
        UpdateSimpleUnitFrame(self)
    end)

    UpdateSimpleUnitFrame(f)
    UnitFrames[unit] = f
end

------------------------------------------------------
-- OPTIONS PANEL
------------------------------------------------------
local function CreateOptionsPanel()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    EnsureDB()

    local panel = CreateFrame("Frame")
    panel.name = "Midnight Simple Unit Frames"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("Midnight Simple Unit Frames")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetText("Configure position, size, visibility, font and text offsets for each frame type.")

    --------------------------------------------------
    -- GROUP FRAMES: frame settings vs font settings
    --------------------------------------------------
    local frameGroup = CreateFrame("Frame", nil, panel)
    frameGroup:SetAllPoints()

    local fontGroup = CreateFrame("Frame", nil, panel)
    fontGroup:SetAllPoints()

    --------------------------------------------------
    -- FRAME TYPE BUTTONS (incl. Fonts-Tab)
    --------------------------------------------------
    local currentKey = "player"
    local buttons = {}

    local function GetLabelForKey(key)
        if key == "player" then return "Player"
        elseif key == "target" then return "Target"
        elseif key == "focus" then return "Focus"
        elseif key == "boss" then return "Boss Frames"
        elseif key == "fonts" then return "Fonts"
        end
        return key
    end

    local function UpdateGroupVisibility()
        if currentKey == "fonts" then
            frameGroup:Hide()
            fontGroup:Show()
        else
            frameGroup:Show()
            fontGroup:Hide()
        end
    end

    local function SetCurrentKey(newKey)
        currentKey = newKey
        for k, b in pairs(buttons) do
            b:Enable()
        end
        if buttons[newKey] then
            buttons[newKey]:Disable()
        end
        UpdateGroupVisibility()
    end

    local function CreateUnitButton(key, xOffset)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(90, 22)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + xOffset, -50)
        b:SetText(GetLabelForKey(key))
        b:SetScript("OnClick", function()
            SetCurrentKey(key)
            panel:LoadFromDB()
        end)
        buttons[key] = b
    end

    CreateUnitButton("player", 0)
    CreateUnitButton("target", 100)
    CreateUnitButton("focus", 200)
    CreateUnitButton("boss", 300)
    CreateUnitButton("fonts", 400)

    --------------------------------------------------
    -- HELPERS: SLIDER + EDITBOX + +/- Buttons
    --------------------------------------------------
    local function CreateLabeledSlider(name, label, parent, minVal, maxVal, step, x, y)
        local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)

        slider.minVal = minVal
        slider.maxVal = maxVal
        slider.step   = step

        _G[name .. "Low"]:SetText(tostring(minVal))
        _G[name .. "High"]:SetText(tostring(maxVal))
        _G[name .. "Text"]:SetText(label)

        local eb = CreateFrame("EditBox", name .. "Input", parent, "InputBoxTemplate")
        eb:SetSize(60, 18)
        eb:SetAutoFocus(false)
        eb:SetPoint("TOP", slider, "BOTTOM", 0, -2)
        eb:SetJustifyH("CENTER")
        slider.editBox = eb

        local function ApplyEditBoxValue()
            local text = eb:GetText()
            local val = tonumber(text)
            if val then
                if val < slider.minVal then val = slider.minVal end
                if val > slider.maxVal then val = slider.maxVal end
                slider:SetValue(val)
            else
                eb:SetText(tostring(math.floor(slider:GetValue() + 0.5)))
            end
        end

        eb:SetScript("OnEnterPressed", function(self)
            ApplyEditBoxValue()
            self:ClearFocus()
        end)
        eb:SetScript("OnEditFocusLost", function(self)
            ApplyEditBoxValue()
        end)

        local minus = CreateFrame("Button", name .. "Minus", parent, "UIPanelButtonTemplate")
        minus:SetSize(20, 18)
        minus:SetText("-")
        minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
        slider.minusButton = minus

        minus:SetScript("OnClick", function()
            local cur = slider:GetValue()
            local st  = slider.step or 1
            local nv  = cur - st
            if nv < slider.minVal then nv = slider.minVal end
            slider:SetValue(nv)
        end)

        local plus = CreateFrame("Button", name .. "Plus", parent, "UIPanelButtonTemplate")
        plus:SetSize(20, 18)
        plus:SetText("+")
        plus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
        slider.plusButton = plus

        plus:SetScript("OnClick", function()
            local cur = slider:GetValue()
            local st  = slider.step or 1
            local nv  = cur + st
            if nv > slider.maxVal then nv = slider.maxVal end
            slider:SetValue(nv)
        end)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            if self.editBox then
                local txt = self.editBox:GetText()
                local num = tonumber(txt)
                if num ~= value then
                    self.editBox:SetText(tostring(value))
                end
            end
            if self.onValueChanged then
                self.onValueChanged(self, value)
            end
        end)

        return slider
    end

    local function CreateLabeledCheckButton(name, label, parent, x, y)
        local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        cb.text = _G[name .. "Text"]
        cb.text:SetText(label)
        return cb
    end

    --------------------------------------------------
    -- FRAME GROUP: WIDTH/HEIGHT/OFFSETS + VISIBILITY
    --------------------------------------------------
    local widthSlider = CreateLabeledSlider(
        "MSUF_WidthSlider", "Width", frameGroup,
        150, 500, 5,
        16, -90
    )

    local heightSlider = CreateLabeledSlider(
        "MSUF_HeightSlider", "Height", frameGroup,
        20, 80, 1,
        16, -140
    )

    local xSlider = CreateLabeledSlider(
        "MSUF_OffsetXSlider", "Offset X", frameGroup,
        -600, 600, 5,
        16, -190
    )

    local ySlider = CreateLabeledSlider(
        "MSUF_OffsetYSlider", "Offset Y", frameGroup,
        -400, 400, 5,
        16, -240
    )

    local showNameCB = CreateLabeledCheckButton(
        "MSUF_ShowNameCheck", "Show name", frameGroup,
        16, -290
    )

    local showHPCB = CreateLabeledCheckButton(
        "MSUF_ShowHPCheck", "Show HP text", frameGroup,
        16, -320
    )

    local showPowerCB = CreateLabeledCheckButton(
        "MSUF_ShowPowerCheck", "Show resource (mana/energy/rage...)", frameGroup,
        16, -350
    )

    -- Anchor settings (global, aber im Frame-Tab sichtbar)
    local anchorLabel = frameGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    anchorLabel:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", 300, -390)
    anchorLabel:SetText("Anchor frame (global name)")

    local anchorEdit = CreateFrame("EditBox", "MSUF_AnchorEditBox", frameGroup, "InputBoxTemplate")
    anchorEdit:SetSize(180, 20)
    anchorEdit:SetAutoFocus(false)
    anchorEdit:SetPoint("TOPLEFT", anchorLabel, "BOTTOMLEFT", 0, -2)
    anchorLabel:Hide()
    anchorEdit:Hide()
anchorEdit:EnableMouse(false)


    local function ApplyAnchorEditBox()
        EnsureDB()
        local txt = anchorEdit:GetText() or ""
        if txt == "" then
            txt = "UIParent"
        end
        MSUF_DB.general.anchorName = txt
        ApplyAllSettings()
    end

    anchorEdit:SetScript("OnEnterPressed", function(self)
        ApplyAnchorEditBox()
        self:ClearFocus()
    end)
    anchorEdit:SetScript("OnEditFocusLost", function(self)
        ApplyAnchorEditBox()
    end)

    local anchorCheck = CreateFrame("CheckButton", "MSUF_AnchorToCooldownCheck", frameGroup, "UICheckButtonTemplate")
    anchorCheck:SetPoint("TOPLEFT", anchorEdit, "BOTTOMLEFT", 0, -4)
    anchorCheck.text = _G["MSUF_AnchorToCooldownCheckText"]
    anchorCheck.text:SetText("Anchor player/target/focus to Cooldown Manager")

    --------------------------------------------------
    -- TEXT OFFSETS (Frame group)
    --------------------------------------------------
    local nameOffsetXSlider = CreateLabeledSlider(
        "MSUF_NameOffsetXSlider", "Name offset X", frameGroup,
        -100, 100, 1,
        300, -110
    )

    local nameOffsetYSlider = CreateLabeledSlider(
        "MSUF_NameOffsetYSlider", "Name offset Y", frameGroup,
        -100, 100, 1,
        300, -160
    )

    local hpOffsetXSlider = CreateLabeledSlider(
        "MSUF_HPOffsetXSlider", "HP text offset X", frameGroup,
        -100, 100, 1,
        300, -210
    )

    local hpOffsetYSlider = CreateLabeledSlider(
        "MSUF_HPOffsetYSlider", "HP text offset Y", frameGroup,
        -100, 100, 1,
        300, -260
    )

    local powerOffsetXSlider = CreateLabeledSlider(
        "MSUF_PowerOffsetXSlider", "Resource offset X", frameGroup,
        -100, 100, 1,
        300, -310
    )

    local powerOffsetYSlider = CreateLabeledSlider(
        "MSUF_PowerOffsetYSlider", "Resource offset Y", frameGroup,
        -100, 100, 1,
        300, -360
    )

    --------------------------------------------------
    -- PROFILE EXPORT / IMPORT (Frame group)
    --------------------------------------------------
    local profileLabel = frameGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    profileLabel:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", 16, -390)
    profileLabel:SetText("Profile export / import")

    local scroll = CreateFrame("ScrollFrame", "MSUF_ProfileScroll", frameGroup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", 16, -410)
    scroll:SetSize(540, 90)

    local editBox = CreateFrame("EditBox", "MSUF_ProfileEditBox", scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(520)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(editBox)

    local exportBtn = CreateFrame("Button", nil, frameGroup, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 22)
    exportBtn:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -5)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local str = MSUF_SerializeDB()
        editBox:SetText(str)
        editBox:HighlightText()
        print("|cff00ff00MSUF:|r Profile exported to text box.")
    end)

    local importBtn = CreateFrame("Button", nil, frameGroup, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local str = editBox:GetText()
        MSUF_ImportFromString(str)
        ApplyAllSettings()
        UpdateAllFonts()
        panel:LoadFromDB()
    end)

    --------------------------------------------------
    -- FONT GROUP: Font-Dropdown & globale Font-Optionen
    --------------------------------------------------
    local fontTitle = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fontTitle:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 16, -100)
    fontTitle:SetText("Font & Color settings")

    local fontLabel = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", fontTitle, "BOTTOMLEFT", 0, -20)
    fontLabel:SetText("Font")

        --------------------------------------------------
    -- FONT DROPDOWN
    --------------------------------------------------
    local fontDrop = CreateFrame("Frame", "MSUF_FontDropdown", fontGroup, "UIDropDownMenuTemplate")
    fontDrop:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -4)

    -- Liste der verfügbaren Fonts (interne + LSM)
    local fontChoices = {}

    local function MSUF_RebuildFontChoices()
        fontChoices = {}

        -- 1) interne Fallback-Fonts aus FONT_LIST
        for _, info in ipairs(FONT_LIST) do
            table.insert(fontChoices, {
                key   = info.key,   -- z.B. "EXPRESSWAY"
                label = info.name,  -- z.B. "Expressway (addon)"
            })
        end

        -- 2) LibSharedMedia-Fonts anhängen, falls vorhanden
        if LSM then
            local names = LSM:List("font")
            table.sort(names)

            local used = {}
            for _, e in ipairs(fontChoices) do
                used[e.key] = true   -- nach KEY deduplizieren
            end

            for _, name in ipairs(names) do
                if not used[name] then
                    table.insert(fontChoices, {
                        key   = name,  -- Key, den LSM:Fetch erwartet
                        label = name,  -- so steht es im Dropdown
                    })
                    used[name] = true
                end
            end
        end
    end

    -- einmal initial aufbauen
    MSUF_RebuildFontChoices()

    local function FontDropdown_Initialize(self, level)
        EnsureDB()

        -- falls LSM Fonts nachträglich registriert wurden
        if not fontChoices or #fontChoices == 0 then
            MSUF_RebuildFontChoices()
        end

        local info       = UIDropDownMenu_CreateInfo()
        local currentKey = MSUF_DB.general.fontKey

        for _, data in ipairs(fontChoices) do
            info.text  = data.label
            info.arg1  = data.key
            info.value = data.key          -- wichtig für SetSelectedValue
            info.func  = function(_, key)
                EnsureDB()
                MSUF_DB.general.fontKey = key
                UIDropDownMenu_SetSelectedValue(fontDrop, key)
                UpdateAllFonts()
            end
            info.checked = (currentKey == data.key)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(fontDrop, FontDropdown_Initialize)
    UIDropDownMenu_SetWidth(fontDrop, 180)
    --------------------------------------------------
-- FONT COLOR DROPDOWN
--------------------------------------------------
local fontColorLabel = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
fontColorLabel:SetPoint("TOPLEFT", fontDrop, "BOTTOMLEFT", 250, 47)
fontColorLabel:SetText("Font color")

local fontColorDrop = CreateFrame("Frame", "MSUF_FontColorDropdown", fontGroup, "UIDropDownMenuTemplate")
fontColorDrop:SetPoint("TOPLEFT", fontColorLabel, "BOTTOMLEFT", -16, -4)

-- 15 NICE COLORS
local MSUF_COLOR_LIST = {
    { key = "white",     r=1,   g=1,   b=1,   label="White" },
    { key = "black",     r=0,   g=0,   b=0,   label="Black" },
    { key = "red",       r=1,   g=0,   b=0,   label="Red" },
    { key = "green",     r=0,   g=1,   b=0,   label="Green" },
    { key = "blue",      r=0,   g=0,   b=1,   label="Blue" },
    { key = "yellow",    r=1,   g=1,   b=0,   label="Yellow" },
    { key = "cyan",      r=0,   g=1,   b=1,   label="Cyan" },
    { key = "magenta",   r=1,   g=0,   b=1,   label="Magenta" },
    { key = "orange",    r=1,   g=0.5, b=0,   label="Orange" },
    { key = "purple",    r=0.6, g=0,   b=0.8, label="Purple" },
    { key = "pink",      r=1,   g=0.6, b=0.8, label="Pink" },
    { key = "turquoise", r=0,   g=0.9, b=0.8, label="Turquoise" },
    { key = "grey",      r=0.5, g=0.5, b=0.5, label="Grey" },
    { key = "brown",     r=0.6, g=0.3, b=0.1, label="Brown" },
    { key = "gold",      r=1,   g=0.85,b=0.1, label="Gold" },
}

local function FontColorDropdown_Initialize(self, lvl)
    local info = UIDropDownMenu_CreateInfo()
    for _, c in ipairs(MSUF_COLOR_LIST) do
        info.text = c.label
        info.func = function()
            EnsureDB()
            MSUF_DB.general.fontColor = c.key
            UIDropDownMenu_SetSelectedValue(fontColorDrop, c.key)
            UpdateAllFonts()
        end
        info.value = c.key
        info.checked = (MSUF_DB.general.fontColor == c.key)
        UIDropDownMenu_AddButton(info, lvl)
    end
end

UIDropDownMenu_Initialize(fontColorDrop, FontColorDropdown_Initialize)
UIDropDownMenu_SetWidth(fontColorDrop, 180)
	

    local darkCheck = CreateFrame("CheckButton", "MSUF_DarkModeCheck", fontGroup, "UICheckButtonTemplate")
    darkCheck:SetPoint("TOPLEFT", fontDrop, "BOTTOMLEFT", 16, -20)
    darkCheck.text = _G["MSUF_DarkModeCheckText"]
    darkCheck.text:SetText("Dark Mode (dark black bars)")

    local classColorCheck = CreateFrame("CheckButton", "MSUF_ClassColorCheck", fontGroup, "UICheckButtonTemplate")
    classColorCheck:SetPoint("TOPLEFT", darkCheck, "BOTTOMLEFT", 0, -4)
    classColorCheck.text = _G["MSUF_ClassColorCheckText"]
    classColorCheck.text:SetText("Class Color Mode (color HP bars)")

    local boldCheck = CreateFrame("CheckButton", "MSUF_BoldTextCheck", fontGroup, "UICheckButtonTemplate")
    boldCheck:SetPoint("TOPLEFT", classColorCheck, "BOTTOMLEFT", 0, -4)
    boldCheck.text = _G["MSUF_BoldTextCheckText"]
    boldCheck.text:SetText("Use bold text (THICKOUTLINE)")

    local nameClassColorCheck = CreateFrame("CheckButton", "MSUF_NameClassColorCheck", fontGroup, "UICheckButtonTemplate")
    nameClassColorCheck:SetPoint("TOPLEFT", boldCheck, "BOTTOMLEFT", 0, -4)
-- Checkbox: shorten names (gleicher Style wie die anderen)
local shortenNamesCheck = CreateFrame("CheckButton", "MSUF_ShortenNamesCheck", fontGroup, "UICheckButtonTemplate")
shortenNamesCheck:SetPoint("TOPLEFT", nameClassColorCheck, "BOTTOMLEFT", 0, -4)

shortenNamesCheck.text = _G["MSUF_ShortenNamesCheckText"]
shortenNamesCheck.text:SetText("Shorten names (max 12 chars)")

shortenNamesCheck:SetChecked(MSUF_DB.shortenNames or false)

shortenNamesCheck:SetScript("OnClick", function(self)
    MSUF_DB.shortenNames = self:GetChecked() and true or false
    ApplyAllSettings()
end)

    nameClassColorCheck.text = _G["MSUF_NameClassColorCheckText"]
    nameClassColorCheck.text:SetText("Color player names by class")

    --------------------------------------------------
    -- DB → UI
    --------------------------------------------------
    function panel:LoadFromDB()
        EnsureDB()

        -- General (always sync)
        anchorEdit:SetText(MSUF_DB.general.anchorName or "UIParent")
        anchorCheck:SetChecked(MSUF_DB.general.anchorToCooldown and true or false)

        UIDropDownMenu_SetSelectedValue(fontDrop, MSUF_DB.general.fontKey or FONT_LIST[1].key)
        UIDropDownMenu_SetSelectedValue(fontColorDrop, MSUF_DB.general.fontColor or "white")
        darkCheck:SetChecked(MSUF_DB.general.darkMode and true or false)
        classColorCheck:SetChecked(MSUF_DB.general.useClassColors and true or false)
        boldCheck:SetChecked(MSUF_DB.general.boldText and true or false)
        nameClassColorCheck:SetChecked(MSUF_DB.general.nameClassColor and true or false)

        if currentKey == "fonts" then
            return
        end

        local conf = MSUF_DB[currentKey]
        if not conf then return end

        widthSlider:SetValue(conf.width or 250)
        heightSlider:SetValue(conf.height or 40)
        xSlider:SetValue(conf.offsetX or 0)
        ySlider:SetValue(conf.offsetY or 0)

        showNameCB:SetChecked(conf.showName ~= false)
        showHPCB:SetChecked(conf.showHP ~= false)
        showPowerCB:SetChecked(conf.showPower ~= false)

        nameOffsetXSlider:SetValue(conf.nameOffsetX or 4)
        nameOffsetYSlider:SetValue(conf.nameOffsetY or -4)
        hpOffsetXSlider:SetValue(conf.hpOffsetX or -4)
        hpOffsetYSlider:SetValue(conf.hpOffsetY or -4)
        powerOffsetXSlider:SetValue(conf.powerOffsetX or -4)
        powerOffsetYSlider:SetValue(conf.powerOffsetY or 4)
    end

    --------------------------------------------------
    -- SLIDER CALLBACKS (frame settings)
    --------------------------------------------------
    widthSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.width = value
        ApplySettingsForKey(currentKey)
    end

    heightSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.height = value
        ApplySettingsForKey(currentKey)
    end

    xSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.offsetX = value
        ApplySettingsForKey(currentKey)
    end

    ySlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.offsetY = value
        ApplySettingsForKey(currentKey)
    end

    showNameCB:SetScript("OnClick", function(self)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.showName = self:GetChecked() and true or false
        ApplySettingsForKey(currentKey)
    end)

    showHPCB:SetScript("OnClick", function(self)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.showHP = self:GetChecked() and true or false
        ApplySettingsForKey(currentKey)
    end)

    showPowerCB:SetScript("OnClick", function(self)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.showPower = self:GetChecked() and true or false
        ApplySettingsForKey(currentKey)
    end)

    nameOffsetXSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.nameOffsetX = value
        ApplySettingsForKey(currentKey)
    end

    nameOffsetYSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.nameOffsetY = value
        ApplySettingsForKey(currentKey)
    end

    hpOffsetXSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.hpOffsetX = value
        ApplySettingsForKey(currentKey)
    end

    hpOffsetYSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.hpOffsetY = value
        ApplySettingsForKey(currentKey)
    end

    powerOffsetXSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.powerOffsetX = value
        ApplySettingsForKey(currentKey)
    end

    powerOffsetYSlider.onValueChanged = function(self, value)
        if currentKey == "fonts" then return end
        EnsureDB()
        local conf = MSUF_DB[currentKey]
        if not conf then return end
        conf.powerOffsetY = value
        ApplySettingsForKey(currentKey)
    end

    --------------------------------------------------
    -- GENERAL TOGGLES
    --------------------------------------------------
    anchorCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.anchorToCooldown = self:GetChecked() and true or false
        ApplyAllSettings()
    end)

    darkCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.darkMode = self:GetChecked() and true or false
        ApplyAllSettings()
    end)

    classColorCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.useClassColors = self:GetChecked() and true or false
        ApplyAllSettings()
    end)

    boldCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.boldText = self:GetChecked() and true or false
        UpdateAllFonts()
    end)

    nameClassColorCheck:SetScript("OnClick", function(self)
    EnsureDB()
    MSUF_DB.general.nameClassColor = self:GetChecked() and true or false

    -- Farben sofort neu anwenden:
    UpdateAllFonts()
    end)


    --------------------------------------------------
    -- INIT
    --------------------------------------------------
    SetCurrentKey("player")
    panel:LoadFromDB()
    UpdateAllFonts()

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

------------------------------------------------------
-- HOOK COOLDOWN VIEWER
------------------------------------------------------
local function HookCooldownViewer()
    EnsureDB()

    if not MSUF_DB.general.anchorToCooldown then
        return
    end

    local ecv = _G["EssentialCooldownViewer"]
    if not ecv or ecv.MSUFHooked then return end
    ecv.MSUFHooked = true

    local function realign()
        if UnitFrames.player then PositionUnitFrame(UnitFrames.player, "player") end
        if UnitFrames.target then PositionUnitFrame(UnitFrames.target, "target") end
        if UnitFrames.focus  then PositionUnitFrame(UnitFrames.focus,  "focus")  end
    end

    ecv:HookScript("OnSizeChanged", realign)
    ecv:HookScript("OnShow",        realign)
    ecv:HookScript("OnHide",        realign)

    realign()
end

------------------------------------------------------
-- ADDON STARTUP
------------------------------------------------------
local main = CreateFrame("Frame")
main:RegisterEvent("PLAYER_LOGIN")

main:SetScript("OnEvent", function(self, event)
    EnsureDB()
    HideDefaultFrames()

    CreateSimpleUnitFrame("player")
    CreateSimpleUnitFrame("target")
    CreateSimpleUnitFrame("focus")
    for i = 1, 5 do
        CreateSimpleUnitFrame("boss" .. i)
    end

    ApplyAllSettings()
    CreateOptionsPanel()
    C_Timer.After(1, HookCooldownViewer)

    print("|cff00ff00MSUF:|r Frames + options loaded (Fonts tab, LSM, Dark/Class modes).")
end)

------------------------------------------------------
-- SLASH: /msuf reset
------------------------------------------------------
SLASH_MIDNIGHTSUF1 = "/msuf"
SlashCmdList["MIDNIGHTSUF"] = function(msg)
    msg = msg and msg:lower() or ""
    if msg == "reset" then
        if InCombatLockdown() then
            print("|cffff0000MSUF:|r Cannot reset while in combat.")
            return
        end
        MSUF_DB = nil
        EnsureDB()
        ApplyAllSettings()
        UpdateAllFonts()
        print("|cff00ff00MSUF:|r Positions and visibility reset to defaults.")
    else
        print("|cff00ff00MSUF:|r Use '/msuf reset' to reset all frames to default.")
    end
end

--[[
MSUF_Options_GF.lua
Options panel for GroupFrames with Party/Raid tab switcher.

NOT wrapped in DeferInit — _G.MSUF_EnsureGFPanelBuilt must exist at file
scope for MIRROR_PAGES late-bind. Panel itself is built lazily on first call.

Mirror-compatible: follows MSUF_EnsureModulesPanelBuilt pattern
(__MSUF_MirrorNoRestoreShow = true, fills parent via SetAllPoints).
]]

local addonName, ns = ...
ns = ns or {}

local _G          = _G
local type        = type
local CreateFrame = CreateFrame
local math_floor  = math.floor
local math_abs    = math.abs

local _gfPanel = nil
local _activeTab = "party"

local function GetGF()
    return ns.GF or _G.MSUF_GF or {}
end

-- ═══════════════════════════════════════════════════════════════
-- Tab Button
-- ═══════════════════════════════════════════════════════════════
local function MakeTab(parent, label, x, tabKey, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(90, 24)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -8)
    btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(label)
    btn._label = fs
    btn._tabKey = tabKey
    btn._msufApplyState = function(self, active)
        if active then
            self:SetBackdropColor(0.12, 0.24, 0.50, 0.95)
            self:SetBackdropBorderColor(0.30, 0.55, 1.00, 0.80)
            self._label:SetTextColor(0.90, 0.95, 1.00)
        else
            self:SetBackdropColor(0.08, 0.12, 0.22, 0.80)
            self:SetBackdropBorderColor(0.15, 0.30, 0.60, 0.50)
            self._label:SetTextColor(0.50, 0.58, 0.72)
        end
    end
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.10, 0.18, 0.36, 0.90)
    end)
    btn:SetScript("OnLeave", function(self)
        self:_msufApplyState(_activeTab == self._tabKey)
    end)
    return btn
end

-- ═══════════════════════════════════════════════════════════════
-- Widget Helpers
-- ═══════════════════════════════════════════════════════════════
local function MakeCheck(parent, label, y, getVal, setVal)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    cb.text = cb.text or cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.text:SetText(label)
    cb._gfGet = getVal
    cb:SetScript("OnClick", function(self)
        setVal(self:GetChecked() and true or false)
        local gf = GetGF()
        if type(gf.Refresh) == "function" then gf.Refresh() end
    end)
    cb:SetScript("OnShow", function(self)
        self:SetChecked(self._gfGet() and true or false)
    end)
    return cb
end

local function MakeSlider(parent, label, lo, hi, step, y, getVal, setVal)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    s:SetSize(180, 17)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Text = s.Text or s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.Text:SetPoint("TOP", s, "BOTTOM", 0, -2)
    if s.Low then s.Low:SetText(tostring(lo)) end
    if s.High then s.High:SetText(tostring(hi)) end
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    lbl:SetText(label)
    s._gfGet = getVal
    s:SetScript("OnValueChanged", function(self, val)
        val = math_floor(val + 0.5)
        self.Text:SetText(tostring(val))
        setVal(val)
        local gf = GetGF()
        if type(gf.Refresh) == "function" then gf.Refresh() end
    end)
    s:SetScript("OnShow", function(self)
        local v = self._gfGet()
        self:SetValue(v)
        self.Text:SetText(tostring(math_floor(v + 0.5)))
    end)
    return s
end

-- ═══════════════════════════════════════════════════════════════
-- Section Builder (party or raid)
-- ═══════════════════════════════════════════════════════════════
local function BuildSection(parent, mode)
    local gf = GetGF()
    local isRaid = (mode == "raid")
    local function Conf()
        return isRaid and gf.GetRaidConf() or gf.GetPartyConf()
    end

    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    section:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    section:SetHeight(800)
    section:Hide()

    local yOff = -10

    MakeCheck(section, "Enable " .. (isRaid and "Raid" or "Party") .. " Frames", yOff,
        function() return Conf().enabled ~= false end,
        function(v) Conf().enabled = v end)
    yOff = yOff - 32

    MakeSlider(section, "Width", isRaid and 30 or 40, isRaid and 200 or 300, 1, yOff,
        function() return Conf().width or (isRaid and 72 or 120) end,
        function(v) Conf().width = v end)
    yOff = yOff - 50

    MakeSlider(section, "Height", isRaid and 12 or 16, isRaid and 80 or 120, 1, yOff,
        function() return Conf().height or (isRaid and 30 or 36) end,
        function(v) Conf().height = v end)
    yOff = yOff - 50

    MakeSlider(section, "Spacing", 0, 20, 1, yOff,
        function() return Conf().spacing or 2 end,
        function(v) Conf().spacing = v end)
    yOff = yOff - 50

    MakeSlider(section, "Power Bar Height", 0, 20, 1, yOff,
        function() return Conf().powerBarHeight or (isRaid and 2 or 3) end,
        function(v) Conf().powerBarHeight = v end)
    yOff = yOff - 50

    MakeCheck(section, "Show Name", yOff,
        function() return Conf().showName ~= false end,
        function(v) Conf().showName = v end)
    yOff = yOff - 26

    MakeCheck(section, "Show HP Text", yOff,
        function() return Conf().showHP ~= false end,
        function(v) Conf().showHP = v end)
    yOff = yOff - 26

    MakeCheck(section, "Show Power Bar", yOff,
        function() return Conf().showPower ~= false end,
        function(v) Conf().showPower = v end)
    yOff = yOff - 36

    if isRaid then
        MakeSlider(section, "Units per Column", 1, 40, 1, yOff,
            function() return Conf().unitsPerColumn or 5 end,
            function(v) Conf().unitsPerColumn = v end)
        yOff = yOff - 50

        MakeSlider(section, "Max Columns", 1, 8, 1, yOff,
            function() return Conf().maxColumns or 8 end,
            function(v) Conf().maxColumns = v end)
        yOff = yOff - 50

        MakeSlider(section, "Group Spacing", 0, 30, 1, yOff,
            function() return Conf().groupSpacing or 4 end,
            function(v) Conf().groupSpacing = v end)
        yOff = yOff - 50
    end

    -- Override section
    do
        yOff = yOff - 6
        local hdr = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", section, "TOPLEFT", 10, yOff)
        hdr:SetText("|cffffcc00Overrides|r")
        yOff = yOff - 4

        local desc = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", section, "TOPLEFT", 14, yOff)
        desc:SetText("Enable overrides, then use the GF " .. (isRaid and "Raid" or "Party") .. " tab in Bars / Fonts menus.")
        desc:SetWidth(580)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(0.6, 0.65, 0.75)
        yOff = yOff - 22

        MakeCheck(section, "Override Bar Settings", yOff,
            function() return Conf().overrideBars == true end,
            function(v) Conf().overrideBars = v end)
        yOff = yOff - 26

        MakeCheck(section, "Override Font Settings", yOff,
            function() return Conf().overrideFont == true end,
            function(v) Conf().overrideFont = v end)
        yOff = yOff - 26

        MakeCheck(section, "Override Color Settings", yOff,
            function() return Conf().overrideColors == true end,
            function(v) Conf().overrideColors = v end)
        yOff = yOff - 30
    end

    section:SetHeight(math_abs(yOff) + 20)
    return section
end

-- ═══════════════════════════════════════════════════════════════
-- Panel Builder (lazy, mirror-compatible)
-- ═══════════════════════════════════════════════════════════════
local function BuildGFPanel()
    if _gfPanel then return _gfPanel end

    local gf = GetGF()

    local panel = CreateFrame("Frame", "MSUF_GFMirrorPanel", UIParent)
    panel:SetPoint("TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.__MSUF_MirrorNoRestoreShow = true
    panel:Hide()

    -- Header
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("Group Frames")
    panel.__MSUF_MirrorHeaderTargets = { title }

    -- Master controls
    local masterY = -44
    local masterEnable = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    masterEnable:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, masterY)
    masterEnable.text = masterEnable.text or masterEnable:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    masterEnable.text:SetPoint("LEFT", masterEnable, "RIGHT", 4, 0)
    masterEnable.text:SetText("Enable Group Frames")
    masterEnable:SetScript("OnClick", function(self)
        local db = _G.MSUF_DB
        if db then
            if type(db.groupframes) ~= "table" then gf.EnsureDB() end
            db.groupframes.enabled = self:GetChecked() and true or false
            if type(gf.Refresh) == "function" then gf.Refresh() end
        end
    end)
    masterEnable:SetScript("OnShow", function(self)
        self:SetChecked(type(gf.IsEnabled) == "function" and gf.IsEnabled() or false)
    end)

    local blizzHide = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    blizzHide:SetPoint("TOPLEFT", panel, "TOPLEFT", 240, masterY)
    blizzHide.text = blizzHide.text or blizzHide:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    blizzHide.text:SetPoint("LEFT", blizzHide, "RIGHT", 4, 0)
    blizzHide.text:SetText("Hide Blizzard Party/Raid Frames")
    blizzHide:SetScript("OnClick", function(self)
        local db = _G.MSUF_DB
        if db and type(db.groupframes) == "table" then
            db.groupframes.hideBlizzardFrames = self:GetChecked() and true or false
            if type(gf.Refresh) == "function" then gf.Refresh() end
        end
    end)
    blizzHide:SetScript("OnShow", function(self)
        self:SetChecked(type(gf.ShouldHideBlizzardFrames) == "function"
            and gf.ShouldHideBlizzardFrames() or false)
    end)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -76)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(640, 900)
    scrollFrame:SetScrollChild(content)
    panel.ScrollFrame = scrollFrame
    panel.content = content

    -- Tabs
    local sectionHost = CreateFrame("Frame", nil, content)
    sectionHost:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -40)
    sectionHost:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -40)
    sectionHost:SetHeight(800)

    local partySection = BuildSection(sectionHost, "party")
    local raidSection  = BuildSection(sectionHost, "raid")
    panel._partySection = partySection
    panel._raidSection  = raidSection

    local function SwitchTab(tab)
        _activeTab = tab
        partySection:SetShown(tab == "party")
        raidSection:SetShown(tab == "raid")
        panel._tabParty:_msufApplyState(tab == "party")
        panel._tabRaid:_msufApplyState(tab == "raid")
    end

    local tabParty = MakeTab(content, "Party Frames", 10, "party", function() SwitchTab("party") end)
    local tabRaid  = MakeTab(content, "Raid Frames", 106, "raid", function() SwitchTab("raid") end)
    panel._tabParty = tabParty
    panel._tabRaid  = tabRaid

    SwitchTab("party")

    -- Refresh on show
    panel:SetScript("OnShow", function(self)
        masterEnable:GetScript("OnShow")(masterEnable)
        blizzHide:GetScript("OnShow")(blizzHide)
        local sec = (_activeTab == "raid") and raidSection or partySection
        if sec then
            for _, kid in ipairs({ sec:GetChildren() }) do
                if kid.GetScript and kid:GetScript("OnShow") then
                    kid:GetScript("OnShow")(kid)
                end
            end
        end
    end)

    _gfPanel = panel
    _G.MSUF_GFMirrorPanel = panel
    return panel
end

-- ═══════════════════════════════════════════════════════════════
-- Global export at FILE SCOPE (not DeferInit)
-- ═══════════════════════════════════════════════════════════════
function _G.MSUF_EnsureGFPanelBuilt()
    return BuildGFPanel()
end

ns.MSUF_EnsureGFPanelBuilt = _G.MSUF_EnsureGFPanelBuilt

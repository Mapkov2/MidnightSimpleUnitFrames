-- MSUF_Options_GF_Auras.lua — GF Options: Buffs, Debuffs, Externals, Private Auras, Spell Indicators
-- 6 accordion sections injected into MSUF_Options_GF.lua panel.
-- Called from MSUF_Options_GF.lua after all other sections are built.
-- Features: drag-to-sort tiles, multi-spec, glow/pulse types, import/export, L["..."] localized.
-- Midnight 12.0, cold-path only.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
local UI = ns.UI
local SI = GF and GF.SpellIndicators
local L  = ns.L or setmetatable({}, { __index = function(_, k) return k end })

if not GF then return end

local CreateFrame = CreateFrame
local type    = type
local pairs   = pairs
local ipairs  = ipairs
local tostring = tostring
local math_floor = math.floor
local math_ceil  = math.ceil
local math_min   = math.min
local math_max   = math.max

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ANCHOR9 = {
    { key = "TOPLEFT",     label = L["Top Left"]     },
    { key = "TOP",         label = L["Top"]           },
    { key = "TOPRIGHT",    label = L["Top Right"]     },
    { key = "LEFT",        label = L["Left"]          },
    { key = "CENTER",      label = L["Center"]        },
    { key = "RIGHT",       label = L["Right"]         },
    { key = "BOTTOMLEFT",  label = L["Bottom Left"]   },
    { key = "BOTTOM",      label = L["Bottom"]        },
    { key = "BOTTOMRIGHT", label = L["Bottom Right"]  },
}
local GROWTH8 = {
    { key = "RIGHTDOWN", label = L["Right -> Down"] },
    { key = "RIGHTUP",   label = L["Right -> Up"]   },
    { key = "LEFTDOWN",  label = L["Left -> Down"]  },
    { key = "LEFTUP",    label = L["Left -> Up"]    },
    { key = "DOWNRIGHT", label = L["Down -> Right"] },
    { key = "DOWNLEFT",  label = L["Down -> Left"]  },
    { key = "UPRIGHT",   label = L["Up -> Right"]   },
    { key = "UPLEFT",    label = L["Up -> Left"]    },
    { key = "CENTER_H",  label = L["Center (Horizontal)"] },
    { key = "CENTER_V",  label = L["Center (Vertical)"]   },
}
local OUTLINE_ITEMS = {
    { key = "NONE",              label = L["None"]              },
    { key = "OUTLINE",           label = L["Outline"]           },
    { key = "THICKOUTLINE",      label = L["Thick Outline"]     },
    { key = "MONOCHROMEOUTLINE", label = L["Monochrome"]        },
}
local STACK_ANCHOR5 = {
    { key = "TOPLEFT",     label = L["Top Left"]     },
    { key = "TOPRIGHT",    label = L["Top Right"]    },
    { key = "BOTTOMLEFT",  label = L["Bottom Left"]  },
    { key = "BOTTOMRIGHT", label = L["Bottom Right"]  },
    { key = "CENTER",      label = L["Center"]        },
}
local FILTER_MODES = {
    { key = "ALL",            label = L["All Buffs"]        },
    { key = "PLAYER",         label = L["My Buffs Only"]    },
    { key = "RAID",           label = L["Raid Buffs"]       },
    { key = "RAID_PLAYER",    label = L["Raid + My Buffs"]  },
    { key = "CANCELABLE",     label = L["Cancelable"]       },
    { key = "NOT_CANCELABLE", label = L["Not Cancelable"]   },
    { key = "IMPORTANT",      label = L["Important"]        },
}
local DEBUFF_FILTER_MODES = {
    { key = "ALL",            label = L["All Debuffs"]      },
    { key = "PLAYER",         label = L["My Debuffs Only"]  },
    { key = "RAID",           label = L["Boss / Raid"]      },
    { key = "DISPELLABLE",    label = L["Dispellable"]      },
    { key = "CROWD_CONTROL",  label = L["Crowd Control"]    },
    { key = "IMPORTANT",      label = L["Important"]        },
}
local DIRECTION4 = {
    { key = "LEFT",   label = L["Left"]   },
    { key = "RIGHT",  label = L["Right"]  },
    { key = "TOP",    label = L["Top"]    },
    { key = "BOTTOM", label = L["Bottom"] },
}
local INDICATOR_TYPES = {
    { key = "none",   label = L["None"]   },
    { key = "icon",   label = L["Icon"]   },
    { key = "square", label = L["Square"] },
    { key = "bar",    label = L["Bar"]    },
    { key = "number", label = L["Number Only"] or "Number Only" },
}
local FRAME_EFFECT_TYPES = {
    { key = "none",       label = L["None"]               },
    { key = "healthtint", label = L["Health Bar Tint"]     },
    { key = "border",     label = L["Border"]              },
    { key = "glow",       label = L["Glow (Animated)"]     },
    { key = "pulse",      label = L["Pulse (Animated)"]    },
}
-- Legacy effect types that have been removed from the dropdown because they
-- had no proper UI controls and produced "dead" panels. Configs containing
-- these values are migrated to "none" on first read (defensive get) and via
-- a one-shot migration when the Spell Indicators section is built.
local LEGACY_FRAME_EFFECT_TYPES = {
    framealpha = true,
    namecolor  = true,
}
local TEX_W8 = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------------------------
-- Injector: called from MSUF_Options_GF.lua
------------------------------------------------------------------------
function GF.BuildAuraOptionsSections(AddSection, SCheck, SSlider, SDropdown, K, TrackRefresh, MakeColorSwatch, OpenColorPicker, refreshFns)
    if not UI then UI = ns.UI end

    local _inlineAuraPreviewFns = {}
    local _timerColorRefreshFns = {}

    local function AG(groupKey)
        local conf = GF.GetConf(K())
        if not conf.auras then conf.auras = {} end
        local g = conf.auras[groupKey]
        if not g then g = {}; conf.auras[groupKey] = g end
        return g
    end
    local function AV(groupKey, key) return AG(groupKey)[key] end
    local function RequestVisualRefresh()
        if GF.MarkAllDirty then
            GF.MarkAllDirty(GF.DIRTY_ALL or 0x3F)
        else
            local refresh = GF.RefreshVisuals
            if refresh then refresh() end
        end
    end
    local function RequestAuraRefresh()
        if GF.RequestAuraRefresh then
            GF.RequestAuraRefresh()
        else
            RequestVisualRefresh()
        end
        local refreshDebuffStripeControls = _G.MSUF_GF_RefreshDebuffStripeControlStates
        if type(refreshDebuffStripeControls) == "function" then refreshDebuffStripeControls() end
    end
    local function AW(groupKey, key, val)
        local g = AG(groupKey)
        if g[key] == val then return end
        g[key] = val
        RequestAuraRefresh()
        for i = 1, #_inlineAuraPreviewFns do
            _inlineAuraPreviewFns[i]()
        end
    end

    local function PA()
        local conf = GF.GetConf(K())
        if not conf.privateAuras then conf.privateAuras = {} end
        return conf.privateAuras
    end

    local function AurasRoot()
        local conf = GF.GetConf(K())
        if not conf.auras then conf.auras = {} end
        return conf.auras
    end

    local function BlizzardTypes()
        local auras = AurasRoot()
        if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
        local t = auras.blizzardTypes
        if t.buffs == nil then t.buffs = true end
        if t.debuffs == nil then t.debuffs = true end
        if t.dispels == nil then t.dispels = true end
        if t.externals == nil then t.externals = true end
        if t.privateAuras == nil then t.privateAuras = true end
        return t
    end

    local function SIC()
        local conf = GF.GetConf(K())
        if not conf.spellIndicators then
            conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 }
        end
        return conf.spellIndicators
    end

    ----------------------------------------------------------------
    -- Compact row layout helpers (mockup-style: label left, control right)
    ----------------------------------------------------------------
    local ROW_H    = 26
    local ROW_PAD  = 8
    local ROW_W    = 640
    local SL_W     = 180
    local DD_W     = 130

    local _auraRefreshFns = {}
    local AURA_CHECK_SIZE = 24
    local function RefreshAuraOptionControls()
        for i = 1, #_auraRefreshFns do
            local fn = _auraRefreshFns[i]
            if type(fn) == "function" then pcall(fn) end
        end
    end

    local function IsNativeRenderer()
        if GF.IsAuraRendererBlizzard and GF.GetConf then
            return GF.IsAuraRendererBlizzard(GF.GetConf(K())) == true
        end
        local mode = AurasRoot().renderer or "BLIZZARD"
        return mode == "BLIZZARD" or mode == "MIXED" or mode == "CUSTOM_BLIZZARD"
            or mode == "CUSTOM+BLIZZARD" or mode == "BOTH"
    end

    local function IsCustomRenderer()
        if GF.IsAuraRendererCustom and GF.GetConf then
            return GF.IsAuraRendererCustom(GF.GetConf(K())) == true
        end
        return AurasRoot().renderer == "CUSTOM"
    end

    _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}

    if not _G.StaticPopupDialogs["MSUF_SI_ICON_BLIZZARD_WARN"] then
        _G.StaticPopupDialogs["MSUF_SI_ICON_BLIZZARD_WARN"] = {
            text = "Spell Indicator |cffffd200Icon|r + |cffffd200Blizzard Renderer|r:\n\nSpell Indicators stay independent from aura rendering. If an indicator icon tracks the same aura Blizzard also shows, both icons can be visible.",
            button1 = "OK",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local function ShowSIIconBlizzardWarn()
        if _G.StaticPopup_Show then
            _G.StaticPopup_Show("MSUF_SI_ICON_BLIZZARD_WARN")
        end
    end

    local function AnySpellIndicatorHasIconPlaced()
        local conf = GF.GetConf(K())
        local si = conf and conf.spellIndicators
        if not (si and si.enabled ~= false) then return false end
        local specs = si.specs
        if not specs then return false end
        for _, specCfg in pairs(specs) do
            if type(specCfg) == "table" then
                for _, auraCfg in pairs(specCfg) do
                    if type(auraCfg) == "table" and auraCfg.enabled ~= false and auraCfg.placed then
                        local ptype = auraCfg.placed.type
                        if ptype == nil or ptype == "icon" then return true end
                    end
                end
            end
        end
        return false
    end

    local NATIVE_TYPE_BY_GROUP = {
        buff = "buffs",
        debuff = "debuffs",
        externals = "externals",
    }

    local function IsNativeAuraGroup(groupKey)
        local nativeKey = NATIVE_TYPE_BY_GROUP[groupKey]
        if not nativeKey then return false end
        local conf = GF.GetConf(K())
        if GF.IsBlizzardAuraTypeEnabled then
            return GF.IsBlizzardAuraTypeEnabled(conf, nativeKey) == true
        end
        return IsNativeRenderer() and BlizzardTypes()[nativeKey] ~= false
    end

    local function IsNativeAuraType(nativeKey)
        local conf = GF.GetConf(K())
        if GF.IsBlizzardAuraTypeEnabled then
            return GF.IsBlizzardAuraTypeEnabled(conf, nativeKey) == true
        end
        return IsNativeRenderer() and BlizzardTypes()[nativeKey] ~= false
    end

    local function HasCustomIconAuraGroups()
        if IsCustomRenderer() then return true end
        return not IsNativeAuraType("buffs")
            or not IsNativeAuraType("debuffs")
            or not IsNativeAuraType("externals")
    end

    local function StyleAuraCheck(cb)
        if not cb then return end
        cb:SetSize(AURA_CHECK_SIZE, AURA_CHECK_SIZE)
        if _G.MSUF_StyleCheckmark then _G.MSUF_StyleCheckmark(cb) end
        if _G.MSUF_StyleToggleText then _G.MSUF_StyleToggleText(cb) end
        if cb._msufToggleUpdate then cb._msufToggleUpdate() end
    end

    local function RowFrame(parent, prevRow, topOfs)
        local r = CreateFrame("Frame", nil, parent)
        r:SetSize(ROW_W, ROW_H)
        if prevRow then
            r:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -(topOfs or 0))
        else
            r:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_PAD, -(topOfs or 6))
        end
        return r
    end

    local function RowLabel(row, text)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", row, "LEFT", 4, 0)
        fs:SetText(text)
        fs:SetTextColor(0.85, 0.85, 0.90, 1)
        return fs
    end

    local function RowCheck(parent, prevRow, label, gk, key, topOfs)
        local row = RowFrame(parent, prevRow, topOfs)
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetPoint("LEFT", row, "LEFT", 2, 0)
        -- Label on the checkbox's built-in text (MSUF style)
        local fs = cb.text or cb.Text
        if fs and fs.SetText then
            fs:SetText(label or "")
            if fs.SetFontObject then fs:SetFontObject("GameFontHighlightSmall") end
        end
        cb:SetChecked(AV(gk, key) ~= false)
        cb:SetScript("OnClick", function(self)
            AW(gk, key, self:GetChecked() and true or false)
            if self._msufToggleUpdate then self._msufToggleUpdate() end
        end)
        -- Apply MSUF style AFTER SetScript (HookScript adds to chain)
        StyleAuraCheck(cb)
        _auraRefreshFns[#_auraRefreshFns + 1] = function()
            cb:SetChecked(AV(gk, key) ~= false)
            if cb._msufToggleUpdate then cb._msufToggleUpdate() end
        end
        row._ctrl = cb
        return row
    end

    local function FormatNumberBoxValue(v, step)
        v = tonumber(v) or 0
        if step and step >= 1 then
            return tostring(math_floor(v + 0.5))
        end
        return tostring(v)
    end

    local function ClampStepValue(v, lo, hi, step, def)
        v = tonumber(v)
        if v == nil then v = def or lo or 0 end
        if step and step > 0 then
            v = ((math_floor(((v - lo) / step) + 0.5) * step) + lo)
        end
        if v < lo then v = lo end
        if v > hi then v = hi end
        if step and step >= 1 then v = math_floor(v + 0.5) end
        return v
    end

    local function MakeNumberStepButton(parent, isPlus, width, height)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(width or 18, height or 20)
        local style = _G.MSUF_StyleSmallButton or (UI and UI.StyleSmallButton)
        if style then style(b, isPlus); b:SetSize(width or 18, height or 20) end
        return b
    end

    local function RowSlider(parent, prevRow, label, gk, key, lo, hi, step, def, topOfs)
        local row = RowFrame(parent, prevRow, topOfs)
        RowLabel(row, label)
        local plus = MakeNumberStepButton(row, true, 18, 20)
        plus:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        eb:SetSize(44, 20)
        eb:SetPoint("RIGHT", plus, "LEFT", -2, 0)
        eb:SetAutoFocus(false)
        eb:SetJustifyH("CENTER")
        eb:SetMaxLetters(6)
        if GameFontHighlightSmall then eb:SetFontObject(GameFontHighlightSmall) end
        if eb.SetTextColor then eb:SetTextColor(1, 1, 1, 1) end
        local minus = MakeNumberStepButton(row, false, 18, 20)
        minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
        local sl = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
        sl:SetSize(SL_W, 14)
        sl:SetPoint("RIGHT", minus, "LEFT", -8, 0)
        sl:SetMinMaxValues(lo, hi)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)
        -- Hide default slider text
        if sl.Text then sl.Text:SetText("") end
        if sl.Low  then sl.Low:SetText("")  end
        if sl.High then sl.High:SetText("") end
        sl.editBox = eb
        sl._msufLastValue = ClampStepValue(AV(gk, key), lo, hi, step, def)
        eb:SetText(FormatNumberBoxValue(sl._msufLastValue, step))
        sl:SetValue(sl._msufLastValue)
        local function SyncBox(v)
            if not eb:HasFocus() then
                eb:SetText(FormatNumberBoxValue(v, step))
            end
        end
        local function ApplyBox()
            local v = ClampStepValue(eb:GetText(), lo, hi, step, sl._msufLastValue or def)
            eb:SetText(FormatNumberBoxValue(v, step))
            sl:SetValue(v)
        end
        eb:SetScript("OnEnterPressed", function(self)
            ApplyBox()
            self:ClearFocus()
        end)
        eb:SetScript("OnEditFocusLost", ApplyBox)
        eb:SetScript("OnEscapePressed", function(self)
            self:SetText(FormatNumberBoxValue(sl:GetValue() or sl._msufLastValue or def, step))
            self:ClearFocus()
        end)
        eb:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        local function StepBox(dir)
            local base = tonumber(eb:GetText())
            if base == nil then base = sl:GetValue() or sl._msufLastValue or def end
            local v = ClampStepValue(base + ((step or 1) * dir), lo, hi, step, def)
            eb:SetText(FormatNumberBoxValue(v, step))
            sl:SetValue(v)
        end
        minus:SetScript("OnClick", function() StepBox(-1) end)
        plus:SetScript("OnClick", function() StepBox(1) end)
        sl:SetScript("OnValueChanged", function(self, v)
            if self._msufSkip then return end
            v = ClampStepValue(v, lo, hi, step, def)
            SyncBox(v)
            if self._msufLastValue == v then return end
            self._msufLastValue = v
            AW(gk, key, v)
        end)
        _auraRefreshFns[#_auraRefreshFns + 1] = function()
            local v = ClampStepValue(AV(gk, key), lo, hi, step, def)
            sl._msufSkip = true
            sl:SetValue(v)
            sl._msufSkip = false
            sl._msufLastValue = v
            if not eb:HasFocus() then
                eb:SetText(FormatNumberBoxValue(v, step))
            end
        end
        local _styleSl = _G.MSUF_StyleSlider or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
        if _styleSl then _styleSl(sl) end
        sl.minusButton = minus
        sl.plusButton = plus
        row._ctrl = sl
        return row
    end

    local function RowDropdown(parent, prevRow, label, gk, key, items, def, topOfs)
        local row = RowFrame(parent, prevRow, topOfs)
        RowLabel(row, label)
        local function CurrentValue()
            local cur = AV(gk, key)
            for _, item in ipairs(items or {}) do
                local itemKey = item.key
                if itemKey == nil then itemKey = item.value end
                if itemKey == cur then return cur end
            end
            return def or (items and items[1] and (items[1].key or items[1].value))
        end
        if UI and UI.Dropdown then
            local dd = UI.Dropdown({
                parent = row,
                width = DD_W,
                items = items,
                get = CurrentValue,
                set = function(v) AW(gk, key, v) end,
                maxVisible = 10,
            })
            dd:ClearAllPoints()
            dd:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            _auraRefreshFns[#_auraRefreshFns + 1] = function()
                if dd.Refresh then dd:Refresh() end
            end
            row._ctrl = dd
            return row
        end
        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetSize(DD_W, 20)
        btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        btn:SetBackdropColor(0.10, 0.14, 0.22, 1)
        btn:SetBackdropBorderColor(0.20, 0.30, 0.50, 0.7)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fs:SetTextColor(0.40, 0.67, 0.93, 1)
        local function RefreshLabel()
            local cur = CurrentValue()
            for _, item in ipairs(items or {}) do
                local itemKey = item.key
                if itemKey == nil then itemKey = item.value end
                if itemKey == cur then fs:SetText(item.label or item.text or tostring(itemKey or "")); return end
            end
            fs:SetText(tostring(cur))
        end
        RefreshLabel()
        -- Simple click-cycle through items
        btn:SetScript("OnClick", function()
            local count = #(items or {})
            if count <= 0 then return end
            local cur = CurrentValue()
            local idx = 1
            for i, item in ipairs(items) do
                local itemKey = item.key
                if itemKey == nil then itemKey = item.value end
                if itemKey == cur then idx = i; break end
            end
            idx = (idx % count) + 1
            AW(gk, key, items[idx].key or items[idx].value)
            RefreshLabel()
        end)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.35, 0.50, 0.75, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            for _, item in ipairs(items or {}) do
                local cur = CurrentValue()
                local itemKey = item.key
                if itemKey == nil then itemKey = item.value end
                local pre = itemKey == cur and "|cff66aaee> " or "  "
                GameTooltip:AddLine(pre .. (item.label or item.text or tostring(itemKey or "")), 0.8, 0.8, 0.8)
            end
            GameTooltip:AddLine(" ", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("Click to cycle", 0.5, 0.5, 0.6)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.20, 0.30, 0.50, 0.7)
            GameTooltip:Hide()
        end)
        _auraRefreshFns[#_auraRefreshFns + 1] = RefreshLabel
        row._ctrl = btn
        return row
    end

    local function RowValue(parent, prevRow, label, getFn, topOfs)
        local row = RowFrame(parent, prevRow, topOfs)
        RowLabel(row, label)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        fs:SetJustifyH("RIGHT")
        fs:SetTextColor(0.75, 0.75, 0.82, 1)
        local function Refresh() fs:SetText(tostring(getFn() or "0 / 0")) end
        Refresh()
        _auraRefreshFns[#_auraRefreshFns + 1] = Refresh
        return row
    end

    local function RowOffsetPair(parent, prevRow, label, gk, xKey, yKey, topOfs)
        local row = RowFrame(parent, prevRow, topOfs)
        RowLabel(row, label)

        local holder = CreateFrame("Frame", nil, row)
        holder:SetSize(184, 20)
        holder:SetPoint("RIGHT", row, "RIGHT", -4, 0)

        local xMinus = MakeNumberStepButton(holder, false, 16, 20)
        xMinus:SetPoint("LEFT", holder, "LEFT", 0, 0)

        local xEB = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
        xEB:SetSize(48, 20)
        xEB:SetPoint("LEFT", xMinus, "RIGHT", 2, 0)
        xEB:SetAutoFocus(false)
        xEB:SetJustifyH("CENTER")
        xEB:SetMaxLetters(6)
        if GameFontHighlightSmall then xEB:SetFontObject(GameFontHighlightSmall) end
        if xEB.SetTextColor then xEB:SetTextColor(1, 1, 1, 1) end

        local xPlus = MakeNumberStepButton(holder, true, 16, 20)
        xPlus:SetPoint("LEFT", xEB, "RIGHT", 2, 0)

        local sep = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sep:SetPoint("LEFT", xPlus, "RIGHT", 5, 0)
        sep:SetText("/")
        sep:SetTextColor(0.75, 0.75, 0.82, 1)

        local yMinus = MakeNumberStepButton(holder, false, 16, 20)
        yMinus:SetPoint("LEFT", sep, "RIGHT", 5, 0)

        local yEB = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
        yEB:SetSize(48, 20)
        yEB:SetPoint("LEFT", yMinus, "RIGHT", 2, 0)
        yEB:SetAutoFocus(false)
        yEB:SetJustifyH("CENTER")
        yEB:SetMaxLetters(6)
        if GameFontHighlightSmall then yEB:SetFontObject(GameFontHighlightSmall) end
        if yEB.SetTextColor then yEB:SetTextColor(1, 1, 1, 1) end

        local yPlus = MakeNumberStepButton(holder, true, 16, 20)
        yPlus:SetPoint("LEFT", yEB, "RIGHT", 2, 0)

        local function ClampOffset(v, def)
            v = tonumber(v)
            if v == nil then v = def or 0 end
            v = math_floor(v + 0.5)
            if v < -9999 then v = -9999 end
            if v > 9999 then v = 9999 end
            return v
        end
        local function CurrentX()
            return ClampOffset(AV(gk, xKey), 0)
        end
        local function CurrentY()
            return ClampOffset(AV(gk, yKey), 0)
        end
        local function Sync()
            if not xEB:HasFocus() then xEB:SetText(tostring(CurrentX())) end
            if not yEB:HasFocus() then yEB:SetText(tostring(CurrentY())) end
        end
        local function Apply()
            local x = ClampOffset(xEB:GetText(), CurrentX())
            local y = ClampOffset(yEB:GetText(), CurrentY())
            xEB:SetText(tostring(x))
            yEB:SetText(tostring(y))
            AW(gk, xKey, x)
            AW(gk, yKey, y)
        end
        local function Escape(self)
            xEB:SetText(tostring(CurrentX()))
            yEB:SetText(tostring(CurrentY()))
            self:ClearFocus()
        end
        for _, eb in ipairs({ xEB, yEB }) do
            eb:SetScript("OnEnterPressed", function(self)
                Apply()
                self:ClearFocus()
            end)
            eb:SetScript("OnEditFocusLost", Apply)
            eb:SetScript("OnEscapePressed", Escape)
            eb:SetScript("OnEditFocusGained", function(self)
                self:HighlightText()
            end)
        end
        local function StepOffset(axis, dir)
            if axis == "x" then
                local v = ClampOffset((tonumber(xEB:GetText()) or CurrentX()) + dir, CurrentX())
                xEB:SetText(tostring(v))
                AW(gk, xKey, v)
            else
                local v = ClampOffset((tonumber(yEB:GetText()) or CurrentY()) + dir, CurrentY())
                yEB:SetText(tostring(v))
                AW(gk, yKey, v)
            end
        end
        xMinus:SetScript("OnClick", function() StepOffset("x", -1) end)
        xPlus:SetScript("OnClick", function() StepOffset("x", 1) end)
        yMinus:SetScript("OnClick", function() StepOffset("y", -1) end)
        yPlus:SetScript("OnClick", function() StepOffset("y", 1) end)
        function holder:SetEnabled(enabled)
            enabled = enabled and true or false
            local a = enabled and 1 or 0.45
            for _, btn in ipairs({ xMinus, xPlus, yMinus, yPlus }) do
                if btn.SetAlpha then btn:SetAlpha(a) end
                if enabled then
                    if btn.Enable then btn:Enable() end
                else
                    if btn.Disable then btn:Disable() end
                end
            end
            for _, eb in ipairs({ xEB, yEB }) do
                if eb.EnableMouse then eb:EnableMouse(enabled) end
                if enabled then
                    if eb.Enable then eb:Enable() end
                else
                    if eb.Disable then eb:Disable() end
                end
                if eb.SetTextColor then
                    local c = enabled and 1 or 0.55
                    eb:SetTextColor(c, c, c, 1)
                end
            end
        end

        Sync()
        _auraRefreshFns[#_auraRefreshFns + 1] = Sync
        row._ctrl = holder
        return row
    end

    local function RowDivider(parent, prevRow, topOfs)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(ROW_W, 1)
        if prevRow then
            row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -(topOfs or 8))
        else
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_PAD, -(topOfs or 8))
        end
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetColorTexture(0.30, 0.30, 0.35, 0.5)
        return row
    end

    local function RowSubLabel(parent, prevRow, text, topOfs)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(ROW_W, 18)
        if prevRow then
            row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -(topOfs or 6))
        else
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_PAD, -(topOfs or 6))
        end
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", row, "LEFT", 4, 0)
        fs:SetText(text)
        fs:SetTextColor(1, 0.82, 0, 1)
        return row
    end

    local AURA_DISABLED_ALPHA = 0.45
    local function SetAuraControlEnabled(widget, enabled, applyAlpha)
        if not widget then return end
        enabled = enabled and true or false
        local alpha = enabled and 1 or AURA_DISABLED_ALPHA

        if widget.SetEnabled then
            widget:SetEnabled(enabled)
        elseif enabled then
            if widget.EnableMouse then widget:EnableMouse(true) end
            if widget.Enable then widget:Enable() end
        else
            if widget.EnableMouse then widget:EnableMouse(false) end
            if widget.Disable then widget:Disable() end
        end

        local name = widget.GetName and widget:GetName()
        local dropButton = widget.Button or (name and _G[name .. "Button"])
        if dropButton then
            if enabled then
                if dropButton.EnableMouse then dropButton:EnableMouse(true) end
                if dropButton.Enable then dropButton:Enable() end
            else
                if dropButton.EnableMouse then dropButton:EnableMouse(false) end
                if dropButton.Disable then dropButton:Disable() end
            end
            if applyAlpha ~= false and dropButton.SetAlpha then dropButton:SetAlpha(alpha) end
        end

        if widget._msufPeelButton then
            if widget._msufPeelButton.EnableMouse then widget._msufPeelButton:EnableMouse(enabled) end
            if enabled then
                if widget._msufPeelButton.Enable then widget._msufPeelButton:Enable() end
            else
                if widget._msufPeelButton.Disable then widget._msufPeelButton:Disable() end
            end
            if applyAlpha ~= false and widget._msufPeelButton.SetAlpha then widget._msufPeelButton:SetAlpha(alpha) end
        end

        if widget.editBox then
            if widget.editBox.EnableMouse then widget.editBox:EnableMouse(enabled) end
            if enabled then
                if widget.editBox.Enable then widget.editBox:Enable() end
            else
                if widget.editBox.Disable then widget.editBox:Disable() end
            end
        end

        for _, btn in ipairs({ widget.minusButton, widget.plusButton }) do
            if btn then
                if enabled then
                    if btn.Enable then btn:Enable() end
                else
                    if btn.Disable then btn:Disable() end
                end
            end
        end

        if applyAlpha ~= false then
            if widget.SetAlpha then widget:SetAlpha(alpha) end
            if widget.Text and widget.Text.SetAlpha then widget.Text:SetAlpha(alpha) end
            if widget.text and widget.text.SetAlpha then widget.text:SetAlpha(alpha) end
            if widget.editBox and widget.editBox.SetAlpha then widget.editBox:SetAlpha(alpha) end
            if widget.editBox and widget.editBox.SetTextColor then
                local c = enabled and 1 or 0.55
                widget.editBox:SetTextColor(c, c, c, 1)
            end
            if widget.minusButton and widget.minusButton.SetAlpha then widget.minusButton:SetAlpha(alpha) end
            if widget.plusButton and widget.plusButton.SetAlpha then widget.plusButton:SetAlpha(alpha) end
            if name then
                for _, suffix in ipairs({ "Text", "Low", "High" }) do
                    local region = _G[name .. suffix]
                    if region and region.SetAlpha then region:SetAlpha(alpha) end
                end
            end
        end

        if widget._msufToggleUpdate then widget._msufToggleUpdate() end
        if widget.__msufToggleUpdate then widget.__msufToggleUpdate() end
    end

    local function SetAuraRegionEnabled(region, enabled)
        if region and region.SetAlpha then region:SetAlpha(enabled and 1 or AURA_DISABLED_ALPHA) end
    end

    local function SetAuraControlsEnabled(enabled, widgets, regions)
        for i = 1, #(widgets or {}) do
            SetAuraControlEnabled(widgets[i], enabled, true)
        end
        for i = 1, #(regions or {}) do
            SetAuraRegionEnabled(regions[i], enabled)
        end
    end

    local function SetAuraBodyRowsEnabled(body, enabled, keepRow)
        if not body or not body.GetChildren then return end
        local alpha = enabled and 1 or AURA_DISABLED_ALPHA
        local rows = { body:GetChildren() }
        for i = 1, #rows do
            local row = rows[i]
            if row == keepRow then
                if row.SetAlpha then row:SetAlpha(1) end
                if row._ctrl then SetAuraControlEnabled(row._ctrl, true, false) end
            else
                if row.SetAlpha then row:SetAlpha(alpha) end
                if row._ctrl then SetAuraControlEnabled(row._ctrl, enabled, false) end
            end
        end
    end

    local function SetAuraRowEnabled(row, enabled)
        if not row then return end
        if row.SetAlpha then row:SetAlpha(enabled and 1 or AURA_DISABLED_ALPHA) end
        if row._ctrl then SetAuraControlEnabled(row._ctrl, enabled, false) end
    end

    local function ApplyNativeGroupSuppression(body, groupKey, keepRow)
        if not (body and body.GetChildren and IsNativeAuraGroup(groupKey)) then return end
        local rows = { body:GetChildren() }
        for i = 1, #rows do
            SetAuraRowEnabled(rows[i], rows[i] == keepRow)
        end
    end

    local AURA_TEXT_PREVIEW_IDS = {
        buff      = { 774, 17, 139 },
        debuff    = { 589, 980, 172 },
        externals = { 6940, 102342, 1022 },
    }
    local _auraTextPreviewTexCache = {}

    local function ResolveAuraPreviewTexture(spellID)
        local cached = _auraTextPreviewTexCache[spellID]
        if cached then return cached end
        local tex
        local cs = _G.C_Spell
        if cs and cs.GetSpellTexture then
            tex = cs.GetSpellTexture(spellID)
        end
        if not tex and _G.GetSpellInfo then
            local _, _, icon = _G.GetSpellInfo(spellID)
            tex = icon
        end
        tex = tex or "Interface\\Icons\\INV_Misc_QuestionMark"
        _auraTextPreviewTexCache[spellID] = tex
        return tex
    end

    local function ResolveAuraPreviewFont(kind)
        local fontPath = (GF.ResolveFontPath and GF.ResolveFontPath(kind)) or "Fonts\\FRIZQT__.TTF"
        local fontFlags = (GF.ResolveFontFlags and GF.ResolveFontFlags(kind)) or "OUTLINE"
        return fontPath, fontFlags
    end

    local function ReadAuraPreviewColor(t, dr, dg, db)
        if type(t) ~= "table" then return dr, dg, db, 1 end
        local r = t[1] or t.r
        local g = t[2] or t.g
        local b = t[3] or t.b
        if type(r) ~= "number" then r = dr end
        if type(g) ~= "number" then g = dg end
        if type(b) ~= "number" then b = db end
        return r, g, b, 1
    end

    local function ResolveAuraPreviewBaseTextColor()
        local g = _G.MSUF_DB and _G.MSUF_DB.general
        if g and g.useCustomFontColor == true then
            local r = g.fontColorCustomR
            local gg = g.fontColorCustomG
            local b = g.fontColorCustomB
            if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
                return r, gg, b, 1
            end
        end
        return 1, 1, 1, 1
    end

    local function ResolveAuraPreviewCooldownColor()
        local g = _G.MSUF_DB and _G.MSUF_DB.general
        local br, bg, bb = ResolveAuraPreviewBaseTextColor()
        local sr, sg, sb, sa = ReadAuraPreviewColor(g and g.aurasCooldownTextSafeColor, br, bg, bb)
        if g and g.gfAurasCooldownTextUseBuckets == false then
            return sr, sg, sb, sa
        end

        local warn = (g and type(g.gfAurasCooldownTextWarningSeconds) == "number") and g.gfAurasCooldownTextWarningSeconds or 15
        local urgent = (g and type(g.gfAurasCooldownTextUrgentSeconds) == "number") and g.gfAurasCooldownTextUrgentSeconds or 5
        if urgent > warn then urgent = warn end

        local remain = 3
        if remain <= urgent then
            return ReadAuraPreviewColor(g and g.aurasCooldownTextUrgentColor, 1, 0.55, 0.10)
        end
        if remain <= warn then
            return ReadAuraPreviewColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.20)
        end
        return sr, sg, sb, sa
    end

    local function ResolveAuraPreviewStackColor()
        local g = _G.MSUF_DB and _G.MSUF_DB.general
        return ReadAuraPreviewColor(g and g.aurasStackCountColor, 1, 1, 1)
    end

    local function RowAuraTextPreview(parent, prevRow, gk, topOfs)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetSize(ROW_W, 68)
        if prevRow then
            row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -(topOfs or 3))
        else
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", ROW_PAD, -(topOfs or 6))
        end
        row:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
        row:SetBackdropColor(0.03, 0.04, 0.07, 0.60)
        row:SetBackdropBorderColor(0.20, 0.24, 0.34, 0.75)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", row, "LEFT", 8, 0)
        label:SetText(L["Preview"] or "Preview")
        label:SetTextColor(0.62, 0.70, 0.86, 1)

        local icons = {}
        local iconIDs = AURA_TEXT_PREVIEW_IDS[gk] or AURA_TEXT_PREVIEW_IDS.buff
        for i = 1, 3 do
            local ic = CreateFrame("Frame", nil, row)
            ic:SetPoint("LEFT", row, "LEFT", 178 + (i - 1) * 54, 0)
            ic:SetSize(42, 42)

            local tex = ic:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(ic)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            tex:SetTexture(ResolveAuraPreviewTexture(iconIDs[i]))
            ic._tex = tex

            local border = ic:CreateTexture(nil, "BORDER")
            border:SetTexture(TEX_W8)
            border:SetPoint("TOPLEFT", ic, "TOPLEFT", -1, 1)
            border:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 1, -1)
            border:SetVertexColor(0.08, 0.09, 0.12, 0.95)

            local cdTarget = CreateFrame("Frame", nil, ic)
            cdTarget:SetAllPoints(ic)
            ic._cdTarget = cdTarget

            local cd = ic:CreateFontString(nil, "OVERLAY")
            ic._cdText = cd

            local st = ic:CreateFontString(nil, "OVERLAY")
            ic._stkText = st

            icons[i] = ic
        end

        local function Refresh()
            local g = AG(gk)
            local kind = K()
            local fontPath, fontFlags = ResolveAuraPreviewFont(kind)
            local rawIconSize = g.size or 20
            local previewIconSize = math_floor(math_min(46, math_max(30, rawIconSize * 1.25)) + 0.5)
            local scale = previewIconSize / math_max(1, rawIconSize)
            local showCd = g.showCooldown ~= false
            local showSt = g.showStacks ~= false
            local cdR, cdG, cdB, cdA = ResolveAuraPreviewCooldownColor()
            local stR, stG, stB, stA = ResolveAuraPreviewStackColor()

            for i = 1, #icons do
                local ic = icons[i]
                ic:SetSize(previewIconSize, previewIconSize)
                if ic._cdTarget then
                    ic._cdTarget:ClearAllPoints()
                    ic._cdTarget:SetAllPoints(ic)
                end

                local cd = ic._cdText
                if cd then
                    if showCd then
                        local cdSize = math_floor(((g.cooldownSize or 8) * scale) + 0.5)
                        cd:SetFont(fontPath, math_max(6, cdSize), g.cooldownOutline or fontFlags)
                        cd:SetText("3")
                        cd:SetTextColor(cdR, cdG, cdB, cdA)
                        cd:ClearAllPoints()
                        local anchor = g.cooldownAnchor or "CENTER"
                        local ox = math_floor(((g.cooldownOffsetX or 0) * scale) + 0.5)
                        local oy = math_floor(((g.cooldownOffsetY or 0) * scale) + 0.5)
                        cd:SetPoint(anchor, ic._cdTarget or ic, anchor, ox, oy)
                        cd:Show()
                    else
                        cd:Hide()
                    end
                end

                local st = ic._stkText
                if st then
                    if showSt then
                        local stSize = math_floor(((g.stackSize or 10) * scale) + 0.5)
                        st:SetFont(fontPath, math_max(6, stSize), g.stackOutline or fontFlags)
                        st:SetText("2")
                        st:SetTextColor(stR, stG, stB, stA)
                        st:ClearAllPoints()
                        local anchor = g.stackAnchor or "BOTTOMRIGHT"
                        local ox = math_floor(((g.stackOffsetX or -1) * scale) + 0.5)
                        local oy = math_floor(((g.stackOffsetY or 1) * scale) + 0.5)
                        st:SetPoint(anchor, ic, anchor, ox, oy)
                        st:Show()
                    else
                        st:Hide()
                    end
                end
            end
        end

        Refresh()
        _inlineAuraPreviewFns[#_inlineAuraPreviewFns + 1] = Refresh
        _auraRefreshFns[#_auraRefreshFns + 1] = Refresh
        return row
    end

    local function GeneralDB()
        _G.MSUF_DB = _G.MSUF_DB or {}
        _G.MSUF_DB.general = _G.MSUF_DB.general or {}
        return _G.MSUF_DB.general
    end

    local function ReadRGB(t, dr, dg, db)
        if type(t) ~= "table" then return dr, dg, db end
        local r = t[1] or t.r
        local g = t[2] or t.g
        local b = t[3] or t.b
        if type(r) ~= "number" then r = dr end
        if type(g) ~= "number" then g = dg end
        if type(b) ~= "number" then b = db end
        return r, g, b
    end

    local function GetBaseTimerColor()
        local g = GeneralDB()
        if g.useCustomFontColor == true
            and type(g.fontColorCustomR) == "number"
            and type(g.fontColorCustomG) == "number"
            and type(g.fontColorCustomB) == "number" then
            return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
        end
        return 1, 1, 1
    end

    local function GetTimerSafeColor()
        local br, bg, bb = GetBaseTimerColor()
        return ReadRGB(GeneralDB().aurasCooldownTextSafeColor, br, bg, bb)
    end

    local function GetTimerWarningColor()
        return ReadRGB(GeneralDB().aurasCooldownTextWarningColor, 1, 0.85, 0.20)
    end

    local function GetTimerUrgentColor()
        return ReadRGB(GeneralDB().aurasCooldownTextUrgentColor, 1, 0.55, 0.10)
    end

    local function RefreshTimerColorControlsOnly()
        for i = 1, #_inlineAuraPreviewFns do
            _inlineAuraPreviewFns[i]()
        end
        for i = 1, #_timerColorRefreshFns do
            _timerColorRefreshFns[i]()
        end
    end

    local function RequestTimerColorRefresh()
        if _G.MSUF_A2_InvalidateCooldownTextCurve then _G.MSUF_A2_InvalidateCooldownTextCurve() end
        if _G.MSUF_A2_ForceCooldownTextRecolor then _G.MSUF_A2_ForceCooldownTextRecolor() end
        if _G.MSUF_GF_InvalidateCooldownTextCurve then _G.MSUF_GF_InvalidateCooldownTextCurve() end
        if _G.MSUF_GF_ForceCooldownTextRecolor then _G.MSUF_GF_ForceCooldownTextRecolor() end
        RequestAuraRefresh()
        RefreshTimerColorControlsOnly()
        if _G.MSUF_Colors_RefreshAurasColorControls then _G.MSUF_Colors_RefreshAurasColorControls() end
        if _G.MSUF_Auras2Options_RefreshTimerColorControls then _G.MSUF_Auras2Options_RefreshTimerColorControls() end
    end
    _G.MSUF_GFAurasOptions_RefreshTimerColorControls = RefreshTimerColorControlsOnly

    local function RowGeneralCheck(parent, prevRow, label, key, def, topOfs)
        local row = RowFrame(parent, prevRow, topOfs)
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetPoint("LEFT", row, "LEFT", 2, 0)
        local fs = cb.text or cb.Text
        if fs and fs.SetText then
            fs:SetText(label or "")
            if fs.SetFontObject then fs:SetFontObject("GameFontHighlightSmall") end
        end
        local function Refresh()
            local v = GeneralDB()[key]
            if v == nil then v = def end
            cb:SetChecked(v and true or false)
            if cb._msufToggleUpdate then cb._msufToggleUpdate() end
        end
        cb:SetScript("OnClick", function(self)
            GeneralDB()[key] = self:GetChecked() and true or false
            RequestTimerColorRefresh()
            Refresh()
        end)
        StyleAuraCheck(cb)
        Refresh()
        _auraRefreshFns[#_auraRefreshFns + 1] = Refresh
        _timerColorRefreshFns[#_timerColorRefreshFns + 1] = Refresh
        row._ctrl = cb
        return row
    end

    local function RowGeneralSlider(parent, prevRow, label, key, lo, hi, step, def, clampFn, topOfs, postSet, enabledFn)
        local row = RowFrame(parent, prevRow, topOfs)
        RowLabel(row, label)
        local valFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        valFS:SetJustifyH("RIGHT")
        local sl = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
        sl:SetSize(SL_W, 14)
        sl:SetPoint("RIGHT", valFS, "LEFT", -8, 0)
        sl:SetMinMaxValues(lo, hi)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)
        if sl.Text then sl.Text:SetText("") end
        if sl.Low then sl.Low:SetText("") end
        if sl.High then sl.High:SetText("") end

        local function GetValue()
            local v = GeneralDB()[key]
            if type(v) ~= "number" then v = def end
            if clampFn then v = clampFn(v) end
            return math_floor(v + 0.5)
        end
        local function Refresh()
            local v = GetValue()
            sl._msufSkip = true
            sl:SetValue(v)
            sl._msufSkip = false
            sl._msufLastValue = v
            valFS:SetText(tostring(v))
            local enabled = not enabledFn or enabledFn() ~= false
            if enabled then
                if sl.Enable then sl:Enable() end
                row:SetAlpha(1)
                sl:SetAlpha(1)
            else
                if sl.Disable then sl:Disable() end
                row:SetAlpha(0.45)
                sl:SetAlpha(0.35)
            end
        end
        sl:SetScript("OnValueChanged", function(self, v)
            if self._msufSkip then return end
            v = math_floor(v + 0.5)
            if clampFn then v = clampFn(v) end
            valFS:SetText(tostring(v))
            if self._msufLastValue == v then return end
            self._msufLastValue = v
            GeneralDB()[key] = v
            if postSet then postSet(v) end
            RequestTimerColorRefresh()
        end)
        local _styleSl = _G.MSUF_StyleSlider or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
        if _styleSl then _styleSl(sl) end
        Refresh()
        _auraRefreshFns[#_auraRefreshFns + 1] = Refresh
        _timerColorRefreshFns[#_timerColorRefreshFns + 1] = Refresh
        row._ctrl = sl
        return row
    end

    local function RowTimerColorPreview(parent, prevRow, topOfs)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetSize(ROW_W, 70)
        row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -(topOfs or 6))
        row:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
        row:SetBackdropColor(0.03, 0.04, 0.07, 0.62)
        row:SetBackdropBorderColor(0.20, 0.24, 0.34, 0.75)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("LEFT", row, "LEFT", 8, 0)
        title:SetText(L["Preview"] or "Preview")
        title:SetTextColor(0.62, 0.70, 0.86, 1)

        local samples = {
            { key = "safe", label = L["Safe"] or "Safe", text = "60" },
            { key = "warn", label = L["Warning"] or "Warning", text = "15" },
            { key = "urg",  label = L["Urgent"] or "Urgent", text = "5" },
        }
        for i = 1, #samples do
            local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
            box:SetSize(104, 46)
            box:SetPoint("LEFT", row, "LEFT", 150 + (i - 1) * 116, 0)
            box:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
            box:SetBackdropColor(0.02, 0.02, 0.03, 0.8)
            box:SetBackdropBorderColor(0.14, 0.16, 0.22, 0.9)
            local fs = box:CreateFontString(nil, "OVERLAY")
            fs:SetFont((GF.ResolveFontPath and GF.ResolveFontPath(K())) or "Fonts\\FRIZQT__.TTF", 18, (GF.ResolveFontFlags and GF.ResolveFontFlags(K())) or "OUTLINE")
            fs:SetPoint("CENTER", box, "CENTER", 0, 4)
            fs:SetText(samples[i].text)
            box._text = fs
            local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            lbl:SetPoint("BOTTOM", box, "BOTTOM", 0, 3)
            lbl:SetText(samples[i].label)
            box._label = lbl
            samples[i].box = box
        end

        local function Refresh()
            local sr, sg, sb = GetTimerSafeColor()
            local wr, wg, wb = GetTimerWarningColor()
            local ur, ug, ub = GetTimerUrgentColor()
            local cols = { safe = { sr, sg, sb }, warn = { wr, wg, wb }, urg = { ur, ug, ub } }
            for i = 1, #samples do
                local sample = samples[i]
                local col = cols[sample.key]
                local fs = sample.box and sample.box._text
                if fs then
                    fs:SetFont((GF.ResolveFontPath and GF.ResolveFontPath(K())) or "Fonts\\FRIZQT__.TTF", 18, (GF.ResolveFontFlags and GF.ResolveFontFlags(K())) or "OUTLINE")
                    fs:SetTextColor(col[1], col[2], col[3], 1)
                end
            end
        end
        Refresh()
        _auraRefreshFns[#_auraRefreshFns + 1] = Refresh
        _timerColorRefreshFns[#_timerColorRefreshFns + 1] = Refresh
        return row
    end

    local function RowTimerColorSwatches(parent, prevRow, topOfs)
        local row = RowFrame(parent, prevRow, topOfs)
        RowLabel(row, L["Colors"] or "Colors")
        local specs = {
            { label = L["Safe"] or "Safe", get = GetTimerSafeColor, set = function(r, g, b)
                GeneralDB().aurasCooldownTextSafeColor = { r, g, b }
            end, reset = function()
                GeneralDB().aurasCooldownTextSafeColor = nil
            end },
            { label = L["Warning"] or "Warning", get = GetTimerWarningColor, set = function(r, g, b)
                GeneralDB().aurasCooldownTextWarningColor = { r, g, b }
            end, reset = function()
                GeneralDB().aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
            end },
            { label = L["Urgent"] or "Urgent", get = GetTimerUrgentColor, set = function(r, g, b)
                GeneralDB().aurasCooldownTextUrgentColor = { r, g, b }
            end, reset = function()
                GeneralDB().aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
            end },
        }
        local refs = {}
        for i = 1, #specs do
            local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
            btn:SetSize(74, 18)
            btn:SetPoint("LEFT", row, "LEFT", 182 + (i - 1) * 92, 0)
            btn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
            btn:SetBackdropBorderColor(0.20, 0.30, 0.50, 0.75)
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("LEFT", btn, "LEFT", 2, 2)
            tex:SetSize(16, 14)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", tex, "RIGHT", 5, 0)
            fs:SetText(specs[i].label)
            btn._tex = tex
            btn:SetScript("OnMouseUp", function(_, button)
                if button == "RightButton" then
                    if specs[i].reset then specs[i].reset() end
                    RequestTimerColorRefresh()
                    for j = 1, #refs do
                        if refs[j].Refresh then refs[j]:Refresh() end
                    end
                    return
                end
                if not OpenColorPicker then return end
                local r, g, b = specs[i].get()
                OpenColorPicker(r, g, b, function(nr, ng, nb)
                    specs[i].set(nr, ng, nb)
                    RequestTimerColorRefresh()
                    for j = 1, #refs do
                        if refs[j].Refresh then refs[j]:Refresh() end
                    end
                end)
            end)
            function btn:Refresh()
                local r, g, b = specs[i].get()
                self._tex:SetColorTexture(r, g, b, 1)
                local bucketsOn = not (GeneralDB().gfAurasCooldownTextUseBuckets == false)
                local enabled = (i == 1) or bucketsOn
                self:EnableMouse(enabled)
                self:SetAlpha(enabled and 1 or 0.35)
            end
            btn:Refresh()
            refs[#refs + 1] = btn
        end
        local reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        reset:SetSize(70, 20)
        reset:SetPoint("LEFT", row, "LEFT", 462, 0)
        reset:SetText(L["Reset"] or "Reset")
        reset:SetScript("OnClick", function()
            local g = GeneralDB()
            g.aurasCooldownTextSafeColor = nil
            g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
            g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
            RequestTimerColorRefresh()
            for j = 1, #refs do
                if refs[j].Refresh then refs[j]:Refresh() end
            end
        end)
        _auraRefreshFns[#_auraRefreshFns + 1] = function()
            for i = 1, #refs do refs[i]:Refresh() end
        end
        _timerColorRefreshFns[#_timerColorRefreshFns + 1] = function()
            for i = 1, #refs do refs[i]:Refresh() end
        end
        return row
    end

    ----------------------------------------------------------------
    -- Declassified Spell Blacklist section (shared by Buffs + Debuffs)
    -- Replaces old spellFilter/spellList system.
    -- Adds: base filter dropdown + category checkboxes
    ----------------------------------------------------------------
    local function BuildSpellFilterWidgets(body, prevRow, gk)
        local r = RowDivider(body, prevRow)
        r = RowSubLabel(body, r, L["Filter"])

        -- Tier 1: Blizzard API filter token (dropdown)
        local filterItems = (gk == "buff") and FILTER_MODES or DEBUFF_FILTER_MODES
        local filterDef = (gk == "buff") and "RAID" or "ALL"
        r = RowDropdown(body, r, L["Base Filter"], gk, "filterToken", filterItems, filterDef)

        -- Tier 2: Declassified spell category blacklist
        local AF = GF.AuraFilter or _G.MSUF_GF_AuraFilter
        if not AF then return r end

        local meta = AF.DECLASSIFIED_META
        if not meta or #meta == 0 then return r end

        r = RowDivider(body, r, 4)
        r = RowSubLabel(body, r, L["Hide Categories"] or "Hide Categories")

        -- Info text
        local infoRow = RowFrame(body, r, 0)
        local infoFs = infoRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        infoFs:SetPoint("LEFT", infoRow, "LEFT", 8, 0)
        infoFs:SetText("|cff666688" .. (L["Checked = hidden. Only works for declassified spells (12.0)."] or "Checked = hidden. Only works for declassified spells (12.0)."))
        r = infoRow

        -- One checkbox per category
        for _, catInfo in ipairs(meta) do
            local catKey = catInfo.key
            local catRow = RowFrame(body, r, 0)
            local cb = CreateFrame("CheckButton", nil, catRow, "UICheckButtonTemplate")
            cb:SetPoint("LEFT", catRow, "LEFT", 12, 0)
            local fs = cb.text or cb.Text
            if fs and fs.SetText then
                fs:SetText(catInfo.label or catKey)
                if fs.SetFontObject then fs:SetFontObject("GameFontHighlightSmall") end
            end
            -- Read current state
            local function GetCatState()
                local g = AG(gk)
                return type(g.blacklistCats) == "table" and g.blacklistCats[catKey] == true
            end
            cb:SetChecked(GetCatState())
            cb:SetScript("OnClick", function(self)
                local g = AG(gk)
                if type(g.blacklistCats) ~= "table" then g.blacklistCats = {} end
                g.blacklistCats[catKey] = self:GetChecked() and true or nil
                -- Invalidate blacklist hash cache
                local afr = GF.AuraFilter or _G.MSUF_GF_AuraFilter
                if afr and afr.InvalidateBlacklistHash then
                    afr.InvalidateBlacklistHash(g)
                end
                RequestVisualRefresh()
            end)
            -- Tooltip with spell details
            if catInfo.tooltip then
                cb:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(catInfo.label or catKey, 1, 1, 1)
                    GameTooltip:AddLine(catInfo.tooltip, 0.7, 0.7, 0.7, true)
                    GameTooltip:AddLine(" ")
                    if GetCatState() then
                        GameTooltip:AddLine("|cffff6666Hidden|r — these spells are filtered out.", 0.6, 0.6, 0.6)
                    else
                        GameTooltip:AddLine("|cff66ff66Shown|r — these spells are visible.", 0.6, 0.6, 0.6)
                    end
                    GameTooltip:Show()
                end)
                cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            StyleAuraCheck(cb)
            _auraRefreshFns[#_auraRefreshFns + 1] = function()
                cb:SetChecked(GetCatState())
                if cb._msufToggleUpdate then cb._msufToggleUpdate() end
            end
            r = catRow
        end

        return r
    end

    ----------------------------------------------------------------
    -- Build one aura group section (Buffs / Debuffs / Externals)
    -- Compact row layout matching mockup design
    ----------------------------------------------------------------
    local _AURA_SEC_KEY = { buff = "buffs", debuff = "debuffs", externals = "ext" }

    local function BuildAuraGroupSection(groupKey, title, expandedH, extraWidgets)
        local box, body = AddSection(expandedH, title, false, _AURA_SEC_KEY[groupKey])
        local gk = groupKey

        -- Row chain
        local r
        r = RowCheck(body, nil, L["Enable"], gk, "enabled", 6)
        local enableRow = r
        local function RefreshAuraGroupControls()
            SetAuraBodyRowsEnabled(body, AV(gk, "enabled") ~= false, enableRow)
            ApplyNativeGroupSuppression(body, gk, enableRow)
        end
        local enableCb = enableRow and enableRow._ctrl
        if enableCb and enableCb.HookScript then
            enableCb:HookScript("OnClick", RefreshAuraGroupControls)
        end
        r = RowDropdown(body, r, L["Anchor"], gk, "anchor", ANCHOR9, "BOTTOMLEFT")
        r = RowDropdown(body, r, L["Growth"], gk, "growth", GROWTH8, "RIGHTDOWN")
        r = RowOffsetPair(body, r, L["Offset X / Y"], gk, "x", "y")

        r = RowDivider(body, r)
        r = RowSlider(body, r, L["Icon size"], gk, "size", 8, 60, 1, 20, 4)
        r = RowSlider(body, r, L["Per row"], gk, "perRow", 1, 16, 1, 4)
        r = RowSlider(body, r, L["Max icons"], gk, "max", 1, 20, 1, 6)
        r = RowSlider(body, r, L["Spacing"], gk, "spacing", 0, 10, 1, 1)
        r = RowSlider(body, r, L["Layer (Z-Order)"], gk, "layer", 1, 15, 1,
            gk == "buff" and 5 or (gk == "debuff" and 6 or 7))
        -- ── Behind Health Bar ───────────────────────────────────
        r = RowDivider(body, r)
        r = RowSubLabel(body, r, L["Behind Health Bar"] or "Behind Health Bar")
        local bbRow = RowCheck(body, r, L["Show icons behind HP bar"] or "Show icons behind HP bar", gk, "behindBar", 0)
        -- Tooltip on the checkbox
        local bbCb = bbRow._ctrl
        if bbCb then
            bbCb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L["Behind Health Bar"] or "Behind Health Bar", 1, 1, 1)
                GameTooltip:AddLine(L["Icons render between background and health bar.\nVisible where HP is missing, hidden behind full HP.\nAnchor to BOTTOMLEFT with small offsets for best results."] or "Icons render between background and health bar.\nVisible where HP is missing, hidden behind full HP.\nAnchor to BOTTOMLEFT with small offsets for best results.", 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            bbCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        r = bbRow
        r = RowSlider(body, r, L["Behind Bar Opacity"] or "Behind Bar Opacity", gk, "behindBarAlpha", 30, 100, 5, 85, 0)
        -- ────────────────────────────────────────────────────────

        if extraWidgets then
            r = extraWidgets(body, r, gk) or r
        end

        r = RowDivider(body, r)
        r = RowSubLabel(body, r, L["Cooldown"] or "Cooldown")
        r = RowCheck(body, r, L["Show Cooldown Swipe"] or "Show Cooldown Swipe", gk, "showCooldownSwipe", 0)
        r = RowAuraTextPreview(body, r, gk)
        r = RowCheck(body, r, L["Show Cooldown Text"] or "Show Cooldown Text", gk, "showCooldown", 0)
        r = RowSlider(body, r, L["Font size"] or "Font size", gk, "cooldownSize", 6, 24, 1, 8)
        r = RowDropdown(body, r, L["Anchor"] or "Anchor", gk, "cooldownAnchor", ANCHOR9, "CENTER")
        r = RowSlider(body, r, L["Offset X"] or "Offset X", gk, "cooldownOffsetX", -20, 20, 1, 0)
        r = RowSlider(body, r, L["Offset Y"] or "Offset Y", gk, "cooldownOffsetY", -20, 20, 1, 0)

        r = RowDivider(body, r)
        r = RowSubLabel(body, r, L["Stack Count"] or "Stack Count")
        r = RowAuraTextPreview(body, r, gk)
        r = RowCheck(body, r, L["Show Stack Count"] or "Show Stack Count", gk, "showStacks", 0)
        r = RowSlider(body, r, L["Font size"] or "Font size", gk, "stackSize", 6, 24, 1, 10)
        r = RowDropdown(body, r, L["Anchor"] or "Anchor", gk, "stackAnchor", ANCHOR9, "BOTTOMRIGHT")
        r = RowSlider(body, r, L["Offset X"] or "Offset X", gk, "stackOffsetX", -20, 20, 1, -1)
        r = RowSlider(body, r, L["Offset Y"] or "Offset Y", gk, "stackOffsetY", -20, 20, 1, 1)

        _auraRefreshFns[#_auraRefreshFns + 1] = RefreshAuraGroupControls
        if body.HookScript then body:HookScript("OnShow", RefreshAuraGroupControls) end
        RefreshAuraGroupControls()

        return box, body
    end

    ----------------------------------------------------------------
    -- Section: Spell Indicators (default open)
    ----------------------------------------------------------------
    do
        -- One-shot migration: clear legacy FRAME_EFFECT_TYPES values that were
        -- removed from the dropdown ("framealpha", "namecolor"). Walks every
        -- saved spell config across all GF kinds. O(kinds * specs * spells),
        -- runs once per options-panel build.
        do
            local KINDS = { "party", "raid", "mythicraid" }
            for i = 1, #KINDS do
                local conf = GF.GetConf and GF.GetConf(KINDS[i])
                local sic  = conf and conf.spellIndicators
                local specs = sic and sic.specs
                if specs then
                    for _, specCfg in pairs(specs) do
                        if type(specCfg) == "table" then
                            for _, auraCfg in pairs(specCfg) do
                                if type(auraCfg) == "table" then
                                    local fc = auraCfg.frame
                                    if fc and fc.type and LEGACY_FRAME_EFFECT_TYPES[fc.type] then
                                        auraCfg.frame = false
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        local box, body = AddSection(640, L["Spell Indicators"], false, "si")
        local siRemeasureQueued = false
        local function RequestSISectionRemeasure()
            if box and box._msufRemeasure then box._msufRemeasure() end
            if siRemeasureQueued or not (C_Timer and C_Timer.After) then return end
            siRemeasureQueued = true
            C_Timer.After(0.05, function()
                siRemeasureQueued = false
                if box and box._msufRemeasure then box._msufRemeasure() end
            end)
        end

        SCheck({
            name = "MSUF_GF_SIEnable", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = L["Enable Spell Indicators"],
            get = function(k) return SIC().enabled == true end,
            set = function(k, v)
                SIC().enabled = v and true or false
                RequestVisualRefresh()
            end,
        })

        local siLayerSl = SSlider({
            name = "MSUF_GF_SILayer", parent = body, compact = true,
            anchor = body, anchorPoint = "TOPLEFT", x = 240, y = -6,
            min = 1, max = 15, step = 1, width = 160, default = 9,
            get = function(k) return SIC().layer or 9 end,
            set = function(k, v) SIC().layer = v; RequestVisualRefresh() end,
            formatText = function(v) return string.format(L["Layer: %d"], v) end,
        })

        -- Forward declarations
        local RefreshSpecLabel, RefreshSpellTiles, HideAllSpellPanels, SwapInOrder
        local RefreshMultiSpecChecks
        local expandedSpell

        local function ClearSIHighlight()
            if GF._highlightedSI then
                GF._highlightedSI = nil
                RequestVisualRefresh()
            end
        end

        -- Spec dropdown (auto-detect + multi-spec + all supported specs)
        local specItems = {
            { key = "auto",  label = L["Auto-Detect"] },
            { key = "multi", label = L["Multi-Spec"]  },
        }
        if SI and SI.SpecInfo then
            for specKey, info in pairs(SI.SpecInfo) do
                specItems[#specItems + 1] = { key = specKey, label = info.display }
            end
        end

        local specDd = SDropdown({
            name = "MSUF_GF_SISpec", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = -4, y = -34, width = 200,
            items = specItems,
            get = function(k) return SIC().spec or "auto" end,
            set = function(k, v)
                SIC().spec = v
                HideAllSpellPanels()
                expandedSpell = nil
                RefreshSpecLabel()
                RefreshMultiSpecChecks()
                RefreshSpellTiles()
                RequestVisualRefresh()
            end,
        })

        local specLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        specLabel:SetPoint("LEFT", specDd, "RIGHT", 8, 0)
        specLabel:SetText("")

        RefreshSpecLabel = function()
            local siCfg = SIC()
            if (siCfg.spec or "auto") == "auto" then
                local specKey = SI and SI.GetPlayerSpec and SI.GetPlayerSpec()
                if specKey then
                    local info = SI.SpecInfo and SI.SpecInfo[specKey]
                    specLabel:SetText(info and ("(" .. info.display .. ")") or "")
                else
                    specLabel:SetText("(" .. L["none detected"] .. ")")
                end
            elseif siCfg.spec == "multi" then
                local n = 0
                if siCfg.multiSpecs then for _ in pairs(siCfg.multiSpecs) do n = n + 1 end end
                specLabel:SetText("(" .. n .. " " .. L["specs selected"] .. ")")
            else
                specLabel:SetText("")
            end
        end
        RefreshSpecLabel()
        refreshFns[#refreshFns + 1] = RefreshSpecLabel

        ----------------------------------------------------------------
        -- Multi-spec checkboxes (shown only when spec == "multi")
        ----------------------------------------------------------------
        local multiContainer = CreateFrame("Frame", nil, body)
        multiContainer:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -58)
        multiContainer:SetSize(600, 1)
        multiContainer:Hide()

        local multiChecks = {}
        local multiSpecColW, multiSpecRowH, multiSpecLabelW = 150, 22, 108

        do
            local idx = 0
            if SI and SI.SpecInfo then
                for specKey, info in pairs(SI.SpecInfo) do
                    idx = idx + 1
                    local col = ((idx - 1) % 4)
                    local row = math_floor((idx - 1) / 4)
                    -- UI.Check expands its click target over the label. Keep that
                    -- expansion inside the 4-column grid so neighboring specs do
                    -- not steal clicks from the visible checkbox.
                    local chk = SCheck({
                        name = "MSUF_GF_SIMulti_" .. specKey, parent = multiContainer,
                        anchor = multiContainer, anchorPoint = "TOPLEFT",
                        x = col * multiSpecColW, y = -(row * multiSpecRowH),
                        label = info.display,
                        maxTextWidth = multiSpecLabelW,
                        get = function()
                            local ms = SIC().multiSpecs
                            return ms and ms[specKey] == true
                        end,
                        set = function(_, v)
                            local siCfg = SIC()
                            siCfg.multiSpecs = siCfg.multiSpecs or {}
                            if v then
                                siCfg.multiSpecs[specKey] = true
                            else
                                siCfg.multiSpecs[specKey] = nil
                            end
                            RefreshSpecLabel()
                            HideAllSpellPanels()
                            expandedSpell = nil
                            RefreshSpellTiles()
                            RequestVisualRefresh()
                        end,
                    })
                    multiChecks[specKey] = chk
                end
            end
            local totalRows = math_ceil(idx / 4)
            multiContainer:SetHeight(totalRows * multiSpecRowH + 4)
        end

        RefreshMultiSpecChecks = function()
            local siCfg = SIC()
            if siCfg.spec == "multi" then
                multiContainer:Show()
            else
                multiContainer:Hide()
            end
        end
        RefreshMultiSpecChecks()

        ----------------------------------------------------------------
        -- Tile grid container (shifts down when multi container visible)
        ----------------------------------------------------------------
        local tileContainer = CreateFrame("Frame", nil, body)
        tileContainer:SetSize(640, 1)
        local function RepositionTiles()
            tileContainer:ClearAllPoints()
            if multiContainer:IsShown() then
                tileContainer:SetPoint("TOPLEFT", multiContainer, "BOTTOMLEFT", 0, -6)
            else
                tileContainer:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -58)
            end
        end
        RepositionTiles()
        multiContainer:HookScript("OnShow", RepositionTiles)
        multiContainer:HookScript("OnHide", RepositionTiles)

        ----------------------------------------------------------------
        -- Per-spell config panels (lazy-created)
        ----------------------------------------------------------------
        local spellPanels = {}
        local function SpellPanelKey(specKey, auraName)
            return tostring(specKey or "") .. "\031" .. tostring(auraName or "")
        end

        HideAllSpellPanels = function()
            for _, panel in pairs(spellPanels) do panel:Hide() end
            ClearSIHighlight()
            RequestSISectionRemeasure()
        end

        local function BuildSpellPanel(auraName, specKey, parentTile)
            local panelKey = SpellPanelKey(specKey, auraName)
            if spellPanels[panelKey] then return spellPanels[panelKey] end

            local panel = CreateFrame("Frame", nil, body)
            panel:SetSize(640, 400)
            panel:EnableMouse(true)

            -- Subtle top divider instead of floating box
            local panelDiv = panel:CreateTexture(nil, "ARTWORK")
            panelDiv:SetHeight(1)
            panelDiv:SetColorTexture(0.25, 0.40, 0.55, 0.5)
            panelDiv:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
            panelDiv:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

            -- Trigger section re-measure on show/hide
            panel:HookScript("OnShow", function()
                RequestSISectionRemeasure()
            end)
            panel:HookScript("OnHide", function()
                RequestSISectionRemeasure()
            end)

            local function SC()
                local siCfg = SIC()
                siCfg.specs = siCfg.specs or {}
                siCfg.specs[specKey] = siCfg.specs[specKey] or {}
                siCfg.specs[specKey][auraName] = siCfg.specs[specKey][auraName] or {}
                return siCfg.specs[specKey][auraName]
            end
            local function PlacedCfg(create)
                local c = SC()
                if not c.placed and create ~= false then c.placed = {} end
                return c.placed
            end
            local function FrameCfg()
                local c = SC()
                if not c.frame then c.frame = {} end
                return c.frame
            end

            local trackable = SI and SI.TrackableAuras and SI.TrackableAuras[specKey]
            local dispName = auraName
            if trackable then
                for _, info in ipairs(trackable) do
                    if info.name == auraName then dispName = info.display; break end
                end
            end

            local titleFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
            titleFs:SetText(dispName)

            SCheck({
                name = "MSUF_GF_SI_" .. auraName .. "_Enable", parent = panel,
                anchor = titleFs, x = 80, y = 4,
                label = L["Enabled"] or "Enabled",
                maxTextWidth = 70,
                get = function(k) return SC().enabled ~= false end,
                set = function(k, v)
                    SC().enabled = v and true or false
                    RefreshSpellTiles()
                    RequestVisualRefresh()
                end,
            })

            SCheck({
                name = "MSUF_GF_SI_" .. tostring(specKey) .. "_" .. auraName .. "_OnlyOwn", parent = panel,
                anchor = titleFs, x = 210, y = 4,
                label = L["Only my cast"],
                maxTextWidth = 120,
                tooltip = L["Only show this spell indicator for auras cast by you."],
                get = function(k) return SC().onlyOwn ~= false end,
                set = function(k, v)
                    SC().onlyOwn = v and true or false
                    RequestVisualRefresh()
                end,
            })

            -- Close button: clean Unicode × with hover highlight. Replaces
            -- the legacy UI-StopButton atlas (small/yellow/pixelated) with a
            -- text-based glyph that scales cleanly and matches the panel
            -- palette. 20×20 hit area is generous; the visible glyph sits
            -- centered with a 1px Y nudge for optical alignment.
            local closeBtn = CreateFrame("Button", nil, panel)
            closeBtn:SetSize(20, 20)
            closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
            local closeFs = closeBtn:CreateFontString(nil, "OVERLAY")
            closeFs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
            closeFs:SetPoint("CENTER", closeBtn, "CENTER", 0, 1)
            closeFs:SetText("×")
            closeFs:SetTextColor(0.72, 0.76, 0.82, 1)
            closeBtn._fs = closeFs
            closeBtn:SetScript("OnEnter", function(self)
                self._fs:SetTextColor(1.0, 0.45, 0.45, 1)
            end)
            closeBtn:SetScript("OnLeave", function(self)
                self._fs:SetTextColor(0.72, 0.76, 0.82, 1)
            end)
            closeBtn:SetScript("OnClick", function() expandedSpell = nil; ClearSIHighlight(); panel:Hide() end)

            -- Arrow buttons for tile reorder (kept as keyboard-friendly fallback)
            local function MakeArrowBtn(par, direction, anchorFrame, anchorPoint, xOff)
                local btn = CreateFrame("Button", nil, par)
                btn:SetSize(16, 16)
                btn:SetPoint("RIGHT", anchorFrame, anchorPoint, xOff, 0)
                local tex = btn:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Arrow")
                btn._tex = tex
                btn:SetScript("OnEnter", function(self) self._tex:SetAlpha(1) end)
                btn:SetScript("OnLeave", function(self) self._tex:SetAlpha(0.7) end)
                tex:SetAlpha(0.7)
                return btn
            end

            local moveRight = MakeArrowBtn(panel, "Next", closeBtn, "LEFT", -8)
            moveRight:SetScript("OnClick", function()
                local siCfg = SIC()
                local sk = specKey
                if sk then SwapInOrder(siCfg, sk, auraName, 1); HideAllSpellPanels(); expandedSpell = nil; RefreshSpellTiles() end
            end)
            local moveLeft = MakeArrowBtn(panel, "Prev", moveRight, "LEFT", -2)
            moveLeft:SetScript("OnClick", function()
                local siCfg = SIC()
                local sk = specKey
                if sk then SwapInOrder(siCfg, sk, auraName, -1); HideAllSpellPanels(); expandedSpell = nil; RefreshSpellTiles() end
            end)

            -- Divider under header
            local headerDiv = panel:CreateTexture(nil, "ARTWORK")
            headerDiv:SetHeight(1)
            headerDiv:SetColorTexture(0.25, 0.30, 0.40, 0.5)
            headerDiv:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -32)
            headerDiv:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -32)

            -- Subtle vertical divider between the two columns. Spans most of
            -- the content area; matches headerDiv tone for visual coherence.
            local colDiv = panel:CreateTexture(nil, "ARTWORK")
            colDiv:SetWidth(1)
            colDiv:SetColorTexture(0.20, 0.32, 0.45, 0.40)
            colDiv:SetPoint("TOPLEFT",    panel, "TOPLEFT",    320, -42)
            colDiv:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 320, 16)

            -- Left column: Placed Indicator
            local COL_L = 20
            local COL_R = 340
            local ROW_TOP = -46

            local placedLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            placedLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_L, ROW_TOP)
            placedLbl:SetText(L["Placed Indicator"])
            placedLbl:SetTextColor(1, 0.82, 0)

            local typeDd = SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_Type", parent = panel,
                anchor = placedLbl, x = -16, y = -4, width = 100,
                items = INDICATOR_TYPES,
                get = function(k)
                    local pc = PlacedCfg(false)
                    return (pc and pc.type) or "none"
                end,
                set = function(k, v)
                    if v == "none" then
                        SC().placed = false
                    else
                        PlacedCfg(true).type = v
                    end
                    if panel._refreshBarW then panel._refreshBarW() end
                    if panel._refreshCDControls then panel._refreshCDControls() end
                    RequestVisualRefresh()
                    if (v == "icon" or v == nil) and IsNativeRenderer() then
                        ShowSIIconBlizzardWarn()
                    end
                end,
            })

            local anchorDd = SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_Anchor", parent = panel,
                anchor = typeDd, x = 0, y = -2, width = 120,
                items = ANCHOR9,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.anchor) or "TOPLEFT" end,
                set = function(k, v) PlacedCfg(true).anchor = v; RequestVisualRefresh() end,
            })

            local sizeSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Size", parent = panel, compact = true,
                anchor = anchorDd, x = 16, y = -6,
                min = 4, max = 40, step = 1, width = 170, default = 18,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.size) or 18 end,
                set = function(k, v) PlacedCfg(true).size = v; RequestVisualRefresh() end,
                formatText = function(v) return string.format(L["Size: %d"], v) end,
            })

            local xSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_X", parent = panel, compact = true,
                anchor = sizeSl, x = 0, y = -34,
                min = -100, max = 100, step = 1, width = 170, default = 0,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.x) or 0 end,
                set = function(k, v) PlacedCfg(true).x = v; RequestVisualRefresh() end,
                formatText = function(v) return string.format("X: %d", v) end,
            })

            local ySl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Y", parent = panel, compact = true,
                anchor = xSl, x = 0, y = -34,
                min = -100, max = 100, step = 1, width = 170, default = 0,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.y) or 0 end,
                set = function(k, v) PlacedCfg(true).y = v; RequestVisualRefresh() end,
                formatText = function(v) return string.format("Y: %d", v) end,
            })

            local barWSlider = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_BarW", parent = panel, compact = true,
                anchor = sizeSl, x = 180, y = 0,
                min = 10, max = 120, step = 1, width = 120, default = 54,
                get = function(k)
                    local pc = PlacedCfg(false)
                    return (pc and pc.barWidth) or (((pc and pc.size) or 18) * 3)
                end,
                set = function(k, v) PlacedCfg(true).barWidth = v; RequestVisualRefresh() end,
                formatText = function(v) return string.format(L["Width: %d"], v) end,
            })
            panel._barWSlider = barWSlider

            local function RefreshBarW()
                local pc = PlacedCfg(false)
                local t = pc and pc.type or "none"
                if t == "bar" then barWSlider:Show() else barWSlider:Hide() end
            end
            panel._refreshBarW = RefreshBarW
            RefreshBarW()

            local missingChk = SCheck({
                name = "MSUF_GF_SI_" .. auraName .. "_Missing", parent = panel,
                anchor = ySl, x = 0, y = -18,
                label = L["Show when missing"],
                get = function(k) local pc = PlacedCfg(false); return pc and pc.missing == true end,
                set = function(k, v) PlacedCfg(true).missing = v and true or false; RequestVisualRefresh() end,
            })

            local showCDChk = SCheck({
                name = "MSUF_GF_SI_" .. auraName .. "_ShowCD", parent = panel,
                anchor = missingChk, x = 0, y = -8,
                label = L["Show Cooldown Text"],
                get = function(k) local pc = PlacedCfg(false); return pc and pc.showCooldown ~= false end,
                set = function(k, v)
                    PlacedCfg(true).showCooldown = v and true or false
                    RequestVisualRefresh()
                    if panel._refreshCDControls then panel._refreshCDControls() end
                end,
            })

            local cdSizeSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_CDSize", parent = panel, compact = true,
                anchor = showCDChk, x = 24, y = -8,
                min = 6, max = 24, step = 1, width = 150, default = 8,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.cooldownSize) or 8 end,
                set = function(k, v) PlacedCfg(true).cooldownSize = v; RequestVisualRefresh() end,
                formatText = function(v) return string.format(L["CD Size: %d"], v) end,
            })

            local function RefreshCDControls()
                local pc = PlacedCfg(false)
                local t = pc and pc.type or "none"
                local placedOn = t ~= "none"
                if anchorDd then anchorDd:SetShown(placedOn) end
                if sizeSl then sizeSl:SetShown(placedOn) end
                if xSl then xSl:SetShown(placedOn) end
                if ySl then ySl:SetShown(placedOn) end
                if missingChk then missingChk:SetShown(placedOn) end
                if t == "bar" then
                    showCDChk:Hide(); cdSizeSl:Hide()
                elseif t == "number" then
                    showCDChk:Hide(); cdSizeSl:Hide()
                elseif t == "none" then
                    showCDChk:Hide(); cdSizeSl:Hide()
                else
                    showCDChk:Show()
                    if pc and pc.showCooldown ~= false then cdSizeSl:Show() else cdSizeSl:Hide() end
                end
            end
            panel._refreshCDControls = RefreshCDControls
            RefreshCDControls()

            -- Right column: Frame Effect
            local fxLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fxLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_R, ROW_TOP)
            fxLbl:SetText(L["Frame Effect"])
            fxLbl:SetTextColor(1, 0.82, 0)

            local fxDd = SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_FX", parent = panel,
                anchor = fxLbl, x = -16, y = -4, width = 150,
                items = FRAME_EFFECT_TYPES,
                get = function(k)
                    local fc = SC().frame
                    if not fc or not fc.type then return "none" end
                    -- Defensive cleanup: any legacy type leaks past the
                    -- one-shot migration get scrubbed on first read.
                    if LEGACY_FRAME_EFFECT_TYPES[fc.type] then
                        SC().frame = false
                        return "none"
                    end
                    return fc.type
                end,
                set = function(k, v)
                    if v == "none" then
                        SC().frame = false
                    else
                        local fc = FrameCfg()
                        fc.type = v
                        if not fc.color then
                            local track = SI and SI.TrackableAuras and SI.TrackableAuras[specKey]
                            if track then
                                for _, info in ipairs(track) do
                                    if info.name == auraName and info.color then
                                        fc.color = { info.color[1], info.color[2], info.color[3], 0.8 }
                                        break
                                    end
                                end
                            end
                            if not fc.color then fc.color = {1, 1, 1, 0.8} end
                        end
                        if not fc.priority then fc.priority = 5 end
                    end
                    RequestVisualRefresh()
                    if panel._refreshFxWidgets then panel._refreshFxWidgets() end
                end,
            })

            local fxColorRow = CreateFrame("Frame", nil, panel)
            fxColorRow:SetSize(250, 20)
            fxColorRow:SetPoint("TOPLEFT", fxDd, "BOTTOMLEFT", 16, -12)
            panel._fxColorRow = fxColorRow

            local fxColorLbl = fxColorRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fxColorLbl:SetPoint("LEFT", fxColorRow, "LEFT", 0, 0)
            fxColorLbl:SetText(L["Color:"])

            local fxSwatch = CreateFrame("Button", nil, fxColorRow)
            fxSwatch:SetSize(28, 14)
            fxSwatch:SetPoint("LEFT", fxColorLbl, "RIGHT", 6, 0)
            local fxSwatchTex = fxSwatch:CreateTexture(nil, "ARTWORK")
            fxSwatchTex:SetAllPoints()

            local function RefreshSwatch()
                local fc = SC().frame
                if fc and fc.color then
                    fxSwatchTex:SetColorTexture(fc.color[1] or 1, fc.color[2] or 1, fc.color[3] or 1, 1)
                end
            end
            fxSwatch:SetScript("OnClick", function()
                local fc = FrameCfg()
                local c = fc.color or {1, 1, 1, 0.8}
                OpenColorPicker(c[1], c[2], c[3], function(r, g, b)
                    fc.color = { r, g, b, c[4] or 0.8 }
                    RefreshSwatch()
                    RequestVisualRefresh()
                end)
            end)
            fxSwatch:SetScript("OnShow", RefreshSwatch)
            RefreshSwatch()

            local prioSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Prio", parent = panel, compact = true,
                anchor = fxColorRow, x = 0, y = -16,
                min = 1, max = 10, step = 1, width = 180, default = 5,
                get = function(k)
                    local fc = SC().frame
                    return fc and fc.priority or 5
                end,
                set = function(k, v)
                    local fc = SC().frame
                    if fc then fc.priority = v; RequestVisualRefresh() end
                end,
                formatText = function(v) return string.format(L["Priority: %d (1=highest)"], v) end,
            })

            local alphaSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Alpha", parent = panel, compact = true,
                anchor = prioSl, x = 0, y = -34,
                min = 5, max = 100, step = 5, width = 180, default = 15,
                get = function(k)
                    local fc = SC().frame
                    local a = fc and fc.alpha
                    return a and math_floor(a * 100 + 0.5) or 15
                end,
                set = function(k, v)
                    local fc = FrameCfg()
                    fc.alpha = v / 100
                    RequestVisualRefresh()
                end,
                formatText = function(v) return string.format(L["Tint Alpha: %d%%"], v) end,
            })

            local thickSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Thick", parent = panel, compact = true,
                anchor = prioSl, x = 0, y = -34,
                min = 1, max = 6, step = 1, width = 180, default = 2,
                get = function(k)
                    local fc = SC().frame
                    return fc and fc.thickness or 2
                end,
                set = function(k, v)
                    local fc = FrameCfg()
                    fc.thickness = v
                    RequestVisualRefresh()
                end,
                formatText = function(v) return string.format(L["Border: %dpx"], v) end,
            })

            local function RefreshFxWidgets()
                local fc = SC().frame
                local ft = fc and fc.type
                local hasFx = ft and ft ~= "none"
                if hasFx then fxColorRow:Show(); prioSl:Show(); RefreshSwatch()
                else fxColorRow:Hide(); prioSl:Hide() end
                if ft == "healthtint" or ft == "pulse" then alphaSl:Show() else alphaSl:Hide() end
                if ft == "border" or ft == "glow" then thickSl:Show() else thickSl:Hide() end
            end
            panel._refreshFxWidgets = RefreshFxWidgets
            panel:SetScript("OnShow", function() RefreshFxWidgets(); RefreshBarW() end)
            RefreshFxWidgets()

            panel:Hide()
            spellPanels[panelKey] = panel
            return panel
        end

        ----------------------------------------------------------------
        -- Sort order helpers
        ----------------------------------------------------------------
        local function GetOrderedTrackable(specKey, siCfg)
            local trackable = SI and SI.TrackableAuras and SI.TrackableAuras[specKey]
            if not trackable then return nil end
            local order = siCfg.sortOrder and siCfg.sortOrder[specKey]
            if not order or #order == 0 then return trackable end
            local nameToInfo = {}
            for _, info in ipairs(trackable) do nameToInfo[info.name] = info end
            local result = {}
            for _, name in ipairs(order) do
                if nameToInfo[name] then
                    result[#result + 1] = nameToInfo[name]
                    nameToInfo[name] = nil
                end
            end
            for _, info in ipairs(trackable) do
                if nameToInfo[info.name] then result[#result + 1] = info end
            end
            return result
        end

        local function EnsureSortOrder(siCfg, specKey)
            siCfg.sortOrder = siCfg.sortOrder or {}
            if not siCfg.sortOrder[specKey] then
                local trackable = SI and SI.TrackableAuras and SI.TrackableAuras[specKey]
                if not trackable then return nil end
                local arr = {}
                for _, info in ipairs(trackable) do arr[#arr + 1] = info.name end
                siCfg.sortOrder[specKey] = arr
            end
            return siCfg.sortOrder[specKey]
        end

        SwapInOrder = function(siCfg, specKey, auraName, delta)
            local arr = EnsureSortOrder(siCfg, specKey)
            if not arr then return end
            for i = 1, #arr do
                if arr[i] == auraName then
                    local j = i + delta
                    if j >= 1 and j <= #arr then
                        arr[i], arr[j] = arr[j], arr[i]
                    end
                    return
                end
            end
        end

        -- Insert auraName at target position in sort order
        local function InsertAtPosition(siCfg, specKey, auraName, targetIdx)
            local arr = EnsureSortOrder(siCfg, specKey)
            if not arr then return end
            local fromIdx
            for i = 1, #arr do
                if arr[i] == auraName then fromIdx = i; break end
            end
            if not fromIdx or fromIdx == targetIdx then return end
            table.remove(arr, fromIdx)
            if targetIdx > fromIdx then targetIdx = targetIdx - 1 end
            if targetIdx < 1 then targetIdx = 1 end
            if targetIdx > #arr + 1 then targetIdx = #arr + 1 end
            table.insert(arr, targetIdx, auraName)
        end

        ----------------------------------------------------------------
        -- Tile snap helper (Bars-proven pattern: SetMovable + StartMoving)
        ----------------------------------------------------------------
        local TILE_SIZE = 52
        local TILE_GAP = 4
        local TILES_PER_ROW = 10

        local function TileSlotPos(slotIdx, baseY)
            local col = (slotIdx - 1) % TILES_PER_ROW
            local row = math_floor((slotIdx - 1) / TILES_PER_ROW)
            return col * (TILE_SIZE + TILE_GAP), -(baseY + row * (TILE_SIZE + TILE_GAP))
        end

        local function SnapAllTiles()
            local tiles = tileContainer._tiles
            if not tiles then return end
            for _, t in ipairs(tiles) do
                if t:IsShown() and t._slotIdx then
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", tileContainer, "TOPLEFT", TileSlotPos(t._slotIdx, t._baseY or 0))
                    t:SetFrameStrata(tileContainer:GetFrameStrata())
                end
            end
        end

        ----------------------------------------------------------------
        -- Build spell tiles (Bars-proven drag pattern)
        ----------------------------------------------------------------
        RefreshSpellTiles = function()
            if tileContainer._tiles then
                for _, tile in ipairs(tileContainer._tiles) do tile:Hide() end
            end
            tileContainer._tiles = tileContainer._tiles or {}

            local siCfg = SIC()
            local isMulti = (siCfg.spec or "auto") == "multi"

            local specsToShow = {}
            if isMulti then
                local ms = siCfg.multiSpecs
                if ms then
                    for sk in pairs(ms) do specsToShow[#specsToShow + 1] = sk end
                end
                table.sort(specsToShow)
            else
                local sk
                if (siCfg.spec or "auto") == "auto" then
                    sk = SI and SI.GetPlayerSpec and SI.GetPlayerSpec()
                else
                    sk = siCfg.spec
                end
                if sk then specsToShow[1] = sk end
            end

            if #specsToShow == 0 then return end

            local globalIdx = 0
            local yOffset = 0

            for _, specKey in ipairs(specsToShow) do
                if isMulti then
                    local info = SI.SpecInfo and SI.SpecInfo[specKey]
                    if info then
                        local hdr = tileContainer._specHeaders and tileContainer._specHeaders[specKey]
                        if not hdr then
                            hdr = tileContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            tileContainer._specHeaders = tileContainer._specHeaders or {}
                            tileContainer._specHeaders[specKey] = hdr
                        end
                        hdr:ClearAllPoints()
                        hdr:SetPoint("TOPLEFT", tileContainer, "TOPLEFT", 0, -yOffset)
                        hdr:SetText(info.display)
                        hdr:SetTextColor(0.9, 0.8, 0.5)
                        hdr:Show()
                        yOffset = yOffset + 18
                    end
                end

                local trackable = GetOrderedTrackable(specKey, siCfg)
                if trackable then
                    local localIdx = 0
                    local specBaseY = yOffset
                    local specTileCount = #trackable

                    for _, info in ipairs(trackable) do
                        globalIdx = globalIdx + 1
                        localIdx = localIdx + 1

                        local tile = tileContainer._tiles[globalIdx]
                        if not tile then
                            -- Frame (not Button) — enables SetMovable + StartMoving
                            tile = CreateFrame("Frame", nil, tileContainer, "BackdropTemplate")
                            tile:SetSize(TILE_SIZE, TILE_SIZE)
                            tile:SetMovable(true)
                            tile:EnableMouse(true)
                            tile:RegisterForDrag("LeftButton")
                            tile:SetBackdrop({
                                bgFile = "Interface\\Buttons\\WHITE8x8",
                                edgeFile = "Interface\\Buttons\\WHITE8x8",
                                edgeSize = 1,
                            })
                            tile:SetBackdropColor(0.10, 0.10, 0.12, 1)

                            tile._icon = tile:CreateTexture(nil, "ARTWORK")
                            tile._icon:SetSize(36, 36)
                            tile._icon:SetPoint("TOP", 0, -3)
                            tile._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                            tile._label = tile:CreateFontString(nil, "OVERLAY")
                            tile._label:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
                            tile._label:SetPoint("BOTTOM", 0, 2)
                            tile._label:SetWidth(TILE_SIZE - 4)
                            tile._label:SetMaxLines(1)
                            tile._label:SetJustifyH("CENTER")

                            tileContainer._tiles[globalIdx] = tile
                        end

                        -- Store position data for snap
                        tile._slotIdx = localIdx
                        tile._baseY = specBaseY
                        tile._auraName = info.name
                        tile._specKey = specKey
                        tile._specTileCount = specTileCount
                        tile._wasDragged = false

                        tile:ClearAllPoints()
                        tile:SetPoint("TOPLEFT", tileContainer, "TOPLEFT", TileSlotPos(localIdx, specBaseY))

                        local iconTex = SI and SI.GetAuraIcon(specKey, info.name) or 136243
                        tile._icon:SetTexture(iconTex)
                        tile._label:SetText(info.display)

                        local auraName = info.name
                        local auraCfg = siCfg.specs and siCfg.specs[specKey] and siCfg.specs[specKey][auraName]
                        local isDisabled = auraCfg and auraCfg.enabled == false

                        local c = info.color or {0.5, 0.5, 0.5}
                        if isDisabled then
                            tile._icon:SetDesaturated(true)
                            tile._icon:SetAlpha(0.35)
                            tile:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
                            tile._label:SetTextColor(0.45, 0.45, 0.45)
                        else
                            tile._icon:SetDesaturated(false)
                            tile._icon:SetAlpha(1)
                            tile:SetBackdropBorderColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.8)
                            if info.secret then
                                tile._label:SetTextColor(0.7, 0.6, 0.9)
                            else
                                tile._label:SetTextColor(0.9, 0.9, 0.9)
                            end
                        end

                        -- Hover
                        tile:SetScript("OnEnter", function(self)
                            self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
                            self:SetBackdropColor(0.15, 0.15, 0.18, 1)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:AddLine(info.display, 1, 1, 1)
                            if info.secret then
                                GameTooltip:AddLine(L["Secret aura (name-matched)"], 0.7, 0.6, 0.9)
                            end
                            GameTooltip:AddLine(L["Left-click to configure"], 0.7, 0.7, 0.7)
                            GameTooltip:AddLine(L["Right-click to toggle"], 0.5, 0.8, 0.5)
                            GameTooltip:AddLine(L["Drag to reorder"], 0.5, 0.7, 0.9)
                            GameTooltip:Show()
                        end)
                        tile:SetScript("OnLeave", function(self)
                            GameTooltip:Hide()
                            local ac = siCfg.specs and siCfg.specs[specKey] and siCfg.specs[specKey][auraName]
                            local off = ac and ac.enabled == false
                            if off then
                                self:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
                            else
                                self:SetBackdropBorderColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.8)
                            end
                            self:SetBackdropColor(0.10, 0.10, 0.12, 1)
                        end)

                        -- Drag: exact Bars pattern (StartMoving / StopMovingOrSizing)
                        tile:SetScript("OnDragStart", function(self)
                            GameTooltip:Hide()
                            self._wasDragged = true
                            self:StartMoving()
                            self:SetFrameStrata("TOOLTIP")
                        end)

                        tile:SetScript("OnDragStop", function(self)
                            self:StopMovingOrSizing()
                            self:SetFrameStrata(tileContainer:GetFrameStrata())
                            -- Find nearest slot by 2D distance
                            local selfCX, selfCY = self:GetCenter()
                            local bestSlot = self._slotIdx
                            local bestDist = math.huge
                            for s = 1, self._specTileCount do
                                local sx, sy = TileSlotPos(s, self._baseY)
                                local slotCX = tileContainer:GetLeft() + sx + TILE_SIZE / 2
                                local slotCY = tileContainer:GetTop() + sy - TILE_SIZE / 2
                                local dx = selfCX - slotCX
                                local dy = selfCY - slotCY
                                local dist = dx * dx + dy * dy
                                if dist < bestDist then
                                    bestDist = dist
                                    bestSlot = s
                                end
                            end
                            if bestSlot ~= self._slotIdx then
                                InsertAtPosition(SIC(), self._specKey, self._auraName, bestSlot)
                            end
                            HideAllSpellPanels()
                            expandedSpell = nil
                            RefreshSpellTiles()
                        end)

                        -- Click via OnMouseUp (Frame, not Button)
                        tile:SetScript("OnMouseUp", function(self, btn)
                            if self._wasDragged then
                                self._wasDragged = false
                                return
                            end
                            if btn == "RightButton" then
                                local sc = SIC()
                                sc.specs = sc.specs or {}
                                sc.specs[specKey] = sc.specs[specKey] or {}
                                sc.specs[specKey][auraName] = sc.specs[specKey][auraName] or {}
                                local ac = sc.specs[specKey][auraName]
                                ac.enabled = ac.enabled == false and true or false
                                RefreshSpellTiles()
                                RequestVisualRefresh()
                                return
                            end
                            if btn == "LeftButton" then
                                HideAllSpellPanels()
                                local panelKey = SpellPanelKey(specKey, auraName)
                                if expandedSpell == panelKey then
                                    expandedSpell = nil
                                    return
                                end
                                expandedSpell = panelKey
                                GF._highlightedSI = auraName
                                RequestVisualRefresh()
                                local panel = BuildSpellPanel(auraName, specKey, self)
                                panel:ClearAllPoints()
                                local totalRows = math_ceil(specTileCount / TILES_PER_ROW)
                                local gridH = yOffset + totalRows * (TILE_SIZE + TILE_GAP) - TILE_GAP + 2
                                panel:SetPoint("TOPLEFT", tileContainer, "TOPLEFT", 0, -gridH)
                                panel:Show()
                                RequestSISectionRemeasure()
                            end
                        end)

                        tile:Show()
                    end

                    local specRows = math_ceil(localIdx / TILES_PER_ROW)
                    yOffset = yOffset + specRows * (TILE_SIZE + TILE_GAP) + (isMulti and 8 or 0)
                end
            end

            -- Hide unused spec headers
            if tileContainer._specHeaders then
                for sk, hdr in pairs(tileContainer._specHeaders) do
                    local found = false
                    for _, s in ipairs(specsToShow) do
                        if s == sk then found = true; break end
                    end
                    if not found then hdr:Hide() end
                end
            end

            tileContainer:SetHeight(yOffset + 280)
            RequestSISectionRemeasure()
        end

        RefreshSpellTiles()
        refreshFns[#refreshFns + 1] = function()
            RefreshSpecLabel()
            RefreshMultiSpecChecks()
            RefreshSpellTiles()
        end
    end

    ----------------------------------------------------------------
    -- Section: Cooldown Style
    ----------------------------------------------------------------
    do
        local box, body = AddSection(120, L["Cooldown Style"] or "Cooldown Style", false, "cooldownstyle")

        local cdSwipeChk = SCheck({
            name = "MSUF_GF_AuraCooldownSwipeStyleCheck", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -10,
            label = L["Swipe darkens on loss"] or "Swipe darkens on loss",
            get = function(k)
                local conf = GF.GetConf(k)
                return conf and conf.cooldownSwipeDarkenOnLoss == true
            end,
            set = function(k, v)
                local conf = GF.GetConf(k)
                if conf then conf.cooldownSwipeDarkenOnLoss = v and true or false end
                RequestVisualRefresh()
            end,
        })

        local cdSwipeHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cdSwipeHint:SetPoint("TOPLEFT", cdSwipeChk, "BOTTOMLEFT", 24, -2)
        cdSwipeHint:SetWidth(560)
        cdSwipeHint:SetJustifyH("LEFT")
        cdSwipeHint:SetText(L["Off = default Blizzard cooldown swipe. On = elapsed-time swipe that darkens as time is lost."] or "Off = default Blizzard cooldown swipe. On = elapsed-time swipe that darkens as time is lost.")
        cdSwipeHint:SetTextColor(0.5, 0.55, 0.65)
    end

    ----------------------------------------------------------------
    -- Section: Blizzard Renderer
    ----------------------------------------------------------------
    do
        local box, body = AddSection(560, L["Blizzard Renderer"] or "Blizzard Renderer", false, "blizzrenderer")
        local refreshBlizzardControls
        local routeLeftX, routeRightX = 340, 500
        local function RendererCheck(spec)
            spec.maxTextWidth = spec.maxTextWidth or 150
            local cb = SCheck(spec)
            -- This section is multi-column. The generic checkbox helper expands
            -- hit rects far to the right, which steals clicks from neighboring
            -- renderer checkboxes and the size slider.
            if cb and cb.SetHitRectInsets then
                cb:SetHitRectInsets(0, 0, 0, 0)
            end
            return cb
        end

        local info = body:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        info:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -8)
        info:SetWidth(610)
        info:SetJustifyH("LEFT")
        info:SetText(L["Renderer path: Blizzard is the default native aura block. Checked types below are rendered by Blizzard; unchecked types use MSUF Custom groups. Custom mode disables the native block completely. Blizzard controls final native aura placement; MSUF only shows an approximate locked preview."] or "Renderer path: Blizzard is the default native aura block. Checked types below are rendered by Blizzard; unchecked types use MSUF Custom groups. Custom mode disables the native block completely. Blizzard controls final native aura placement; MSUF only shows an approximate locked preview.")

        local routingLabel = body:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        routingLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 340, -64)
        routingLabel:SetWidth(330)
        routingLabel:SetJustifyH("LEFT")
        routingLabel:SetTextColor(0.74, 0.82, 0.95, 1)
        routingLabel:SetText(L["Rendered by Blizzard"] or "Rendered by Blizzard")

        local routeTip = L["Only applies while Renderer is Blizzard. Checked = Blizzard native block. Unchecked = MSUF Custom for that aura type."] or "Only applies while Renderer is Blizzard. Checked = Blizzard native block. Unchecked = MSUF Custom for that aura type."

        local rendererDD = SDropdown({
            name = "MSUF_GF_BlizzardRendererMode", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = -4, y = -88,
            width = DD_W,
            label = L["Renderer"] or "Renderer",
            items = {
                { key = "BLIZZARD", label = L["Blizzard"] or "Blizzard" },
                { key = "CUSTOM", label = L["Custom"] or "Custom" },
            },
            get = function()
                return AurasRoot().renderer == "CUSTOM" and "CUSTOM" or "BLIZZARD"
            end,
            set = function(_, v)
                AurasRoot().renderer = v == "CUSTOM" and "CUSTOM" or "BLIZZARD"
                BlizzardTypes()
                RequestAuraRefresh()
                if refreshBlizzardControls then refreshBlizzardControls() end
                RefreshAuraOptionControls()
                if v == "BLIZZARD" and AnySpellIndicatorHasIconPlaced() then
                    ShowSIIconBlizzardWarn()
                end
            end,
        })

        local buffChk = RendererCheck({
            name = "MSUF_GF_BlizzardBuffs", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = routeLeftX, y = -88,
            label = L["Use Blizzard: Buffs"] or "Use Blizzard: Buffs",
            tooltip = routeTip,
            get = function() return BlizzardTypes().buffs == true end,
            set = function(_, v) BlizzardTypes().buffs = v and true or false; RequestAuraRefresh(); RefreshAuraOptionControls() end,
        })
        local debuffChk = RendererCheck({
            name = "MSUF_GF_BlizzardDebuffs", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = routeLeftX, y = -148,
            label = L["Use Blizzard: Debuffs"] or "Use Blizzard: Debuffs",
            tooltip = routeTip,
            get = function() return BlizzardTypes().debuffs == true end,
            set = function(_, v) BlizzardTypes().debuffs = v and true or false; RequestAuraRefresh(); RefreshAuraOptionControls() end,
        })
        local dispelChk = RendererCheck({
            name = "MSUF_GF_BlizzardDispels", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = routeLeftX, y = -208,
            label = L["Use Blizzard: Dispels"] or "Use Blizzard: Dispels",
            tooltip = routeTip,
            get = function() return BlizzardTypes().dispels == true end,
            set = function(_, v) BlizzardTypes().dispels = v and true or false; RequestAuraRefresh(); RefreshAuraOptionControls() end,
        })
        local extChk = RendererCheck({
            name = "MSUF_GF_BlizzardExt", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = routeRightX, y = -88,
            label = L["Use Blizzard: Defensives"] or "Use Blizzard: Defensives",
            tooltip = routeTip,
            get = function() return BlizzardTypes().externals == true end,
            set = function(_, v) BlizzardTypes().externals = v and true or false; RequestAuraRefresh(); RefreshAuraOptionControls() end,
        })
        local cdTextChk = RendererCheck({
            name = "MSUF_GF_BlizzardCooldownText", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = routeRightX, y = -148,
            label = L["Blizzard Cooldown Text"] or "Blizzard Cooldown Text",
            tooltip = L["Controls cooldown numbers on Blizzard-rendered aura icons."] or "Controls cooldown numbers on Blizzard-rendered aura icons.",
            get = function() return AurasRoot().blizzardShowCooldownText ~= false end,
            set = function(_, v) AurasRoot().blizzardShowCooldownText = v and true or false; RequestAuraRefresh() end,
        })
        local privateChk = RendererCheck({
            name = "MSUF_GF_BlizzardPrivateAuras", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = routeRightX, y = -208,
            label = L["Use Blizzard: Private"] or "Use Blizzard: Private",
            tooltip = routeTip,
            get = function() return BlizzardTypes().privateAuras == true end,
            set = function(_, v) BlizzardTypes().privateAuras = v and true or false; RequestAuraRefresh(); RefreshAuraOptionControls() end,
        })
        local iconSizeSl = SSlider({
            name = "MSUF_GF_BlizzardIconSize", parent = body, compact = true,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -168,
            min = 8, max = 80, step = 1, width = 200, default = 20,
            get = function() return AurasRoot().blizzardIconSize or 20 end,
            set = function(_, v) AurasRoot().blizzardIconSize = v; RequestAuraRefresh() end,
            formatText = function(v) return string.format(L["Icon size: %d"] or "Icon size: %d", v) end,
        })

        local buffMaxSl = SSlider({
            name = "MSUF_GF_BlizzardBuffMax", parent = body, compact = true,
            anchor = iconSizeSl, x = 0, y = -52,
            min = 0, max = 20, step = 1, width = 200, default = 6,
            get = function() return AG("buff").max or 6 end,
            set = function(_, v) AG("buff").max = v; RequestAuraRefresh() end,
            formatText = function(v) return string.format(L["Buff max: %d"] or "Buff max: %d", v) end,
        })

        local debuffMaxSl = SSlider({
            name = "MSUF_GF_BlizzardDebuffMax", parent = body, compact = true,
            anchor = buffMaxSl, x = 0, y = -52,
            min = 0, max = 20, step = 1, width = 200, default = 6,
            get = function() return AG("debuff").max or 6 end,
            set = function(_, v) AG("debuff").max = v; RequestAuraRefresh() end,
            formatText = function(v) return string.format(L["Debuff max: %d"] or "Debuff max: %d", v) end,
        })

        local orgLabel = body:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        orgLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 340, -268)
        orgLabel:SetText(L["Organization"] or "Organization")

        local orgDD = SDropdown({
            name = "MSUF_GF_BlizzardOrganization", parent = body,
            anchor = orgLabel, anchorPoint = "BOTTOMLEFT", x = -16, y = -6,
            width = 240,
            items = {
                { key = "default", label = L["Default"] or "Default" },
                { key = "BUFFS_TOP_DEBUFFS_BOTTOM", label = L["Buffs Top / Debuffs Bottom"] or "Buffs Top / Debuffs Bottom" },
                { key = "BUFFS_RIGHT_DEBUFFS_LEFT", label = L["Buffs Right / Debuffs Left"] or "Buffs Right / Debuffs Left" },
            },
            get = function() return AurasRoot().blizzardOrganizationType or "default" end,
            set = function(_, v)
                AurasRoot().blizzardOrganizationType = v or "default"
                RequestAuraRefresh()
            end,
        })

        local posLabel = body:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        posLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 340, -350)
        posLabel:SetText(L["Blizzard Position"] or "Blizzard Position")

        local posHint = body:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        posHint:SetPoint("TOPLEFT", posLabel, "BOTTOMLEFT", 0, -8)
        posHint:SetWidth(330)
        posHint:SetJustifyH("LEFT")
        posHint:SetText(L["Locked by Blizzard. MSUF can pass the native renderer settings above, but cannot drag or set the native block position. The preview marks the Blizzard-owned area and enabled aura types; exact placement is decided by Blizzard at runtime."] or "Locked by Blizzard. MSUF can pass the native renderer settings above, but cannot drag or set the native block position. The preview marks the Blizzard-owned area and enabled aura types; exact placement is decided by Blizzard at runtime.")

        refreshBlizzardControls = function()
            local enabled = IsNativeRenderer()
            SetAuraControlsEnabled(enabled, {
                buffChk, debuffChk, dispelChk, extChk, cdTextChk, privateChk,
                iconSizeSl, buffMaxSl, debuffMaxSl, orgDD,
            }, { orgLabel, posLabel, posHint })
        end
        _auraRefreshFns[#_auraRefreshFns + 1] = refreshBlizzardControls
        if rendererDD and rendererDD.HookScript then
            rendererDD:HookScript("OnShow", refreshBlizzardControls)
        end
        if body and body.HookScript then
            body:HookScript("OnShow", refreshBlizzardControls)
        end
        refreshBlizzardControls()
    end

    ----------------------------------------------------------------
    -- Section: Buffs
    ----------------------------------------------------------------
    BuildAuraGroupSection("buff", L["Buffs"], 1490, function(body, prevRow, gk)
        local r = BuildSpellFilterWidgets(body, prevRow, gk)
        return r
    end)

    ----------------------------------------------------------------
    -- Section: Debuffs
    ----------------------------------------------------------------
    BuildAuraGroupSection("debuff", L["Debuffs"], 1630, function(body, prevRow, gk)
        local r = RowCheck(body, prevRow, L["Show Dispel Type Border"], gk, "showDispelBorder")
        r = BuildSpellFilterWidgets(body, r, gk)
        return r
    end)

    ----------------------------------------------------------------
    -- Section: Defensives
    ----------------------------------------------------------------
    BuildAuraGroupSection("externals", L["Defensives"], 890)

    ----------------------------------------------------------------
    -- Section: Text Coloring
    ----------------------------------------------------------------
    do
        local box, body = AddSection(340, L["Text Coloring"] or "Text Coloring", false, "textcolor")

        local r = RowSubLabel(body, nil, L["Cooldown Timer Text"] or "Cooldown Timer Text", 6)

        local infoRow = RowFrame(body, r, 0)
        local infoFS = infoRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        infoFS:SetPoint("LEFT", infoRow, "LEFT", 4, 0)
        infoFS:SetWidth(610)
        infoFS:SetJustifyH("LEFT")
        infoFS:SetText(L["MSUF timer coloring only applies to custom aura icons. Blizzard-rendered cooldown text can be shown or hidden, but not recolored by Safe/Warning/Urgent buckets."] or "MSUF timer coloring only applies to custom aura icons. Blizzard-rendered cooldown text can be shown or hidden, but not recolored by Safe/Warning/Urgent buckets.")
        r = infoRow

        r = RowGeneralCheck(body, r, L["Color aura timers by remaining time"] or "Color aura timers by remaining time",
            "gfAurasCooldownTextUseBuckets", true, 2)

        r = RowTimerColorPreview(body, r, 8)
        r = RowTimerColorSwatches(body, r, 8)
        r = RowDivider(body, r, 8)

        local function BucketsEnabled()
            return GeneralDB().gfAurasCooldownTextUseBuckets ~= false
        end
        local function ClampRange(v, lo, hi)
            if type(v) ~= "number" then v = lo end
            if v < lo then return lo end
            if v > hi then return hi end
            return v
        end
        local function ClampSafe(v)
            return ClampRange(v, 0, 600)
        end
        local function ClampWarn(v)
            local safe = GeneralDB().gfAurasCooldownTextSafeSeconds
            if type(safe) ~= "number" then safe = 60 end
            return math_min(ClampRange(v, 0, 30), safe)
        end
        local function ClampUrgent(v)
            local warn = GeneralDB().gfAurasCooldownTextWarningSeconds
            if type(warn) ~= "number" then warn = 15 end
            return math_min(ClampRange(v, 0, 15), warn)
        end
        local function AfterSafe(v)
            local g = GeneralDB()
            if type(g.gfAurasCooldownTextWarningSeconds) ~= "number" then g.gfAurasCooldownTextWarningSeconds = 15 end
            if type(g.gfAurasCooldownTextUrgentSeconds) ~= "number" then g.gfAurasCooldownTextUrgentSeconds = 5 end
            if g.gfAurasCooldownTextWarningSeconds > v then g.gfAurasCooldownTextWarningSeconds = v end
            if g.gfAurasCooldownTextUrgentSeconds > g.gfAurasCooldownTextWarningSeconds then
                g.gfAurasCooldownTextUrgentSeconds = g.gfAurasCooldownTextWarningSeconds
            end
        end
        local function AfterWarn(v)
            local g = GeneralDB()
            if type(g.gfAurasCooldownTextSafeSeconds) ~= "number" then g.gfAurasCooldownTextSafeSeconds = 60 end
            if type(g.gfAurasCooldownTextUrgentSeconds) ~= "number" then g.gfAurasCooldownTextUrgentSeconds = 5 end
            if v > g.gfAurasCooldownTextSafeSeconds then g.gfAurasCooldownTextWarningSeconds = g.gfAurasCooldownTextSafeSeconds end
            if g.gfAurasCooldownTextUrgentSeconds > v then g.gfAurasCooldownTextUrgentSeconds = v end
        end
        local function AfterUrgent(v)
            local g = GeneralDB()
            if type(g.gfAurasCooldownTextWarningSeconds) ~= "number" then g.gfAurasCooldownTextWarningSeconds = 15 end
            if v > g.gfAurasCooldownTextWarningSeconds then g.gfAurasCooldownTextUrgentSeconds = g.gfAurasCooldownTextWarningSeconds end
        end

        r = RowGeneralSlider(body, r, L["Safe (seconds)"] or "Safe (seconds)",
            "gfAurasCooldownTextSafeSeconds", 0, 600, 1, 60, ClampSafe, 8, AfterSafe)
        r = RowGeneralSlider(body, r, L["Warning (<=)"] or "Warning (<=)",
            "gfAurasCooldownTextWarningSeconds", 0, 30, 1, 15, ClampWarn, 0, AfterWarn, BucketsEnabled)
        r = RowGeneralSlider(body, r, L["Urgent (<=)"] or "Urgent (<=)",
            "gfAurasCooldownTextUrgentSeconds", 0, 15, 1, 5, ClampUrgent, 0, AfterUrgent, BucketsEnabled)

        local function RefreshTextColorControls()
            local enabled = HasCustomIconAuraGroups()
            local rows = { body:GetChildren() }
            for i = 1, #rows do
                local row = rows[i]
                if row == infoRow then
                    SetAuraRowEnabled(row, true)
                else
                    SetAuraRowEnabled(row, enabled)
                end
            end
            if enabled then RefreshTimerColorControlsOnly() end
        end
        _auraRefreshFns[#_auraRefreshFns + 1] = RefreshTextColorControls
        if body.HookScript then body:HookScript("OnShow", RefreshTextColorControls) end
        RefreshTextColorControls()
    end

    ----------------------------------------------------------------
    -- Section: Private Auras
    ----------------------------------------------------------------
    do
        local box, body = AddSection(320, L["Private Auras"], false, "priv")

        local refreshPrivateAuraControls

        local paEnableChk = SCheck({
            name = "MSUF_GF_PAEnable", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = L["Enable Private Auras"],
            get = function(k) return PA().enabled ~= false end,
            set = function(k, v)
                PA().enabled = v
                RequestAuraRefresh()
                if refreshPrivateAuraControls then refreshPrivateAuraControls() end
            end,
        })

        local paMaxSl = SSlider({
            name = "MSUF_GF_PAMax", parent = body, compact = true,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -40,
            min = 1, max = 12, step = 1, width = 200, default = 4,
            get = function(k) return PA().max or 4 end,
            set = function(k, v) PA().max = v; RequestAuraRefresh() end,
            formatText = function(v) return string.format(L["Max: %d"], v) end,
        })

        local paSzSl = SSlider({
            name = "MSUF_GF_PASize", parent = body, compact = true,
            anchor = paMaxSl, x = 0, y = -32,
            min = 8, max = 60, step = 1, width = 200, default = 20,
            get = function(k) return PA().size or 20 end,
            set = function(k, v) PA().size = v; RequestAuraRefresh() end,
            formatText = function(v) return string.format(L["Size: %d"], v) end,
        })

        local paDirDd = SDropdown({
            name = "MSUF_GF_PADirection", parent = body,
            anchor = paSzSl, x = -16, y = -10, width = 140,
            items = DIRECTION4,
            get = function(k) return PA().direction or "LEFT" end,
            set = function(k, v) PA().direction = v; RequestAuraRefresh() end,
        })

        local paAnchorDd = SDropdown({
            name = "MSUF_GF_PAAnchor", parent = body,
            anchor = paSzSl, x = 150, y = -10, width = 140,
            items = ANCHOR9,
            get = function(k) return PA().anchor or "TOPRIGHT" end,
            set = function(k, v) PA().anchor = v; RequestAuraRefresh() end,
        })

        local paXSl = SSlider({
            name = "MSUF_GF_PAX", parent = body, compact = true,
            anchor = paSzSl, x = 0, y = -76,
            min = -200, max = 200, step = 1, width = 200, default = 0,
            get = function(k) return PA().x or 0 end,
            set = function(k, v) PA().x = v; RequestAuraRefresh() end,
            formatText = function(v) return string.format("X: %d", v) end,
        })

        local paYSl = SSlider({
            name = "MSUF_GF_PAY", parent = body, compact = true,
            anchor = paXSl, x = 0, y = -32,
            min = -200, max = 200, step = 1, width = 200, default = 0,
            get = function(k) return PA().y or 0 end,
            set = function(k, v) PA().y = v; RequestAuraRefresh() end,
            formatText = function(v) return string.format("Y: %d", v) end,
        })

        local paLayerSl = SSlider({
            name = "MSUF_GF_PALayer", parent = body, compact = true,
            anchor = paYSl, x = 0, y = -32,
            min = 1, max = 15, step = 1, width = 200, default = 8,
            get = function(k) return PA().layer or 8 end,
            set = function(k, v) PA().layer = v; RequestAuraRefresh() end,
            formatText = function(v) return string.format(L["Layer: %d"], v) end,
        })

        local paCdChk = SCheck({
            name = "MSUF_GF_PACd", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 380, y = -40,
            label = L["Show Countdown Frame"],
            get = function(k) return PA().showCountdown ~= false end,
            set = function(k, v) PA().showCountdown = v; RequestAuraRefresh() end,
        })

        local paNumChk = SCheck({
            name = "MSUF_GF_PANumbers", parent = body,
            anchor = paCdChk, x = 0, y = -24,
            label = L["Show Countdown Numbers"],
            get = function(k) return PA().showNumbers == true end,
            set = function(k, v) PA().showNumbers = v; RequestAuraRefresh() end,
        })

        local paDispelChk = SCheck({
            name = "MSUF_GF_PADispelType", parent = body,
            anchor = paNumChk, x = 0, y = -24,
            label = L["Show Private Dispel Type"] or "Show Private Dispel Type",
            get = function(k) return PA().showDispelType == true end,
            set = function(k, v) PA().showDispelType = v; RequestAuraRefresh() end,
        })

        refreshPrivateAuraControls = function()
            local enabled = PA().enabled ~= false
            local nativePrivate = IsNativeAuraType("privateAuras")
            local customPrivateActive = not nativePrivate

            SetAuraControlsEnabled(enabled and (nativePrivate or customPrivateActive), {
                paMaxSl,
            })
            SetAuraControlsEnabled(enabled and customPrivateActive, {
                paSzSl, paDirDd, paAnchorDd, paXSl, paYSl, paLayerSl,
                paCdChk, paNumChk, paDispelChk,
            })
        end
        _auraRefreshFns[#_auraRefreshFns + 1] = function()
            if refreshPrivateAuraControls then refreshPrivateAuraControls() end
        end
        if body.HookScript then body:HookScript("OnShow", function() if refreshPrivateAuraControls then refreshPrivateAuraControls() end end) end
        refreshPrivateAuraControls()
    end

    ----------------------------------------------------------------
    -- Section: Corner Indicators
    ----------------------------------------------------------------
    do
        local box, body = AddSection(600, L["Corner Indicators"] or "Corner Indicators", false, "ci")

        -- Helper: read/write directly from conf (not auras sub-table)
        local function CIV(key)
            local conf = GF.GetConf(K())
            return conf and conf[key]
        end
        local function CIW(key, val)
            local conf = GF.GetConf(K())
            if conf then
                if conf[key] == val then return end
                conf[key] = val
            end
            RequestVisualRefresh()
        end

        -- Enable toggle
        local enChk = SCheck({
            name = "MSUF_GF_CIEnable", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = L["Enable"] or "Enable",
            get = function() return CIV("ciEnabled") ~= false end,
            set = function(_, v) CIW("ciEnabled", v and true or false) end,
        })

        -- Slot category items (live source: GF.CI_CATEGORIES, fallback below)
        local CI_CATS = GF.CI_CATEGORIES or {
            { key = "none",   label = "None"          },
            { key = "dispel", label = "Dispellable"   },
            { key = "aggro",  label = "Aggro/Threat"  },
            { key = "custom", label = "Custom Spell"  },
        }
        local CI_FILTERS = GF.CI_CUSTOM_FILTERS or {
            { key = "HELPFUL|PLAYER", label = "Buff (cast by me)",   secretSafe = true  },
            { key = "HELPFUL",        label = "Buff (any caster)",   secretSafe = false },
            { key = "HARMFUL|PLAYER", label = "Debuff (cast by me)", secretSafe = true  },
            { key = "HARMFUL",        label = "Debuff (any caster)", secretSafe = false },
        }
        local CI_MODES = GF.CI_CUSTOM_MODES or {
            { key = "present", label = "Show when present" },
            { key = "missing", label = "Show when missing" },
        }

        -- Forward-decls so slot dropdown OnClick can update tab visuals + editor
        -- when the user changes a slot's category. These are wired up by the
        -- Custom Spell Editor block further below.
        local _ciRefreshTabs, _ciRefreshEditor

        -- Slot labels for display
        local SLOT_LABELS = {
            TL = L["Top Left"]     or "Top Left",
            TR = L["Top Right"]    or "Top Right",
            BL = L["Bottom Left"]  or "Bottom Left",
            BR = L["Bottom Right"] or "Bottom Right",
            C  = L["Center"]       or "Center",
        }

        -- Build 5 slot dropdowns
        local prevRow = nil
        for idx, sk in ipairs(GF.CI_SLOT_KEYS or {"TL","TR","BL","BR","C"}) do
            local dbKey = "ciSlot" .. sk
            local row = RowFrame(body, prevRow, idx == 1 and 36 or 2)
            RowLabel(row, SLOT_LABELS[sk] or sk)
            local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
            btn:SetSize(DD_W, 20)
            btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            btn:SetBackdropColor(0.10, 0.14, 0.22, 1)
            btn:SetBackdropBorderColor(0.20, 0.30, 0.50, 0.7)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
            fs:SetTextColor(0.40, 0.67, 0.93, 1)
            local function RefreshDD()
                local cur = CIV(dbKey) or "none"
                for _, item in ipairs(CI_CATS) do
                    if item.key == cur then fs:SetText(item.label or item.key); return end
                end
                fs:SetText(tostring(cur))
            end
            RefreshDD()
            btn:SetScript("OnClick", function()
                local cur = CIV(dbKey) or "none"
                local nextIdx = 1
                for ci, item in ipairs(CI_CATS) do
                    if item.key == cur then nextIdx = ci + 1; break end
                end
                if nextIdx > #CI_CATS then nextIdx = 1 end
                CIW(dbKey, CI_CATS[nextIdx].key)
                RefreshDD()
                if _ciRefreshTabs then _ciRefreshTabs() end
                if _ciRefreshEditor then _ciRefreshEditor() end
            end)
            _auraRefreshFns[#_auraRefreshFns + 1] = RefreshDD
            prevRow = row
        end

        -- Size slider
        do
            local row = RowFrame(body, prevRow, 6)
            RowLabel(row, L["Icon Size: %d"] and string.format(L["Icon Size: %d"], 8) or "Size")
            local valFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            valFS:SetJustifyH("RIGHT")
            local sl = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
            sl:SetSize(SL_W, 14)
            sl:SetPoint("RIGHT", valFS, "LEFT", -8, 0)
            sl:SetMinMaxValues(4, 20)
            sl:SetValueStep(1)
            sl:SetObeyStepOnDrag(true)
            sl:SetValue(CIV("ciSize") or 8)
            if sl.Text then sl.Text:SetText("") end
            if sl.Low  then sl.Low:SetText("")  end
            if sl.High then sl.High:SetText("") end
            sl._msufLastValue = math_floor((CIV("ciSize") or 8) + 0.5)
            valFS:SetText(tostring(sl._msufLastValue))
            sl:SetScript("OnValueChanged", function(self, v)
                if self._msufSkip then return end
                v = math_floor(v + 0.5)
                valFS:SetText(tostring(v))
                if self._msufLastValue == v then return end
                self._msufLastValue = v
                CIW("ciSize", v)
            end)
            _auraRefreshFns[#_auraRefreshFns + 1] = function()
                local v = math_floor((CIV("ciSize") or 8) + 0.5)
                sl._msufSkip = true
                sl:SetValue(v)
                sl._msufSkip = false
                sl._msufLastValue = v
                valFS:SetText(tostring(v))
            end
            local _styleSl = _G.MSUF_StyleSlider or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
            if _styleSl then _styleSl(sl) end
            prevRow = row
        end

        -- Alpha slider
        do
            local row = RowFrame(body, prevRow, 2)
            RowLabel(row, "Alpha")
            local valFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            valFS:SetJustifyH("RIGHT")
            local sl = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
            sl:SetSize(SL_W, 14)
            sl:SetPoint("RIGHT", valFS, "LEFT", -8, 0)
            sl:SetMinMaxValues(10, 100)
            sl:SetValueStep(5)
            sl:SetObeyStepOnDrag(true)
            local cur = math_floor(((CIV("ciAlpha") or 1.0) * 100) + 0.5)
            sl:SetValue(cur)
            if sl.Text then sl.Text:SetText("") end
            if sl.Low  then sl.Low:SetText("")  end
            if sl.High then sl.High:SetText("") end
            valFS:SetText(tostring(cur) .. "%")
            sl._msufLastValue = cur
            sl:SetScript("OnValueChanged", function(self, v)
                if self._msufSkip then return end
                v = math_floor(v + 0.5)
                valFS:SetText(tostring(v) .. "%")
                if self._msufLastValue == v then return end
                self._msufLastValue = v
                CIW("ciAlpha", v / 100)
            end)
            _auraRefreshFns[#_auraRefreshFns + 1] = function()
                local v = math_floor(((CIV("ciAlpha") or 1.0) * 100) + 0.5)
                sl._msufSkip = true
                sl:SetValue(v)
                sl._msufSkip = false
                sl._msufLastValue = v
                valFS:SetText(tostring(v) .. "%")
            end
            local _styleSl = _G.MSUF_StyleSlider or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
            if _styleSl then _styleSl(sl) end
            prevRow = row
        end

        -- ─────────────────────────────────────────────────────────────
        -- Custom Spell Editor: tabs for TL/TR/BL/BR/C, shared editor body.
        -- Active tab edits its slot's ciCustomXX = { spells, mode, filter, r, g, b }.
        -- Tabs visually highlight when the slot is set to "custom"; clicking a
        -- non-custom-slot tab is allowed (lets user pre-configure before flipping
        -- the dropdown). Default config is created lazily on first edit.
        -- ─────────────────────────────────────────────────────────────
        do
            -- Section divider
            local hdr = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hdr:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 6, -10)
            hdr:SetText("|cffaaaaaaCustom Spell Configuration|r")

            -- Tab strip
            local tabStrip = CreateFrame("Frame", nil, body)
            tabStrip:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -4)
            tabStrip:SetSize(300, 22)

            local SLOT_TAB_KEYS = GF.CI_SLOT_KEYS or { "TL", "TR", "BL", "BR", "C" }
            local activeSlot = SLOT_TAB_KEYS[1] or "TL"
            local tabBtns = {}

            -- Forward decls (tab refresh + body refresh need each other)
            local RefreshEditorBody, RefreshTabs

            -- Helper: get/lazy-create the custom config table for a slot.
            -- TYPE-GUARD: any non-table value (legacy number, corrupt state)
            -- is treated as nil. createIfMissing replaces it with a default table.
            local function GetCustomConf(slotKey, createIfMissing)
                local conf = GF.GetConf(K())
                if not conf then return nil end
                local k = "ciCustom" .. slotKey
                local cc = conf[k]
                if type(cc) ~= "table" then
                    cc = nil
                    if createIfMissing then
                        cc = {
                            spells = "",
                            mode   = "present",
                            filter = "HELPFUL|PLAYER",
                            r = 0.40, g = 1.00, b = 0.40,
                        }
                        conf[k] = cc
                    else
                        -- Stale non-table value present? Wipe so future reads see nil.
                        if conf[k] ~= nil then conf[k] = nil end
                    end
                end
                return cc
            end

            -- Build 5 tab buttons (TL/TR/BL/BR/C)
            local TAB_W, TAB_H = 30, 20
            for i, sk in ipairs(SLOT_TAB_KEYS) do
                local b = CreateFrame("Button", nil, tabStrip, "BackdropTemplate")
                b:SetSize(TAB_W, TAB_H)
                b:SetPoint("LEFT", tabStrip, "LEFT", (i - 1) * (TAB_W + 4), 0)
                b:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("CENTER", b, "CENTER", 0, 0)
                fs:SetText(sk)
                b._fs = fs
                b._slotKey = sk
                b:SetScript("OnClick", function()
                    activeSlot = sk
                    if RefreshTabs then RefreshTabs() end
                    if RefreshEditorBody then RefreshEditorBody() end
                end)
                tabBtns[i] = b
            end

            RefreshTabs = function()
                for _, b in ipairs(tabBtns) do
                    local sk = b._slotKey
                    local cat = CIV("ciSlot" .. sk) or "none"
                    local isActive = (sk == activeSlot)
                    local isCustom = (cat == "custom")
                    if isActive then
                        b:SetBackdropColor(0.20, 0.40, 0.65, 1)
                        b:SetBackdropBorderColor(0.45, 0.75, 1.00, 1)
                    elseif isCustom then
                        b:SetBackdropColor(0.10, 0.18, 0.28, 1)
                        b:SetBackdropBorderColor(0.30, 0.55, 0.85, 0.8)
                    else
                        b:SetBackdropColor(0.08, 0.10, 0.14, 1)
                        b:SetBackdropBorderColor(0.20, 0.22, 0.28, 0.6)
                    end
                    if b._fs then
                        if isCustom then
                            b._fs:SetTextColor(0.80, 0.95, 1.00, 1)
                        else
                            b._fs:SetTextColor(0.55, 0.55, 0.60, 1)
                        end
                    end
                end
            end
            _auraRefreshFns[#_auraRefreshFns + 1] = RefreshTabs

            -- Editor body (single set of widgets, repointed by RefreshEditorBody)
            -- LAYOUT: explicit Frame wrappers with fixed sizes to guarantee
            -- vertical separation from the tab strip (no Texture-as-anchor
            -- chain — those can render unreliably in some Blizzard builds).

            -- Subtle horizontal separator below the tab strip (visual polish).
            local tabSep = body:CreateTexture(nil, "ARTWORK")
            tabSep:SetColorTexture(0.30, 0.40, 0.55, 0.25)
            tabSep:SetSize(540, 1)
            tabSep:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -6)

            -- Status wrapper Frame: gives statusFS a deterministic geometry
            -- (width + minimum height) so the layout never collapses onto
            -- the tab row. Fixed 540×34 covers two wrapped lines comfortably.
            local statusBox = CreateFrame("Frame", nil, body)
            statusBox:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -16)
            statusBox:SetSize(540, 34)

            local statusFS = statusBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            statusFS:SetAllPoints(statusBox)
            statusFS:SetJustifyH("LEFT")
            statusFS:SetJustifyV("TOP")
            statusFS:SetWordWrap(true)
            statusFS:SetNonSpaceWrap(true)

            local editorBody = CreateFrame("Frame", nil, body)
            editorBody:SetPoint("TOPLEFT", statusBox, "BOTTOMLEFT", 0, -10)
            editorBody:SetSize(540, 130)

            -- Spell IDs editbox
            local spLbl = editorBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            spLbl:SetPoint("TOPLEFT", editorBody, "TOPLEFT", 4, -2)
            spLbl:SetText("Spell IDs (comma-separated):")
            local spEB = CreateFrame("EditBox", "MSUF_GF_CICustomSpells", editorBody, "InputBoxTemplate")
            spEB:SetSize(380, 18)
            spEB:SetPoint("TOPLEFT", spLbl, "BOTTOMLEFT", 6, -4)
            spEB:SetAutoFocus(false)
            spEB:SetFontObject(GameFontHighlightSmall)
            spEB:SetTextColor(1, 1, 1, 1)
            spEB:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            spEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            spEB:SetScript("OnEditFocusLost", function(self)
                local cc = GetCustomConf(activeSlot, true)
                if cc then
                    cc.spells = self:GetText() or ""
                    cc._setStamp = nil
                    cc._set = nil
                end
                RequestVisualRefresh()
            end)

            -- Mode toggle button (present / missing)
            local modeLbl = editorBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            modeLbl:SetPoint("TOPLEFT", spEB, "BOTTOMLEFT", -6, -12)
            modeLbl:SetText("When:")
            local modeBtn = CreateFrame("Button", nil, editorBody, "BackdropTemplate")
            modeBtn:SetSize(160, 20)
            modeBtn:SetPoint("LEFT", modeLbl, "RIGHT", 8, 0)
            modeBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            modeBtn:SetBackdropColor(0.10, 0.14, 0.22, 1)
            modeBtn:SetBackdropBorderColor(0.20, 0.30, 0.50, 0.7)
            local modeFS = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            modeFS:SetPoint("CENTER", modeBtn, "CENTER", 0, 0)
            modeFS:SetTextColor(0.40, 0.67, 0.93, 1)
            modeBtn:SetScript("OnClick", function()
                local cc = GetCustomConf(activeSlot, true)
                if not cc then return end
                local cur = cc.mode or "present"
                local nextIdx = 1
                for ci, item in ipairs(CI_MODES) do
                    if item.key == cur then nextIdx = ci + 1; break end
                end
                if nextIdx > #CI_MODES then nextIdx = 1 end
                cc.mode = CI_MODES[nextIdx].key
                if RefreshEditorBody then RefreshEditorBody() end
                RequestVisualRefresh()
            end)

            -- Filter dropdown button
            local filtLbl = editorBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            filtLbl:SetPoint("TOPLEFT", modeLbl, "BOTTOMLEFT", 0, -10)
            filtLbl:SetText("Filter:")
            local filtBtn = CreateFrame("Button", nil, editorBody, "BackdropTemplate")
            filtBtn:SetSize(180, 20)
            filtBtn:SetPoint("LEFT", filtLbl, "RIGHT", 8, 0)
            filtBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            filtBtn:SetBackdropColor(0.10, 0.14, 0.22, 1)
            filtBtn:SetBackdropBorderColor(0.20, 0.30, 0.50, 0.7)
            local filtFS = filtBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            filtFS:SetPoint("CENTER", filtBtn, "CENTER", 0, 0)
            filtFS:SetTextColor(0.40, 0.67, 0.93, 1)
            filtBtn:SetScript("OnClick", function()
                local cc = GetCustomConf(activeSlot, true)
                if not cc then return end
                local cur = cc.filter or "HELPFUL|PLAYER"
                local nextIdx = 1
                for ci, item in ipairs(CI_FILTERS) do
                    if item.key == cur then nextIdx = ci + 1; break end
                end
                if nextIdx > #CI_FILTERS then nextIdx = 1 end
                cc.filter = CI_FILTERS[nextIdx].key
                if RefreshEditorBody then RefreshEditorBody() end
                RequestVisualRefresh()
            end)

            -- Color swatch
            local colLbl = editorBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            colLbl:SetPoint("TOPLEFT", filtLbl, "BOTTOMLEFT", 0, -10)
            colLbl:SetText("Color:")
            local colSw = CreateFrame("Button", nil, editorBody)
            colSw:SetSize(40, 14)
            colSw:SetPoint("LEFT", colLbl, "RIGHT", 8, 0)
            local colTex = colSw:CreateTexture(nil, "ARTWORK")
            colTex:SetAllPoints()
            colSw:SetScript("OnClick", function()
                local cc = GetCustomConf(activeSlot, true)
                if not cc then return end
                if OpenColorPicker then
                    OpenColorPicker(cc.r or 0.4, cc.g or 1.0, cc.b or 0.4, function(r, g, b)
                        cc.r, cc.g, cc.b = r, g, b
                        colTex:SetColorTexture(r, g, b, 1)
                        RequestVisualRefresh()
                    end)
                end
            end)

            -- Warning + secret-safety hint (multi-line, dim)
            local warnFS = editorBody:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            warnFS:SetPoint("TOPLEFT", colLbl, "BOTTOMLEFT", 0, -12)
            warnFS:SetWidth(530)
            warnFS:SetJustifyH("LEFT")
            warnFS:SetWordWrap(true)
            warnFS:SetNonSpaceWrap(true)

            RefreshEditorBody = function()
                local cc = GetCustomConf(activeSlot, false)
                local cat = CIV("ciSlot" .. activeSlot) or "none"

                -- Status line above the editor
                if cat == "custom" then
                    statusFS:SetText("Editing slot " .. activeSlot .. "  (active)")
                else
                    statusFS:SetText("Slot " .. activeSlot .. " is set to '" .. cat .. "'. Set to 'Custom Spell' in the dropdown above to activate this configuration.")
                end

                -- Spells text
                spEB:SetText((cc and cc.spells) or "")

                -- Mode label
                local modeKey = (cc and cc.mode) or "present"
                local modeLabel = modeKey
                for _, m in ipairs(CI_MODES) do if m.key == modeKey then modeLabel = m.label; break end end
                modeFS:SetText(modeLabel)

                -- Filter label + secret-safe color
                local filtKey = (cc and cc.filter) or "HELPFUL|PLAYER"
                local filtLabel, filtSafe = filtKey, true
                for _, ff in ipairs(CI_FILTERS) do
                    if ff.key == filtKey then filtLabel = ff.label; filtSafe = ff.secretSafe; break end
                end
                filtFS:SetText(filtLabel)
                if filtSafe then
                    filtFS:SetTextColor(0.40, 0.85, 0.50, 1)
                else
                    filtFS:SetTextColor(1.00, 0.70, 0.30, 1)
                end

                -- Color swatch
                local cr, cg, cb = (cc and cc.r) or 0.4, (cc and cc.g) or 1.0, (cc and cc.b) or 0.4
                colTex:SetColorTexture(cr, cg, cb, 1)

                -- Warning text — depends on selected filter
                if filtSafe then
                    warnFS:SetText("|cff666666The selected filter is reliable in 12.0: only the local player's casts are tracked, and their spell IDs are always visible.|r")
                else
                    warnFS:SetText("|cffffaa55Warning:|r |cff999999This filter scans buffs/debuffs from any caster. Midnight 12.0 marks other players' aura spell IDs as 'secret', so most matches will be silently skipped. Use this filter only for spells you've verified are visible (e.g. permanent raid buffs you cast yourself).|r")
                end
            end
            _auraRefreshFns[#_auraRefreshFns + 1] = RefreshEditorBody

            -- Bind to outer-scope refs so slot dropdown OnClick can trigger us.
            _ciRefreshTabs   = RefreshTabs
            _ciRefreshEditor = RefreshEditorBody

            RefreshTabs()
            RefreshEditorBody()

            -- Refresh on slot dropdown changes (chain into prev RefreshDDs).
            -- Done by piggy-backing the global _auraRefreshFns trigger; the
            -- existing dropdown OnClick handlers fire GF.RefreshVisuals which
            -- ultimately re-runs the refresh fn list.
        end
    end

    ----------------------------------------------------------------
    -- Masque (requires Masque addon)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(100, L["Masque"] or "Masque", false, "masque")

        local masqueChk = SCheck({
            name = "MSUF_GF_MasqueEnabled", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = L["Enable Masque Skin"] or "Enable Masque Skin",
            get = function(k)
                local conf = GF.GetConf(K())
                return conf and conf.masqueEnabled == true
            end,
            set = function(k, v)
                local conf = GF.GetConf(K())
                if conf then conf.masqueEnabled = v and true or false end
                if GF.Masque and GF.Masque.ReskinAllIcons then GF.Masque.ReskinAllIcons() end
                RequestVisualRefresh()
            end,
        })

        local infoFS = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        infoFS:SetPoint("TOPLEFT", masqueChk, "BOTTOMLEFT", 6, -4)
        infoFS:SetText("|cff888888" .. (L["Applies to Buffs, Debuffs & Externals icons.\nCount text is managed by MSUF (not Masque)."] or "Applies to Buffs, Debuffs & Externals icons.\nCount text is managed by MSUF (not Masque)."))

        local function RefreshMasqueControls()
            local enabled = HasCustomIconAuraGroups()
            SetAuraControlsEnabled(enabled, { masqueChk }, { infoFS })
        end
        _auraRefreshFns[#_auraRefreshFns + 1] = RefreshMasqueControls
        if body.HookScript then body:HookScript("OnShow", RefreshMasqueControls) end
        RefreshMasqueControls()
    end

    ----------------------------------------------------------------
    -- Aura Utilities (copy + dynamic scale + import/export)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(260, L["Aura Utilities"], false, "autil")

        -- Dynamic content scale
        local dynScaleChk = SCheck({
            name = "MSUF_GF_AuraDynScale", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = L["Auto-shrink icons in large raids (16+)"],
            get = function(k)
                local conf = GF.GetConf(K())
                return conf and conf.auras and conf.auras.dynamicScale == true
            end,
            set = function(k, v)
                local conf = GF.GetConf(K())
                if conf and conf.auras then
                    conf.auras.dynamicScale = v and true or false
                end
                RequestVisualRefresh()
            end,
        })

        -- Deep copy utility
        local function DeepCopy(src)
            if not src then return src end
            local dst = {}
            for k, v in pairs(src) do dst[k] = DeepCopy(v) end
            return dst
        end

        local function DoCopy(srcKind, dstKind)
            local srcConf = GF.GetConf(srcKind)
            local dstConf = GF.GetConf(dstKind)
            if not srcConf or not dstConf then return end
            if srcConf.auras then dstConf.auras = DeepCopy(srcConf.auras) end
            if srcConf.privateAuras then dstConf.privateAuras = DeepCopy(srcConf.privateAuras) end
            if srcConf.spellIndicators then dstConf.spellIndicators = DeepCopy(srcConf.spellIndicators) end
            -- Corner Indicators
            for _, ck in ipairs({"ciEnabled","ciSize","ciAlpha",
                "ciSlotTL","ciSlotTR","ciSlotBL","ciSlotBR","ciSlotC"}) do
                if srcConf[ck] ~= nil then dstConf[ck] = srcConf[ck] end
            end
            RequestVisualRefresh()
        end

        local copyLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        copyLbl:SetPoint("TOPLEFT", dynScaleChk, "BOTTOMLEFT", 6, -8)
        copyLbl:SetText(L["Copy All Aura Settings"])
        copyLbl:SetTextColor(1, 0.82, 0)

        local copyButtons = {
            { src = "party",      dst = "raid",       label = L["Party -> Raid"] },
            { src = "party",      dst = "mythicraid", label = L["Party -> Mythic Raid"] or "Party -> Mythic Raid" },
            { src = "raid",       dst = "party",      label = L["Raid -> Party"] },
            { src = "raid",       dst = "mythicraid", label = L["Raid -> Mythic Raid"] or "Raid -> Mythic Raid" },
            { src = "mythicraid", dst = "party",      label = L["Mythic Raid -> Party"] or "Mythic Raid -> Party" },
            { src = "mythicraid", dst = "raid",       label = L["Mythic Raid -> Raid"] or "Mythic Raid -> Raid" },
        }
        local copyBtnRefs = {}
        for idx, spec in ipairs(copyButtons) do
            local btn = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
            btn:SetSize(180, 24)
            local row = math.floor((idx - 1) / 2)
            local col = (idx - 1) % 2
            if idx == 1 then
                btn:SetPoint("TOPLEFT", copyLbl, "BOTTOMLEFT", 0, -6)
            else
                btn:SetPoint("TOPLEFT", copyLbl, "BOTTOMLEFT", col * 192, -6 - row * 28)
            end
            btn:SetText(spec.label)
            btn:SetScript("OnClick", function() DoCopy(spec.src, spec.dst) end)
            copyBtnRefs[#copyBtnRefs + 1] = btn
        end

        -- Import/Export section
        local ioLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ioLbl:SetPoint("TOPLEFT", copyBtnRefs[5] or copyBtnRefs[#copyBtnRefs], "BOTTOMLEFT", 0, -16)
        ioLbl:SetText(L["Import / Export Spell Config"])
        ioLbl:SetTextColor(1, 0.82, 0)

        -- Export button
        local btnExport = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
        btnExport:SetSize(130, 24)
        btnExport:SetPoint("TOPLEFT", ioLbl, "BOTTOMLEFT", 0, -6)
        btnExport:SetText(L["Export"])
        btnExport:SetScript("OnClick", function()
            local siCfg = SIC()
            local specKey
            if (siCfg.spec or "auto") == "auto" then
                specKey = SI and SI.GetPlayerSpec and SI.GetPlayerSpec()
            elseif siCfg.spec == "multi" then
                -- Export first enabled spec in multi mode
                if siCfg.multiSpecs then
                    for sk in pairs(siCfg.multiSpecs) do specKey = sk; break end
                end
            else
                specKey = siCfg.spec
            end
            if not specKey then
                print("|cffff6600MSUF:|r " .. L["No spec selected for export."])
                return
            end
            local str = SI.ExportConfig(siCfg, specKey)
            if not str then
                print("|cffff6600MSUF:|r " .. L["Nothing to export."])
                return
            end
            -- Show copy dialog
            local dlg = StaticPopup_Show("MSUF_SI_EXPORT")
            if dlg and dlg.editBox then
                dlg.editBox:SetText(str)
                dlg.editBox:HighlightText()
                dlg.editBox:SetFocus()
            end
        end)

        -- Import button
        local btnImport = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
        btnImport:SetSize(130, 24)
        btnImport:SetPoint("LEFT", btnExport, "RIGHT", 12, 0)
        btnImport:SetText(L["Import"])
        btnImport:SetScript("OnClick", function()
            StaticPopup_Show("MSUF_SI_IMPORT")
        end)

        -- Register StaticPopup dialogs (cold-path, once)
        if not StaticPopupDialogs["MSUF_SI_EXPORT"] then
            StaticPopupDialogs["MSUF_SI_EXPORT"] = {
                text = L["Copy the string below (Ctrl+A, Ctrl+C):"],
                button1 = OKAY,
                hasEditBox = true,
                editBoxWidth = 350,
                OnShow = function(self) self.editBox:SetFocus() end,
                EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
        end
        if not StaticPopupDialogs["MSUF_SI_IMPORT"] then
            StaticPopupDialogs["MSUF_SI_IMPORT"] = {
                text = L["Paste spell config string below:"],
                button1 = L["Import"],
                button2 = CANCEL,
                hasEditBox = true,
                editBoxWidth = 350,
                OnAccept = function(self)
                    local str = self.editBox:GetText()
                    local siCfg = SIC()
                    local ok, sk = SI.ImportConfig(siCfg, str)
                    if ok then
                        print("|cff00ff00MSUF:|r " .. L["Imported spell config for"] .. " " .. (sk or "?"))
                        RequestVisualRefresh()
                    else
                        print("|cffff6600MSUF:|r " .. L["Import failed. Invalid string."])
                    end
                end,
                EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
        end
    end

    -- Register compact/manual refresh functions after every section has
    -- appended its callbacks. Corner Indicator rows are built later than the
    -- aura-group rows and were previously missed by the early registration.
    for i = 1, #_auraRefreshFns do
        refreshFns[#refreshFns + 1] = _auraRefreshFns[i]
    end

end

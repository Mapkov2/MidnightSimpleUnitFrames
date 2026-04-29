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

------------------------------------------------------------------------
-- Injector: called from MSUF_Options_GF.lua
------------------------------------------------------------------------
function GF.BuildAuraOptionsSections(AddSection, SCheck, SSlider, SDropdown, K, TrackRefresh, MakeColorSwatch, OpenColorPicker, refreshFns)
    if not UI then UI = ns.UI end

    local function AG(groupKey)
        local conf = GF.GetConf(K())
        if not conf.auras then conf.auras = {} end
        local g = conf.auras[groupKey]
        if not g then g = {}; conf.auras[groupKey] = g end
        return g
    end
    local function AV(groupKey, key) return AG(groupKey)[key] end
    local function AW(groupKey, key, val)
        AG(groupKey)[key] = val
        GF.RefreshVisuals()
    end

    local function PA()
        local conf = GF.GetConf(K())
        if not conf.privateAuras then conf.privateAuras = {} end
        return conf.privateAuras
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
        cb:SetSize(22, 22)
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
        if _G.MSUF_StyleCheckmark then _G.MSUF_StyleCheckmark(cb) end
        if _G.MSUF_StyleToggleText then _G.MSUF_StyleToggleText(cb) end
        if cb._msufToggleUpdate then cb._msufToggleUpdate() end
        _auraRefreshFns[#_auraRefreshFns + 1] = function()
            cb:SetChecked(AV(gk, key) ~= false)
            if cb._msufToggleUpdate then cb._msufToggleUpdate() end
        end
        row._ctrl = cb
        return row
    end

    local function RowSlider(parent, prevRow, label, gk, key, lo, hi, step, def, topOfs)
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
        sl:SetValue(AV(gk, key) or def)
        -- Hide default slider text
        if sl.Text then sl.Text:SetText("") end
        if sl.Low  then sl.Low:SetText("")  end
        if sl.High then sl.High:SetText("") end
        valFS:SetText(tostring(math_floor((AV(gk, key) or def) + 0.5)))
        sl:SetScript("OnValueChanged", function(self, v)
            v = math_floor(v + 0.5)
            valFS:SetText(tostring(v))
            AW(gk, key, v)
        end)
        _auraRefreshFns[#_auraRefreshFns + 1] = function()
            local v = AV(gk, key) or def
            sl:SetValue(v)
            valFS:SetText(tostring(math_floor(v + 0.5)))
        end
        local _styleSl = _G.MSUF_StyleSlider or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
        if _styleSl then _styleSl(sl) end
        row._ctrl = sl
        return row
    end

    local function RowDropdown(parent, prevRow, label, gk, key, items, def, topOfs)
        local row = RowFrame(parent, prevRow, topOfs)
        RowLabel(row, label)
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
            local cur = AV(gk, key) or def
            for _, item in ipairs(items) do
                if item.key == cur then fs:SetText(item.label or item.key); return end
            end
            fs:SetText(tostring(cur))
        end
        RefreshLabel()
        -- Simple click-cycle through items
        btn:SetScript("OnClick", function()
            local cur = AV(gk, key) or def
            local idx = 1
            for i, item in ipairs(items) do
                if item.key == cur then idx = i; break end
            end
            idx = (idx % #items) + 1
            AW(gk, key, items[idx].key)
            RefreshLabel()
        end)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.35, 0.50, 0.75, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            for _, item in ipairs(items) do
                local cur = AV(gk, key) or def
                local pre = item.key == cur and "|cff66aaee> " or "  "
                GameTooltip:AddLine(pre .. (item.label or item.key), 0.8, 0.8, 0.8)
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
            cb:SetSize(20, 20)
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
                GF.RefreshVisuals()
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
            if _G.MSUF_StyleCheckmark then _G.MSUF_StyleCheckmark(cb) end
            _auraRefreshFns[#_auraRefreshFns + 1] = function()
                cb:SetChecked(GetCatState())
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
        r = RowDropdown(body, r, L["Anchor"], gk, "anchor", ANCHOR9, "BOTTOMLEFT")
        r = RowDropdown(body, r, L["Growth"], gk, "growth", GROWTH8, "RIGHTDOWN")
        r = RowValue(body, r, L["Offset X / Y"], function()
            return tostring(AV(gk, "x") or 0) .. " / " .. tostring(AV(gk, "y") or 0)
        end)

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
        r = RowSubLabel(body, r, L["Cooldown Text"] or "Cooldown Text")
        r = RowCheck(body, r, L["Show Cooldown Text"] or "Show Cooldown Text", gk, "showCooldown", 0)
        r = RowSlider(body, r, L["Font size"] or "Font size", gk, "cooldownSize", 6, 24, 1, 8)
        r = RowDropdown(body, r, L["Anchor"] or "Anchor", gk, "cooldownAnchor", ANCHOR9, "CENTER")
        r = RowSlider(body, r, L["Offset X"] or "Offset X", gk, "cooldownOffsetX", -20, 20, 1, 0)
        r = RowSlider(body, r, L["Offset Y"] or "Offset Y", gk, "cooldownOffsetY", -20, 20, 1, 0)

        r = RowDivider(body, r)
        r = RowSubLabel(body, r, L["Stack Count"] or "Stack Count")
        r = RowCheck(body, r, L["Show Stack Count"] or "Show Stack Count", gk, "showStacks", 0)
        r = RowSlider(body, r, L["Font size"] or "Font size", gk, "stackSize", 6, 24, 1, 10)
        r = RowDropdown(body, r, L["Anchor"] or "Anchor", gk, "stackAnchor", ANCHOR9, "BOTTOMRIGHT")
        r = RowSlider(body, r, L["Offset X"] or "Offset X", gk, "stackOffsetX", -20, 20, 1, -1)
        r = RowSlider(body, r, L["Offset Y"] or "Offset Y", gk, "stackOffsetY", -20, 20, 1, 1)

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

        SCheck({
            name = "MSUF_GF_SIEnable", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = L["Enable Spell Indicators"],
            get = function(k) return SIC().enabled == true end,
            set = function(k, v)
                SIC().enabled = v and true or false
                GF.RefreshVisuals()
            end,
        })

        local siLayerSl = SSlider({
            name = "MSUF_GF_SILayer", parent = body, compact = true,
            anchor = body, anchorPoint = "TOPLEFT", x = 240, y = -6,
            min = 1, max = 15, step = 1, width = 160, default = 9,
            get = function(k) return SIC().layer or 9 end,
            set = function(k, v) SIC().layer = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format(L["Layer: %d"], v) end,
        })

        -- Forward declarations
        local RefreshSpecLabel, RefreshSpellTiles, HideAllSpellPanels, SwapInOrder
        local RefreshMultiSpecChecks
        local expandedSpell

        local function ClearSIHighlight()
            if GF._highlightedSI then
                GF._highlightedSI = nil
                GF.RefreshVisuals()
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
                GF.RefreshVisuals()
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

        do
            local idx = 0
            if SI and SI.SpecInfo then
                for specKey, info in pairs(SI.SpecInfo) do
                    idx = idx + 1
                    local col = ((idx - 1) % 4)
                    local row = math_floor((idx - 1) / 4)
                    local chk = SCheck({
                        name = "MSUF_GF_SIMulti_" .. specKey, parent = multiContainer,
                        anchor = multiContainer, anchorPoint = "TOPLEFT",
                        x = col * 150, y = -(row * 22),
                        label = info.display,
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
                            GF.RefreshVisuals()
                        end,
                    })
                    multiChecks[specKey] = chk
                end
            end
            local totalRows = math_ceil(idx / 4)
            multiContainer:SetHeight(totalRows * 22 + 4)
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
                if box._msufRemeasure then box._msufRemeasure() end
            end)
            panel:HookScript("OnHide", function()
                if box._msufRemeasure then box._msufRemeasure() end
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
                label = "",
                get = function(k) return SC().enabled ~= false end,
                set = function(k, v)
                    SC().enabled = v and true or false
                    RefreshSpellTiles()
                    GF.RefreshVisuals()
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
                    GF.RefreshVisuals()
                end,
            })

            local anchorDd = SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_Anchor", parent = panel,
                anchor = typeDd, x = 0, y = -2, width = 120,
                items = ANCHOR9,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.anchor) or "TOPLEFT" end,
                set = function(k, v) PlacedCfg(true).anchor = v; GF.RefreshVisuals() end,
            })

            local sizeSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Size", parent = panel, compact = true,
                anchor = anchorDd, x = 16, y = -6,
                min = 4, max = 40, step = 1, width = 170, default = 18,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.size) or 18 end,
                set = function(k, v) PlacedCfg(true).size = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format(L["Size: %d"], v) end,
            })

            local xSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_X", parent = panel, compact = true,
                anchor = sizeSl, x = 0, y = -34,
                min = -100, max = 100, step = 1, width = 170, default = 0,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.x) or 0 end,
                set = function(k, v) PlacedCfg(true).x = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format("X: %d", v) end,
            })

            local ySl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Y", parent = panel, compact = true,
                anchor = xSl, x = 0, y = -34,
                min = -100, max = 100, step = 1, width = 170, default = 0,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.y) or 0 end,
                set = function(k, v) PlacedCfg(true).y = v; GF.RefreshVisuals() end,
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
                set = function(k, v) PlacedCfg(true).barWidth = v; GF.RefreshVisuals() end,
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
                set = function(k, v) PlacedCfg(true).missing = v and true or false; GF.RefreshVisuals() end,
            })

            local showCDChk = SCheck({
                name = "MSUF_GF_SI_" .. auraName .. "_ShowCD", parent = panel,
                anchor = missingChk, x = 0, y = -8,
                label = L["Show Cooldown Text"],
                get = function(k) local pc = PlacedCfg(false); return pc and pc.showCooldown ~= false end,
                set = function(k, v)
                    PlacedCfg(true).showCooldown = v and true or false
                    GF.RefreshVisuals()
                    if panel._refreshCDControls then panel._refreshCDControls() end
                end,
            })

            local cdSizeSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_CDSize", parent = panel, compact = true,
                anchor = showCDChk, x = 24, y = -8,
                min = 6, max = 24, step = 1, width = 150, default = 8,
                get = function(k) local pc = PlacedCfg(false); return (pc and pc.cooldownSize) or 8 end,
                set = function(k, v) PlacedCfg(true).cooldownSize = v; GF.RefreshVisuals() end,
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
                    GF.RefreshVisuals()
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
                    GF.RefreshVisuals()
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
                    if fc then fc.priority = v; GF.RefreshVisuals() end
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
                    GF.RefreshVisuals()
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
                    GF.RefreshVisuals()
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
                                GF.RefreshVisuals()
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
                                GF.RefreshVisuals()
                                local panel = BuildSpellPanel(auraName, specKey, self)
                                panel:ClearAllPoints()
                                local totalRows = math_ceil(specTileCount / TILES_PER_ROW)
                                local gridH = yOffset + totalRows * (TILE_SIZE + TILE_GAP) - TILE_GAP + 2
                                panel:SetPoint("TOPLEFT", tileContainer, "TOPLEFT", 0, -gridH)
                                panel:Show()
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
        end

        RefreshSpellTiles()
        refreshFns[#refreshFns + 1] = function()
            RefreshSpecLabel()
            RefreshMultiSpecChecks()
            RefreshSpellTiles()
        end
    end

    ----------------------------------------------------------------
    -- Section: Buffs
    ----------------------------------------------------------------
    BuildAuraGroupSection("buff", L["Buffs"], 1300, function(body, prevRow, gk)
        local r = BuildSpellFilterWidgets(body, prevRow, gk)
        return r
    end)

    ----------------------------------------------------------------
    -- Section: Debuffs
    ----------------------------------------------------------------
    BuildAuraGroupSection("debuff", L["Debuffs"], 1440, function(body, prevRow, gk)
        local r = RowCheck(body, prevRow, L["Show Dispel Type Border"], gk, "showDispelBorder")
        r = BuildSpellFilterWidgets(body, r, gk)
        return r
    end)

    ----------------------------------------------------------------
    -- Section: Defensives
    ----------------------------------------------------------------
    BuildAuraGroupSection("externals", L["Defensives"], 700)

    -- Register all compact row refresh functions
    for i = 1, #_auraRefreshFns do
        refreshFns[#refreshFns + 1] = _auraRefreshFns[i]
    end

    ----------------------------------------------------------------
    -- Section: Private Auras
    ----------------------------------------------------------------
    do
        -- Height extended to accommodate the 12.0.5 Private Aura Dispel
        -- Overlay controls at the bottom of the section.
        local box, body = AddSection(700, L["Private Auras"], false, "priv")

        -- Helper for container-overlay sub-table (created lazily).
        local function PAC()
            local pa = PA()
            if not pa.containerOverlay then
                pa.containerOverlay = {
                    enabled     = false,
                    showIcons   = true,
                    dispelMode  = "dispellableByMe",
                    gradientDir = "default",
                }
            end
            return pa.containerOverlay
        end

        SCheck({
            name = "MSUF_GF_PAEnable", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = L["Enable Private Auras"],
            get = function(k) return PA().enabled ~= false end,
            set = function(k, v) PA().enabled = v; GF.RefreshVisuals() end,
        })

        local paMaxSl = SSlider({
            name = "MSUF_GF_PAMax", parent = body, compact = true,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -40,
            min = 1, max = 12, step = 1, width = 200, default = 4,
            get = function(k) return PA().max or 4 end,
            set = function(k, v) PA().max = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format(L["Max: %d"], v) end,
        })

        local paSzSl = SSlider({
            name = "MSUF_GF_PASize", parent = body, compact = true,
            anchor = paMaxSl, x = 0, y = -32,
            min = 8, max = 60, step = 1, width = 200, default = 20,
            get = function(k) return PA().size or 20 end,
            set = function(k, v) PA().size = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format(L["Size: %d"], v) end,
        })

        SDropdown({
            name = "MSUF_GF_PADirection", parent = body,
            anchor = paSzSl, x = -16, y = -10, width = 140,
            items = DIRECTION4,
            get = function(k) return PA().direction or "LEFT" end,
            set = function(k, v) PA().direction = v; GF.RefreshVisuals() end,
        })

        SDropdown({
            name = "MSUF_GF_PAAnchor", parent = body,
            anchor = paSzSl, x = 150, y = -10, width = 140,
            items = ANCHOR9,
            get = function(k) return PA().anchor or "TOPRIGHT" end,
            set = function(k, v) PA().anchor = v; GF.RefreshVisuals() end,
        })

        local paXSl = SSlider({
            name = "MSUF_GF_PAX", parent = body, compact = true,
            anchor = paSzSl, x = 0, y = -76,
            min = -200, max = 200, step = 1, width = 200, default = 0,
            get = function(k) return PA().x or 0 end,
            set = function(k, v) PA().x = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format("X: %d", v) end,
        })

        local paYSl = SSlider({
            name = "MSUF_GF_PAY", parent = body, compact = true,
            anchor = paXSl, x = 0, y = -32,
            min = -200, max = 200, step = 1, width = 200, default = 0,
            get = function(k) return PA().y or 0 end,
            set = function(k, v) PA().y = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format("Y: %d", v) end,
        })

        local paLayerSl = SSlider({
            name = "MSUF_GF_PALayer", parent = body, compact = true,
            anchor = paYSl, x = 0, y = -32,
            min = 1, max = 15, step = 1, width = 200, default = 8,
            get = function(k) return PA().layer or 8 end,
            set = function(k, v) PA().layer = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format(L["Layer: %d"], v) end,
        })

        local paCdChk = SCheck({
            name = "MSUF_GF_PACd", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 380, y = -40,
            label = L["Show Countdown Frame"],
            get = function(k) return PA().showCountdown ~= false end,
            set = function(k, v) PA().showCountdown = v; GF.RefreshVisuals() end,
        })

        local paNumChk = SCheck({
            name = "MSUF_GF_PANumbers", parent = body,
            anchor = paCdChk, x = 0, y = -24,
            label = L["Show Countdown Numbers"],
            get = function(k) return PA().showNumbers == true end,
            set = function(k, v) PA().showNumbers = v; GF.RefreshVisuals() end,
        })

        local paDispelChk = SCheck({
            name = "MSUF_GF_PADispelType", parent = body,
            anchor = paNumChk, x = 0, y = -24,
            label = L["Show Dispel Type"],
            get = function(k) return PA().showDispelType == true end,
            set = function(k, v) PA().showDispelType = v; GF.RefreshVisuals() end,
        })

        ----------------------------------------------------------------
        -- Sub-section: Private Aura Dispel Overlay
        --
        -- Blizzard-rendered overlay driven by container-anchor attributes
        -- (max-buffs / max-debuffs / max-dispel-debuffs / dispel-indicator-
        -- option / aura-organization-type). 12.0.5+ baseline.
        --
        -- LAYOUT: anchor below paLayerSl (left column), NOT paDispelChk
        -- (right column). The left column ends ~110px lower; anchoring to
        -- the right column would render this header on top of paYSl/paLayerSl.
        ----------------------------------------------------------------
        local coHeader = body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        coHeader:SetPoint("TOPLEFT", paLayerSl, "BOTTOMLEFT", 0, -24)
        coHeader:SetText(L["Dispel Overlay"] or "Dispel Overlay")
        coHeader:SetTextColor(1.00, 0.82, 0.00)

        local coEnableChk = SCheck({
            name = "MSUF_GF_PAContainerOverlayEnable", parent = body,
            anchor = coHeader, x = 0, y = -22,
            label = L["Enable Dispel Overlay"] or "Enable Dispel Overlay",
            get = function() return PAC().enabled == true end,
            set = function(_, v)
                PAC().enabled = v and true or false
                GF.RefreshVisuals()
                -- Live-apply on every visible GF frame.
                if GF.frames and GF.UpdatePrivateAuraContainerOverlay then
                    for fr in pairs(GF.frames) do
                        if fr.unit and fr:IsShown() then
                            GF.UpdatePrivateAuraContainerOverlay(fr)
                        end
                    end
                end
            end,
        })

        local coShowIconsChk = SCheck({
            name = "MSUF_GF_PAContainerOverlayShowIcons", parent = body,
            anchor = coEnableChk, x = 0, y = -24,
            label = L["Show Dispel Icon"] or "Show Dispel Icon",
            get = function() return PAC().showIcons ~= false end,
            set = function(_, v)
                PAC().showIcons = v and true or false
                if GF.frames and GF.UpdatePrivateAuraContainerOverlay then
                    for fr in pairs(GF.frames) do
                        if fr.unit and fr:IsShown() then
                            GF.UpdatePrivateAuraContainerOverlay(fr)
                        end
                    end
                end
            end,
        })

        local coDispelModeDD = SDropdown({
            name = "MSUF_GF_PAContainerOverlayDispelMode", parent = body, compact = true,
            anchor = coShowIconsChk, x = 0, y = -28,
            width = DD_W,
            label = L["Dispel Filter"] or "Dispel Filter",
            items = {
                { value = "dispellableByMe", text = L["Dispellable By Me"] or "Dispellable By Me" },
                { value = "allDispellable",  text = L["All Dispellable"]   or "All Dispellable"   },
            },
            get = function() return PAC().dispelMode or "dispellableByMe" end,
            set = function(_, v)
                PAC().dispelMode = v
                if GF.frames and GF.UpdatePrivateAuraContainerOverlay then
                    for fr in pairs(GF.frames) do
                        if fr.unit and fr:IsShown() then
                            GF.UpdatePrivateAuraContainerOverlay(fr)
                        end
                    end
                end
            end,
        })

        SDropdown({
            name = "MSUF_GF_PAContainerOverlayGradient", parent = body, compact = true,
            anchor = coDispelModeDD, anchorPoint = "TOPRIGHT", x = 12, y = 0,
            width = DD_W,
            label = L["Gradient Direction"] or "Gradient Direction",
            items = {
                { value = "default", text = L["Default"] or "Default" },
                { value = "TOP",     text = L["Top"]     or "Top"     },
                { value = "BOTTOM",  text = L["Bottom"]  or "Bottom"  },
                { value = "LEFT",    text = L["Left"]    or "Left"    },
                { value = "RIGHT",   text = L["Right"]   or "Right"   },
            },
            get = function() return PAC().gradientDir or "default" end,
            set = function(_, v)
                PAC().gradientDir = v
                if GF.frames and GF.UpdatePrivateAuraContainerOverlay then
                    for fr in pairs(GF.frames) do
                        if fr.unit and fr:IsShown() then
                            GF.UpdatePrivateAuraContainerOverlay(fr)
                        end
                    end
                end
            end,
        })
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
            if conf then conf[key] = val end
            GF.RefreshVisuals()
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
            valFS:SetText(tostring(math_floor((CIV("ciSize") or 8) + 0.5)))
            sl:SetScript("OnValueChanged", function(self, v)
                v = math_floor(v + 0.5)
                valFS:SetText(tostring(v))
                CIW("ciSize", v)
            end)
            _auraRefreshFns[#_auraRefreshFns + 1] = function()
                local v = CIV("ciSize") or 8
                sl:SetValue(v)
                valFS:SetText(tostring(math_floor(v + 0.5)))
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
            sl:SetScript("OnValueChanged", function(self, v)
                v = math_floor(v + 0.5)
                valFS:SetText(tostring(v) .. "%")
                CIW("ciAlpha", v / 100)
            end)
            _auraRefreshFns[#_auraRefreshFns + 1] = function()
                local v = math_floor(((CIV("ciAlpha") or 1.0) * 100) + 0.5)
                sl:SetValue(v)
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
                GF.RefreshVisuals()
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
                GF.RefreshVisuals()
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
                GF.RefreshVisuals()
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
                        GF.RefreshVisuals()
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
                    statusFS:SetText("|cff80e080●|r Editing slot " .. activeSlot .. "  (active)")
                else
                    statusFS:SetText("|cff888888○|r Slot " .. activeSlot .. " is set to '" .. cat .. "'. Set to 'Custom Spell' in the dropdown above to activate this configuration.")
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
                    warnFS:SetText("|cffffaa55⚠ Warning:|r |cff999999This filter scans buffs/debuffs from any caster. Midnight 12.0 marks other players' aura spell IDs as 'secret', so most matches will be silently skipped. Use this filter only for spells you've verified are visible (e.g. permanent raid buffs you cast yourself).|r")
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
                if v then
                    if GF.Masque and GF.Masque.ReskinAllIcons then GF.Masque.ReskinAllIcons() end
                end
                GF.RefreshVisuals()
            end,
        })

        local infoFS = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        infoFS:SetPoint("TOPLEFT", masqueChk, "BOTTOMLEFT", 6, -4)
        infoFS:SetText("|cff888888" .. (L["Applies to Buffs, Debuffs & Externals icons.\nCount text is managed by MSUF (not Masque)."] or "Applies to Buffs, Debuffs & Externals icons.\nCount text is managed by MSUF (not Masque)."))
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
                GF.RefreshVisuals()
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
            GF.RefreshVisuals()
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
                        GF.RefreshVisuals()
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

end

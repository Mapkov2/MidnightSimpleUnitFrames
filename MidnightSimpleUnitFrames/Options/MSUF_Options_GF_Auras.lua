-- MSUF_Options_GF_Auras.lua — GF Options: Buffs, Debuffs, Externals, Private Auras, Spell Indicators
-- 6 accordion sections injected into MSUF_Options_GF.lua panel.
-- Called from MSUF_Options_GF.lua after all other sections are built.
-- Features: drag-to-sort tiles, multi-spec, glow/pulse types, import/export, L["..."] localized.
-- Midnight 12.0, cold-path only.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

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
    { key = "RAID_PLAYER",    label = L["Raid + Player"]           },
    { key = "RAID_IN_COMBAT", label = L["Raid in Combat + Player"] },
    { key = "ALL_PLAYER",     label = L["All Player"]              },
}
local DIRECTION4 = {
    { key = "LEFT",   label = L["Left"]   },
    { key = "RIGHT",  label = L["Right"]  },
    { key = "TOP",    label = L["Top"]    },
    { key = "BOTTOM", label = L["Bottom"] },
}
local INDICATOR_TYPES = {
    { key = "icon",   label = L["Icon"]   },
    { key = "square", label = L["Square"] },
    { key = "bar",    label = L["Bar"]    },
}
local FRAME_EFFECT_TYPES = {
    { key = "none",       label = L["None"]               },
    { key = "healthtint", label = L["Health Bar Tint"]     },
    { key = "border",     label = L["Border"]              },
    { key = "glow",       label = L["Glow (Animated)"]     },
    { key = "pulse",      label = L["Pulse (Animated)"]    },
    { key = "namecolor",  label = L["Name Text Color"]     },
    { key = "framealpha", label = L["Frame Alpha"]          },
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
            conf.spellIndicators = { enabled = false, spec = "auto", specs = {} }
        end
        return conf.spellIndicators
    end

    ----------------------------------------------------------------
    -- Build one aura group section (Buffs / Debuffs / Externals)
    ----------------------------------------------------------------
    local function BuildAuraGroupSection(groupKey, title, expandedH, extraWidgets)
        local box, body = AddSection(expandedH, title, false)

        local enChk = SCheck({
            name = "MSUF_GF_" .. groupKey .. "Enable", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = L["Enable"],
            get = function(k) return AV(groupKey, "enabled") ~= false end,
            set = function(k, v) AW(groupKey, "enabled", v and true or false) end,
        })

        local lastWidget = enChk
        if extraWidgets then
            lastWidget = extraWidgets(body, lastWidget, groupKey) or lastWidget
        end

        local anchorDd = SDropdown({
            name = "MSUF_GF_" .. groupKey .. "Anchor", parent = body,
            anchor = lastWidget, x = -16, y = -10, width = 160,
            items = ANCHOR9,
            get = function(k) return AV(groupKey, "anchor") or "BOTTOMLEFT" end,
            set = function(k, v) AW(groupKey, "anchor", v) end,
        })

        local growthDd = SDropdown({
            name = "MSUF_GF_" .. groupKey .. "Growth", parent = body,
            anchor = anchorDd, x = 0, y = -4, width = 160,
            items = GROWTH8,
            get = function(k) return AV(groupKey, "growth") or "RIGHTDOWN" end,
            set = function(k, v) AW(groupKey, "growth", v) end,
        })

        local xSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "X", parent = body, compact = true,
            anchor = growthDd, x = 16, y = -10,
            min = -200, max = 200, step = 1, width = 200, default = 0,
            get = function(k) return AV(groupKey, "x") or 0 end,
            set = function(k, v) AW(groupKey, "x", v) end,
            formatText = function(v) return string.format("X: %d", v) end,
        })

        local ySl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "Y", parent = body, compact = true,
            anchor = xSl, x = 0, y = -32,
            min = -200, max = 200, step = 1, width = 200, default = 0,
            get = function(k) return AV(groupKey, "y") or 0 end,
            set = function(k, v) AW(groupKey, "y", v) end,
            formatText = function(v) return string.format("Y: %d", v) end,
        })

        local sizeSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "Size", parent = body, compact = true,
            anchor = ySl, x = 0, y = -32,
            min = 8, max = 60, step = 1, width = 200, default = 20,
            get = function(k) return AV(groupKey, "size") or 20 end,
            set = function(k, v) AW(groupKey, "size", v) end,
            formatText = function(v) return string.format(L["Icon Size: %d"], v) end,
        })

        local perRowSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "PerRow", parent = body, compact = true,
            anchor = sizeSl, x = 0, y = -32,
            min = 1, max = 16, step = 1, width = 200, default = 4,
            get = function(k) return AV(groupKey, "perRow") or 4 end,
            set = function(k, v) AW(groupKey, "perRow", v) end,
            formatText = function(v) return string.format(L["Per Row: %d"], v) end,
        })

        local maxSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "Max", parent = body, compact = true,
            anchor = perRowSl, x = 0, y = -32,
            min = 1, max = 20, step = 1, width = 200, default = 6,
            get = function(k) return AV(groupKey, "max") or 6 end,
            set = function(k, v) AW(groupKey, "max", v) end,
            formatText = function(v) return string.format(L["Max: %d"], v) end,
        })

        local spaceSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "Spacing", parent = body, compact = true,
            anchor = maxSl, x = 0, y = -32,
            min = 0, max = 10, step = 1, width = 200, default = 1,
            get = function(k) return AV(groupKey, "spacing") or 1 end,
            set = function(k, v) AW(groupKey, "spacing", v) end,
            formatText = function(v) return string.format(L["Spacing: %d"], v) end,
        })

        -- Divider
        local divider = body:CreateTexture(nil, "ARTWORK")
        divider:SetHeight(1)
        divider:SetColorTexture(0.3, 0.3, 0.3, 0.4)
        divider:SetPoint("TOPLEFT", spaceSl, "BOTTOMLEFT", 0, -12)
        divider:SetPoint("RIGHT", body, "RIGHT", -16, 0)

        local cdLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cdLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
        cdLabel:SetText(L["Cooldown Text"])
        cdLabel:SetTextColor(1, 0.82, 0)

        local cdChk = SCheck({
            name = "MSUF_GF_" .. groupKey .. "CdEnable", parent = body,
            anchor = cdLabel, x = 0, y = -6,
            label = L["Show Cooldown Text"],
            get = function(k) return AV(groupKey, "showCooldown") ~= false end,
            set = function(k, v) AW(groupKey, "showCooldown", v) end,
        })

        local cdAnchorDd = SDropdown({
            name = "MSUF_GF_" .. groupKey .. "CdAnchor", parent = body,
            anchor = cdChk, x = -16, y = -6, width = 140,
            items = ANCHOR9,
            get = function(k) return AV(groupKey, "cooldownAnchor") or "CENTER" end,
            set = function(k, v) AW(groupKey, "cooldownAnchor", v) end,
        })

        local cdSizeSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "CdSize", parent = body, compact = true,
            anchor = cdAnchorDd, x = 16, y = -6,
            min = 6, max = 24, step = 1, width = 160, default = 8,
            get = function(k) return AV(groupKey, "cooldownSize") or 8 end,
            set = function(k, v) AW(groupKey, "cooldownSize", v) end,
            formatText = function(v) return string.format(L["CD Size: %d"], v) end,
        })

        -- Divider 2
        local divider2 = body:CreateTexture(nil, "ARTWORK")
        divider2:SetHeight(1)
        divider2:SetColorTexture(0.3, 0.3, 0.3, 0.4)
        divider2:SetPoint("TOPLEFT", cdSizeSl, "BOTTOMLEFT", 0, -12)
        divider2:SetPoint("RIGHT", body, "RIGHT", -16, 0)

        local stackLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        stackLabel:SetPoint("TOPLEFT", divider2, "BOTTOMLEFT", 0, -8)
        stackLabel:SetText(L["Stack Count"])
        stackLabel:SetTextColor(1, 0.82, 0)

        SCheck({
            name = "MSUF_GF_" .. groupKey .. "StackEnable", parent = body,
            anchor = stackLabel, x = 0, y = -6,
            label = L["Show Stack Count"],
            get = function(k) return AV(groupKey, "showStacks") ~= false end,
            set = function(k, v) AW(groupKey, "showStacks", v) end,
        })

        return box, body
    end

    ----------------------------------------------------------------
    -- Section: Spell Indicators (default open)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(640, L["Spell Indicators"], true)

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

        -- Forward declarations
        local RefreshSpecLabel, RefreshSpellTiles, HideAllSpellPanels, SwapInOrder
        local RefreshMultiSpecChecks
        local expandedSpell

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

        HideAllSpellPanels = function()
            for _, panel in pairs(spellPanels) do panel:Hide() end
        end

        local function BuildSpellPanel(auraName, specKey, parentTile)
            if spellPanels[auraName] then return spellPanels[auraName] end

            local panel = CreateFrame("Frame", nil, body, "BackdropTemplate")
            panel:SetSize(580, 260)
            panel:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            panel:SetBackdropColor(0.08, 0.10, 0.14, 0.95)
            panel:SetBackdropBorderColor(0.2, 0.35, 0.5, 0.6)
            panel:EnableMouse(true)

            local function SC()
                local siCfg = SIC()
                siCfg.specs = siCfg.specs or {}
                siCfg.specs[specKey] = siCfg.specs[specKey] or {}
                siCfg.specs[specKey][auraName] = siCfg.specs[specKey][auraName] or {}
                return siCfg.specs[specKey][auraName]
            end
            local function PlacedCfg()
                local c = SC()
                if not c.placed then c.placed = {} end
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

            local closeBtn = CreateFrame("Button", nil, panel)
            closeBtn:SetSize(16, 16)
            closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
            local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
            closeTex:SetAllPoints()
            closeTex:SetTexture("Interface\\Buttons\\UI-StopButton")
            closeBtn:SetScript("OnClick", function() expandedSpell = nil; panel:Hide() end)

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
            headerDiv:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -26)
            headerDiv:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -26)

            -- Left column: Placed Indicator
            local COL_L = 10
            local COL_R = 290
            local ROW_TOP = -34

            local placedLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            placedLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_L, ROW_TOP)
            placedLbl:SetText(L["Placed Indicator"])
            placedLbl:SetTextColor(1, 0.82, 0)

            local typeDd = SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_Type", parent = panel,
                anchor = placedLbl, x = -16, y = -4, width = 100,
                items = INDICATOR_TYPES,
                get = function(k) return PlacedCfg().type or "icon" end,
                set = function(k, v)
                    PlacedCfg().type = v
                    if panel._refreshBarW then panel._refreshBarW() end
                    GF.RefreshVisuals()
                end,
            })

            local anchorDd = SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_Anchor", parent = panel,
                anchor = typeDd, x = 0, y = -2, width = 120,
                items = ANCHOR9,
                get = function(k) return PlacedCfg().anchor or "TOPLEFT" end,
                set = function(k, v) PlacedCfg().anchor = v; GF.RefreshVisuals() end,
            })

            local sizeSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Size", parent = panel, compact = true,
                anchor = anchorDd, x = 16, y = -6,
                min = 4, max = 40, step = 1, width = 140, default = 18,
                get = function(k) return PlacedCfg().size or 18 end,
                set = function(k, v) PlacedCfg().size = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format(L["Size: %d"], v) end,
            })

            local xSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_X", parent = panel, compact = true,
                anchor = sizeSl, x = 0, y = -28,
                min = -100, max = 100, step = 1, width = 140, default = 0,
                get = function(k) return PlacedCfg().x or 0 end,
                set = function(k, v) PlacedCfg().x = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format("X: %d", v) end,
            })

            local ySl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Y", parent = panel, compact = true,
                anchor = xSl, x = 0, y = -28,
                min = -100, max = 100, step = 1, width = 140, default = 0,
                get = function(k) return PlacedCfg().y or 0 end,
                set = function(k, v) PlacedCfg().y = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format("Y: %d", v) end,
            })

            local barWSlider = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_BarW", parent = panel, compact = true,
                anchor = sizeSl, x = 160, y = 0,
                min = 10, max = 120, step = 1, width = 120, default = 54,
                get = function(k) return PlacedCfg().barWidth or ((PlacedCfg().size or 18) * 3) end,
                set = function(k, v) PlacedCfg().barWidth = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format(L["Width: %d"], v) end,
            })
            panel._barWSlider = barWSlider

            local function RefreshBarW()
                local t = PlacedCfg().type or "icon"
                if t == "bar" then barWSlider:Show() else barWSlider:Hide() end
            end
            panel._refreshBarW = RefreshBarW
            RefreshBarW()

            SCheck({
                name = "MSUF_GF_SI_" .. auraName .. "_Missing", parent = panel,
                anchor = ySl, x = 0, y = -12,
                label = L["Show when missing"],
                get = function(k) return PlacedCfg().missing == true end,
                set = function(k, v) PlacedCfg().missing = v and true or false; GF.RefreshVisuals() end,
            })

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
                    return fc.type
                end,
                set = function(k, v)
                    if v == "none" then
                        SC().frame = nil
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
            fxColorRow:SetPoint("TOPLEFT", fxDd, "BOTTOMLEFT", 16, -6)
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
                anchor = fxColorRow, x = 0, y = -10,
                min = 1, max = 10, step = 1, width = 140, default = 5,
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
                anchor = prioSl, x = 0, y = -28,
                min = 5, max = 100, step = 5, width = 140, default = 15,
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
                anchor = prioSl, x = 0, y = -28,
                min = 1, max = 6, step = 1, width = 140, default = 2,
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
            spellPanels[auraName] = panel
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
                                if expandedSpell == auraName then
                                    expandedSpell = nil
                                    return
                                end
                                expandedSpell = auraName
                                local panel = BuildSpellPanel(auraName, specKey, self)
                                panel:ClearAllPoints()
                                local totalRows = math_ceil(specTileCount / TILES_PER_ROW)
                                local gridH = yOffset + totalRows * (TILE_SIZE + TILE_GAP) + 8
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
    BuildAuraGroupSection("buff", L["Buffs"], 620, function(body, lastWidget, gk)
        return SDropdown({
            name = "MSUF_GF_BuffFilter", parent = body,
            anchor = lastWidget, x = -16, y = -6, width = 200,
            items = FILTER_MODES,
            get = function(k) return AV(gk, "filterMode") or "RAID_PLAYER" end,
            set = function(k, v) AW(gk, "filterMode", v) end,
        })
    end)

    ----------------------------------------------------------------
    -- Section: Debuffs
    ----------------------------------------------------------------
    BuildAuraGroupSection("debuff", L["Debuffs"], 620, function(body, lastWidget, gk)
        return SCheck({
            name = "MSUF_GF_DebuffDispelBorder", parent = body,
            anchor = lastWidget, x = 0, y = -6,
            label = L["Show Dispel Type Border"],
            get = function(k) return AV(gk, "showDispelBorder") ~= false end,
            set = function(k, v) AW(gk, "showDispelBorder", v) end,
        })
    end)

    ----------------------------------------------------------------
    -- Section: Externals
    ----------------------------------------------------------------
    BuildAuraGroupSection("externals", L["Externals"], 580)


    ----------------------------------------------------------------
    -- Section: Private Auras
    ----------------------------------------------------------------
    do
        local box, body = AddSection(480, L["Private Auras"], false)

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

        SCheck({
            name = "MSUF_GF_PACd", parent = body,
            anchor = paYSl, x = 0, y = -12,
            label = L["Show Countdown Frame"],
            get = function(k) return PA().showCountdown ~= false end,
            set = function(k, v) PA().showCountdown = v; GF.RefreshVisuals() end,
        })

        SCheck({
            name = "MSUF_GF_PANumbers", parent = body,
            anchor = paYSl, x = 0, y = -36,
            label = L["Show Countdown Numbers"],
            get = function(k) return PA().showNumbers == true end,
            set = function(k, v) PA().showNumbers = v; GF.RefreshVisuals() end,
        })

        SCheck({
            name = "MSUF_GF_PADispelType", parent = body,
            anchor = paYSl, x = 0, y = -60,
            label = L["Show Dispel Type"],
            get = function(k) return PA().showDispelType == true end,
            set = function(k, v) PA().showDispelType = v; GF.RefreshVisuals() end,
        })
    end

    ----------------------------------------------------------------
    -- Aura Utilities (copy + dynamic scale + import/export)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(220, L["Aura Utilities"], false)

        -- Dynamic content scale
        SCheck({
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
            if type(src) ~= "table" then return src end
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
            GF.RefreshVisuals()
        end

        local copyLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        copyLbl:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -36)
        copyLbl:SetText(L["Copy All Aura Settings"])
        copyLbl:SetTextColor(1, 0.82, 0)

        local btnP2R = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
        btnP2R:SetSize(180, 24)
        btnP2R:SetPoint("TOPLEFT", copyLbl, "BOTTOMLEFT", 0, -6)
        btnP2R:SetText(L["Party -> Raid"])
        btnP2R:SetScript("OnClick", function() DoCopy("party", "raid") end)

        local btnR2P = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
        btnR2P:SetSize(180, 24)
        btnR2P:SetPoint("LEFT", btnP2R, "RIGHT", 12, 0)
        btnR2P:SetText(L["Raid -> Party"])
        btnR2P:SetScript("OnClick", function() DoCopy("raid", "party") end)

        -- Import/Export section
        local ioLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ioLbl:SetPoint("TOPLEFT", btnP2R, "BOTTOMLEFT", 0, -16)
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

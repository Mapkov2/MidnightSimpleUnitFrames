-- MSUF_Options_GF_Auras.lua — GF Options: Buffs, Debuffs, Externals, Private Auras, Spell Indicators
-- 5 accordion sections injected into MSUF_Options_GF.lua panel.
-- Called from MSUF_Options_GF.lua after all other sections are built.
-- Midnight 12.0, cold-path only.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local GF = ns.GF
local UI = ns.UI
local SI = GF and GF.SpellIndicators
local TR = ns.TR or function(v) return v end

if not GF then return end

local CreateFrame = CreateFrame
local type    = type
local pairs   = pairs
local ipairs  = ipairs
local tostring = tostring

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ANCHOR9 = {
    { key = "TOPLEFT",     label = "Top Left"     },
    { key = "TOP",         label = "Top"           },
    { key = "TOPRIGHT",    label = "Top Right"     },
    { key = "LEFT",        label = "Left"          },
    { key = "CENTER",      label = "Center"        },
    { key = "RIGHT",       label = "Right"         },
    { key = "BOTTOMLEFT",  label = "Bottom Left"   },
    { key = "BOTTOM",      label = "Bottom"        },
    { key = "BOTTOMRIGHT", label = "Bottom Right"  },
}
local GROWTH8 = {
    { key = "RIGHTDOWN", label = "Right → Down" },
    { key = "RIGHTUP",   label = "Right → Up"   },
    { key = "LEFTDOWN",  label = "Left → Down"  },
    { key = "LEFTUP",    label = "Left → Up"    },
    { key = "DOWNRIGHT", label = "Down → Right" },
    { key = "DOWNLEFT",  label = "Down → Left"  },
    { key = "UPRIGHT",   label = "Up → Right"   },
    { key = "UPLEFT",    label = "Up → Left"    },
}
local OUTLINE_ITEMS = {
    { key = "NONE",              label = "None"              },
    { key = "OUTLINE",           label = "Outline"           },
    { key = "THICKOUTLINE",      label = "Thick Outline"     },
    { key = "MONOCHROMEOUTLINE", label = "Monochrome"        },
}
local STACK_ANCHOR5 = {
    { key = "TOPLEFT",     label = "Top Left"     },
    { key = "TOPRIGHT",    label = "Top Right"    },
    { key = "BOTTOMLEFT",  label = "Bottom Left"  },
    { key = "BOTTOMRIGHT", label = "Bottom Right"  },
    { key = "CENTER",      label = "Center"        },
}
local FILTER_MODES = {
    { key = "RAID_PLAYER",    label = "Raid + Player"           },
    { key = "RAID_IN_COMBAT", label = "Raid in Combat + Player" },
    { key = "ALL_PLAYER",     label = "All Player"              },
}
local DIRECTION4 = {
    { key = "LEFT",   label = "Left"   },
    { key = "RIGHT",  label = "Right"  },
    { key = "TOP",    label = "Top"    },
    { key = "BOTTOM", label = "Bottom" },
}
local INDICATOR_TYPES = {
    { key = "icon",   label = "Icon"   },
    { key = "square", label = "Square" },
}
local FRAME_EFFECT_TYPES = {
    { key = "none",       label = "None"               },
    { key = "healthtint", label = "Health Bar Tint"     },
    { key = "border",     label = "Border Glow"         },
    { key = "namecolor",  label = "Name Text Color"     },
    { key = "framealpha", label = "Frame Alpha"          },
}

------------------------------------------------------------------------
-- Injector: called from MSUF_Options_GF.lua
------------------------------------------------------------------------
function GF.BuildAuraOptionsSections(AddSection, SCheck, SSlider, SDropdown, K, TrackRefresh, MakeColorSwatch, OpenColorPicker, refreshFns)
    if not UI then UI = ns.UI end
    if not TR then TR = ns.TR or function(v) return v end end

    -- Helper: get nested aura group config
    local function AG(groupKey)
        local conf = GF.GetConf(K())
        if not conf.auras then conf.auras = {} end
        local g = conf.auras[groupKey]
        if not g then
            g = {}
            conf.auras[groupKey] = g
        end
        return g
    end
    local function AV(groupKey, key)
        local g = AG(groupKey)
        return g[key]
    end
    local function AW(groupKey, key, val)
        AG(groupKey)[key] = val
        GF.RefreshVisuals()
    end

    -- Helper: ensure private auras nested config
    local function PA()
        local conf = GF.GetConf(K())
        if not conf.privateAuras then conf.privateAuras = {} end
        return conf.privateAuras
    end

    -- Helper: ensure spell indicators config
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
            label = TR("Enable"),
            get = function(k) return AV(groupKey, "enabled") ~= false end,
            set = function(k, v)
                AW(groupKey, "enabled", v and true or false)
            end,
        })

        -- Extra widgets (e.g. filter dropdown for buffs)
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
            formatText = function(v) return string.format("Icon Size: %d", v) end,
        })

        local perRowSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "PerRow", parent = body, compact = true,
            anchor = sizeSl, x = 0, y = -32,
            min = 1, max = 16, step = 1, width = 200, default = 4,
            get = function(k) return AV(groupKey, "perRow") or 4 end,
            set = function(k, v) AW(groupKey, "perRow", v) end,
            formatText = function(v) return string.format("Per Row: %d", v) end,
        })

        local maxSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "Max", parent = body, compact = true,
            anchor = perRowSl, x = 0, y = -32,
            min = 1, max = 20, step = 1, width = 200, default = 6,
            get = function(k) return AV(groupKey, "max") or 6 end,
            set = function(k, v) AW(groupKey, "max", v) end,
            formatText = function(v) return string.format("Max: %d", v) end,
        })

        local spaceSl = SSlider({
            name = "MSUF_GF_" .. groupKey .. "Spacing", parent = body, compact = true,
            anchor = maxSl, x = 0, y = -32,
            min = 0, max = 10, step = 1, width = 200, default = 1,
            get = function(k) return AV(groupKey, "spacing") or 1 end,
            set = function(k, v) AW(groupKey, "spacing", v) end,
            formatText = function(v) return string.format("Spacing: %d", v) end,
        })

        -- Divider
        local divider = body:CreateTexture(nil, "ARTWORK")
        divider:SetHeight(1)
        divider:SetColorTexture(0.3, 0.3, 0.3, 0.4)
        divider:SetPoint("TOPLEFT", spaceSl, "BOTTOMLEFT", 0, -12)
        divider:SetPoint("RIGHT", body, "RIGHT", -16, 0)

        -- Cooldown text section
        local cdLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cdLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
        cdLabel:SetText(TR("Cooldown Text"))
        cdLabel:SetTextColor(1, 0.82, 0)

        local cdChk = SCheck({
            name = "MSUF_GF_" .. groupKey .. "CdEnable", parent = body,
            anchor = cdLabel, x = 0, y = -6,
            label = TR("Show Cooldown Text"),
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
            formatText = function(v) return string.format("CD Size: %d", v) end,
        })

        -- Divider 2
        local divider2 = body:CreateTexture(nil, "ARTWORK")
        divider2:SetHeight(1)
        divider2:SetColorTexture(0.3, 0.3, 0.3, 0.4)
        divider2:SetPoint("TOPLEFT", cdSizeSl, "BOTTOMLEFT", 0, -12)
        divider2:SetPoint("RIGHT", body, "RIGHT", -16, 0)

        -- Stack count section
        local stackLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        stackLabel:SetPoint("TOPLEFT", divider2, "BOTTOMLEFT", 0, -8)
        stackLabel:SetText(TR("Stack Count"))
        stackLabel:SetTextColor(1, 0.82, 0)

        SCheck({
            name = "MSUF_GF_" .. groupKey .. "StackEnable", parent = body,
            anchor = stackLabel, x = 0, y = -6,
            label = TR("Show Stack Count"),
            get = function(k) return AV(groupKey, "showStacks") ~= false end,
            set = function(k, v) AW(groupKey, "showStacks", v) end,
        })

        return box, body
    end

    ----------------------------------------------------------------
    -- Section: Buffs
    ----------------------------------------------------------------
    BuildAuraGroupSection("buff", "Buffs", 620, function(body, lastWidget, gk)
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
    BuildAuraGroupSection("debuff", "Debuffs", 620, function(body, lastWidget, gk)
        return SCheck({
            name = "MSUF_GF_DebuffDispelBorder", parent = body,
            anchor = lastWidget, x = 0, y = -6,
            label = TR("Show Dispel Type Border"),
            get = function(k) return AV(gk, "showDispelBorder") ~= false end,
            set = function(k, v) AW(gk, "showDispelBorder", v) end,
        })
    end)

    ----------------------------------------------------------------
    -- Section: Externals
    ----------------------------------------------------------------
    BuildAuraGroupSection("externals", "Externals", 580)

    ----------------------------------------------------------------
    -- Section: Private Auras (extended)
    ----------------------------------------------------------------
    do
        local box, body = AddSection(480, "Private Auras", false)

        SCheck({
            name = "MSUF_GF_PAEnable", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Enable Private Auras"),
            get = function(k) return PA().enabled ~= false end,
            set = function(k, v) PA().enabled = v; GF.RefreshVisuals() end,
        })

        local paMaxSl = SSlider({
            name = "MSUF_GF_PAMax", parent = body, compact = true,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -40,
            min = 1, max = 12, step = 1, width = 200, default = 4,
            get = function(k) return PA().max or 4 end,
            set = function(k, v) PA().max = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format("Max: %d", v) end,
        })

        local paSzSl = SSlider({
            name = "MSUF_GF_PASize", parent = body, compact = true,
            anchor = paMaxSl, x = 0, y = -32,
            min = 8, max = 60, step = 1, width = 200, default = 20,
            get = function(k) return PA().size or 20 end,
            set = function(k, v) PA().size = v; GF.RefreshVisuals() end,
            formatText = function(v) return string.format("Size: %d", v) end,
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
            label = TR("Show Countdown Frame"),
            get = function(k) return PA().showCountdown ~= false end,
            set = function(k, v) PA().showCountdown = v; GF.RefreshVisuals() end,
        })

        SCheck({
            name = "MSUF_GF_PANumbers", parent = body,
            anchor = paYSl, x = 0, y = -36,
            label = TR("Show Countdown Numbers"),
            get = function(k) return PA().showNumbers == true end,
            set = function(k, v) PA().showNumbers = v; GF.RefreshVisuals() end,
        })

        SCheck({
            name = "MSUF_GF_PADispelType", parent = body,
            anchor = paYSl, x = 0, y = -60,
            label = TR("Show Dispel Type"),
            get = function(k) return PA().showDispelType == true end,
            set = function(k, v) PA().showDispelType = v; GF.RefreshVisuals() end,
        })
    end

    ----------------------------------------------------------------
    -- Section: Spell Indicators
    ----------------------------------------------------------------
    do
        local box, body = AddSection(800, "Spell Indicators", false)

        SCheck({
            name = "MSUF_GF_SIEnable", parent = body,
            anchor = body, anchorPoint = "TOPLEFT", x = 12, y = -6,
            label = TR("Enable Spell Indicators"),
            get = function(k) return SIC().enabled == true end,
            set = function(k, v)
                SIC().enabled = v and true or false
                GF.RefreshVisuals()
            end,
        })

        -- Spec label
        local specLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        specLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -36)
        specLabel:SetText(TR("Spec: Auto-Detect"))

        local function RefreshSpecLabel()
            local siCfg = SIC()
            local specKey
            if siCfg.spec == "auto" then
                specKey = SI and SI.GetPlayerSpec and SI.GetPlayerSpec()
            else
                specKey = siCfg.spec
            end
            local info = specKey and SI and SI.SpecInfo and SI.SpecInfo[specKey]
            if info then
                specLabel:SetText(TR("Spec:") .. " " .. info.display)
            else
                specLabel:SetText(TR("Spec: (none detected)"))
            end
        end
        RefreshSpecLabel()
        refreshFns[#refreshFns + 1] = RefreshSpecLabel

        -- Spell tile grid (icon buttons for each trackable aura)
        local tileContainer = CreateFrame("Frame", nil, body)
        tileContainer:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -58)
        tileContainer:SetSize(640, 1) -- height auto

        -- Per-spell config panels (lazy-created, one per auraName)
        local spellPanels = {}
        local expandedSpell = nil

        local function HideAllSpellPanels()
            for _, panel in pairs(spellPanels) do
                panel:Hide()
            end
        end

        local function BuildSpellPanel(auraName, specKey, parentTile)
            if spellPanels[auraName] then return spellPanels[auraName] end

            local panel = CreateFrame("Frame", nil, body, "BackdropTemplate")
            panel:SetSize(620, 260)
            panel:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            panel:SetBackdropColor(0.08, 0.10, 0.14, 0.95)
            panel:SetBackdropBorderColor(0.2, 0.35, 0.5, 0.6)
            panel:EnableMouse(true)

            -- Config accessors
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

            local titleFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
            local trackable = SI and SI.TrackableAuras and SI.TrackableAuras[specKey]
            local dispName = auraName
            if trackable then
                for _, info in ipairs(trackable) do
                    if info.name == auraName then dispName = info.display; break end
                end
            end
            titleFs:SetText(dispName)

            -- Close button
            local closeBtn = CreateFrame("Button", nil, panel)
            closeBtn:SetSize(16, 16)
            closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
            local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
            closeTex:SetAllPoints()
            closeTex:SetTexture("Interface\\Buttons\\UI-StopButton")
            closeBtn:SetScript("OnClick", function()
                expandedSpell = nil
                panel:Hide()
            end)

            -- Placed indicator type dropdown
            local typeLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            typeLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -32)
            typeLbl:SetText(TR("Type:"))

            local typeDd = SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_Type", parent = panel,
                anchor = typeLbl, x = 30, y = 6, width = 100,
                items = INDICATOR_TYPES,
                get = function(k) return PlacedCfg().type or "icon" end,
                set = function(k, v) PlacedCfg().type = v; GF.RefreshVisuals() end,
            })

            -- Anchor dropdown
            local anchorDd = SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_Anchor", parent = panel,
                anchor = typeDd, x = 0, y = -4, width = 140,
                items = ANCHOR9,
                get = function(k) return PlacedCfg().anchor or "TOPLEFT" end,
                set = function(k, v) PlacedCfg().anchor = v; GF.RefreshVisuals() end,
            })

            -- Size slider
            local sizeSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Size", parent = panel, compact = true,
                anchor = anchorDd, x = 16, y = -10,
                min = 4, max = 40, step = 1, width = 160, default = 18,
                get = function(k) return PlacedCfg().size or 18 end,
                set = function(k, v) PlacedCfg().size = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format("Size: %d", v) end,
            })

            -- X/Y offset
            local xSl = SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_X", parent = panel, compact = true,
                anchor = sizeSl, x = 0, y = -32,
                min = -100, max = 100, step = 1, width = 160, default = 0,
                get = function(k) return PlacedCfg().x or 0 end,
                set = function(k, v) PlacedCfg().x = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format("X: %d", v) end,
            })

            SSlider({
                name = "MSUF_GF_SI_" .. auraName .. "_Y", parent = panel, compact = true,
                anchor = xSl, x = 0, y = -32,
                min = -100, max = 100, step = 1, width = 160, default = 0,
                get = function(k) return PlacedCfg().y or 0 end,
                set = function(k, v) PlacedCfg().y = v; GF.RefreshVisuals() end,
                formatText = function(v) return string.format("Y: %d", v) end,
            })

            -- Show when missing
            SCheck({
                name = "MSUF_GF_SI_" .. auraName .. "_Missing", parent = panel,
                anchor = xSl, x = 0, y = -48,
                label = TR("Show When Missing"),
                get = function(k) return PlacedCfg().missing == true end,
                set = function(k, v) PlacedCfg().missing = v and true or false; GF.RefreshVisuals() end,
            })

            -- Divider
            local div = panel:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(0.3, 0.3, 0.3, 0.4)
            div:SetPoint("TOPLEFT", xSl, "BOTTOMLEFT", 0, -70)
            div:SetPoint("RIGHT", panel, "RIGHT", -10, 0)

            -- Frame effect dropdown
            local fxLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fxLbl:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -8)
            fxLbl:SetText(TR("Frame Effect"))
            fxLbl:SetTextColor(1, 0.82, 0)

            SDropdown({
                name = "MSUF_GF_SI_" .. auraName .. "_FX", parent = panel,
                anchor = fxLbl, x = -16, y = -6, width = 160,
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
                end,
            })

            panel:Hide()
            spellPanels[auraName] = panel
            return panel
        end

        -- Build spell tiles
        local function RefreshSpellTiles()
            -- Hide all existing tiles
            if tileContainer._tiles then
                for _, tile in pairs(tileContainer._tiles) do tile:Hide() end
            end
            tileContainer._tiles = tileContainer._tiles or {}

            local siCfg = SIC()
            local specKey
            if siCfg.spec == "auto" then
                specKey = SI and SI.GetPlayerSpec and SI.GetPlayerSpec()
            else
                specKey = siCfg.spec
            end
            if not specKey then return end

            local trackable = SI and SI.TrackableAuras and SI.TrackableAuras[specKey]
            if not trackable then return end

            local TILE_SIZE = 52
            local TILE_GAP = 4
            local TILES_PER_ROW = 10
            local idx = 0

            for _, info in ipairs(trackable) do
                idx = idx + 1
                local col = (idx - 1) % TILES_PER_ROW
                local row = math.floor((idx - 1) / TILES_PER_ROW)

                local tile = tileContainer._tiles[idx]
                if not tile then
                    tile = CreateFrame("Button", nil, tileContainer, "BackdropTemplate")
                    tile:SetSize(TILE_SIZE, TILE_SIZE)
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

                    tileContainer._tiles[idx] = tile
                end

                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", tileContainer, "TOPLEFT",
                              col * (TILE_SIZE + TILE_GAP), -row * (TILE_SIZE + TILE_GAP))

                -- Icon + label
                local iconTex = SI and SI.GetAuraIcon(specKey, info.name) or 136243
                tile._icon:SetTexture(iconTex)
                tile._label:SetText(info.display)

                -- Color accent from aura color
                local c = info.color or {0.5, 0.5, 0.5}
                tile:SetBackdropBorderColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.8)

                -- Secret badge
                if info.secret then
                    tile._label:SetTextColor(0.7, 0.6, 0.9)
                else
                    tile._label:SetTextColor(0.9, 0.9, 0.9)
                end

                -- Hover
                local auraName = info.name
                tile:SetScript("OnEnter", function(self)
                    self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
                    self:SetBackdropColor(0.15, 0.15, 0.18, 1)
                end)
                tile:SetScript("OnLeave", function(self)
                    self:SetBackdropBorderColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.8)
                    self:SetBackdropColor(0.10, 0.10, 0.12, 1)
                end)

                -- Click → expand spell config panel
                tile:SetScript("OnClick", function()
                    HideAllSpellPanels()
                    if expandedSpell == auraName then
                        expandedSpell = nil
                        return
                    end
                    expandedSpell = auraName
                    local panel = BuildSpellPanel(auraName, specKey, tile)
                    panel:ClearAllPoints()
                    -- Position below tile grid
                    local totalRows = math.ceil(#trackable / TILES_PER_ROW)
                    local gridH = totalRows * (TILE_SIZE + TILE_GAP) + 8
                    panel:SetPoint("TOPLEFT", tileContainer, "TOPLEFT", 0, -gridH)
                    panel:Show()
                end)

                tile:Show()
            end

            -- Set tile container height
            local totalRows = math.ceil(idx / TILES_PER_ROW)
            tileContainer:SetHeight(totalRows * (TILE_SIZE + TILE_GAP) + 280)
        end

        RefreshSpellTiles()
        refreshFns[#refreshFns + 1] = function()
            RefreshSpecLabel()
            RefreshSpellTiles()
        end
    end
end

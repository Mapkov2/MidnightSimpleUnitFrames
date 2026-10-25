-- Frozen hand setters captured before the schema accessor conversion.
return {
    ["H4.AdvancedGameplay.Text"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedGameplay.lua",
        source = [====[set = function(value) setValue(value) apply() end]====] },
    ["AdvancedClassPower.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value) SetValue(source(), key, value, apply) end]====] },
    ["AdvancedClassPower.11"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value) SetValue(Bars(), "playerHPBarEnabled", value, applyRefresh) end]====] },
    ["AdvancedClassPower.12"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value) SetValue(Bars(), "showAltMana", value, applyRefresh) end]====] },
    ["AdvancedClassPower.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value) SetValue(Bars(), "showClassPower", value, applySourceRefresh) end]====] },
    ["AdvancedGameplay.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedGameplay.lua", source = [====[row.set = function(value)
        if row[1] == "dropdown" and not value then value = fallback end
        return AP.SetValue(Gameplay(), key, value, apply or defaultApply)
    end]====] },
    ["AdvancedGameplay.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedGameplay.lua", source = [====[set = function(value) return AP.SetValue(Gameplay(), key, value, apply) end]====] },
    ["GlobalMisc.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(v)
                SetGBool(key, v, reason, opts or PREVIEW_FALSE)
                if afterSet then afterSet(v) end
            end]====] },
    ["GlobalMisc.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(value)
                    SetG("menuBackgroundOpacity", value, "MSUF2_MENU_BACKGROUND", MENU_WRITE_OPTS)
                    if T.RefreshMenuBackgroundOpacity then T.RefreshMenuBackgroundOpacity() end
                end]====] },
    ["Group.8"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group_Order.lua", source = [====[set = function(value)
                    Set(CurrentScope(), "growth", value, "geometry")
                    RefreshGrowthTiles()
                end]====] },
    ["GroupBars.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(value) Set(CurrentScope(), key, tonumber(value) or default, mode) end]====] },
    ["GroupBars.16"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(v) Set(CurrentScope(), "rangeFadeLayerMode", v or "frame", "visual") end]====] },
    ["GroupBars.7"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(v)
                Set(CurrentScope(), "powerBarBorderEnabled", v and true or false, "color")
                RequestGroupBarsRefresh(ctx, "gf-bars-power-border")
            end]====] },
    ["GroupLayout.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua", source = [====[set = function(value)
                -- Keep the configured Blizzard fallback when toggling MSUF off.
                Set(CurrentScope(), "enabled", value == true, "rebuild")
                M.Refresh(ctx)
            end]====] },
    ["GroupLayout.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua", source = [====[set = function(value) Set(CurrentScope(), spec.key, tonumber(value) or spec.default, "visual") end]====] },
    ["GroupLayoutAdditional.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupLayoutAdditional.lua", source = [====[set = function(value)
                GP.Set(GP.CurrentScope(), key, value, mode)
                GP.RefreshContext(ctx)
            end]====] },
    ["UnitAlpha.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitAlpha.lua", source = [====[set = function(value)
                    Schema.SetUnit(row.domain, unit, row.key, value, row.reason, row.kind)
                    if row.key == "oocFadeEnabled" then
                        UP.SetControlEnabled(controls.oocFadeAlpha, ReadBool(unit, row.key, Default()))
                    end
                end]====] },
    ["UnitArenaTrinket.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitArenaTrinket.lua", source = [====[row.set = function(value)
                Schema.SetUnit("arenaTrinket", unit, key, value, APPLY_REASON, kind)
                if kind == "toggle" then RefreshGate() end
            end]====] },
    ["UnitFrameVisuals.19"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v) SetBool(unit, "showInterrupt", v, "MSUF2_CASTBAR_INTERRUPT", { castbar = true, preview = true }) end]====] },
    ["UnitFrameVisuals.20"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v) SetBool(unit, "showInterruptSource", v, "MSUF2_CASTBAR_INTERRUPT_SOURCE", { castbar = true, preview = true }) end]====] },
    ["UnitFrameVisuals.22"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v)
                if not key then return end
                SetGeneralNumber(key, v, reason)
            end]====] },
    ["UnitFrameVisuals.23"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v)
                SetGeneralBool(field, v, reason, { castbar = true, preview = true })
                RefreshCastbarEnabled()
            end]====] },
    ["UnitFrameVisuals.24"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v)
            SetPortraitValue(unit, "portraitCastSpellIcon", v and true or false, "MSUF2_PORTRAIT_CAST_ICON")
            M.RequestRefresh(ctx, "portrait-cast-icon-mirror")
        end]====] },
    ["UnitFrameVisuals.25"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v)
                SetGeneralBool(fields.targetName, v, "MSUF2_CASTBAR_TARGET_NAME", { castbar = true, preview = true })
                RefreshCastbarEnabled()
            end]====] },
    ["UnitFrameVisuals.27"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v) SetGeneralNumber(DetailKey("SpellNameMaxWidth"), v, "MSUF2_CASTBAR_SPELL_MAX_WIDTH") end]====] },
    ["UnitFrameVisuals.28"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v) SetGeneralNumber(DetailKey("FrameLevelOffset"), v, "MSUF2_CASTBAR_LAYER") end]====] },
    ["UnitFrameVisuals.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(value) SetPortraitValue(unit, "portraitBlizzardDirection", value, "MSUF2_PORTRAIT_BLIZZARD_DIRECTION") end]====] },
    ["UnitFrameVisuals.8"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v)
            SetBool(unit, "showPowerBar", v, "MSUF2_POWER_SHOW", { power = true, preview = true })
            EnsureCooldownWidthObservers()
            if show.refreshDetails then show.refreshDetails() end
        end]====] },
    ["UnitRangeFade.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua", source = [====[enabledRow.set = function(value)
        Schema.SetUnit("range", unit, enabledRow[2], value, "MSUF2_RANGE_FADE", "toggle")
        RefreshRangeControls()
    end]====] },
    ["UnitRangeFade.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua", source = [====[alphaRow.set = function(value)
        Schema.SetUnit("range", unit, alphaRow[2], value, "MSUF2_RANGE_FADE_ALPHA", "slider")
    end]====] },
    ["UnitSections.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(v)
                SetBool(unit, "enabled", v, "MSUF2_FRAME_ENABLED", { preview = true })
                M.Refresh(ctx)
            end]====] },
    ["UnitSections.12"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(v)
                local conf = GetConf("targettarget")
                conf.showToTInTargetName = v and true or false
                ApplyToTInline("MSUF2_TOT_INLINE")
            end]====] },
    ["UnitSections.17"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(v)
                GetConf(unit)[key] = v
                Apply()
            end]====] },
    ["UnitSections.19"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(v)
                GetConf(unit).bossTargetMultipleOnly = v == true
                Apply()
            end]====] },
    ["UnitText.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v)
                    SetBool(unit, key, v, "MSUF2_TEXT_MOUSEOVER", { text = true, preview = true })
                    RefreshTextControlState()
                end]====] },
    ["UnitText.14"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v) SetText(unit, cfg.separatorKey, v or "", cfg.separatorReason) end]====] },
    ["UnitText.15"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v) SetText(unit, cfg.reverseKey, v and true or false, cfg.reverseReason) end]====] },
    ["UnitText.16"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v) SetText(unit, cfg.decimalsKey, v and true or false, cfg.decimalsReason) end]====] },
    ["UnitText.17"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v)
                SetText(unit, cfg.fullValueShortKey, v and true or false, cfg.fullValueShortReason)
                if controls.RefreshPreview then controls.RefreshPreview() end
            end]====] },
    ["UnitText.18"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v)
                SetNumber(unit, key, v, reason, { text = true, fonts = true, preview = true })
                RefreshTextHeader()
            end]====] },
    ["UnitText.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v) SetNumber(unit, settingKey, v, "MSUF2_TEXT_MOUSEOVER_FADE", { text = true, preview = true }) end]====] },
    ["UnitText.4"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v)
            SetBool(unit, "showName", v, "MSUF2_SHOW_NAME_TEXT", { text = true, preview = true })
            RefreshTextControlState()
        end]====] },
    ["UnitText.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v)
            SetText(unit, "nameTextAnchor", v or "TOPLEFT", "MSUF2_NAME_ANCHOR")
            FocusPreviewText("name", nil, true)
            RefreshTextHeader()
        end]====] },
    ["UnitText.6"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v) SetNumber(unit, "nameFontSize", v, "MSUF2_NAME_SIZE", { text = true, fonts = true, preview = true }) end]====] },
    ["UnitText.9"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v)
            SetBool(unit, cfg.showKey, v, cfg.showReason, { text = true, preview = true })
            RefreshTextControlState()
        end]====] },
    ["AdvancedColors.7"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Frames.lua", source = [====[set = function(v)
            G().petFrameUsePlayerClassColor = v and true or false
            M.RequestUnitDomains("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
            RefreshPetColorControl()
        end]====] },
    ["AdvancedColors.9"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Frames.lua", source = [====[set = function(v)
                G().tapDeniedGray = v and true or false
                ApplyUnitframeColorWithReload()
                SetControlEnabled(tappedColor, v and true or false)
            end]====] },
    ["UnitSections.4"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(v)
                GetGeneral().petFrameUsePlayerClassColor = v and true or false
                M.RequestUnitDomains("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
                if M.Refresh then M.Refresh(ctx) end
            end]====] },
    ["UnitSections.15"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(v)
                GetConf(unit)[key] = v and true or false
                UpdateLoadActive(unit)
                M.RequestUnitDomains(unit, "MSUF2_LOAD_CONDITION", { preview = true })
            end]====] },
    ["GlobalBars.19"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars_Highlights.lua", source = [====[set = function(v)
            v = v and true or false
            local bars = Bars()
            if bars.realtimePowerText == v then return end
            bars.realtimePowerText = v
            -- Recompile Player and rebind both Power and PowerText events.
            -- A generic Bars layout refresh leaves this event option dead.
            M.RequestUnitDomains("player", "MSUF2_BARS_REALTIME_POWER", {
                preview = true, power = true, text = true,
            })
        end]====] },
    ["GlobalBars.11"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars_Shapes.lua", source = [====[set = function(value)
            value = floor((tonumber(value) or 3) + 0.5)
            if value < 1 then value = 1 elseif value > 5 then value = 5 end
            local bars = Bars()
            if bars.roundedCornerStrength == value then return end
            bars.roundedCornerStrength = value
            QueueRoundingRuntime()
        end]====] },
    ["GlobalMisc.6"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(value)
            SetG("highlightThickness", floor((tonumber(value) or 6) + 0.5),
                "MSUF2_MOUSEOVER_SIZE", MOUSEOVER_WRITE_OPTS)
        end]====] },
    ["GroupBars.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(v)
                v = floor(max(1, min(30, tonumber(v) or CurrentPowerHeight(CurrentScope()))) + 0.5)
                Set(CurrentScope(), "powerHeight", v, "geometry")
            end]====] },
    ["GroupBars.15"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(v)
                    local n = tonumber(v) or default or 0
                    local conf = Conf(CurrentScope())
                    if conf[key] == n then return end
                    conf[key] = n
                    QueueGF(CurrentScope(), "visual")
                end]====] },
    ["GroupPriority.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua", source = [====[set = function(value) SetPriorityOption(ctx, "anchorMode", value or "RAID_RIGHT", "Priority Frames placement") end]====] },
    ["GroupPriority.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua", source = [====[set = function(value) SetPriorityOption(ctx, "growth", value or "DOWN", "Priority Frames growth") end]====] },
    ["GroupPriority.4"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua", source = [====[set = function(value) SetPriorityOption(ctx, "enabled", value == true, "Enable Priority Frames") end]====] },
    ["GroupPriority.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua", source = [====[set = function(value) SetPriorityOption(ctx, "autoTanks", value == true, "Priority Frames automatic tanks") end]====] },
    ["GroupPriority.6"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua", source = [====[set = function(value) SetPriorityOption(ctx, "maxFrames", tonumber(value) or 5, "Priority Frames visible slots") end]====] },
    ["SwingTimers.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_SwingTimers.lua", source = [====[set = function(value) Swing.Set(hand, key, value) ui.Paint() end]====] },
    ["Schema.Unit"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua", source = [====[set = function(value)
        Schema.SetUnit(spec.applyDomain, spec.unit, spec.key, value, spec.reason, spec.kind)
        if spec.after then spec.after(value) end
    end]====] },
    ["Schema.Source"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua", source = [====[set = function(value)
        if spec.kind == "dropdown" and not value then value = spec.defaultSource() end
        return M.AdvancedPage.SetValue(source(), spec.key, value, spec.apply)
    end]====] },
    ["Schema.Group"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua", source = [====[set = function(value)
        if kind == "toggle" then
            gp.Set(gp.CurrentScope(), key, value and true or false, domain)
            gp.RefreshContext(ctx)
        elseif kind == "slider" then
            gp.Set(gp.CurrentScope(), key, math.floor((tonumber(value) or default or 0) + 0.5), domain)
        else gp.Set(gp.CurrentScope(), key, value or default, domain) end
    end]====] },
    ["Schema.Record"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua", source = [====[set = function(value, green, blue)
        if row.accept and not row.accept(value) then return end
        local record = config(scope(), true)
        if kind == "color" then
            if record then record[row.channels[1]], record[row.channels[2]], record[row.channels[3]] = value, green, blue end
        elseif row.subtype then
            if not record then return end
            if value == "none" then record[key] = false
            else
                record[key] = type(record[key]) == "table" and record[key] or {}
                record[key].type = value
                if row.defaults then row.defaults(record[key]) end
            end
        elseif not record and row.requireRecord then return
        elseif record then
            if row.convert then
                local converted = row.convert(value)
                record[key] = converted
                if row.afterWrite then row.afterWrite(record, converted) end
            elseif kind == "toggle" then
                if row.uncheckedNil then record[key] = value and true or nil
                elseif owner.strictToggles then record[key] = value == true
                else record[key] = value and true or false end
            elseif kind == "slider" then
                local number = tonumber(value) or default
                record[key] = owner.rawNumber and number or math.floor(number + 0.5)
            else record[key] = value or default end
        end
        owner.changed(scope())
        local afterSet = row.afterSet or (kind == "toggle" and owner.afterToggle)
        if afterSet then afterSet() end
    end]====] },
    ["Advanced.TableBool"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Advanced.lua", source = [====[set = function(v) SetValue(getTable(), key, v, apply) end]====] },
    ["Advanced.TableNumber"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Advanced.lua", source = [====[set = function(v) SetValue(getTable(), key, v, apply) end]====] },
    ["Advanced.TableChoice"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Advanced.lua", source = [====[set = function(v) SetValue(getTable(), key, v or default, apply) end]====] },
    ["GlobalCastbars.Rows"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua", source = [====[set = function(value)
                local nextValue = value
                if kind == "slider" then
                    local fallback = row.writeDefault ~= nil and row.writeDefault or default
                    nextValue = row.precise and (tonumber(value) or fallback) or floor((tonumber(value) or fallback) + 0.5)
                elseif kind == "dropdown" then
                    nextValue = value or default
                end
                if kind == "toggle" then SetGBool(key, nextValue, reason, { castbar = true, preview = true })
                else SetG(key, nextValue, reason, { castbar = true, preview = true }) end
                if row.afterWrite then row.afterWrite(reason, nextValue, true) end
            end]====] },
    ["Group.Portrait"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group_Portrait.lua", source = [====[set = function(value)
                if controlKind == "toggle" then value = value and true or false
                elseif controlKind == "slider" then value = tonumber(value) or default
                else value = row.normalize and row.normalize(value or default) or (value or default) end
                SetValue(key, value)
                if row.afterSet then row.afterSet() end
            end]====] },
    ["Schema.Scope"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua", source = [====[set = function(value)
        local field = Target()
        if row.select then M.SetMenuStateValue(row.select[1], row.select[2]) end
        if row.scale then value = (tonumber(value) or row.fallback) / row.scale
        else
            local fallback = row.writeDefault
            if fallback == nil then fallback = default end
            value = value or fallback
        end
        gp.Set(gp.CurrentScope(), field, value, row.domain or "visual")
        if row.afterSet then row.afterSet() end
    end]====] },
    ["UnitFrameVisuals.PowerRows"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(value)
                    if kind == "toggle" then
                        SetBool(unit, key, value, row.reason, row.opts or POWER_OPTS)
                        if row.afterSet then row.afterSet() end
                    elseif key == "detachedPowerBarWidth" then
                        return SetManualDetachedPowerWidth(value, row.reason)
                    else return SetNumber(unit, key, value, row.reason, row.opts or POWER_OPTS) end
                end]====] },
    ["UnitDispel.Rows"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitDispel.lua", source = [====[set = function(value)
        if row.kind == "dropdown" then value = normalize and normalize(value) or (value or default)
        elseif row.kind == "toggle" then value = value and true or false
        else value = tonumber(value) or default end
        SetValue(unit, key, value, row.reason)
        if row.sync then Sync() end
    end]====] },
    ["UnitFrameVisuals.PortraitRows"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(value)
            if kind == "slider" then SetNumber(unit, key, value, row.reason, { preview = true })
            else
                if kind == "toggle" then value = value and true or false
                else value = row.normalize and row.normalize(value or fallback) or (value or fallback) end
                SetPortraitValue(unit, key, value, row.reason)
            end
            if row.afterSet then row.afterSet() end
        end]====] },
    ["UnitFrameVisuals.DetailRows"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(value)
                if kind == "slider" then
                    if row.beforeSet then row.beforeSet(value) end
                    SetGeneralNumber(key, value, row.reason)
                else
                    SetGeneralValue(key, value or fallback, row.reason)
                    if row.afterSet then row.afterSet() end
                end
            end]====] },
    ["GroupPriority.Sliders"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupPriority.lua", source = [====[set = function(value)
            if rounded then value = floor((tonumber(value) or fallback) + 0.5) end
            SetPriorityOption(ctx, key, value, historyLabel or label)
        end]====] },
    ["GlobalMisc.Language"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(value)
            value = value or "auto"
            SetG("menuLocale", value, "MSUF2_LOCALE", { preview = false, applyAll = false, noRuntime = true })
        end]====] },
    ["H4.AdvancedClassPower.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value)
            Bars().classPowerShapeAlign = NormalizeClassPowerShapeAlign(value)
            ApplyClassPower()
        end]====] },
    ["H4.AdvancedClassPower.4"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value)
            local player = Player()
            value = NormalizePlayerPowerSource(value)
            if player.playerPowerSource == value then return end
            player.playerPowerSource = value
            M.ApplyPlayerPowerSource("MSUF2_CLASSPOWER_PLAYER_POWER_SOURCE")
        end]====] },
    ["H4.GlobalCastbars.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua", source = [====[set = function(value)
                local duration = max(0, min(5, tonumber(value) or 0.5))
                SetG("castbarInterruptFeedbackDuration", duration, "MSUF2_CASTBAR_INTERRUPT_DURATION", { preview = true })
                MSUF.Castbars.Config.Refresh()
                M.PlayCastbarPreviewInterrupt()
            end]====] },
    ["H4.GlobalCastbars.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua", source = [====[set = function(v)
                SetG("castbarSpellNameShortening", v and 1 or 0, "MSUF2_CASTBAR_NAME_SHORTEN", { castbar = true, preview = true })
                RequestCastPreviewRefresh()
                if syncNameShortening then syncNameShortening() end
            end]====] },
    ["H4.GlobalCastbars.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua", source = [====[set = function(v)
                SetG("focusKickTextSize", floor((tonumber(v) or 12) + 0.5), "MSUF2_FOCUS_KICK_TEXT", { castbar = true, preview = true })
                RequestFocusKickTextFont()
                ApplyFocusKickOptions()
            end]====] },
    ["H4.GlobalMisc.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(value)
            value = (value == "COMPACT") and "COMPACT" or "GAME"
            -- Persist without a runtime apply, push the new style, then repaint
            -- once - so the refresh already formats with the new options instead of
            -- painting stale text and correcting it on the next unit event.
            SetG("numberAbbrevStyle", value, "MSUF2_NUMBER_ABBREV", MENU_WRITE_OPTS)
            local NumberFormat = MSUF.NumberFormat
            if NumberFormat and NumberFormat.Refresh then NumberFormat.Refresh() end
            M.RequestGeneralDomains("MSUF2_NUMBER_ABBREV_TEXT", { text = true })
            MSUF.GF.RefreshVisuals()
            RefreshAbbrevSample()
        end]====] },
    ["H4.Group.7"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group_Portrait.lua", source = [====[set = function(value)
                SetValue("portraitSizeMode", value == "SEPARATE" and "SEPARATE" or "UNIFORM")
                RefreshPortraitControls()
            end]====] },
    ["H4.GroupBars.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(value)
            Set(CurrentScope(), row[2], NormalizeGFDispelOverlayTrigger(value), "visual")
            RequestGroupBarsRefresh(ctx, row.reason)
        end]====] },
    ["H4.GroupLayout.7"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua", source = [====[set = function(v)
                local conf = Conf(CurrentScope())
                local selectedValue1
                if not ((v == "FREE")) then selectedValue1 = v end
                conf.anchorToFrame = selectedValue1
                QueueGF(CurrentScope(), "rebuild")
            end]====] },
    ["H4.GroupLayoutAdditional.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupLayoutAdditional.lua", source = [====[set = function(v) GP.Set(GP.CurrentScope(), key, max(0, min(100, floor((tonumber(v) or 0) + 0.5))) / 100, "rebuild") end]====] },
    ["H4.ResourceExtras.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_ResourceExtras.lua", source = [====[row.set=function(value)
            Bars()[group.master]=value and true or false
            FocusExample(page,group)
            Apply()
        end]====] },
    ["H4.UnitDispel.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitDispel.lua", source = [====[spec.set = function(value)
        if row.kind == "dropdown" then value = normalize and normalize(value) or (value or default)
        elseif row.kind == "toggle" then value = value and true or false
        else value = tonumber(value) or default end
        SetValue(unit, key, value, row.reason)
        if row.sync then Sync() end
    end]====] },
    ["H4.UnitFrameVisuals.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[row.set = function(value)
            if kind == "slider" then SetNumber(unit, key, value, row.reason, { preview = true })
            else
                if kind == "toggle" then value = value and true or false
                else value = row.normalize and row.normalize(value or fallback) or (value or fallback) end
                SetPortraitValue(unit, key, value, row.reason)
            end
            if row.afterSet then row.afterSet() end
        end]====] },
    ["H4.UnitFrameVisuals.8"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(value) SetBool(unit, "showPowerBar", value == true, "MSUF2_POWER_SHOW", { power = true, preview = true }) end]====] },
    ["H4.UnitFrameVisuals.9"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(value)
                GetConf(unit).playerPowerSource = NormalizePlayerPowerSource(value)
                M.ApplyPlayerPowerSource("MSUF2_PLAYER_POWER_SOURCE")
            end]====] },
    ["H4.UnitFrameVisuals.15"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[row.set = function(value)
                if kind == "slider" then
                    if row.beforeSet then row.beforeSet(value) end
                    SetGeneralNumber(key, value, row.reason)
                else
                    SetGeneralValue(key, value or fallback, row.reason)
                    if row.afterSet then row.afterSet() end
                end
            end]====] },
    ["H4.UnitRangeFade.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua", source = [====[modeRow.set = function(value)
        Schema.SetUnit("range", unit, modeRow[2], value == "health" and "health" or modeRow[3], "MSUF2_RANGE_FADE_LAYER", "segment")
    end]====] },
    ["H4.UnitRangeFade.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua", source = [====[rateRow.set = function(value)
            local rate = floor((tonumber(value) or 0) + 0.5)
            if rate < 0 then rate = 0 elseif rate > 20 then rate = 20 end
            Schema.SetUnit("range", unit, rateRow[2], rate, "MSUF2_BOSS_RANGE_UPDATE_RATE", "slider")
            if updateRate and updateRate._msuf2SliderActive then
                updateRate._msuf2BossRateWarningPending = rate > 0 and rate or nil
            else
                MaybeShowBossUpdateRateWarning(rate)
            end
        end]====] },
    ["H4.UnitSections.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(v)
                local conf = GetConf(unit)
                conf.healthColorMode = NormalizeHealthColorMode(v)
                M.RequestUnitDomains(unit, "MSUF2_HEALTH_COLOR_MODE", { preview = true, colors = true })
                if M.Refresh then M.Refresh(ctx) end
            end]====] },
    ["H4.UnitSections.6"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(value) SetBool(unit, "enabled", value == true, "MSUF2_FRAME_ENABLED", { preview = true }) end]====] },
    ["H4.UnitStatusSection.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    SetBool(unit, spec.show, value == true, "MSUF2_STATUS_ENABLED", { preview = true })
                    RefreshStatusRuntime(unit, spec)
                    if Refresh then Refresh() end
                    return true
                end]====] },
    ["H4.UnitTextureLayer.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitTextureLayer.lua", source = [====[row.set = function(value)
                        if kind == "toggle" then SetBool(unit, Key(base), value, "MSUF2_TEXLAYER", { preview = true })
                        elseif kind == "slider" then SetNumber(unit, Key(base), value, "MSUF2_TEXLAYER", { preview = true })
                        else SetString(unit, Key(base), value or default, "MSUF2_TEXLAYER", { preview = true }) end
                        RefreshLayer()
                        if row.afterSet then row.afterSet() end
                    end]====] },
    ["H4.UnitTextureLayer.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitTextureLayer.lua", source = [====[set = function(v)
                SetString(unit, Key("BlendMode"), v and "ADD" or "BLEND", "MSUF2_TEXLAYER", { preview = true })
                RefreshLayer()
            end]====] },
    ["H4.GlobalCastbars.4"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua", source = [====[set = function(v)
                if M.SetGeneralValue("focusKickShowCastbar", v and true or false, "MSUF2_FOCUS_KICK_CASTBAR",
                    { applyAll = false, preview = false, notify = false }) then
                    MSUF.Castbars.Config.Refresh()
                    forceUpdate = forceUpdate or MSUF.Require("MSUF_FocusKickDriver_ForceUpdate", FILE)
                    forceUpdate()
                end
            end]====] },
    ["H4.Group.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group_Portrait.lua", source = [====[set = function(value)
                value = tonumber(value)
                if value == nil then return false end
                SetValue(key, value)
                return true
            end]====] },
    ["H4.Group.4"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group_Portrait.lua", source = [====[set = function(value)
                if controlKind == "toggle" then value = value and true or false
                elseif controlKind == "slider" then value = tonumber(value) or default
                else value = row.normalize and row.normalize(value or default) or (value or default) end
                SetValue(key, value)
                if row.afterSet then row.afterSet() end
            end]====] },
    ["H4.GroupBars.11"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(v)
                Set(CurrentScope(), SlotFontSizeKey(kind), v, "font")
                FocusGFPreviewText(kind, CurrentSlot(kind), true)
            end]====] },
    ["H4.SwingTimers.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_SwingTimers.lua", source = [====[set = function(value) Swing.SetEnabled(value) M.Refresh(ctx) end]====] },
    ["H4.UnitFrameVisuals.6"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(value)
            value = value == "SEPARATE" and "SEPARATE" or "UNIFORM"
            SetPortraitValue(unit, "portraitSizeMode", value, "MSUF2_PORTRAIT_SIZE_MODE")
            p.Refresh()
        end]====] },
    ["H4.UnitText.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", source = [====[set = function(v)
                SetNumber(unit, SlotFontSizeKey(kind), v, cfg.slotSizeReason, { text = true, fonts = true, preview = true })
                FocusPreviewText(kind, CurrentSlot(kind), true)
            end]====] },
    ["H4.GlobalMisc.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(value)
                local groupPage = M.GroupPage
                if groupPage and type(groupPage.Set) == "function" then
                    groupPage.Set(kind, "targetIndicator", value and true or false, "visual")
                end
            end]====] },
    ["H4.UnitFrameVisuals.21"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v)
            local key = CastbarWidthSourceKey()
            if not key then return end
            local nextValue = NormalizeWidthSource(v)
            SetGeneralValue(key, nextValue, "MSUF2_CASTBAR_WIDTH_MODE")
            RefreshCastbarEnabled()
        end]====] },
    ["H4.UnitSections.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua", source = [====[set = function(v)
                if unit == "pettarget" or ReadBool(unit, "useBlizzardFrame", false) == (v == true) then return end
                SetBool(unit, "useBlizzardFrame", v, "MSUF2_BLIZZARD_FRAME_OWNERSHIP", { preview = false })
                local reloadLabel = M.Format("%s Blizzard frame ownership", label or UnitTopLabel(unit))
                Core.ShowReloadPopup(reloadLabel)
            end]====] },
    ["H4.AdvancedColors.10"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Frames.lua", source = [====[set = function(v)
            if not ApiCall("SetNPCColorMode", v and "type" or "reaction") then
                G().npcColorMode = v and "type" or "reaction"
                ApplyUnitframeColorWithReload()
            end
            RefreshNPCTypeControls(v and true or false)
        end]====] },
    ["H4.GroupBars.8"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(value)
                local spec, oldMode = SelectedSlotSpec(), CurrentMode()
                local mode = value or spec.default
                if hasAbsorb and M.UnitSectionsShared.HealthModeHasAbsorb(oldMode) and M.UnitSectionsShared.HealthModeSupportsAbsorb(mode) then
                    mode = M.UnitSectionsShared.HealthModeWithAbsorb(mode, true)
                end
                Set(CurrentScope(), spec.key, mode, "visual")
                AfterModeChanged(mode)
            end]====] },
    ["H4.GroupBars.10"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", source = [====[set = function(value)
            local spec = SelectedSlotSpec()
            if spec.hidePercentKey then Set(CurrentScope(), spec.hidePercentKey, value and true or false, "visual") end
            FocusGFPreviewText(kind, CurrentSlot(kind), true)
            RequestGroupBarsRefresh(ctx, "gf-bars-text-hide-percent-symbol")
        end]====] },
    ["H4.ResourceExtras.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_ResourceExtras.lua", source = [====[row.set=function(value) Write(key,value) end]====] },
    ["H4.Group.RoleOrder"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group_Order.lua", source = [====[set = function(value)
                local changed = ApplyRoleOrder(value)
                if changed and holder and holder.Refresh then holder.Refresh() end
                return changed
            end]====] },
    ["J5.GroupAuras.AutoBlacklist"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua", source = [====[set = function(value)
            local activeScope = CurrentScope()
            AuraGroup(activeScope, "externals").autoBlacklistBuffs = value == true
            if QueueGF then QueueGF(activeScope, "auras") end
            RefreshContext(ctx)
        end]====] },
    ["J5.GlobalBars.OutlineTexture"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars_Shapes.lua", source = [====[set = function(value)
            BarScopeSetBars("barOutlineTexture", value or "", "MSUF2_BAR_OUTLINE_TEXTURE", true)
            RequestOutlineRuntime()
        end]====] },
    ["J5.ClassPower.SourceToggle"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value)
            value = value and true or false
            if source == Player then SetPlayerTextValue(key, value, apply) else SetValue(source(), key, value, apply) end
        end]====] },
    ["J5.ClassPower.Alpha"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value)
            value = tonumber(value) or ((default or 0) * 100)
            if value < 0 then value = 0 elseif value > 100 then value = 100 end
            SetValue(Bars(), key, value / 100, apply)
        end]====] },
    ["J5.ClassPower.NilDropdown"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value)
                source()[key] = value ~= default and value or nil
                apply()
            end]====] },
    ["J5.Schema.Selected"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ControlSchema.lua", source = [====[set = function(value)
        local spec = selected()
        if kind == "dropdown" then
            local key = spec and spec[field]
            if not key then return end
            owner.write(scope(), key, value or default(spec, valueDefault), domain)
        else
            if kind == "toggle" then value = value and true or false
            else value = math.floor((tonumber(value) or default(spec, valueDefault)) + 0.5) end
            if row.clamp then
                if value < low then value = low elseif value > high then value = high end
            end
            owner.write(scope(), spec[field], value, domain)
        end
        if row.afterSet then row.afterSet() end
    end]====] },
    ["J5.CustomLists.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Lists.lua", source = [====[set = function(value)
                item.reminderEnchantDurationMinutes = tonumber(value) or 60
                Apply("AURAS3_CUSTOM_REMINDER_ENCHANT_DURATION", true)
            end]====] },
    ["J5.CustomStyle.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
item.filters.maxDuration = Round(min(180, max(0, tonumber(value) or 0)))
                Apply("AURAS3_CUSTOM_MAX_DURATION", true)
end]====] },
    ["J5.CustomStyle.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                    item.filters.hidePermanent = value == true
                    Apply("AURAS3_CUSTOM_HIDE_PERMANENT", true)
                end]====] },
    ["J5.CustomStyle.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.filters.enabled = value == true
                Apply("AURAS3_CUSTOM_FILTER_ENABLE", true)
            end]====] },
    ["J5.CustomStyle.4"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.filters.hidePermanent = value == true
                Apply("AURAS3_CUSTOM_HIDE_PERMANENT", true)
            end]====] },
    ["J5.CustomStyle.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.anchor = value or "TOPRIGHT"
                Apply("AURAS3_CUSTOM_ANCHOR")
            end]====] },
    ["J5.CustomStyle.6"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.growth = value or "LEFTDOWN"
                Apply("AURAS3_CUSTOM_GROWTH", true)
            end]====] },
    ["J5.CustomStyle.7"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed[key] = tonumber(value) or fallback
                Apply("AURAS3_CUSTOM_APPEARANCE_" .. key:upper())
                if type(afterSet) == "function" then afterSet() end
            end]====] },
    ["J5.CustomStyle.8"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.pandemicStyle = value or "BORDER"
                Apply("AURAS3_TARGET_DOT_PANDEMIC_STYLE", true)
            end]====] },
    ["J5.CustomStyle.9"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.pandemicBlend = value == "BLEND" and "BLEND" or "ADD"
                Apply("AURAS3_TARGET_DOT_PANDEMIC_BLEND", true)
            end]====] },
    ["J5.CustomStyle.10"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.pandemicBorderAlpha = (tonumber(value) or 100) / 100
                Apply("AURAS3_TARGET_DOT_PANDEMIC_BORDER_ALPHA", true)
            end]====] },
    ["J5.CustomStyle.11"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.pandemicTintAlpha = (tonumber(value) or 22) / 100
                Apply("AURAS3_TARGET_DOT_PANDEMIC_TINT_ALPHA", true)
            end]====] },
    ["J5.CustomStyle.12"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
            item.placed.iconZoom = tonumber(value) or 100
            Apply("AURAS3_CUSTOM_APPEARANCE_ICONZOOM")
        end]====] },
    ["J5.CustomStyle.13"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
            item.placed.showTooltip = value == true
            Apply("AURAS3_CUSTOM_TOOLTIP")
        end]====] },
    ["J5.CustomStyle.14"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
            item.placed.alpha = (tonumber(value) or 100) / 100
            Apply("AURAS3_CUSTOM_ALPHA")
        end]====] },
    ["J5.CustomStyle.15"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
            item.placed.stylePadding = tonumber(value) or 0
            Apply("AURAS3_CUSTOM_STYLE_PADDING")
        end]====] },
    ["J5.CustomStyle.16"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.debuffTypeBorderMode = value or "OFF"
                Apply("AURAS3_CUSTOM_DEBUFF_TYPE_BORDER")
            end]====] },
    ["J5.CustomStyle.17"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
            item.placed.showStacks = value == true
            Apply("AURAS3_CUSTOM_STACKS", true)
        end]====] },
    ["J5.CustomStyle.18"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.stackAnchor = value or "BOTTOMRIGHT"
                Apply("AURAS3_CUSTOM_STACK_ANCHOR")
            end]====] },
    ["J5.CustomStyle.19"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
            item.placed.showCooldown = value == true
            Apply("AURAS3_CUSTOM_COOLDOWN", true)
        end]====] },
    ["J5.CustomStyle.20"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
            item.placed.showCooldownSwipe = value == true
            Apply("AURAS3_CUSTOM_SWIPE", true)
        end]====] },
    ["J5.CustomStyle.21"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.cooldownAnchor = value or "CENTER"
                Apply("AURAS3_CUSTOM_COOLDOWN_ANCHOR")
            end]====] },
    ["J5.CustomStyle.22"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.cooldownSwipeReverse = value == "REVERSE"
                Apply("AURAS3_CUSTOM_SWIPE_DIRECTION")
            end]====] },
    ["J5.CustomStyle.23"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.frame.type = value or "none"
                Apply("AURAS3_CUSTOM_EFFECT")
            end]====] },
    ["J5.CustomStyle.24"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.frame.layer = floor(tonumber(value) or 0)
                Apply("AURAS3_CUSTOM_EFFECT_LAYER")
            end]====] },
    ["J5.CustomStyle.25"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.frame.thickness = tonumber(value) or 2
                Apply("AURAS3_CUSTOM_EFFECT_THICKNESS")
            end]====] },
    ["J5.CustomStyle.26"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.frame.priority = tonumber(value) or 5
                Apply("AURAS3_CUSTOM_EFFECT_PRIORITY")
            end]====] },
    ["J5.CustomStyle.27"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                    item.frame.onlyInPandemicWindow = value == true
                    Apply("AURAS3_TARGET_DOT_EFFECT_PANDEMIC_ONLY", true)
                end]====] },
    ["J5.CustomStyle.28"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.sortReverse = value == "REVERSE"
                Apply("AURAS3_CUSTOM_SORT_DIRECTION")
            end]====] },
    ["J5.CustomSetup.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Setup.lua", source = [====[set = function(value)
                    item.portraitMaxIcons = max(1, min(8, floor((tonumber(value) or 1) + 0.5)))
                    Apply(reason, true)
                end]====] },
    ["J5.CustomSetup.2"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Setup.lua", source = [====[set = function(value)
                    item[key] = value == true
                    Apply(reason, true)
                end]====] },
    ["J5.CustomSetup.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Setup.lua", source = [====[set = function(value)
                item.placed[key] = value == true
                Apply(reason, true)
            end]====] },
    ["J5.CustomSetup.4"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Setup.lua", source = [====[set = function(value)
            item.placed.reminderAlpha = max(0.1, min(1, (tonumber(value) or 45) / 100))
            Apply("AURAS3_CUSTOM_REMINDER_ALPHA", true)
        end]====] },
    ["J5.CustomSetup.5"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Setup.lua", source = [====[set = function(value)
            item.enabled = value == true
            Apply("AURAS3_CUSTOM_CONTAINER_ENABLE")
        end]====] },
    ["J5.CustomSetup.6"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Setup.lua", source = [====[set = function(value)
            item.name = (value == "" or value == shownFactoryName) and factoryName or value
            Apply("AURAS3_CUSTOM_CONTAINER_NAME")
        end]====] },
    ["J5.ClassPower.TextOnBar"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua", source = [====[set = function(value)
            local function Write()
                local player, changed = source(), false
                value = value and true or false
                if player[key] ~= value then player[key], changed = value, true end
                if changed then apply() end
                return changed
            end
            if type(M.RunWithHistory) == "function" then return M.RunWithHistory(tostring(key), "classpower:detachedPowerText:" .. key, Write) end
            return Write()
        end]====] },
    ["J5.Spell.Tracked"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators_SpellControls.lua", source = [====[set = function(value)
            local kind = CurrentScope()
            local cfg = SpellIndicators(kind)
            local specKey = CurrentSpellMultiSpec(kind)
            if specKey == "" or IsAllSpecsSpellSpec(specKey) then return end
            cfg.multiSpecs = cfg.multiSpecs or {}
            cfg.multiSpecs[specKey] = value and true or nil
            QueueSpellIndicators(kind)
            RefreshGFPreview()
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-multi-track")
        end]====] },
    ["J5.Colors.DarkBackground"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Frames.lua", source = [====[set = function(v)
            G().darkBgCustomColor = v and true or false
            ApplyBackgroundColorPreview()
        end]====] },
    ["J5.Colors.HealthText"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Text.lua", source = [====[set = function(v)
            G().colorHealthTextByHealth = (v == "CLASS") and "CLASS" or (v == "HEALTH")
            ApplySharedFontTextColors("MSUF2_HP_TEXT_COLOR")
        end]====] },
    ["J5.Colors.PowerText"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Text.lua", source = [====[set = function(v)
            G().colorPowerTextByType = v == "RESOURCE"
            ApplySharedFontTextColors("MSUF2_POWER_TEXT_COLOR")
        end]====] },
    ["J5.Colors.PowerMode"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua", source = [====[set = function(enabled)
        G().powerColorMode = enabled and "class" or "power"
        ApplyColors()
    end]====] },
    ["J5.Colors.CooldownBuckets"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Text.lua", source = [====[set = function(v)
            G().aurasCooldownTextUseBuckets = v and true or false
            RefreshColorSamples()
            ApplyAuraColors()
        end]====] },
    ["J5.CustomSetup.Display"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Setup.lua", source = [====[set = function(value)
            if not REMINDERS_AVAILABLE then return end
            item.placed.reminderEnabled = value == "reminder"
            Apply("AURAS3_CUSTOM_REMINDER", true)
            Repaint(ctx)
        end]====] },
    ["J5.CustomStyle.LayoutFields"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                    if spec[2] == "layer" then item.layer = floor(tonumber(value) or spec[5]) else item.placed[spec[2]] = tonumber(value) or spec[5] end
                    Apply("AURAS3_CUSTOM_" .. spec[2]:upper())
                end]====] },
    ["J5.CustomStyle.PandemicEnabled"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed.pandemicEnabled = value == true
                Apply("AURAS3_TARGET_DOT_PANDEMIC", true)
                if RefreshPandemicState then RefreshPandemicState() end
            end]====] },
    ["J5.CustomStyle.DurationChoice"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
                item.placed[key] = value or fallback
                Apply(reason)
                RefreshCustomDurationBarState()
            end]====] },
    ["J5.CustomStyle.DurationEnabled"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Style.lua", source = [====[set = function(value)
            item.placed.showDurationBar = value == true
            Apply("AURAS3_CUSTOM_DURATION_BAR")
            RefreshCustomDurationBarState()
        end]====] },
    ["J5.UnitStatus.Placement"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    local spec = CurrentStatusSpec(unit)
                    if not spec then return end
                    SetNumber(unit, spec[specKey], normalize and normalize(value, spec) or value, reason, { preview = true })
                    RefreshStatusRuntime(unit, spec)
                end]====] },
    ["J5.UnitStatus.TestMode"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    SetBool(unit, "stateIconsTestMode", value, reason, { preview = true })
                    RefreshStatusIcons = RefreshStatusIcons or MSUF.Require("MSUF_RequestStatusIconsRefreshForCurrent", FILE)
                    RefreshStatusIcons(unit, reason or "MSUF2_STATUS_TEST")
                end]====] },
    ["J5.UnitStatus.Choice"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    local spec = CurrentStatusSpec(unit)
                    local key = spec and spec[specField]
                    if not key then return end
                    local fallback = ResolveStatusDefault(defaultValue, spec)
                    SetString(unit, key, value or fallback, reason, { preview = true })
                    RefreshStatusRuntime(unit, spec)
                    if afterSet then afterSet() end
                end]====] },
    ["J5.UnitStatus.Option"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    SetBool(unit, option.key, value, option.reason, { preview = true })
                    RefreshStatusRuntime(unit, CurrentStatusSpec(unit))
                end]====] },
    ["J5.UnitStatus.Midnight"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    SetGeneralBool("statusIconsUseMidnightStyle", value, "MSUF2_STATUS_STYLE", { preview = true, applyAll = false, notify = false })
                    RefreshStatusIcons = RefreshStatusIcons or MSUF.Require("MSUF_RequestStatusIconsRefreshForCurrent", FILE)
                    RefreshStatusIcons()
                end]====] },
    ["J5.UnitStatus.Enabled"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    local spec = CurrentStatusSpec(unit)
                    if not spec then return end
                    SetBool(unit, spec.show, value, "MSUF2_STATUS_ENABLED", { preview = true })
                    RefreshStatusRuntime(unit, spec)
                    if RefreshStatusSectionState then RefreshStatusSectionState() end
                end]====] },
    ["J5.UnitStatus.RaidGroup"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    if value ~= "BRACKET" and value ~= "NONE" then value = "PAREN" end
                    SetString(unit, "raidGroupNameStyle", value, "MSUF2_RAID_GROUP_NAME_STYLE", { preview = true, text = true })
                    RefreshStatusRuntime(unit, CurrentStatusSpec(unit))
                end]====] },
    ["J5.UnitStatus.Size"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", source = [====[set = function(value)
                    local spec = CurrentStatusSpec(unit)
                    if not spec then return end
                    SetNumber(unit, spec.size, value, "MSUF2_STATUS_SIZE", { preview = true })
                    RefreshStatusRuntime(unit, spec)
                end]====] },
    ["J5.CustomLists.Enchant"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace_Lists.lua", source = [====[set = function(value)
                    item[key] = value == true
                    Apply("AURAS3_CUSTOM_REMINDER_ENCHANT", true)
                    Repaint(ctx)
                end]====] },
    ["J5.Misc.Accent"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(value)
            if not IsAccentMode(value) then value = "midnight" end
            SetG("menuAccent", value, "MSUF2_MENU_ACCENT", MENU_WRITE_OPTS)
            RefreshAccentSwatchEnabled()
            AccentReloadCheck()
        end]====] },
    ["J5.Misc.Highlight"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(value)
            SetG("highlightStyle", value == "BORDER" and "BORDER" or "GRADIENT",
                "MSUF2_MOUSEOVER_STYLE", MOUSEOVER_WRITE_OPTS)
        end]====] },
    ["J5.Misc.MenuFont"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", source = [====[set = function(value)
            if type(MenuFontKeySet) == "function" then
                MenuFontKeySet(value)
            else
                SetG("menuFontKey", value or "", "MSUF2_MENU_FONT", MENU_WRITE_OPTS)
            end
            T.ClearMenuFontCache()
            T.RefreshMenuFonts()
            if menuFontPreview and menuFontPreview.SetText then
                menuFontPreview:SetText("AaBbCc 12345 - MSUF Menu")
            end
        end]====] },
    ["J5.IconSkins.Gloss"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_IconSkins.lua", source = [====[set = function(value)
            local gloss
            if value == "ON" then gloss = true elseif value == "OFF" then gloss = false end
            Skins().WriteDefault("styleSkinGloss", gloss)
            Page.Apply("AURAS3_ICON_SKIN_GLOSS")
        end]====] },
    ["J5.IconSkins.OwnColor"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_IconSkins.lua", source = [====[set = function(value)
            Skins().WriteDefault("styleSkinColorOverride", value == true)
            Page.Apply("AURAS3_ICON_SKIN_COLOR")
        end]====] },
    ["J5.Colors.FullResource"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Resources.lua", source = [====[set = function(value)
            SetClassPowerFullColorEnabled(M.colorsCPToken or "COMBO_POINTS", value)
        end]====] },
    ["J5.Colors.PowerBackground"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Frames.lua", source = [====[set = function(v)
            if not ApiCall("SetPowerBarBackgroundMatchHP", v) then
                G().powerBarBgMatchBarColor = v and true or false
                ApplyColors()
            end
            SetControlEnabled(powerBg, not (v and true or false))
        end]====] },
    ["J5.Colors.CastbarMode"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Frames.lua", source = [====[set = function(v)
            if not ApiCall("SetPlayerCastbarOverrideMode", v) then
                G().playerCastbarOverrideMode = v
                ApplyCastbarColors()
            end
            SetControlEnabled(overrideColor, (overrideEnable and overrideEnable:GetChecked() and true or false) and v == "CUSTOM")
        end]====] },
    ["J5.Colors.CastbarEnabled"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Frames.lua", source = [====[set = function(v)
            if not ApiCall("SetPlayerCastbarOverrideEnabled", v) then
                G().playerCastbarOverrideEnabled = v and true or false
                ApplyCastbarColors()
            end
            RefreshCastbarOverrideControls(v and true or false)
        end]====] },
    ["J5.GroupPortrait.Position"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group_Portrait.lua", source = [====[set = function(value)
                value = value == "RIGHT" and "RIGHT" or "LEFT"
                M._msuf2LastGroupPortraitSide = value
                SetValue("portraitMode", value)
                RefreshPortraitControls()
            end]====] },
    ["J5.UnitPortrait.Position"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua", source = [====[set = function(v)
            M._msuf2LastPortraitSide[unit] = v == "RIGHT" and "RIGHT" or "LEFT"
            SetPortraitValue(unit, "portraitMode", v or "LEFT", "MSUF2_PORTRAIT_MODE")
            p.Refresh()
        end]====] },
    ["J5.Colors.Scope"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Frames.lua", source = [====[set = function(value)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(value)
            if M.RequestRefresh then M.RequestRefresh(ctx, "bar-gradient-color-scope")
            elseif M.Refresh then M.Refresh(ctx) end
        end]====] },
    ["J5.Bars.Scope"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars_Textures.lua", source = [====[set = function(v)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(v)
            RefreshBorderTestModes()
            RefreshBarsPage("bars-scope-change")
        end]====] },
}

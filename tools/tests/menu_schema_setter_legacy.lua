-- Frozen hand setters captured before the schema accessor conversion.
return {
    ["AdvancedClassPower.1"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua", source = [====[set = function(value) SetValue(source(), key, value, apply) end]====] },
    ["AdvancedClassPower.11"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua", source = [====[set = function(value) SetValue(Bars(), "playerHPBarEnabled", value, applyRefresh) end]====] },
    ["AdvancedClassPower.12"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua", source = [====[set = function(value) SetValue(Bars(), "showAltMana", value, applyRefresh) end]====] },
    ["AdvancedClassPower.3"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua", source = [====[set = function(value) SetValue(Bars(), "showClassPower", value, applySourceRefresh) end]====] },
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
    ["Group.8"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group.lua", source = [====[set = function(value)
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
    ["AdvancedColors.7"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua", source = [====[set = function(v)
            G().petFrameUsePlayerClassColor = v and true or false
            M.RequestUnitDomains("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
            RefreshPetColorControl()
        end]====] },
    ["AdvancedColors.9"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua", source = [====[set = function(v)
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
    ["GlobalBars.19"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua", source = [====[set = function(v)
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
    ["GlobalBars.11"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua", source = [====[set = function(value)
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
    ["Group.Portrait"] = { path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group.lua", source = [====[set = function(value)
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
}

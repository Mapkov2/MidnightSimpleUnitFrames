-- Replay the same visual/selection contract against baseline and candidate.
-- Native owner/slot counts may decrease; per-visual output must stay identical.
local root = arg[1] or "."
local h = assert(loadfile(root .. "/.github/scripts/auras3_native_contract_smoke.lua"))()
local A3 = h.A3
local editFrames = {}
local editNS = {MSUF_Auras3={EditMode={groups={}}}}
local edit
if not os.getenv("MSUF_AURAS3_TEST_SOURCE_ROOT") then
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode_Drag.lua"))("MidnightSimpleUnitFrames", editNS)
    edit = editNS.MSUF_Auras3.EditModeModules.Drag({},
        {GetFrame=function(unit) return editFrames[unit] end},
        function() return true end, function() return false end, function() end)
end
local outputs, work = {}, {}
local function Equal(a, b, message)
    assert(a == b, (message or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function Serial(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = tostring(key) .. "=" .. Serial(value[key]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local function Owners(frame)
    local owners = {}
    for key, value in pairs(frame.Auras or {}) do
        if type(value) == "table" and value._msufA3NativeRegistered then owners[#owners + 1] = value end
    end
    return owners
end
local function Snapshot(frame, case)
    local rows, slotCount, groupCount = {}, 0, 0
    local function Anchor(value, host)
        if value == frame then return "frame" end
        if value == frame.hpBar then return "health" end
        if value == frame.hpBar:GetStatusBarTexture() then return "fill" end
        if value == frame.barGroup then return "body" end
        if value == host then return "visual" end
        return tostring(value)
    end
    local function Rect(region, host)
        local out = { tostring(region.width), tostring(region.height) }
        if region.allPoints then out[#out + 1] = "all:" .. Anchor(region.allPoints, host) end
        for _, point in ipairs(region.points or {}) do
            out[#out + 1] = table.concat({point[1], Anchor(point[2], host), point[3], point[4], point[5]}, ":")
        end
        return table.concat(out, "/")
    end
    local owners = Owners(frame)
    for _, owner in ipairs(owners) do
        for slotKey, slot in pairs(owner.auraSlotOptions or {}) do
            slotCount = slotCount + 1
            local button = owner.auraSlotButtons[slotKey]
            for _, binding in ipairs(button._boundDispelTextures or {}) do
                local region, options = binding.region, binding.options
                local host = region.parent
                local visual = assert(host._msufA3DispelSensor, "visual host lost its kind")
                -- Every registered region must remain an AuraButton descendant.
                local ancestor = host
                while ancestor and ancestor ~= button do ancestor = ancestor.parent end
                Equal(ancestor, button, "foreign native dispel texture")
                local row = {case, visual, slot.filter, Serial(owner.slotCandidateFilters and owner.slotCandidateFilters[slotKey]),
                    tostring(owner._msufA3NativeLaneConfig.identityCandidateMode),
                    tostring(host:GetAlpha() * region:GetAlpha()), tostring(host:GetFrameLevel()), host:GetFrameStrata(),
                    Rect(host, host), Rect(region, host), tostring(region.texture), Serial(region.sliceMargins), Serial(options)}
                rows[#rows + 1] = table.concat(row, "|")
            end
        end
        for _ in pairs(owner.groupOptions or {}) do groupCount = groupCount + 1 end
    end
    table.sort(rows)
    for _, row in ipairs(rows) do outputs[#outputs + 1] = row end
    work[#work + 1] = table.concat({case, #owners, slotCount, groupCount, #rows}, "|")
    return #owners, slotCount
end
local scenarios = 0
for _, kind in ipairs({"target", "party"}) do
    for _, rounded in ipairs({false, true}) do
        for _, trigger in ipairs({"DISPEL_TYPE", "BY_ME", "BY_RAID", "PLAYER_CAST"}) do
            for _, mode in ipairs({"TOP", "ALL"}) do
                for _, showOn in ipairs({"BOTH", "FRIENDLY", "ENEMY"}) do
                    scenarios = scenarios + 1
                    local unit = kind == "party" and "party1" or "target"
                    local frame = h.NewFrame(nil)
                    frame.unit, frame.MSUFUnitKey = unit, unit
                    frame.hpBar = h.NewHealthBar(frame)
                    frame.barGroup = kind == "party" and h.NewFrame(frame) or nil
                    frame.health = frame.hpBar
                    frame._msufIsGroupFrame = kind == "party"
                    frame._msufGFKind = kind == "party" and "party" or nil
                    _G.MSUF_DB = { bars = { roundedFramesEnabled = rounded, roundedUnitFrames = rounded, roundedGroupFrames = rounded,
                        roundedCornerStrength = 3 }, auras3 = { enabled = true, showTarget = true,
                        shared = {}, perUnit = { target = { layoutShared = { showBuffs = false, showDebuffs = false } } } } }
                    local style = ({"FULL", "TOP", "LEFT", "BOTTOM", "RIGHT"})[scenarios % 5 + 1]
                    frame.MSUFSpec = {
                        auras = { enabled = false },
                        border = { dispel = true, dispelTrigger = trigger, dispelShowOn = showOn, highlightThickness = 4, layer = 9 },
                        dispelOverlay = { enabled = true, trigger = trigger, alpha = 0.27, style = style, layer = 2 },
                        group = { dispelOverlayEnabled = true, dispelOverlayTrigger = trigger,
                            dispelOverlayAlpha = 0.27, dispelOverlayStyle = style, dispelOverlayLayer = 2 },
                        cornerIndicators = kind == "party" and { enabled = true, needsDispel = true,
                            alpha = 0.61, layer = 7, size = 6, dispelSlots = {
                                {key="a", anchor="TOPLEFT", x=2, y=-3}, {key="b", anchor="BOTTOMRIGHT", x=-4, y=5} } } or nil,
                        dispelSymbol = {enabled=true, trigger=trigger, mode=mode, style="MSUF_LETTERS",
                            alpha=0.73, layer=8, anchor="TOPRIGHT", x=-2, y=-1, size=13},
                    }
                    A3._runtimeConfigGen = (A3._runtimeConfigGen or 0) + 1
                    h.unitCanAssistState[unit] = true
                    assert(h.Element.Enable(frame))
                    local label = table.concat({kind,tostring(rounded),trigger,mode,showOn}, ":")
                    local before = #h.created
                    Snapshot(frame, label)
                    assert(h.Element.Enable(frame))
                    Equal(#h.created, before, "unchanged sensor plan allocated a container")
                    A3.DisableFrame(frame)
                    Equal(#Owners(frame), 0, "disabled sensors retained event owners")
                end
            end
        end
    end
end

-- Unit Buffs/Debuffs keep their independent flows while one shares Dispel's
-- cache. The one-icon variant shares both fixed lanes with that same owner.
for _, unit in ipairs({"player", "target", "focus", "boss1"}) do
for _, cap in ipairs({1,4}) do
    local frame = h.NewFrame(nil)
    frame.unit, frame.MSUFUnitKey, frame.hpBar = unit, unit, h.NewHealthBar(frame)
    local settings = { showBuffs=true, showDebuffs=true, maxBuffs=cap, maxDebuffs=cap }
    _G.MSUF_DB = { bars={}, auras3={enabled=true, showPlayer=true, showTarget=true, showFocus=true, showBoss=true, shared={},
        perUnit={[unit]={layoutShared=settings, layout={buffGroupIconSize=21,debuffGroupIconSize=23}}}} }
    frame.MSUFSpec = { border={dispel=true,dispelTrigger="DISPEL_TYPE"} }
    A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    assert(h.Element.Enable(frame))
    local cfg = frame.Auras._msufA3Config
    Equal(cfg.lanes.buff.max, cap, "fixture buff cap")
    Equal(cfg.lanes.debuff.max, cap, "fixture debuff cap")
    local before = #h.created
    local ownerCount = #Owners(frame)
    local laneSeen = {}
    local laneRows = {}
    local function ObserveLane(button, owner)
        local kind = button._msufA3LaneKind
        if not kind then return end
        laneSeen[kind] = (laneSeen[kind] or 0) + 1
        local lane = cfg.lanes[kind]
        Equal(button.mouseClickEnabled, unit == "player" and kind == "buff", "native aura cancellation gate")
        local groupKey = "msuf_" .. kind
        local filter = owner.auraSlotOptions and owner.auraSlotOptions[groupKey]
        filter = filter and filter.filter or owner.groupFilters[groupKey]
        Equal(filter, lane.nativeFilter, "lane filter moved during sharing")
        laneRows[#laneRows+1] = table.concat({unit,cap,kind,button:GetWidth(),button:GetHeight(),
            button:GetFrameLevel(),button:GetFrameStrata(),tostring(button.mouseClickEnabled),
            tostring(button.mouseMotionEnabled),filter}, "|")
        if cap > 1 then
            local host = assert(owner._msufA3LayoutHost)
            Equal(host.point[1], lane.anchor, "flow host anchor")
            Equal(host.point[2], frame, "flow host parent anchor")
            Equal(host.point[4], lane.x, "flow X")
            Equal(host.point[5], lane.y, "flow Y")
            Equal(host:GetWidth(), lane.width, "flow capacity width")
            Equal(host:GetHeight(), lane.height, "flow capacity height")
        else
            Equal(button.point[1], lane.anchor, "fixed lane anchor")
            Equal(button.point[2], frame, "fixed lane parent anchor")
            Equal(button.point[4], lane.x, "fixed lane X")
            Equal(button.point[5], lane.y, "fixed lane Y")
        end
    end
    for _, owner in ipairs(Owners(frame)) do
        for _, button in pairs(owner.auraSlotButtons or {}) do
            ObserveLane(button, owner)
        end
        for key, group in pairs(owner.groups or {}) do
            for _, button in ipairs(group:GetFramesByIndex()) do
                ObserveLane(button, owner)
            end
        end
    end
    Equal(laneSeen.buff, cap, "buff icons lost/duplicated")
    Equal(laneSeen.debuff, cap, "debuff icons lost/duplicated")
    table.sort(laneRows)
    for _, row in ipairs(laneRows) do outputs[#outputs+1] = row end
    work[#work+1] = unit .. "-cap-" .. cap .. "|" .. ownerCount .. "|" .. laneSeen.buff .. "|" .. laneSeen.debuff
    for _=1,100 do assert(h.Element.Enable(frame)); assert(A3._RefreshAppliedNativeAuras(frame, false)) end
    Equal(#h.created, before, "unchanged unit plan replaced a native owner")
    -- The same public Edit Mode hide/restore must reach every merged lane.
    -- Exercise readable script hooks here; the native contract also covers
    -- buttons whose secret script aspects reject those hooks.
    if edit then
    editFrames[unit] = frame
    local editGroups, forwarded = {}, nil
    editNS.MSUF_Auras3.EditMode.groups[unit] = editGroups
    for _, kind in ipairs({"buff","debuff"}) do
        local group, expectedKind = h.NewFrame(nil), kind
        group:SetScript("OnMouseDown", function() forwarded=expectedKind end)
        editGroups[kind] = group
    end
    local buttons = {}
    for _, owner in ipairs(Owners(frame)) do
        local function AddButton(button)
            button._secretScriptRestricted = false
            buttons[#buttons+1] = button
        end
        for _, button in pairs(owner.auraSlotButtons or {}) do AddButton(button) end
        for _, group in pairs(owner.groups or {}) do
            for _, button in ipairs(group.frames) do AddButton(button) end
        end
    end
    edit.SetRuntimeAuraHidden(unit, true)
    Equal(frame.Auras:GetAlpha(), 0, "Edit Mode did not hide runtime root")
    for _, button in ipairs(buttons) do
        local kind = button._msufA3LaneKind
        if kind then
            Equal(button.mouseClickEnabled, true, "Edit Mode lost native lane forwarding")
            Equal(button.mouseMotionEnabled, false, "Edit Mode retained tooltip motion")
            assert(button.hooks and button.hooks.OnMouseDown)(button,"LeftButton")
            Equal(forwarded, kind, "mixed owner forwarded to the wrong lane")
        end
    end
    edit.SetRuntimeAuraHidden(unit, false)
    Equal(frame.Auras:GetAlpha(), 1, "Edit Mode did not restore runtime root")
    for _, button in ipairs(buttons) do
        local kind = button._msufA3LaneKind
        Equal(button.mouseClickEnabled, unit=="player" and kind=="buff", "Edit Mode cancellation restore")
        if kind then Equal(button.mouseMotionEnabled, cfg.lanes[kind].showTooltip ~= false, "Edit Mode tooltip restore") end
    end
    editFrames[unit] = nil
    end
    -- Removing Dispel must return the merged lanes to independently owned rows.
    frame.MSUFSpec.border.dispel = false
    A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    assert(h.Element.Enable(frame))
    assert(frame.Auras.Buffs and frame.Auras.Debuffs, "removing sensor lost normal lanes")
    A3.DisableFrame(frame)
    Equal(#Owners(frame), 0, "disabled mixed unit retained owners")
    Equal(frame._msufA3UnitAuraOwner, nil, "disabled Unit retained its owner marker")
end
end
for _, entry in ipairs({{"MSUF_AURAS3_VISUAL_TRACE",outputs},{"MSUF_AURAS3_WORK_TRACE",work}}) do
    local path = os.getenv(entry[1])
    if path then local f=assert(io.open(path,"wb")); f:write(table.concat(entry[2],"\n"),"\n"); f:close() end
end
print("PASS Auras3 sharing: " .. scenarios .. " visual selections; cap-1/cap-4 Unit owners, "
    .. (edit and "Edit Mode, " or "") .. "reuse and split lifecycle")

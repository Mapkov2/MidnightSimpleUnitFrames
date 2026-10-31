local _, MSUF = ...
local W, F, V = MSUF.ProfileWorkbench, MSUF.ProfileFields, MSUF.ProfileVariants
function W.Changes()
    local db = MSUF.History.EnsureDB()
    local defaults = MSUF.PublicGlobals.MSUF_CreateFactoryDefaultProfile()
    if not defaults then return nil, "Factory defaults are unavailable." end
    local changes, why = F.Diff(defaults, db, 8192)
    if not changes then return nil, why end
    for _, change in ipairs(changes) do
        change.default = F.CopySnapshot(F.Read(defaults, change.path))
        change.source = V.Source(change.path) or "Profile value"
        change.effective = F.CopySnapshot(F.Read(db, change.path))
    end
    return changes
end
function W.InspectSetting(settingKey)
    local path = {}
    for field in tostring(settingKey or ""):gmatch("[^.]+") do path[#path + 1] = tonumber(field) or field end
    if not F.Path(path) then return nil end
    local defaults = MSUF.PublicGlobals.MSUF_CreateFactoryDefaultProfile()
    if not defaults then return nil end
    local value = F.Read(MSUF.History.EnsureDB(), path)
    local default = F.Read(defaults, path)
    return { path = path, default = F.CopySnapshot(default), effective = F.CopySnapshot(value),
        source = V.Source(path) or (value == nil and "Default / not set" or "Profile value") }
end
local function SplitAncestorPatches(snapshot, path)
    local entries = snapshot.core.profileVariants.entries
    for depth = 2, #path - 1 do
        local prefix = {}
        for i = 1, depth do prefix[i] = path[i] end
        local id, keys = F.ID(prefix), {}
        local base = F.Read(snapshot.core, prefix)
        if type(base) == "table" then for key in pairs(base) do keys[key] = true end end
        for _, entry in ipairs(entries) do
            for _, field in ipairs(entry.patch) do
                if F.ID(field.path) == id and type(field.value) == "table" then
                    for key in pairs(field.value) do keys[key] = true end
                end
            end
        end
        for _, entry in ipairs(entries) do
            for i = #entry.patch, 1, -1 do
                local field = entry.patch[i]
                if F.ID(field.path) == id then
                    table.remove(entry.patch, i)
                    for key in pairs(keys) do
                        local child = F.CopySnapshot(prefix)
                        child[#child + 1] = key
                        local value
                        if type(field.value) == "table" then value = field.value[key] end
                        entry.patch[#entry.patch + 1] = { path = child, value = F.CopySnapshot(value), remove = value == nil }
                    end
                end
            end
        end
    end
end
function W.Revert(change)
    local snapshot, why = W.Snapshot()
    if not snapshot then return false, why end
    local path = change.path
    local owner = V.Source(path)
    if owner then
        -- Split matching ancestor paths in every layer so removing one leaf
        -- exposes the layer beneath it, including later edits to that layer.
        SplitAncestorPatches(snapshot, path)
        for _, entry in ipairs(snapshot.core.profileVariants.entries) do
            if entry.name == owner then
                for i = #entry.patch, 1, -1 do
                    local field = entry.patch[i]
                    if F.Overlaps(path, field.path) then table.remove(entry.patch, i) end
                end
            end
        end
        local clean, reason = V.Validate(snapshot.core.profileVariants)
        if not clean then return false, reason end
        snapshot.core.profileVariants = clean
    else F.Write(snapshot.core, path, F.CopySnapshot(change.default)) end
    return W.ApplySnapshot(snapshot, "Before reverting a setting")
end
local PALETTES = {
    deuteranopia = { { 0, 0.45, 0.70 }, { 0.90, 0.60, 0 }, { 0.80, 0.40, 0 } },
    protanopia = { { 0.20, 0.65, 0.85 }, { 0.95, 0.85, 0.25 }, { 0.70, 0.35, 0.70 } },
    tritanopia = { { 0, 0.65, 0.55 }, { 0.85, 0.35, 0.45 }, { 0.75, 0.15, 0.35 } },
}
local function RGB(target, prefix, color)
    target[prefix .. "R"], target[prefix .. "G"], target[prefix .. "B"] = color[1], color[2], color[3]
end
function W.Accessibility(id)
    local colors = PALETTES[id]
    if not colors then return nil, "Unknown accessibility preset." end
    local snapshot, why = W.Snapshot()
    if not snapshot then return nil, why end
    local db = snapshot.core
    RGB(db.general, "castbarInterruptible", colors[1])
    RGB(db.general, "castbarNonInterruptible", colors[2])
    RGB(db.general, "castbarInterruptFeedback", colors[3])
    RGB(db.general, "threatColorLow", colors[1])
    RGB(db.general, "threatColorMid", colors[2])
    RGB(db.general, "threatColorHigh", colors[3])
    db.npcColors = db.npcColors or {}
    for i, key in ipairs({ "friendly", "neutral", "enemy" }) do
        db.npcColors[key] = { r = colors[i][1], g = colors[i][2], b = colors[i][3] }
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        local conf = db[key]
        if conf then
            conf.dispelSymbolEnabled = true
            conf.dispelSymbolStyle = "MSUF_SHAPES"
        end
    end
    return W.ReviewSnapshot(snapshot, "Before applying accessibility colors")
end
function W.Visibility(selectedUnit, selectedLane)
    local rows = selectedUnit and {} or W.InspectProviders()
    local auras = MSUF.MSUF_Auras3
    if not auras or not auras.ResolveUnitFrameConfig then return rows end
    local titles = { player = "Player", target = "Target", focus = "Focus", pet = "Pet", boss = "Boss" }
    for _, unit in ipairs({ "player", "target", "focus", "pet", "boss" }) do
        local config = (not selectedUnit or selectedUnit == unit) and auras.ResolveUnitFrameConfig(unit)
        if config then
            local keys = {}
            for key in pairs(config.lanes or {}) do if not selectedLane or selectedLane == key then keys[#keys + 1] = key end end
            table.sort(keys)
            for _, key in ipairs(keys) do
                local lane = config.lanes[key]
                local title = lane.kind == "buff" and "Buffs" or lane.kind == "debuff" and "Debuffs" or tostring(lane.kind)
                rows[#rows + 1] = { unit = unit, label = MSUF.Translate(titles[unit]) .. " / " .. MSUF.Translate(title),
                    lane = key, page = "uf_" .. unit,
                    target = { pageKey = "uf_" .. unit, sectionId = "workbench_visibility",
                        prepareKind = "unitAuraWorkspace", prepareValue = key .. "_layout" },
                    reason = config.enabled == false and "Aura configuration disabled"
                        or lane.enabled and "Enabled by configuration" or "Disabled by configuration",
                    detail = tostring(lane.nativeFilter or "") .. " / " .. tostring(lane.max or 0) }
            end
            if not config.enabled then
                rows[#rows + 1] = { unit = unit, label = MSUF.Translate(titles[unit]), page = "uf_" .. unit,
                    target = { pageKey = "uf_" .. unit, sectionId = "auras" }, reason = "Aura configuration disabled" }
            end
        end
    end
    return rows
end
-- These conditions select existing profile variants. Relative UI scaling stays
-- with its existing profile owner and can be recorded into the same variant.
function W.DisplayRule(name, width, aspect, maxWidth, maxAspect)
    local ok, why = W.CanEdit()
    if not ok then return false, why end
    local db = MSUF.History.EnsureDB()
    local schema, reason = V.Validate(db.profileVariants)
    if not schema then return false, reason or "Create a profile variant first." end
    for _, entry in ipairs(schema.entries) do
        if entry.name == name then
            entry.conditions.display = { minWidth = width, minAspect = aspect, maxWidth = maxWidth, maxAspect = maxAspect }
            return V.Replace(db, schema)
        end
    end
    return false, "Choose a profile variant."
end
function W.BeginDisplayLayout(name)
    local ok, why = W.CanEdit()
    if not ok then return false, why end
    local db = MSUF.History.EnsureDB()
    local schema, reason = V.Validate(db.profileVariants)
    if db.profileVariants and not schema then return false, reason end
    schema = schema or { version = 1, entries = {} }
    local width, aspect = V.DisplayValues()
    if width <= 0 or aspect <= 0 then return false, "Display size unavailable." end
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then return false, "Enter a layout name." end
    schema.entries[#schema.entries + 1] = { name = name, patch = {}, conditions = {
        display = { minWidth = width, maxWidth = width, minAspect = aspect - 0.01, maxAspect = aspect + 0.01 } } }
    local replaced, replaceWhy = V.Replace(db, schema)
    if not replaced then return false, replaceWhy end
    local recording, recordWhy = V.BeginRecording(name)
    if not recording then return false, recordWhy end
    MSUF.Require("MSUF_SetCurrentProfileScreenReferenceHeight", "State/MSUF_ProfileWorkbenchTools.lua")(width / aspect)
    return true
end

local _, MSUF = ...
local M = {}
MSUF.History = M
local ApplyService = MSUF.ApplyService
local DeepCopy = MSUF.Util.DeepCopy
local CLASSPOWER_FULL_RUNTIME = { full = true, cdm = true }
local UNIT_KEYS = ApplyService.UnitKeys
local uiBridge
local function UI(name, ...)
    if uiBridge then return uiBridge(name, ...) end
end
function M.AttachUI(bridge)
    uiBridge = bridge
end
local function IsConfigCombatLocked()
    return MSUF.Public.IsConfigCombatLocked()
end
function M.BlockCombatAction()
    if not IsConfigCombatLocked() then return false end
    _G.MSUF_ShowConfigCombatLockMessage()
    return true
end
local function QueueMenuRefresh() UI("QueueMenuRefresh") end
local function CancelQueuedMenuRefresh() UI("CancelQueuedMenuRefresh") end
function M.MarkMenuDataDirty(reason) UI("MarkMenuDataDirty", reason) end
local function HistoryDisplayLabel(label)
    return UI("HistoryDisplayLabel", label) or label
end
local function RequestHistoryApply(method, ...)
    local handled, result = UI("RequestHistoryApply", method, ...)
    if handled then return result end
    return M[method](...)
end
local function ProfileSystemNeedsInit()
    local active = _G.MSUF_ActiveProfile
    local gdb = _G.MSUF_GlobalDB
    local profiles = type(gdb) == "table" and gdb.profiles or nil
    local activeTable = type(active) == "string" and type(profiles) == "table" and profiles[active] or nil
    return type(active) ~= "string"
        or active == ""
        or type(_G.MSUF_DB) ~= "table"
        or type(activeTable) ~= "table"
        or _G.MSUF_DB ~= activeTable
end
M.ProfileSystemNeedsInit = ProfileSystemNeedsInit
local lastEnsuredDB
function M.EnsureDB()
    local db = _G.MSUF_DB
    if db ~= nil and db == lastEnsuredDB and type(db.general) == "table" and not ProfileSystemNeedsInit() then
        return db
    end
    if ProfileSystemNeedsInit() then
        _G.MSUF_InitProfiles()
    end
    local ensure = _G.MSUF_EnsureDB
    if type(ensure) == "function" then ensure() end
    MSUF.ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    lastEnsuredDB = _G.MSUF_DB
    return _G.MSUF_DB
end
local HISTORY_BYTE_BUDGET = 4 * 1024 * 1024
local DIFF_ENTRY_BYTES, DIFF_TABLE_BYTES = 64, 80
local historyDepth = 0
local historyDepthStamp
local historyRestoring = false
local historySessionActive = false
local historySessionBaseSnapshot
local historySessionSnapshot
local historySessionDirty = false
local historyTransaction
local historySurfaces = {}
local historySurfaceMarkers = {}
local historySurfaceCount = 0
local deferredHistoryCommit
local historySnapshotFailureReported = false
local historyCursorPartial = false
local historyStepSerial = 0
local historyFirstUnsyncedStep = 0
local function WipeTable(t)
    for k in pairs(t) do t[k] = nil end
end
local function HistoryFrameStamp()
    local now = _G.GetTime
    return now and now() or 0
end
local function HealLeakedHistoryDepth()
    if historyDepth > 0 and historyDepthStamp ~= HistoryFrameStamp() then
        historyDepth = 0
        historyDepthStamp = nil
    end
end
local function EnterHistoryDepth()
    if historyDepth == 0 then historyDepthStamp = HistoryFrameStamp() end
    historyDepth = historyDepth + 1
end
local function LeaveHistoryDepth()
    if historyDepth > 0 then historyDepth = historyDepth - 1 end
    if historyDepth == 0 then historyDepthStamp = nil end
end
local function HistoryBusy()
    HealLeakedHistoryDepth()
    return historyDepth > 0 or historyTransaction ~= nil or historyRestoring
end
local function ReportHistorySnapshotFailure()
    if historySnapshotFailureReported then return end
    historySnapshotFailureReported = true
    if type(MSUF.ReportError) == "function" then
        MSUF.ReportError("Menu2 history", "the active profile holds a value the undo snapshot cannot copy;"
            .. " menu changes apply without undo until that value is removed")
    end
end
local function EnsureHistoryStacks()
    M.historyUndo = M.historyUndo or {}
    M.historyRedo = M.historyRedo or {}
    return M.historyUndo, M.historyRedo
end
local function DeepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
local function DeepReplace(dst, src, seen)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    seen = seen or {}
    seen[src] = dst
    for k in pairs(dst) do
        if src[k] == nil then dst[k] = nil end
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if seen[v] then
                dst[k] = seen[v]
            else
                if type(dst[k]) ~= "table" then dst[k] = {} end
                DeepReplace(dst[k], v, seen)
            end
        else
            dst[k] = v
        end
    end
end
local function HistoryCharacterKey()
    local value = _G.MSUF_GetCharKey()
    if type(value) == "string" and value ~= "" then return value end
    if type(_G.UnitName) == "function" and type(_G.GetRealmName) == "function" then
        local name = _G.UnitName("player")
        local realm = _G.GetRealmName()
        if type(name) == "string" and name ~= "" and type(realm) == "string" then
            return name .. "-" .. realm
        end
    end
end
local function SnapshotProfileRouting()
    local key = HistoryCharacterKey()
    if not key then return nil end
    local gdb = _G.MSUF_GlobalDB
    local chars = type(gdb) == "table" and gdb.char or nil
    local char = type(chars) == "table" and chars[key] or nil
    local existed = type(char) == "table"
    local autoSwitch
    if existed then autoSwitch = char.specAutoSwitch end -- Preserve an explicit false value.
    return {
        key = key,
        existed = existed,
        specAutoSwitch = autoSwitch,
        specProfileMap = existed and DeepCopy(char.specProfileMap) or nil,
    }
end
local historyProviders = {}
local ForgetHistoryPath, SyncHistoryCursor, SettleHistoryCursor
function M.RegisterHistoryProvider(key, capture, restore)
    if type(key) ~= "string" or key == "" or type(capture) ~= "function" or type(restore) ~= "function" then return false end
    historyProviders[key] = { capture = capture, restore = restore }
    local cursor = historySessionActive and historySessionSnapshot
    if type(cursor) == "table" and cursor._msuf2HistoryState == true then
        cursor.externalProviders = cursor.externalProviders or {}
        cursor.externalProviders[key] = DeepCopy(capture())
        ForgetHistoryPath({ "externalProviders", key })
    end
    return true
end
function M.UnregisterHistoryProvider(key)
    historyProviders[key] = nil
end
local function SnapshotHistoryProviders()
    local snapshot = {}
    for key, provider in pairs(historyProviders) do
        local value = provider.capture()
        if value ~= nil then snapshot[key] = value end
    end
    return snapshot
end
local function RestoreHistoryProviders(snapshot, reason, source)
    local values = type(snapshot) == "table" and snapshot.externalProviders
    if type(values) ~= "table" then return end
    for key, value in pairs(values) do
        local provider = historyProviders[key]
        if provider then provider.restore(DeepCopy(value), reason, source) end
    end
end
local function OwnedViewTable(parent, key, owned, create)
    local child = parent[key]
    if type(child) ~= "table" then
        if not create then return nil end
        child = {}
    elseif owned[child] then
        return child
    else
        local copy = {}
        for field, value in pairs(child) do copy[field] = value end
        child = copy
    end
    owned[child] = true
    parent[key] = child
    return child
end
local function BaseProfileView(db)
    local Variants, Fields = MSUF.ProfileVariants, MSUF.ProfileFields
    local journal = Variants.BaseJournal and Variants.BaseJournal(db)
    local view = {}
    for key, value in pairs(db) do view[key] = value end
    if Fields and Fields.CaptureExternal and not Fields.CaptureExternal(db, view) then return nil end
    if not journal then return view end
    local owned, created = { [view] = true }, {}
    for _, record in pairs(journal) do
        local parent, path = view, record.path
        for i = 1, #path - 1 do
            parent = parent and OwnedViewTable(parent, path[i], owned, record.base ~= nil)
        end
        if parent then parent[path[#path]] = record.base end
        for _, prefix in ipairs(record.created) do created[#created + 1] = prefix end
    end
    table.sort(created, function(a, b) return #a > #b end)
    for _, path in ipairs(created) do
        local parent = view
        for i = 1, #path - 1 do parent = parent and OwnedViewTable(parent, path[i], owned, false) end
        local value = parent and parent[path[#path]]
        if type(value) == "table" and next(value) == nil then parent[path[#path]] = nil end
    end
    return view
end
local function SnapshotDB(view)
    local externalAPI = (type(MSUF) == "table" and MSUF.EditModeAPI) or _G.MSUF_EditModeAPI
    local externalState = type(externalAPI) == "table"
        and type(externalAPI._CaptureHistorySnapshot) == "function"
        and externalAPI._CaptureHistorySnapshot() or nil
    local profileDB
    if view and MSUF.ProfileVariants then profileDB = BaseProfileView(M.EnsureDB())
    elseif view then profileDB = M.EnsureDB()
    elseif MSUF.ProfileVariants then profileDB=MSUF.ProfileVariants.BaseSnapshot(M.EnsureDB(),true)
    else profileDB=DeepCopy(M.EnsureDB()) end
    if type(profileDB)~="table" then return nil end
    return {
        _msuf2HistoryState = true,
        profileDB = profileDB,
        profileRouting = SnapshotProfileRouting(),
        externalEditMode = externalState,
        externalProviders = SnapshotHistoryProviders(),
    }
end
local snapshotProfiles = setmetatable({}, { __mode = "k" })
local SnapshotUnstampedDB = SnapshotDB
SnapshotDB = function(view)
    local snapshot = SnapshotUnstampedDB(view)
    local runtime = MSUF.ProfileRuntime
    if type(snapshot) == "table" and runtime and runtime.Identity then
        snapshotProfiles[snapshot] = runtime.Identity()
    end
    return snapshot
end
local function IsForeignProfileSnapshot(snapshot)
    local runtime = MSUF.ProfileRuntime
    if type(snapshot) ~= "table" or not (runtime and runtime.IsCurrentIdentity) then return false end
    return runtime.IsCurrentIdentity(snapshotProfiles[snapshot]) ~= true
end
local function RebaseHistoryToActiveProfile()
    if historyTransaction then M.CancelHistoryTransaction() end
    return M.ClearHistory()
end
local function StackHoldsForeignSnapshot(stack)
    for i = 1, #stack do
        local entry = stack[i]
        if IsForeignProfileSnapshot(entry) then return true end
    end
    return false
end
function M.RebaseHistoryForProfileChange()
    UI("ProfileChange")
    if IsConfigCombatLocked() then return false end
    local foreign = (deferredHistoryCommit and IsForeignProfileSnapshot(deferredHistoryCommit.before))
        or (historyTransaction and IsForeignProfileSnapshot(historyTransaction.before))
        or IsForeignProfileSnapshot(historySessionBaseSnapshot)
        or IsForeignProfileSnapshot(historySessionSnapshot)
    for _, marker in pairs(historySurfaceMarkers) do
        if foreign then break end
        foreign = IsForeignProfileSnapshot(marker.point)
    end
    if not foreign then
        local undo, redo = EnsureHistoryStacks()
        foreign = StackHoldsForeignSnapshot(undo) or StackHoldsForeignSnapshot(redo)
    end
    if not foreign then return true end
    return RebaseHistoryToActiveProfile()
end
local function HistoryProfileDB(snapshot)
    if type(snapshot) == "table" and snapshot._msuf2HistoryState == true then return snapshot.profileDB end
    return snapshot -- Backward compatibility for a history entry created before this schema.
end
local function RestoreProfileRouting(snapshot)
    local routing = type(snapshot) == "table" and snapshot._msuf2HistoryState == true and snapshot.profileRouting or nil
    if type(routing) ~= "table" or type(routing.key) ~= "string" then return end
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return end
    if type(gdb.char) ~= "table" then gdb.char = {} end
    local char = gdb.char[routing.key]
    if type(char) ~= "table" then
        char = {}
        gdb.char[routing.key] = char
    end
    if routing.existed then
        char.specAutoSwitch = routing.specAutoSwitch
        char.specProfileMap = DeepCopy(routing.specProfileMap)
    else
        char.specAutoSwitch = nil
        char.specProfileMap = nil
        if next(char) == nil then gdb.char[routing.key] = nil end
    end
end
local function CurrentHistorySnapshot()
    if not historySessionActive then return SnapshotDB() end
    if type(historySessionSnapshot) ~= "table" then historySessionSnapshot = SnapshotDB() end
    return historySessionSnapshot
end
local function NotifyHistoryChanged(refreshMenu)
    UI("NotifyHistoryChanged")
    _G.MSUF_EM_RefreshHistoryControls()
    if refreshMenu == true then QueueMenuRefresh() end
end
function M.SyncExternalHistoryState()
    if HistoryBusy() then return false end
    if not historySessionActive then return false end
    SettleHistoryCursor()
    SyncHistoryCursor()
    NotifyHistoryChanged(false)
    return true
end
local function TableBytes(value, seen)
    if type(value) == "string" then return #value + 32 end
    if type(value) ~= "table" or seen[value] then return 0 end
    seen[value] = true
    local bytes = DIFF_TABLE_BYTES
    for key, item in pairs(value) do
        bytes = bytes + DIFF_ENTRY_BYTES + TableBytes(key, seen) + TableBytes(item, seen)
    end
    return bytes
end
local HUGE = math.huge
local DIFF_LIMIT_COUNT, DIFF_LIMIT_BYTES, DIFF_LIMIT_DEPTH = 131072, 8388608, 32
local type, pairs, getmetatable = type, pairs, getmetatable
local diffOut, diffSeen, diffStrictProfile
local diffCount, diffBytes = 0, 0
local diffPath = {}
local function DiffEmit(depth, key, before, after)
    local path = {}
    for i = 1, depth do path[i] = diffPath[i] end
    path[depth + 1] = key
    diffOut[#diffOut + 1] = { path = path, before = before, after = after }
end
local function DiffCopy(value, depth, strict)
    if not strict then return DeepCopy(value), true end
    local budget = { count = diffCount, limit = DIFF_LIMIT_COUNT, maxDepth = DIFF_LIMIT_DEPTH - depth,
        bytes = diffBytes, maxBytes = DIFF_LIMIT_BYTES }
    local copy, valid = MSUF.ProfileFields.CopySnapshot(value, budget)
    diffCount, diffBytes = budget.count, budget.bytes
    return copy, valid
end
local function DiffTable(a, b, depth, strict)
    if diffSeen[b] then return false end
    diffSeen[b] = true
    local deeper = depth + 1
    for key, value in pairs(b) do
        local kind = type(value)
        if strict then
            local keyKind = type(key)
            if keyKind == "string" then
                diffBytes = diffBytes + #key
            elseif keyKind == "number" then
                if key ~= key or key == HUGE or key == -HUGE then return false end
            elseif keyKind ~= "boolean" then
                return false
            end
            if kind == "string" then
                diffBytes = diffBytes + #value
            elseif kind == "number" then
                if value ~= value or value == HUGE or value == -HUGE then return false end
            elseif kind ~= "boolean" and kind ~= "table" then
                return false
            end
            diffCount = diffCount + 1
            if diffCount > DIFF_LIMIT_COUNT or diffBytes > DIFF_LIMIT_BYTES then return false end
        end
        local old = a[key]
        if kind == "table" then
            local inner = strict or (diffStrictProfile and depth == 0 and key == "profileDB")
            if inner and (getmetatable(value) ~= nil or depth >= DIFF_LIMIT_DEPTH) then return false end
            if type(old) == "table" then
                diffPath[deeper] = key
                if not DiffTable(old, value, deeper, inner) then return false end
            else
                local copy, valid = DiffCopy(value, depth, inner)
                if not valid then return false end
                DiffEmit(depth, key, old, copy)
            end
        elseif old ~= value then
            DiffEmit(depth, key, old, value)
        end
    end
    for key, old in pairs(a) do
        if b[key] == nil then DiffEmit(depth, key, old, nil) end
    end
    diffSeen[b] = nil
    return true
end
local function ProfileDiff(before, after)
    if type(before) ~= "table" or type(after) ~= "table" then return nil end
    diffOut, diffSeen, diffCount, diffBytes = {}, {}, 0, 0
    diffStrictProfile = MSUF.ProfileVariants ~= nil and MSUF.ProfileFields ~= nil
    local ok = DiffTable(before, after, 0, false)
    local changes = ok and diffOut or nil
    diffOut, diffSeen = nil, nil
    for i = #diffPath, 1, -1 do diffPath[i] = nil end
    return changes
end
local function ReadHistoryPath(target, path)
    for i = 1, #path do
        if type(target) ~= "table" then return nil end
        target = target[path[i]]
    end
    return target
end
local function WriteHistoryPath(target, path, value)
    local last = #path
    for i = 1, last - 1 do
        local child = target[path[i]]
        if type(child) ~= "table" then
            if value == nil then return end
            child = {}
            target[path[i]] = child
        end
        target = child
    end
    target[path[last]] = value
end
local function NewHistoryPoint()
    local point = { tree = {} }
    snapshotProfiles[point] = snapshotProfiles[historySessionSnapshot]
    return point
end
local function FoldSavedValues(node, holder, key)
    local target = holder[key]
    if type(target) ~= "table" then
        target = {}
        holder[key] = target
    end
    for childKey, child in pairs(node.kids) do
        if child.saved then
            target[childKey] = child.value
        elseif child.kids then
            FoldSavedValues(child, target, childKey)
        end
    end
end
local function RememberPointValue(point, path, old)
    local node = point.tree
    for i = 1, #path do
        if node.saved then return end
        local kids = node.kids
        if not kids then
            kids = {}
            node.kids = kids
        end
        local child = kids[path[i]]
        if not child then
            child = {}
            kids[path[i]] = child
        end
        node = child
    end
    if node.saved then return end
    if node.kids then
        local box = { DeepCopy(old) }
        FoldSavedValues(node, box, 1)
        old, node.kids = box[1], nil
    end
    node.saved, node.value = true, old
end
local function RememberHistoryValue(path, old)
    local base = historySessionBaseSnapshot
    if base then RememberPointValue(base, path, old) end
    for _, marker in pairs(historySurfaceMarkers) do
        if marker.point ~= base then RememberPointValue(marker.point, path, old) end
    end
end
ForgetHistoryPath = function(path)
    local points = { historySessionBaseSnapshot }
    for _, marker in pairs(historySurfaceMarkers) do points[#points + 1] = marker.point end
    for _, point in pairs(points) do
        local node = point.tree
        for i = 1, #path - 1 do node = node and node.kids and node.kids[path[i]] end
        if node and node.kids then node.kids[path[#path]] = nil end
    end
end
local function PointChanges(node, depth, path, out)
    for key, child in pairs(node.kids or {}) do
        path[depth + 1] = key
        if child.saved then
            local copy = {}
            for i = 1, depth + 1 do copy[i] = path[i] end
            out[#out + 1] = { path = copy, before = child.value }
        else
            PointChanges(child, depth + 1, path, out)
        end
    end
    path[depth + 1] = nil
    return out
end
local function PointDiffers(node, value)
    for key, child in pairs(node.kids or {}) do
        local current
        if type(value) == "table" then current = value[key] end
        if child.saved then
            if not DeepEqual(child.value, current) then return true end
        elseif PointDiffers(child, current) then
            return true
        end
    end
    return false
end
local function RefreshSessionDirty()
    local base, cursor = historySessionBaseSnapshot, historySessionSnapshot
    historySessionDirty = historySessionActive and base ~= nil and type(cursor) == "table"
        and PointDiffers(base.tree, cursor) or false
end
local function ApplyChanges(target, changes, field, replaced)
    local remember = historySessionActive and target == historySessionSnapshot
    local first, last, step = 1, #changes, 1
    if field == "before" then first, last, step = #changes, 1, -1 end
    for i = first, last, step do
        local change = changes[i]
        local path = change.path
        if remember or replaced then
            local old = ReadHistoryPath(target, path)
            if remember then RememberHistoryValue(path, old) end
            if replaced then replaced[i] = old end
        end
        local value = change[field]
        if type(value) == "table" then value = DeepCopy(value) end
        WriteHistoryPath(target, path, value)
    end
end
local function RevertChanges(target, changes, replaced, field)
    local first, last, step = #changes, 1, -1
    if field == "before" then first, last, step = 1, #changes, 1 end
    for i = first, last, step do
        local old = replaced[i]
        if type(old) == "table" then old = DeepCopy(old) end
        WriteHistoryPath(target, changes[i].path, old)
    end
end
SyncHistoryCursor = function()
    local cursor = historySessionSnapshot
    if type(cursor) ~= "table" then
        historySessionSnapshot = SnapshotDB()
        return
    end
    local drift = ProfileDiff(cursor, SnapshotDB(true))
    if drift then
        ApplyChanges(cursor, drift, "after")
        historyCursorPartial = false
    end
end
local retainedStacks = {}
local function RetainedHistoryStacks()
    local undo, redo = EnsureHistoryStacks()
    local count = 2
    retainedStacks[1], retainedStacks[2] = undo, redo
    for _, marker in pairs(historySurfaceMarkers) do
        retainedStacks[count + 1], retainedStacks[count + 2] = marker.undo, marker.redo
        count = count + 2
    end
    for i = #retainedStacks, count + 1, -1 do retainedStacks[i] = nil end
    return retainedStacks, count
end
local function CountRetainedSteps(stacks, count)
    local bytes = 0
    for s = 1, count do
        local stack = stacks[s]
        for i = 1, #stack do stack[i].refs = 0 end
    end
    for s = 1, count do
        local stack = stacks[s]
        for i = 1, #stack do
            local entry = stack[i]
            if entry.refs == 0 then bytes = bytes + entry.bytes end
            entry.refs = entry.refs + 1
        end
    end
    return bytes
end
function M.HistoryRetainedBytes()
    return CountRetainedSteps(RetainedHistoryStacks())
end
local function TrimHistoryToBudget(budget)
    local stacks, count = RetainedHistoryStacks()
    local bytes = CountRetainedSteps(stacks, count)
    local live = stacks[1]
    local newest = live[#live]
    while bytes > budget do
        local victim
        for s = 1, count do
            local stack = stacks[s]
            local candidate = s % 2 == 1 and stack[1] or stack[#stack]
            if candidate and (not victim or candidate.seq < victim.seq) then victim = candidate end
        end
        if not victim or victim == newest then break end
        for s = 1, count do
            local stack = stacks[s]
            local drop = s % 2 == 1 and (stack[1] == victim and 1 or 0) or (stack[#stack] == victim and #stack or 0)
            for _ = 1, drop do
                local entry = s % 2 == 1 and table.remove(stack, 1) or table.remove(stack)
                entry.refs = entry.refs - 1
                if entry.refs == 0 then bytes = bytes - entry.bytes end
            end
        end
    end
end
local function RecordHistoryStep(label, source, before, diff)
    if #diff == 0 then return false end
    local stack, redo = EnsureHistoryStacks()
    historyStepSerial = historyStepSerial + 1
    local entry = {
        label = label or "MSUF2 change",
        source = source,
        diff = diff,
    }
    entry.bytes = TableBytes(entry, {})
    entry.seq = historyStepSerial
    snapshotProfiles[entry] = snapshotProfiles[before]
    stack[#stack + 1] = entry
    WipeTable(redo)
    TrimHistoryToBudget(HISTORY_BYTE_BUDGET)
    if historySessionActive then
        historySessionDirty = true
    end
    NotifyHistoryChanged(false)
    if uiBridge then
        UI("ShowHistoryFeedback", label)
    end
    return true
end
SettleHistoryCursor = function()
    if not historyCursorPartial or historyTransaction or deferredHistoryCommit then return end
    local cursor = historySessionSnapshot
    if type(cursor) ~= "table" then
        historyCursorPartial = false
        return
    end
    if IsConfigCombatLocked() then return end
    local drift = ProfileDiff(cursor, SnapshotDB(true))
    historyCursorPartial = false
    if not drift then
        ReportHistorySnapshotFailure()
        return
    end
    if #drift == 0 then return end
    ApplyChanges(cursor, drift, "after")
    local undo = EnsureHistoryStacks()
    local entry
    for i = #undo, 1, -1 do
        if undo[i].seq < historyFirstUnsyncedStep then break end
        entry = undo[i]
    end
    entry = entry or undo[#undo]
    if not entry then return end
    local diff = entry.diff
    for i = 1, #drift do diff[#diff + 1] = drift[i] end
    entry.bytes = entry.bytes + TableBytes(drift, {})
    TrimHistoryToBudget(HISTORY_BYTE_BUDGET)
end
local function ScopedHistoryRoot(before, scope)
    if type(scope) ~= "string" or type(before) ~= "table" or not historySessionActive
        or before ~= historySessionSnapshot then return nil end
    local root = scope:match("^([^.]+)")
    local fields, variants = MSUF.ProfileFields, MSUF.ProfileVariants
    if not root or (fields and fields.IsExternal and fields.IsExternal(root)) then return nil end
    local db = M.EnsureDB()
    if variants and variants.IsMaterialized and variants.IsMaterialized(db) then return nil end
    local cursorDB = before.profileDB
    if type(cursorDB) ~= "table" or type(cursorDB[root]) ~= "table" or type(db[root]) ~= "table" then return nil end
    return root
end
local function PushScopedHistory(label, source, before, root)
    diffOut, diffSeen, diffCount, diffBytes = {}, {}, 0, 0
    diffStrictProfile = MSUF.ProfileVariants ~= nil and MSUF.ProfileFields ~= nil
    diffPath[1], diffPath[2] = "profileDB", root
    local ok = DiffTable(before.profileDB[root], M.EnsureDB()[root], 2, diffStrictProfile)
    local diff = ok and diffOut or nil
    diffOut, diffSeen = nil, nil
    for i = #diffPath, 1, -1 do diffPath[i] = nil end
    if not diff or #diff == 0 then return nil end
    ApplyChanges(before, diff, "after")
    if not historyCursorPartial then historyFirstUnsyncedStep = historyStepSerial + 1 end
    historyCursorPartial = true
    return RecordHistoryStep(label, source, before, diff)
end
local function PushHistory(label, source, before, after)
    if type(before)~="table" or type(after)~="table" then return false end
    if IsForeignProfileSnapshot(before) then
        RebaseHistoryToActiveProfile()
        return false
    end
    local diff = ProfileDiff(before, after)
    if not diff then
        ReportHistorySnapshotFailure()
        return false
    end
    ApplyChanges(before, diff, "after")
    local cursor = historySessionActive and historySessionSnapshot or nil
    if cursor and cursor ~= before then
        local drift = ProfileDiff(cursor, after)
        if drift then ApplyChanges(cursor, drift, "after") end
    elseif historySessionActive then
        historySessionSnapshot = before
    end
    if historySessionActive then historyCursorPartial = false end
    return RecordHistoryStep(label, source, before, diff)
end
local function RepaintActivePage(reason)
    if not UI("RepaintActivePage", reason or "history") then
        NotifyHistoryChanged(true)
    end
end
local function NormalizeHistoryUnit(unit)
    if ApplyService.NormalizeUnit then return ApplyService.NormalizeUnit(unit) end
    unit = (unit == "tot") and "targettarget" or unit
    unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    if not UNIT_KEYS[unit] then return nil end
    return unit
end
local HISTORY_PAGE_RESET_UNITS = {
    uf_player = "player",
    uf_target = "target",
    uf_targettarget = "targettarget",
    uf_focustarget = "focustarget",
    uf_focus = "focus",
    uf_pet = "pet",
    uf_pettarget = "pettarget",
    uf_boss = "boss",
    uf_arena = "arena",
}
local HISTORY_PAGE_RESET_FEATURES = {
    opt_bars = "bars",
    opt_fonts = "fonts",
    opt_colors = "colors",
    opt_castbar = "castbar",
    classpower = "classpower",
    gameplay = "gameplay",
    modules = "modules",
}
local COLOR_CLASSPOWER_RUNTIME = { colors = true, playerHP = true }
local RequestHistoryAurasRuntime
local RequestHistoryGroupRuntime
local function HistoryUnitFromSource(source)
    if type(source) ~= "string" then return nil end
    local unit = source:match("^unit:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^apply:unit:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^edit_mode:unit:([^:]+)")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^unitPreview:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    unit = source:match("^status:reset:([^:]+):")
    if unit then return NormalizeHistoryUnit(unit) end
    local pageKey = source:match("^page:reset:([^:]+)$")
    if pageKey then return NormalizeHistoryUnit(HISTORY_PAGE_RESET_UNITS[pageKey]) end
    pageKey = source:match("^([^:]+):")
    if pageKey then return NormalizeHistoryUnit(HISTORY_PAGE_RESET_UNITS[pageKey]) end
end
local function HistoryFeatureFromSource(source)
    if type(source) ~= "string" then return nil end
    local pageKey = source:match("^page:reset:([^:]+)$")
    if pageKey then return HISTORY_PAGE_RESET_FEATURES[pageKey] end
    local editCategory, editKey = source:match("^edit_mode:([^:]+):?([^:]*)")
    if editCategory == "castbar" then return "castbar", editKey end
    if editCategory == "aura" then return "auras", editKey end
    if editCategory == "gf" then return "group", editKey end
    if editCategory == "external" then return "external", editKey end
    local scope = source:match("^groupPreview:([^:]+):") or source:match("^group:([^:]+):")
    if scope then return "group", scope end
    scope = source:match("^auras:([^:]+):")
    if scope then return "auras", scope end
    if source:match("^classPowerPreview:") or source:match("^classpower:") then return "classpower" end
    pageKey = source:match("^([^:]+):")
    if not pageKey then return nil end
    if pageKey:match("^gf_") then return "group" end
    if pageKey:match("^auras3") then return "auras" end
    if pageKey == "opt_bars" then return "bars" end
    if pageKey == "opt_fonts" then return "fonts" end
    if pageKey == "opt_colors" then return "colors" end
    return HISTORY_PAGE_RESET_FEATURES[pageKey]
end
local function ApplyScopedFeatureRuntime(kind, reason, scope)
    kind = tostring(kind or "")
    reason = reason or "MSUF2_HISTORY_FEATURE"
    if kind == "external" then return true end
    if kind == "castbar" then
        if ApplyService.RequestCastbars then return ApplyService.RequestCastbars(reason, "history") ~= false end
        if M.RequestGeneralDomains then return M.RequestGeneralDomains(reason, { history = false, preview = true, applyAll = false, castbar = true,
            castbarTextures = true }) ~= false end
        _G.MSUF_UpdateCastbarVisuals()
        _G.MSUF_UpdateBossCastbarPreview()
        return true
    end
    if kind == "classpower" then
        _G.MSUF_ApplyModules()
        if ApplyService.RequestClassPowerDomains then
            ApplyService.RequestClassPowerDomains(reason, CLASSPOWER_FULL_RUNTIME)
            return true
        end
        return true, _G.MSUF_ClassPower_Apply(CLASSPOWER_FULL_RUNTIME)
    end
    if kind == "auras" then
        return RequestHistoryAurasRuntime and RequestHistoryAurasRuntime(reason, scope) or false
    end
    if kind == "group" then
        return RequestHistoryGroupRuntime and RequestHistoryGroupRuntime(reason, scope) or false
    end
    if kind == "bars" and ApplyService.RequestBars then
        return ApplyService.RequestBars(reason, scope) ~= false
    end
    if kind == "fonts" and ApplyService.RequestFonts then
        return ApplyService.RequestFonts(reason, scope) ~= false
    end
    if kind == "colors" then
        local did = ApplyService.RequestColors and ApplyService.RequestColors(reason, scope) ~= false or false
        if RequestHistoryAurasRuntime then did = RequestHistoryAurasRuntime(reason, scope, true) or did end
        if ApplyService.RequestClassPowerDomains then
            ApplyService.RequestClassPowerDomains(reason, COLOR_CLASSPOWER_RUNTIME, { preview = true, applyAll = false, classpower = true })
            did = true
        end
        return did
    end
    if kind == "gameplay" then
        if uiBridge then
            local result = UI("ApplyGameplay")
            return result ~= false
        end
        if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
            local result = MSUF.MSUF_RequestGameplayApply(reason)
            return result ~= false
        end
        if MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
            local result = MSUF.MSUF_ApplyGameplayVisuals()
            return result ~= false
        end
        return false
    end
    if kind == "modules" then
        return true, _G.MSUF_ApplyModules()
    end
    return false
end
local function ApplyScopedHistoryRestore(reason, source)
    if source == "classpower:playerPowerSource" then
        _G.MSUF_ApplyModules()
        _G.MSUF_ClassPower_Apply(CLASSPOWER_FULL_RUNTIME)
        UI("RefreshUnitPreview", reason)
        UI("RefreshPlayerPowerSource")
        return true
    end
    local unit = HistoryUnitFromSource(source)
    local applyReason = reason or "MSUF2_HISTORY_UNIT"
    if unit then
        if unit == "player" and source == "page:reset:uf_player" then
            ApplyScopedFeatureRuntime("classpower", applyReason)
        end
        local opts = {
            history = false,
            preview = true,
            power = true,
            castbar = true,
            auras = true,
            classpowerApplied = unit == "player" and source == "page:reset:uf_player",
        }
        return RequestHistoryApply("RequestUnitDomains", unit, applyReason, opts) ~= false
    end
    local feature, scope = HistoryFeatureFromSource(source)
    if feature then return ApplyScopedFeatureRuntime(feature, applyReason, scope) end
    return false
end
RequestHistoryAurasRuntime = function(reason, scope, visuals)
    if visuals and ApplyService.RequestAuraFonts then
        ApplyService.RequestAuraFonts(scope or "shared", reason or "MSUF2_HISTORY_AURAS")
        return true
    end
    if ApplyService.RequestAuras then
        ApplyService.RequestAuras(scope or "shared", reason or "MSUF2_HISTORY_AURAS")
        return true
    end
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras and type(auras.RequestApply) == "function" then
        auras.RequestApply()
        return true
    end
    return false
end
RequestHistoryGroupRuntime = function(reason, kind)
    kind = kind and tostring(kind) or nil
    if kind == "gf_party" then kind = "party" end
    if kind == "gf_raid" then kind = "raid" end
    if kind == "gf_mythicraid" then kind = "mythicraid" end
    if kind == "gf_priority" then kind = "priority" end
    if kind and kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid" and kind ~= "priority" then kind = nil end
    if kind and ApplyService.RequestGroup then
        ApplyService.RequestGroup(kind, "reset", reason or "MSUF2_HISTORY_GROUP")
        return true
    end
    if ApplyService.RequestGroupReset then
        ApplyService.RequestGroupReset(reason or "MSUF2_HISTORY_GROUP")
        return true
    end
    if ApplyService.RequestGroup then
        ApplyService.RequestGroup("group", "reset", reason or "MSUF2_HISTORY_GROUP")
        return true
    end
    if MSUF and MSUF.GF then
        if type(MSUF.GF.RefreshAll) == "function" then
            MSUF.GF.RefreshAll()
        else
            if type(MSUF.GF.RefreshVisuals) == "function" then MSUF.GF.RefreshVisuals() end
        end
        if type(MSUF.GF.RefreshPreviewLayout) == "function" then MSUF.GF.RefreshPreviewLayout() end
        return true
    end
    return false
end
local function FlushApplyServiceNow()
    if ApplyService.Flush then
        ApplyService.Flush()
        return true
    end
    return false
end
local SETTER_ONLY_SETTINGS = {
    msufUiScale = { "MSUF_ApplyMsufScale", "scale" },
    showMinimapIcon = { "MSUF_SetMinimapIconEnabled", "enabled" },
    showGameMenuButton = { "MSUF_SetGameMenuButtonEnabled", "enabled" },
    playTargetSelectLostSounds = { "MSUF_TargetSoundDriver_ApplySetting" },
    playerResourcePingEnabled = { "MSUF_RefreshPlayerResourcePing" },
    versionCheckEnabled = { "MSUF_ApplyModules" },
    nsrtNicknameIntegration = { "MSUF_NSRTNicknames_ApplySetting" },
    grid2EditModeIntegration = { "MSUF_Grid2EditMode_SetEnabled", "enabled" },
    detailsEditModeIntegration = { "MSUF_DetailsEditMode_SetEnabled", "enabled" },
    dominosEditModeIntegration = { "MSUF_DominosEditMode_SetEnabled", "enabled" },
    dandersEditModeIntegration = { "MSUF_DandersEditMode_SetEnabled", "enabled" },
    unitTooltipMode = { apply = function() MSUF.Tooltips.Refresh() end },
    numberAbbrevStyle = { apply = function() MSUF.NumberFormat.Refresh() end },
    mapkoSkinMenus = { apply = function() if MSUF.MenuSkin then MSUF.MenuSkin.Refresh() end end },
}
if MSUF.Client.SupportsEllesmereEditMode then
    SETTER_ONLY_SETTINGS.ellesmereEditModeIntegration = { "MSUF_EllesmereEditMode_SetEnabled", "enabled" }
end
if MSUF.Client.SupportsBlizzardEditMode then
    SETTER_ONLY_SETTINGS.blizzardEditModeIntegration = { "MSUF_BlizzardEditMode_SetEnabled", "enabled" }
end
local CASTBAR_HISTORY_UNITS = { "player", "target", "focus", "boss", "arena" }
local function BarHistoryFlag(key)
    if type(key) ~= "string" then return end
    local lower = key:lower()
    if lower:find("baroutline", 1, true) then return "barOutline" end
    if lower:find("rounded", 1, true) then return "roundedBars" end
    if lower:find("gradient", 1, true) then return "barGradients" end
    if lower:find("highlight", 1, true) or lower:match("^hl") then return "highlightBorders" end
end
local function CaptureRuntimeSettings(db, values)
    values.castbarBackends, values.barSettings = {}, {}
    for _, unit in ipairs(CASTBAR_HISTORY_UNITS) do
        values.castbarBackends[unit] = MSUF.Castbars.Backend.Resolve(unit, db.general)
    end
    for scope, config in pairs(db) do
        if type(config) == "table" then
            local fields
            for key, value in pairs(config) do
                if BarHistoryFlag(key) then
                    fields = fields or {}
                    fields[key] = type(value) == "table" and DeepCopy(value) or value
                end
            end
            if fields then values.barSettings[scope] = fields end
        end
    end
end
local function ResyncRuntimeSettings(db, before)
    for _, unit in ipairs(CASTBAR_HISTORY_UNITS) do
        if before.castbarBackends[unit] ~= MSUF.Castbars.Backend.Resolve(unit, db.general) then
            ApplyService.RequestCastbarUnit(unit, "MSUF2_HISTORY_BACKEND", "history")
        end
    end
    local flags = { preview = true, applyAll = false, notify = false }
    local changed = false
    local function Compare(fields, other)
        for key, value in pairs(fields) do
            local flag = BarHistoryFlag(key)
            if flag and not DeepEqual(value, other and other[key]) then
                flags[flag], changed = true, true
            end
        end
    end
    for scope, fields in pairs(before.barSettings) do Compare(fields, db[scope]) end
    for scope, config in pairs(db) do
        if type(config) == "table" then Compare(config, before.barSettings[scope]) end
    end
    if changed then ApplyService.RequestGeneralDomains("MSUF2_HISTORY_BAR_SETTINGS", flags) end
end
local function CaptureSetterOnlySettings()
    local db, values = M.EnsureDB(), {}
    local g = db and db.general
    if type(g) ~= "table" then return values end
    for key in pairs(SETTER_ONLY_SETTINGS) do values[key] = g[key] end
    values.menu = UI("CaptureMenuSettings", g)
    CaptureRuntimeSettings(db, values)
    return values
end
local function ResyncSetterOnlySettings(before)
    local db = M.EnsureDB()
    local g = db and db.general
    if type(g) ~= "table" or type(before) ~= "table" then return end
    UI("ResyncMenuSettings", before.menu, g)
    if before.castbarBackends then ResyncRuntimeSettings(db, before) end
    for key, entry in pairs(SETTER_ONLY_SETTINGS) do
        local value = g[key]
        if value ~= before[key] then
            local setter = entry.apply or MSUF.Require(entry[1], "Shell/Menu2/MSUF_Menu2_Bindings_History.lua")
            if entry[2] == "scale" then
                setter(tonumber(value) or 1)
            elseif entry[2] == "enabled" then
                setter(value ~= false)
            else
                setter()
            end
        end
    end
end
local function RestoreHistoryProfile(activeDB, profileDB, reason)
    if MSUF.ProfileVariants then MSUF.ProfileVariants.Restore(false) end
    if MSUF.ProfileFields and MSUF.ProfileFields.RestoreExternal then
        local restored=MSUF.ProfileFields.RestoreExternal(activeDB,profileDB)
        if not restored then
            if MSUF.ProfileVariants then MSUF.ProfileVariants.ResolveCurrent() end
            return false
        end
        local owned = {}
        for key, value in pairs(profileDB) do owned[key] = value end
        profileDB = MSUF.ProfileFields.StripExternal(owned)
    end
    DeepReplace(activeDB, profileDB)
    MSUF.Castbars.Config.Invalidate()
    if MSUF.ProfileVariants then MSUF.ProfileVariants.ResolveCurrent() end
    if MSUF.ProfileFields and MSUF.ProfileFields.ApplyExternal then MSUF.ProfileFields.ApplyExternal(reason) end
    return true
end
local function ApplyHistorySnapshot(snapshot, reason, source, trustProfile)
    if type(snapshot) ~= "table" then return false end
    if trustProfile ~= true and IsForeignProfileSnapshot(snapshot) then return false, "profile_mismatch" end
    local profileDB = HistoryProfileDB(snapshot)
    if type(profileDB) ~= "table" then return false end
    historyRestoring = true
    local activeDB = M.EnsureDB()
    local activeGeneral = activeDB and activeDB.general
    local activeUi = type(activeGeneral) == "table" and activeGeneral.UIScale
    local restoredGeneral = profileDB.general
    local restoredUi = type(restoredGeneral) == "table" and restoredGeneral.UIScale
    local wasEnabled = type(activeUi) == "table" and activeUi.Enabled == true
    local willEnable = type(restoredUi) == "table" and restoredUi.Enabled == true
    local scaleChanged = wasEnabled ~= willEnable
        or (willEnable and tonumber(activeUi.Scale) ~= tonumber(restoredUi.Scale))
    local setterOnly = CaptureSetterOnlySettings()
    if not RestoreHistoryProfile(activeDB, profileDB, reason or "MSUF2_HISTORY") then
        historyRestoring = false
        return false
    end
    RestoreProfileRouting(snapshot)
    local externalAPI = (type(MSUF) == "table" and MSUF.EditModeAPI) or _G.MSUF_EditModeAPI
    if type(externalAPI) == "table" and type(externalAPI._RestoreHistorySnapshot) == "function"
        and type(snapshot.externalEditMode) == "table" then
        externalAPI._RestoreHistorySnapshot(snapshot.externalEditMode, reason or "history")
    end
    RestoreHistoryProviders(snapshot, reason, source)
    historyRestoring = false
    if scaleChanged and type(_G.MSUF_ApplyCurrentProfileGlobalUiScale) == "function" then
        _G.MSUF_ApplyCurrentProfileGlobalUiScale()
    end
    ResyncSetterOnlySettings(setterOnly)
    if ApplyScopedHistoryRestore(reason, source) then
        FlushApplyServiceNow()
        M.MarkMenuDataDirty(reason or "history")
        RepaintActivePage(reason)
        _G.MSUF_EM_RefreshAfterHistoryRestore(reason or "MSUF2_HISTORY", source)
        return true
    end
    RequestHistoryApply("RequestGeneralDomains", reason or "MSUF2_HISTORY", {
        history = false, preview = true, alpha = true, castbar = true,
    })
    if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
        MSUF.MSUF_RequestGameplayApply()
    elseif MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
        MSUF.MSUF_ApplyGameplayVisuals()
    end
    UI("ApplyMenuScale")
    RequestHistoryAurasRuntime(reason or "MSUF2_HISTORY_AURAS")
    if ApplyService.RequestClassPowerDomains then
        ApplyService.RequestClassPowerDomains("MSUF2_HISTORY_CLASSPOWER", CLASSPOWER_FULL_RUNTIME, {
            preview = false,
            applyAll = false,
            classpower = true,
        })
    end
    RequestHistoryGroupRuntime(reason or "MSUF2_HISTORY_GROUP")
    FlushApplyServiceNow()
    _G.MSUF_ApplySpecProfileIfEnabled("MSUF2_HISTORY_PROFILE_ROUTING")
    UI("ApplyLocaleSelection")
    M.MarkMenuDataDirty(reason or "history")
    RepaintActivePage(reason)
    _G.MSUF_EM_RefreshAfterHistoryRestore(reason or "MSUF2_HISTORY", source)
    return true
end
function M.CaptureGuidedTourRestorePoint()
    if IsConfigCombatLocked() then return nil end
    local snapshot = SnapshotDB()
    snapshot._msuf2GuidedProfileName = tostring(_G.MSUF_ActiveProfile or "Default")
    return snapshot
end
function M.RestoreGuidedTourRestorePoint(snapshot)
    if IsConfigCombatLocked() then return false end
    local expectedProfile = type(snapshot) == "table" and tostring(snapshot._msuf2GuidedProfileName or "") or ""
    local activeProfile = tostring(_G.MSUF_ActiveProfile or "Default")
    if expectedProfile == "" or activeProfile ~= expectedProfile then return false, "profile_mismatch" end
    SettleHistoryCursor()
    local ok, why = ApplyHistorySnapshot(snapshot, "MSUF2_GUIDED_TOUR_RESTORE", "guided_tour:restore_point", true)
    if ok and historySessionActive then SyncHistoryCursor() end
    return ok, why
end
function M.IsHistoryCapturing()
    return HistoryBusy()
end
function M.CaptureHistory(label, source, fn, scope)
    if type(fn) ~= "function" then return nil end
    if M.BlockCombatAction() then return false end
    if historyTransaction and historyTransaction.preparedNudge == true and historyDepth == 0
        and historyTransaction.source ~= source then M.CommitHistoryTransaction() end
    if HistoryBusy() then
        local result = fn()
        if result ~= false then
            if historyTransaction then
                historyTransaction.dirty = true
            elseif M.MarkMenuDataDirty then
                M.MarkMenuDataDirty("history")
            end
        end
        return result
    end
    local root = scope and ScopedHistoryRoot(historySessionSnapshot, scope)
    if not root then SettleHistoryCursor() end
    local before = CurrentHistorySnapshot()
    local snapshotted = type(before) == "table"
    if not snapshotted then ReportHistorySnapshotFailure() end
    EnterHistoryDepth()
    local result = fn()
    LeaveHistoryDepth()
    if result == false then return result end
    local pushed = false
    if snapshotted then
        root = root and ScopedHistoryRoot(before, scope)
        if root then pushed = PushScopedHistory(label, source, before, root) end
        if pushed == nil or not root then
            local after = SnapshotDB(true)
            if type(after) ~= "table" then ReportHistorySnapshotFailure() end
            pushed = PushHistory(label, source, before, after)
        end
    end
    if MSUF.ProfileVariants then MSUF.ProfileVariants.RequestApply("PROFILE_VARIANT_SETTING") end
    if (pushed or not snapshotted) and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return result
end
function M.RunWithHistory(label, source, fn)
    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then return M.CaptureHistory(label, source, fn) end
    return type(fn) == "function" and fn() or nil
end
local function CopyStack(stack)
    local copy = {}
    for i = 1, #stack do copy[i] = stack[i] end
    return copy
end
local function RestoreStack(stack, saved)
    WipeTable(stack)
    for i = 1, #(saved or {}) do stack[i] = saved[i] end
end
local function DeferHistoryCommit(label, source, before)
    if deferredHistoryCommit then return true end
    deferredHistoryCommit = {
        label = label or "MSUF2 change",
        source = source or "external:change",
        before = before,
    }
    return true
end
function M.FlushDeferredHistory(afterSnapshot)
    if IsConfigCombatLocked() or not deferredHistoryCommit then return false end
    local pending = deferredHistoryCommit
    deferredHistoryCommit = nil
    afterSnapshot = type(afterSnapshot) == "table" and afterSnapshot or SnapshotDB(true)
    local pushed = PushHistory(pending.label, pending.source, pending.before, afterSnapshot)
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed, afterSnapshot
end
function M.DeferPreparedHistory(prepared)
    if historyRestoring or type(prepared) ~= "table" or prepared._msuf2PreparedHistory ~= true then return false end
    return DeferHistoryCommit(prepared.label, prepared.source, prepared.before)
end
function M.StartHistorySession(surface)
    if IsConfigCombatLocked() then return false end
    surface = tostring(surface or "menu")
    if historySurfaces[surface] then
        M.FlushDeferredHistory()
        return true
    end
    SettleHistoryCursor()
    if not historySessionActive then
        HealLeakedHistoryDepth()
        historyRestoring = false
    end
    M.FlushDeferredHistory()
    local fresh = not historySessionActive
    if fresh then
        historyCursorPartial = false
        historySessionSnapshot = SnapshotDB()
    end
    local undo, redo = EnsureHistoryStacks()
    historySurfaces[surface] = true
    historySurfaceCount = historySurfaceCount + 1
    historySurfaceMarkers[surface] = {
        undo = CopyStack(undo),
        redo = CopyStack(redo),
        point = NewHistoryPoint(),
    }
    if fresh then
        historySessionActive = true
        historySessionBaseSnapshot = NewHistoryPoint()
        historySessionDirty = false
    end
    NotifyHistoryChanged()
    return true
end
function M.EndHistorySession(surface)
    local combatLocked = IsConfigCombatLocked()
    surface = tostring(surface or "menu")
    if historyTransaction then
        local txSurface = type(historyTransaction.source) == "string" and historyTransaction.source:match("^edit_mode:")
            and "edit_mode" or "menu"
        if txSurface == surface or historySurfaceCount <= 1 then M.CommitHistoryTransaction() end
    end
    if historySurfaces[surface] then
        historySurfaces[surface] = nil
        historySurfaceMarkers[surface] = nil
        historySurfaceCount = math.max(0, historySurfaceCount - 1)
    end
    if historySurfaceCount == 0 then
        SettleHistoryCursor()
        historySessionActive = false
        historySessionBaseSnapshot = nil
        if not historyCursorPartial then historySessionSnapshot = nil end
        historySessionDirty = false
    end
    if combatLocked then
        CancelQueuedMenuRefresh()
    else
        NotifyHistoryChanged()
    end
    return true
end
local function RewindCursorToPoint(point)
    local cursor = CurrentHistorySnapshot()
    if type(cursor) ~= "table" then return nil end
    SyncHistoryCursor()
    local changes, replaced = PointChanges(point.tree, 0, {}, {}), {}
    ApplyChanges(cursor, changes, "before", replaced)
    return cursor, changes, replaced
end
function M.CancelHistorySurface(surface, restoreState)
    if IsConfigCombatLocked() then return false end
    surface = tostring(surface or "menu")
    local marker = historySurfaceMarkers[surface]
    if not marker then return false end
    if IsForeignProfileSnapshot(marker.point) then
        RebaseHistoryToActiveProfile()
        return false
    end
    if historyTransaction then M.CancelHistoryTransaction() end
    if restoreState == true then
        local cursor, changes, replaced = RewindCursorToPoint(marker.point)
        if not cursor then return false end
        local profileDB = HistoryProfileDB(cursor)
        local setterOnly = CaptureSetterOnlySettings()
        historyRestoring = true
        if type(profileDB) ~= "table"
            or not RestoreHistoryProfile(M.EnsureDB(), profileDB, "MSUF2_HISTORY_CANCEL_SURFACE") then
            RevertChanges(cursor, changes, replaced, "before")
            historyRestoring = false
            return false
        end
        RestoreProfileRouting(cursor)
        RestoreHistoryProviders(cursor, "MSUF2_HISTORY_CANCEL_SURFACE", surface)
        historyRestoring = false
        ResyncSetterOnlySettings(setterOnly)
        marker.point.tree = {}
    else
        SyncHistoryCursor()
    end
    local undo, redo = EnsureHistoryStacks()
    RestoreStack(undo, marker.undo)
    RestoreStack(redo, marker.redo)
    RefreshSessionDirty()
    NotifyHistoryChanged(true)
    return true
end
function M.CheckpointHistory(label, source)
    if M.BlockCombatAction() then return false end
    if HistoryBusy() or not historySessionActive then return false end
    SettleHistoryCursor()
    local before = CurrentHistorySnapshot()
    local after = SnapshotDB(true)
    if type(before) ~= "table" or type(after) ~= "table" then ReportHistorySnapshotFailure() end
    local pushed = PushHistory(label or "MSUF2 change", source or "menu:checkpoint", before, after)
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed
end
function M.BeginHistoryTransaction(label, source, scope)
    if M.BlockCombatAction() then return false end
    if historyTransaction and source and historyTransaction.source ~= source then M.CommitHistoryTransaction() end
    if HistoryBusy() or not historySessionActive then return false end
    SettleHistoryCursor()
    local before = CurrentHistorySnapshot()
    if type(before) ~= "table" then ReportHistorySnapshotFailure() end
    historyTransaction = {
        label = label or "MSUF2 change",
        source = source or "menu:transaction",
        before = before,
        scope = scope,
    }
    return true
end
function M.PrepareHistoryChange(label, source)
    if M.BlockCombatAction() then return nil end
    if HistoryBusy() then return nil end
    SettleHistoryCursor()
    local before = CurrentHistorySnapshot()
    if type(before) ~= "table" then ReportHistorySnapshotFailure() end
    return {
        _msuf2PreparedHistory = true,
        label = label or "MSUF change",
        source = source or "external:change",
        before = before,
    }
end
function M.BeginPreparedHistory(prepared)
    if M.BlockCombatAction() or HistoryBusy() or not historySessionActive then return nil end
    if type(prepared) ~= "table" or prepared._msuf2PreparedHistory ~= true
        or IsForeignProfileSnapshot(prepared.before) then return nil end
    historyTransaction = {
        label = prepared.label,
        source = prepared.source,
        before = prepared.before,
        preparedNudge = true,
    }
    return historyTransaction
end
function M.IsHistoryTransactionActive(token)
    return token ~= nil and historyTransaction == token
end
function M.CommitPreparedHistory(prepared)
    if historyRestoring or type(prepared) ~= "table" or prepared._msuf2PreparedHistory ~= true then return false end
    if IsConfigCombatLocked() then
        M.DeferPreparedHistory(prepared)
        return false
    end
    local pushed = PushHistory(prepared.label, prepared.source, prepared.before, SnapshotDB(true))
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed
end
function M.CommitHistoryTransaction()
    local tx = historyTransaction
    if not tx then return false end
    historyTransaction = nil
    if IsConfigCombatLocked() then
        DeferHistoryCommit(tx.label, tx.source, tx.before)
        return false
    end
    local root = tx.scope and ScopedHistoryRoot(tx.before, tx.scope)
    local pushed = root and PushScopedHistory(tx.label, tx.source, tx.before, root)
    if pushed == nil or not root then
        pushed = PushHistory(tx.label, tx.source, tx.before, SnapshotDB(true))
    end
    if pushed and M.MarkMenuDataDirty then M.MarkMenuDataDirty("history") end
    return pushed
end
function M.CancelHistoryTransaction()
    if not historyTransaction then return false end
    historyTransaction = nil
    return true
end
function M.ResetHistorySession()
    if M.BlockCombatAction() then return false end
    if not historySessionActive or type(historySessionBaseSnapshot) ~= "table" then return false end
    local cursor, changes, replaced = RewindCursorToPoint(historySessionBaseSnapshot)
    if not cursor then return false end
    local ok, why = ApplyHistorySnapshot(cursor, "MSUF2_HISTORY_RESET_SESSION")
    if not ok then RevertChanges(cursor, changes, replaced, "before") end
    if ok then M.ClearHistory() end
    if why == "profile_mismatch" then RebaseHistoryToActiveProfile() end
    if ok then UI("CommandFeedback", "reset") end
    return ok
end
function M.ClearHistory()
    if IsConfigCombatLocked() then return false end
    deferredHistoryCommit = nil
    historyCursorPartial = false
    local undo, redo = EnsureHistoryStacks()
    WipeTable(undo)
    WipeTable(redo)
    if not historySessionActive then historySessionSnapshot = nil end
    if historySessionActive then
        historySessionSnapshot = SnapshotDB()
        for surface in pairs(historySurfaces) do
            historySurfaceMarkers[surface] = { undo = {}, redo = {}, point = NewHistoryPoint() }
        end
        historySessionBaseSnapshot = NewHistoryPoint()
        historySessionDirty = false
    end
    NotifyHistoryChanged()
    return true
end
function M.GetHistoryState()
    local undoStack, redoStack = EnsureHistoryStacks()
    local undo = undoStack[#undoStack]
    local redo = redoStack[#redoStack]
    local nudge = historyTransaction and historyTransaction.preparedNudge == true and historyTransaction or nil
    return {
        canUndo = undo ~= nil or nudge ~= nil,
        canRedo = redo ~= nil and not nudge,
        canResetAll = historySessionActive and type(historySessionBaseSnapshot) == "table" and historySessionDirty,
        undoLabel = undo and HistoryDisplayLabel(undo.label) or nil,
        redoLabel = redo and HistoryDisplayLabel(redo.label) or nil,
        undoCount = #undoStack,
        redoCount = #redoStack,
        activeSurfaces = historySurfaceCount,
    }
end
local function ApplyHistoryEntry(entry, field, reason)
    if IsForeignProfileSnapshot(entry) then return false, "profile_mismatch" end
    local cursor = CurrentHistorySnapshot()
    if type(cursor) ~= "table" then return false end
    local replaced = {}
    ApplyChanges(cursor, entry.diff, field, replaced)
    local ok, why = ApplyHistorySnapshot(cursor, reason, entry.source)
    if not ok then
        RevertChanges(cursor, entry.diff, replaced, field)
        return ok, why
    end
    RefreshSessionDirty()
    return true
end
function M.Undo()
    if M.BlockCombatAction() then return false end
    if historyTransaction and historyTransaction.preparedNudge == true then M.CommitHistoryTransaction() end
    M.FlushDeferredHistory()
    SettleHistoryCursor()
    local undo, redo = EnsureHistoryStacks()
    local entry = table.remove(undo)
    if not entry then return false end
    local ok, why = ApplyHistoryEntry(entry, "before", "MSUF2_HISTORY_UNDO")
    if ok then
        redo[#redo + 1] = entry
    elseif why == "profile_mismatch" then
        RebaseHistoryToActiveProfile()
    else
        undo[#undo + 1] = entry
    end
    NotifyHistoryChanged()
    if ok then UI("CommandFeedback", "undo", entry.label) end
    return ok
end
function M.Redo()
    if M.BlockCombatAction() then return false end
    if historyTransaction and historyTransaction.preparedNudge == true then M.CommitHistoryTransaction() end
    M.FlushDeferredHistory()
    SettleHistoryCursor()
    local undo, redo = EnsureHistoryStacks()
    local entry = table.remove(redo)
    if not entry then return false end
    local ok, why = ApplyHistoryEntry(entry, "after", "MSUF2_HISTORY_REDO")
    if ok then
        undo[#undo + 1] = entry
    elseif why == "profile_mismatch" then
        RebaseHistoryToActiveProfile()
    else
        redo[#redo + 1] = entry
    end
    NotifyHistoryChanged()
    if ok then UI("CommandFeedback", "redo", entry.label) end
    return ok
end
function M.RequestUnitDomains(unit, reason, opts)
    if M.BlockCombatAction() then return false end
    if ApplyService.NormalizeUnit then
        unit = ApplyService.NormalizeUnit(unit)
    else
        unit = (unit == "tot") and "targettarget" or unit
        unit = (unit == "focus_target" or unit == "focustargettarget") and "focustarget" or unit
    end
    if not UNIT_KEYS[unit] then return end
    if not (opts and opts.history == false) then
        M.CheckpointHistory(reason or ("MSUF2_" .. tostring(unit)), "apply:unit:" .. tostring(unit) .. ":" .. tostring(reason or "change"))
    end
    local result = false
    if ApplyService.RequestUnit then result = ApplyService.RequestUnitDomains(unit, reason, opts) end
    return result
end
function M.RequestGeneralDomains(reason, opts)
    if M.BlockCombatAction() then return false end
    if not (opts and opts.history == false) then
        M.CheckpointHistory(reason or "MSUF2_GENERAL", "apply:general:" .. tostring(reason or "change"))
    end
    local result = false
    if ApplyService.RequestGeneral then result = ApplyService.RequestGeneralDomains(reason, opts) end
    return result
end
M.ApplyScopedFeatureRuntime = ApplyScopedFeatureRuntime
M.FlushApplyServiceNow = FlushApplyServiceNow
M.CaptureSetterOnlySettings, M.ResyncSetterOnlySettings = CaptureSetterOnlySettings, ResyncSetterOnlySettings
M.COLOR_CLASSPOWER_RUNTIME = COLOR_CLASSPOWER_RUNTIME

function M.RequestGeneralApply(reason, opts)
    if M.BlockCombatAction() then return false end
    if not (opts and opts.history == false) then
        M.CheckpointHistory(reason or "MSUF2_GENERAL", "apply:general:" .. tostring(reason or "change"))
    end
    return ApplyService.RequestGeneral(reason, opts)
end
M.RequestUnitApply = M.RequestUnitDomains

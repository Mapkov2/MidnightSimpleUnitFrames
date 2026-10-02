local _, MSUF = ...
local Fields, Variants = MSUF.ProfileFields, {}
MSUF.ProfileVariants = Variants
local activeDB, journal, manual = nil, {}, nil
local DARK_PATH = { "general", "darkMode" }
local DARK_ID = Fields.ID(DARK_PATH)
local NO_CONDITIONS, NO_ENTRIES = {}, {}
-- Precise reasons for a profile snapshot that cannot be taken.
local SNAPSHOT_PROBLEMS = {
    number = "profile contains an invalid number",
    value = "profile contains a value that cannot be saved",
    cycle = "profile contains a table that refers to itself",
    limits = "profile exceeds snapshot limits",
}
local CONTEXTS = { party=true, raid=true, arena=true, pvp=true, solo=true, world=true }
local function AddPath(tree,path)
    local node=tree
    for i=1,#path do
        if node.terminal then return false end
        node.children=node.children or {}
        node.children[path[i]]=node.children[path[i]] or {}
        node=node.children[path[i]]
    end
    if node.children and next(node.children) then return false end
    node.terminal=true
    return true
end
local function Entries(db)
    local schema = type(db) == "table" and db.profileVariants
    return type(schema) == "table" and type(schema.entries) == "table" and schema.entries or nil
end
local function Entry(db, name)
    for _, entry in ipairs(Entries(db) or {}) do if entry.name == name then return entry end end
end

function Variants.Validate(schema)
    if schema == nil then return nil end
    if type(schema) ~= "table" or getmetatable(schema) ~= nil or schema.version ~= 1 or type(schema.entries) ~= "table"
        or #schema.entries > 16 then return nil, "invalid profile variants" end
    local clean, names, allPaths, hotkeys = { version=1, entries={} }, {}, {}, {}
    for index, entry in ipairs(schema.entries) do
        if type(entry) ~= "table" or getmetatable(entry) ~= nil or type(entry.name) ~= "string" or #entry.name < 1
            or #entry.name > 64 or entry.name:find("[%c]") or names[entry.name] then return nil, "invalid variant name" end
        names[entry.name] = true
        local patch, err = Fields.ValidatePatch(entry.patch or {})
        if not patch then return nil, err end
        for _, field in ipairs(patch) do
            if not AddPath(allPaths,field.path) then return nil,"overlapping variant table paths" end
        end
        local input, condition = entry.conditions or {}, {}
        if type(input) ~= "table" or getmetatable(input) ~= nil then return nil, "invalid variant conditions" end
        if input.context ~= nil then
            if not CONTEXTS[input.context] then return nil, "invalid variant context" end
            condition.context = input.context
        end
        if input.dark ~= nil then
            if type(input.dark) ~= "boolean" then return nil, "invalid dark condition" end
            condition.dark = input.dark
        end
        condition.manual = input.manual == true
        if input.specs ~= nil then
            if type(input.specs) ~= "table" then return nil, "invalid specialization group" end
            condition.specs = {}
            local count = 0
            for id, enabled in pairs(input.specs) do
                if type(id) ~= "string" or not id:match("^%d+$") or #id>6 or enabled ~= true then return nil, "invalid specialization" end
                count=count+1
                if count>32 then return nil, "too many specializations" end
                condition.specs[id]=true
            end
        end
        local hotkey=entry.hotkey
        if hotkey~=nil then
            if type(hotkey)~="number" or hotkey<1 or hotkey>8 or hotkey~=math.floor(hotkey) or hotkeys[hotkey] then
                return nil,"invalid or duplicate variant hotkey"
            end
            hotkeys[hotkey]=true
            condition.manual=true
        end
        clean.entries[index] = { name=entry.name, enabled=entry.enabled ~= false, conditions=condition, patch=patch, hotkey=hotkey }
    end
    for index in pairs(schema.entries) do
        if type(index) ~= "number" or index < 1 or index > #clean.entries or index ~= math.floor(index) then
            return nil, "invalid variant list"
        end
    end
    return clean
end

-- Context values travel as plain arguments so the per-event signature below
-- allocates nothing.
local function MatchValues(entry, location, spec, dark)
    if type(entry) ~= "table" or entry.enabled == false then return false end
    local c = type(entry.conditions) == "table" and entry.conditions or NO_CONDITIONS
    if c.manual and entry.name ~= manual then return false end
    if c.context and c.context ~= location then return false end
    if c.dark ~= nil and c.dark ~= dark then return false end
    if type(c.specs) == "table" and next(c.specs) and not c.specs[tostring(spec or "")] then return false end
    return true
end
local function Matches(entry, context)
    return MatchValues(entry, context.location, context.spec, context.dark)
end

-- Capture edits of an overlaid setting back into its owning variant. An ordinary
-- menu slider must never silently overwrite the remembered base value.
local function CaptureEdits()
    if not activeDB then return end
    for _, record in pairs(journal) do
        local value = Fields.Read(activeDB, record.path)
        if not Fields.Equal(value, record.applied) then
            local owner = Entry(activeDB, record.owner)
            if owner then
                for _, field in ipairs(owner.patch) do
                    if Fields.ID(field.path) == record.id then
                        local copied, valid = Fields.Copy(value)
                        if valid then field.value, field.remove = copied, value == nil end
                        break
                    end
                end
            end
        end
    end
end

local function RestoreInto(db)
    local created={}
    for _, record in pairs(journal) do
        Fields.Write(db, record.path, Fields.CopySnapshot(record.base))
        for _,path in ipairs(record.created) do created[#created+1]=path end
    end
    table.sort(created,function(a,b) return #a>#b end)
    for _,path in ipairs(created) do
        local value=Fields.Read(db,path)
        if type(value)=="table" and next(value)==nil then Fields.Write(db,path,nil) end
    end
end

function Variants.Restore(capture)
    if not activeDB then return end
    if capture ~= false then CaptureEdits() end
    RestoreInto(activeDB)
    journal, activeDB = {}, nil
end

function Variants.Resolve(db, context)
    Variants.Restore()
    if type(db) ~= "table" or db.profileVariants == nil then return false end
    local schema, err = Variants.Validate(db.profileVariants)
    if not schema then return false, err end
    db.profileVariants = schema
    local entries = schema.entries
    if not entries or #entries == 0 then return false end
    activeDB = db
    context = context or Variants.Context(db)
    local applied = false
    for _, entry in ipairs(entries) do
        if Matches(entry, context) then
            for _, field in ipairs(entry.patch) do
              if not Fields.ExternalAvailable or Fields.ExternalAvailable(db,field.path) then
                local id = Fields.ID(field.path)
                local record = journal[id]
                if not record then
                    local base,valid=Fields.CopySnapshot(Fields.Read(db,field.path))
                    if not valid then Variants.Restore(false); return false,"setting base exceeds copy limits" end
                    record = { id=id, path=field.path, base=base, created={} }
                    local prefix={}
                    for i=1,#field.path-1 do
                        prefix[i]=field.path[i]
                        local parent=Fields.Read(db,prefix)
                        if parent~=nil and type(parent)~="table" then
                            Variants.Restore(false)
                            return false,"setting parent is not a table"
                        end
                        if parent==nil then record.created[#record.created+1]=Fields.Copy(prefix) end
                    end
                    journal[id] = record
                end
                local value=Fields.Copy(field.value)
                if field.remove then value=nil end
                if Fields.CheckExternal then
                    local valid
                    value,valid=Fields.CheckExternal(field.path,value,field.remove)
                    if not valid then Variants.Restore(false); return false,"invalid setting value" end
                end
                if record.base~=nil and value~=nil and type(record.base)~=type(value) then
                    Variants.Restore(false); return false,"invalid setting value"
                end
                Fields.Write(db,field.path,value)
                record.applied, record.owner = Fields.Copy(value), entry.name
                applied = true
              end
            end
        end
    end
    return applied
end

function Variants.ContextValues(db)
    local _, location = IsInInstance()
    if not CONTEXTS[location] then location=IsInGroup() and "world" or "solo" end
    local spec=MSUF_GetPlayerSpecID()
    local dark=type(db.general)=="table" and db.general.darkMode == true
    local record=db==activeDB and journal[DARK_ID]
    if record then dark=record.base==true end
    return location, spec, dark
end
function Variants.Context(db)
    local location, spec, dark = Variants.ContextValues(db)
    return { location=location, spec=spec, dark=dark }
end
-- Which entries match right now, as a bit set (at most 16 entries). The
-- overlay is fully decided by it, so an unchanged set needs no apply.
function Variants.MatchSignature(db)
    local entries = Entries(db)
    if not entries then return 0 end
    local location, spec, dark = Variants.ContextValues(db)
    local signature, bit = 0, 1
    for i = 1, #entries do
        if MatchValues(entries[i], location, spec, dark) then signature = signature + bit end
        bit = bit * 2
    end
    return signature
end
-- Whether any entry depends on the location or the specialization: only
-- those conditions need game events.
function Variants.ConditionKinds(db)
    local location, spec = false, false
    for _, entry in ipairs(Entries(db) or NO_ENTRIES) do
        local c = type(entry) == "table" and entry.conditions
        if type(c) == "table" then
            if c.context ~= nil then location = true end
            if type(c.specs) == "table" and next(c.specs) then spec = true end
        end
    end
    return location, spec
end

-- Snapshots export the base even while the live table carries active overrides.
-- Do not add a setting to partial exports that did not include it in the first place.
function Variants.BaseSnapshot(db, include)
    if db == activeDB then CaptureEdits() end
    -- A complete trusted profile includes the schema/entry/path wrappers around
    -- already validated bounded values; their nesting is not value nesting.
    local budget={count=0,limit=131072,maxDepth=32,bytes=0,maxBytes=8388608}
    local copy, valid, problem = Fields.CopySnapshot(db,budget)
    if not valid then return nil, SNAPSHOT_PROBLEMS[problem] or "profile exceeds snapshot limits" end
    if Fields.CaptureExternal and not Fields.CaptureExternal(db,copy,budget) then return nil, "an add-on part of the profile could not be copied" end
    if db == activeDB then
        RestoreInto(copy)
    end
    if include == false then copy.profileVariants=nil end
    return copy
end

-- Reject incompatible values before replacing metadata or staging an import.
-- The base snapshot avoids comparing a new patch with a temporary live overlay.
function Variants.ValidateForProfile(db,schema)
    local clean,why=Variants.Validate(schema)
    if schema==nil or not clean then return clean,why end
    local base
    base,why=Variants.BaseSnapshot(db,true)
    if not base then return nil,why end
    for _,entry in ipairs(clean.entries) do
        for _,field in ipairs(entry.patch) do
            local parent=base
            for i=1,#field.path-1 do
                parent=type(parent)=="table" and parent[field.path[i]] or nil
                if parent~=nil and type(parent)~="table" then return nil,"setting parent is not a table" end
            end
            local value,valid=field.value,true
            if Fields.CheckExternal then value,valid=Fields.CheckExternal(field.path,value,field.remove) end
            if not valid then return nil,"invalid setting value" end
            local original=Fields.Read(base,field.path)
            if original~=nil and value~=nil and type(original)~=type(value) then return nil,"invalid setting value" end
            if not field.remove then field.value=Fields.Copy(value) end
        end
    end
    return clean
end

function Variants.HasExternalOverlay(root)
    for _,record in pairs(journal) do if record.path[1]==root then return true end end
    return false
end

-- Unit frames a saved variant switches on or off (a patch on <unit>.enabled),
-- by profile root. The Factory asks before it detaches a frame that is off:
-- such a frame stays attached and hidden, so the variant brings it back live.
-- While a variant is being recorded any unit frame may become one. Cached per
-- schema table: every save, import or Resolve installs a new one.
local switchSchema, switchRoots = nil, {}
function Variants.SwitchesUnitFrame(root)
    if Variants.IsRecording and Variants.IsRecording() then return true end
    local db = MSUF_DB
    local schema = type(db) == "table" and db.profileVariants or nil
    if type(schema) ~= "table" then return false end
    if schema ~= switchSchema then
        switchSchema = schema
        for key in pairs(switchRoots) do switchRoots[key] = nil end
        for _, entry in ipairs(type(schema.entries) == "table" and schema.entries or NO_ENTRIES) do
            local fields = type(entry) == "table" and type(entry.patch) == "table" and entry.patch or NO_ENTRIES
            for _, field in ipairs(fields) do
                local unit = type(field) == "table" and Fields.UnitSwitchRoot(field.path)
                if unit then switchRoots[unit] = true end
            end
        end
    end
    return switchRoots[root] == true
end

function Variants.SetManual(name)
    if name ~= nil and not Entry(MSUF_DB,name) then return false end
    if manual == name then manual=nil else manual=name end
    return true
end
function Variants.GetManual() return manual end
function Variants.Find(db,name) return Entry(db,name) end
function Variants.IsMaterialized(db) return activeDB == db and next(journal) ~= nil end

-- Explicit recording reuses every existing options page and Edit Mode control.
-- It is an in-memory transaction: logout/cancel restores its untouched base.
local _, MSUF = ...
local F,V=MSUF.ProfileFields,MSUF.ProfileVariants
local recording
-- msufFirst (logout): MSUF settings are restored before provider code runs,
-- so a provider error cannot leave the recording's edits as the base.
local function ReplaceContents(target,source,msufFirst)
    local function Own()
        for key in pairs(target) do target[key]=nil end
        for key,value in pairs(source) do
            if not F.IsExternal or not F.IsExternal(key) then target[key]=value end
        end
    end
    if msufFirst then Own() end
    if F.RestoreExternal then
        local ok,why=F.RestoreExternal(target,source)
        if not ok then return false,why end
    end
    if not msufFirst then Own() end
    return true
end
function V.IsRecording() return recording~=nil end
function V.RecordingName() return recording and recording.name end
function V.BeginRecording(name)
    if recording then return false,"finish editing the variant first" end
    if InCombatLockdown() then return false,"profile variants cannot be edited in combat" end
    -- Fill the profile's lazy defaults before the base is taken, so a module
    -- that completes its settings during the recording records nothing.
    if MSUF.ProfileIOEnsureCompleteProfileDB then MSUF.ProfileIOEnsureCompleteProfileDB() end
    local schema,why=V.ValidateForProfile(MSUF_DB,MSUF_DB.profileVariants)
    if not schema then return false,why end
    local entry
    for _,candidate in ipairs(schema.entries) do if candidate.name==name then entry=candidate; break end end
    if not entry then return false,"unknown profile variant" end
    local base,err=V.BaseSnapshot(MSUF_DB,true)
    if not base then return false,err end
    for _,field in ipairs(entry.patch) do
        local owner=base
        for i=1,#field.path-1 do
            owner=type(owner)=="table" and owner[field.path[i]] or nil
            if owner~=nil and type(owner)~="table" then return false,"setting parent is not a table" end
        end
    end
    local ok,why=MSUF.ProfileSync.Flush(); if not ok then return false,why end
    V.Restore()
    recording={name=name,db=MSUF_DB,base=base,entry=entry}
    for _,field in ipairs(entry.patch) do
        local value=F.Copy(field.value)
        if F.CheckExternal then value=F.CheckExternal(field.path,value,field.remove) end
        F.Write(MSUF_DB,field.path,value)
    end
    MSUF.ProfileRuntime.Apply("PROFILE_VARIANT_EDIT_BEGIN",false)
    return true
end
function V.CancelRecording(apply,msufFirst)
    if not recording then return false end
    local current=recording
    if msufFirst then recording=nil end
    local ok,why=ReplaceContents(current.db,current.base,msufFirst)
    if not ok then return false,why end
    recording=nil
    if apply~=false then MSUF.ProfileRuntime.Apply("PROFILE_VARIANT_EDIT_CANCEL",false) end
    return true
end
function V.SaveRecording()
    if not recording then return false,"no profile variant is being edited" end
    if InCombatLockdown() then return false,"profile variants cannot be edited in combat" end
    local current,why=V.BaseSnapshot(recording.db,true)
    if not current then return false,why end
    local patch,err,skipped=F.Diff(recording.base,current)
    if not patch then return false,err end
    -- A field of the entry the recording left untouched stays, even when it
    -- equals the base right now; a field set back to its base is dropped.
    local recorded={}
    for _,field in ipairs(patch) do recorded[F.ID(field.path)]=true end
    for _,field in ipairs(recording.entry.patch) do
        if not recorded[F.ID(field.path)] and F.Equal(F.Read(current,field.path),field.value) then
            patch[#patch+1]={path=F.Copy(field.path),value=F.Copy(field.value),remove=field.remove}
        end
    end
    patch,err=F.ValidatePatch(patch)
    if not patch then return false,err end
    local schema=F.Copy(recording.base.profileVariants,0,nil,{count=0,limit=131072,maxDepth=32})
    for _,entry in ipairs(schema.entries) do if entry.name==recording.name then entry.patch=patch end end
    local clean,why=V.ValidateForProfile(recording.base,schema)
    if not clean then return false,why end
    local db=recording.db
    local ok,reason=V.CancelRecording(false)
    if not ok then return false,reason end
    db.profileVariants=clean
    if skipped and skipped>0 then
        local translate=type(MSUF.Translate)=="function" and MSUF.Translate or function(text) return text end
        print("|cffffd700MSUF:|r "..string.format(translate("%d change(s) could not be stored in the variant and were left out."),skipped))
    end
    MSUF.ProfileRuntime.Apply("PROFILE_VARIANT_EDIT_SAVE",false)
    return true
end
function V.CanMutateProfile()
    if not recording then return true end
    local namespace=MSUF.MSUF2
    local message="Save or cancel the profile variant before changing profiles."
    if namespace and namespace.Tr then message=namespace.Tr(message) end
    print("|cffffd700MSUF:|r "..message)
    return false
end
function _G.MSUF_ToggleProfileVariant(slot)
    if recording then return end
    local entries=MSUF_DB and MSUF_DB.profileVariants and MSUF_DB.profileVariants.entries or {}
    for _,entry in ipairs(entries) do
        if entry.hotkey==slot and entry.enabled~=false then
            V.SetManual(entry.name)
            V.RequestApply("PROFILE_VARIANT_HOTKEY",true)
            return
        end
    end
end

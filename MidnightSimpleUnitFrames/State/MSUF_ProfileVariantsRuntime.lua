-- Context changes share the existing full-profile apply order and combat gate.
-- With no configured variants there is no context-event subscription or timer.
local _, MSUF = ...
local V = MSUF.ProfileVariants
local driver, pending, signature
-- Only the conditions the entries use subscribe; nothing is allocated per event.
local LOCATION_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE" }
local SPEC_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }
local function Subscribe(list)
    for _,event in ipairs(list) do
        if MSUF.Client.SupportsEvent(event) then driver:RegisterEvent(event) end
    end
end
local function Enabled()
    local schema=MSUF_DB and MSUF_DB.profileVariants
    return type(schema)=="table" and type(schema.entries)=="table" and #schema.entries>0
end
function V.RequestApply(reason, force)
    if V.IsRecording and V.IsRecording() then return end
    if not Enabled() and not V.IsMaterialized(MSUF_DB) then return end
    if InCombatLockdown() then
        pending=true
        V.RefreshEvents()
        return
    end
    local db=MSUF_DB
    if type(db)~="table" or (not force and signature==V.MatchSignature(db)) then return end
    MSUF.ProfileRuntime.Apply(reason or "PROFILE_VARIANT_CONTEXT",false)
end
local function Event(_,event,unit)
    if event=="PLAYER_LOGOUT" then
        -- The overlay and an unsaved recording come off the profile first,
        -- MSUF settings before any provider (Suite) code: an error in a later
        -- step must never save an overlay or a recording as the base.
        V.Restore()
        if V.CancelRecording then V.CancelRecording(false,true) end
        if MSUF.ProfileSync then MSUF.ProfileSync.Flush() end
        return
    end
    if event=="PLAYER_SPECIALIZATION_CHANGED" and unit~="player" then return end
    if event=="PLAYER_REGEN_ENABLED" then
        local wasPending=pending
        pending=nil
        V.RefreshEvents()
        if not wasPending then return end
    end
    V.RequestApply(event)
end
function V.RefreshEvents()
    local enabled=Enabled()
    if not enabled and not pending and not driver then return end
    if not driver then driver=CreateFrame("Frame"); driver:SetScript("OnEvent",Event) end
    driver:UnregisterAllEvents()
    if enabled then
        local location,spec=V.ConditionKinds(MSUF_DB)
        if location then Subscribe(LOCATION_EVENTS) end
        if spec then Subscribe(SPEC_EVENTS) end
        driver:RegisterEvent("PLAYER_LOGOUT")
    end
    if pending then driver:RegisterEvent("PLAYER_REGEN_ENABLED") end
end
function V.ResolveCurrent()
    if V.IsRecording and V.IsRecording() then return true end
    if InCombatLockdown() then pending=true; V.RefreshEvents(); return false end
    local db=MSUF_DB
    if type(db)~="table" then return false end
    V.Restore()
    local context=V.Context(db)
    local result,err=V.Resolve(db,context)
    if err then print("|cffffd700MSUF:|r "..(MSUF.Translate and MSUF.Translate(err) or err)) end
    signature=V.MatchSignature(db)
    V.RefreshEvents()
    return result,err
end
function V.Replace(db,schema)
    if type(db)~="table" then return false,"invalid profile" end
    if V.IsRecording and V.IsRecording() then return false,"finish editing the variant first" end
    if InCombatLockdown() then return false,"profile variants cannot be edited in combat" end
    local clean,err=V.ValidateForProfile(db,schema)
    if schema~=nil and not clean then return false,err end
    if db==MSUF_DB then V.Restore() end
    db.profileVariants=clean
    if db==MSUF_DB then
        signature=nil
        MSUF.ProfileRuntime.Apply("PROFILE_VARIANTS_EDIT",false)
    end
    return true
end

-- Profile synchronization is a cold-path delta transfer. Groups never subscribe
-- to gameplay events and never copy effective specialization/context overrides.
local _, MSUF = ...
local Fields, Variants, Sync = MSUF.ProfileFields, MSUF.ProfileVariants, {}
MSUF.ProfileSync = Sync
local baseline, activeName, logoutFrame
Sync.Modules = { "unitframes", "groupframes", "castbars", "colors", "auras", "resources", "gameplay" }
local modules = {}; for _,id in ipairs(Sync.Modules) do modules[id]=true end
-- Root ownership is shared with the variants (State/MSUF_ProfileFields.lua).
local roots = Fields.RootModules
-- profile.bars holds the class resource settings next to the unit frame bar
-- settings. Every key the Class Resources page writes there (and the class
-- resource colours of the Colors page) belongs to the Class Resources module;
-- a key a Unit Frames page also writes stays with Unit Frames. The list is
-- derived from the page sources by tools/tests/profile_sync_smoke.lua, which
-- fails while it is stale; `lua tools/tests/profile_sync_smoke.lua <repoRoot>
-- --write` rewrites it. Sync runs without the menu (logout, Edit Mode), so the
-- core keeps the list.
local RESOURCE_BAR_KEYS = {}
for key in ([[
altManaHeight altManaOffsetX altManaOffsetY altManaSmoothFill altManaWidth altManaWidthMode arcaneWindowColor
arcaneWindowSoulColor arcaneWindowText arcaneWindowTextFrom arcaneWindowWarnColor arcaneWindowWarnLastGCD
arcaneWindowWarnSeconds classPowerAnchorToCooldown classPowerBgAlpha classPowerBgTexture classPowerColorByType
classPowerComboPointColorMode classPowerCooldownTopAnchor classPowerEmptyAlpha classPowerFillReverse
classPowerFilledAlpha classPowerFontSize classPowerFrameLevelOffset classPowerFullColorEnabled classPowerGap
classPowerHeight classPowerHideOOC classPowerHideWhenEmpty classPowerHideWhenFull classPowerOffsetX
classPowerOffsetY classPowerOutline classPowerShape classPowerShapeAlign classPowerShowPrediction
classPowerShowText classPowerSlotColorModes classPowerSmoothFill classPowerSyncPlayerPowerOOC
classPowerTextLayer classPowerTextMode classPowerTextOffsetX classPowerTextOffsetY classPowerTexture
classPowerTickWidth classPowerWidth classPowerWidthMode guardianIronfurShowHashLines ignorePainColor
ignorePainTimeMarker manaCostColor manaGainPulse manaGainPulseColor manaRegenPause manaRegenPauseColor
manaUpcomingCost playerHPBarAnchor playerHPBarBgAlpha playerHPBarBgTexture playerHPBarColorMode
playerHPBarEnabled playerHPBarFrameLevelOffset playerHPBarGap playerHPBarHeight playerHPBarOffsetX
playerHPBarOffsetY playerHPBarOrbSize playerHPBarOutline playerHPBarShape playerHPBarSmoothFill
playerHPBarTextCenter playerHPBarTextCenterHidePercentSymbol playerHPBarTextEnabled playerHPBarTextLeft
playerHPBarTextLeftHidePercentSymbol playerHPBarTextOffsetX playerHPBarTextOffsetY playerHPBarTextReverse
playerHPBarTextRight playerHPBarTextRightHidePercentSymbol playerHPBarTextSeparator playerHPBarTextSize
playerHPBarTexture playerHPBarUsePlayerText playerHPBarWidth playerHPBarWidthMode resourceExtraHeight
resourceExtraOffsetX resourceExtraOffsetY resourceExtraWidth resourceMarks runeShowTime showAltMana
showArcaneWindow showChargedComboPoints showClassPower showEbonMight showEleMaelstrom showGuardianIronfur
showIgnorePain showShadowMana showSweepingStrikes
]]):gmatch("%S+") do RESOURCE_BAR_KEYS[key] = true end
local function BarsOwner(key)
    if RESOURCE_BAR_KEYS[key] == true then return "resources" end
    return roots.bars
end
function Sync.Owner(path)
    if Fields.ExternalOwner then local owner=Fields.ExternalOwner(path); if owner then return owner end end
    if path[1]=="bars" then return BarsOwner(path[2]) end
    if path[1]~="general" then return roots[path[1]] end
    local key=path[2]
    if type(key)~="string" or key:match("^_") then return end
    -- Menu/account integration preferences are local to each profile. The general
    -- key owner registry (State/MSUF_ProfileFields.lua) decides after the more
    -- specific runtime owners.
    local lower=key:lower()
    if lower:find("classpower",1,true) or lower:find("resource",1,true) then return "resources" end
    if lower:find("aura",1,true) then return "auras" end
    return Fields.GeneralSyncOwner(key)
end
local function Report(message,detail)
    local translate=type(MSUF.Translate)=="function" and MSUF.Translate or function(text) return text end
    message=translate(message)
    if detail~=nil then message=string.format(message,translate(tostring(detail))) end
    print("|cffffd700MSUF:|r "..message)
end
-- Saved groups are repaired, never trusted and never allowed to block a
-- profile operation: an invalid group, member, module or exclusion is dropped,
-- a profile that no longer exists leaves its groups, and a profile module that
-- two groups claim stays with the first. S.Validate stays strict for edits.
local repairReported
local function Sanitize(groups)
    if type(groups)~="table" or getmetatable(groups) then return {},true end
    local profiles=MSUF_GlobalDB and MSUF_GlobalDB.profiles
    local clean,names,ownership,changed={},{},{},false
    for key in pairs(groups) do
        if type(key)~="number" or key<1 or key>#groups or key~=math.floor(key) then changed=true end
    end
    for _,group in ipairs(groups) do
        local name=type(group)=="table" and group.name
        if #clean>=16 or type(name)~="string" or #name<1 or #name>64 or name:find("[%c]") or names[name]
            or type(group.members)~="table" or type(group.modules)~="table" or getmetatable(group) then
            changed=true
        else
            names[name]=true
            local out,count={name=name,members={},modules={},exclude={}},0
            for module,on in pairs(group.modules) do
                if on==true and (modules[module] or (type(module)=="string" and module:match("^suite:[%w_]+$"))) then
                    out.modules[module]=true
                else changed=true end
            end
            for member,on in pairs(group.members) do
                local keep=on==true and type(member)=="string" and #member>=1 and #member<=128 and count<64
                    and (type(profiles)~="table" or type(profiles[member])=="table")
                for module in pairs(out.modules) do
                    if keep and ownership[member] and ownership[member][module] then keep=false end
                end
                if keep then
                    count=count+1
                    out.members[member]=true
                    ownership[member]=ownership[member] or {}
                    for module in pairs(out.modules) do ownership[member][module]=true end
                else changed=true end
            end
            local exclusions=group.exclude
            if type(exclusions)=="table" then
                for key in pairs(exclusions) do
                    if type(key)~="number" or key<1 or key>#exclusions or key~=math.floor(key) then changed=true end
                end
                for _,path in ipairs(exclusions) do
                    if #out.exclude<512 and Fields.Path(path) then out.exclude[#out.exclude+1]=Fields.Copy(path) else changed=true end
                end
            elseif exclusions~=nil then changed=true end
            clean[#clean+1]=out
        end
    end
    return clean,changed
end
-- The repaired list replaces the saved one, so callers that edit members
-- (rename/delete) edit the stored table.
local function Groups()
    local global=MSUF_GlobalDB and MSUF_GlobalDB.global
    if type(global)~="table" or global.profileSyncGroups==nil then return {} end
    local clean,changed=Sanitize(global.profileSyncGroups)
    if not changed then return global.profileSyncGroups end
    global.profileSyncGroups=clean
    if not repairReported then
        repairReported=true
        Report("Saved profile sync groups had invalid entries; those entries were removed.")
    end
    return clean
end
function Sync.Validate(groups)
    if type(groups)~="table" or getmetatable(groups) or #groups>16 then return nil,"invalid sync groups" end
    local clean, names, ownership = {}, {}, {}
    for i,group in ipairs(groups) do
        if type(group)~="table" or type(group.name)~="string" or #group.name<1 or #group.name>64
            or group.name:find("[%c]") or names[group.name] then return nil,"invalid sync group name" end
        names[group.name]=true
        local out={name=group.name,members={},modules={},exclude={}}
        if type(group.members)~="table" or type(group.modules)~="table" then return nil,"invalid sync members" end
        local count=0
        for name,on in pairs(group.members) do
            if type(name)~="string" or #name<1 or #name>128 or on~=true then return nil,"invalid sync member" end
            count=count+1; if count>64 then return nil,"too many sync members" end
            out.members[name]=true
        end
        for module,on in pairs(group.modules) do
            if (not modules[module] and not (type(module)=="string" and module:match("^suite:[%w_]+$"))) or on~=true then return nil,"invalid sync module" end
            out.modules[module]=true
            for name in pairs(out.members) do
                ownership[name]=ownership[name] or {}
                if ownership[name][module] then return nil,"profile module belongs to another sync group" end
                ownership[name][module]=true
            end
        end
        local exclusions=group.exclude or {}
        if type(exclusions)~="table" or #exclusions>512 then return nil,"too many sync exclusions" end
        for index,path in ipairs(exclusions) do
            if not Fields.Path(path) then return nil,"invalid sync exclusion" end
            out.exclude[index]=Fields.Copy(path)
        end
        for index in pairs(exclusions) do
            if type(index)~="number" or index<1 or index>#out.exclude or index~=math.floor(index) then return nil,"invalid sync exclusions" end
        end
        clean[i]=out
    end
    for i in pairs(groups) do
        if type(i)~="number" or i<1 or i>#clean or i~=math.floor(i) then return nil,"invalid sync groups" end
    end
    return clean
end
local function Excluded(path,group,source,target)
    for _,excluded in ipairs(group.exclude) do if Fields.Overlaps(path,excluded) then return true end end
    for _,db in ipairs({source,target}) do
        local entries=db.profileVariants and db.profileVariants.entries or {}
        for _,entry in ipairs(entries) do
            for _,field in ipairs(entry.patch or {}) do if Fields.Overlaps(path,field.path) then return true end end
        end
    end
    return false
end
-- Walk leaves even when a whole source table was inserted/deleted. Copying that
-- parent wholesale would bypass excluded descendants in the receiving profile.
-- Every changed leaf is an edit, a first value for an unset (nil) key included:
-- late default fills are absorbed into the baseline (see FillLazyDefaults).
local function Changes(before,after)
    local out,path,count={}, {},0
    local function Visit(a,b,depth)
        count=count+1
        if count>65536 or depth>12 then return false end
        if a==b then return true end
        if (type(a)=="table" or a==nil) and (type(b)=="table" or b==nil)
            and (type(a)=="table" or type(b)=="table") then
            local keys={}
            for key in pairs(a or {}) do keys[key]=true end
            for key in pairs(b or {}) do keys[key]=true end
            for key in pairs(keys) do
                path[depth+1]=key
                if not (type(key)=="string" and key:match("^_")) then
                    if not Visit(a and a[key],b and b[key],depth+1) then return false end
                end
                path[depth+1]=nil
            end
        elseif Fields.Path(path) and not Fields.Equal(a,b) then
            local value,valid=Fields.Copy(b)
            if not valid then return false end
            out[#out+1]={path=Fields.Copy(path),value=value,remove=b==nil}
        end
        return true
    end
    for root in pairs(roots) do
        path[1]=root
        if not Visit(before[root],after[root],1) then return nil,"sync exceeds field limits" end
    end
    for root in pairs(Fields.ExternalRoots and Fields.ExternalRoots() or {}) do
        path[1]=root
        if not Visit(before[root],after[root],1) then return nil,"sync exceeds field limits" end
    end
    path[1]="general"
    if not Visit(before.general,after.general,1) then return nil,"sync exceeds field limits" end
    return out
end
-- The defaults, gameplay, group-frame and aura ensures add missing keys the
-- first time a module reads its settings (review F9). They run on the active
-- profile before its baseline is taken, so such a fill never reaches the
-- members as an edit and a member's own value survives it.
local function FillLazyDefaults()
    if type(MSUF_DB)~="table" then return end
    if MSUF.MSUF_EnsureDB then MSUF.MSUF_EnsureDB() end
    if MSUF.MSUF_EnsureGameplayDefaults then MSUF.MSUF_EnsureGameplayDefaults() end
    if MSUF.GF and MSUF.GF.EnsureDB then MSUF.GF.EnsureDB() end
    if MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.EnsureDB then MSUF.MSUF_Auras3.EnsureDB() end
end
function Sync.Activate(force)
    local name=MSUF_ActiveProfile
    if force or name~=activeName or not baseline then
        activeName=name
        local enabled=next(Groups())~=nil
        if enabled then FillLazyDefaults() end
        baseline=enabled and Variants.BaseSnapshot(MSUF_DB,true) or nil
    end
end
-- A reset or import replaces the active profile on purpose; it stays in that
-- profile. Re-basing makes only the edits after it reach the other members.
function Sync.Rebase() Sync.Activate(true) end
function Sync.Flush(full)
    if Variants.IsRecording and Variants.IsRecording() then return false,"finish editing the variant first" end
    local groups=Groups()
    if #groups==0 then baseline=nil; return true end
    local source,why=Variants.BaseSnapshot(MSUF_DB,true)
    if not source then return false,why end
    local before=full and {} or (activeName==MSUF_ActiveProfile and baseline or nil)
    if not before then baseline,activeName=source,MSUF_ActiveProfile; return true end
    local changes,errorText=Changes(before,source)
    if not changes then return false,errorText end
    local profiles=MSUF_GlobalDB.profiles
    for _,group in ipairs(groups) do
        if group.members[MSUF_ActiveProfile] then
            for name in pairs(group.members) do
                local target=profiles[name]
                if name~=MSUF_ActiveProfile and type(target)=="table" then
                    for _,field in ipairs(changes) do
                        if group.modules[Sync.Owner(field.path)] and not Excluded(field.path,group,source,target) then
                            Fields.Write(target,field.path,Fields.Copy(field.value))
                        end
                    end
                end
            end
        end
    end
    baseline,activeName=source,MSUF_ActiveProfile
    return true
end
function Sync.RegisterModule(id,label)
    if modules[id] then return end
    modules[id]=true
    Sync.Modules[#Sync.Modules+1]=id
    Sync.Labels=Sync.Labels or {}; Sync.Labels[id]=label
end
function Sync.RebaseExternal(root)
    if baseline and baseline[root]==nil and activeName==MSUF_ActiveProfile then
        local snapshot=Variants.BaseSnapshot(MSUF_DB,true)
        if snapshot then baseline[root]=snapshot[root] end
    end
end
function Sync.RefreshEvents()
    local enabled=next(Groups())~=nil
    if not enabled and not logoutFrame then return end
    if not logoutFrame then
        logoutFrame=CreateFrame("Frame")
        logoutFrame:SetScript("OnEvent",function() Sync.Flush() end)
    end
    logoutFrame:UnregisterAllEvents()
    if enabled then logoutFrame:RegisterEvent("PLAYER_LOGOUT") end
end
function Sync.Replace(groups)
    if InCombatLockdown() then return false,"sync groups cannot be edited in combat" end
    if Variants.IsRecording and Variants.IsRecording() then return false,"finish editing the variant first" end
    local clean,err=Sync.Validate(groups)
    if not clean then return false,err end
    -- Pending edits reach the members of the saved (repaired) groups first; a
    -- flush that cannot run is reported and never locks the editor.
    local ok,why=Sync.Flush()
    if not ok then Report("Profile sync skipped (%s).",why) end
    MSUF_GlobalDB.global=MSUF_GlobalDB.global or {}
    MSUF_GlobalDB.global.profileSyncGroups=clean
    baseline,activeName=nil,nil
    Sync.Activate(); Sync.RefreshEvents()
    return true
end
Sync.Report=Report
function Sync.RenameOrDelete(name,replacement)
    for _,group in ipairs(Groups()) do
        if group.members[name] then group.members[name]=nil; if replacement then group.members[replacement]=true end end
    end
    if activeName==name and replacement then activeName=replacement end
end
function Sync.GetGroups() return Fields.Copy(Groups(),0,nil,{count=0,limit=16384,maxDepth=16}) end

-- Optional addons keep ownership of their own profile stores. Synthetic roots
-- exist only in snapshots; no aliases/duplicate settings enter MSUF saved data.
local _,MSUF=...
local F=MSUF.ProfileFields
local providers={}
local roots={suiteModules=true}
local names=setmetatable({},{__mode="k"})
function F.ProfileName(db)
    if db==MSUF_DB then return MSUF_ActiveProfile end
    local profiles=MSUF_GlobalDB and MSUF_GlobalDB.profiles
    if type(profiles)~="table" then return end
    local name=names[db]
    if name and profiles[name]==db then return name end
    for key,profile in pairs(profiles) do
        if profile==db then names[db]=key; return key end
    end
end
function F.IsExternal(root) return roots[root]==true end
function F.RegisterExternal(root,provider)
    assert(roots[root] and type(provider)=="table" and type(provider.Resolve)=="function","invalid profile provider")
    providers[root]=provider
end
function F.ProfileRoot(db,root,create)
    if not roots[root] or not F.ProfileName(db) then
        if create and type(db[root])~="table" then db[root]={} end
        return db[root]
    end
    local provider=providers[root]
    if provider then return provider.Resolve(F.ProfileName(db),create==true) end
end
function F.ExternalAvailable(db,path)
    if not roots[path[1]] then return true end
    local provider=providers[path[1]]
    return provider~=nil and (not provider.Allows or provider.Allows(path))
        and F.ProfileRoot(db,path[1],true)~=nil
end
function F.ExternalOwner(path)
    local provider=providers[path[1]]
    if provider and provider.Owner then return provider.Owner(path) end
end
function F.ExternalRoots() return roots end
function F.CaptureExternal(db,copy,budget)
    if not F.ProfileName(db) then return true end
    for root in pairs(providers) do
        local source=F.ProfileRoot(db,root,true)
        if source then
            local provider=providers[root]
            if provider.Snapshot then
                local valid
                source,valid=provider.Snapshot(source)
                if valid==false then return false end
            end
            local value,ok=F.CopySnapshot(source,budget)
            if not ok then return false end
            copy[root]=value
        end
    end
    return true
end
function F.StripExternal(copy)
    for root in pairs(roots) do copy[root]=nil end
    return copy
end
function F.RestoreExternal(db,snapshot)
    for root,provider in pairs(providers) do
        if snapshot[root]~=nil then
            local target=F.ProfileRoot(db,root,true)
            if target then
                local copy,valid=F.CopySnapshot(snapshot[root])
                if not valid then return false,"profile exceeds snapshot limits" end
                if provider.Restore then
                    local ok,why=provider.Restore(target,copy)
                    if ok==false then return false,why or "invalid setting value" end
                else
                for key in pairs(target) do target[key]=nil end
                for key,value in pairs(copy) do target[key]=value end
                end
            else return false,"invalid profile" end
        end
    end
    return true
end
function F.CheckExternal(path,value,remove)
    local provider=providers[path[1]]
    if provider and provider.Check then return provider.Check(path,value,remove) end
    return value,true
end
function F.ApplyExternal(reason)
    for _,provider in pairs(providers) do if provider.Apply then provider.Apply(reason) end end
end
function F.ExternalSnapshot(db,root)
    local snapshot,why=MSUF.ProfileVariants.BaseSnapshot(db,true)
    if not snapshot then return nil,why end
    return snapshot[root]
end

--- Bridge the private Options-addon namespace to the canonical MSUF namespace.
--- WoW gives every addon its own `...` table; Menu2 historically received the
--- main addon's table and must keep that exact read/write behavior after the
--- physical LoadOnDemand split.

local addonName, private = ...
local main = _G.MSUF
if type(main) ~= "table" or type(private) ~= "table" then return end

main.OptionsAddonName = addonName

if private ~= main then
    setmetatable(private, {
        __index = main,
        __newindex = function(_, key, value)
            main[key] = value
        end,
    })
end

local menu = main.MSUF2 or main.Optional("MSUF2") or {}
main.MSUF2 = menu
main.ExportPublic("MSUF2", menu)

function menu.SupportsFrameScope(scope)
    local client = main.Client
    if not client then return true end
    local group = type(scope) == "string" and (scope:match("^gf_(.+)$") or scope)
    if group == "party" or group == "raid" or group == "mythicraid" then
        return not client.SupportsGroupKind or client.SupportsGroupKind(group)
    end
    return not client.SupportsUnit or client.SupportsUnit(scope)
end

local COOLDOWN_ANCHORS = { EssentialCooldownViewer = true, UtilityCooldownViewer = true, BuffIconCooldownViewer = true }
function menu.SupportsAnchorTarget(target)
    if COOLDOWN_ANCHORS[target] then return main.Client.HostsCooldownManager == true end
    return menu.SupportsFrameScope(target)
end

-- Build this cold dropdown list on demand. Imported unavailable targets remain
-- visible and read-only so merely opening a portable profile never rewrites it.
function menu.AnchorTargetValues(items, selected, excluded)
    local values = {}
    for i = 1, #items do
        local item = items[i]
        if item.value ~= excluded then
            if menu.SupportsAnchorTarget(item.value) then
                values[#values + 1] = item
            elseif item.value == selected then
                values[#values + 1] = { value = item.value, disabled = true,
                    text = menu.Format("%s (unavailable on this client)", menu.Tr(item.text)), translate = false }
            end
        end
    end
    return values
end

function menu.NormalizeGroupScope(scope)
    return menu.SupportsFrameScope(scope) and scope or "raid"
end

function menu.SupportsUnitPage(pageKey, settingKey)
    local unit = type(pageKey) == "string" and pageKey:match("^uf_(.+)$")
    if settingKey == "general.bossTargetOutlineMode" then unit = "boss" end
    -- Focus Kick tracks the focus unit, so its settings follow the focus scope.
    if settingKey == "general.enableFocusKickIcon"
        or (type(settingKey) == "string" and settingKey:find("^general%.focusKick")) then
        unit = "focus"
    end
    local settingScope = type(settingKey) == "string" and settingKey:match("^([^%.]+)%.")
    if settingScope and not menu.SupportsFrameScope(settingScope) then return false end
    return not unit or menu.SupportsFrameScope(unit)
end

function menu.SupportsSearchTarget(pageKey, settingKey, prepareKind, prepareValue)
    if not menu.SupportsUnitPage(pageKey, settingKey) then return false end
    if settingKey == "pettarget.useBlizzardFrame" then return false end
    local targetScope = type(settingKey) == "string" and settingKey:match("^gf_(%w+)%.targets")
    if targetScope and targetScope ~= "party" then return false end
    if settingKey == "general.kickReadyShowNameplates"
        and not (menu.CastbarSuiteNameplatesSupported and menu.CastbarSuiteNameplatesSupported()) then return false end
    if prepareKind == "unitStatusIndicator" then
        local unit = pageKey:match("^uf_(.+)$")
        local spec = unit and menu.UnitPage.FindStatusSpec(unit, prepareValue)
        return spec ~= nil and spec.value == prepareValue
    end
    local scope
    if prepareKind == "groupStatus" then
        local value
        scope, value = tostring(prepareValue):match("^(%a+)_(%w+)$")
        if pageKey ~= "gf_indicators" or not scope or not main.Client.SupportsGroupKind(scope) then return false end
        local recognizedScope = false
        for _, candidate in ipairs(menu.GroupPage.SCOPE_VALUES) do
            if candidate.value == scope then recognizedScope = true break end
        end
        if not recognizedScope then return false end
        for _, spec in ipairs(menu.GroupPage.GF_STATUS_ICON_SPECS) do
            if spec.value == value then return true end
        end
        return false
    elseif prepareKind == "groupScope" then scope = prepareValue
    elseif prepareKind == "groupAuraWorkspace" then
        scope = type(prepareValue) == "string" and prepareValue:match("^(%w+)_")
    end
    return not scope or menu.SupportsFrameScope(scope)
end

function menu.FilterSupportedUnitValues(values)
    local client = main.Client
    if client and client.SupportsUnit then
        for i = #values, 1, -1 do
            if not menu.SupportsFrameScope(values[i].value or values[i].key) then table.remove(values, i) end
        end
    end
    return values
end

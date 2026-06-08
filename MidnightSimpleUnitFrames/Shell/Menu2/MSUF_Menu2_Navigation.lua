--- Menu2 navigation data and slash/page aliases.
---
--- This module is intentionally data-only. The window shell consumes
--- `M.navItems` and `M.ALIASES`; search indexing also reads `M.navItems`.
--- Keeping it separate makes page/navigation changes visible without digging
--- through frame construction code.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local function NavRows(rows)
    local nav = {}
    for line in tostring(rows or ""):gmatch("[^\r\n]+") do
        local cols, n = {}, 0
        for col in (line .. "|"):gmatch("(.-)|") do n = n + 1; cols[n] = col end
        if cols[1] == "H" then
            nav[#nav + 1] = { header = cols[2], id = cols[3], defaultOpen = cols[4] ~= "0" }
        elseif cols[1] == "P" then
            local item = { key = cols[2], label = cols[3] }
            if cols[4] and cols[4] ~= "" then item.group = cols[4] end
            nav[#nav + 1] = item
        end
    end
    return nav
end

M.navItems = NavRows [[
P|home|Dashboard
H|Frames|unitframes|1
P|uf_player|Player|unitframes
P|uf_target|Target|unitframes
P|uf_boss|Boss Frames|unitframes
P|uf_focus|Focus|unitframes
P|uf_pet|Pet|unitframes
P|uf_targettarget|Target of Target|unitframes
P|uf_focustarget|Focus Target|unitframes
H|Group Frames|groupframes|1
P|gf_layout|Layout|groupframes
P|gf_bars|Health & Text|groupframes
P|gf_indicators|Indicators|groupframes
P|gf_auras|Auras|groupframes
H|Auras|auras|1
P|auras3_styling|Style|auras
P|auras3_filters|Filters|auras
H|Appearance|globalstyle|1
P|opt_bars|Bars|globalstyle
P|opt_castbar|Castbars|globalstyle
P|opt_colors|Colors|globalstyle
P|opt_fonts|Fonts|globalstyle
P|opt_misc|Miscellaneous|globalstyle
P|classpower|Class Resources
P|gameplay|Gameplay
P|profiles|Profiles
H|Advanced|modules|0
P|modules|Modules|modules
]]

local function AliasRows(rows)
    local aliases = {}
    for line in tostring(rows or ""):gmatch("[^\r\n]+") do
        local target, keys = line:match("^([^=]+)=(.+)$")
        if target and keys then
            for key in keys:gmatch("[^|]+") do
                aliases[key == "<empty>" and "" or key] = target
            end
        end
    end
    return aliases
end

M.ALIASES = AliasRows [[
home=<empty>|home|menu|main|options|opt
uf_player=player
uf_target=target
uf_targettarget=tot|targettarget
uf_focustarget=focustarget|focus_target|focustargettarget|ft
uf_focus=focus
uf_boss=boss
uf_pet=pet
opt_bars=bars
opt_fonts=fonts
auras3=aura|auras|auras3|aura_rendering|aurarendering|aura_renderer|aurarenderer
auras3_styling=aura_style|aurastyle|aura_styling|aurastyling|buff|buffs|aura_buffs|aurabuffs|debuff|debuffs|aura_debuffs|auradebuffs
auras3_filters=aura_filters|aurafilters|aura_filter|blacklist|aura_blacklist|aurablacklist
opt_castbar=castbar
opt_colors=colors|colours
opt_misc=misc
classpower=classpower|class
gameplay=gameplay
profiles=profiles
gf_layout=layout|group|groupframes
gf_bars=health
modules=modules
search=search
]]

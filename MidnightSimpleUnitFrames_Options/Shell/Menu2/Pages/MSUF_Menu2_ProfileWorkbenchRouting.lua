local _, MSUF = ...
local M, W = MSUF.MSUF2, MSUF.ProfileWorkbench
local PREFIX = "menu2.profile.tools.profiles."
local OWNERS = {
    version = { "profiles", "workbench_versions" }, review = { "profiles", "workbench_review" },
    inspector = { "profiles", "workbench_inspector" }, display = { "profiles", "workbench_display" },
    accessibility = { "opt_colors", "workbench_accessibility" },
    multi = { "edit_selection", "workbench_alignment" },
}
local function Resolve(page, exact)
    if page ~= "profile_tools" then return end
    if not exact then return "profiles" end
    local id = tostring(exact.controlId or "")
    if id:sub(1, #PREFIX) ~= PREFIX then return "profiles", exact end
    local key = id:sub(#PREFIX + 1)
    local group = key:match("^([^.]+)")
    if group == "visibility" then
        local row = W.Visibility()[tonumber(key:match("%.(%d+)$")) or 0]
        if not row then return false end
        return row.page, row.target
    end
    local owner = OWNERS[group]
    if not owner then return false end
    local target = {}
    for field, value in pairs(exact) do target[field] = value end
    target.pageKey, target.sectionId = owner[1], owner[2]
    if key == "review.input" then
        target.controlId, target.sectionId = "menu2.profiles.advanced.import.export.buffer", "profiles_io"
    elseif key == "review.prepare" then
        target.controlId, target.sectionId = "menu2.profiles.advanced.import.review", "profiles_io"
    elseif group == "review" and not M.ProfileWorkbenchUI.HasReview() then
        target.controlId, target.sectionId = "menu2.profiles.advanced.import.review", "profiles_io"
    end
    return owner[1], target
end
M.RegisterSearchTargetResolver("profile-tools", Resolve)

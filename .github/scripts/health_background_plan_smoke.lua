-- Exercise the prepared-color route through its actual cold owner, while the
-- shared fixture also retains coverage of the public live-spec resolver.
local saved=arg
arg={saved[1] or ".",saved[2],"compiled"}
assert(loadfile(arg[1].."/.github/scripts/health_background_sample_parity_smoke.lua"))()
arg=saved

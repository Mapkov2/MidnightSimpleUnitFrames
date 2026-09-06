-- Run an unchanged legacy harness against XML-defined Auras3 module groups.
local script = assert(arg and arg[1], "usage: lua auras3_test_driver.lua test.lua [test args]")
local shifted = { [0] = script }
for i = 2, #arg do shifted[i - 1] = arg[i] end
local loader = assert(loadfile(".github/scripts/auras3_test_loader.lua"))()
loader.SetSourceRoot(os.getenv("MSUF_AURAS3_TEST_SOURCE_ROOT"))
_G.MSUF_Auras3TestLoader = loader
loader.Install()
arg = shifted
assert(loadfile(script))()

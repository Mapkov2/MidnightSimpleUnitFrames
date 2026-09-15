-- Run an unchanged legacy harness against XML-defined Auras3 module groups.
local script = assert(arg and arg[1], "usage: lua auras3_test_driver.lua test.lua [test args]")
local shifted = { [0] = script }
for i = 2, #arg do shifted[i - 1] = arg[i] end
local loaderPath = ".github/scripts/auras3_test_loader.lua"
local loaderProbe = io.open(loaderPath, "rb")
if not loaderProbe then
    error("auras3_test_driver.lua must run with the repository root as the working directory: the loader and the smokes read repository-relative paths", 0)
end
loaderProbe:close()
local loader = assert(loadfile(loaderPath))()
loader.SetSourceRoot(os.getenv("MSUF_AURAS3_TEST_SOURCE_ROOT"))
_G.MSUF_Auras3TestLoader = loader
loader.Install()
arg = shifted
assert(loadfile(script))()

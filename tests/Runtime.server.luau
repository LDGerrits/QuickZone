local ServerScriptService = game:GetService("ServerScriptService")

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest
local SpecificationsFolder = TestFolder.Specifications

local Tiniest = require(TiniestFolder.tiniest_for_roblox).configure({})

local Tests = Tiniest.collect_tests_from_hierarchy(SpecificationsFolder)
local Results = Tiniest.run_tests(Tests, {})

local PassCount = Results.status_tally.pass
local FailCount = Results.status_tally.fail

if FailCount > 0 then
	warn(`[QuickZone Tests]: {FailCount}/{PassCount + FailCount} test(s) failed!`)
end
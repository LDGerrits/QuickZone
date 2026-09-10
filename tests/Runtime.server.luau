--!strict
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest
local SpecificationsFolder = TestFolder.Specifications

local Tiniest = require(TiniestFolder.tiniest_for_roblox).configure({})

local tests = Tiniest.collect_tests_from_hierarchy(SpecificationsFolder)
local results = Tiniest.run_tests(tests, {})

local passCount = results.status_tally.pass
local failCount = results.status_tally.fail

if failCount > 0 then
	warn(`[QuickZone Tests]: {failCount}/{passCount + failCount} test(s) failed!`)
end

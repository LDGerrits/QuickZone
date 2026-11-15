--!strict
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest
local SpecificationsFolder = TestFolder.Specifications

local Tiniest = require(TiniestFolder.tiniest_for_roblox).configure({})
local Invariants = require(TestFolder.Invariants)

local tests = Tiniest.collect_tests_from_hierarchy(SpecificationsFolder)

-- Every test also leaves QuickZone's internal tables consistent
for _, test in tests do
	local run = test.run
	test.run = function()
		run()
		local problems = Invariants.check()
		if problems then
			error(`Internal state is inconsistent after the test: {problems}`, 0)
		end
	end
end
local results = Tiniest.run_tests(tests, {})

local passCount = results.status_tally.pass
local failCount = results.status_tally.fail

if failCount > 0 then
	warn(`[QuickZone Tests]: {failCount}/{passCount + failCount} test(s) failed!`)
end

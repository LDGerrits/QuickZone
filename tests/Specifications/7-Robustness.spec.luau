--!strict
-- Misuse and odd timing that a game hits sooner or later: callbacks that destroy what fired them, zones that go
-- away together, values of the wrong type, iterators whose tables change under them, entities that are also
-- references, players whose parts are swapped, and a check of every shape against the engine's own geometry
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest

local Util = require(TestFolder.Util)

local QuickZone = require(ReplicatedStorage.QuickZone)
local Zone = QuickZone.Zone
local Group = QuickZone.Group
local Observer = QuickZone.Observer

type Tiniest = typeof(require(TiniestFolder.tiniest_for_roblox).configure({}))

local AWAY = Vector3.new(0, 5000, 0)

-- Calls fn, then destroys whatever it registered, so a failing expectation leaves nothing behind. Every entity
-- is checked in each update
local function withCleanup(fn: (track: (any) -> any) -> ())
	local tracked = {}
	local function track(object: any): any
		table.insert(tracked, object)
		return object
	end

	QuickZone:setFrameBudget(1000)
	local ok, err = pcall(fn, track)
	QuickZone:setFrameBudget(1)
	for i = #tracked, 1, -1 do
		local object = tracked[i]
		if typeof(object) == 'Instance' then
			object:Destroy()
		elseif type(object) == 'table' and not object.destroyed and type(object.destroy) == 'function' then
			pcall(object.destroy, object)
		end
	end
	if not ok then
		error(err, 0)
	end
end

local function cube(position: Vector3, size: number?): { cframe: CFrame, size: Vector3 }
	return { cframe = CFrame.new(position), size = Vector3.one * (size or 10) }
end

-- Whether pcall(fn, ...) failed with a message containing text
local function refuses(text: string, fn: (...any) -> ...any, ...: any): boolean
	local ok, err = pcall(fn, ...)
	return not ok and string.find(tostring(err), text, 1, true) ~= nil
end

return function(Tiniest: Tiniest)
	local Describe = Tiniest.describe
	local Test = Tiniest.test
	local Expect = Tiniest.expect

	Describe('Callbacks that change what fired them', function()
		Test(
			'An observer destroyed by an exit callback still tells every other exit callback, and its group cleanups run.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-41000, 0, 41000)
					local entity = { Position = position }
					local zone = track(Zone.new(cube(position)))
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
					local events = {}
					observer:onExit(function()
						table.insert(events, 'destroy')
						observer:destroy()
					end)
					observer:onExit(function()
						table.insert(events, 'exit')
					end)
					observer:observe(function()
						return function()
							table.insert(events, 'observe cleanup')
						end
					end)
					observer:observeGroup(function()
						return function()
							table.insert(events, 'group cleanup')
						end
					end)
					observer:onGroupExit(function()
						table.insert(events, 'group exit')
					end)

					QuickZone:update(1)
					entity.Position = position + AWAY
					QuickZone:update(1)

					-- The observe cleanup runs as the observer is destroyed, the rest hear the exit after
					Expect(table.concat(events, ', ')).is('destroy, observe cleanup, exit, group cleanup, group exit')
				end)
			end
		)

		Test(
			'A zone destroyed by an enter callback hands the entry on to an overlapping zone, where later callbacks see it.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-41100, 0, 41000)
					local entity = { Position = position + AWAY }
					local zoneA = track(Zone.new(cube(position)))
					local zoneB = track(Zone.new(cube(position)))
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local observer =
						track(Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false }))
					QuickZone:update(1)

					local destroyed = nil
					local function name(zone: any): string
						return if zone == destroyed then 'destroyed' else 'other'
					end
					local events = {}
					observer:onEnter(function(_, zone)
						if not destroyed then
							destroyed = zone
							table.insert(events, 'destroy')
							zone:destroy()
						end
					end)
					observer:onTransition(function(_, zone)
						table.insert(events, `transition {name(zone)}`)
					end)
					observer:onEnter(function(_, zone)
						table.insert(events, `enter {name(zone)}`)
					end)
					observer:observe(function(_, zone)
						table.insert(events, `observe {name(zone)}`)
						return function()
							table.insert(events, 'cleanup')
						end
					end)

					entity.Position = position
					QuickZone:update(1)
					QuickZone:update(1)
					entity.Position = position + AWAY
					QuickZone:update(1)

					Expect(table.concat(events, ', ')).is(
						'destroy, transition other, enter other, observe other, cleanup'
					)
				end)
			end
		)

		Test('Callbacks connected while an event fires get the next event, not that one.', function()
			withCleanup(function(track)
				local position = Vector3.new(-41200, 0, 41000)
				local entity = { Position = position }
				local zone = track(Zone.new(cube(position)))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				local events = {}
				local connected = false
				observer:onEnter(function()
					table.insert(events, 'first')
					if not connected then
						connected = true
						observer:onEnter(function()
							table.insert(events, 'late')
						end)
					end
				end)
				observer:onEnter(function()
					table.insert(events, 'second')
				end)

				QuickZone:update(1)
				entity.Position = position + AWAY
				QuickZone:update(1)
				entity.Position = position
				QuickZone:update(1)

				Expect(table.concat(events, ', ')).is('first, second, first, second, late')
			end)
		end)

		Test('Connecting tens of thousands of callbacks stays fast, and each fires once.', function()
			withCleanup(function(track)
				local position = Vector3.new(-41300, 0, 41000)
				local entity = { Position = position + AWAY }
				local zone = track(Zone.new(cube(position)))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)

				local count = 0
				local function onEnter()
					count += 1
				end
				local disconnects = {}
				local start = os.clock()
				for i = 1, 50000 do
					disconnects[i] = observer:onEnter(onEnter)
				end
				local elapsed = os.clock() - start

				entity.Position = position
				QuickZone:update(1)
				local first = count

				-- Some disconnected, the others still fire
				for i = 1, 10 do
					disconnects[i]()
				end
				entity.Position = position + AWAY
				QuickZone:update(1)
				entity.Position = position
				QuickZone:update(1)

				Expect(if elapsed < 0.5 then 'fast' else string.format('%.2f s', elapsed)).is('fast')
				Expect(first).is(50000)
				Expect(count - first).is(49990)
			end)
		end)

		Test('An unsafe callback that yields holds updates back with one warning, and they resume after it.', function()
			withCleanup(function(track)
				local position = Vector3.new(-41400, 0, 41000)
				local entity = { Position = position }
				local zone = track(Zone.new(cube(position)))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				local resumed = false
				observer:onEnter(function()
					task.wait(0.1)
					resumed = true
				end)
				local exits = 0
				observer:onExit(function()
					exits += 1
				end)

				QuickZone:setEnabled(false)
				local ok, err = pcall(function()
					task.spawn(QuickZone.update, QuickZone, 1)
					local warnings = Util.captureWarnings(function()
						QuickZone:update(1)
						QuickZone:update(1)
					end)
					local waited = 0
					while not resumed and waited < 2 do
						waited += task.wait()
					end
					entity.Position = position + AWAY
					QuickZone:update(1)

					Expect(#warnings).is(1)
					Expect(string.find(warnings[1], 'yielded', 1, true) ~= nil).is_true()
					Expect(resumed).is_true()
					Expect(exits).is(1)
				end)
				QuickZone:setEnabled(true)
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end)

	Describe('Values of the wrong type', function()
		Test('Every callback method refuses what is not a function when it is connected.', function()
			withCleanup(function(track)
				local observer = track(Observer.new({ zones = {}, groups = {} }))
				local accepted = {}
				for _, method in
					{
						'observe',
						'onEnter',
						'onExit',
						'observePlayer',
						'onPlayerEnter',
						'onPlayerExit',
						'observeGroup',
						'onGroupEnter',
						'onGroupExit',
						'onTransition',
						'onPlayerTransition',
						'onDestroy',
					}
				do
					if not refuses('callback', (observer :: any)[method], observer, nil) then
						table.insert(accepted, method)
					end
				end

				Expect(table.concat(accepted, ', ')).is('')
			end)
		end)
	end)
end

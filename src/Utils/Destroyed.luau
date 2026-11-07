--!strict

-- Teardown shared by every destroyable object. An object is alive, then destroying while its destroy runs, then
-- dead. While destroying, its callbacks run and see it as it was: queries still find it, but it takes on nothing
-- new, like entities, observers or syncing, which its destroy would leave behind. Once dead, queries no longer
-- find it and its methods are gone

local Log = require(script.Parent.Log)
local Types = require(script.Parent.Parent.Types)

type Destroyable = { phase: Types.Phase, onDestroyCallbacks: { () -> () }? }

local Destroyed = {}

-- Starts destroying the object. Returns false when destroy was called before, so a callback destroying it again
-- does nothing
function Destroyed.begin(object: Destroyable): boolean
	if object.phase ~= 'alive' then
		return false
	end
	object.phase = 'destroying'
	return true
end

-- Ends the destroy. The methods go with the metatable, so a dead object can't be used by mistake
function Destroyed.finish(object: Destroyable)
	object.phase = 'dead'
	setmetatable(object :: any, nil)
end

-- Whether destroy was called on the object, which then takes on nothing new. False for anything that isn't a
-- QuickZone object
function Destroyed.isDestroyed(object: any): boolean
	return type(object) == 'table' and (object.phase == 'destroying' or object.phase == 'dead')
end

-- Whether the object's destroy has ended, so queries no longer find it
function Destroyed.isDead(object: any): boolean
	return type(object) == 'table' and object.phase == 'dead'
end

-- Connects an onDestroy callback, returns its disconnect function. Checked here, as destroy would only fail on it
-- halfway through
function Destroyed.connect(object: Destroyable, callback: () -> ()): () -> ()
	Log.checkCallback(callback)

	local callbacks = object.onDestroyCallbacks or {}
	object.onDestroyCallbacks = callbacks
	table.insert(callbacks, callback)

	return function()
		local idx = table.find(callbacks, callback)
		if idx then
			table.remove(callbacks, idx)
		end
	end
end

-- Fires an object's onDestroy callbacks. Cloned first, as a callback may disconnect itself, and
-- callbacks an earlier one disconnected are skipped
function Destroyed.fireCallbacks(callbacks: { () -> () }?)
	if not callbacks then
		return
	end

	for _, callback in table.clone(callbacks) do
		if table.find(callbacks, callback) then
			task.spawn(callback)
		end
	end
	table.clear(callbacks)
end

return Destroyed

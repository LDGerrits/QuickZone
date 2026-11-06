--!strict

-- Teardown shared by every destroyable object

local Log = require(script.Parent.Log)

local Destroyed = {}

-- Connects an onDestroy callback, returns its disconnect function. Checked here, as destroy would only fail on it
-- halfway through
function Destroyed.connect(object: { onDestroyCallbacks: { () -> () }? }, callback: () -> ()): () -> ()
	if type(callback) ~= 'function' then
		Log.fatal('Expected a callback function, got %s.', nil, typeof(callback))
	end

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

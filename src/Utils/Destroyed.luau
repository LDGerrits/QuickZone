--!strict

-- Teardown shared by every destroyable object

local Destroyed = {}

-- Metatable of destroyed objects, so destroying one again does nothing
Destroyed.metatable = table.freeze({
	__index = table.freeze({
		destroy = function() end,
	}),
})

-- Fires an object's onDestroy callbacks. Cloned first, as a callback may disconnect itself
function Destroyed.fireCallbacks(callbacks: { () -> () }?)
	if not callbacks then
		return
	end

	for _, callback in table.clone(callbacks) do
		task.spawn(callback)
	end
	table.clear(callbacks)
end

return Destroyed

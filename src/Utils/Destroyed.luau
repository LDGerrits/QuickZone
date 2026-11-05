--!strict

-- Teardown shared by every destroyable object

local Destroyed = {}

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

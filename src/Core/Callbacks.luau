--!strict

local Types = require(script.Parent.Parent.Types)

local function withTraceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local Callbacks = {}

-- Unsafe callbacks run directly, but an error is reported instead of thrown,
-- so it can't interrupt the state change that fired it
function Callbacks.fire(
	callbacks: { (any, Types.Zone, Types.Entity) -> () },
	reference: any,
	zone: Types.Zone,
	entity: any,
	safety: boolean
)
	if safety then
		for _, callback in callbacks do
			task.spawn(callback, reference, zone, entity)
		end
	else
		for _, callback in callbacks do
			local ok, trace = xpcall(callback, withTraceback, reference, zone, entity)
			if not ok then
				task.spawn(error, trace, 0)
			end
		end
	end
end

return Callbacks

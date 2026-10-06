--!strict

-- Metatable of destroyed objects, so destroying one again does nothing
local Destroyed = {
	__index = table.freeze({
		destroy = function() end,
	}),
}

return table.freeze(Destroyed)

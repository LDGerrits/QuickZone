--!strict

local Config = {}

-- Static enums used to determine how to read an entity's position
Config.Strategy = {
	POS = 1,
	PRIM = 2,
	WORLD = 3,
	CFRAME = 4,
	PIVOT = 5,
}

Config.Scheduler = {
	-- If true, the scheduler will automatically run every frame.
	-- If false, you must call QuickZone:update manually.
	autoUpdate = true,

	-- Maximum execution time (in seconds) per frame
	-- 0.001 = 1ms (approx 6% of a frame at 60 FPS)
	frameBudget = 1 / 1000,
}

Config.Observer = {
	-- Update frequency (Hz).
	updateRate = 30,

	-- Minimum positional change (in studs) required to trigger a spatial query
	precision = 0.1,

	-- If true, callbacks are fired via task.spawn
	-- If false, callbacks fire immediately
	safety = true,
}

Config.Debug = {
	-- Static zones
	staticActive = Color3.fromRGB(0, 204, 255),
	staticInactive = Color3.fromRGB(40, 114, 133),

	-- Dynamic zones
	dynamicActive = Color3.fromRGB(94, 255, 0),
	dynamicInactive = Color3.fromRGB(80, 141, 46),

	-- General
	transparency = 0.6,
}

return Config

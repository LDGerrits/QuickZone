--!strict

local Config = {}

-- How an entity's position is read
Config.Strategy = {
	POS = 1,
	PRIM = 2,
	WORLD = 3,
	CFRAME = 4,
	TRANSFORM = 5,
	PIVOT = 6,
}

Config.Group = {
	autoClean = true,
}

Config.Scheduler = {
	-- When false, call QuickZone:update yourself
	enabled = true,

	-- Seconds, while the public API takes ms
	frameBudget = 1 / 1000,

	-- Hz
	autoSyncRate = 30,
}

Config.Observer = {
	-- Hz
	updateRate = 30,

	-- Studs moved before an entity is queried again
	precision = 0.1,

	-- Callbacks run via task.spawn
	safety = true,
}

Config.Debug = {
	staticActive = Color3.fromRGB(0, 204, 255),
	staticInactive = Color3.fromRGB(40, 114, 133),

	dynamicActive = Color3.fromRGB(94, 255, 0),
	dynamicInactive = Color3.fromRGB(80, 141, 46),

	transparency = 0.6,
}

return Config

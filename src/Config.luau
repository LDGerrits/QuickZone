--!strict

local Config = {}

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
	enabled = true,

	frameBudgetSeconds = 1 / 1000,

	autoSyncRate = 30,
}

Config.Observer = {
	updateRate = 30,

	precision = 0.1,

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

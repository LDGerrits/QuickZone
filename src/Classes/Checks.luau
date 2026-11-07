--!strict

-- Argument checks shared by the classes

local Log = require(script.Parent.Parent.Utils.Log)
local Zone = require(script.Parent.Zone)
local Zones = require(script.Parent.Zones)

local Checks = {}

-- A live Zone or Zones. Destroyed ones have another metatable
local function isZone(zone: any): boolean
	local class = getmetatable(zone)
	return type(zone) == 'table' and (class == Zone or class == Zones)
end

function Checks.checkZone(zone: any)
	if not isZone(zone) then
		Log.fatal('Expected a live Zone or Zones, got %s.', nil, tostring(zone))
	end
end

return Checks

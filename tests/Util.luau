--!strict
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local Log = require(ReplicatedStorage.QuickZone.Utils.Log)

type InstanceTree = {
	className: string,
	properties: { [string]: any }?,
	children: { InstanceTree }?,
}

local PART_DEFAULTS: { [string]: any } = {
	Transparency = 1,
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	AudioCanCollide = false,
	EnableFluidForces = false,
}

local Util = {}

function Util.create<C>(tree: InstanceTree): C
	local object: any = Instance.new(tree.className)

	if object:IsA('BasePart') then
		for property, value in PART_DEFAULTS do
			object[property] = value
		end
		object.Parent = workspace
	end
	if tree.properties ~= nil then
		for property, value in tree.properties do
			object[property] = value
		end
	end
	if tree.children ~= nil then
		for _, child in tree.children do
			Util.create(child).Parent = object
		end
	end

	return object
end

function Util.createPart(properties: { [string]: any }?): Part
	return Util.create({
		className = 'Part',
		properties = properties,
	})
end

function Util.captureWarnings(callback: () -> ()): { string }
	local captured: { string } = {}
	local original = Log.warn

	Log.warn = function(message: string, _trace: string?, ...: any)
		table.insert(captured, string.format(message, ...))
	end

	local ok, err = pcall(callback)
	Log.warn = original

	if not ok then
		error(err, 0)
	end

	return captured
end

function Util.createParts(count: number, properties: { [string]: any }?): { BasePart }
	local parts: { BasePart } = table.create(count)
	for i = 1, count do
		table.insert(parts, Util.createPart(properties))
	end
	return parts
end

local SHAPES = { 'Block', 'Ball', 'Cylinder', 'Wedge', 'CornerWedge' }

function Util.randomOffset(rng: Random, spread: number): Vector3
	return Vector3.new(
		rng:NextNumber(-spread, spread),
		rng:NextNumber(-spread, spread),
		rng:NextNumber(-spread, spread)
	)
end

function Util.randomCFrame(rng: Random, origin: Vector3, spread: number): CFrame
	local position = origin + Util.randomOffset(rng, spread)
	-- Half stay unrotated to cover both paths
	if rng:NextNumber() < 0.5 then
		return CFrame.new(position)
	end
	return CFrame.new(position)
		* CFrame.fromOrientation(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3))
end

-- Balls and cylinders use Roblox's uniform cross-section
function Util.randomSize(rng: Random, shape: string): Vector3
	local x, y, z = rng:NextNumber(4, 30), rng:NextNumber(4, 30), rng:NextNumber(4, 30)
	if shape == 'Ball' then
		return Vector3.new(x, x, x)
	elseif shape == 'Cylinder' then
		return Vector3.new(x, y, y)
	end
	return Vector3.new(x, y, z)
end

function Util.randomZoneConfig(rng: Random, origin: Vector3, spread: number, isDynamic: boolean): { [string]: any }
	local shape = SHAPES[rng:NextInteger(1, #SHAPES)]
	return {
		cframe = Util.randomCFrame(rng, origin, spread),
		size = Util.randomSize(rng, shape),
		shape = shape,
		isDynamic = isDynamic,
	}
end

-- Returns where found disagrees with checking each zone, or nil. Zones not in zones are ignored.
function Util.findMismatch(zones: { any }, point: Vector3, found: { any }): string?
	local owned = {}
	for _, zone in zones do
		owned[zone] = true
	end

	local foundSet = {}
	for _, zone in found do
		if owned[zone] then
			foundSet[zone] = true
		end
	end

	for _, zone in zones do
		local inside = zone:isPointInside(point)
		if inside ~= (foundSet[zone] == true) then
			return `zone {zone:getId()} ({zone:getShape()}, dynamic={zone:isDynamic()}) at {point}: inside={inside}, found={not inside}`
		end
	end

	return nil
end

return Util

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

return Util

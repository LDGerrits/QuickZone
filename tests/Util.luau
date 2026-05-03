--!strict
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

function Util.createParts(count: number, properties: { [string]: any }?): { BasePart }
	local parts: { BasePart } = table.create(count)
	for i = 1, count do
		table.insert(parts, Util.createPart(properties))
	end
	return parts
end

return Util
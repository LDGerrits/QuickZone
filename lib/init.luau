--!strict
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Collection = require(script.Collection)
local Geometry = require(script.Geometry)
local LinearBVH = require(script.LinearBVH)
local Types = require(script.Types)
local State = require(script.State)
local Zone = require(script.Zone)
local Group = require(script.Group)
local Scheduler = require(script.Scheduler)

local objects = State.Objects
local zoneBoundGroups = State.ZoneBoundGroups
local groupIdToGroupObj = State.GroupIdToGroupObj

local IS_CLIENT = RunService:IsClient()

export type BitZone = Types.BitZone
export type Zone = Types.Zone
export type Group = Types.Group
export type Collection = Types.Collection
export type Item = Types.Item

local BitZone = {}

function BitZone.newZone(cframe: CFrame, size: Vector3, shape: Types.ShapeType, associatedPart: BasePart?): Zone
	return Zone.new(cframe, size, shape, associatedPart)
end

function BitZone.newZoneFromPart(part: BasePart): Zone
	local shape: Types.ShapeType = 'Block'
	if (part :: any).Shape == Enum.PartType.Ball then
		shape = 'Ball'
	elseif (part :: any).Shape == Enum.PartType.Cylinder then
		shape = 'Cylinder'
	end
	return Zone.new(part.CFrame, part.Size, shape, part)
end

function BitZone.newGroup(priority: number?): Group
	return Group.new(priority)
end

function BitZone.newCollection(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
}?)
	return Collection.new(config)
end

-- TODO
function BitZone.playersCollection(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
}?): Collection
	return
end

-- TODO
function BitZone.localPlayerCollection(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
}?): Collection
	assert(IS_CLIENT, '[BitZone] TrackLocalPlayer can only be called on the Client.')

	return
end

function BitZone:SetFrameBudget(n: number): BitZone
	assert(n > 0, '[BitZone] FrameBudget must be greater than 0')

	Scheduler.SetFrameBudget(n)
	return BitZone
end

function BitZone:GetGroupsAtPoint(position: Vector3): { Group }
	local results = {}
	local foundIds = {}

	if State.RootNode then
		LinearBVH.QueryPoint(State.RootNode, position, function(zoneId)
			if Geometry.IsPointInShape(position, objects[zoneId]) then
				local groups = zoneBoundGroups[zoneId]
				if groups then
					for _, id in groups do
						if not foundIds[id] then
							foundIds[id] = true
							local group = groupIdToGroupObj[id]
							if group then
								table.insert(results, group)
							end
						end
					end
				end
			end
		end)
	end
	return results
end

function BitZone:GetCollectionOfItem(item: Types.Item): Types.Collection?
	local colId = State.ItemToCollection[item]
	if colId then
		return State.Collections[colId]
	end
	return nil
end

function BitZone:GetZones(): { Types.Zone }
	local result = {}
	for _, zone in pairs(State.ZoneIdToZoneObj) do
		table.insert(result, zone)
	end
	return result
end

function BitZone:GetGroups(): { Types.Group }
	local result = {}
	for _, group in pairs(State.GroupIdToGroupObj) do
		table.insert(result, group)
	end
	return result
end

function BitZone:GetCollections(): { Types.Collection }
	local result = {}
	for _, collection in pairs(State.Collections) do
		table.insert(result, collection)
	end
	return result
end

function BitZone:GetItems(): { Types.Item }
	local result = {}
	for _, collection in pairs(State.Collections) do
		local count = #collection._items
		if count > 0 then
			local currentSize = #result
			table.move(collection._items, 1, count, currentSize + 1, result)
		end
	end
	return result
end

function BitZone:IsItemValidType(item: any): boolean
	if typeof(item) == 'Instance' then
		if
			item:IsA('BasePart')
			or item:IsA('Attachment')
			or item:IsA('Bone')
			or item:IsA('Camera')
			or item:IsA('Model')
		then
			return true
		end
	elseif typeof(item) == 'table' then
		if item.Position or item.CFrame or item.WorldPosition or item.GetPivot then
			return true
		end
	end
	return false
end

function BitZone:IsItemInAnyCollection(item: Item): boolean
	return State.ItemToCollection[item] ~= nil
end

return BitZone

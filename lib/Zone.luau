--!strict

local State = require(script.Parent.State)
local Types = require(script.Parent.Types)

local Zone = {}
Zone.__index = Zone

function Zone.new(cframe: CFrame, size: Vector3, shape: Types.ShapeType, associatedPart: BasePart?): Types.Zone
	local halfSize = size / 2
	local object: Types.BoundingVolume = {
		Position = cframe.Position,
		CFrame = cframe,
		HalfSize = halfSize,
		Shape = shape,
	}

	if shape == 'Ball' then
		object.radiusSquared = halfSize.X * halfSize.X
	elseif shape == 'Cylinder' then
		local halfHeight = halfSize.X
		object.start = object.Position - object.CFrame.RightVector * halfHeight
		object.axis = object.CFrame.RightVector
		object.axisLength = halfHeight * 2
		object.radiusSquared = halfSize.Y * halfSize.Y
	end

	local index = State.nextZoneId
	State.nextZoneId += 1
	State.objects[index] = object
	State.pendingRebuild = true

	local self = (setmetatable({ Index = index, Part = associatedPart }, Zone) :: any) :: Types.Zone
	State.zoneIndexToZoneObj[index] = self

	return self
end

function Zone:BindToGroups(...): Types.Zone
	local bound = State.zoneBoundGroups[self.Index] or {}
	State.zoneBoundGroups[self.Index] = bound
	for _, group in { ... } do
		if not table.find(bound, group.UID) then
			table.insert(bound, group.UID)
		end
	end
	State.isDirty = true
	return self
end

function Zone:UnbindFromGroups(...): Types.Zone
	local bound = State.zoneBoundGroups[self.Index]
	if not bound then
		return self
	end

	for _, group in { ... } do
		local idx = table.find(bound, group.UID)
		while idx do
			table.remove(bound, idx)
			idx = table.find(bound, group.UID)
		end
	end
	if #bound == 0 then
		State.zoneBoundGroups[self.Index] = nil
	end
	State.isDirty = true

	return self
end

function Zone:GetGroups(): { Types.Group }
	local bound = State.zoneBoundGroups[self.Index]
	if not bound then
		return {}
	end

	local result = {}
	for _, uid in bound do
		local group = State.groupUIDToGroupObj[uid]
		if group then
			table.insert(result, group)
		end
	end
	return result
end

function Zone:Destroy()
	State.zoneBoundGroups[self.Index] = nil
	State.zoneIndexToZoneObj[self.Index] = nil
	State.objects[self.Index] = nil
	State.pendingRebuild = true

	setmetatable(self :: any, nil)
end

return Zone

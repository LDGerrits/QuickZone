--!strict
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestFolder = ServerScriptService.Test

local QuickZone = require(ReplicatedStorage.QuickZone)
local Group = QuickZone.Group

type Tiniest = typeof(require(TestFolder.Tiniest.tiniest_for_roblox).configure({}))

local function Create(Properties: { [string]: any }?, ClassName: string?): BasePart
	local Part = Instance.new(ClassName or "Part") :: BasePart
	if Properties ~= nil then
		for Property, Value in Properties do
			(Part :: any)[Property] = Value
		end
	end
	Part.Anchored = true
	Part.Parent = workspace
	return Part
end

return function(Tiniest: Tiniest)
	local Test = Tiniest.test
	local Describe = Tiniest.describe
	local Expect = Tiniest.expect

	Describe("Group.new", function()
		Test("Creates an empty group.", function()
			local group = Group.new()

			Expect(#group:getEntities()).is(0)
			group:destroy()
		end)

		Test("Creates a group with initial entities.", function()
			local parts = {Create(), Create(), Create()}
			local group = Group.new({entities = parts})

			Expect(#group:getEntities()).is(#parts)
			for _, part in parts do
				Expect(group:contains(part)).is_true()
			end

			group:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test("autoClean true for destroyed entities.", function()
			local part = Create()
			local group = Group.new({entities = {part}})

			Expect(group:contains(part)).is_true()
			part:Destroy()
			task.wait() -- Deferring for AncestryChanged.

			Expect(group:contains(part)).never_is_true()
			group:destroy()
		end)

		Test("autoClean false retains destroyed entities.", function()
			local part = Create()
			local group = Group.new({entities = {part}, autoClean = false})

			part:Destroy()
			task.wait()

			Expect(group:contains(part)).is_true()
			group:destroy()
		end)
	end)

	Describe("Group.fromTag", function()
		Test("Populates from instances already tagged.", function()
			local tag = "QZGroupFromTagPreExisting"
			local partA = Create()
			local partB = Create()
			CollectionService:AddTag(partA, tag)
			CollectionService:AddTag(partB, tag)

			local group = Group.fromTag(tag)

			Expect(#group:getEntities()).is(2)
			Expect(group:contains(partA)).is_true()
			Expect(group:contains(partB)).is_true()

			group:destroy()
			CollectionService:RemoveTag(partA, tag)
			CollectionService:RemoveTag(partB, tag)

			partA:Destroy()
			partB:Destroy()
		end)

		Test("Tracks tag added and removed.", function()
			local tag = "QZGroupFromTagAddRemove"
			local part = Create()
			local group = Group.fromTag(tag)

			Expect(group:contains(part)).never_is_true()

			CollectionService:AddTag(part, tag)
			task.wait() -- Deferring for CollectionService.

			Expect(group:contains(part)).is_true()
			CollectionService:RemoveTag(part, tag)
			task.wait()

			Expect(group:contains(part)).never_is_true()
			group:destroy()
			part:Destroy()
		end)

		Test("Removes entity when it leaves workspace and re-adds when it returns.", function()
			local tag = "QZGroupFromTagAncestry"
			local part = Create()
			CollectionService:AddTag(part, tag)

			local group = Group.fromTag(tag)

			Expect(group:contains(part)).is_true()
			part.Parent = nil
			task.wait() -- Deferring for AncestryChanged.

			Expect(group:contains(part)).never_is_true()
			part.Parent = workspace
			task.wait()

			Expect(group:contains(part)).is_true()

			group:destroy()
			CollectionService:RemoveTag(part, tag)
			part:Destroy()
		end)
	end)

	Describe("Group:setAutoClean", function()
		Test("Disabling stops removing entities on destroy.", function()
			local part = Create()
			local group = Group.new({entities = {part}, autoClean = true})

			Expect(group:setAutoClean(false)).is(group)
			part:Destroy()
			task.wait()

			Expect(group:contains(part)).is_true()
			group:destroy()
		end)

		Test("Enabling removes future destroyed entities.", function()
			local part = Create()
			local group = Group.new({entities = {part}, autoClean = false})

			Expect(group:setAutoClean(true)).is(group)
			part:Destroy()
			task.wait()

			Expect(group:contains(part)).never_is_true()
			group:destroy()
		end)
	end)

	Describe("Group:add", function()
		Test("Adds a BasePart.", function()
			local part = Create()
			local group = Group.new()

			Expect(group:add(part)).is(group)
			Expect(group:contains(part)).is_true()

			group:destroy()
			part:Destroy()
		end)

		Test("Adds a Model with a PrimaryPart.", function()
			local model = Instance.new("Model")
			local part = Create()
			local group = Group.new()

			part.Parent = model
			model.PrimaryPart = part
			model.Parent = workspace
			group:add(model)

			Expect(group:contains(model)).is_true()
			group:destroy()
			model:Destroy()
		end)

		Test("Adds a Camera.", function()
			local camera = Instance.new("Camera")
			local group = Group.new()

			camera.Parent = workspace
			group:add(camera)

			Expect(group:contains(camera)).is_true()
			group:destroy()
			camera:Destroy()
		end)

		Test("Adds an Attachment.", function()
			local attachment = Instance.new("Attachment")
			local group = Group.new()

			attachment.Parent = workspace
			group:add(attachment)

			Expect(group:contains(attachment)).is_true()
			group:destroy()
			attachment:Destroy()
		end)

		Test("Adds a Bone.", function()
			local part = Create()
			local bone = Instance.new("Bone")
			local group = Group.new()

			bone.Parent = part
			group:add(bone)

			Expect(group:contains(bone)).is_true()
			group:destroy()
			part:Destroy()
		end)

		Test("Adds a table with a position.", function()
			local entity = {Position = Vector3.zero}
			local group = Group.new()

			group:add(entity)

			Expect(group:contains(entity)).is_true()
			group:destroy()
		end)

		Test("Adding the same entity twice does not duplicate.", function()
			local part = Create()
			local group = Group.new()

			group:add(part)
			group:add(part)

			Expect(#group:getEntities()).is(1)
			group:destroy()
			part:Destroy()
		end)

		Test("Re-adding an entity after removing it works.", function()
			local part = Create()
			local group = Group.new()

			group:add(part)
			group:remove(part)
			Expect(group:contains(part)).never_is_true()

			group:add(part)
			Expect(group:contains(part)).is_true()
			Expect(#group:getEntities()).is(1)

			group:destroy()
			part:Destroy()
		end)

		Test("Adding an entity to a new group removes it from prior groups.", function()
			local part = Create()
			local groupA = Group.new()
			local groupB = Group.new()
			
			groupA:add(part)
			Expect(groupA:contains(part)).is_true()

			groupB:add(part)
			Expect(groupA:contains(part)).never_is_true()
			Expect(groupB:contains(part)).is_true()

			groupA:destroy()
			groupB:destroy()
			part:Destroy()
		end)
	end)

	Describe("Group:addBulk", function()
		Test("Adds multiple entities in one call.", function()
			local parts = {Create(), Create(), Create()}
			local group = Group.new()

			Expect(group:addBulk(parts)).is(group)
			for _, part in parts do
				Expect(group:contains(part)).is_true()
			end

			group:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)
	end)

	Describe("Group:remove", function()
		Test("Removes an existing entity.", function()
			local part = Create()
			local group = Group.new({entities = {part}})

			Expect(group:remove(part)).is(group)
			Expect(group:contains(part)).never_is_true()

			group:destroy()
			part:Destroy()
		end)

		Test("Removing a non-group entity is ignored.", function()
			local part = Create()
			local group = Group.new()

			Expect(group:remove(part)).is(group)
			Expect(group:contains(part)).never_is_true()

			group:destroy()
			part:Destroy()
		end)
	end)

	Describe("Group:removeBulk", function()
		Test("Removes multiple entities in one call.", function()
			local parts = {Create(), Create(), Create()}
			local group = Group.new({entities = parts})

			Expect(group:removeBulk(parts)).is(group)
			for _, part in parts do
				Expect(group:contains(part)).never_is_true()
			end

			group:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)
	end)

	Describe("Group:clear", function()
		Test("Removes all entities.", function()
			local parts = {Create(), Create(), Create()}
			local group = Group.new({entities = parts})

			Expect(group:clear()).is(group)
			Expect(#group:getEntities()).is(0)
			for _, part in parts do
				Expect(group:contains(part)).never_is_true()
			end

			group:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)
	end)

	Describe("Group:getId", function()
		Test("Returns a unique number per group.", function()
			local groupA = Group.new()
			local groupB = Group.new()

			Expect(groupA:getId()).is_a("number")
			Expect(groupA:getId()).never_is(groupB:getId())

			groupA:destroy()
			groupB:destroy()
		end)
	end)

	Describe("Group:getEntities", function()
		Test("Returns every contained entity exactly once.", function()
			local parts = {Create(), Create(), Create()}
			local group = Group.new({entities = parts})
			local entities = group:getEntities()
			local seen = {}

			Expect(#entities).is(#parts)
			for _, entity in entities do
				seen[entity] = (seen[entity] or 0) + 1
			end
			for _, part in parts do
				Expect(seen[part]).is(1)
			end

			group:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test("Returned array is a copy.", function()
			local parts = {Create(), Create()}
			local group = Group.new({entities = parts})
			local snapshot = group:getEntities()

			table.clear(snapshot)
			Expect(#group:getEntities()).is(#parts)

			group:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)
	end)

	Describe("Group:iterEntities", function()
		Test("Iterates every entity exactly once.", function()
			local parts = {Create(), Create(), Create()}
			local group = Group.new({entities = parts})
			local seen = {}
			local count = 0

			for entity in group:iterEntities() do
				count += 1
				seen[entity] = (seen[entity] or 0) + 1
			end
			Expect(count).is(#parts)
			for _, part in parts do
				Expect(seen[part]).is(1)
			end

			group:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test("Iterates nothing for an empty group.", function()
			local group = Group.new()
			local count = 0

			for _ in group:iterEntities() do
				count += 1
			end
			Expect(count).is(0)

			group:destroy()
		end)
	end)

	Describe("Group:onDestroy", function()
		Test("Fires connected callbacks and disconnected doesn't fire.", function()
			local firedA, firedB = 0, 0
			local group = Group.new()

			group:onDestroy(function() firedA += 1 end)
			group:onDestroy(function() firedB += 1 end)()
			group:destroy()

			Expect(firedA).is(1)
			Expect(firedB).is(0)
		end)
	end)

	Describe("Group:destroy", function()
		Test("Removes group association with contained entities.", function()
			local part = Create()
			local groupA = Group.new({entities = {part}})
			local groupB = Group.new()

			groupA:destroy()
			Expect(groupB:contains(part)).never_is_true()
			groupB:add(part)
			Expect(groupB:contains(part)).is_true()

			groupB:destroy()
			part:Destroy()
		end)
	end)
end
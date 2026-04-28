--!strict
local Players = game:GetService('Players')
local CollectionService = game:GetService('CollectionService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest

local Util = require(TestFolder.Util)

local QuickZone = require(ReplicatedStorage.QuickZone)
local Group = QuickZone.Group

type Tiniest = typeof(require(TiniestFolder.tiniest_for_roblox).configure({}))

return function(Tiniest: Tiniest)
	local Describe = Tiniest.describe
	local Test = Tiniest.test
	local Expect = Tiniest.expect
	local CreatePart = Util.createPart
	local CreateParts = Util.createParts

	local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	local character = player.Character or player.CharacterAdded:Wait()

	Describe('Group.new', function()
		Test('Populates the group from the given entities at construction.', function()
			local parts = CreateParts(3)
			local group = Group.new({ entities = parts })

			Expect(#group:getEntities()).is(#parts)
			for _, part in parts do
				Expect(group:contains(part)).is_true()
			end

			group:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test('Auto clean enabled removes destroyed members.', function()
			local part = CreatePart()
			local group = Group.new({ entities = { part } })

			Expect(group:contains(part)).is_true()

			part:Destroy()
			task.wait()

			Expect(group:contains(part)).never_is_true()
			group:destroy()
		end)

		Test('Auto clean disabled keeps destroyed members.', function()
			local part = CreatePart()
			local group = Group.new({ entities = { part }, autoClean = false })

			part:Destroy()
			task.wait()

			Expect(group:contains(part)).is_true()
			group:destroy()
		end)
	end)

	Describe('Group.fromTag', function()
		Test('Instances tagged before construction are picked up at construction time.', function()
			local tag = 'QZ_FROM_TAG_PRE_EXISTING'
			local partA = CreatePart()
			local partB = CreatePart()
			local group

			CollectionService:AddTag(partA, tag)
			CollectionService:AddTag(partB, tag)
			group = Group.fromTag(tag)

			Expect(#group:getEntities()).is(2)
			Expect(group:contains(partA)).is_true()
			Expect(group:contains(partB)).is_true()

			group:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Updates as tags are added and removed at runtime.', function()
			local tag = 'QZ_FROM_TAG_RUNTIME'
			local part = CreatePart()
			local group = Group.fromTag(tag)

			Expect(group:contains(part)).never_is_true()

			CollectionService:AddTag(part, tag)
			task.wait()

			Expect(group:contains(part)).is_true()

			CollectionService:RemoveTag(part, tag)
			task.wait()

			Expect(group:contains(part)).never_is_true()
			group:destroy()
			part:Destroy()
		end)

		Test('Tagged parts outside workspace drops groups, re-parenting restores them.', function()
			local tag = 'QZ_FROM_TAG_ANCESTRY'
			local part = CreatePart()
			local group

			CollectionService:AddTag(part, tag)
			group = Group.fromTag(tag)

			Expect(group:contains(part)).is_true()

			part.Parent = nil
			task.wait()

			Expect(group:contains(part)).never_is_true()

			part.Parent = workspace
			task.wait()

			Expect(group:contains(part)).is_true()
			group:destroy()
			part:Destroy()
		end)
	end)

	Describe('Group:setAutoClean', function()
		Test('Disabling auto clean keeps Instance members in the group.', function()
			local part = CreatePart()
			local group = Group.new({ entities = { part }, autoClean = true })

			Expect(group:setAutoClean(false)).is(group)

			part:Destroy()
			task.wait()

			Expect(group:contains(part)).is_true()
			group:destroy()
		end)

		Test('Enabling auto clean removes Instance members in the group.', function()
			local part = CreatePart()
			local group = Group.new({ entities = { part }, autoClean = false })

			group:setAutoClean(true)
			part:Destroy()
			task.wait()

			Expect(group:contains(part)).never_is_true()
			group:destroy()
		end)
	end)

	Describe('Group:add', function()
		Test('Accepts a BasePart.', function()
			local part = CreatePart()
			local group = Group.new()

			Expect(group:add(part)).is(group)
			Expect(group:contains(part)).is_true()
			group:destroy()
			part:Destroy()
		end)

		Test('Accepts a Model.', function()
			local model = Instance.new('Model')
			local part = CreatePart()
			local group = Group.new()

			part.Parent = model
			model.Parent = workspace
			group:add(model)

			Expect(group:contains(model)).is_true()
			group:destroy()
			model:Destroy()
		end)

		Test('Accepts a Camera.', function()
			local camera = Instance.new('Camera')
			local group = Group.new()

			camera.Parent = workspace
			group:add(camera)

			Expect(group:contains(camera)).is_true()
			group:destroy()
			camera:Destroy()
		end)

		Test('Accepts an Attachment.', function()
			local attachment = Instance.new('Attachment')
			local group = Group.new()

			attachment.Parent = workspace
			group:add(attachment)

			Expect(group:contains(attachment)).is_true()
			group:destroy()
			attachment:Destroy()
		end)

		Test('Accepts a Bone.', function()
			local part = CreatePart()
			local bone = Instance.new('Bone')
			local group = Group.new()

			bone.Parent = part
			group:add(bone)

			Expect(group:contains(bone)).is_true()
			group:destroy()
			part:Destroy()
		end)

		Test('Accepts a table with a Position field.', function()
			local entity = { Position = Vector3.zero }
			local group = Group.new()

			group:add(entity)

			Expect(group:contains(entity)).is_true()
			group:destroy()
		end)

		Test('Adding the same entity twice still counts as one member.', function()
			local part = CreatePart()
			local group = Group.new()

			group:add(part)
			group:add(part)

			Expect(#group:getEntities()).is(1)
			group:destroy()
			part:Destroy()
		end)

		Test('Re-adding an entity after removing re-enters with no stale state.', function()
			local part = CreatePart()
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

		Test('Multi-group membership is additive.', function()
			local part = CreatePart()
			local groupA = Group.new()
			local groupB = Group.new()

			groupA:add(part)

			Expect(groupA:contains(part)).is_true()

			groupB:add(part)

			Expect(groupA:contains(part)).is_true()
			Expect(groupB:contains(part)).is_true()

			groupA:destroy()
			groupB:destroy()
			part:Destroy()
		end)
	end)

	Describe('Group:addBulk', function()
		Test('Every element of the passed array ends up in the group.', function()
			local parts = CreateParts(3)
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

	Describe('Group:remove', function()
		Test('Removes the entity from membership.', function()
			local part = CreatePart()
			local group = Group.new({ entities = { part } })

			Expect(group:remove(part)).is(group)
			Expect(group:contains(part)).never_is_true()
			group:destroy()
			part:Destroy()
		end)
	end)

	Describe('Group:removeBulk', function()
		Test('Every element of the passed array leaves the group.', function()
			local parts = CreateParts(3)
			local group = Group.new({ entities = parts })

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

	Describe('Group:clear', function()
		Test('After clear, no prior member is still contained.', function()
			local parts = CreateParts(3)
			local group = Group.new({ entities = parts })

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

	Describe('Group:contains', function()
		Test('Accepts either the entity or its mapped reference.', function()
			local id = 'QZ_CONTAINS_REF'
			local part = CreatePart()
			local group = Group.new()

			QuickZone:setReference(part, id)
			group:add(part)

			Expect(group:contains(part)).is_true()
			Expect(group:contains(id :: any)).is_true()

			QuickZone:setReference(part, nil)

			group:destroy()
			part:Destroy()
		end)
	end)

	Describe('Group:getId', function()
		Test('Two groups have different IDs.', function()
			local groupA = Group.new()
			local groupB = Group.new()

			Expect(groupA:getId()).is_a('number')
			Expect(groupA:getId()).never_is(groupB:getId())
			groupA:destroy()
			groupB:destroy()
		end)
	end)

	Describe('Group:getEntities', function()
		Test('Return contains the mapped reference, not the raw entity.', function()
			local id = 'QZ_GET_ENTITIES_REF'
			local part = CreatePart()
			local group = Group.new()
			local entities

			QuickZone:setReference(part, id)
			group:add(part)
			entities = group:getEntities()
			QuickZone:setReference(part, nil)

			Expect(#entities).is(1)
			Expect(entities[1]).is(id)
			group:destroy()
			part:Destroy()
		end)
	end)

	Describe('Group:iterEntities', function()
		Test('Yields every member once.', function()
			local count = 0
			local seen = {}
			local parts = CreateParts(3)
			local group = Group.new({ entities = parts })

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
	end)

	Describe('Group:onDestroy', function()
		Test('Connected callbacks fire on destroy, calling the disconnect function unbinds them.', function()
			local firedA, firedB = 0, 0
			local group = Group.new()

			group:onDestroy(function()
				firedA += 1
			end)
			group:onDestroy(function()
				firedB += 1
			end)()

			group:destroy()
			Expect(firedA).is(1)
			Expect(firedB).is(0)
		end)
	end)

	Describe('Group:destroy', function()
		Test('Releases members so another group can re-claim them.', function()
			local part = CreatePart()
			local groupA = Group.new({ entities = { part } })
			local groupB = Group.new()

			groupA:destroy()

			Expect(groupB:contains(part)).never_is_true()

			groupB:add(part)

			Expect(groupB:contains(part)).is_true()
			groupB:destroy()
			part:Destroy()
		end)
	end)

	Describe('Group.players', function()
		Test('Both HumanoidRootPart and player is in the group.', function()
			local group = Group.players()

			Expect(group:contains(character.HumanoidRootPart)).is_true()
			Expect(group:contains(player)).is_true()
			group:destroy()
		end)

		Test('State survives destroy and recreate.', function()
			local first = Group.players()
			local second

			Expect(first:contains(player)).is_true()

			first:destroy()
			second = Group.players()

			Expect(second:contains(player)).is_true()
			second:destroy()
		end)
	end)
end
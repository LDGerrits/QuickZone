--!strict
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestFolder = ServerScriptService.Test

local Types = require(ReplicatedStorage.QuickZone.Types)
local QuickZone = require(ReplicatedStorage.QuickZone)
local Zone = QuickZone.Zone

type Tiniest = typeof(require(TestFolder.Tiniest.tiniest_for_roblox).configure({}))

local ShapeTypes = {"Block", "Ball", "Cylinder", "Wedge", "CornerWedge"}

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

	Describe("Zone.new", function()
		local cframe = CFrame.identity
		local size = Vector3.one * 20

		Test("Creates a zone for each shape.", function()
			for _, shape in ShapeTypes do
				local zone = Zone.new({
					cframe = cframe,
					size = size,
					shape = shape :: Types.ShapeType,
				})

				Expect(zone:getShape()).is(shape)
				zone:destroy()
			end
		end)

		Test("Creates a dynamic zone with metadata.", function()
			local metadata = { Name = "Test", Value = 100 }
			local zone = Zone.new({
					cframe = cframe,
					size = size,
					isDynamic = true,
					metadata = metadata,
				})

			Expect(zone:isDynamic()).is_true()
			Expect(zone:getMetadata()).is(metadata)
			zone:destroy()
		end)

		Test("Creates a zone with proper defaults.", function()
			local zone = Zone.new({
				cframe = cframe,
				size = size,
			})

			Expect(zone:getShape()).is("Block")
			Expect(zone:getSize()).is(size)
			Expect(zone:getCFrame()).is(cframe)
			Expect(zone:getPosition()).is(cframe.Position)
			Expect(zone:getMetadata()).is()
			Expect(zone:getReference()).is()
			Expect(zone:isDynamic()).never_is_true()

			zone:destroy()
		end)
	end)

	Describe("Zone.fromPart", function()
		local cframe = CFrame.new(5, 5, 10) * CFrame.Angles(0, math.pi / 4, 0)
		local size = Vector3.one * 10

		Test("Creates a zone using an existing part.", function()
			for _, shape in ShapeTypes do
				local part = Create({
					CFrame = cframe,
					Size = size,
					Shape = (Enum.PartType :: any)[shape],
				})
				local zone = Zone.fromPart(part)

				Expect(zone:getReference()).is(part)
				Expect(zone:getPosition()).is(part.Position)
				Expect(zone:getCFrame()).is(part.CFrame)
				Expect(zone:getSize()).is(size)
				Expect(zone:getShape()).is(shape)

				zone:destroy()
				part:Destroy()
			end
		end)

		Test("Creates a zone using a WedgePart.", function()
			local part = Create(nil, "WedgePart")
			local zone = Zone.fromPart(part)

			Expect(zone:getShape()).is("Wedge")
			zone:destroy()
			part:Destroy()
		end)

		Test("Creates a zone using a CornerWedgePart.", function()
			local part = Create(nil, "CornerWedgePart")
			local zone = Zone.fromPart(part)

			Expect(zone:getShape()).is("CornerWedge")
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe("Zone:setCFrame", function()
		Test("Sets the zone's CFrame.", function()
			local cframe = CFrame.Angles(0, math.pi / 4, 0) + Vector3.new(10, 15, 20)
			local zone = Zone.new({cframe = CFrame.identity, size = Vector3.one * 5.5})

			Expect(zone:setCFrame(cframe)).is(zone)
			Expect(zone:getCFrame()).is(cframe)
			zone:destroy()
		end)

		Test("Dynamic zone moved via setCFrame.", function()
			local point = Vector3.zero
			local cframe = CFrame.new(0, 0, 15)
			local zone = Zone.new({
				cframe = CFrame.identity,
				size = Vector3.one * 10,
				isDynamic = true,
			})

			Expect(zone:isPointInside(point)).is_true()
			Expect(zone:setCFrame(cframe)).is(zone)
			Expect(zone:isPointInside(cframe.Position)).is_true()
			Expect(zone:isPointInside(point)).never_is_true()

			zone:destroy()
		end)
	end)

	Describe("Zone:setPosition", function()
		Test("Sets the zone's position.", function()
			local rotation = CFrame.Angles(0, math.pi / 4, 0)
			local position = Vector3.new(25, 0, 0)
			local zone = Zone.new({cframe = rotation, size = Vector3.one * 5.5})

			Expect(zone:setPosition(position)).is(zone)
			Expect(zone:getPosition()).is(position)
			Expect(zone:getCFrame()).is(rotation + position)

			zone:destroy()
		end)
	end)

	Describe("Zone:setSize", function()
		Test("Sets the zone's size.", function()
			local size = Vector3.one * 2.5
			local point = Vector3.new(4, 0, 0)
			local zone = Zone.new({cframe = CFrame.identity, size = Vector3.one * 10})

			Expect(zone:isPointInside(point)).is_true()
			Expect(zone:setSize(size)).is(zone)
			Expect(zone:isPointInside(point)).never_is_true()
			Expect(zone:getSize()).is(size)

			zone:destroy()
		end)
	end)

	Describe("Zone:setShape", function()
		Test("Sets the zone's shape.", function()
			local point = Vector3.new(4, 4, 4)
			local zone = Zone.new({
				cframe = CFrame.identity,
				size = Vector3.one * 10,
			})

			Expect(zone:isPointInside(point)).is_true()
			Expect(zone:setShape("Ball")).is(zone)
			Expect(zone:getShape()).is("Ball")
			Expect(zone:isPointInside(point)).never_is_true()

			zone:destroy()
		end)
	end)

	Describe("Zone:setDynamic", function()
		Test("Dynamic zone changed to static.", function()
			local zone = Zone.new({
				cframe = CFrame.identity,
				size = Vector3.one * 10,
				isDynamic = true,
			})

			Expect(zone:setCFrame(CFrame.new(100, 0, 0))).is(zone)
			Expect(zone:setDynamic(false)).is(zone)
			Expect(zone:isPointInside(Vector3.new(100, 0, 0))).is_true()
			Expect(zone:isPointInside(Vector3.new(0, 0, 0))).never_is_true()

			zone:destroy()
		end)
	end)

	Describe("Zone:setMetadata", function()
		Test("Sets the zone's metadata.", function()
			local metadata = { Name = "Test", Value = 100 }
			local zone = Zone.new({cframe = CFrame.identity, size = Vector3.one * 10})

			Expect(zone:getMetadata()).is()
			Expect(zone:setMetadata(metadata)).is(zone)
			Expect(zone:getMetadata()).is(metadata)

			zone:destroy()
		end)
	end)

	Describe("Zone:setReference", function()
		Test("Sets and clears the zone's reference.", function()
			local part = Create()
			local zone = Zone.new({cframe = CFrame.identity, size = Vector3.one * 10})

			Expect(zone:getReference()).is()
			Expect(zone:setReference(part)).is(zone)
			Expect(zone:getReference()).is(part)
			Expect(zone:setReference()).is(zone)
			Expect(zone:getReference()).is()

			zone:destroy()
			part:Destroy()
		end)

		Test("Attach auto-sync to the new reference.", function()
			local partA = Create({Size = Vector3.one * 10})
			local partB = Create({Size = Vector3.one * 10})
			local zone = Zone.fromPart(partA, {autoSync = true})

			Expect(zone:setReference(partB)).is(zone)

			partA.Size = Vector3.one * 50
			partB.Size = Vector3.one * 20
			task.wait() -- Deferring for GetPropertyChangedSignal.

			Expect(zone:getSize()).is(Vector3.one * 20)

			zone:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe("Zone:setAutoSync", function()
		Test("Automatically changes a static zone to dynamic.", function()
			local part = Create()
			local zone = Zone.fromPart(part)

			Expect(zone:isDynamic()).never_is_true()
			Expect(zone:setAutoSync(true)).is(zone)
			Expect(zone:isDynamic()).is_true()

			zone:destroy()
			part:Destroy()
		end)

		Test("Syncs CFrame via scheduler update.", function()
			local cframe = CFrame.new(50, 0, 0)
			local part = Create()
			local zone = Zone.fromPart(part, {autoSync = true})

			part.CFrame = cframe
			QuickZone:update(1 / 10)

			Expect(zone:getCFrame()).is(cframe)
			zone:destroy()
			part:Destroy()
		end)

		Test("Disabling stops future syncing.", function()
			local part = Create()
			local zone = Zone.fromPart(part, {autoSync = true})

			part.CFrame = CFrame.new(10, 0, 0)
			QuickZone:update(1 / 10)

			Expect(zone:getPosition()).is(Vector3.new(10, 0, 0))
			Expect(zone:setAutoSync(false)).is(zone)

			part.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)

			Expect(zone:getPosition()).is(Vector3.new(10, 0, 0))
			zone:destroy()
			part:Destroy()
		end)

		Test("Auto-syncs size.", function()
			local size = Vector3.one * 20
			local part = Create({Size = Vector3.one * 10})
			local zone = Zone.fromPart(part, {autoSync = true})

			part.Size = size
			task.wait() -- Deferring for GetPropertyChangedSignal.

			Expect(zone:getSize()).is(size)
			zone:destroy()
			part:Destroy()
		end)

		Test("Auto-syncs shape.", function()
			local part = Create({Shape = Enum.PartType.Block}) :: Part
			local zone = Zone.fromPart(part, {autoSync = true})

			part.Shape = Enum.PartType.Ball
			task.wait() -- Deferring for GetPropertyChangedSignal.

			Expect(zone:getShape()).is("Ball")
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe("Zone:sync", function()
		Test("Gets CFrame, size, and shape from reference.", function()
			local cframe = CFrame.new(50, 0, 0)
			local size = Vector3.one * 20
			local part = Create({Size = Vector3.one * 10}) :: Part
			local zone = Zone.fromPart(part)

			part.CFrame = cframe
			part.Size = size
			part.Shape = Enum.PartType.Ball

			Expect(zone:sync()).is(zone)
			Expect(zone:getCFrame()).is(cframe)
			Expect(zone:getSize()).is(size)
			Expect(zone:getShape()).is("Ball")

			zone:destroy()
			part:Destroy()
		end)

		Test("Gets WorldCFrame from an Attachment reference.", function()
			local cframe = CFrame.new(50, 0, 0)
			local attachment = Instance.new("Attachment")
			local zone = Zone.new({
				cframe = CFrame.identity,
				size = Vector3.one * 10,
				reference = attachment,
			})

			attachment.WorldCFrame = cframe
			attachment.Parent = workspace

			Expect(zone:sync()).is(zone)
			Expect(zone:getCFrame()).is(cframe)

			zone:destroy()
			attachment:Destroy()
		end)
	end)

	Describe("Zone:getId", function()
		Test("Returns a unique number per zone.", function()
			local zoneA = Zone.new({cframe = CFrame.identity, size = Vector3.one * 5})
			local zoneB = Zone.new({cframe = CFrame.identity, size = Vector3.one * 15})

			Expect(zoneA:getId()).is_a("number")
			Expect(zoneA:getId()).never_is(zoneB:getId())

			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe("Zone:isPointInside", function()
		local size = Vector3.one * 10
		local rotation = CFrame.Angles(0, math.pi / 4, 0)

		Test("Block", function()
			local zoneA = Zone.new({cframe = CFrame.identity, size = size})
			local zoneB = Zone.new({cframe = rotation, size = size})

			Expect(zoneA:isPointInside(Vector3.zero)).is_true()
			Expect(zoneA:isPointInside(Vector3.new(4.9, 4.9, 4.9))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(5.1, 0, 0))).never_is_true()
			Expect(zoneA:isPointInside(Vector3.new(100, 0, 0))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.zero))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(4.9, 4.9, 4.9)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(5.1, 0, 0)))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(100, 0, 0)))).never_is_true()

			zoneA:destroy()
			zoneB:destroy()
		end)

		Test("Ball", function()
			local zoneA = Zone.new({cframe = CFrame.identity, size = size, shape = "Ball"})
			local zoneB = Zone.new({cframe = rotation, size = size, shape = "Ball"})

			Expect(zoneA:isPointInside(Vector3.zero)).is_true()
			Expect(zoneA:isPointInside(Vector3.new(4.9, 0, 0))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(5.1, 0, 0))).never_is_true()
			Expect(zoneA:isPointInside(Vector3.new(4.9, 4.9, 4.9))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.zero))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(4.9, 0, 0)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(5.1, 0, 0)))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(4.9, 4.9, 4.9)))).never_is_true()

			zoneA:destroy()
			zoneB:destroy()
		end)

		Test("Cylinder", function()
			local zoneA = Zone.new({cframe = CFrame.identity, size = size, shape = "Cylinder"})
			local zoneB = Zone.new({cframe = rotation, size = size, shape = "Cylinder"})

			Expect(zoneA:isPointInside(Vector3.zero)).is_true()
			Expect(zoneA:isPointInside(Vector3.new(4.9, 0, 0))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(4.9, 4.9, 0))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(0, 4.9, 4.9))).never_is_true()
			Expect(zoneA:isPointInside(Vector3.new(0, 100, 0))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.zero))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(4.9, 0, 0)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(4.9, 4.9, 0)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(0, 4.9, 4.9)))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(0, 100, 0)))).never_is_true()

			zoneA:destroy()
			zoneB:destroy()
		end)

		Test("Wedge", function()
			local zoneA = Zone.new({cframe = CFrame.identity, size = size, shape = "Wedge"})
			local zoneB = Zone.new({cframe = rotation, size = size, shape = "Wedge"})

			Expect(zoneA:isPointInside(Vector3.new(0, -4, 0))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(0, -4, 4))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(0, 4.9, -4.9))).never_is_true()
			Expect(zoneA:isPointInside(Vector3.new(100, 0, 0))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(0, -4, 0)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(0, -4, 4)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(0, 4.9, -4.9)))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(100, 0, 0)))).never_is_true()

			zoneA:destroy()
			zoneB:destroy()
		end)

		Test("CornerWedge", function()
			local zoneA = Zone.new({cframe = CFrame.identity, size = size, shape = "CornerWedge"})
			local zoneB = Zone.new({cframe = rotation, size = size, shape = "CornerWedge"})

			Expect(zoneA:isPointInside(Vector3.new(0, -4, 0))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(4, -4, -4))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(0, 4.9, 4.9))).never_is_true()
			Expect(zoneA:isPointInside(Vector3.new(-4.9, 4.9, -4.9))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(0, -4, 0)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(4, -4, -4)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(0, 4.9, 4.9)))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(-4.9, 4.9, -4.9)))).never_is_true()

			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe("Zone:onDestroy", function()
		Test("Fires connected callbacks and disconnected doesn't fire.", function()
			local firedA, firedB = 0, 0
			local zone = Zone.new({cframe = CFrame.identity, size = Vector3.one * 10})

			zone:onDestroy(function() firedA += 1 end)
			zone:onDestroy(function() firedB += 1 end)()
			zone:destroy()

			Expect(firedA).is(1)
			Expect(firedB).is(0)
		end)
	end)

	Describe("Zone.fromParts", function()
		Test("Creates a Zones container with one inner zone per part.", function()
			local parts = {Create(), Create(), Create()}
			local seen = {}
			local zones = Zone.fromParts(parts)

			Expect(#zones:getZones()).is(#parts)

			for reference, _ in zones:iterReferences() do
				seen[reference] = true
			end
			for _, part in parts do
				Expect(seen[part]).is_true()
			end
			for _, part in parts do
				part:Destroy()
			end

			zones:destroy()
		end)
	end)

	Describe("Zone.fromChildren", function()
		Test("Gets direct children only.", function()
			local parentFolder = Instance.new("Folder")
			local childFolder = Instance.new("Folder")
			Create().Parent = parentFolder
			Create().Parent = childFolder
			childFolder.Parent = parentFolder
			parentFolder.Parent = workspace

			local zones = Zone.fromChildren(parentFolder)

			Expect(#zones:getZones()).is(1)
			zones:destroy()
			parentFolder:Destroy()
		end)

		Test("Tracks children added and removed.", function()
			local parentFolder = Instance.new("Folder")
			local partA = Create()
			local partB = Create()
			partA.Parent = parentFolder
			parentFolder.Parent = workspace

			local zones = Zone.fromChildren(parentFolder)

			Expect(#zones:getZones()).is(1)

			partB.Parent = parentFolder
			task.wait() -- Deferring for ChildAdded.

			Expect(#zones:getZones()).is(2)
			partA:Destroy()

			task.wait()

			Expect(#zones:getZones()).is(1)
			zones:destroy()
			parentFolder:Destroy()
		end)
	end)

	Describe("Zone.fromDescendants", function()
		Test("Gets nested descendants, not just direct children.", function()
			local parentFolder = Instance.new("Folder")
			local childFolder = Instance.new("Folder")
			Create().Parent = parentFolder
			Create().Parent = childFolder
			childFolder.Parent = parentFolder
			parentFolder.Parent = workspace

			local zones = Zone.fromDescendants(parentFolder)

			Expect(#zones:getZones()).is(2)
			zones:destroy()
			parentFolder:Destroy()
		end)

		Test("Tracks descendants added and removed.", function()
			local parentFolder = Instance.new("Folder")
			local childFolder = Instance.new("Folder")
			local partA = Create()
			local partB = Create()
			partA.Parent = childFolder
			childFolder.Parent = parentFolder
			parentFolder.Parent = workspace

			local zones = Zone.fromDescendants(parentFolder)

			Expect(#zones:getZones()).is(1)

			partB.Parent = childFolder
			task.wait() -- Deferring for DescendantAdded.

			Expect(#zones:getZones()).is(2)
			partA:Destroy()

			task.wait()

			Expect(#zones:getZones()).is(1)
			zones:destroy()
			parentFolder:Destroy()
		end)
	end)

	Describe("Zone.fromTag", function()
		Test("Populates from instances already tagged.", function()
			local tag = "QZFromTagPreExisting"
			local partA = Create()
			local partB = Create()
			CollectionService:AddTag(partA, tag)
			CollectionService:AddTag(partB, tag)

			local zones = Zone.fromTag(tag)

			Expect(#zones:getZones()).is(2)
			zones:destroy()

			CollectionService:RemoveTag(partA, tag)
			CollectionService:RemoveTag(partB, tag)
			partA:Destroy()
			partB:Destroy()
		end)

		Test("Tracks tag added and removed.", function()
			local tag = "QZFromTagExisting"
			local partA = Create()
			local partB = Create()
			CollectionService:AddTag(partA, tag)

			local zones = Zone.fromTag(tag)

			Expect(#zones:getZones()).is(1)

			CollectionService:AddTag(partB, tag)
			task.wait() -- Deferring for CollectionService.

			Expect(#zones:getZones()).is(2)

			CollectionService:RemoveTag(partA, tag)
			task.wait()

			Expect(#zones:getZones()).is(1)
			zones:destroy()

			CollectionService:RemoveTag(partB, tag)
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	-- Zones are covered below.
	Describe("Zones", function()
		Test("Returns true for inner zones and false for outer zones.", function()
			local parts = {Create(), Create()}
			local zones = Zone.fromParts(parts)
			local outer = Zone.new({cframe = CFrame.identity, size = Vector3.one * 5})
			
			for _, inner in zones:getZones() do
				Expect(zones:contains(inner)).is_true()
			end

			Expect(zones:contains(outer)).never_is_true()
			zones:destroy()
			outer:destroy()

			for _, part in parts do
				part:Destroy()
			end
		end)

		Test("Iteration methods yield every entry once.", function()
			local parts = {Create(), Create(), Create()}
			local seenZones, seenReferences = {}, {}
			local zoneCount = 0
			local zones = Zone.fromParts(parts)

			Expect(#zones:getZones()).is(#parts)
			Expect(#zones:getReferences()).is(#parts)

			for zone in zones:iterZones() do
				zoneCount += 1
				seenZones[zone] = (seenZones[zone] or 0) + 1
			end
			Expect(zoneCount).is(#parts)
			for _, zone in zones:getZones() do
				Expect(seenZones[zone]).is(1)
			end
			for reference, _ in zones:iterReferences() do
				seenReferences[reference] = (seenReferences[reference] or 0) + 1
			end
			for _, part in parts do
				Expect(seenReferences[part]).is(1)
			end

			zones:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test("Zones set to dynamic.", function()
			local parts = {Create(), Create()}
			local zones = Zone.fromParts(parts)

			Expect(zones:isDynamic()).never_is_true()
			zones:setDynamic(true)
			Expect(zones:isDynamic()).is_true()

			for _, inner in zones:getZones() do
				Expect(inner:isDynamic()).is_true()
			end

			zones:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test("Zones set with metadata.", function()
			local metadata = { Value = 5 }
			local parts = {Create(), Create()}
			local zones = Zone.fromParts(parts)

			zones:setMetadata(metadata)
			Expect(zones:getMetadata()).is(metadata)

			for _, inner in zones:getZones() do
				Expect(inner:getMetadata()).is(metadata)
			end

			zones:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test("Zones set to auto-sync.", function()
			local partA = Create()
			local partB = Create({CFrame = CFrame.new(100, 0, 0)})
			local matches = 0
			local zones = Zone.fromParts({partA, partB})

			zones:setAutoSync(true)

			for _, inner in zones:getZones() do
				Expect(inner:isDynamic()).is_true()
			end

			partA.CFrame = CFrame.new(50, 0, 0)
			partB.CFrame = CFrame.new(150, 0, 0)
			QuickZone:update(1 / 10)

			for reference, inner in zones:iterReferences() do
				if inner == nil then continue end
				if reference == partA then
					Expect(inner:getPosition()).is(Vector3.new(50, 0, 0))
					matches += 1
				elseif reference == partB then
					Expect(inner:getPosition()).is(Vector3.new(150, 0, 0))
					matches += 1
				end
			end
			Expect(matches).is(2)

			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test("Sync updates every inner zone from its reference.", function()
			local partA = Create()
			local partB = Create({CFrame = CFrame.new(100, 0, 0)})
			local matches = 0
			local zones = Zone.fromParts({partA, partB}, {isDynamic = true})

			partA.CFrame = CFrame.new(50, 0, 0)
			partB.CFrame = CFrame.new(150, 0, 0)
			zones:sync()

			for reference, inner in zones:iterReferences() do
				if inner == nil then continue end
				if reference == partA then
					Expect(inner:getPosition()).is(Vector3.new(50, 0, 0))
					matches += 1
				elseif reference == partB then
					Expect(inner:getPosition()).is(Vector3.new(150, 0, 0))
					matches += 1
				end
			end
			Expect(matches).is(2)

			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test("Returns true inside any inner zone, false outside.", function()
			local partA = Create({Size = Vector3.one * 10})
			local partB = Create({CFrame = CFrame.new(100, 0, 0), Size = Vector3.one * 10})
			local zones = Zone.fromParts({partA, partB})

			Expect(zones:isPointInside(Vector3.zero)).is_true()
			Expect(zones:isPointInside(Vector3.new(100, 0, 0))).is_true()
			Expect(zones:isPointInside(Vector3.new(50, 0, 0))).never_is_true()

			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test("Zones fire connected callbacks and disconnected doesn't fire.", function()
			local parts = {Create(), Create()}
			local firedA, firedB = 0, 0
			local zones = Zone.fromParts(parts)

			zones:onDestroy(function() firedA += 1 end)
			zones:onDestroy(function() firedB += 1 end)()
			zones:destroy()

			Expect(firedA).is(1)
			Expect(firedB).is(0)

			for _, part in parts do
				part:Destroy()
			end
		end)
	end)
end
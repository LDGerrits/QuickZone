--!strict
local CollectionService = game:GetService('CollectionService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest

local Util = require(TestFolder.Util)

local Types = require(ReplicatedStorage.QuickZone.Types)
local QuickZone = require(ReplicatedStorage.QuickZone)
local Zone = QuickZone.Zone

local SHAPE_TYPES = { 'Block', 'Ball', 'Cylinder', 'Wedge', 'CornerWedge' }

type Tiniest = typeof(require(TiniestFolder.tiniest_for_roblox).configure({}))

return function(Tiniest: Tiniest)
	local Describe = Tiniest.describe
	local Test = Tiniest.test
	local Expect = Tiniest.expect
	local Create = Util.create
	local CreatePart = Util.createPart
	local CreateParts = Util.createParts

	Describe('Zone.new', function()
		local cframe = CFrame.identity
		local size = Vector3.one * 20

		Test('Accepts every supported shape type.', function()
			for _, shape in SHAPE_TYPES do
				local zone = Zone.new({ cframe = cframe, size = size, shape = (shape :: Types.ShapeType) })

				Expect(zone:getShape()).is(shape)
				zone:destroy()
			end
		end)

		Test('Accepts isDynamic and metadata config fields.', function()
			local metadata = { Name = 'QZ', Value = 1000 }
			local zone = Zone.new({ cframe = cframe, size = size, isDynamic = true, metadata = metadata })

			Expect(zone:isDynamic()).is_true()
			Expect(zone:getMetadata()).is(metadata)
			zone:destroy()
		end)

		Test('Creates a default zone with omitted config fields.', function()
			local zone = Zone.new({ cframe = cframe, size = size })

			Expect(zone:getShape()).is('Block')
			Expect(zone:getSize()).is(size)
			Expect(zone:getCFrame()).is(cframe)
			Expect(zone:getPosition()).is(cframe.Position)
			Expect(zone:getMetadata()).is()
			Expect(zone:getReference()).is()
			Expect(zone:isDynamic()).never_is_true()

			zone:destroy()
		end)

		Test('Stores the reference as-is.', function()
			local part = CreatePart()
			local zone = Zone.new({ cframe = cframe, size = size, reference = part })

			Expect(zone:getReference()).is(part)
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Zone.fromPart', function()
		Test('Creates a zone from the part, stores the part as the reference.', function()
			local cframe = CFrame.new(5, 5, 10) * CFrame.Angles(0, math.pi / 4, 0)
			local size = Vector3.one * 10

			for _, shape in SHAPE_TYPES do
				local part = CreatePart({ CFrame = cframe, Size = size, Shape = (Enum.PartType :: any)[shape] })
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

		Test('WedgePart maps to shape Wedge.', function()
			local part: WedgePart = Create({ className = 'WedgePart' })
			local zone = Zone.fromPart(part)

			Expect(zone:getShape()).is('Wedge')
			zone:destroy()
			part:Destroy()
		end)

		Test('CornerWedgePart maps to shape CornerWedge.', function()
			local part: CornerWedgePart = Create({ className = 'CornerWedgePart' })
			local zone = Zone.fromPart(part)

			Expect(zone:getShape()).is('CornerWedge')
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Zone.fromParts', function()
		Test('Produces one inner zone per part, each referencing its source.', function()
			local seen = {}
			local parts = CreateParts(3)
			local zones = Zone.fromParts(parts)

			Expect(#zones:getZones()).is(#parts)

			for reference, _ in zones:iterReferences() do
				seen[reference] = true
			end
			
			for _, part in parts do
				Expect(seen[part]).is_true()
			end

			zones:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test('Each inner zone independent from its own source.', function()
			local matched = 0
			local partA = CreatePart({ CFrame = CFrame.new(10, 0, 0), Size = Vector3.one * 4, Shape = Enum.PartType.Ball })
			local partB = CreatePart({ CFrame = CFrame.new(-10, 5, 0), Size = Vector3.new(6, 2, 8) })
			local zones = Zone.fromParts({ partA, partB })

			for reference, inner in zones:iterReferences() do
				if inner == nil then
					continue
				end
				if reference == partA then
					Expect(inner:getCFrame()).is(partA.CFrame)
					Expect(inner:getSize()).is(partA.Size)
					Expect(inner:getShape()).is('Ball')
					matched += 1
				elseif reference == partB then
					Expect(inner:getCFrame()).is(partB.CFrame)
					Expect(inner:getSize()).is(partB.Size)
					Expect(inner:getShape()).is('Block')
					matched += 1
				end
			end

			Expect(matched).is(2)
			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Propagates autoSync to every inner zone.', function()
			local matches = 0
			local cframeA = CFrame.new(25, 0, 0)
			local cframeB = CFrame.new(75, 0, 0)
			local partA = CreatePart()
			local partB = CreatePart({ CFrame = CFrame.new(50, 0, 0) })
			local zones = Zone.fromParts({ partA, partB }, { autoSync = true })

			for _, inner in zones:getZones() do
				Expect(inner:isDynamic()).is_true()
			end

			partA.CFrame = cframeA
			partB.CFrame = cframeB
			QuickZone:update(1 / 10)

			for reference, inner in zones:iterReferences() do
				if inner == nil then
					continue
				end
				if reference == partA then
					Expect(inner:getPosition()).is(cframeA.Position)
					matches += 1
				elseif reference == partB then
					Expect(inner:getPosition()).is(cframeB.Position)
					matches += 1
				end
			end

			Expect(matches).is(2)
			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('Zone.fromChildren', function()
		Test('Only direct BasePart children become zones, nested parts are ignored.', function()
			local parentFolder = Instance.new('Folder')
			local childFolder = Instance.new('Folder')
			local zones

			CreatePart().Parent = childFolder
			CreatePart().Parent = parentFolder
			childFolder.Parent = parentFolder
			parentFolder.Parent = workspace
			zones = Zone.fromChildren(parentFolder)

			Expect(#zones:getZones()).is(1)
			zones:destroy()
			parentFolder:Destroy()
		end)

		Test('Updates as children are added and removed.', function()
			local parentFolder = Instance.new('Folder')
			local partA = CreatePart()
			local partB = CreatePart()
			local zones

			partA.Parent = parentFolder
			parentFolder.Parent = workspace
			zones = Zone.fromChildren(parentFolder)

			Expect(#zones:getZones()).is(1)

			partB.Parent = parentFolder
			task.wait()

			Expect(#zones:getZones()).is(2)

			partA:Destroy()
			task.wait()

			Expect(#zones:getZones()).is(1)
			zones:destroy()
			parentFolder:Destroy()
		end)

		Test('Applies autoSync to existing and late children.', function()
			local synced
			local cframeA = CFrame.new(40, 0, 0)
			local cframeB = CFrame.new(99, 0, 0)
			local parentFolder = Instance.new('Folder')
			local partA = CreatePart()
			local partB = CreatePart({ CFrame = CFrame.new(7, 0, 0) })
			local zones

			partA.Parent = parentFolder
			parentFolder.Parent = workspace
			zones = Zone.fromChildren(parentFolder, { autoSync = true })

			for _, inner in zones:getZones() do
				Expect(inner:isDynamic()).is_true()
			end

			partA.CFrame = cframeA
			QuickZone:update(1 / 10)

			for reference, inner in zones:iterReferences() do
				if inner == nil then
					continue
				end
				if reference == partA then
					Expect(inner:getPosition()).is(cframeA.Position)
				end
			end

			partB.Parent = parentFolder
			task.wait()

			partB.CFrame = cframeB
			QuickZone:update(1 / 10)

			for reference, inner in zones:iterReferences() do
				if inner == nil then
					continue
				end
				if reference == partB then
					Expect(inner:isDynamic()).is_true()
					Expect(inner:getPosition()).is(cframeB.Position)
					synced = true
				end
			end

			Expect(synced).is_true()
			zones:destroy()
			parentFolder:Destroy()
		end)
	end)

	Describe('Zone.fromDescendants', function()
		Test('Every BasePart in the descendant tree becomes a zone, not just direct children.', function()
			local parentFolder = Instance.new('Folder')
			local childFolder = Instance.new('Folder')
			local zones

			CreatePart().Parent = childFolder
			CreatePart().Parent = parentFolder
			childFolder.Parent = parentFolder
			parentFolder.Parent = workspace
			zones = Zone.fromDescendants(parentFolder)

			Expect(#zones:getZones()).is(2)
			zones:destroy()
			parentFolder:Destroy()
		end)

		Test('Updates as descendants are added and removed.', function()
			local parentFolder = Instance.new('Folder')
			local childFolder = Instance.new('Folder')
			local partA = CreatePart()
			local partB = CreatePart()
			local zones

			partA.Parent = childFolder
			childFolder.Parent = parentFolder
			parentFolder.Parent = workspace
			zones = Zone.fromDescendants(parentFolder)

			Expect(#zones:getZones()).is(1)

			partB.Parent = childFolder
			task.wait()

			Expect(#zones:getZones()).is(2)

			partA:Destroy()
			task.wait()

			Expect(#zones:getZones()).is(1)
			zones:destroy()
			parentFolder:Destroy()
		end)

		Test('Applies autoSync to existing and late descendants.', function()
			local synced
			local cframeA = CFrame.new(33, 0, 0)
			local cframeB = CFrame.new(-12, 0, 0)
			local parentFolder = Instance.new('Folder')
			local childFolder = Instance.new('Folder')
			local partA = CreatePart()
			local partB = CreatePart()
			local zones

			partA.Parent = childFolder
			childFolder.Parent = parentFolder
			parentFolder.Parent = workspace
			zones = Zone.fromDescendants(parentFolder, { autoSync = true })

			for _, inner in zones:getZones() do
				Expect(inner:isDynamic()).is_true()
			end

			partA.CFrame = cframeA
			QuickZone:update(1 / 10)

			for reference, inner in zones:iterReferences() do
				if inner == nil then
					continue
				end
				if reference == partA then
					Expect(inner:getPosition()).is(cframeA.Position)
				end
			end

			partB.Parent = childFolder
			task.wait()

			partB.CFrame = cframeB
			QuickZone:update(1 / 10)

			for reference, inner in zones:iterReferences() do
				if inner == nil then
					continue
				end
				if reference == partB then
					Expect(inner:isDynamic()).is_true()
					Expect(inner:getPosition()).is(cframeB.Position)
					synced = true
				end
			end

			Expect(synced).is_true()
			zones:destroy()
			parentFolder:Destroy()
		end)
	end)

	Describe('Zone.fromTag', function()
		Test('Instances tagged before construction are picked up at construction time.', function()
			local tag = 'QZ_FROM_TAG_PRE_EXISTING'
			local partA = CreatePart()
			local partB = CreatePart()
			local zones

			CollectionService:AddTag(partA, tag)
			CollectionService:AddTag(partB, tag)
			zones = Zone.fromTag(tag)

			Expect(#zones:getZones()).is(2)
			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Updates as tags are added and removed at runtime.', function()
			local tag = 'QZ_FROM_TAG_RUNTIME'
			local partA = CreatePart()
			local partB = CreatePart()
			local zones

			CollectionService:AddTag(partA, tag)
			zones = Zone.fromTag(tag)

			Expect(#zones:getZones()).is(1)

			CollectionService:AddTag(partB, tag)
			task.wait()

			Expect(#zones:getZones()).is(2)

			CollectionService:RemoveTag(partA, tag)
			task.wait()

			Expect(#zones:getZones()).is(1)
			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Tagging a container creates a zone per BasePart descendant.', function()
			local tag = 'QZ_FROM_TAG_CONTAINER'
			local model = Instance.new('Model')
			local folder = Instance.new('Folder')
			local partA = CreatePart()
			local partB = CreatePart()
			local partC = CreatePart()
			local zones

			partB.Parent = folder
			partA.Parent = model
			folder.Parent = model
			model.Parent = workspace
			zones = Zone.fromTag(tag)

			CollectionService:AddTag(model, tag)
			task.wait()

			Expect(#zones:getZones()).is(2)

			partC.Parent = folder
			task.wait()

			Expect(#zones:getZones()).is(3)

			zones:destroy()
			model:Destroy()
			folder:Destroy()
			partA:Destroy()
			partB:Destroy()
			partC:Destroy()
		end)

		Test('Overlapping tags, so a zone can lose one of them.', function()
			local tag = 'QZ_FROM_TAG_OVERLAP'
			local model = Instance.new('Model')
			local part = CreatePart()
			local zones

			part.Parent = model
			model.Parent = workspace
			zones = Zone.fromTag(tag)

			-- Tag the model
			CollectionService:AddTag(model, tag)
			task.wait()

			Expect(#zones:getZones()).is(1)

			-- Tag the part directly
			CollectionService:AddTag(part, tag)
			task.wait()

			Expect(#zones:getZones()).is(1)

			-- Remove tag from model
			CollectionService:RemoveTag(model, tag)
			task.wait()

			Expect(#zones:getZones()).is(1)

			-- Remove tag from part
			CollectionService:RemoveTag(part, tag)
			task.wait()

			Expect(#zones:getZones()).is(0)
			zones:destroy()
			model:Destroy()
			part:Destroy()
		end)

		Test('Tagged container outside workspace drops zones, re-parenting restores them.', function()
			local tag = 'QZ_FROM_TAG_ANCESTRY'
			local model = Instance.new('Model')
			local part = CreatePart()
			local zones

			part.Parent = model
			model.Parent = workspace
			CollectionService:AddTag(model, tag)
			zones = Zone.fromTag(tag)

			Expect(#zones:getZones()).is(1)

			model.Parent = nil
			task.wait()

			Expect(#zones:getZones()).is(0)

			model.Parent = workspace
			task.wait()

			Expect(#zones:getZones()).is(1)
			zones:destroy()
			model:Destroy()
			part:Destroy()
		end)
	end)

	Describe('Zone:setAutoSync', function()
		Test('Enabling on a static zone promotes it to dynamic.', function()
			local part = CreatePart()
			local zone = Zone.fromPart(part)

			Expect(zone:isDynamic()).never_is_true()
			Expect(zone:setAutoSync(true)).is(zone)
			Expect(zone:isDynamic()).is_true()

			zone:destroy()
			part:Destroy()
		end)

		Test('Zone CFrame tracks its reference on every tick.', function()
			local cframe = CFrame.new(50, 0, 0)
			local part = CreatePart()
			local zone = Zone.fromPart(part, { autoSync = true })

			part.CFrame = cframe
			QuickZone:update(1 / 10)

			Expect(zone:getCFrame()).is(cframe)
			zone:destroy()
			part:Destroy()
		end)

		Test('Disabling stops the zone at its last position.', function()
			local cframe = CFrame.new(10, 0, 0)
			local part = CreatePart()
			local zone = Zone.fromPart(part, { autoSync = true })

			part.CFrame = cframe
			QuickZone:update(1 / 10)

			Expect(zone:getPosition()).is(cframe.Position)

			zone:setAutoSync(false)
			part.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)

			Expect(zone:getPosition()).is(cframe.Position)
			zone:destroy()
			part:Destroy()
		end)

		Test('Reference size changes propagate to the zone.', function()
			local size = Vector3.one * 20
			local part = CreatePart({ Size = Vector3.one * 10 })
			local zone = Zone.fromPart(part, { autoSync = true })

			part.Size = size
			task.wait()

			Expect(zone:getSize()).is(size)
			zone:destroy()
			part:Destroy()
		end)

		Test('Reference shape changes propagate to the zone.', function()
			local part = CreatePart({ Shape = Enum.PartType.Block })
			local zone = Zone.fromPart(part, { autoSync = true })

			part.Shape = Enum.PartType.Ball
			task.wait()

			Expect(zone:getShape()).is('Ball')
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Zone:setReference', function()
		Test('Round-trips the reference.', function()
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })

			Expect(zone:getReference()).is()
			Expect(zone:setReference(part)).is(zone)
			Expect(zone:getReference()).is(part)
			Expect(zone:setReference()).is(zone)
			Expect(zone:getReference()).is()

			zone:destroy()
			part:Destroy()
		end)

		Test('Rewires autoSync to the new reference, disconnecting from the old one.', function()
			local size = Vector3.one * 20
			local partA = CreatePart({ Size = Vector3.one * 10 })
			local partB = CreatePart({ Size = Vector3.one * 10 })
			local zone = Zone.fromPart(partA, { autoSync = true })

			zone:setReference(partB)

			partB.Size = size
			task.wait()

			Expect(zone:getSize()).is(size)

			partA.Size = Vector3.one * 77
			task.wait()

			Expect(zone:getSize()).is(size)
			zone:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('Zone:sync', function()
		Test('Gets details from the reference part.', function()
			local cframe = CFrame.new(50, 0, 0)
			local size = Vector3.one * 20
			local part = CreatePart({ Size = Vector3.one * 10 })
			local zone = Zone.fromPart(part)

			part.CFrame = cframe
			part.Size = size
			part.Shape = Enum.PartType.Ball

			Expect(zone:sync()).is(zone)
			Expect(zone:getCFrame()).is(cframe)
			Expect(zone:getSize()).is(size)
			Expect(zone:getShape()).is('Ball')

			zone:destroy()
			part:Destroy()
		end)

		Test('Reads WorldCFrame from an Attachment reference.', function()
			local cframe = CFrame.new(50, 0, 0)
			local attachment = Instance.new('Attachment')
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10, reference = attachment })

			attachment.WorldCFrame = cframe
			attachment.Parent = workspace
			zone:sync()

			Expect(zone:getCFrame()).is(cframe)
			zone:destroy()
			attachment:Destroy()
		end)
	end)

	Describe('Zone:setDynamic', function()
		Test('Dynamic to static preserves position during the change.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10, isDynamic = true })

			zone:setCFrame(CFrame.new(100, 0, 0))

			Expect(zone:setDynamic(false)).is(zone)
			Expect(zone:isPointInside(Vector3.new(100, 0, 0))).is_true()
			Expect(zone:isPointInside(Vector3.new(0, 0, 0))).never_is_true()
			zone:destroy()
		end)

		Test('Dynamic to static with autoSync on turns autoSync off.', function()
			local part = CreatePart({ Size = Vector3.one * 10 })
			local zone = Zone.fromPart(part, { autoSync = true })

			Expect(zone:isDynamic()).is_true()

			zone:setDynamic(false)
			part.Size = Vector3.one * 50
			task.wait()

			Expect(zone:getSize()).is(Vector3.one * 10)
			zone:destroy()
			part:Destroy()
		end)

		Test('Static to dynamic moves it to the dynamic tree, so later moves update on tick.', function()
			local origin = Vector3.new(80000, 0, 0)
			local far = Vector3.new(80500, 0, 0)
			local zone = Zone.new({ cframe = CFrame.new(origin), size = Vector3.one * 10 })

			QuickZone:rebuild()
			
			Expect(zone:isDynamic()).never_is_true()
			Expect(QuickZone:getZonesAtPoint(origin)).has_value(zone)

			zone:setDynamic(true)

			Expect(zone:isDynamic()).is_true()

			zone:setCFrame(CFrame.new(far))
			QuickZone:update(1 / 10)

			Expect(QuickZone:getZonesAtPoint(far)).has_value(zone)
			Expect(QuickZone:getZonesAtPoint(origin)).never_has_value(zone)
			zone:destroy()
		end)
	end)

	Describe('Zone:setCFrame', function()
		Test('CFrame round-trips through getCFrame, preserving both position and rotation.', function()
			local cframe = CFrame.Angles(0, math.pi / 4, 0) + Vector3.new(10, 15, 20)
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 5.5 })

			Expect(zone:setCFrame(cframe)).is(zone)
			Expect(zone:getCFrame()).is(cframe)
			zone:destroy()
		end)

		Test('Zone updates after setCFrame, no tick.', function()
			local point = Vector3.zero
			local cframe = CFrame.new(0, 0, 15)
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10, isDynamic = true })

			Expect(zone:isPointInside(point)).is_true()

			zone:setCFrame(cframe)

			Expect(zone:isPointInside(cframe.Position)).is_true()
			Expect(zone:isPointInside(point)).never_is_true()
			zone:destroy()
		end)
	end)

	Describe('Zone:setPosition', function()
		Test('Position update preserves rotation.', function()
			local rotation = CFrame.Angles(0, math.pi / 4, 0)
			local position = Vector3.new(25, 0, 0)
			local zone = Zone.new({ cframe = rotation, size = Vector3.one * 5.5 })

			Expect(zone:setPosition(position)).is(zone)
			Expect(zone:getPosition()).is(position)
			Expect(zone:getCFrame()).is(rotation + position)
			zone:destroy()
		end)
	end)

	Describe('Zone:setSize', function()
		Test('Shrinking the zone excludes a point that was previously inside.', function()
			local size = Vector3.one * 2.5
			local point = Vector3.new(4, 0, 0)
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })

			Expect(zone:isPointInside(point)).is_true()
			Expect(zone:setSize(size)).is(zone)
			Expect(zone:isPointInside(point)).never_is_true()
			Expect(zone:getSize()).is(size)

			zone:destroy()
		end)
	end)

	Describe('Zone:setShape', function()
		Test('Swapping from Block to Ball changes containment on a corner point.', function()
			local point = Vector3.new(4, 4, 4)
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })

			Expect(zone:isPointInside(point)).is_true()
			Expect(zone:setShape('Ball')).is(zone)
			Expect(zone:getShape()).is('Ball')
			Expect(zone:isPointInside(point)).never_is_true()

			zone:destroy()
		end)
	end)

	Describe('Zone:setMetadata', function()
		Test('Metadata round-trips by identity.', function()
			local metadata = { Name = 'QZ', Value = 1000 }
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })

			Expect(zone:getMetadata()).is()
			Expect(zone:setMetadata(metadata)).is(zone)
			Expect(zone:getMetadata()).is(metadata)
			zone:destroy()
		end)
	end)

	Describe('Zone:getId', function()
		Test('Zones have different IDs.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 5 })
			local zoneB = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 15 })

			Expect(zoneA:getId()).is_a('number')
			Expect(zoneA:getId()).never_is(zoneB:getId())
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Zone:isPointInside', function()
		local size = Vector3.one * 10
		local rotation = CFrame.Angles(0, math.pi / 4, 0)

		Test('Block: checks points of aligned and rotated zones.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = size })
			local zoneB = Zone.new({ cframe = rotation, size = size })

			Expect(zoneA:isPointInside(Vector3.zero)).is_true()
			Expect(zoneA:isPointInside(Vector3.new(4.9, 4.9, 4.9))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(5.1, 0, 0))).never_is_true()
			Expect(zoneA:isPointInside(Vector3.new(100, 0, 0))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.zero))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(4.9, 4.9, 4.9)))).is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(5.1, 0, 0)))).never_is_true()
			Expect(zoneB:isPointInside(rotation:PointToWorldSpace(Vector3.new(100, 0, 0)))).never_is_true()
			Expect(zoneA:isPointInside(Vector3.new(5, 0, 0))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(-5, 0, 0))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(5, 5, 5))).is_true()
			Expect(zoneA:isPointInside(Vector3.new(5, 5, 0))).is_true()

			zoneA:destroy()
			zoneB:destroy()
		end)

		Test('Ball: checks points of aligned and rotated zones.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = size, shape = 'Ball' })
			local zoneB = Zone.new({ cframe = rotation, size = size, shape = 'Ball' })

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

		Test('Cylinder: checks points of aligned and rotated zones.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = size, shape = 'Cylinder' })
			local zoneB = Zone.new({ cframe = rotation, size = size, shape = 'Cylinder' })

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

		Test('Wedge: checks points of aligned and rotated zones.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = size, shape = 'Wedge' })
			local zoneB = Zone.new({ cframe = rotation, size = size, shape = 'Wedge' })

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

		Test('CornerWedge: checks points of aligned and rotated zones.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = size, shape = 'CornerWedge' })
			local zoneB = Zone.new({ cframe = rotation, size = size, shape = 'CornerWedge' })

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

	Describe('Zone:onDestroy', function()
		Test('Connected callbacks fire on destroy, calling the disconnect function unbinds them.', function()
			local firedA, firedB = 0, 0
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })

			zone:onDestroy(function()
				firedA += 1
			end)
			zone:onDestroy(function()
				firedB += 1
			end)()

			zone:destroy()
			Expect(firedA).is(1)
			Expect(firedB).is(0)
		end)
	end)

	-- Zones are covered below.
	Describe('Zones', function()
		Test('Zones:contains only returns true for zones owned by this container.', function()
			local parts = CreateParts(2)
			local zones = Zone.fromParts(parts)
			local outer = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 5 })

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

		Test('Zones:getZones, Zones:getReferences, Zones:iterZones, and Zones:iterReferences each yield every entry once.', function()
			local zoneCount = 0
			local seenZones, seenReferences = {}, {}
			local parts = CreateParts(3)
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

		Test('Propagates setDynamic to every inner zone.', function()
			local parts = CreateParts(2)
			local zones = Zone.fromParts(parts)

			Expect(zones:isDynamic()).never_is_true()
			Expect(zones:setDynamic(true)).is(zones)
			Expect(zones:isDynamic()).is_true()
			for _, inner in zones:getZones() do
				Expect(inner:isDynamic()).is_true()
			end

			zones:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test('Propagates setMetadata to every inner zone.', function()
			local metadata = { Value = 5 }
			local parts = CreateParts(2)
			local zones = Zone.fromParts(parts)

			Expect(zones:setMetadata(metadata)).is(zones)
			Expect(zones:getMetadata()).is(metadata)
			for _, inner in zones:getZones() do
				Expect(inner:getMetadata()).is(metadata)
			end

			zones:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test('Zones:setAutoSync makes every inner zone dynamic and follow its reference.', function()
			local matches = 0
			local cframeA = CFrame.new(50, 0, 0)
			local cframeB = CFrame.new(150, 0, 0)
			local partA = CreatePart()
			local partB = CreatePart({ CFrame = CFrame.new(100, 0, 0) })
			local zones = Zone.fromParts({ partA, partB })

			Expect(zones:setAutoSync(true)).is(zones)
			for _, inner in zones:getZones() do
				Expect(inner:isDynamic()).is_true()
			end

			partA.CFrame = cframeA
			partB.CFrame = cframeB
			QuickZone:update(1 / 10)

			for reference, inner in zones:iterReferences() do
				if inner == nil then
					continue
				end
				if reference == partA then
					Expect(inner:getPosition()).is(cframeA.Position)
					matches += 1
				elseif reference == partB then
					Expect(inner:getPosition()).is(cframeB.Position)
					matches += 1
				end
			end

			Expect(matches).is(2)
			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Zones:sync pulls every inner zone from its own reference.', function()
			local matches = 0
			local partA = CreatePart()
			local partB = CreatePart({ CFrame = CFrame.new(100, 0, 0) })
			local zones = Zone.fromParts({ partA, partB }, { isDynamic = true })

			partA.CFrame = CFrame.new(50, 0, 0)
			partB.CFrame = CFrame.new(150, 0, 0)

			Expect(zones:sync()).is(zones)
			for reference, inner in zones:iterReferences() do
				if inner == nil then
					continue
				end
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

		Test('Zones:isPointInside returns true if the point is inside any inner zone.', function()
			local partA = CreatePart({ Size = Vector3.one * 10 })
			local partB = CreatePart({ CFrame = CFrame.new(100, 0, 0), Size = Vector3.one * 10 })
			local zones = Zone.fromParts({ partA, partB })

			Expect(zones:isPointInside(Vector3.zero)).is_true()
			Expect(zones:isPointInside(Vector3.new(100, 0, 0))).is_true()
			Expect(zones:isPointInside(Vector3.new(50, 0, 0))).never_is_true()

			zones:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Connected callbacks fire on destroy, calling the disconnect function unbinds them.', function()
			local firedA, firedB = 0, 0
			local parts = CreateParts(2)
			local zones = Zone.fromParts(parts)

			zones:onDestroy(function()
				firedA += 1
			end)
			zones:onDestroy(function()
				firedB += 1
			end)()

			for _, part in parts do
				part:Destroy()
			end

			zones:destroy()
			Expect(firedA).is(1)
			Expect(firedB).is(0)
		end)
	end)
end
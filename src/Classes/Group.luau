--!strict
--[=[ 
	@class Group

	Groups represent a collection of entities that should be tracked by the system.

	:::info Observer
	Every entity must be in a group to be observed.
	:::
]=]

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)
local Entities = require(script.Parent.Parent.Core.Entities)
local Groups = require(script.Parent.Parent.Core.Groups)
local References = require(script.Parent.Parent.Core.References)
local Registry = require(script.Parent.Parent.Core.Registry)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Log = require(script.Parent.Parent.Utils.Log)
local Snapshot = require(script.Parent.Parent.Utils.Snapshot)
local TagWatcher = require(script.Parent.Parent.Utils.TagWatcher)

local IS_CLIENT = RunService:IsClient()

local Group = {}
Group.__index = Group

local ManagedGroup: any

--[=[ 
	Creates a generic Group. 
	Groups manage collections of Entities (any instance with a position in the world like BaseParts, Models, Attachments, etc.) that Observers should track.

	```lua
	local myGroup = Group.new({
		entities = { NPC1, NPC2, NPC3 }, -- Add entities
		autoClean = true, -- Entities in group are cleaned up when entities are destroyed
	})
	```

	@tag Constructor
	@tag Chainable
	@param config { entities: { T }?, autoClean: boolean? }?
	@return Group
]=]
function Group.new<T>(config: {
	entities: { T }?,
	autoClean: boolean?,
}?): Types.Group<T>
	local id = Registry.nextGroupId
	Registry.nextGroupId += 1

	local autoClean = Config.Group.autoClean
	if config and config.autoClean ~= nil then
		autoClean = config.autoClean
	end

	local self: Types.InternalGroup<T> = setmetatable({
		id = id,
		phase = 'alive',
	}, Group) :: any

	Registry.groups[id] = self
	Groups.create(id, autoClean)

	if config and config.entities then
		Groups.addBulk(id, config.entities)
	end

	return self
end

--[=[ 
	Creates a dynamic Group that automatically tracks all instances with a specific tag.
	Instances are only tracked while they are descendants of the Workspace.

	Its members are kept for you, so `add`, `addBulk`, `remove`, `removeBulk`, `clear` and `setAutoClean` only warn.

	@tag Constructor
	@tag Chainable
	@param tag string
	@return Group
]=]
function Group.fromTag(tag: string): Types.Group<Types.Entity>
	local group = Group.new({ autoClean = false, entities = nil }) :: Types.InternalGroup<Types.Entity>
	setmetatable(group :: any, ManagedGroup)

	local id = group.id
	local stopWatch = TagWatcher.watch(tag, function(instance)
		if instance:IsDescendantOf(workspace) then
			Groups.addEntity(id, instance :: any)
		else
			Groups.removeEntity(id, instance :: any)
		end
	end, function(instance)
		Groups.removeEntity(id, instance :: any)
	end, Entities.canTrack)

	group:onDestroy(stopWatch)

	return group
end

--[=[ 
	Returns a Group that automatically tracks all Players in the server.

	Its members are kept for you, so `add`, `addBulk`, `remove`, `removeBulk`, `clear` and `setAutoClean` only warn.

	:::info Behavior
	* Automatically tracks the `HumanoidRootPart` of every player.
	* Handles `PlayerAdded` and `CharacterAdded` internally.
	:::

	@tag Constructor
	@tag Chainable
	@return Group
]=]
function Group.players(): Types.Group<Player>
	local group = Group.new({ autoClean = false, entities = nil }) :: Types.InternalGroup<Player>
	setmetatable(group :: any, ManagedGroup)

	local conn = Players.PlayerAdded:Connect(function(player)
		Groups.add(group.id, player)
	end)

	for _, player in Players:GetPlayers() do
		Groups.add(group.id, player)
	end

	group:onDestroy(function()
		conn:Disconnect()
	end)

	return group
end

--[=[ 
	Returns a Group that tracks only the LocalPlayer.

	Its members are kept for you, so `add`, `addBulk`, `remove`, `removeBulk`, `clear` and `setAutoClean` only warn.

	:::info Behavior
	* Automatically tracks the `HumanoidRootPart` of the local player.
	* Handles `CharacterAdded` internally.
	:::

	@client
	@tag Constructor
	@tag Chainable
	@return Group
]=]
function Group.localPlayer(): Types.Group<Player>
	if not IS_CLIENT then
		Log.fatal('Group.localPlayer() can only be called on the Client.', nil)
	end

	local group = Group.new({ autoClean = false, entities = nil }) :: Types.InternalGroup<Player>
	setmetatable(group :: any, ManagedGroup)

	Groups.add(group.id, Players.LocalPlayer)

	return group
end

--[=[ 
	Enables or disables automatic cleanup for Instances in this group.
	When enabled, if an Instance is Destroyed() or parented to nil, it will be 
	automatically removed from this group.

	@tag Chainable
	@method setAutoClean
	@within Group
	@param enabled boolean
	@return Group
]=]
function Group.setAutoClean(self: Types.InternalGroup, enabled: boolean): Types.Group
	Groups.setAutoClean(self.id, not not enabled)
	return self
end

--[=[ 
	Adds an entity to the group.

	#### Example: Adding Different Entity Types
	```lua
	-- Adding a BasePart and a Model
	myGroup:add(workspace.Part):add(workspace.NPCModel)

	-- Adding a custom table
	local spell = {
		CFrame = CFrame.new(0, 10, 0),
		Name = 'Fireball'
	}
	myGroup:add(spell)
	```

	:::info Strategy Detection
	QuickZone automatically determines how to track the entity's position:
	* **BasePart:** Uses `Position`
	* **Model:** Uses `PrimaryPart.Position` or `GetPivot()`
	* **Attachment/Bone:** Uses `WorldPosition`
	* **Camera:** Uses `CFrame`
	* **Table:** Looks for `.Position`, `.CFrame`, `.Transform`, `.WorldPosition`, or `:GetPivot()`.
	:::

	@tag Chainable
	@method add
	@within Group
	@param entity any -- The object to track.
	@return Group
]=]
function Group.add(self: Types.InternalGroup, entity: any): Types.Group
	Groups.add(self.id, entity)
	return self
end

--[=[ 
	Adds multiple entities to the group.

	```lua
	-- Add an entire folder of NPCs at once
	myGroup:addBulk(workspace.Enemies:GetChildren())
	```

	@tag Chainable
	@method addBulk
	@within Group
	@param entities { any } -- Array of entities to add.
	@return Group
]=]
function Group.addBulk(self: Types.InternalGroup, entities: { any }): Types.Group
	Groups.addBulk(self.id, entities)
	return self
end

--[=[ 
	Removes the entity from the group. Removing a player's `HumanoidRootPart` removes the player.

	@tag Chainable
	@method remove
	@within Group
	@param entity any
	@return Group
]=]
function Group.remove(self: Types.InternalGroup, entity: any): Types.Group
	Groups.remove(self.id, entity)
	return self
end

--[=[ 
	Removes multiple entities from the group.
	
	@tag Chainable
	@method removeBulk
	@within Group
	@param entities { any }
	@return Group
]=]
function Group.removeBulk(self: Types.InternalGroup, entities: { any }): Types.Group
	Groups.removeBulk(self.id, entities)
	return self
end

--[=[ 
	Removes all entities from the group.
	This fires 'onExit' events for every entity currently inside a zone.

	@tag Chainable
	@method clear
	@within Group
	@return Group
]=]
function Group.clear(self: Types.InternalGroup): Types.Group
	Groups.clear(self.id)
	return self
end

--[=[ 
	Checks if a specific entity is currently a member of this group.

	@method contains
	@within Group
	@param entity any
	@return boolean
]=]
function Group.contains(self: Types.InternalGroup, entity: any): boolean
	return Groups.contains(self.id, entity)
end

--[=[ 
	Returns the unique internal ID of the group.

	@method getId
	@within Group
	@return number
]=]
function Group.getId(self: Types.InternalGroup): number
	return self.id
end

--[=[ 
	Returns a list of all entities currently belonging to the group.

	@method getEntities
	@within Group
	@return { any }
]=]
function Group.getEntities(self: Types.InternalGroup): { any }
	local members = Entities.groupEntities[self.id] or {}
	local result = table.create(#members)
	for i, entity in ipairs(members) do
		result[i] = References.referenceOf(entity)
	end
	return result
end

--[=[ 
	Iterates over all entities currently belonging to the group, ideal for high-frequency checks.
	Safe to use while entities are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	```lua
	for entity in myGroup:iterEntities() do
		print(entity.Name .. " is in the group!")
	end
	```

	@method iterEntities
	@within Group
	@return () -> any?
]=]
function Group.iterEntities(self: Types.InternalGroup): () -> any?
	local nextEntity = Snapshot.keys(Entities.groupEntityIndices[self.id] or {})

	return function()
		local entity = nextEntity()
		if entity ~= nil then
			return References.referenceOf(entity)
		end
		return nil
	end
end

--[=[ 
	Fires when `destroy()` is called on the group.

	```lua
	local disconnect = myGroup:onDestroy(function()
		print('Group was destroyed!')
	end)
	```

	@tag Event
	@method onDestroy
	@within Group
	@param callback () -> ()
	@return () -> () -- Disconnect function
]=]
function Group.onDestroy(self: Types.InternalGroup, callback: () -> ()): () -> ()
	return Destroyed.connect(self, callback)
end

--[=[ 
	Cleans up the group, removes all tracked entities, and detaches any 
	associated observers.

	Destroying it again does nothing. Its other methods raise an error once it is destroyed.
	
	@tag Destructor
	@method destroy
	@within Group
]=]
function Group.destroy(self: Types.InternalGroup): ()
	-- A callback below may destroy the group again
	if not Destroyed.begin(self) then
		return
	end

	Destroyed.fireCallbacks(self.onDestroyCallbacks)

	Groups.destroy(self.id)
	Registry.groups[self.id] = nil

	Destroyed.finish(self)
end

-- Player and tag groups own their members, so the methods that change them only warn
ManagedGroup = setmetatable({}, { __index = Group }) :: any
ManagedGroup.__index = ManagedGroup

local function refuse(message: string)
	return function(self: Types.InternalGroup)
		Log.warn(message, nil)
		return self
	end
end

ManagedGroup.add = refuse('Cannot manually add to a Managed Group. Ignoring request.')
ManagedGroup.addBulk = refuse('Cannot manually addBulk to a Managed Group. Ignoring request.')
ManagedGroup.remove = refuse('Cannot manually remove from a Managed Group. Ignoring request.')
ManagedGroup.removeBulk = refuse('Cannot manually removeBulk from a Managed Group. Ignoring request.')
ManagedGroup.clear = refuse('Cannot clear a Managed Group. Ignoring request.')
ManagedGroup.setAutoClean = refuse('Cannot set autoClean on a Managed Group. Ignoring request.')

return Group

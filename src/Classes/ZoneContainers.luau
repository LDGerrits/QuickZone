--!strict

local Types = require(script.Parent.Parent.Types)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local TagWatcher = require(script.Parent.Parent.Utils.TagWatcher)
local Zones = require(script.Parent.Zones)

type PartsConfig = Types.PartsConfig

local ZoneContainers = {}

type ZoneClass = { fromPart: (part: BasePart, config: PartsConfig?) -> Types.Zone }

-- Zone gives itself, as it requires this module
local Zone: ZoneClass

function ZoneContainers.setZone(zone: ZoneClass)
	Zone = zone
end

local function fromContainer(
	config: PartsConfig?,
	added: RBXScriptSignal,
	removed: RBXScriptSignal,
	initial: { Instance }
): Types.Zones
	local zones = Zones.new(config) :: Types.InternalZones
	local instanceToZone = {} :: { [Instance]: Types.Zone }

	local function onAdded(instance: Instance)
		if instance:IsA('BasePart') and not instanceToZone[instance] then
			local zone = Zone.fromPart(instance, { isDynamic = zones.dynamic })
			instanceToZone[instance] = zone
			zones:add(zone)
		end
	end

	local function onRemoved(instance: Instance)
		local zone = instanceToZone[instance]
		if zone then
			instanceToZone[instance] = nil
			zone:destroy()
		end
	end

	local addedConn = added:Connect(onAdded)
	local removedConn = removed:Connect(onRemoved)
	for _, instance in initial do
		onAdded(instance)
	end

	zones:onDestroy(function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for instance in instanceToZone do
			onRemoved(instance)
		end
	end)

	return zones
end

--[=[
	Creates and manages a collection of Zones from a static array of BaseParts.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parts { BasePart }
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function ZoneContainers.fromParts(parts: { BasePart }, config: PartsConfig?): Types.Zones
	local zones = Zones.new(config) :: Types.InternalZones
	for _, part in parts do
		if typeof(part) == 'Instance' and part:IsA('BasePart') then
			zones:add(Zone.fromPart(part, { isDynamic = zones.dynamic }))
		end
	end
	return zones
end

--[=[
	Dynamically creates and manages a Zones object from all BaseParts that are 
	direct children of the given Instance. Automatically updates as children are added/removed.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parent Instance
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function ZoneContainers.fromChildren(parent: Instance, config: PartsConfig?): Types.Zones
	return fromContainer(config, parent.ChildAdded, parent.ChildRemoved, parent:GetChildren())
end

--[=[
	Dynamically creates and manages a Zones object from all BaseParts contained 
	anywhere within the given Instance. Automatically updates as descendants are added/removed.
	
	```lua
	local mapZones = QuickZone.Zone.fromDescendants(workspace.HazardFolder)
	```
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parent Instance -- The container (Model, Folder, etc.) to search through.
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function ZoneContainers.fromDescendants(parent: Instance, config: PartsConfig?): Types.Zones
	return fromContainer(config, parent.DescendantAdded, parent.DescendantRemoving, parent:GetDescendants())
end

--[=[
	Dynamically creates and manages Zones for all BaseParts with a specific CollectionService tag.
	If the tag is applied to a container (e.g., a Model or a Folder), it will create zones for all BasePart descendants.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param tag string
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function ZoneContainers.fromTag(tag: string, config: PartsConfig?): Types.Zones
	local zones = Zones.new(config) :: Types.InternalZones

	local containerConnections = {} :: { [Instance]: { RBXScriptConnection } }
	local partDestroyingConnections = {} :: { [BasePart]: RBXScriptConnection }
	local instanceToZone = {} :: { [BasePart]: Types.Zone }
	-- A set rather than a count, as a tagged instance reports itself again each time it moves
	local partClaims = {} :: { [BasePart]: { [Instance]: true } }

	local function dropPart(part: BasePart)
		partClaims[part] = nil
		local deadZone = instanceToZone[part]
		if deadZone then
			instanceToZone[part] = nil
			deadZone:destroy()
		end
		local destroyingConn = partDestroyingConnections[part]
		if destroyingConn then
			destroyingConn:Disconnect()
			partDestroyingConnections[part] = nil
		end
	end

	local function releasePart(part: BasePart, claimer: Instance)
		local claims = partClaims[part]
		if not claims or not claims[claimer] then
			return
		end
		claims[claimer] = nil
		if next(claims) == nil then
			dropPart(part)
		end
	end

	local function addZone(part: BasePart)
		local newZone = Zone.fromPart(part, { isDynamic = zones.dynamic })
		instanceToZone[part] = newZone
		zones:add(newZone)
	end

	local function claimPart(part: BasePart, claimer: Instance)
		local claims = partClaims[part]
		if claims then
			-- A user-destroyed zone returns on a new claim, not on a claimer reporting itself again
			if not claims[claimer] then
				claims[claimer] = true
				if Destroyed.isDestroyed(instanceToZone[part]) then
					addZone(part)
				end
			end
			return
		end
		partClaims[part] = { [claimer] = true }

		addZone(part)

		partDestroyingConnections[part] = part.Destroying:Connect(function()
			dropPart(part)
		end)
	end

	local function releaseInstance(instance: Instance)
		if instance:IsA('BasePart') then
			releasePart(instance, instance)
			return
		end
		local conns = containerConnections[instance]
		if conns then
			conns[1]:Disconnect()
			conns[2]:Disconnect()
			containerConnections[instance] = nil
		end
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA('BasePart') then
				releasePart(descendant, instance)
			end
		end
	end

	local function processTaggedInstance(instance: Instance)
		if not instance:IsDescendantOf(workspace) then
			releaseInstance(instance)
		elseif instance:IsA('BasePart') then
			claimPart(instance, instance)
		elseif not containerConnections[instance] then
			local addedConn = instance.DescendantAdded:Connect(function(descendant)
				if descendant:IsA('BasePart') then
					claimPart(descendant, instance)
				end
			end)
			local removedConn = instance.DescendantRemoving:Connect(function(descendant)
				if descendant:IsA('BasePart') then
					releasePart(descendant, instance)
				end
			end)
			containerConnections[instance] = { addedConn, removedConn }

			for _, descendant in instance:GetDescendants() do
				if descendant:IsA('BasePart') then
					claimPart(descendant, instance)
				end
			end
		end
	end

	local stopWatch = TagWatcher.watch(tag, processTaggedInstance, releaseInstance)

	zones:onDestroy(function()
		stopWatch()
		for _, conn in partDestroyingConnections do
			conn:Disconnect()
		end
		table.clear(containerConnections)
		table.clear(partDestroyingConnections)
		table.clear(instanceToZone)
		table.clear(partClaims)
	end)

	return zones
end

return ZoneContainers

--!strict

local Types = require(script.Parent.Parent.Types)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local ZoneChanges = require(script.Parent.ZoneChanges)

local State = {
	nextZoneId = 1,
	-- Keyed by slot instead of id, slots are reused
	zoneSlotCount = 0,
	freeZoneSlots = {} :: { number },
	zoneSlotIds = {} :: { [number]: number },
	nextObserverId = 1,
	nextGroupId = 1,

	-- Slots of the zones in each tree
	staticSlots = {} :: { [number]: true },
	dynamicSlots = {} :: { [number]: true },

	-- Geometry of every zone, only written through Core/ZoneShapes
	shapeCFrames = {} :: { [number]: CFrame },
	shapeHalfSizes = {} :: { [number]: Vector3 },
	-- Half size the shape fills, as a Ball fills its smallest side and a Cylinder its smallest cross-section
	shapeExtents = {} :: { [number]: Vector3 },
	shapeTypes = {} :: { [number]: number },
	-- The part a Mesh zone queries
	shapeParts = {} :: { [number]: BasePart },

	-- World-space shape derived from the geometry
	shapePositions = {} :: { [number]: Vector3 },
	shapeRights = {} :: { [number]: Vector3 },
	shapeUps = {} :: { [number]: Vector3 },
	shapeBacks = {} :: { [number]: Vector3 },
	shapeBoundsMin = {} :: { [number]: Vector3 },
	shapeBoundsMax = {} :: { [number]: Vector3 },
	shapeAxisAligned = {} :: { [number]: boolean },
	-- Zones whose leaf is exactly their shape
	treeExact = {} :: { [number]: boolean },
	-- Zones added, moved or changed since their tree was built, which the trees may not find where they are
	staleSlots = {} :: { [number]: true },

	-- Where zones changed per tree
	staticChanges = ZoneChanges.new(),
	dynamicChanges = ZoneChanges.new(),

	staticTree = LinearBVH.new(),
	dynamicTree = LinearBVH.new(),
	staticVersion = 0,
	dynamicVersion = 0,
	logicVersion = 0,

	groups = {} :: { [number]: Types.InternalGroup },
	groupToObservers = {} :: { [number]: { [number]: boolean } },
	groupEntityCleanups = {} :: { [number]: { [any]: RBXScriptConnection } },
	entityToGroups = {} :: { [Types.Entity]: { [number]: boolean } },
	entityData = {} :: { [Types.Entity]: Types.EntityData },
	entityToObservers = {} :: { [Types.Entity]: { [number]: boolean } },
	-- Only the entity side is weak: a reference lives as long as its entity, also when nothing else holds it,
	-- and an entity nothing else holds can still go
	entityToReference = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Types.Entity]: any },
	referenceToEntity = (setmetatable({}, { __mode = 'v' }) :: any) :: { [any]: Types.Entity },

	dirtyProfiles = {} :: { [Types.Entity]: boolean },
	dirtyTopology = {} :: { [Types.Entity]: boolean },
	bucketList = {} :: { number },
	buckets = {} :: { [number]: { Types.Entity } },

	-- Entity to the id of its zone
	observerTrackingEntities = {} :: { [number]: { [Types.Entity]: number } },
	observerPriorityMap = {} :: { [number]: number },
	observerEnteredCallbacks = {} :: { [number]: { (any, Types.Zone, Types.Entity) -> () } },
	observerExitedCallbacks = {} :: { [number]: { (any, Types.Zone, Types.Entity) -> () } },
	observerTransitionedCallbacks = {} :: { [number]: { (any, Types.Zone, Types.Entity) -> () } },
	-- Group event trackers of each observer, told when an entity inside it changes groups. Only set while
	-- an observer has some
	observerGroupTrackers = {} :: { [number]: { (entity: any, destroyedGroupId: number?) -> () } },
	observerEnabled = {} :: { [number]: boolean },
	observerSafety = {} :: { [number]: boolean },
	observerUpdateRate = {} :: { [number]: number },
	observerPrecisionSq = {} :: { [number]: number },
	observerDynamicCount = {} :: { [number]: number },
	observerStaticCount = {} :: { [number]: number },

	autoSyncZones = {} :: { [number]: Types.InternalZone },
	zoneAttachedObservers = {} :: { [number]: { number } },
	-- Observer of zones attached to exactly one
	zoneSoleObserver = {} :: { [number]: number },
	-- Zone id to the number of entities observers have in it, only written through Core/Memberships
	zoneOccupants = {} :: { [number]: number },
	zoneIdToZoneObj = {} :: { [number]: Types.InternalZone },
	-- Ids of zones a Zones is destroying, so entities don't move from one to the next on the way out
	zonesBeingDestroyed = {} :: { [number]: true },
	zoneSlotToZoneObj = {} :: { [number]: Types.InternalZone },
	observerIdToObserverObj = {} :: { [number]: Types.InternalObserver },
}

return State

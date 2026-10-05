--!strict

local Types = require(script.Parent.Parent.Types)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local ZoneChanges = require(script.Parent.ZoneChanges)

local State = {
	nextZoneId = 1,
	-- Keyed by slot instead of id, slots are reused
	zoneSlotCount = 0,
	freeZoneSlots = {} :: { number },
	-- Destroyed zones' slots, free after the next rebuild
	releasedZoneSlots = {} :: { number },
	zoneSlotIds = {} :: { [number]: number },
	nextObserverId = 1,
	nextGroupId = 1,

	staticCFrames = {} :: { [number]: CFrame },
	staticHalfSizes = {} :: { [number]: Vector3 },
	staticTypes = {} :: { [number]: number },
	staticMeshes = {} :: { [number]: BasePart },

	dynamicCFrames = {} :: { [number]: CFrame },
	dynamicHalfSizes = {} :: { [number]: Vector3 },
	dynamicTypes = {} :: { [number]: number },
	dynamicMeshes = {} :: { [number]: BasePart },

	-- World-space shape of every zone
	shapeTypes = {} :: { [number]: number },
	shapeHalfSizes = {} :: { [number]: Vector3 },
	shapeParts = {} :: { [number]: BasePart },
	shapePositions = {} :: { [number]: Vector3 },
	shapeRights = {} :: { [number]: Vector3 },
	shapeUps = {} :: { [number]: Vector3 },
	shapeBacks = {} :: { [number]: Vector3 },
	shapeBoundsMin = {} :: { [number]: Vector3 },
	shapeBoundsMax = {} :: { [number]: Vector3 },
	shapeAxisAligned = {} :: { [number]: boolean },
	-- Zones whose leaf is exactly their shape
	treeExact = {} :: { [number]: boolean },

	-- Where zones changed per tree
	staticChanges = ZoneChanges.new(),
	dynamicChanges = ZoneChanges.new(),

	staticTree = LinearBVH.new(),
	dynamicTree = LinearBVH.new(),
	pendingStaticRebuild = false,
	pendingDynamicRebuild = false,
	staticVersion = 0,
	dynamicVersion = 0,
	logicVersion = 0,

	groups = {} :: { [number]: Types.InternalGroup },
	groupToObservers = {} :: { [number]: { [number]: boolean } },
	groupEntityCleanups = {} :: { [number]: { [any]: RBXScriptConnection } },
	entityToGroups = {} :: { [Types.Entity]: { [number]: boolean } },
	entityData = {} :: { [Types.Entity]: Types.EntityData },
	entityToObservers = {} :: { [Types.Entity]: { [number]: boolean } },
	entityToReference = (setmetatable({}, { __mode = 'kv' }) :: any) :: { [Types.Entity]: any },
	referenceToEntity = (setmetatable({}, { __mode = 'kv' }) :: any) :: { [any]: Types.Entity },

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
	observerEnabled = {} :: { [number]: boolean },
	observerSafety = {} :: { [number]: boolean },
	observerUpdateRate = {} :: { [number]: number },
	observerPrecisionSq = {} :: { [number]: number },
	observerDynamicCount = {} :: { [number]: number },
	observerStaticCount = {} :: { [number]: number },
	-- Ids of zones the observer detached from, whose entities may still be in them
	observerDetachedZones = {} :: { [number]: { [number]: boolean } },

	autoSyncZones = {} :: { [number]: Types.InternalZone },
	zoneAttachedObservers = {} :: { [number]: { number } },
	-- Observer of zones attached to exactly one
	zoneSoleObserver = {} :: { [number]: number },
	zoneIdToZoneObj = {} :: { [number]: Types.InternalZone },
	zoneSlotToZoneObj = {} :: { [number]: Types.InternalZone },
	observerIdToObserverObj = {} :: { [number]: Types.InternalObserver },
}

return State

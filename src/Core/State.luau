--!strict

local Types = require(script.Parent.Parent.Types)

local State = {
	nextZoneId = 1,
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

	staticTree = { buffer = buffer.create(0), count = 0, cost = 0, refitSkips = 0, membersChanged = false } :: Types.Tree,
	dynamicTree = { buffer = buffer.create(0), count = 0, cost = 0, refitSkips = 0, membersChanged = false } :: Types.Tree,
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

	observerTrackingEntities = {} :: { [number]: { [Types.Entity]: boolean } },
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

	autoSyncZones = {} :: { [number]: Types.InternalZone },
	zoneAttachedObservers = {} :: { [number]: { number } },
	-- Observer of zones attached to exactly one
	zoneSoleObserver = {} :: { [number]: number },
	zoneIdToZoneObj = {} :: { [number]: Types.InternalZone },
	observerIdToObserverObj = {} :: { [number]: Types.InternalObserver },
}

return State

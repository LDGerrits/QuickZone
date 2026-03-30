--!strict

local Types = require(script.Parent.Parent.Types)

local State = {
	nextZoneId = 1,
	nextObserverId = 1,
	nextGroupId = 1,

	staticCFrames = {} :: { [number]: CFrame },
	staticHalfSizes = {} :: { [number]: Vector3 },
	staticTypes = {} :: { [number]: number },

	dynamicCFrames = {} :: { [number]: CFrame },
	dynamicHalfSizes = {} :: { [number]: Vector3 },
	dynamicTypes = {} :: { [number]: number },

	staticTree = { nodes = {}, count = 0 } :: Types.Tree,
	dynamicTree = { nodes = {}, count = 0 } :: Types.Tree,
	pendingStaticRebuild = false,
	pendingDynamicRebuild = false,
	staticVersion = 1,
	dynamicVersion = 1,
	logicVersion = 1,

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
	zoneIdToZoneObj = {} :: { [number]: Types.InternalZone },
	observerIdToObserverObj = {} :: { [number]: Types.InternalObserver },
}

return State

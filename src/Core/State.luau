--!strict

local Types = require(script.Parent.Parent.Types)

local State = {}

State.nextZoneId = 1
State.nextObserverId = 1
State.nextGroupId = 1

State.staticCFrames = {} :: { [number]: CFrame }
State.staticHalfSizes = {} :: { [number]: Vector3 }
State.staticTypes = {} :: { [number]: number }

State.dynamicCFrames = {} :: { [number]: CFrame }
State.dynamicHalfSizes = {} :: { [number]: Vector3 }
State.dynamicTypes = {} :: { [number]: number }

State.staticTree = { nodes = {}, count = 0 } :: Types.Tree
State.dynamicTree = { nodes = {}, count = 0 } :: Types.Tree
State.pendingStaticRebuild = false
State.pendingDynamicRebuild = false
State.staticVersion = 1
State.dynamicVersion = 1
State.logicVersion = 1

State.groups = {} :: { [number]: Types.InternalGroup<any> }
State.groupToObservers = {} :: { [number]: { [number]: boolean } }
State.groupEntityCleanups = {} :: { [number]: { [any]: RBXScriptConnection } }
State.entityToGroups = {} :: { [Types.Entity]: { [number]: boolean } }
State.entityData = {} :: { [Types.Entity]: Types.EntityData }
State.entityToObservers = {} :: { [Types.Entity]: { [number]: boolean } }
State.entityToPlayer = {} :: { [Types.Entity]: Player }
State.entityToReference = (setmetatable({}, { __mode = 'kv' }) :: any) :: { [Types.Entity]: any }
State.referenceToEntity = (setmetatable({}, { __mode = 'kv' }) :: any) :: { [any]: Types.Entity }

State.dirtyProfiles = {} :: { [Types.Entity]: boolean }
State.dirtyTopology = {} :: { [Types.Entity]: boolean }
State.bucketList = {} :: { number }
State.buckets = {} :: { [number]: { Types.Entity } }

State.observerTrackingEntities = {} :: { [number]: { [Types.Entity]: boolean } }
State.observerPriorityMap = {} :: { [number]: number }
State.observerEnteredCallbacks = {} :: { [number]: { (Types.Entity, Types.Zone) -> () } }
State.observerExitedCallbacks = {} :: { [number]: { (Types.Entity, Types.Zone) -> () } }
State.observerTransitionedCallbacks = {} :: { [number]: { (Types.Entity, Types.Zone, Types.Zone) -> () } }
State.observerEnabled = {} :: { [number]: boolean }
State.observerSafety = {} :: { [number]: boolean }
State.observerUpdateRate = {} :: { [number]: number }
State.observerPrecisionSq = {} :: { [number]: number }
State.observerDynamicCount = {} :: { [number]: number }
State.observerStaticCount = {} :: { [number]: number }

State.autoSyncZones = {} :: { [number]: Types.InternalZone }
State.zoneAttachedObservers = {} :: { [number]: { number } }
State.zoneIdToZoneObj = {} :: { [number]: Types.InternalZone }
State.observerIdToObserverObj = {} :: { [number]: Types.InternalObserver<any> }

return State

--!strict

local Types = require(script.Parent.Types)

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

State.staticRootNode = nil :: Types.Node?
State.dynamicRootNode = nil :: Types.Node?
State.pendingStaticRebuild = false
State.pendingDynamicRebuild = false
State.isDirty = false -- Forces spatial query for every entity

State.groups = {} :: { [number]: Types.InternalGroup }
State.groupToObservers = {} :: { [number]: { [number]: boolean } }
State.groupList = {} :: { Types.InternalGroup }
State.entityToGroup = {} :: { [Types.Entity]: number }
State.entityMetadata = {} :: { [Types.Entity]: { [number]: any } }

State.observerTrackingEntities = {} :: { [number]: { [Types.Entity]: boolean } }
State.observerPriorityMap = {} :: { [number]: number }
State.observerEnteredCallbacks = {} :: { [number]: { Types.Callback } }
State.observerExitedCallbacks = {} :: { [number]: { Types.Callback } }
State.observerEnabled = {} :: { [number]: boolean }

State.zoneAttachedObservers = {} :: { [number]: { number } }
State.zoneIdToZoneObj = {} :: { [number]: Types.InternalZone }
State.observerIdToObserverObj = {} :: { [number]: Types.InternalObserver }

return State

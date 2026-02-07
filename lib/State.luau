--!strict

local Types = require(script.Parent.Types)

local State = {}

-- IDs
State.nextZoneId = 1
State.nextGroupId = 1

-- Geometry / Spatial
State.objects = {} :: { Types.BoundingVolume }
State.rootNode = nil :: Types.Node?
State.pendingRebuild = false
State.isDirty = false
State.frameBudget = 1 / 1000

-- Item storage
State.items = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Types.Item]: Types.ItemData }
State.itemCustomData = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Types.Item]: { [number]: any } }

-- Maps
State.groupActiveMembers = {} :: { [number]: { [Types.Item]: boolean } }
State.groupPriorityMap = {} :: { [number]: number }
State.groupEnteredCallbacks = {} :: { [number]: { Types.Callback } }
State.groupExitedCallbacks = {} :: { [number]: { Types.Callback } }

State.zoneWatchingGroups = {} :: { [number]: { number } }
State.zoneIndexToZoneObj = {} :: { [number]: Types.Zone }
State.groupUIDToGroupObj = {} :: { [number]: Types.Group }

return State

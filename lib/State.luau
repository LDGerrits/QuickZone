--!strict

local Types = require(script.Parent.Types)

local State = {}

State.NextZoneId = 1
State.NextGroupId = 1
State.NextCollectionId = 1

State.Collections = {} :: { [number]: Types.Collection }
State.ItemToCollection = {} :: { [Types.Item]: number }
State.CollectionToGroups = {} :: { [number]: { [number]: boolean } }

State.Objects = {} :: { Types.BoundingVolume }
State.RootNode = nil :: Types.Node?
State.PendingRebuild = false
State.IsDirty = false

State.GroupTrackingItems = {} :: { [number]: { [Types.Item]: boolean } }
State.GroupPriorityMap = {} :: { [number]: number }
State.ItemCustomData = {} :: { [Types.Item]: { [number]: any } }
State.GroupEnteredCallbacks = {} :: { [number]: { Types.Callback } }
State.GroupExitedCallbacks = {} :: { [number]: { Types.Callback } }

State.ZoneBoundGroups = {} :: { [number]: { number } }
State.ZoneIdToZoneObj = {} :: { [number]: Types.Zone }
State.GroupIdToGroupObj = {} :: { [number]: Types.Group }

return State

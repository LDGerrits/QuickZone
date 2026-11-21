--!strict

local Types = require(script.Parent.Parent.Types)

local Registry = {}

Registry.nextZoneId = 1
Registry.nextObserverId = 1
Registry.nextGroupId = 1

Registry.groups = {} :: { [number]: Types.InternalGroup }

Registry.zoneIdToZoneObj = {} :: { [number]: Types.InternalZone }
Registry.zoneSlotToZoneObj = {} :: { [number]: Types.InternalZone }
Registry.autoSyncZones = {} :: { [number]: Types.InternalZone }

Registry.observers = {} :: { [number]: Types.InternalObserver }

return Registry

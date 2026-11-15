--!strict

-- Objects by id, kept low in Core so hot readers can hold them as locals. Writers:
--   groups                                  Groups
--   autoSyncZones                           Zone
--   observers                               Wiring
--   zoneIdToZoneObj, zoneSlotToZoneObj      Wiring

local Types = require(script.Parent.Parent.Types)

local Registry = {}

-- Ids are never reused
Registry.nextZoneId = 1
Registry.nextObserverId = 1
Registry.nextGroupId = 1

-- Live groups, which hold their own state (see Types.InternalGroup)
Registry.groups = {} :: { [number]: Types.InternalGroup }

Registry.zoneIdToZoneObj = {} :: { [number]: Types.InternalZone }
Registry.zoneSlotToZoneObj = {} :: { [number]: Types.InternalZone }
Registry.autoSyncZones = {} :: { [number]: Types.InternalZone }

-- Live observers, which hold their own state (see Types.InternalObserver)
Registry.observers = {} :: { [number]: Types.InternalObserver }

return Registry

--!strict

-- Objects by id and observer settings, kept low in Core so hot readers can hold them as locals. One writer each:
--   groups                               Group     Routing, Memberships, ObserverEvents
--   zoneIdToZoneObj, zoneSlotToZoneObj   Zone      Scheduler, Memberships, Callbacks
--   autoSyncZones                        Zone      Scheduler
--   observerIdToObserverObj              Observer  WorldQueries
--   observer* settings                   Wiring    Scheduler, Routing, Memberships

local Types = require(script.Parent.Parent.Types)

local Registry = {}

-- Ids are never reused
Registry.nextZoneId = 1
Registry.nextObserverId = 1
Registry.nextGroupId = 1

Registry.groups = {} :: { [number]: Types.InternalGroup }

Registry.zoneIdToZoneObj = {} :: { [number]: Types.InternalZone }
Registry.zoneSlotToZoneObj = {} :: { [number]: Types.InternalZone }
Registry.autoSyncZones = {} :: { [number]: Types.InternalZone }

Registry.observerIdToObserverObj = {} :: { [number]: Types.InternalObserver }

Registry.observerPriorityMap = {} :: { [number]: number }
Registry.observerEnabled = {} :: { [number]: boolean }
Registry.observerSafety = {} :: { [number]: boolean }
Registry.observerUpdateRate = {} :: { [number]: number }
Registry.observerPrecisionSq = {} :: { [number]: number }

return Registry

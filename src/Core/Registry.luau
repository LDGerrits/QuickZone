--!strict

-- Every QuickZone object by id, and the settings of each observer. Each table has one writer and is kept here, low
-- in Core, so the modules that read it every tick can hold it as a local:
--
--   tables                                  writer      hot readers
--   groups                                  Group       Routing, Memberships, ObserverEvents
--   zoneIdToZoneObj, zoneSlotToZoneObj      Zone        Scheduler, Memberships, Callbacks
--   autoSyncZones                           Zone        Scheduler
--   observerIdToObserverObj                 Observer    WorldQueries
--   observer settings (priority, enabled,   Wiring      Scheduler, Routing, Memberships
--     safety, updateRate, precisionSq)

local Types = require(script.Parent.Parent.Types)

local Registry = {}

-- Ids are never reused
Registry.nextZoneId = 1
Registry.nextObserverId = 1
Registry.nextGroupId = 1

-- Written by Group
Registry.groups = {} :: { [number]: Types.InternalGroup }

-- Written by Zone
Registry.zoneIdToZoneObj = {} :: { [number]: Types.InternalZone }
Registry.zoneSlotToZoneObj = {} :: { [number]: Types.InternalZone }
Registry.autoSyncZones = {} :: { [number]: Types.InternalZone }

-- Written by Observer
Registry.observerIdToObserverObj = {} :: { [number]: Types.InternalObserver }

-- Written by Wiring
Registry.observerPriorityMap = {} :: { [number]: number }
Registry.observerEnabled = {} :: { [number]: boolean }
Registry.observerSafety = {} :: { [number]: boolean }
Registry.observerUpdateRate = {} :: { [number]: number }
Registry.observerPrecisionSq = {} :: { [number]: number }

return Registry

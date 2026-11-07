--!strict

-- Every QuickZone object by id, and the settings of each observer. Each table is written only by the class whose
-- objects it holds, the core reads them

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
Registry.observerPriorityMap = {} :: { [number]: number }
Registry.observerEnabled = {} :: { [number]: boolean }
Registry.observerSafety = {} :: { [number]: boolean }
Registry.observerUpdateRate = {} :: { [number]: number }
Registry.observerPrecisionSq = {} :: { [number]: number }

return Registry

--!strict

-- static -> dynamic (moves when told) -> synced (follows its reference every tick). Synced zones are always dynamic:
-- these transitions are where that rule lives, for Zone and for the default a Zones gives its zones

local Types = require(script.Parent.Parent.Types)

type SyncMode = Types.SyncMode

local SyncMode = {}

function SyncMode.of(isDynamic: boolean, autoSync: boolean): SyncMode
	return if autoSync then 'synced' elseif isDynamic then 'dynamic' else 'static'
end

-- Syncing makes it dynamic, and stopping leaves it dynamic
function SyncMode.withAutoSync(mode: SyncMode, autoSync: boolean): SyncMode
	if autoSync then
		return 'synced'
	end
	return if mode == 'synced' then 'dynamic' else mode
end

-- Making it static stops its sync
function SyncMode.withDynamic(mode: SyncMode, isDynamic: boolean): SyncMode
	if not isDynamic then
		return 'static'
	end
	return if mode == 'static' then 'dynamic' else mode
end

return SyncMode

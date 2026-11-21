--!strict

local Types = require(script.Parent.Parent.Types)

type SyncMode = Types.SyncMode

local SyncMode = {}

function SyncMode.of(isDynamic: boolean, autoSync: boolean): SyncMode
	return if autoSync then 'synced' elseif isDynamic then 'dynamic' else 'static'
end

function SyncMode.withAutoSync(mode: SyncMode, autoSync: boolean): SyncMode
	return if autoSync then 'synced' elseif mode == 'synced' then 'dynamic' else mode
end

function SyncMode.withDynamic(mode: SyncMode, isDynamic: boolean): SyncMode
	return if not isDynamic then 'static' elseif mode == 'static' then 'dynamic' else mode
end

return SyncMode

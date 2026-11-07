--!strict

local Log = {}

local function formatLog(messageTemplate: string, trace: string?, ...: any): string
	local messageText = string.format(messageTemplate, ...)

	messageText = `[QuickZone] {messageText}`

	local finalTrace = trace or debug.traceback('', 3)

	if finalTrace ~= '' then
		messageText ..= ` \n---- Stack trace ----\n{finalTrace}`
	end

	return (messageText:gsub('\n', '\n    '))
end

function Log.warn(message: string, trace: string?, ...: any)
	warn(formatLog(message, trace, ...))
end

function Log.fatal(message: string, trace: string?, ...: any)
	error(formatLog(message, trace, ...), 0)
end

function Log.nonFatal(message: string, trace: string?, ...: any)
	local formattedString = formatLog(message, trace, ...)
	task.spawn(error :: any, formattedString, 0)
end

-- Checked where a callback is given, as the code that calls it would only fail later
function Log.checkCallback(callback: any)
	if type(callback) ~= 'function' then
		Log.fatal('Expected a callback function, got %s.', nil, typeof(callback))
	end
end

return Log

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedGroups = require(ReplicatedStorage.Common.Groups)

local discoPart = workspace:WaitForChild('DiscoPart')
local defaultColor = discoPart.Color

local discoObserver = QuickZone.Observer.new({
	groups = { SharedGroups.Players },
	updateRate = 5,
})

QuickZone.Zone.fromPart(discoPart, {
	observers = { discoObserver },
})

discoObserver:observeGroup(function(_, zone)
	local part = zone:getReference()
	if not (part and part:IsA('BasePart')) then
		return
	end

	print('The party has started!')

	local hue = 0
	local colorSpeed = 0.5
	local heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		hue = (hue + (dt * colorSpeed)) % 1
		part.Color = Color3.fromHSV(hue, 0.8, 1)
	end)

	return function()
		print('Last player left. Party is over!')

		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end

		part.Color = defaultColor
	end
end)

return nil

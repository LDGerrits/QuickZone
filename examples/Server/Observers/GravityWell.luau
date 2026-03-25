local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedGroups = require(ReplicatedStorage.Common.Groups)

local gravityWell = workspace:WaitForChild('GravityWell')

local gravityWellZone = QuickZone.Zone.fromPart(gravityWell, {
	isDynamic = true,
	autoSync = true,
})

local gravityWellObserver = QuickZone.Observer.new({
	groups = { SharedGroups.Players },
	zones = { gravityWellZone },
	updateRate = 20,
})

gravityWellObserver:observe(function(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild('HumanoidRootPart')
	local humanoid = character and character:FindFirstChild('Humanoid')
	if not hrp or not humanoid then
		return
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local attachment = Instance.new('Attachment', hrp)
	local align = Instance.new('AlignPosition')
	align.Attachment0 = attachment
	local targetAttachment = gravityWell:FindFirstChild('CenterPoint') or Instance.new('Attachment', gravityWell)
	targetAttachment.Name = 'CenterPoint'

	align.Attachment1 = targetAttachment
	align.MaxForce = 50000
	align.Responsiveness = 15
	align.Parent = hrp

	local angular = Instance.new('AngularVelocity')
	angular.Attachment0 = attachment
	angular.MaxTorque = 100000
	angular.AngularVelocity = Vector3.new(0, 20, 0)
	angular.Parent = hrp

	print(player.Name .. ' got caught in the gravity well!')

	return function()
		print(player.Name .. ' was ejected!')

		align:Destroy()
		angular:Destroy()
		attachment:Destroy()

		local exitVelocity = (hrp.Position - gravityWell.Position).Unit * 100
		hrp.AssemblyLinearVelocity += exitVelocity + Vector3.new(0, 50, 0)

		task.delay(0.3, function()
			if humanoid then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
end)

local centerPoint = gravityWell.Position
local orbitRadius = 10
local baseSize = 15
RunService.Heartbeat:Connect(function()
	local t = time()
	local offsetX = math.cos(t * 2) * orbitRadius
	local offsetZ = math.sin(t * 2) * orbitRadius
	gravityWell.Position = centerPoint + Vector3.new(offsetX, 0, offsetZ)

	local pulse = baseSize + math.sin(t * 2) * 5
	gravityWell.Size = Vector3.new(pulse, pulse, pulse)
end)

local shapes = { Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder }
local currentShapeIdx = 1
task.spawn(function()
	while true do
		task.wait(3)
		currentShapeIdx = (currentShapeIdx % #shapes) + 1
		if gravityWell:IsA('Part') then
			gravityWell.Shape = shapes[currentShapeIdx]
		end
	end
end)

return nil

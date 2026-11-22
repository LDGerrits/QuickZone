--!strict

local Log = require(script.Parent.Log)
local Types = require(script.Parent.Parent.Types)

type Destroyable = Types.Destroyable

local Destroyed = {}

function Destroyed.begin(object: Destroyable): boolean
	local phase = object.phase
	if phase ~= nil and phase ~= 'alive' then
		return false
	end
	object.phase = 'destroying'
	return true
end

local function ignoreDestroy() end

local deadMetatables = {} :: { [any]: any }

local function deadMetatableOf(class: any): any
	local dead = deadMetatables[class]
	if dead == nil then
		dead = {
			__index = function(_, key): any
				if key == 'destroy' then
					return ignoreDestroy
				end
				if type(class[key]) == 'function' then
					return function()
						Log.fatal('Cannot call %s, as the object was destroyed.', nil, tostring(key))
					end
				end
				return nil
			end,
		}
		deadMetatables[class] = dead
	end
	return dead
end

function Destroyed.finish(object: Destroyable)
	object.phase = 'dead'
	local metatable = getmetatable(object :: any)
	local class = metatable and metatable.__index
	setmetatable(object :: any, if type(class) == 'table' then deadMetatableOf(class) else nil)
end

function Destroyed.isDestroyed(object: any): boolean
	return type(object) == 'table' and (object.phase == 'destroying' or object.phase == 'dead')
end

function Destroyed.isDead(object: any): boolean
	return type(object) == 'table' and object.phase == 'dead'
end

function Destroyed.connect(object: Destroyable, callback: () -> ()): () -> ()
	Log.checkCallback(callback)

	local callbacks = object.onDestroyCallbacks or {}
	object.onDestroyCallbacks = callbacks
	table.insert(callbacks, callback)

	return function()
		local idx = table.find(callbacks, callback)
		if idx then
			table.remove(callbacks, idx)
		end
	end
end

function Destroyed.fireCallbacks(callbacks: { () -> () }?)
	if not callbacks then
		return
	end

	for _, callback in table.clone(callbacks) do
		if table.find(callbacks, callback) then
			task.spawn(callback)
		end
	end
	table.clear(callbacks)
end

return Destroyed

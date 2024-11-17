--- Lua-side duplication of the API of events on Roblox objects.
-- Signals are needed for to ensure that for local events objects are passed by
-- reference rather than by value where possible, as the BindableEvent objects
-- always pass signal arguments by value, meaning tables will be deep copied.
-- @classmod Signal

cloneref = cloneref or function(...) return ... end
local HttpService = cloneref(game:GetService("HttpService"))

local ENABLE_TRACEBACK = false
local CLEANUP_DELAY = 30 -- seconds

local Signal = {}
Signal.__index = Signal
Signal.ClassName = "Signal"

--- Constructs a new signal.
-- @constructor Signal.new()
-- @treturn Signal
function Signal.new()
	local self = setmetatable({}, Signal)

	self._bindableEvent = Instance.new("BindableEvent")
	self._argMap = {}
	self._source = ENABLE_TRACEBACK and debug.traceback() or ""
	self._locked = false
	self._connections = {}
	self._lastFire = os.clock()

	-- Automatic cleanup of stale args
	task.spawn(function()
		while self._argMap do
			local now = os.clock()
			if now - self._lastFire > CLEANUP_DELAY then
				table.clear(self._argMap)
			end
			task.wait(CLEANUP_DELAY)
		end
	end)

	self._bindableEvent.Event:Connect(function(key)
		self._argMap[key] = nil
		if (not self._bindableEvent) and (not next(self._argMap)) then
			self._argMap = nil
		end
	end)

	return self
end

--- Fire the event with the given arguments. All handlers will be invoked. Handlers follow
-- Roblox signal conventions.
-- @param ... Variable arguments to pass to handler
-- @treturn nil
function Signal:Fire(...)
	if self._locked or not self._bindableEvent then
		return
	end

	local args = table.pack(...)
	local key = HttpService:GenerateGUID(false)
	self._argMap[key] = args
	self._lastFire = os.clock()

	task.defer(function()
		if self._bindableEvent then
			self._bindableEvent:Fire(key)
		end
	end)
end

--- Connect a new handler to the event. Returns a connection object that can be disconnected.
-- @tparam function handler Function handler called with arguments passed when `:Fire(...)` is called
-- @treturn Connection Connection object that can be disconnected
function Signal:Connect(handler)
	assert(type(handler) == "function", ("connect(%s)"):format(typeof(handler)))

	if not self._bindableEvent then
		return {
			Disconnect = function() end,
			Connected = false
		}
	end

	local connection = self._bindableEvent.Event:Connect(function(key)
		local args = self._argMap[key]
		if args then
			task.spawn(handler, table.unpack(args, 1, args.n))
		end
	end)

	table.insert(self._connections, connection)

	return setmetatable({
		Connected = true,
		Disconnect = function()
			connection:Disconnect()
			table.remove(self._connections, table.find(self._connections, connection))
		end
	}, {
		__index = connection
	})
end

--- Wait for fire to be called, and return the arguments it was given.
-- @treturn ... Variable arguments from connection
function Signal:Wait()
	assert(self._bindableEvent, "Cannot wait on destroyed signal")

	local key = self._bindableEvent.Event:Wait()
	local args = self._argMap[key]
	
	return args and table.unpack(args, 1, args.n)
end

--- Returns whether the signal is active
-- @treturn boolean
function Signal:IsActive()
	return self._bindableEvent ~= nil
end

--- Disconnects all connected events to the signal. Voids the signal as unusable.
-- @treturn nil
function Signal:Destroy()
	if self._locked or not self._bindableEvent then
		return
	end

	self._locked = true

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	
	self._bindableEvent:Destroy()
	self._bindableEvent = nil
	table.clear(self._argMap)
	self._argMap = nil
	
	setmetatable(self, nil)
end

return Signal

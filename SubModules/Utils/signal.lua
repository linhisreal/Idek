--[=[
    @class Signal
    Lua-side duplication of the API of events on Roblox objects.
    Signals ensure local events pass objects by reference rather than by value.
    
    @field ClassName string -- Class identifier
    @field _bindableEvent BindableEvent -- Internal event handler
    @field _argMap table<string, table> -- Maps GUIDs to argument tables
    @field _connections {RBXScriptConnection} -- Active connections
    @field _lastFire number -- Timestamp of last fire
    @field _locked boolean -- Prevents modifications when true
    @field _source string -- Debug traceback if enabled
    @field _handlerCount number -- Number of active handlers
]=]

-- cloneref = cloneref or function(...) return ... end
-- local HttpService = cloneref(game:GetService("HttpService"))
local HttpService = game:GetService("HttpService")

local ENABLE_TRACEBACK = false
local CLEANUP_DELAY = 30 -- seconds
local ARG_CACHE_SIZE = 100
local HANDLER_WARNING_THRESHOLD = 100

local Signal = {}
Signal.__index = Signal
Signal.ClassName = "Signal"

function Signal.new()
    local self = setmetatable({}, Signal)

    self._bindableEvent = Instance.new("BindableEvent")
    self._argMap = table.create(ARG_CACHE_SIZE)
    self._source = ENABLE_TRACEBACK and debug.traceback() or ""
    self._locked = false
    self._connections = {}
    self._lastFire = os.clock()
    self._handlerCount = 0

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

function Signal:Connect(handler)
    assert(type(handler) == "function", ("connect(%s)"):format(typeof(handler)))

    if not self._bindableEvent then
        return {
            Connected = false,
            Disconnect = function() end,
            Destroy = function() end
        }
    end

    self._handlerCount += 1
    
    if self._handlerCount > HANDLER_WARNING_THRESHOLD then
        warn(("[Signal] High number of handlers (%d) for signal %s"):format(
            self._handlerCount,
            self._source
        ))
    end
    
    local connection = self._bindableEvent.Event:Connect(function(key)
        local args = self._argMap[key]
        if args then
            task.spawn(handler, table.unpack(args, 1, args.n))
        end
    end)

    table.insert(self._connections, connection)

    local connectionObject = {
        Connected = true,
        Disconnect = function()
            self._handlerCount -= 1
            connection:Disconnect()
            table.remove(self._connections, table.find(self._connections, connection))
        end,
        Destroy = function()
            self._handlerCount -= 1
            connection:Disconnect()
            table.remove(self._connections, table.find(self._connections, connection))
        end
    }

    return setmetatable(connectionObject, {
        __index = connection
    })
end

function Signal:Wait()
    assert(self._bindableEvent, "Cannot wait on destroyed signal")

    local key = self._bindableEvent.Event:Wait()
    local args = self._argMap[key]
    
    return args and table.unpack(args, 1, args.n)
end

function Signal:GetHandlerCount()
    return self._handlerCount
end

function Signal:IsActive()
    return self._bindableEvent ~= nil
end

function Signal:Destroy()
    if self._locked or not self._bindableEvent then
        return
    end

    self._locked = true
    self._handlerCount = 0

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

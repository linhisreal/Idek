--!strict
local Promise = {}
Promise.__index = Promise

export type Status = "Pending" | "Fulfilled" | "Rejected"
export type PromiseExecutor<T> = (resolve: (T) -> (), reject: (any) -> ()) -> ()
export type PromiseChain = {promise: Promise, onFulfilled: (() -> any)?, onRejected: (() -> any)?}
export type Thenable = {then: (any, (() -> any)?, (() -> any)?) -> any}
export type AggregateError = {name: string, errors: {any}, message: string}
export type PromiseConfig = {
    ENABLE_DEBUG: boolean,
    MAX_RECURSION: number,
    DEFAULT_TIMEOUT: number,
    ERROR_BOUNDARY: boolean
}

-- Simplified config with TRACE_WARNINGS merged into ENABLE_DEBUG
local Config: PromiseConfig = {
    ENABLE_DEBUG = true,
    MAX_RECURSION = 100,
    DEFAULT_TIMEOUT = 30,
    ERROR_BOUNDARY = true
}

-- Constants
local PENDING = "Pending"
local FULFILLED = "Fulfilled"
local REJECTED = "Rejected"

-- Enhanced callable check with weak reference cache
local callableCache = setmetatable({}, {__mode = "k"})
local function isCallable(value)
    if callableCache[value] ~= nil then
        return callableCache[value]
    end
    
    local result = false
    if type(value) == "function" then
        result = true
    elseif type(value) == "table" then
        local mt = getmetatable(value)
        result = mt and type(mt.__call) == "function"
    end
    
    callableCache[value] = result
    return result
end

function Promise.new<T>(executor: PromiseExecutor<T>)
    assert(isCallable(executor), "Promise executor must be callable")
    
    local self = setmetatable({
        _state = PENDING,
        _value = nil,
        _reason = nil,
        _thenQueue = {},
        _finallyQueue = {},
        _trace = Config.ENABLE_DEBUG and debug.traceback() or nil,
        _timestamp = os.clock(),
        _unhandledRejection = true,
        _recursionCount = 0,
        _children = {},
        _cancelled = false
    }, Promise)

    local function resolve(value)
        if self._state ~= PENDING or self._cancelled then return end
        
        self._recursionCount += 1
        if self._recursionCount > Config.MAX_RECURSION then
            reject("Maximum recursion depth exceeded")
            return
        end
        
        if Promise.isThenable(value) then
            value:then(resolve, reject)
            return
        end
        
        self._state = FULFILLED
        self._value = value
        self:_processQueue()
    end

    local function reject(reason)
        if self._state ~= PENDING or self._cancelled then return end
        
        self._state = REJECTED
        self._reason = reason
        self:_processQueue()
        
        if Config.ENABLE_DEBUG and self._unhandledRejection then
            task.delay(0, function()
                if self._unhandledRejection then
                    warn("[Promise] Unhandled rejection:", reason, self._trace)
                end
            end)
        end
    end

    -- Always run async for consistent behavior
    task.spawn(function()
        local success, result = xpcall(executor, debug.traceback, resolve, reject)
        if not success then
            reject(result)
        end
    end)

    return self
end

function Promise:_processQueue()
    while #self._thenQueue > 0 do
        local item = table.remove(self._thenQueue, 1)
        local promise = item.promise
        local handler = self._state == FULFILLED and item.onFulfilled or item.onRejected
        local value = self._state == FULFILLED and self._value or self._reason

        if handler then
            promise:_resolveFromHandler(handler, value)
        else
            if self._state == FULFILLED then
                promise:_resolve(value)
            else
                promise:_reject(value)
            end
        end
    end

    for _, finallyFn in ipairs(self._finallyQueue) do
        task.spawn(finallyFn)
    end
    table.clear(self._finallyQueue)
end

function Promise:_resolveFromHandler(handler, value)
    if self._cancelled then return end
    
    task.spawn(function()
        local success, result = pcall(handler, value)
        if success then
            self:_resolve(result)
        else
            self:_reject(result)
        end
    end)
end

function Promise:_resolve(value)
    if self._state ~= PENDING or self._cancelled then return end
    
    if Promise.isThenable(value) then
        value:then(
            function(val) self:_resolve(val) end,
            function(reason) self:_reject(reason) end
        )
        return
    end
    
    self._state = FULFILLED
    self._value = value
    self:_processQueue()
end

function Promise:_reject(reason)
    if self._state ~= PENDING or self._cancelled then return end
    
    self._state = REJECTED
    self._reason = reason
    self:_processQueue()
end

function Promise:then(onFulfilled, onRejected)
    if onRejected then
        self._unhandledRejection = false
    end

    local promise = Promise.new(function() end)
    table.insert(self._children, promise)
    
    table.insert(self._thenQueue, {
        promise = promise,
        onFulfilled = isCallable(onFulfilled) and onFulfilled,
        onRejected = isCallable(onRejected) and onRejected
    })
    
    if self._state ~= PENDING then
        self:_processQueue()
    end
    
    return promise
end

function Promise:catch(onRejected)
    return self:then(nil, onRejected)
end

function Promise:finally(onFinally)
    if isCallable(onFinally) then
        table.insert(self._finallyQueue, onFinally)
    end
    return self
end

function Promise:cancel()
    if self._state == PENDING then
        self._cancelled = true
        self:_reject({
            cancelled = true,
            message = "Promise cancelled",
            timestamp = os.clock()
        })
        
        for _, child in ipairs(self._children) do
            child:cancel()
        end
    end
end

function Promise:timeout(seconds: number, errorMessage: string?)
    return Promise.race({
        self,
        Promise.new(function(_, reject)
            task.delay(seconds, function()
                reject(errorMessage or "Promise timed out")
            end)
        end)
    })
end

function Promise:andThen(onFulfilled)
    return self:then(function(...)
        return Promise.resolve(onFulfilled(...))
    end)
end

function Promise:tap(tapHandler)
    return self:then(function(value)
        task.spawn(tapHandler, value)
        return value
    end)
end

function Promise:await()
    assert(coroutine.isyieldable(), "Cannot await outside of a coroutine")
    
    local result, value
    self:then(
        function(...)
            result = true
            value = {...}
        end,
        function(...)
            result = false
            value = {...}
        end
    )
    
    while result == nil do
        task.wait()
    end
    
    if result then
        return unpack(value)
    else
        error(value[1], 2)
    end
end

function Promise:expect()
    local success, result = self:await()
    assert(success, result)
    return result
end

function Promise:withErrorBoundary(errorHandler)
    if not Config.ERROR_BOUNDARY then return self end
    
    return self:catch(function(err)
        if isCallable(errorHandler) then
            return errorHandler(err)
        end
        return Promise.reject(err)
    end)
end

function Promise.resolve(value)
    if Promise.is(value) then
        return value
    end
    return Promise.new(function(resolve)
        resolve(value)
    end)
end

function Promise.reject(reason)
    return Promise.new(function(_, reject)
        reject(reason)
    end)
end

function Promise.all(promises)
    return Promise.new(function(resolve, reject)
        local results = table.create(#promises)
        local remaining = #promises
        
        if remaining == 0 then
            resolve(results)
            return
        end
        
        for i, promise in ipairs(promises) do
            Promise.resolve(promise):then(
                function(value)
                    results[i] = value
                    remaining -= 1
                    if remaining == 0 then
                        resolve(results)
                    end
                end,
                reject
            )
        end
    end)
end

function Promise.race(promises)
    return Promise.new(function(resolve, reject)
        for _, promise in ipairs(promises) do
            Promise.resolve(promise):then(resolve, reject)
        end
    end)
end

function Promise.allSettled(promises)
    return Promise.new(function(resolve)
        local results = table.create(#promises)
        local remaining = #promises
        
        if remaining == 0 then
            resolve(results)
            return
        end
        
        for i, promise in ipairs(promises) do
            Promise.resolve(promise):then(
                function(value)
                    results[i] = {status = FULFILLED, value = value}
                    remaining -= 1
                    if remaining == 0 then
                        resolve(results)
                    end
                end,
                function(reason)
                    results[i] = {status = REJECTED, reason = reason}
                    remaining -= 1
                    if remaining == 0 then
                        resolve(results)
                    end
                end
            )
        end
    end)
end

function Promise.any(promises)
    return Promise.new(function(resolve, reject)
        local errors = table.create(#promises)
        local remaining = #promises
        
        if remaining == 0 then
            reject({
                name = "AggregateError",
                errors = errors,
                message = "No promises to resolve"
            })
            return
        end
        
        for i, promise in ipairs(promises) do
            Promise.resolve(promise):then(
                resolve,
                function(reason)
                    errors[i] = reason
                    remaining -= 1
                    if remaining == 0 then
                        reject({
                            name = "AggregateError",
                            errors = errors,
                            message = "All promises were rejected"
                        })
                    end
                end
            )
        end
    end)
end

function Promise.delay(seconds: number)
    return Promise.new(function(resolve)
        task.delay(seconds, resolve)
    end)
end

function Promise.retry(callback, attempts: number, delay: number?)
    return Promise.new(function(resolve, reject)
        local function attempt(remaining)
            if remaining <= 0 then
                reject("Max retry attempts reached")
                return
            end

            Promise.resolve(callback()):then(
                resolve,
                function(err)
                    if remaining > 1 then
                        task.delay(delay or 0, function()
                            attempt(remaining - 1)
                        end)
                    else
                        reject(err)
                    end
                end
            )
        end

        attempt(attempts)
    end)
end

function Promise.is(value)
    return type(value) == "table" and getmetatable(value) == Promise
end

function Promise.isThenable(value)
    return type(value) == "table" and isCallable(value.then)
end

function Promise:getStatus(): Status
    return self._state
end

function Promise:isPending(): boolean
    return self._state == PENDING
end

function Promise:isFulfilled(): boolean
    return self._state == FULFILLED
end

function Promise:isRejected(): boolean
    return self._state == REJECTED
end

function Promise:isCancelled(): boolean
    return self._cancelled
end

function Promise.configure(options: PromiseConfig)
    for key, value in pairs(options) do
        if Config[key] ~= nil then
            Config[key] = value
        end
    end
end

return Promise
--!strict
local function createPromiseModule()
    local Promise = {}
    Promise.__index = Promise

    local internal = {
        callCount = {},
        activeCall = false
    }

    local function validateInternalUsage(funcName)
        if internal.activeCall then
            return
        end

        local success, caller = pcall(function()
            return debug.info(3, "s")
        end)
        
        if success and caller then
            internal.callCount[funcName] = (internal.callCount[funcName] or 0) + 1
            warn(string.format(
                "Warning: Internal function '%s' was called from: %s",
                funcName,
                caller
            ))
        end
    end

    local function withInternalAccess(fn, ...)
        internal.activeCall = true
        local result = fn(...)
        internal.activeCall = false
        return result
    end

    local function wrapInternalFunction(fn, name)
        return function(...)
            return withInternalAccess(function()
                validateInternalUsage(name)
                return fn(...)
            end, ...)
        end
    end

    -- Types
    export type Status = "Pending" | "Fulfilled" | "Rejected"
    export type PromiseExecutor<T> = (resolve: (T) -> (), reject: (any) -> ()) -> ()
    export type PromiseChain = {promise: Promise, onFulfilled: (() -> any)?, onRejected: (() -> any)?}
    export type Thenable = {andThen: (any, (() -> any)?, (() -> any)?) -> any}
    export type AggregateError = {name: string, errors: {any}, message: string}
    export type PromiseConfig = {
        ENABLE_DEBUG: boolean,
        MAX_RECURSION: number,
        DEFAULT_TIMEOUT: number,
        ERROR_BOUNDARY: boolean
    }

    local Config: PromiseConfig = {
        ENABLE_DEBUG = true,
        MAX_RECURSION = 100,
        DEFAULT_TIMEOUT = 30,
        ERROR_BOUNDARY = true
    }

    -- Protected isCallable implementation
    local callableCache = setmetatable({}, {__mode = "k"})
    local isCallable = wrapInternalFunction(function(value)
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
    end, "isCallable")

    -- Forward declare internal functions
    local resolvePromise, rejectPromise, processQueue, resolveFromHandler

    processQueue = wrapInternalFunction(function(self)
        while #self._thenQueue > 0 do
            local item = table.remove(self._thenQueue, 1)
            local promise = item.promise
            local handler = self._state == "Fulfilled" and item.onFulfilled or item.onRejected
            local value = self._state == "Fulfilled" and self._value or self._reason

            if handler then
                resolveFromHandler(promise, handler, value)
            else
                if self._state == "Fulfilled" then
                    resolvePromise(promise, value)
                else
                    rejectPromise(promise, value)
                end
            end
        end

        for _, finallyFn in ipairs(self._finallyQueue) do
            task.spawn(finallyFn)
        end
        table.clear(self._finallyQueue)
    end, "processQueue")
    
        resolveFromHandler = wrapInternalFunction(function(promise, handler, value)
        if promise._cancelled then return end
        
        task.spawn(function()
            local success, result = pcall(handler, value)
            if success then
                resolvePromise(promise, result)
            else
                rejectPromise(promise, result)
            end
        end)
    end, "resolveFromHandler")

    resolvePromise = wrapInternalFunction(function(promise, value)
        if promise._state ~= "Pending" or promise._cancelled then return end
        
        if Promise.isThenable(value) then
            local success, result = pcall(function()
                return value.andThen(
                    function(val) resolvePromise(promise, val) end,
                    function(reason) rejectPromise(promise, reason) end
                )
            end)
            if not success then
                rejectPromise(promise, result)
            end
            return
        end
        
        promise._state = "Fulfilled"
        promise._value = value
        processQueue(promise)
    end, "resolvePromise")

    rejectPromise = wrapInternalFunction(function(promise, reason)
        if promise._state ~= "Pending" or promise._cancelled then return end
        
        promise._state = "Rejected"
        promise._reason = reason
        processQueue(promise)

        if Config.ENABLE_DEBUG and promise._unhandledRejection then
            task.delay(0, function()
                if promise._unhandledRejection then
                    warn("[Promise] Unhandled rejection:", reason, promise._trace)
                end
            end)
        end
    end, "rejectPromise")

    function Promise.new<T>(executor: PromiseExecutor<T>)
        assert(isCallable(executor), "Promise executor must be callable")
        
        local self = setmetatable({
            _state = "Pending",
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
            if self._state ~= "Pending" or self._cancelled then return end
            
            self._recursionCount += 1
            if self._recursionCount > Config.MAX_RECURSION then
                rejectPromise(self, "Maximum recursion depth exceeded")
                return
            end
            
            if Promise.isThenable(value) then
                local success, result = pcall(function()
                    return value.andThen(resolve, function(reason) rejectPromise(self, reason) end)
                end)
                if not success then
                    rejectPromise(self, result)
                end
                return
            end
            
            resolvePromise(self, value)
        end

        task.spawn(function()
            local success, result = xpcall(executor, debug.traceback, resolve, 
                function(reason) rejectPromise(self, reason) end)
            if not success then
                rejectPromise(self, result)
            end
        end)

        return self
    end

        function Promise:andThen(onFulfilled, onRejected)
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
        
        if self._state ~= "Pending" then
            processQueue(self)
        end
        
        return promise
    end

    function Promise:catch(onRejected)
        return self:andThen(nil, onRejected)
    end

    function Promise:finally(onFinally)
        if isCallable(onFinally) then
            table.insert(self._finallyQueue, onFinally)
        end
        return self
    end

    function Promise:cancel()
        if self._state == "Pending" then
            self._cancelled = true
            rejectPromise(self, {
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

    function Promise:tap(tapHandler)
        return self:andThen(function(value)
            task.spawn(tapHandler, value)
            return value
        end)
    end

    function Promise:await()
        assert(coroutine.isyieldable(), "Cannot await outside of a coroutine")
        
        local result, value
        self:andThen(
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
                Promise.resolve(promise):andThen(
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
                Promise.resolve(promise):andThen(resolve, reject)
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
                Promise.resolve(promise):andThen(
                    function(value)
                        results[i] = {status = "Fulfilled", value = value}
                        remaining -= 1
                        if remaining == 0 then
                            resolve(results)
                        end
                    end,
                    function(reason)
                        results[i] = {status = "Rejected", reason = reason}
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
                Promise.resolve(promise):andThen(
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

                Promise.resolve(callback()):andThen(
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
        return type(value) == "table" and isCallable(value.andThen)
    end

    function Promise:getStatus(): Status
        return self._state
    end

    function Promise:isPending(): boolean
        return self._state == "Pending"
    end

    function Promise:isFulfilled(): boolean
        return self._state == "Fulfilled"
    end

    function Promise:isRejected(): boolean
        return self._state == "Rejected"
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

    function Promise.getInternalCallStats()
        return table.clone(internal.callCount)
    end

    return Promise
end

return createPromiseModule()


--!strict
--[=[
    Promise Implementation for Roblox Luau
    Follows Promise/A+ specification with additional utilities
    
    @class Promise
]=]

local INTERNAL_ACCESS = newproxy(true)
getmetatable(INTERNAL_ACCESS).__tostring = function()
    return "aDi7<SfG>8ehjUe7Ff7ei_[INTERNAL]_<286AbfDka>"
end

local Internal = {}
local Promise = {}
Promise.__index = Promise

export type Status = "pending" | "fulfilled" | "rejected"
export type PromiseExecutor = (resolve: (value: any) -> (), reject: (reason: any) -> ()) -> ()
export type Promise = {
    _status: Status,
    _value: any?,
    _reason: any?,
    _thenQueue: {any},
    _catchQueue: {any},
    _finallyQueue: {any},
    _settled: boolean,
    
    andThen: (self: Promise, onFulfilled: ((value: any) -> any)?, onRejected: ((reason: any) -> any)?) -> Promise,
    catch: (self: Promise, onRejected: (reason: any) -> any) -> Promise,
    finally: (self: Promise, onFinally: () -> ()) -> Promise
}

-- Internal Utilities
function Internal.createPromise(access)
    assert(access == INTERNAL_ACCESS, "Cannot create promise (INTERNAL) outside of Module")
    return setmetatable({
        _status = "pending",
        _value = nil,
        _reason = nil,
        _thenQueue = {},
        _catchQueue = {},
        _finallyQueue = {},
        _settled = false
    }, Promise)
end

function Internal.settle(promise, access)
    assert(access == INTERNAL_ACCESS, "Cannot settle promise (INTERNAL) outside of Module")
    promise._settled = true
end

function Internal.isPromise(value)
    return type(value) == "table" and getmetatable(value) == Promise
end

function Internal.resolveValue(promise, value, access)
    assert(access == INTERNAL_ACCESS, "Cannot resolve promise (INTERNAL) outside of Module")
    
    if promise._settled then return end
    
    if Internal.isPromise(value) then
        if value == promise then
            Internal.rejectValue(promise, "Promise cannot resolve to itself", INTERNAL_ACCESS)
            return
        end
        
        value:andThen(
            function(resolvedValue)
                Internal.resolveValue(promise, resolvedValue, INTERNAL_ACCESS)
            end,
            function(reason)
                Internal.rejectValue(promise, reason, INTERNAL_ACCESS)
            end
        )
        return
    end
    
    promise._status = "fulfilled"
    promise._value = value
    Internal.settle(promise, INTERNAL_ACCESS)
    
    for _, callback in ipairs(promise._thenQueue) do
        task.spawn(callback, value)
    end
    
    for _, callback in ipairs(promise._finallyQueue) do
        task.spawn(callback)
    end
    
    table.clear(promise._thenQueue)
    table.clear(promise._catchQueue)
    table.clear(promise._finallyQueue)
end

function Internal.rejectValue(promise, reason, access)
    assert(access == INTERNAL_ACCESS, "Cannot reject promise (INTERNAL) outside of Module")
    
    if promise._settled then return end
    
    promise._status = "rejected"
    promise._reason = reason
    Internal.settle(promise, INTERNAL_ACCESS)
    
    for _, callback in ipairs(promise._catchQueue) do
        task.spawn(callback, reason)
    end
    
    for _, callback in ipairs(promise._finallyQueue) do
        task.spawn(callback)
    end
    
    table.clear(promise._thenQueue)
    table.clear(promise._catchQueue)
    table.clear(promise._finallyQueue)
end

-- Public API
function Promise.new(executor: PromiseExecutor): Promise
    assert(type(executor) == "function", "Executor must be a function")
    
    local promise = Internal.createPromise(INTERNAL_ACCESS)
    
    local function resolve(value)
        Internal.resolveValue(promise, value, INTERNAL_ACCESS)
    end
    
    local function reject(reason)
        Internal.rejectValue(promise, reason, INTERNAL_ACCESS)
    end
    
    local success, err = pcall(executor, resolve, reject)
    if not success then
        reject(err)
    end
    
    return promise
end

function Promise:andThen(onFulfilled, onRejected)
    return Promise.new(function(resolve, reject)
        local function handleFulfilled(value)
            if type(onFulfilled) ~= "function" then
                resolve(value)
                return
            end
            
            local success, result = pcall(onFulfilled, value)
            if success then
                resolve(result)
            else
                reject(result)
            end
        end
        
        local function handleRejected(reason)
            if type(onRejected) ~= "function" then
                reject(reason)
                return
            end
            
            local success, result = pcall(onRejected, reason)
            if success then
                resolve(result)
            else
                reject(result)
            end
        end
        
        if self._status == "pending" then
            table.insert(self._thenQueue, handleFulfilled)
            table.insert(self._catchQueue, handleRejected)
        elseif self._status == "fulfilled" then
            task.spawn(handleFulfilled, self._value)
        else
            task.spawn(handleRejected, self._reason)
        end
    end)
end

function Promise:catch(onRejected)
    return self:andThen(nil, onRejected)
end

function Promise:finally(onFinally)
    return Promise.new(function(resolve, reject)
        local function handleFinally()
            local success, result = pcall(onFinally)
            if success then
                if self._status == "fulfilled" then
                    resolve(self._value)
                else
                    reject(self._reason)
                end
            else
                reject(result)
            end
        end
        
        if self._status == "pending" then
            table.insert(self._finallyQueue, handleFinally)
        else
            task.spawn(handleFinally)
        end
    end)
end

function Promise.resolve(value)
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
        local results = {}
        local completed = 0
        local total = #promises
        
        if total == 0 then
            resolve(results)
            return
        end
        
        for i, promise in ipairs(promises) do
            promise:andThen(function(value)
                results[i] = value
                completed += 1
                
                if completed == total then
                    resolve(results)
                end
            end, reject)
        end
    end)
end

function Promise.race(promises)
    return Promise.new(function(resolve, reject)
        for _, promise in ipairs(promises) do
            promise:andThen(resolve, reject)
        end
    end)
end

function Promise.delay(seconds: number)
    return Promise.new(function(resolve)
        task.delay(seconds, resolve)
    end)
end

function Promise.retry(callback: () -> any, attempts: number, delay: number?)
    return Promise.new(function(resolve, reject)
        local function attempt(count)
            if count > attempts then
                reject("Max retry attempts reached")
                return
            end
            
            Promise.new(callback)
                :andThen(resolve)
                :catch(function(err)
                    if count < attempts then
                        if delay then
                            task.wait(delay)
                        end
                        attempt(count + 1)
                    else
                        reject(err)
                    end
                end)
        end
        
        attempt(1)
    end)
end

function Promise.some(promises: {Promise}, count: number)
    return Promise.new(function(resolve, reject)
        local results = {}
        local fulfilled = 0
        local rejected = 0
        local total = #promises
        
        if count > total then
            reject("Count cannot be greater than total promises")
            return
        end
        
        for i, promise in ipairs(promises) do
            promise:andThen(function(value)
                results[i] = value
                fulfilled += 1
                
                if fulfilled >= count then
                    resolve(results)
                end
            end):catch(function()
                rejected += 1
                
                if rejected > (total - count) then
                    reject("Not enough promises fulfilled")
                end
            end)
        end
    end)
end

return Promise

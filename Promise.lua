--[=[
    Promise Implementation for Roblox Luau
    Follows Promise/A+ specification with additional utilities
    
    @class Promise
]=]
local Maid = require(game.ReplicatedStorage.rbxPromise.maid)
local Signal = require(game.ReplicatedStorage.rbxPromise.signal)

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
	_maid: any,
	_settleSignal: any,

	andThen: (self: Promise, onFulfilled: ((value: any) -> any)?, onRejected: ((reason: any) -> any)?) -> Promise,
	catch: (self: Promise, onRejected: (reason: any) -> any) -> Promise,
	finally: (self: Promise, onFinally: () -> ()) -> Promise,
	getStatus: (self: Promise) -> Status,
	isPending: (self: Promise) -> boolean,
	isFulfilled: (self: Promise) -> boolean,
	isRejected: (self: Promise) -> boolean,
	timeout: (self: Promise, seconds: number) -> Promise,
	cancel: (self: Promise) -> (),
}

function Internal.createPromise(access)
	assert(access == INTERNAL_ACCESS, "Cannot create promise (INTERNAL) outside of Module")
	local maid = Maid.new()
	local settleSignal = Signal.new()

	maid:GiveTask(settleSignal)
	local promise = setmetatable({
		_status = "pending",
		_value = nil,
		_reason = nil,
		_thenQueue = {},
		_catchQueue = {},
		_finallyQueue = {},
		_settled = false,
		_maid = maid,
		_settleSignal = settleSignal
	}, Promise)

	return promise
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

	promise._settleSignal:Fire("fulfilled", value)
	promise._maid:DoCleaning() -- Cleanup resources

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
	if type(reason) == "string" and not string.match(reason, "^%[Promise%]") then
		reason = "[Promise]: " .. reason
	end
	promise._reason = reason

	promise._settleSignal:Fire("rejected", reason)
	promise._maid:DoCleaning()

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
	local executorRan = false

	local function resolve(value)
		if executorRan then return end
		executorRan = true
		Internal.resolveValue(promise, value, INTERNAL_ACCESS)
	end

	local function reject(reason)
		if executorRan then return end
		executorRan = true
		Internal.rejectValue(promise, reason, INTERNAL_ACCESS)
	end

	local success, err = pcall(executor, resolve, reject)
	if not success then
		reject(err)
	end

	return promise
end

function Promise:andThen(onFulfilled, onRejected)
	assert(onFulfilled == nil or type(onFulfilled) == "function", "[Promise]: onFulfilled must be a function or nil")
	assert(onRejected == nil or type(onRejected) == "function", "[Promise]: onRejected must be a function or nil")

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
				reject("[Promise]: Error in andThen handler - " .. tostring(result))
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
				reject("[Promise]: Error in catch handler - " .. tostring(result))
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
	assert(onRejected == nil or type(onRejected) == "function", 
		"[Promise]: onRejected must be a function or nil")

	return self:andThen(nil, function(...)
		if onRejected then
			return onRejected(...)
		end
		return Promise.reject(...)
	end)
end


function Promise:finally(onFinally)
	assert(type(onFinally) == "function", "[Promise]: onFinally must be a function")

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
				reject("[Promise]: Error in finally handler - " .. tostring(result))
			end
		end

		if self._status == "pending" then
			table.insert(self._finallyQueue, handleFinally)
		else
			task.spawn(handleFinally)
		end
	end)
end


function Promise:timeout(seconds: number): Promise
	assert(type(seconds) == "number", "[Promise]: Timeout must be a number")
	assert(seconds > 0, "[Promise]: Timeout must be positive")

	return Promise.race({
		self,
		Promise.new(function(_, reject)
			Promise.delay(seconds):andThen(function()
				reject("[Promise]: Promise timed out after ".. tostring(seconds) .. " seconds")
			end)
		end)
	})
end

function Promise:tap(tapCallback: (value: any) -> ()): Promise
	assert(type(tapCallback) == "function", "[Promise]: Tap callback must be a function")

	return self:andThen(function(value)
		local success, err = pcall(tapCallback, value)
		if not success then
			warn("[Promise]: Tap callback error -", err)
		end
		return value
	end)
end

function Promise:cancel()
	if self._status == "pending" then
		Internal.rejectValue(self, "[Promise]: Promise cancelled", INTERNAL_ACCESS)

		-- Clear queues to prevent memory leaks
		table.clear(self._thenQueue)
		table.clear(self._catchQueue)
		table.clear(self._finallyQueue)

		self._maid:DoCleaning()
	end
end

-- Static methods --
function Promise.resolve(value)
	if Internal.isPromise(value) then
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

function Promise.all(promises: {Promise})
	assert(type(promises) == "table", "[Promise]: Expected array of promises")

	return Promise.new(function(resolve, reject)
		local results = table.create(#promises)
		local completed = 0
		local total = #promises
		local rejected = false

		if total == 0 then
			resolve(results)
			return
		end

		for i, promise in ipairs(promises) do
			if not Internal.isPromise(promise) then
				promise = Promise.resolve(promise)
			end

			promise:andThen(function(value)
				if rejected then return end
				results[i] = value
				completed += 1

				if completed == total then
					resolve(results)
				end
			end, function(err)
				if rejected then return end
				rejected = true
				reject(err)
			end)
		end
	end)
end


function Promise.race(promises: {Promise})
	assert(type(promises) == "table", "[Promise]: Expected array of promises")

	return Promise.new(function(resolve, reject)
		if #promises == 0 then
			reject("[Promise]: Empty promise array")
			return
		end

		for _, promise in ipairs(promises) do
			if not Internal.isPromise(promise) then
				promise = Promise.resolve(promise)
			end
			promise:andThen(resolve, reject)
		end
	end)
end

function Promise.delay(seconds: number)
	assert(type(seconds) == "number", "[Promise]: Delay must be a number")
	assert(seconds >= 0, "[Promise]: Delay must be non-negative")

	return Promise.new(function(resolve)
		local thread = coroutine.running()
		local connection
		connection = task.delay(seconds, function()
			connection = nil
			resolve(true)
		end)
	end)
end

function Promise.retry(callback: () -> any, attempts: number, delay: number?, exponential: boolean?)
	assert(type(callback) == "function", "[Promise]: Expected function for retry callback")
	assert(type(attempts) == "number", "[Promise]: Expected number for attempts")
	assert(delay == nil or type(delay) == "number", "[Promise]: Expected number for delay")

	return Promise.new(function(resolve, reject)
		local function attempt(count, currentDelay)
			if count > attempts then
				reject("[Promise]: Max retry attempts reached")
				return
			end

			Promise.new(callback)
				:andThen(resolve)
				:catch(function(err)
					if count < attempts then
						if delay then
							task.wait(currentDelay)
						end
						local nextDelay = exponential and currentDelay * 2 or currentDelay
						attempt(count + 1, nextDelay)
					else
						reject(err)
					end
				end)
		end

		attempt(1, delay or 0)
	end)
end

function Promise.some(promises: {Promise}, count: number)
	assert(type(promises) == "table", "[Promise]: Expected array of promises")
	assert(type(count) == "number", "[Promise]: Count must be a number")

	return Promise.new(function(resolve, reject)
		local results = table.create(#promises)
		local fulfilled = 0
		local rejected = 0
		local total = #promises

		if count > total then
			reject("[Promise]: Count cannot be greater than total promises")
			return
		end

		if total == 0 then
			reject("[Promise]: Empty promise array")
			return
		end

		for i, promise in ipairs(promises) do
			if not Internal.isPromise(promise) then
				promise = Promise.resolve(promise)
			end

			promise:andThen(function(value)
				results[i] = value
				fulfilled += 1

				if fulfilled >= count then
					resolve(results)
				end
			end):catch(function()
				rejected += 1

				if rejected > (total - count) then
					reject("[Promise]: Not enough promises fulfilled")
				end
			end)
		end
	end)
end


function Promise.await(promise: Promise)
	assert(Internal.isPromise(promise), "[Promise]: Expected promise object")

	local result, value
	local completed = false

	promise:andThen(function(v)
		result = true
		value = v
		completed = true
	end):catch(function(v)
		result = false
		value = v
		completed = true
	end)

	while not completed do
		task.wait()
	end

	return result, value
end

function Promise.any(promises: {Promise})
	assert(type(promises) == "table", "[Promise]: Expected array of promises")

	return Promise.new(function(resolve, reject)
		local errors = {}
		local rejected = 0
		local total = #promises

		if total == 0 then
			reject("[Promise]: No promises provided")
			return
		end

		for _, promise in ipairs(promises) do
			if not Internal.isPromise(promise) then
				promise = Promise.resolve(promise)
			end

			promise:andThen(resolve):catch(function(err)
				rejected += 1
				table.insert(errors, err)

				if rejected == total then
					reject("[Promise]: All promises rejected - " .. table.concat(errors, ", "))
				end
			end)
		end
	end)
end

function Promise.fromEvent(event: RBXScriptSignal, timeout: number?)
	assert(typeof(event) == "RBXScriptSignal", "[Promise]: Expected RBXScriptSignal")
	assert(timeout == nil or type(timeout) == "number", "[Promise]: Timeout must be a number")

	return Promise.new(function(resolve, reject)
		local connection
		local timeoutHandle

		connection = event:Connect(function(...)
			if timeoutHandle then
				task.cancel(timeoutHandle)
			end
			connection:Disconnect()
			resolve(...)
		end)

		if timeout then
			timeoutHandle = task.delay(timeout, function()
				connection:Disconnect()
				reject("[Promise]: Event listener timed out")
			end)
		end
	end)
end

function Promise.allSettled(promises: {Promise})
	assert(type(promises) == "table", "[Promise]: Expected array of promises")

	return Promise.new(function(resolve)
		local results = table.create(#promises)
		local completed = 0
		local total = #promises

		if total == 0 then
			resolve(results)
			return
		end

		for i, promise in ipairs(promises) do
			if not Internal.isPromise(promise) then
				promise = Promise.resolve(promise)
			end

			promise:andThen(
				function(value)
					results[i] = {status = "fulfilled", value = value}
				end,
				function(reason)
					results[i] = {status = "rejected", reason = reason}
				end
			):finally(function()
				completed += 1
				if completed == total then
					resolve(results)
				end
			end)
		end
	end)
end

-- Add these functions before the Status methods

function Promise.map<T, U>(
	array: {T}, 
	callback: (value: T, index: number) -> U,
	concurrency: number?
): Promise
	assert(type(array) == "table", "[Promise]: Expected array")
	assert(type(callback) == "function", "[Promise]: Expected callback function")
	assert(concurrency == nil or (type(concurrency) == "number" and concurrency > 0), 
		"[Promise]: Concurrency must be positive number")

	if #array == 0 then
		return Promise.resolve({})
	end

	return Promise.new(function(resolve, reject)
		local results = table.create(#array)
		local completed = 0
		local nextIndex = 1
		local running = 0
		local maxConcurrent = concurrency or math.huge
		local errored = false

		local function startNext()
			if errored or nextIndex > #array then return end

			while running < maxConcurrent and nextIndex <= #array do
				local index = nextIndex
				nextIndex += 1
				running += 1

				Promise.new(function(resolve)
					resolve(callback(array[index], index))
				end)
					:andThen(function(result)
						if errored then return end
						results[index] = result
						completed += 1
						running -= 1

						if completed == #array then
							resolve(results)
						else
							startNext()
						end
					end)
					:catch(function(err)
						if errored then return end
						errored = true
						reject(err)
					end)
			end
		end

		startNext()
	end)
end

function Promise.fold<T, U>(
	array: {T},
	callback: (accumulator: U, value: T, index: number) -> U,
	initial: U
): Promise
	assert(type(array) == "table", "[Promise]: Expected array")
	assert(type(callback) == "function", "[Promise]: Expected callback function")

	return Promise.new(function(resolve, reject)
		local result = initial
		for i, value in ipairs(array) do
			local success, newResult = pcall(callback, result, value, i)
			if not success then
				reject("[Promise]: Fold error - " .. tostring(newResult))
				return
			end
			result = newResult
		end
		resolve(result)
	end)
end

-- Status --
function Promise:getStatus(): Status 
	return self._status
end

function Promise:isPending(): boolean
	return self._status == "pending"    
end

function Promise:isFulfilled(): boolean
	return self._status == "fulfilled"
end

function Promise:isRejected(): boolean
	return self._status == "rejected"
end

return Promise

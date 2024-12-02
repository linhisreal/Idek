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

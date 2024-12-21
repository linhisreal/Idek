--[=[
    @class Maid
    Manages cleanup of events, connections and objects.
    Provides automatic task tracking and disposal.
    
    @field ClassName string -- Class identifier
    @field _tasks table<any, any> -- Active tasks
    @field _taskCount number -- Number of active tasks
    @field _locked boolean -- Prevents modifications when true
    @field _cleaning boolean -- Indicates cleanup in progress
]=]

local Maid = {}
Maid.ClassName = "Maid"

function Maid.new()
    return setmetatable({
        _tasks = {},
        _taskCount = 0,
        _locked = false,
        _cleaning = false
    }, Maid)
end

function Maid.isMaid(value)
    return type(value) == "table" and value.ClassName == "Maid"
end

function Maid:__index(index)
    if Maid[index] then
        return Maid[index]
    else
        return self._tasks[index]
    end
end

function Maid:__newindex(index, newTask)
    if self._locked then
        return
    end

    if Maid[index] ~= nil then
        error(("'%s' is reserved"):format(tostring(index)), 2)
    end

    local tasks = self._tasks
    local oldTask = tasks[index]

    if oldTask == newTask then
        return
    end

    tasks[index] = newTask
    
    if newTask then
        self._taskCount += 1
    end

    if oldTask then
        self._taskCount = math.max(0, self._taskCount - 1)
        
        if type(oldTask) == "function" then
            task.spawn(oldTask)
        elseif typeof(oldTask) == "RBXScriptConnection" then
            oldTask:Disconnect()
        elseif oldTask.Destroy then
            task.spawn(function()
                oldTask:Destroy()
            end)
        end
    end
end

function Maid:GiveTask(task)
    assert(task ~= nil, "Task cannot be nil", 2)

    local taskId = #self._tasks + 1
    self[taskId] = task

    if type(task) == "table" and (not task.Destroy) then
        warn("[Maid.GiveTask] - Gave table task without .Destroy\n\n" .. debug.traceback())
    end

    return taskId
end

function Maid:GivePromise(promise)
    if not promise:IsPending() then
        return promise
    end

    local newPromise = promise.resolved(promise)
    local id = self:GiveTask(newPromise)

    newPromise:Finally(function()
        self[id] = nil
    end)

    return newPromise
end

function Maid:DoCleaning()
    if self._locked or self._cleaning then
        return
    end
    
    self._locked = true
    self._cleaning = true
    
    local tasks = self._tasks

    for index, task in pairs(tasks) do
        if typeof(task) == "RBXScriptConnection" then
            tasks[index] = nil
            task:Disconnect()
        end
    end

    local index, task = next(tasks)
    while task ~= nil do
        tasks[index] = nil
        if type(task) == "function" then
            task()
        elseif typeof(task) == "RBXScriptConnection" then
            task:Disconnect()
        elseif task.Destroy then
            task:Destroy()
        end
        index, task = next(tasks)
    end
    
    self._taskCount = 0
    self._cleaning = false
    self._locked = false
end

Maid.Destroy = Maid.DoCleaning

return Maid

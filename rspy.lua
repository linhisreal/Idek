local RemoteSpy = {}
RemoteSpy.__index = RemoteSpy
RemoteSpy.ClassName = "RemoteSpy"

local logQueue = {}
local isProcessingQueue = false
local startTime = os.clock()

local getinfo = debug.getinfo
local traceback = debug.traceback

--- Formats the arguments for logging with improved type handling
-- @param args Table of arguments to format
-- @return string Formatted argument string
local function formatArgs(args)
    if #args == 0 then
        return "No arguments"
    end
    
    local formatted = {}
    for i, arg in ipairs(args) do
        local argType = typeof(arg)
        if argType == "table" then
            local success, result = pcall(function()
                return "Table [" .. table.concat(arg, ",") .. "]"
            end)
            formatted[i] = success and result or "Table [Complex]"
        elseif argType == "Instance" then
            formatted[i] = arg.ClassName .. ": " .. arg:GetFullName()
        elseif argType == "function" then
            local info = getinfo(arg, "S")
            formatted[i] = string.format("Function: %s (defined at: %s)", tostring(arg), info.source)
        elseif argType == "vector" or argType == "CFrame" then
            formatted[i] = string.format("%s: %s", argType, tostring(arg))
        elseif arg == nil then
            formatted[i] = "nil"
        else
            formatted[i] = string.format("%s: %s", argType, tostring(arg))
        end
    end
    return table.concat(formatted, " | ")
end

--- Processes the log queue in a separate thread
-- @treturn nil
local function processLogQueue()
    if isProcessingQueue then return end
    isProcessingQueue = true
    
    task.spawn(function()
        while true do
            if #logQueue > 0 then
                local content = table.remove(logQueue, 1)
                local date = os.date("%Y-%m-%d")
                local filename = "remotelog_" .. date .. ".txt"
                
                pcall(function()
                    if not isfile(filename) then
                        writefile(filename, string.format("🔍 RemoteSpy Log Started: %s\nSession Duration: %.2f seconds\n\n", 
                            os.date(), os.clock() - startTime))
                    end
                    appendfile(filename, content .. "\n\n")
                end)
            end
            task.wait(0.1)
        end
    end)
end

--- Hook individual remote objects
-- @param remote RemoteEvent or RemoteFunction to hook
-- @treturn nil
local function hookRemote(remote)
    local oldIndex
    oldIndex = hookmetamethod(remote, "__index", newcclosure(function(self, k)
        local result = oldIndex(self, k)
        if typeof(result) == "function" then
            return newcclosure(function(...)
                local args = {...}
                local trace = traceback("Stack trace:", 2)
                local info = getinfo(2, "Sl")
                
                task.defer(function()
                    local logEntry = string.format([[
🔍 Remote Spy Detected:
Time: %s
Remote Name: %s
Remote Type: %s
Remote Path: %s
Method: %s
Direction: %s
Arguments: %s
Source: %s
Line: %s
%s
Session Duration: %.2f seconds
----------------]], 
                        os.date("%Y-%m-%d %H:%M:%S"),
                        remote.Name,
                        remote.ClassName,
                        remote:GetFullName(),
                        k,
                        k:match("Client") and "Server → Client" or "Client → Server",
                        formatArgs(args),
                        info and info.source or "Unknown",
                        info and info.currentline or 0,
                        trace,
                        os.clock() - startTime
                    )
                    
                    print(logEntry)
                    table.insert(logQueue, logEntry)
                    if not isProcessingQueue then
                        processLogQueue()
                    end
                end)
                
                return result(...)
            end)
        end
        return result
    end))
end

--- Initialize the RemoteSpy hook
-- @treturn nil
local function initializeHook()
    -- Hook existing remotes
    for _, remote in ipairs(game:GetDescendants()) do
        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
            hookRemote(remote)
        end
    end
    
    -- Hook new remotes
    game.DescendantAdded:Connect(function(remote)
        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
            hookRemote(remote)
        end
    end)
    
    -- Namecall hook for additional coverage
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        local result = oldNamecall(self, unpack(args))
        
        if (method:match("Server") or method:match("Client")) and 
           (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            
            local callerFrame = 2
            local info = getinfo(callerFrame, "Sl")
            local trace = traceback("Remote Call Stack:", callerFrame)
            
            task.defer(function()
                local logEntry = string.format([[
🔍 Remote Spy Detected (Namecall):
Time: %s
Remote Name: %s
Remote Type: %s
Remote Path: %s
Method: %s
Direction: %s
Arguments: %s
Source: %s
Line: %s
Stack Trace:
%s
Session Duration: %.2f seconds
----------------]], 
                    os.date("%Y-%m-%d %H:%M:%S"),
                    self.Name,
                    self.ClassName,
                    self:GetFullName(),
                    method,
                    method:match("Client") and "Server → Client" or "Client → Server",
                    formatArgs(args),
                    info and info.source or "Unknown",
                    info and info.currentline or 0,
                    trace,
                    os.clock() - startTime
                )
                
                print(logEntry)
                table.insert(logQueue, logEntry)
                if not isProcessingQueue then
                    processLogQueue()
                end
            end)
        end
        
        return result
    end))
end

-- Initialize RemoteSpy
initializeHook()
print(string.format("✅ RemoteSpy started - Full detailed logging enabled (Session: %.2f seconds)", os.clock() - startTime))

return RemoteSpy

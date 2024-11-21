local RemoteSpy = {}
RemoteSpy.__index = RemoteSpy

local logQueue = {}
local isProcessingQueue = false

--- Formats the arguments for logging
-- @param args Table of arguments to format
-- @return string Formatted argument string
local function formatArgs(args)
    if #args == 0 then
        return "No arguments"
    end
    
    local formatted = {}
    for i, arg in ipairs(args) do
        if typeof(arg) == "table" then
            formatted[i] = "Table [" .. table.concat(arg, ",") .. "]"
        elseif typeof(arg) == "Instance" then
            formatted[i] = arg.ClassName .. ": " .. arg:GetFullName()
        elseif typeof(arg) == "function" then
            formatted[i] = "Function: " .. tostring(arg)
        elseif arg == nil then
            formatted[i] = "nil"
        else
            formatted[i] = tostring(arg)
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
                        writefile(filename, "🔍 RemoteSpy Log Started: " .. os.date() .. "\n\n")
                    end
                    appendfile(filename, content .. "\n\n")
                end)
            end
            task.wait(0.1)
        end
    end)
end

--- Initialize the RemoteSpy hook
-- @treturn nil
local function initializeHook()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        -- Execute original function first to maintain game functionality
        local result = oldNamecall(self, unpack(args))
        
        -- Log remote calls after original execution
        if (method == "FireServer" or method == "InvokeServer") and 
           (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            
            -- Get debug info from the caller's context
            local trace = debug.traceback("\n")
            local info = debug.getinfo(2, "Sl")
            
            task.defer(function()
                local logEntry = string.format([[
🔍 Remote Spy Detected:
Time: %s
Remote Name: %s
Remote Type: %s
Remote Path: %s
Method: %s
Arguments: %s
Source: %s
Line: %s
Stack Trace:
%s
----------------]], 
                    os.date("%Y-%m-%d %H:%M:%S"),
                    self.Name,
                    self.ClassName,
                    self:GetFullName(),
                    method,
                    formatArgs(args),
                    info and info.source or "Unknown",
                    info and info.currentline or 0,
                    trace
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
print("✅ RemoteSpy started - Full detailed logging enabled")

return RemoteSpy

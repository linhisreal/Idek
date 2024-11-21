local RemoteSpy = {}
RemoteSpy.__index = RemoteSpy

local logQueue = {}
local isProcessingQueue = false
local startTime = os.clock()

local SUPPORTED_METHODS = {
    ["FireServer"] = true,
    ["InvokeServer"] = true,
    ["FireClient"] = true,
    ["InvokeClient"] = true
}

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
            local info = debug.getinfo(arg, "S")
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

--- Initialize the RemoteSpy hook with enhanced debugging
-- @treturn nil
local function initializeHook()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        local result = oldNamecall(self, unpack(args))
        
        if SUPPORTED_METHODS[method] and 
           (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            
            local callerFrame = 2
            local info = debug.getinfo(callerFrame, "Sl")
            local trace = debug.traceback("Remote Call Stack:", callerFrame)
            
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
Stack Trace:
%s
Session Duration: %.2f seconds
----------------]], 
                    os.date("%Y-%m-%d %H:%M:%S"),
                    self.Name,
                    self.ClassName,
                    self:GetFullName(),
                    method,
                    method:match("Server") and "Client → Server" or "Server → Client",
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

-- Initialize RemoteSpy with enhanced features
initializeHook()
print(string.format("✅ RemoteSpy started - Full detailed logging enabled (Session: %.2f seconds)", os.clock() - startTime))

return RemoteSpy

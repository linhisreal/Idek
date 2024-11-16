local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ContentProvider = game:GetService("ContentProvider")

local IWLoader = {
    Config = {
        BaseURL = "https://raw.githubusercontent.com/Kitler69/InfiniteWare/refs/heads/main/",
        Debug = true,
        RetryAttempts = 3,
        Version = "2.0-BETA",
        MemoryThreshold = 500000,
        SecurityKey = "IW_" .. HttpService:GenerateGUID(false),
        MaxCacheAge = 3600,
        KeyCheckInterval = 180,
        MaxSessionDuration = 86400,
        EncryptionKey = HttpService:GenerateGUID(false)
    },
    
    KeySystem = {
        ValidKeys = {},
        ActiveKey = nil,
        KeyData = {
            LastCheck = 0,
            Expiry = 0,
            Type = nil
        },
        KeyTypes = {
            FREE = {
                Prefix = "IW-FREE-",
                RateLimit = 50
            },
            DEVELOPER = {
                Prefix = "IW-DEV-",
                RateLimit = 1000
            }
        }
    },

    Cache = setmetatable({}, {
        __index = function(t, k)
            local cached = rawget(t, k)
            if cached and cached.timestamp + IWLoader.Config.MaxCacheAge > os.time() then
                return cached.data
            end
            return nil
        end,
        __newindex = function(t, k, v)
            rawset(t, k, {
                data = type(v) == "string" and v:gsub("%%", "%%%%") or v,
                timestamp = os.time(),
                size = #tostring(v)
            })
        end
    }),

    Games = {
        ["Slap_Battle"] = {
            PlaceIds = {6403373529},
            Script = "SlapBattle.lua",
            Version = "2.0.0",
            Priority = 1,
            RequiredMemory = 300000,
            AutoUpdate = true,
            Assets = {
                "rbxassetid://123456789",
                "rbxassetid://987654321"
            }
        },
        ["Fisch"] = {
            PlaceIds = {16732694052},
            Script = "Fisch",
            Version = "1.5.0",
            Priority = 2,
            RequiredMemory = 200000,
            AutoUpdate = true
        },
        ["Baseplate"] = {
            PlaceIds = {4483381587},
            Script = "Baseplate",
            Version = "1.2.0",
            Priority = 3,
            RequiredMemory = 100000,
            AutoUpdate = true
        }
    },

    Analytics = {
        LoadCount = 0,
        LastLoad = 0,
        Errors = {},
        Performance = {
            StartTime = os.clock(),
            MemoryUsage = 0,
            LoadTimes = {},
            NetworkLatency = {},
            FPS = {},
            MemoryPeaks = {}
        },
        SessionData = {
            StartTime = os.time(),
            GameChanges = {},
            ExecutionSuccess = {},
            UserData = {
                Hardware = {},
                Settings = {}
            }
        }
    },
    
    FileSystem = {
        Paths = {
            Base = "IW_Loader",
            Keys = "IW_Loader/Keys",
            Cache = "IW_Loader/Cache",
            KeyFile = "IW_Loader/Keys/keys.json",
            SessionFile = "IW_Loader/Keys/session.json"
        }
    }
}

function IWLoader:InitializeFileSystem()
    if not isfolder(self.FileSystem.Paths.Base) then
        makefolder(self.FileSystem.Paths.Base)
        makefolder(self.FileSystem.Paths.Keys)
        makefolder(self.FileSystem.Paths.Cache)
    end
end

function IWLoader:SaveKey(keyData)
    local success, encoded = pcall(HttpService.JSONEncode, HttpService, keyData)
    if success then
        writefile(self.FileSystem.Paths.KeyFile, encoded)
        return true
    end
    return false
end

function IWLoader:LoadSavedKey()
    if isfile(self.FileSystem.Paths.KeyFile) then
        local content = readfile(self.FileSystem.Paths.KeyFile)
        local success, decoded = pcall(HttpService.JSONDecode, HttpService, content)
        if success then
            return decoded
        end
    end
    return nil
end

function IWLoader:Log(message, messageType)
    if self.Config.Debug then
        local types = {
            ["info"] = "💡",
            ["success"] = "✅",
            ["error"] = "❌",
            ["warning"] = "⚠️",
            ["system"] = "⚙️",
            ["performance"] = "⚡",
            ["security"] = "🔒",
            ["auth"] = "🔑"
        }
        
        local timestamp = os.date("%H:%M:%S")
        local memoryUsage = math.floor(game:GetService("Stats"):GetTotalMemoryUsageMb())
        local fps = math.floor(1/RunService.Heartbeat:Wait())
        
        print(string.format("[IW-Loader %s | %dMB | %dFPS] %s: %s", 
            timestamp, 
            memoryUsage,
            fps,
            types[messageType] or "📝", 
            message
        ))
        
        table.insert(self.Analytics.Performance.FPS, fps)
        table.insert(self.Analytics.Performance.MemoryPeaks, memoryUsage)
    end
end

--[[
function IWLoader:ValidateKey(key)
    if not key then return false end
    
    local currentTime = os.time()
    
    local savedKey = self:LoadSavedKey()
    if savedKey and savedKey.key == key and currentTime < savedKey.expiry then
        self.KeySystem.ActiveKey = key
        self.KeySystem.KeyData = savedKey
        return true
    end
    
    local keyType = nil
    for type, data in pairs(self.KeySystem.KeyTypes) do
        if string.match(key, "^" .. data.Prefix) then
            keyType = type
            break
        end
    end
    
    if not keyType then
        self:Log("Invalid key format", "error")
        return false
    end
    
    local success, result = pcall(function()
        return {
            valid = true,
            expiry = currentTime + 86400,
            type = keyType,
            key = key,
            timestamp = currentTime
        }
    end)
    
    if success and result.valid then
        self.KeySystem.ActiveKey = key
        self.KeySystem.KeyData = result
        self:SaveKey(result)
        
        self:Log("Key validated successfully: " .. keyType, "success")
        return true
    end
    
    return false
end ]]

function IWLoader:ValidateKey(key)
    if not key then return false end
    
    local currentTime = os.time()
    
    -- Add these predefined valid keys
    self.KeySystem.ValidKeys = {
        ["IW-FREE-1234-5678-9ABC"] = {type = "FREE", expiry = currentTime + 86400},
        ["IW-DEV-1234-5678-9ABC"] = {type = "DEVELOPER", expiry = currentTime + 86400}
    }
    
    -- Check if key exists in valid keys
    if self.KeySystem.ValidKeys[key] then
        self.KeySystem.ActiveKey = key
        self.KeySystem.KeyData = {
            LastCheck = currentTime,
            Expiry = self.KeySystem.ValidKeys[key].expiry,
            Type = self.KeySystem.ValidKeys[key].type
        }
        self:Log("Key validated successfully: " .. self.KeySystem.ValidKeys[key].type, "success")
        return true
    end
    
    self:Log("Invalid key format", "error")
    return false
end


function IWLoader:ValidateEnvironment()
    local currentTime = os.time()
    
    if currentTime - self.Auth.SecurityChecks.LastEnvironmentValidation < 60 then
        return true
    end
    
    local success = pcall(function()
        return game:GetService("RunService") ~= nil 
            and game:GetService("Players") ~= nil 
            and game:GetService("Stats") ~= nil
    end)
    
    if not success then
        self:Log("Environment validation failed", "security")
        return false
    end
    
    self.Auth.SecurityChecks.LastEnvironmentValidation = currentTime
    return true
end

function IWLoader:CollectSystemInfo()
    local success, info = pcall(function()
        return {
            Memory = game:GetService("Stats"):GetTotalMemoryUsageMb(),
            Resolution = workspace.CurrentCamera.ViewportSize
        }
    end)
    
    if success then
        self.Analytics.SessionData.UserData.Hardware = info
    end
end

function IWLoader:CheckSystem()
    if not self.KeySystem.ActiveKey then
        self:Log("Key validation required!", "auth")
        return false
    end
    
    local stats = game:GetService("Stats")
    local currentMemory = stats:GetTotalMemoryUsageMb()
    self.Analytics.Performance.MemoryUsage = currentMemory
    
    if currentMemory > self.Config.MemoryThreshold then
        self:Log("Memory threshold exceeded - optimizing...", "performance")
        self:CleanupResources()
        
        if stats:GetTotalMemoryUsageMb() > self.Config.MemoryThreshold then
            self:Log("Critical memory usage persists!", "warning")
            return false
        end
    end
    
    return true
end

function IWLoader:CleanupResources()
    self.Cache = {}
    collectgarbage("collect")
    task.wait()
    game:GetService("ContentProvider"):PreloadAsync({})
end

function IWLoader:ValidateExecution(script, gameName)
    if not script then return false end
    
    local validationKey = string.format("%s_%s_%s", 
        self.Config.SecurityKey, 
        gameName, 
        self.KeySystem.ActiveKey
    )
    
    return pcall(function()
        local env = getfenv()
        env.IWLoader = setmetatable({
            _validation = validationKey,
            Version = self.Config.Version,
            KeyData = {
                Type = self.KeySystem.KeyData.Type,
                Key = self.KeySystem.ActiveKey
            }
        }, {
            __index = self,
            __newindex = function()
                self:Log("Attempted to modify loader environment!", "security")
                return false
            end
        })
        
        local execFunc = loadstring(script)
        setfenv(execFunc, env)
        return execFunc()
    end)
end

function IWLoader:ExecuteGameScript(scriptUrl, gameName, gameData)
    local startTime = os.clock()
    
    if not self:CheckSystem() then
        return false
    end
    
    local cacheFile = self.FileSystem.Paths.Cache .. "/" .. gameName .. ".lua"
    ContentProvider:PreloadAsync(gameData.Assets or {})
    
    for attempt = 1, self.Config.RetryAttempts do
        if isfile(cacheFile) then
            self:Log("Using cached script", "info")
            local cachedScript = readfile(cacheFile)
            local success = self:ValidateExecution(cachedScript, gameName)
            if success then 
                self:UpdateAnalytics(gameName, true, os.clock() - startTime)
                return true 
            end
        end
        
        local success, script = pcall(function()
            return game:HttpGet(scriptUrl)
        end)
        
        if success then
            local execSuccess = self:ValidateExecution(script, gameName)
            
            if execSuccess then
                writefile(cacheFile, script)
                self:Log("Script cached successfully", "success")
                self:UpdateAnalytics(gameName, true, os.clock() - startTime)
                return true
            end
        end
        
        self:Log(string.format("Execution attempt %d/%d failed", attempt, self.Config.RetryAttempts), "warning")
        self:UpdateAnalytics(gameName, false, os.clock() - startTime)
        
        if attempt < self.Config.RetryAttempts then
            task.wait(attempt * 1.5)
        end
    end
    return false
end

function IWLoader:UpdateAnalytics(gameName, success, loadTime)
    table.insert(self.Analytics.Performance.LoadTimes, loadTime)
    self.Analytics.SessionData.ExecutionSuccess[gameName] = success
    
    if success then
        self:Log(string.format("Load time: %.2f seconds", loadTime), "performance")
    else
        table.insert(self.Analytics.Errors, {
            timestamp = os.time(),
            game = gameName,
            memory = self.Analytics.Performance.MemoryUsage,
            loadTime = loadTime,
            fps = self.Analytics.Performance.FPS[#self.Analytics.Performance.FPS]
        })
    end
end

function IWLoader:LoadGame()
    if not self.KeySystem.ActiveKey then
        self:Log("Please enter a valid key to continue", "error")
        return false
    end
    
    local currentPlaceId = game.PlaceId
    self.Analytics.LoadCount += 1
    self.Analytics.LastLoad = os.time()
    
    for gameName, gameData in pairs(self.Games) do
        if table.find(gameData.PlaceIds, currentPlaceId) then
            self:Log(string.format("Initializing %s v%s", gameName, gameData.Version), "info")
            
            if gameData.Script then
                local scriptUrl = self.Config.BaseURL .. gameData.Script
                return self:ExecuteGameScript(scriptUrl, gameName, gameData)
            end
        end
    end
    
    self:Log("Game not supported", "error")
    return false
end

if not RunService:IsStudio() then
    task.spawn(function()
        IWLoader:InitializeFileSystem()
        IWLoader:Log("IW-Loader v" .. IWLoader.Config.Version .. " initializing...", "system")
        local userKey = "IW-FREE-1234-5678-9ABC"
        if IWLoader:ValidateKey(userKey) then
            return IWLoader:LoadGame()
        end
    end)
end

return IWLoader

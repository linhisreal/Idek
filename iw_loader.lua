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
        Version = "7.0.0",
        MemoryThreshold = 500000,
        SecurityKey = "IW_" .. HttpService:GenerateGUID(false),
        MaxCacheAge = 3600,
        AuthRefreshInterval = 180,
        MaxSessionDuration = 86400,
        EncryptionKey = HttpService:GenerateGUID(false)
    },
    
    Auth = {
        Keys = {
            ["STANDARD"] = {
                Key = "IW-STANDARD-2024",
                Expires = 0,
                RateLimit = 100
            },
            ["DEVELOPER"] = {
                Key = "IW-DEVELOPER-2024",
                Expires = 0,
                RateLimit = 1000,
                AllowedUserIds = {1234567890, 9876543210}
            }
        },
        Session = nil,
        Verified = false,
        LastVerification = 0,
        Heartbeat = 0,
        RequestCount = 0,
        LastRequestReset = 0,
        TokenRotation = {},
        SecurityChecks = {
            LastIntegrityCheck = 0,
            LastEnvironmentValidation = 0
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
            RequiredTier = "STANDARD",
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
            RequiredTier = "STANDARD",
            AutoUpdate = true
        },
        ["Baseplate"] = {
            PlaceIds = {4483381587},
            Script = "Baseplate",
            Version = "1.2.0",
            Priority = 3,
            RequiredMemory = 100000,
            RequiredTier = "STANDARD",
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
    }
}

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

function IWLoader:ValidateAuth(key)
    if not key then return false end
    
    local currentTime = os.time()
    if currentTime - self.Auth.LastRequestReset >= 3600 then
        self.Auth.RequestCount = 0
        self.Auth.LastRequestReset = currentTime
    end
    
    if self.Auth.Session and currentTime - self.Auth.LastVerification > self.Config.MaxSessionDuration then
        self.Auth.Verified = false
        self.Auth.Session = nil
    end
    
    if self.Auth.Verified and currentTime - self.Auth.LastVerification < self.Config.AuthRefreshInterval then
        self.Auth.Heartbeat = currentTime
        return true
    end
    
    local player = Players.LocalPlayer
    for tier, data in pairs(self.Auth.Keys) do
        if data.Key == key then
            if tier == "DEVELOPER" and not table.find(data.AllowedUserIds, player.UserId) then
                continue
            end
            
            if data.Expires == 0 or currentTime < data.Expires then
                if self.Auth.RequestCount >= data.RateLimit then
                    self:Log("Rate limit exceeded for " .. tier, "security")
                    return false
                end
                
                local sessionToken = self:GenerateSessionToken(player.UserId, tier)
                self.Auth.Session = sessionToken
                self.Auth.Verified = true
                self.Auth.Tier = tier
                self.Auth.LastVerification = currentTime
                self.Auth.Heartbeat = currentTime
                self.Auth.RequestCount += 1
                
                self:CollectSystemInfo()
                self:Log("Authentication successful with " .. tier .. " tier!", "auth")
                return true
            end
        end
    end
    
    self:Log("Authentication failed", "auth")
    return false
end

function IWLoader:GenerateSessionToken(userId, tier)
    local timestamp = os.time()
    local randomSeed = HttpService:GenerateGUID(false)
    local tokenData = string.format("%d_%s_%s_%d", userId, tier, randomSeed, timestamp)
    local encrypted = self:EncryptString(tokenData, self.Config.EncryptionKey)
    self.Auth.TokenRotation[encrypted] = timestamp
    return encrypted
end

function IWLoader:EncryptString(str, key)
    local result = {}
    local keyLength = #key
    
    for i = 1, #str do
        local charByte = string.byte(str, i)
        local keyByte = string.byte(key, ((i-1) % keyLength) + 1)
        table.insert(result, string.char(bit32.bxor(charByte, keyByte)))
    end
    
    return table.concat(result)
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
    if not self.Auth.Verified then
        self:Log("Authentication required!", "auth")
        return false
    end
    
    if os.time() - self.Auth.Heartbeat > 300 then
        self:Log("Session expired - revalidating...", "auth")
        return self:ValidateAuth(self.Auth.Keys[self.Auth.Tier].Key)
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
        self.Auth.Session
    )
    
    return pcall(function()
        local env = getfenv()
        env.IWLoader = setmetatable({
            _validation = validationKey,
            Version = self.Config.Version,
            Auth = {
                Tier = self.Auth.Tier,
                Session = self.Auth.Session
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
    
    ContentProvider:PreloadAsync(gameData.Assets or {})
    
    for attempt = 1, self.Config.RetryAttempts do
        if self.Cache[scriptUrl] then
            self:Log("Using cached script", "info")
            local success = self:ValidateExecution(self.Cache[scriptUrl], gameName)
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
                self.Cache[scriptUrl] = script
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
    local currentPlaceId = game.PlaceId
    self.Analytics.LoadCount += 1
    self.Analytics.LastLoad = os.time()
    
    for gameName, gameData in pairs(self.Games) do
        if table.find(gameData.PlaceIds, currentPlaceId) then
            self:Log(string.format("Initializing %s v%s (Priority: %d)", 
                gameName, 
                gameData.Version, 
                gameData.Priority
            ), "info")
            
            if gameData.Script then
                local scriptUrl = self.Config.BaseURL .. gameData.Script
                local success = self:ExecuteGameScript(scriptUrl, gameName, gameData)
                
                if success then
                    self:Log(string.format("Successfully loaded %s!", gameName), "success")
                    return true
                end
            end
            return false
        end
    end
    
    self:Log("Game not supported in IW-Loader", "error")
    return false
end

if not RunService:IsStudio() then
    task.spawn(function()
        IWLoader:Log(string.format("IW-Loader v%s initializing...", IWLoader.Config.Version), "system")
        if IWLoader:ValidateAuth("IW-STANDARD-2024") then
            return IWLoader:LoadGame()
        end
    end)
end

return IWLoader


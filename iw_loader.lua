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
        Version = "7.1.0",
        MemoryThreshold = 500000,
        SecurityKey = "IW_" .. HttpService:GenerateGUID(false),
        MaxCacheAge = 3600,
        AuthRefreshInterval = 300,
        MaxSessionDuration = 7200,
        EncryptionKey = HttpService:GenerateGUID(false),
        KeyFolder = "InfiniteWare",
        KeyFile = "auth.iw"
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
            LastEnvironmentValidation = 0,
            BlacklistedHWIDs = {}
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
            Version = "2.1.0",
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
            Script = "Fisch.lua",
            Version = "1.6.0",
            Priority = 2,
            RequiredMemory = 200000,
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
        }
    }
}

function IWLoader:InitializeFileSystem()
    if not isfolder(self.Config.KeyFolder) then
        makefolder(self.Config.KeyFolder)
    end
end

function IWLoader:SaveKeyData(keyData)
    self:InitializeFileSystem()
    local encryptedData = self:EncryptString(HttpService:JSONEncode(keyData), self.Config.EncryptionKey)
    writefile(self.Config.KeyFolder .. "/" .. self.Config.KeyFile, encryptedData)
end

function IWLoader:LoadKeyData()
    if not isfile(self.Config.KeyFolder .. "/" .. self.Config.KeyFile) then
        return nil
    end
    
    local encryptedData = readfile(self.Config.KeyFolder .. "/" .. self.Config.KeyFile)
    local success, data = pcall(function()
        return HttpService:JSONDecode(self:EncryptString(encryptedData, self.Config.EncryptionKey))
    end)
    
    return success and data or nil
end

function IWLoader:ValidateKey(key)
    if not key then return false end
    
    local player = Players.LocalPlayer
    if not player then return false end
    
    local hwid = HttpService:GenerateGUID(false) .. "-" .. 
                 tostring(player.UserId) .. "-" ..
                 game:GetService("RbxAnalyticsService"):GetClientId()
    
    if table.find(self.Auth.SecurityChecks.BlacklistedHWIDs, hwid) then
        self:Log("Blacklisted HWID detected", "security")
        return false
    end
    
    local savedData = self:LoadKeyData()
    if savedData and savedData.key == key and savedData.hwid == hwid then
        if savedData.expires == 0 or savedData.expires > os.time() then
            self.Auth.Session = self:GenerateSessionToken(player.UserId, savedData.tier, hwid)
            self.Auth.Verified = true
            self.Auth.Tier = savedData.tier
            self.Auth.LastVerification = os.time()
            self.Auth.Heartbeat = os.time()
            self.Auth.HWID = hwid
            
            self:Log("Key verification successful from cache: " .. savedData.tier, "auth")
            return true
        end
    end

    for tier, data in pairs(self.Auth.Keys) do
        if data.Key == key then
            if tier == "DEVELOPER" and not table.find(data.AllowedUserIds, player.UserId) then
                continue
            end
            
            local keyData = {
                key = key,
                hwid = hwid,
                tier = tier,
                timestamp = os.time(),
                expires = data.Expires,
                userId = player.UserId
            }
            
            self:SaveKeyData(keyData)
            
            self.Auth.Session = self:GenerateSessionToken(player.UserId, tier, hwid)
            self.Auth.Verified = true
            self.Auth.Tier = tier
            self.Auth.LastVerification = os.time()
            self.Auth.Heartbeat = os.time()
            self.Auth.HWID = hwid
            
            self:Log("Key verification successful: " .. tier, "auth")
            return true
        end
    end
    
    self:Log("Key verification failed", "auth")
    return false
end

function IWLoader:GenerateSessionToken(userId, tier, hwid)
    local timestamp = os.time()
    local randomSeed = HttpService:GenerateGUID(false)
    local tokenData = string.format("%d_%s_%s_%s_%d", 
        userId, 
        tier, 
        hwid,
        randomSeed, 
        timestamp
    )
    return self:EncryptString(tokenData, self.Config.EncryptionKey)
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
    end
end

function IWLoader:ExecuteGameScript(scriptUrl, gameName, gameData)
    local startTime = os.clock()
    
    if not self:CheckSession() then
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
        if IWLoader:ValidateKey("YOUR-KEY-HERE") then
            return IWLoader:LoadGame()
        end
    end)
end

return IWLoader

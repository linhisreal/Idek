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
        KeyFile = "IW/keys.iw",
        KeyFolder = "IW",
        KeyFormat = "IW-%s-%s"
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
    end
end

function IWLoader:InitializeFileSystem()
    if not isfolder(self.Config.KeyFolder) then
        makefolder(self.Config.KeyFolder)
    end
    
    if not isfile(self.Config.KeyFile) then
        writefile(self.Config.KeyFile, HttpService:JSONEncode({
            keys = {},
            lastCheck = os.time()
        }))
    end
end

function IWLoader:ValidateKey(key)
    if not key then return false end
    
    local player = Players.LocalPlayer
    if not player then return false end
    
    self:InitializeFileSystem()
    
    local success, keyData = pcall(function()
        return HttpService:JSONDecode(readfile(self.Config.KeyFile))
    end)
    
    if not success then
        self:Log("Key file corrupted, resetting...", "warning")
        writefile(self.Config.KeyFile, HttpService:JSONEncode({
            keys = {},
            lastCheck = os.time()
        }))
        return false
    end
    
    local hwid = HttpService:GenerateGUID(false) .. "-" .. 
                 tostring(player.UserId) .. "-" ..
                 game:GetService("RbxAnalyticsService"):GetClientId()
    
    if table.find(self.Auth.SecurityChecks.BlacklistedHWIDs, hwid) then
        self:Log("Blacklisted HWID detected", "security")
        return false
    end
    
    local tier, timestamp = key:match("IW%-(%w+)%-(%d+)")
    if not tier or not timestamp then
        self:Log("Invalid key format", "error")
        return false
    end
    
    if not keyData.keys[key] then
        keyData.keys[key] = {
            tier = tier,
            timestamp = tonumber(timestamp),
            hwid = hwid,
            uses = 0
        }
        writefile(self.Config.KeyFile, HttpService:JSONEncode(keyData))
    end
    
    local keyInfo = keyData.keys[key]
    
    if keyInfo.hwid ~= hwid then
        self:Log("Key bound to different HWID", "security")
        return false
    end
    
    self.Auth.Session = self:GenerateSessionToken(player.UserId, tier, hwid)
    self.Auth.Verified = true
    self.Auth.Tier = tier
    self.Auth.LastVerification = os.time()
    self.Auth.Heartbeat = os.time()
    self.Auth.HWID = hwid
    
    keyInfo.uses += 1
    keyInfo.lastUse = os.time()
    writefile(self.Config.KeyFile, HttpService:JSONEncode(keyData))
    
    self:Log("Key verification successful: " .. tier, "auth")
    return true
end

function IWLoader:GenerateKey(tier)
    local timestamp = os.time()
    return string.format(self.Config.KeyFormat, tier, timestamp)
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

function IWLoader:CheckSession()
    if not self.Auth.Verified then
        return false
    end
    
    local currentTime = os.time()
    if currentTime - self.Auth.LastVerification > self.Config.MaxSessionDuration then
        self.Auth.Verified = false
        self.Auth.Session = nil
        return false
    end
    
    if currentTime - self.Auth.Heartbeat > self.Config.AuthRefreshInterval then
        return self:ValidateKey(self.Auth.Keys[self.Auth.Tier].Key)
    end
    
    return true
end

function IWLoader:LoadGame()
    local currentPlaceId = game.PlaceId
    
    for gameName, gameData in pairs(self.Games) do
        if table.find(gameData.PlaceIds, currentPlaceId) then
            self:Log(string.format("Loading %s v%s", gameName, gameData.Version), "info")
            
            if gameData.Script then
                -- Create scripts folder if it doesn't exist
                local scriptsFolder = self.Config.KeyFolder .. "/scripts"
                if not isfolder(scriptsFolder) then
                    makefolder(scriptsFolder)
                end
                
                local scriptPath = scriptsFolder .. "/" .. gameData.Script
                local scriptUrl = self.Config.BaseURL .. gameData.Script
                
                -- Download script if it doesn't exist
                if not isfile(scriptPath) then
                    local success, content = pcall(game.HttpGet, game, scriptUrl)
                    if success then
                        writefile(scriptPath, content)
                    else
                        self:Log("Failed to download script", "error")
                        return false
                    end
                end
                
                -- Load and execute script
                local success, result = pcall(loadfile, scriptPath)
                if success and result then
                    self:Log("Successfully loaded " .. gameName, "success")
                    return true
                end
            end
            
            self:Log("Failed to load " .. gameName, "error")
            return false
        end
    end
    
    self:Log("Game not supported", "warning")
    return false
end


if not RunService:IsStudio() then
    task.spawn(function()
        IWLoader:Log(string.format("IW-Loader v%s initializing...", IWLoader.Config.Version), "system")
        local key = IWLoader:GenerateKey("STANDARD")
        if IWLoader:ValidateKey(key) then
            return IWLoader:LoadGame()
        end
    end)
end

return IWLoader

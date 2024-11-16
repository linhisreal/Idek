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
    
    SecuritySystem = {
        Signatures = {},
        ActiveSessions = {},
        TempModules = {},
        SecurityChecks = {
            LastValidation = 0,
            EnvironmentFingerprint = HttpService:GenerateGUID(false),
            SignatureFile = "IW_Loader/Keys/signature.iw"
        }
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
            SessionFile = "IW_Loader/Keys/session.json",
            TempModules = "IW_Loader/Temp"
        }
    }
}

function IWLoader:InitializeFileSystem()
    if not isfolder(self.FileSystem.Paths.Base) then
        makefolder(self.FileSystem.Paths.Base)
        makefolder(self.FileSystem.Paths.Keys)
        makefolder(self.FileSystem.Paths.Cache)
        makefolder(self.FileSystem.Paths.TempModules)
    end
end

function IWLoader:CreateTempAuthModule()
    local moduleName = "IW_Auth_" .. HttpService:GenerateGUID(false)
    local moduleContent = string.format([[
        local module = {
            timestamp = %d,
            signature = "%s",
            verified = false
        }
        
        function module:Verify(key)
            if os.time() - self.timestamp > 30 then return false end
            return key:match("^IW%-[%w]+%-[%w]+$") ~= nil
        end
        
        return module
    ]], os.time(), self.Config.SecurityKey)
    
    writefile(self.FileSystem.Paths.TempModules .. "/" .. moduleName .. ".lua", moduleContent)
    return moduleName
end

function IWLoader:SaveKey(keyData)
    local encrypted = self:EncryptData(HttpService:JSONEncode(keyData))
    local signature = HttpService:GenerateGUID(false) .. "_" .. os.time()
    
    local success = pcall(function()
        writefile(self.FileSystem.Paths.KeyFile, encrypted)
        writefile(self.SecuritySystem.SecurityChecks.SignatureFile, signature)
    end)
    return success
end

function IWLoader:EncryptData(data)
    local result = ""
    for i = 1, #data do
        local byte = string.byte(data, i)
        result = result .. string.char(bit32.bxor(byte, string.byte(self.Config.EncryptionKey, 
            (i % #self.Config.EncryptionKey) + 1)))
    end
    return result
end

function IWLoader:DecryptData(data)
    return self:EncryptData(data)
end

function IWLoader:ValidateKey(key)
    if not key then return false end
    
    local currentTime = os.time()
    local authModuleName = self:CreateTempAuthModule()
    
    local success, authModule = pcall(function()
        local content = readfile(self.FileSystem.Paths.TempModules .. "/" .. authModuleName .. ".lua")
        return loadstring(content)()
    end)
    
    pcall(function()
        delfile(self.FileSystem.Paths.TempModules .. "/" .. authModuleName .. ".lua")
    end)
    
    if not success or not authModule:Verify(key) then
        self:Log("Key verification failed", "security")
        return false
    end

    local keyType = string.match(key, "^IW%-(%w+)%-")
    if keyType ~= "FREE" and keyType ~= "DEV" then
        self:Log("Invalid key type", "error")
        return false
    end
    
    local keyData = {
        key = key,
        type = keyType,
        timestamp = currentTime,
        expiry = currentTime + 86400,
        signature = HttpService:GenerateGUID(false)
    }
    
    self.KeySystem.ActiveKey = key
    self.KeySystem.KeyData = keyData
    
    self:SaveKey(keyData)
    self:Log("Key validated successfully: " .. keyType, "success")
    
    return true
end

function IWLoader:ValidateEnvironment()
    local currentTime = os.time()
    
    if currentTime - self.SecuritySystem.SecurityChecks.LastValidation < 60 then
        return true
    end
    
    local success = pcall(function()
        return game:GetService("RunService") ~= nil 
            and game:GetService("Players") ~= nil 
            and game:GetService("Stats") ~= nil
            and isfile(self.SecuritySystem.SecurityChecks.SignatureFile)
    end)
    
    if not success then
        self:Log("Environment validation failed", "security")
        return false
    end
    
    self.SecuritySystem.SecurityChecks.LastValidation = currentTime
    return true
end

function IWLoader:ValidateExecution(script, gameName)
    if not script then return false end
    
    local executionContext = {
        timestamp = os.time(),
        gameHash = HttpService:GenerateGUID(false),
        signature = string.format("%s_%s_%s", 
            self.Config.SecurityKey,
            self.SecuritySystem.SecurityChecks.EnvironmentFingerprint,
            self.KeySystem.KeyData.signature
        )
    }
    
    local secureEnv = setmetatable({
        IWLoader = {
            Version = self.Config.Version,
            GameData = {
                Name = gameName,
                Context = executionContext
            },
            Security = {
                KeyType = self.KeySystem.KeyData.type,
                SessionId = self.SecuritySystem.ActiveSessions[1]
            }
        }
    }, {
        __index = getfenv(),
        __metatable = "Locked"
    })
    
    return pcall(function()
        local execFunc = loadstring(script)
        setfenv(execFunc, secureEnv)
        return execFunc()
    end)
end

function IWLoader:ExecuteGameScript(scriptUrl, gameName, gameData)
    local startTime = os.clock()

    if not self:CheckSystem() or not self:ValidateEnvironment() then
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

if not RunService:IsStudio() then
    task.spawn(function()
        IWLoader:InitializeFileSystem()
        
        -- Generate unique hardware ID for key
        local hwid = game:GetService("RbxAnalyticsService"):GetClientId()
        local userKey = "IW-FREE-" .. string.upper(string.sub(hwid, 1, 8))
        
        local sessionData = {
            id = HttpService:GenerateGUID(false),
            startTime = os.time(),
            fingerprint = hwid,
            validationKey = IWLoader.Config.SecurityKey
        }
        
        -- Save encrypted session
        writefile(IWLoader.FileSystem.Paths.SessionFile, 
            IWLoader:EncryptData(HttpService:JSONEncode(sessionData)))
        
        task.spawn(function()
            while task.wait(30) do
                if not IWLoader:ValidateEnvironment() then
                    IWLoader:Log("Security check failed - terminating", "security")
                    break
                end
            end
        end)
        
        IWLoader:Log("IW-Loader v" .. IWLoader.Config.Version .. " initializing...", "system")
        
        if IWLoader:ValidateKey(userKey) then
            return IWLoader:LoadGame()
        end
    end)
end

return IWLoader

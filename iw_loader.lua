local HttpService = cloneref(game:GetService("HttpService"))
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ContentProvider = game:GetService("ContentProvider")

local function generateSecureToken()
    return HttpService:GenerateGUID(false) .. "_" .. os.time() .. "_" .. game:GetService("RbxAnalyticsService"):GetClientId()
end

local IWLoader = {
    Config = {
        BaseURL = "https://raw.githubusercontent.com/Kitler69/InfiniteWare/refs/heads/main/",
        Debug = true,
        RetryAttempts = 3,
        Version = "2.0-BETA",
        MemoryThreshold = 500000,
        SecurityKey = generateSecureToken(),
        MaxCacheAge = 3600,
        KeyCheckInterval = 180,
        MaxSessionDuration = 86400,
        EncryptionKey = HttpService:GenerateGUID(false),
        AuthModuleName = "IW_TempAuth_" .. HttpService:GenerateGUID(false)
    },
    
    KeySystem = {
        ValidKeys = {},
        ActiveKey = nil,
        KeyData = {
            LastCheck = 0,
            Expiry = 0,
            Type = nil,
            HardwareId = nil,
            SessionToken = nil
        },
        KeyTypes = {
            FREE = {
                Prefix = "IW-FREE-",
                RateLimit = 50,
                MaxSessions = 1
            },
            DEVELOPER = {
                Prefix = "IW-DEV-",
                RateLimit = 1000,
                MaxSessions = 3
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

function IWLoader:HandleSecurity(action, data)
    local function encrypt(input)
        local result = ""
        for i = 1, #input do
            result ..= string.char(bit32.bxor(string.byte(input, i), 
                string.byte(self.Config.EncryptionKey, (i % #self.Config.EncryptionKey) + 1)))
        end
        return result
    end

    local actions = {
        save = function(path, content)
            local encoded = HttpService:JSONEncode(content)
            writefile(path, encrypt(encoded))
            return true
        end,
        load = function(path)
            if isfile(path) then
                local content = readfile(path)
                local decoded = HttpService:JSONDecode(encrypt(content))
                return decoded
            end
            return nil
        end,
        validate = function(key)
            if not key then return false end
            
            local tempModule = Instance.new("ModuleScript")
            tempModule.Name = self.Config.AuthModuleName
            
            local keyType = string.match(key, "^IW%-(%w+)%-")
            if not keyType or not self.KeySystem.KeyTypes[keyType] then
                tempModule:Destroy()
                return false
            end

            self.KeySystem.ActiveKey = key
            self.KeySystem.KeyData = {
                LastCheck = os.time(),
                Expiry = os.time() + 86400,
                Type = keyType,
                HardwareId = game:GetService("RbxAnalyticsService"):GetClientId(),
                SessionToken = generateSecureToken()
            }

            task.delay(3, function() tempModule:Destroy() end)
            return true
        end
    }

    return actions[action] and actions[action](data)
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

function IWLoader:ManageSystem(operation)
    local operations = {
        initialize = function()
            if not isfolder(self.FileSystem.Paths.Base) then
                for _, path in pairs(self.FileSystem.Paths) do
                    if not string.find(path, "%.") then
                        makefolder(path)
                    end
                end
                self:HandleSecurity("save", self.FileSystem.Paths.SessionFile, {
                    token = generateSecureToken(),
                    timestamp = os.time()
                })
            end
        end,
        
        check = function()
            if not self.KeySystem.ActiveKey then return false end
            
            local stats = game:GetService("Stats")
            local memory = stats:GetTotalMemoryUsageMb()
            self.Analytics.Performance.MemoryUsage = memory
            
            if memory > self.Config.MemoryThreshold then
                self:Log("Memory threshold exceeded - optimizing...", "performance")
                self.Cache = {}
                collectgarbage("collect")
                task.wait()
                
                if stats:GetTotalMemoryUsageMb() > self.Config.MemoryThreshold then
                    self:Log("Critical memory usage persists!", "warning")
                    return false
                end
            end
            return true
        end,
        
        validate = function()
            local session = self:HandleSecurity("load", self.FileSystem.Paths.SessionFile)
            if not session or 
               os.time() - session.timestamp > self.Config.MaxSessionDuration or
               session.token ~= self.KeySystem.KeyData.SessionToken then
                self:Log("Session validation failed", "security")
                return false
            end
            return true
        end
    }

    return operations[operation] and operations[operation]()
end

function IWLoader:ExecuteGameScript(scriptUrl, gameName, gameData)
    local startTime = os.clock()
    
    if not self:ManageSystem("check") then
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
        IWLoader:ManageSystem("initialize")
        IWLoader:Log("IW-Loader v" .. IWLoader.Config.Version .. " initializing...", "system")
        
        getgenv().key = " "
        if IWLoader:HandleSecurity("validate", getgenv().key) then
            return IWLoader:LoadGame()
        end
    end)
end

return IWLoader

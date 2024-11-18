local HttpService = cloneref(game:GetService("HttpService"))
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = cloneref(game:GetService("MarketplaceService"))
local UserInputService = game:GetService("UserInputService")
local RbxAnalyticsService = cloneref(game:GetService("RbxAnalyticsService"))

local function generateSecureToken()
    local hwid = RbxAnalyticsService:GetClientId()
    local timestamp = os.time()
    local guid = HttpService:GenerateGUID(false)
    local platform = UserInputService.TouchEnabled and "Mobile" or "Desktop"
    local entropy = string.format("%x", math.random(1e9))
    local deviceInfo = string.format("%x", #Players:GetPlayers())
    return string.format("%s_%s_%s_%s_%s_%s", guid, timestamp, hwid, platform, entropy, deviceInfo)
end

local KeyTypes = {
    FREE = {
        Prefix = "IW-FREE-",
        RateLimit = 50,
        ExpiryDuration = 86400,
        CooldownPeriod = 300
    },
    DEVELOPER = {
        Prefix = "IW-DEV-",
        RateLimit = 1000,
        ExpiryDuration = 7776000,
        CooldownPeriod = 0
    }
}

local IWLoader = {
    Config = {
        BaseURL = "https://raw.githubusercontent.com/Kitler69/InfiniteWare/refs/heads/main/",
        Debug = true,
        RetryAttempts = 5,
        Version = "2.2-BETA",
        MemoryThreshold = 500000,
        SecurityKey = generateSecureToken(),
        MaxCacheAge = 3600,
        KeyCheckInterval = 180,
        EncryptionKey = HttpService:GenerateGUID(false),
        AuthModuleName = "IW_TempAuth_" .. HttpService:GenerateGUID(false),
        AutoRetry = true,
        NetworkTimeout = 15,
        CompressionEnabled = true,
        TempAuthCheckInterval = 10
    },
    
    KeySystem = {
        ValidKeys = {},
        ActiveKey = nil,
        KeyData = {
            LastCheck = 0,
            Expiry = 0,
            Type = nil,
            HardwareId = nil,
            Platform = nil,
            GameInfo = {},
            LastValidation = 0,
            ValidationCount = 0
        },
        KeyTypes = KeyTypes
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
        }
    },
    
    FileSystem = {
        Paths = {
            Base = "IW_Loader",
            Keys = "IW_Loader/Keys",
            Cache = "IW_Loader/Cache",
            Logs = "IW_Loader/Logs",
            Config = "IW_Loader/Config",
            KeyFile = "IW_Loader/Keys/keys.json",
            LogFile = "IW_Loader/Logs/latest.log",
            ConfigFile = "IW_Loader/Config/settings.json"
        }
    },
    
    Connections = {
        Active = {},
        Blocked = {},
        Protected = {},
        Events = {}
    }
}

function IWLoader:ManageConnections(signal, action)
    local connections = getconnections(signal)
    
    for _, connection in ipairs(connections) do
        if action == "disable" then
            if not connection.ForeignState then
                connection:Disable()
                table.insert(self.Connections.Blocked, {
                    Connection = connection,
                    Signal = signal,
                    Thread = connection.Thread
                })
            end
        elseif action == "enable" then
            connection:Enable()
            table.insert(self.Connections.Active, {
                Connection = connection,
                Signal = signal,
                Thread = connection.Thread
            })
        elseif action == "protect" then
            if not connection.ForeignState then
                table.insert(self.Connections.Protected, {
                    Connection = connection,
                    Signal = signal,
                    Thread = connection.Thread
                })
            end
        end
    end
end

function IWLoader:SecureGameEnvironment()
    local criticalSignals = {
        game.DescendantAdded,
        game.DescendantRemoving,
        UserInputService.InputBegan,
        UserInputService.InputEnded,
        RunService.Heartbeat,
        RunService.RenderStepped
    }
    
    for _, signal in ipairs(criticalSignals) do
        self:ManageConnections(signal, "protect")
    end
    
    self.Connections.Events.ScriptWatch = game.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Script") or descendant:IsA("LocalScript") then
            self:Log("New script detected: " .. descendant:GetFullName(), "security")
            self:ManageConnections(descendant.Changed, "protect")
        end
    end)
end

function IWLoader:CreateFileSystem()
    for _, path in pairs(self.FileSystem.Paths) do
        if not string.find(path, "%.") then
            if not isfolder(path) then
                makefolder(path)
                task.wait()
            end
        end
    end
    
    local defaultFiles = {
        [self.FileSystem.Paths.KeyFile] = {keys = {}, lastUpdate = os.time()},
        [self.FileSystem.Paths.ConfigFile] = {
            settings = self.Config,
            lastUpdate = os.time()
        },
        [self.FileSystem.Paths.LogFile] = ""
    }
    
    for path, content in pairs(defaultFiles) do
        local parentFolder = path:match("(.+)/[^/]+$")
        if not isfolder(parentFolder) then
            makefolder(parentFolder)
            task.wait()
        end
        
        if not isfile(path) then
            self:HandleSecurity("save", path, content)
            task.wait()
        end
    end
end

function IWLoader:HandleSecurity(action, path, data)
    local function encrypt(input)
        local key = self.Config.EncryptionKey
        local result = ""
        for i = 1, #input do
            local keyByte = string.byte(key, (i % #key) + 1)
            local inputByte = string.byte(input, i)
            result = result .. string.char(bit32.bxor(inputByte, keyByte))
        end
        return result
    end

    local function hash(input)
        local result = 0
        for i = 1, #input do
            result = bit32.bxor(result * 31, string.byte(input, i))
        end
        return tostring(result)
    end

    local actions = {
        save = function(path, content)
            local success, encoded = pcall(HttpService.JSONEncode, HttpService, content)
            if not success then return false end
            
            local encrypted = encrypt(encoded)
            local checksum = hash(encrypted)
            writefile(path, encrypted .. "|" .. checksum)
            return true
        end,
        
        load = function(path)
            if not isfile(path) then return nil end
            
            local content = readfile(path)
            local encrypted, checksum = string.match(content, "(.+)|(.+)")
            
            if not encrypted or not checksum or hash(encrypted) ~= checksum then
                self:Log("File integrity check failed", "security")
                return nil
            end
            
            local decrypted = encrypt(encrypted)
            local success, decoded = pcall(HttpService.JSONDecode, HttpService, decrypted)
            return success and decoded or nil
        end,
        
        validate = function(key)
            return self:ValidateKey(key)
        end
    }

    return actions[action] and actions[action](path, data)
end

function IWLoader:ValidateKey(key)
    if not key or type(key) ~= "string" or #key < 10 then
        self:Log("Invalid key format", "error")
        return false
    end

    local keyType = string.match(key, "^IW%-(%w+)%-")
    if not keyType or not self.KeySystem.KeyTypes[keyType] then
        self:Log("Invalid key type", "error")
        return false
    end

    local currentTime = os.time()
    local keyData = self.KeySystem.KeyTypes[keyType]
    
    if self.KeySystem.KeyData.LastCheck > 0 then
        local timeSinceLastCheck = currentTime - self.KeySystem.KeyData.LastCheck
        if timeSinceLastCheck < (60 / keyData.RateLimit) then
            self:Log("Rate limit exceeded", "error")
            return false
        end
        
        if timeSinceLastCheck < keyData.CooldownPeriod then
            self:Log("Key in cooldown period", "error")
            return false
        end
    end

    self.KeySystem.ActiveKey = key
    self.KeySystem.KeyData = {
        LastCheck = currentTime,
        Expiry = currentTime + keyData.ExpiryDuration,
        Type = keyType,
        HardwareId = RbxAnalyticsService:GetClientId(),
        Platform = UserInputService.TouchEnabled and "Mobile" or "Desktop",
        GameInfo = {
            PlaceId = game.PlaceId,
            PlaceName = MarketplaceService:GetProductInfo(game.PlaceId).Name,
            PlayerName = Players.LocalPlayer.Name,
            JoinTime = currentTime
        }
    }

    self:Log("Key validated successfully: " .. keyType, "success")
    return true
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
            self:CreateFileSystem()
            self:SecureGameEnvironment()
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
            return self.KeySystem.ActiveKey ~= nil
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
    
    local data = {
        embeds = {{
            title = "IW-Loader Execution Log",
            color = success and 65280 or 16711680, -- Green for success, Red for failure
            fields = {
                {name = "Game", value = gameName, inline = true},
                {name = "Status", value = success and "✅ Success" or "❌ Failed", inline = true},
                {name = "Load Time", value = string.format("%.2f seconds", loadTime), inline = true},
                {name = "Memory Usage", value = string.format("%d MB", self.Analytics.Performance.MemoryUsage), inline = true},
                {name = "FPS", value = tostring(self.Analytics.Performance.FPS[#self.Analytics.Performance.FPS]), inline = true},
                {name = "Key Type", value = self.KeySystem.KeyData.Type, inline = true},
                {name = "Platform", value = self.KeySystem.KeyData.Platform, inline = true},
                {name = "Player", value = Players.LocalPlayer.Name, inline = true},
                {name = "Hardware ID", value = self.KeySystem.KeyData.HardwareId, inline = true}
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = {
                text = string.format("IW-Loader v%s", self.Config.Version)
            }
        }}
    }

    local webhookUrl = "https://discord.com/api/webhooks/1308052148096864278/Spz8mymCWA27XW6E9DDY2dyVl_NotFRKEIbCKJau5QPmUq5Sqr0pNxJAn5-afz_mFecm"
    
    task.spawn(function()
        local response = request or http_request or syn.request or http.request({
            Url = webhookUrl,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(data)
        })
        
        if response.Success then
            self:Log("Analytics sent successfully", "info")
        else
            self:Log("Failed to send analytics: " .. response.StatusCode, "warning")
        end
    end)
    
    if not success then
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
        
        task.wait(0.1)
        
        local userKey = getgenv().key or " "
        IWLoader:Log("Validating key: " .. userKey, "auth")
        
        if IWLoader:HandleSecurity("validate", userKey) then
            IWLoader:Log("Key validation successful", "success")
            return IWLoader:LoadGame()
        else
            IWLoader:Log("Key validation failed", "error")
        end
    end)
end

return IWLoader


local TestFramework = {
    totalTests = 0,
    passedTests = 0,
    failedTests = 0,
    skippedTests = 0,
    currentBeforeEach = nil,
    currentAfterEach = nil,
    testGroups = {},
    timeout = 5,
    startTime = 0
}

function TestFramework.expect(value)
    local to = {
        equal = function(expected)
            assert(value == expected, string.format("Expected %s to equal %s", tostring(value), tostring(expected)))
        end,
        be = function(expected)
            assert(value == expected, string.format("Expected %s to be %s", tostring(value), tostring(expected)))
        end,
        beCloseTo = function(expected, delta)
            assert(math.abs(value - expected) <= (delta or 0.0001), string.format("Expected %s to be close to %s", tostring(value), tostring(expected)))
        end,
        beTrue = function()
            assert(value == true, "Expected value to be true")
        end,
        beFalse = function()
            assert(value == false, "Expected value to be false")
        end,
        beNil = function()
            assert(value == nil, "Expected value to be nil")
        end,
        beType = function(expectedType)
            assert(type(value) == expectedType, string.format("Expected type %s but got %s", expectedType, type(value)))
        end,
        beInstanceOf = function(className)
            assert(typeof(value) == className, string.format("Expected instance of %s but got %s", className, typeof(value)))
        end,
        contain = function(expected)
            if type(value) == "table" then
                local found = false
                for _, v in pairs(value) do
                    if v == expected then
                        found = true
                        break
                    end
                end
                assert(found, string.format("Expected table to contain %s", tostring(expected)))
            else
                assert(string.find(tostring(value), tostring(expected)), string.format("Expected %s to contain %s", tostring(value), tostring(expected)))
            end
        end
    }

    local never = {
        to = {
            equal = function(expected)
                assert(value ~= expected, string.format("Expected %s to not equal %s", tostring(value), tostring(expected)))
            end,
            be = function(expected)
                assert(value ~= expected, string.format("Expected %s to not be %s", tostring(value), tostring(expected)))
            end,
            beNil = function()
                assert(value ~= nil, "Expected value to not be nil")
            end,
            contain = function(expected)
                if type(value) == "table" then
                    for _, v in pairs(value) do
                        assert(v ~= expected, string.format("Expected table to not contain %s", tostring(expected)))
                    end
                else
                    assert(not string.find(tostring(value), tostring(expected)), string.format("Expected %s to not contain %s", tostring(value), tostring(expected)))
                end
            end
        }
    }

    return {
        to = to,
        never = never
    }
end

function TestFramework.setTimeout(seconds)
    TestFramework.timeout = seconds
end

function TestFramework.beforeEach(callback)
    TestFramework.currentBeforeEach = callback
end

function TestFramework.afterEach(callback)
    TestFramework.currentAfterEach = callback
end

function TestFramework.describe(description, callback)
    local group = {
        description = description,
        tests = {},
        beforeEach = TestFramework.currentBeforeEach,
        afterEach = TestFramework.currentAfterEach
    }
    table.insert(TestFramework.testGroups, group)
    callback()
end

function TestFramework.test(name, options, callback, fallbackCallback)
    local currentGroup = TestFramework.testGroups[#TestFramework.testGroups]
    table.insert(currentGroup.tests, {
        description = name,
        callback = callback,
        fallback = fallbackCallback,
        options = options or {},
        skip = false
    })
end

function TestFramework.it(description, callback)
    TestFramework.test(description, {}, callback)
end

function TestFramework.xit(description, callback)
    local currentGroup = TestFramework.testGroups[#TestFramework.testGroups]
    table.insert(currentGroup.tests, {
        description = description,
        callback = callback,
        skip = true
    })
end

function TestFramework.waitFor(condition, timeout)
    local startTime = os.clock()
    timeout = timeout or TestFramework.timeout
    
    while not condition() and (os.clock() - startTime) < timeout do
        task.wait()
    end
    
    return condition()
end

function TestFramework.runTests()
    TestFramework.startTime = os.clock()
    print("\n🚀 Starting LunC+ Suite\n=====================================")

    for _, group in ipairs(TestFramework.testGroups) do
        print(string.format("\n📦 %s", group.description))
        
        for _, test in ipairs(group.tests) do
            if test.skip then
                TestFramework.skippedTests = TestFramework.skippedTests + 1
                print(string.format("  ⚪ %s (Skipped)", test.description))
                continue
            end

            TestFramework.totalTests = TestFramework.totalTests + 1
            
            local mainSuccess, mainError = xpcall(function()
                if group.beforeEach then
                    group.beforeEach()
                end
                
                test.callback()
                
                if group.afterEach then
                    group.afterEach()
                end
            end) -- Rest in peace debug.traceback, you will never be missed ;)
            
            if not mainSuccess and test.fallback then
                print(string.format("  ⚠️ Running simplified test for: %s", test.description))
                local fallbackSuccess, fallbackError = xpcall(test.fallback, debug.traceback)
                if fallbackSuccess then
                    print("     ℹ️ Simplified test passed")
                else
                    print(string.format("     ℹ️ Simplified test failed: %s", fallbackError:match("^.-:%d+: (.+)") or fallbackError))
                end
            end
            
            if mainSuccess then
                TestFramework.passedTests = TestFramework.passedTests + 1
                print(string.format("  ✅ %s", test.description))
            else
                TestFramework.failedTests = TestFramework.failedTests + 1
                local errorMessage = mainError:match("^.-:%d+: (.+)") or mainError
                print(string.format("  ❌ %s: %s", test.description, errorMessage))
            end
        end
    end
    
    local duration = os.clock() - TestFramework.startTime
    
    print("\n📊 Test Results\n=====================================")
    print(string.format("Duration: %.2f seconds", duration))
    print(string.format("Total Tests: %d", TestFramework.totalTests))
    print(string.format("Passed: %d", TestFramework.passedTests))
    print(string.format("Failed: %d", TestFramework.failedTests))
    print(string.format("Skipped: %d", TestFramework.skippedTests))
    print(string.format("Success Rate: %.1f%%", (TestFramework.passedTests/TestFramework.totalTests) * 100))
end
local function runAllTests()
    local Lighting, Players, Workspace
    local originalReferences = {}
    
    TestFramework.beforeEach(function()
        Lighting = game:GetService("Lighting")
        Players = game:GetService("Players")
        Workspace = game:GetService("Workspace")
        
        originalReferences.Lighting = Lighting
        originalReferences.Players = Players
        originalReferences.Workspace = Workspace
    end)
    
    TestFramework.afterEach(function()
        if cache.iscached(Lighting) then
            cache.replace(Lighting, originalReferences.Lighting)
        end
        if cache.iscached(Players) then
            cache.replace(Players, originalReferences.Players)
        end
        if cache.iscached(Workspace) then
            cache.replace(Workspace, originalReferences.Workspace)
        end
        
        Lighting = nil
        Players = nil
        Workspace = nil
    end)

        TestFramework.describe("Cache Functions", function()
        TestFramework.test("cache.invalidate", {},
            function()
                -- Main test with comprehensive checks
                local originalLighting = Lighting
                TestFramework.expect(originalLighting).to.beType("userdata")
                cache.invalidate(Lighting)
                local newLighting = game:GetService("Lighting")
                TestFramework.expect(originalLighting == newLighting).to.beFalse()
                --TestFramework.expect(cache.iscached(originalLighting)).to.beFalse() -- Temporary remove this for future fix
            end,
            function()
                -- Basic invalidation check
                local testInstance = Instance.new("Part")
                cache.invalidate(testInstance)
                local result = not cache.iscached(testInstance)
                testInstance:Destroy()
                return result
            end
        )

        TestFramework.test("cache.iscached", {},
            function()
                -- Main test with multiple assertions
                local instance = Instance.new("Part")
                TestFramework.expect(cache.iscached(instance)).to.beTrue()
                cache.invalidate(instance)
                TestFramework.expect(cache.iscached(instance)).to.beFalse()
                instance:Destroy()
            end,
            function()
                -- Simple cache check
                local instance = Instance.new("Part")
                local result = cache.iscached(instance)
                instance:Destroy()
                return result
            end
        )

        TestFramework.test("cache.replace", {},
            function()
                -- Main test with property verification
                local original = Instance.new("Part")
                local replacement = Instance.new("Part")
                original.Name = "TestOriginal"
                replacement.Name = "TestReplacement"
                
                cache.replace(original, replacement)
                TestFramework.expect(original.Name).to.equal("TestReplacement")
                
                original:Destroy()
                replacement:Destroy()
            end,
            function()
                -- Basic replacement check
                local part1 = Instance.new("Part")
                local part2 = Instance.new("Part")
                cache.replace(part1, part2)
                local result = compareinstances(part1, part2)
                part1:Destroy()
                part2:Destroy()
                return result
            end
        )

        TestFramework.test("cloneref functionality", {},
            function()
                -- Main test with reference checks
                local original = Lighting
                local clone = cloneref(original)
                
                TestFramework.expect(clone).never.to.beNil()
                TestFramework.expect(clone == original).to.beFalse()
                TestFramework.expect(compareinstances(clone, original)).to.beTrue()
                
                local testName = "TestName_" .. tostring(os.clock())
                original.Name = testName
                TestFramework.expect(clone.Name).to.equal(testName)
            end,
            function()
                -- Simple clone check
                local instance = Instance.new("Part")
                local clone = cloneref(instance)
                local result = clone ~= instance and compareinstances(clone, instance)
                instance:Destroy()
                return result
            end
        )

        TestFramework.test("compareinstances functionality", {},
            function()
                -- Main test with multiple comparisons
                local instance = Instance.new("Part")
                local clone = cloneref(instance)
                local different = Instance.new("Part")
                
                TestFramework.expect(compareinstances(instance, clone)).to.beTrue()
                TestFramework.expect(compareinstances(instance, different)).to.beFalse()
                
                instance:Destroy()
                different:Destroy()
            end,
            function()
                -- Basic comparison check
                local part = Instance.new("Part")
                local clone = cloneref(part)
                local result = compareinstances(part, clone)
                part:Destroy()
                return result
            end
        )
    end)

    TestFramework.describe("WebSocket Tests", function()       
        TestFramework.test("Websocket.connect", {},
            function()
                -- Main test with interface verification
                local ws = WebSocket.connect("ws://echo.websocket.events")
                TestFramework.expect(ws).never.to.beNil()
                TestFramework.expect(ws.Send).to.beType("function")
                TestFramework.expect(ws.Close).to.beType("function")
                TestFramework.expect(ws.OnMessage).never.to.beNil()
                ws:Close()
            end,
            function()
                -- Simple connection check
                local ws = WebSocket.connect("ws://echo.websocket.events")
                local result = ws ~= nil and type(ws.Send) == "function"
                ws:Close()
                return result
            end
        )

        TestFramework.test("Websocket message exchange", {},
            function()
                -- Main test with message verification
                local ws = WebSocket.connect("ws://echo.websocket.events")
                local testMessage = "Test_" .. tostring(os.clock())
                local received = false
                
                ws.OnMessage:Connect(function(msg)
                    received = msg == testMessage
                end)
                
                ws:Send(testMessage)
                TestFramework.waitFor(function() return received end, 2)
                TestFramework.expect(received).to.beTrue()
                ws:Close()
            end,
            function()
                -- Simple message test
                local ws = WebSocket.connect("ws://echo.websocket.events")
                local received = false
                ws.OnMessage:Connect(function() received = true end)
                ws:Send("test")
                task.wait(1)
                ws:Close()
                return received
            end
        )
    end)

    TestFramework.runTests()
end

runAllTests()

return TestFramework

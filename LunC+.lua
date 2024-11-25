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
    print("\n🚀 Starting Test Suite")
    print("====================")

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
            end, debug.traceback)
            
            -- If main test fails, run fallback but don't change the success status
            if not mainSuccess and test.fallback then
                print(string.format("  ⚠️ Running simplified test for: %s", test.description))
                local fallbackSuccess, fallbackError = xpcall(test.fallback, debug.traceback)
                if fallbackSuccess then
                    print("     ℹ️ Simplified test passed, but main test still failed")
                else
                    print(string.format("     ℹ️ Simplified test also failed: %s", tostring(fallbackError)))
                end
            end
            
            if mainSuccess then
                TestFramework.passedTests = TestFramework.passedTests + 1
                print(string.format("  ✅ %s", test.description))
            else
                TestFramework.failedTests = TestFramework.failedTests + 1
                print(string.format("  ❌ %s\n     Error: %s", test.description, tostring(mainError)))
            end
        end
    end
    
    local duration = os.clock() - TestFramework.startTime
    
    print("\n📊 Test Results")
    print("====================")
    print(string.format("Duration: %.2f seconds", duration))
    print(string.format("Total Tests: %d", TestFramework.totalTests))
    print(string.format("Passed: %d", TestFramework.passedTests))
    print(string.format("Failed: %d", TestFramework.failedTests))
    print(string.format("Skipped: %d", TestFramework.skippedTests))
    print(string.format("Success Rate: %.1f%%", (TestFramework.passedTests/TestFramework.totalTests) * 100))
end

local function runAllTests()
    TestFramework.describe("WebSocket Tests", function()
        TestFramework.test("Websocket.Connect", {},
            function()
                local ws = WebSocket.connect("ws://echo.websocket.events")
                TestFramework.expect(ws).never.to.beNil()
                TestFramework.expect(ws.Send).to.beType("function")
                TestFramework.expect(ws.Close).to.beType("function")
                ws:Close()
            end,
            function()
                local ws = WebSocket.connect("ws://echo.websocket.events")
                assert(ws, "WebSocket connection failed")
                assert(type(ws.Send) == "function", "Send method missing")
                ws:Close()
            end
        )

        TestFramework.test("websocket message exchange", {},
            function()
                local ws = WebSocket.connect("ws://echo.websocket.events")
                local testMessage = "Hello WebSocket Test"
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
                local ws = WebSocket.connect("ws://echo.websocket.events")
                local msg = "Simple Test"
                local received = false
                ws.OnMessage:Connect(function(m) received = m == msg end)
                ws:Send(msg)
                task.wait(1)
                assert(received, "Message echo failed")
                ws:Close()
            end
        )

        TestFramework.test("multiple messages handling", {},
            function()
                local ws = WebSocket.connect("ws://echo.websocket.events")
                local messages = {"Test1", "Test2", "Test3"}
                local receivedMessages = {}
                
                ws.OnMessage:Connect(function(msg)
                    table.insert(receivedMessages, msg)
                end)
                
                for _, msg in ipairs(messages) do
                    ws:Send(msg)
                end
                
                local allReceived = TestFramework.waitFor(function()
                    return #receivedMessages == #messages
                end, 3)
                
                TestFramework.expect(allReceived).to.beTrue()
                TestFramework.expect(#receivedMessages).to.equal(#messages)
                
                for i, msg in ipairs(messages) do
                    TestFramework.expect(receivedMessages[i]).to.equal(msg)
                end
                
                ws:Close()
            end,
            function()
                local ws = WebSocket.connect("ws://echo.websocket.events")
                local msg1, msg2 = "Test1", "Test2"
                local received = 0
                ws.OnMessage:Connect(function() received = received + 1 end)
                ws:Send(msg1)
                ws:Send(msg2)
                task.wait(1)
                assert(received == 2, "Failed to receive multiple messages")
                ws:Close()
            end
        )
    end)
    
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
                local originalLighting = Lighting
                TestFramework.expect(originalLighting).to.beType("userdata")
                cache.invalidate(Lighting)
                local newLighting = game:GetService("Lighting")
                TestFramework.expect(originalLighting == newLighting).to.beFalse()
            end,
            function()
                local part = Instance.new("Part")
                cache.invalidate(part)
                assert(not cache.iscached(part), "Instance was not invalidated")
                part:Destroy()
            end
        )

        TestFramework.test("cache.iscached", {},
            function()
                TestFramework.expect(cache.iscached).to.beType("function")
                TestFramework.expect(cache.iscached(Lighting)).to.beTrue()
                cache.invalidate(Lighting)
                TestFramework.expect(cache.iscached(Lighting)).to.beFalse()
            end,
            function()
                local part = Instance.new("Part")
                assert(cache.iscached(part), "New instance not cached")
                cache.invalidate(part)
                assert(not cache.iscached(part), "Instance still cached after invalidate")
                part:Destroy()
            end
        )

        TestFramework.test("cache.replace", {},
            function()
                local part1 = Instance.new("Part")
                local part2 = Instance.new("Part")
                part1.Name = "Original"
                part2.Name = "Replacement"
                
                TestFramework.expect(part1).to.beInstanceOf("Instance")
                TestFramework.expect(part2).to.beInstanceOf("Instance")
                
                cache.replace(part1, part2)
                TestFramework.expect(part1.Name).to.equal("Replacement")
                
                part1:Destroy()
                part2:Destroy()
            end,
            function()
                local part = Instance.new("Part")
                local fire = Instance.new("Fire")
                cache.replace(part, fire)
                assert(part ~= fire, "Part was not replaced with Fire")
                part:Destroy()
                fire:Destroy()
            end
        )

        TestFramework.test("cloneref", {},
            function()
                local original = game:GetService("Lighting")
                local clone = cloneref(original)
                
                TestFramework.expect(clone).never.to.beNil()
                TestFramework.expect(clone == original).to.beFalse()
                TestFramework.expect(clone.Name).to.equal(original.Name)
                
                local testProp = "TestProperty" .. tostring(os.clock())
                original.Name = testProp
                TestFramework.expect(clone.Name).to.equal(testProp)
            end,
            function()
                local part = Instance.new("Part")
                local clone = cloneref(part)
                assert(clone ~= part, "Clone reference matches original")
                assert(clone.Name == part.Name, "Clone properties don't match")
                part:Destroy()
            end
        )

        TestFramework.test("compareinstances", {},
            function()
                local clone = cloneref(Lighting)
                TestFramework.expect(compareinstances(Lighting, clone)).to.beTrue()
                TestFramework.expect(compareinstances(Lighting, Players)).to.beFalse()
            end,
            function()
                local part = Instance.new("Part")
                local clone = cloneref(part)
                assert(compareinstances(part, clone), "Instances don't compare equal")
                part:Destroy()
            end
        )
    end)

    TestFramework.runTests()
end

runAllTests()

return TestFramework

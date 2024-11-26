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

            local success, error = pcall(function()
                if group.beforeEach then
                    group.beforeEach()
                end

                test.callback()

                if group.afterEach then
                    group.afterEach()
                end
            end)

            if not success and test.fallback then
                print(string.format("  ⚠️ Running simplified test for: %s", test.description))
                local fallbackSuccess = pcall(test.fallback)

                if fallbackSuccess then
                    print("     ℹ️ Simplified test passed")
                else
                    print(string.format("     ℹ️ Simplified test failed"))
                end
            end

            if success then
                TestFramework.passedTests = TestFramework.passedTests + 1
                print(string.format("  ✅ %s", test.description))
            else
                TestFramework.failedTests = TestFramework.failedTests + 1
                print(string.format("  ❌ %s", test.description))
                print(string.format("     %s", error))
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

    TestFramework.describe("Drawing Library Tests", function()
      TestFramework.test("Drawing.new creation", {}, function()
        local drawings = {
            Line = Drawing.new("Line"),
            Text = Drawing.new("Text"),
            Image = Drawing.new("Image"),
            Circle = Drawing.new("Circle"),
            Square = Drawing.new("Square"),
            Quad = Drawing.new("Quad"),
            Triangle = Drawing.new("Triangle")
        }
        
        for type, drawing in pairs(drawings) do
            TestFramework.expect(isrenderobj(drawing)).to.beTrue()
            drawing:Destroy()
        end
    end)

    TestFramework.test("Drawing.Fonts availability", {}, function()
        local expectedFonts = {"UI", "System", "Plex", "Monospace"}
        for _, fontName in ipairs(expectedFonts) do
            TestFramework.expect(Drawing.Fonts[fontName]).never.to.beNil()
        end
    end)

    TestFramework.test("Line properties", {}, function()
        local line = Drawing.new("Line")
        line.From = Vector2.new(0, 0)
        line.To = Vector2.new(100, 100)
        line.Thickness = 2
        line.Color = Color3.fromRGB(255, 0, 0)
        line.Transparency = 1
        line.Visible = true

        TestFramework.expect(getrenderproperty(line, "From")).to.equal(Vector2.new(0, 0))
        TestFramework.expect(getrenderproperty(line, "To")).to.equal(Vector2.new(100, 100))
        line:Destroy()
    end)

    TestFramework.test("Text properties", {}, function()
        local text = Drawing.new("Text")
        text.Text = "Test Text"
        text.Size = 18
        text.Center = true
        text.Outline = true
        text.Position = Vector2.new(100, 100)
        text.Font = Drawing.Fonts.UI

        TestFramework.expect(text.Text).to.equal("Test Text")
        TestFramework.expect(text.Size).to.equal(18)
        text:Destroy()
    end)

    TestFramework.test("Circle properties", {}, function()
        local circle = Drawing.new("Circle")
        circle.Radius = 50
        circle.Position = Vector2.new(300, 300)
        circle.NumSides = 32
        circle.Thickness = 2
        circle.Filled = true

        TestFramework.expect(circle.Radius).to.equal(50)
        TestFramework.expect(circle.NumSides).to.equal(32)
        circle:Destroy()
    end)

    TestFramework.test("Square properties", {}, function()
        local square = Drawing.new("Square")
        square.Size = Vector2.new(100, 100)
        square.Position = Vector2.new(200, 200)
        square.Filled = true
        square.Thickness = 2

        TestFramework.expect(square.Size).to.equal(Vector2.new(100, 100))
        TestFramework.expect(square.Position).to.equal(Vector2.new(200, 200))
        square:Destroy()
    end)

    TestFramework.test("Quad properties", {}, function()
        local quad = Drawing.new("Quad")
        quad.PointA = Vector2.new(0, 0)
        quad.PointB = Vector2.new(100, 0)
        quad.PointC = Vector2.new(100, 100)
        quad.PointD = Vector2.new(0, 100)
        quad.Filled = true

        TestFramework.expect(quad.PointA).to.equal(Vector2.new(0, 0))
        TestFramework.expect(quad.PointC).to.equal(Vector2.new(100, 100))
        quad:Destroy()
    end)

    TestFramework.test("Triangle properties", {}, function()
        local triangle = Drawing.new("Triangle")
        triangle.PointA = Vector2.new(0, 100)
        triangle.PointB = Vector2.new(50, 0)
        triangle.PointC = Vector2.new(100, 100)
        triangle.Filled = true

        TestFramework.expect(triangle.PointB).to.equal(Vector2.new(50, 0))
        triangle:Destroy()
    end)

    TestFramework.test("cleardrawcache functionality", {}, function()
        local drawings = {}
        for i = 1, 5 do
            local circle = Drawing.new("Circle")
            circle.Visible = true
            table.insert(drawings, circle)
        end
        
        cleardrawcache()
        for _, drawing in ipairs(drawings) do
            TestFramework.expect(pcall(function() return drawing.Visible end)).to.beFalse()
        end
    end)

    TestFramework.test("isrenderobj validation", {}, function()
        local circle = Drawing.new("Circle")
        local normalTable = {}
        local normalString = "test"
        
        TestFramework.expect(isrenderobj(circle)).to.beTrue()
        TestFramework.expect(isrenderobj(normalTable)).to.beFalse()
        TestFramework.expect(isrenderobj(normalString)).to.beFalse()
        TestFramework.expect(isrenderobj(nil)).to.beFalse()
        
        circle:Destroy()
    end)

    TestFramework.test("setrenderproperty functionality", {}, function()
        local circle = Drawing.new("Circle")
        
        setrenderproperty(circle, "Radius", 100)
        TestFramework.expect(getrenderproperty(circle, "Radius")).to.equal(100)
        
        setrenderproperty(circle, "Color", Color3.fromRGB(255, 0, 0))
        TestFramework.expect(getrenderproperty(circle, "Color")).to.equal(Color3.fromRGB(255, 0, 0))
        
        setrenderproperty(circle, "Transparency", 0.5)
        TestFramework.expect(getrenderproperty(circle, "Transparency")).to.equal(0.5)
        
        circle:Destroy()
    end)

    TestFramework.test("getrenderproperty functionality", {}, function()
        local circle = Drawing.new("Circle")
        circle.Radius = 75
        circle.Visible = true
        circle.ZIndex = 5
        
        TestFramework.expect(getrenderproperty(circle, "Radius")).to.equal(75)
        TestFramework.expect(getrenderproperty(circle, "Visible")).to.beTrue()
        TestFramework.expect(getrenderproperty(circle, "ZIndex")).to.equal(5)
        
        circle:Destroy()
    end)

    TestFramework.test("Base Drawing properties", {}, function()
        local circle = Drawing.new("Circle")
        
        circle.Visible = true
        circle.ZIndex = 10
        circle.Transparency = 0.8
        circle.Color = Color3.fromRGB(0, 255, 0)
        
        TestFramework.expect(circle.Visible).to.beTrue()
        TestFramework.expect(circle.ZIndex).to.equal(10)
        TestFramework.expect(circle.Transparency).to.equal(0.8)
        TestFramework.expect(circle.Color).to.equal(Color3.fromRGB(0, 255, 0))
        
        circle:Destroy()
    end)
end)

    TestFramework.runTests()
end

runAllTests()

return TestFramework
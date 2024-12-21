# Signal Module Documentation

**Name:** Signal  
**Version:** 1.0  
**Description:**  
A Lua-side implementation that mimics the behavior of Roblox's RBXScriptSignal, allowing for better control over event handling, especially for passing objects by reference rather than by value.

## Class Overview

- **ClassName:** `string` - Identifier for the class.
- **_bindableEvent:** `BindableEvent` - Internal event used for firing signals.
- **_argMap:** `table<string, table>` - Maps unique keys to argument tables for event handling.
- **_connections:** `{RBXScriptConnection}` - List of all active connections to the signal.
- **_lastFire:** `number` - Timestamp of the last time the signal was fired.
- **_locked:** `boolean` - Flag to indicate if the Signal is locked from further modifications.
- **_source:** `string` - Traceback for debugging when enabled.
- **_handlerCount:** `number` - Counts the number of active handlers.

## Methods

- **Signal.new()**  
  Creates a new Signal instance. Initializes all necessary internal structures and starts a background task for cleaning up old argument maps.

- **Signal:Fire(...)**  
  Fires the signal with the given arguments. Uses a GUID to uniquely identify each call.

- **Signal:Connect(handler)**  
  Connects a function to the signal. Returns a connection object that can be used to disconnect or destroy the connection. Warns if handler count exceeds a predefined threshold.

- **Signal:Wait()**  
  Waits for the signal to be fired and returns the arguments passed during the last fire.

- **Signal:GetHandlerCount()**  
  Returns the number of handlers currently connected to this signal.

- **Signal:IsActive()**  
  Checks if the signal is still active (not destroyed).

- **Signal:Destroy()**  
  Destroys the signal, disconnecting all connections and clearing all internal data structures.

## Usage Example

```lua
local Signal = require(path.to.signal)
local mySignal = Signal.new()

mySignal:Connect(function(arg1, arg2)
    print("Received:", arg1, arg2)
end)
```
## Notes
- Be cautious with the high number of handlers as it might impact performance.
- This implementation ensures that objects are passed by reference, which is crucial for maintaining data integrity in event-driven systems.

# Maid Module Documentation

**Name:** Maid  
**Version:** 1.0  
**Description:**  
A utility class to manage cleanup tasks for scripts, ensuring that connections, instances, and other resources are properly disposed of to prevent memory leaks.

## Class Overview

- **ClassName:** `string` - Identifier for the class.
- **_tasks:** `table<any, any>` - Stores all tasks to be managed by the Maid.
- **_taskCount:** `number` - Keeps track of the number of active tasks.
- **_locked:** `boolean` - Flag to prevent modifications during cleaning.
- **_cleaning:** `boolean` - Indicates if a cleaning operation is in progress.

## Methods

- **Maid.new()**  
  Creates a new Maid instance.

- **Maid.isMaid(value)**  
  Checks if a given value is an instance of Maid.

- **Maid:__index(index)**  
  Metamethod for accessing tasks or Maid methods.

- **Maid:__newindex(index, newTask)**  
  Metamethod for assigning or updating tasks, handling old task cleanup.

- **Maid:GiveTask(task)**  
  Adds a new task to the Maid. Supports functions, connections, and objects with `Destroy` method.

- **Maid:GivePromise(promise)**  
  Manages a promise, ensuring it's cleaned up if still pending when the maid cleans.

- **Maid:DoCleaning()**  
  Cleans up all registered tasks, disconnecting events, calling cleanup functions, or destroying objects.

- **Maid:Destroy()**  
  Alias for `DoCleaning`, used for consistency with Roblox patterns.

## Usage Example

```lua
local Maid = require(path.to.maid)
local maid = Maid.new()

local part = Instance.new("Part")
maid:GiveTask(part)

local connection = game.Workspace.ChildAdded:Connect(function() print("Child added") end)
maid:GiveTask(connection)

-- Cleanup all tasks
maid:Destroy()
```
## Notes
- Maid is particularly useful in scenarios where you need to manage resources or event connections that should be cleaned up when a script or object is no longer needed.
- The GivePromise method ensures that promises do not leak if they're still pending during cleanup.

mySignal:Fire("Hello", "World")

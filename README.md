# Idek Repository

This repository contains various scripts and utilities including:

## Files

- **C++ Files**: `littleone.cpp`, `oldcpp.cpp` - Windows application code using DirectX and ImGui
- **Lua/Luau Files**: `LunC+.lua`, `Promise.lua` - Test framework and Promise implementation (Roblox Luau syntax)
- **Markdown Files**: Various documentation files
- **SubModules**: Additional utility modules

## CI/CD

This repository includes GitHub Actions workflows for:

- C++ syntax validation (with dependency handling)
- Lua/Luau syntax checking  
- Basic file structure validation

## Building

The C++ files require external dependencies:
- ImGui
- DirectX 11
- curl
- nlohmann/json
- Various Windows-specific libraries

The Lua files use Luau (Roblox Lua) syntax and are not standard Lua.
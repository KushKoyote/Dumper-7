# FNamePool GNames Finder - Implementation Guide

## Overview

This document provides a comprehensive guide to the Lua implementation of the FNamePool GNames finder, which replicates the functionality found in the Dumper-7 C++ codebase.

## C++ Source Analysis

The original functionality is implemented in the following C++ files:

### Core Implementation Files
- `Dumper/Engine/Private/Unreal/NameArray.cpp` - Main implementation
- `Dumper/Engine/Public/Unreal/NameArray.h` - Interface definitions
- `Dumper/Engine/Private/Unreal/UnrealTypes.cpp` - FName initialization

### Key C++ Methods

#### `NameArray::TryFindNamePool()` (lines 399-476)
- Searches for FNamePool constructor pattern: `48 8D 0D ? ? ? ? E8`
- Looks for InitializeSRWLock calls within constructors
- Validates findings using ByteProperty string references
- Extracts FNamePool instance address from LEA instruction

#### `NameArray::TryFindNameArray()` (lines 349-397)
- Fallback method for TNameEntryArray detection
- Searches for ByteProperty string references
- Finds FName::GetNames calls
- Analyzes GetNames function for GNames references

#### `FName::Init()` (lines 67-136)
- Initializes the name system
- Attempts to find FName::AppendString first
- Falls back to GNames-based approach if needed

## Lua Implementation

### Script Files

1. **`fnamepool_gnames_finder.lua`** - Basic implementation
2. **`advanced_gnames_finder.lua`** - Enhanced version with validation
3. **`simple_example.lua`** - Minimal example
4. **`usage_example.lua`** - Practical usage demonstration
5. **`test_suite.lua`** - Test suite with mocks

### Key Implementation Details

#### Pattern Matching
```lua
-- FNamePool constructor pattern
local pattern = "48 8D 0D ? ? ? ? E8"
local result = proc.find_signature(base_address, module_size, pattern)
```

#### Address Resolution
```lua
-- Resolve LEA instruction target
local function resolve_32bit_relative_move(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 3)
    return instruction_address + 7 + relative_offset
end
```

#### Validation
```lua
-- Validate FNamePool structure
local function validate_name_pool(address)
    local max_chunks = read_uint32(address)
    local byte_cursor = read_uint32(address + 4)
    -- Additional validation logic...
end
```

## API Mapping

### C++ to Lua API Translation

| C++ Function | Lua API | Description |
|-------------|---------|-------------|
| `FindPattern()` | `proc.find_signature()` | Pattern search in memory |
| `GetModuleBase()` | `proc.get_base_module()` | Get module base and size |
| `*reinterpret_cast<int32*>()` | `proc.read_int32()` | Read 32-bit integer |
| `*reinterpret_cast<int64*>()` | `proc.read_int64()` | Read 64-bit integer |
| `IsInProcessRange()` | Custom validation | Check address validity |
| `IsBadReadPtr()` | Error handling | Check if address is readable |

### Memory Operations

#### C++ Implementation
```cpp
uint8* GNamesAddress = *reinterpret_cast<uint8**>(ImageBase + Off::InSDK::NameArray::GNames);
```

#### Lua Implementation
```lua
local gnames_address = proc.read_int64(base_address + offset)
```

## Pattern Analysis

### FNamePool Constructor Pattern
```asm
48 8D 0D ? ? ? ? E8    ; lea rcx, [FNamePool_instance]
                       ; call FNamePool_constructor
```

### TNameEntryArray Access Patterns
```asm
48 8B 05 ? ? ? ? 48 8B ; mov rax, [GNames]
48 8B 15 ? ? ? ? 48 8B ; mov rdx, [GNames]
48 8B 0D ? ? ? ? 48 8B ; mov rcx, [GNames]
```

## Validation Logic

### FNamePool Structure Validation
```lua
local function validate_name_pool(address)
    -- Check max chunks (reasonable value)
    local max_chunks = read_uint32(address)
    if max_chunks <= 0 or max_chunks > 0x10000 then
        return false
    end
    
    -- Check byte cursor
    local byte_cursor = read_uint32(address + 4)
    if byte_cursor <= 0 or byte_cursor > 0x100000 then
        return false
    end
    
    -- Validate chunk pointers
    local chunks_start = address + 0x10
    local valid_chunks = 0
    for i = 0, math.min(max_chunks, 10) do
        local chunk_ptr = read_pointer(chunks_start + i * 8)
        if is_valid_address(chunk_ptr) then
            valid_chunks = valid_chunks + 1
        end
    end
    
    return valid_chunks > 0
end
```

### TNameEntryArray Structure Validation
```lua
local function validate_name_array(address)
    local array_ptr = read_pointer(address)
    if not is_valid_address(array_ptr) then
        return false
    end
    
    -- Check array structure
    local num_elements = read_uint32(array_ptr + 0x8)
    local max_elements = read_uint32(array_ptr + 0xC)
    
    return num_elements > 0 and 
           num_elements <= 0x1000000 and 
           max_elements > num_elements and 
           max_elements <= 0x2000000
end
```

## Error Handling

### C++ Error Handling
```cpp
if (!IsInProcessRange(Address) || IsBadReadPtr(*reinterpret_cast<void**>(Address)))
    return false;
```

### Lua Error Handling
```lua
local function is_valid_address(address)
    return address and address ~= 0 and address > 0x10000
end

local function is_in_process_range(address)
    return address >= g_base_address and address < (g_base_address + g_base_module_size)
end
```

## Usage Examples

### Basic Usage
```lua
-- Attach to process
if not proc.attach_by_name("UE4Game.exe") then
    return
end

-- Get module info
local base_address, module_size = proc.get_base_module()

-- Search for GNames
local offset, gnames_type = find_gnames()
if offset then
    print("Found " .. gnames_type .. " at offset 0x" .. string.format("%X", offset))
end
```

### Advanced Usage with Validation
```lua
-- Search and validate
local offset, gnames_type = find_gnames()
if offset then
    local full_address = base_address + offset
    local is_valid = false
    
    if gnames_type == "FNamePool" then
        is_valid = validate_name_pool(full_address)
    else
        is_valid = validate_name_array(full_address)
    end
    
    if is_valid then
        print("Successfully found and validated " .. gnames_type)
    else
        print("Found " .. gnames_type .. " but validation failed")
    end
end
```

## Debugging and Troubleshooting

### Common Issues

1. **Pattern Not Found**
   - Check if the process is an Unreal Engine game
   - Verify the process is not protected by anti-cheat
   - Try different pattern variations

2. **Invalid Address**
   - Ensure proper address calculation
   - Check for address space layout randomization (ASLR)
   - Verify base address is correct

3. **Validation Failures**
   - Check for memory encryption
   - Verify structure offsets for different UE versions
   - Ensure proper pointer dereferencing

### Debug Logging
```lua
local function debug_log(level, message)
    local colors = {
        DEBUG = {128, 128, 128, 255},
        INFO = {255, 255, 255, 255},
        WARNING = {255, 255, 0, 255},
        ERROR = {255, 0, 0, 255}
    }
    
    local color = colors[level] or colors.INFO
    engine.log("[" .. level .. "] " .. message, color[1], color[2], color[3], color[4])
end
```

## Performance Considerations

### Memory Access Optimization
- Use chunked reading for large memory regions
- Cache frequently accessed values
- Minimize redundant memory operations

### Pattern Search Optimization
- Use specific patterns to reduce false positives
- Limit search ranges when possible
- Implement early termination conditions

## Future Enhancements

### Potential Improvements
1. **Encryption Support** - Add support for encrypted processes
2. **Version Detection** - Automatically detect UE version
3. **GUI Interface** - Create user-friendly interface
4. **Batch Processing** - Process multiple targets simultaneously
5. **Configuration System** - Allow customizable patterns and offsets

### Extension Points
```lua
-- Configuration system
local CONFIG = {
    patterns = {
        fnamepool_constructor = "48 8D 0D ? ? ? ? E8",
        -- Add more patterns for different UE versions
    },
    offsets = {
        -- Version-specific offsets
    },
    validation = {
        -- Validation parameters
    }
}
```

## Conclusion

The Lua implementation successfully replicates the core functionality of the C++ FNamePool GNames finder while providing additional features like validation, interactive mode, and comprehensive error handling. The modular design allows for easy extension and customization for different use cases and Unreal Engine versions.

## References

- [Dumper-7 Original Repository](https://github.com/Encryqed/Dumper-7)
- [Unreal Engine Documentation](https://docs.unrealengine.com/)
- [Pattern Scanning Techniques](https://github.com/learn-more/findpattern-bench)
- [Assembly Instruction Reference](https://www.felixcloutier.com/x86/)
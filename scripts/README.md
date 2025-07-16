# FNamePool GNames Finder - Lua Implementation

This directory contains Lua scripts that implement the same functionality as the C++ code in Dumper-7 for finding `FNamePool GNames` and `TNameEntryArray GNames` in Unreal Engine processes.

## Files

- `fnamepool_gnames_finder.lua` - Basic implementation with core functionality
- `advanced_gnames_finder.lua` - Enhanced version with validation and interactive mode

## Overview

The scripts replicate the functionality from the C++ files:
- `Dumper/Engine/Private/Unreal/NameArray.cpp` - Main implementation
- `Dumper/Engine/Public/Unreal/NameArray.h` - Interface definitions

## Key Features

### Pattern-Based Search
- Searches for FNamePool constructor patterns (`48 8D 0D ? ? ? ? E8`)
- Looks for InitializeSRWLock calls within constructors
- Validates findings using ByteProperty string references

### Fallback Detection
- Falls back to TNameEntryArray if FNamePool not found
- Searches for FName::GetNames calls and GNames references
- Uses multiple pattern matching approaches

### Validation
- Validates found structures for correctness
- Checks for reasonable data values and pointer validity
- Performs structural integrity checks

## Usage

### Basic Usage
```lua
-- Modify the target process name in the script
local target_process = "YourGame.exe"

-- Run the script in your Lua environment
```

### Interactive Mode (Advanced Script)
The advanced script includes an interactive mode:
- Press `1` to search for GNames
- Press `2` to validate results
- Press `3` to show process information
- Press `ESC` to exit

## Configuration

Both scripts include configuration constants that can be modified:

```lua
local CONFIG = {
    INIT_SRW_LOCK_SEARCH_RANGE = 0x50,
    BYTE_PROPERTY_SEARCH_RANGE = 0x2A0,
    GET_NAMES_CALL_SEARCH_RANGE = 0x100,
    -- ... other settings
}
```

## API Functions Used

The scripts utilize the following API functions:

### Process Management
- `proc.attach_by_name(process_name)` - Attach to target process
- `proc.get_base_module()` - Get base address and size
- `proc.pid()` - Get process ID

### Memory Operations
- `proc.read_int32(address)` - Read 32-bit integer
- `proc.read_int64(address)` - Read 64-bit integer
- `proc.read_string(address, size)` - Read string
- `proc.find_signature(base, size, pattern)` - Pattern search

### Logging
- `engine.log(message, r, g, b, a)` - Colored console output

### Input (Advanced Script)
- `input.is_key_pressed(key)` - Key press detection

## Implementation Details

### FNamePool Detection
1. Searches for the FNamePool constructor pattern
2. Analyzes the constructor for InitializeSRWLock calls
3. Validates by finding ByteProperty string references
4. Extracts the FNamePool instance address

### TNameEntryArray Detection
1. Finds ByteProperty string references
2. Searches upward for GetNames calls
3. Analyzes GetNames function for GNames references
4. Validates found addresses

### Assembly Instruction Parsing
- `resolve_32bit_relative_call()` - Resolves relative call targets
- `resolve_32bit_relative_move()` - Resolves relative move targets
- `resolve_32bit_section_relative_call()` - Resolves section-relative calls

## Output

The scripts provide detailed logging:
- ✓ Success messages (green)
- ✗ Error messages (red)
- ℹ Information messages (cyan)
- ⚠ Warning messages (yellow)

Example output:
```
ℹ Starting comprehensive GNames search...
ℹ Searching for FNamePool constructor...
ℹ Found potential constructor at 0x140001234
✓ Found FNamePool constructor with ByteProperty reference!
✓ FNamePool validation passed (5 valid chunks)
✓ Successfully found and validated FNamePool GNames!
✓ GNames Type: FNamePool
✓ GNames Offset: 0x12345678
✓ GNames Address: 0x140012345678
```

## Limitations

- String search is simplified compared to the C++ implementation
- Import table checking is not fully implemented
- Some advanced validation checks are simplified
- Performance may be slower than the C++ version

## Compatibility

The scripts are designed to work with:
- Unreal Engine 4.x and 5.x games
- Both FNamePool and TNameEntryArray implementations
- Common Unreal Engine process names

## Troubleshooting

If the scripts fail to find GNames:
1. Ensure the target process is an Unreal Engine game
2. Check if the process has anti-cheat protection
3. Try different process names
4. Verify the process is not encrypted
5. Check the log output for specific error messages

## Extension

The scripts can be extended to:
- Add support for additional patterns
- Implement more sophisticated validation
- Add encryption/decryption support
- Include more Unreal Engine version-specific logic
- Add GUI interface for easier usage
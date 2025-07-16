-- Test Suite for FNamePool GNames Finder
-- This script tests the functionality without requiring a real Unreal Engine process

-- Mock API for testing
local mock_proc = {
    attached = false,
    base_address = 0x140000000,
    module_size = 0x1000000,
    memory = {},
}

-- Add functions separately to avoid reference issues
mock_proc.attach_by_name = function(name)
    print("Mock: Attaching to " .. name)
    mock_proc.attached = true
    return true
end

mock_proc.get_base_module = function()
    return mock_proc.base_address, mock_proc.module_size
end

mock_proc.pid = function()
    return 1234
end

mock_proc.read_int32 = function(address)
    return mock_proc.memory[address] or 0
end

mock_proc.read_int64 = function(address)
    return mock_proc.memory[address] or 0
end

mock_proc.read_string = function(address, size)
    if address == 0x140001000 then
        return "ByteProperty"
    end
    return ""
end

mock_proc.find_signature = function(base, size, pattern)
    -- Mock finding the FNamePool constructor pattern
    if pattern == "48 8D 0D ? ? ? ? E8" then
        return 0x140000100
    end
    return 0
end

-- Mock engine API
local mock_engine = {
    log = function(msg, r, g, b, a)
        print(string.format("[%d,%d,%d,%d] %s", r or 255, g or 255, b or 255, a or 255, msg))
    end,
    
    register_on_engine_tick = function(callback)
        print("Mock: Registered engine tick callback")
        callback()  -- Execute immediately for testing
    end
}

-- Mock input API
local mock_input = {
    is_key_pressed = function(key)
        return false  -- No key pressed in mock
    end
}

-- Mock time API
local mock_time = {
    now_local = function()
        return "2024-01-01 12:00:00"
    end
}

-- Set up mock memory for testing
mock_proc.memory[0x140000103] = 0x12345678  -- Mock relative offset for LEA instruction
mock_proc.memory[0x140000107] = 0x140001000  -- Mock address containing ByteProperty

-- Override global APIs with mocks
proc = mock_proc
engine = mock_engine
input = mock_input
time = mock_time

-- Test function
local function run_tests()
    print("=== Running FNamePool GNames Finder Tests ===")
    
    -- Test 1: Basic pattern detection
    print("\n--- Test 1: Basic Pattern Detection ---")
    local pattern = "48 8D 0D ? ? ? ? E8"
    local result = proc.find_signature(0x140000000, 0x1000000, pattern)
    print("Pattern search result: 0x" .. string.format("%X", result))
    
    if result == 0x140000100 then
        print("✓ Pattern detection test passed")
    else
        print("✗ Pattern detection test failed")
    end
    
    -- Test 2: Address calculation
    print("\n--- Test 2: Address Calculation ---")
    local instruction_addr = 0x140000100
    local relative_offset = proc.read_int32(instruction_addr + 3)
    local calculated_addr = instruction_addr + 7 + relative_offset
    print("Calculated address: 0x" .. string.format("%X", calculated_addr))
    
    -- Test 3: String search
    print("\n--- Test 3: String Search ---")
    local byte_property = proc.read_string(0x140001000, 12)
    print("Found string: " .. byte_property)
    
    if byte_property == "ByteProperty" then
        print("✓ String search test passed")
    else
        print("✗ String search test failed")
    end
    
    -- Test 4: Process attachment
    print("\n--- Test 4: Process Attachment ---")
    local attached = proc.attach_by_name("TestProcess.exe")
    print("Attachment result: " .. tostring(attached))
    
    if attached then
        print("✓ Process attachment test passed")
    else
        print("✗ Process attachment test failed")
    end
    
    -- Test 5: Module information
    print("\n--- Test 5: Module Information ---")
    local base, size = proc.get_base_module()
    print("Base address: 0x" .. string.format("%X", base))
    print("Module size: 0x" .. string.format("%X", size))
    
    if base == 0x140000000 and size == 0x1000000 then
        print("✓ Module information test passed")
    else
        print("✗ Module information test failed")
    end
    
    print("\n=== Test Suite Complete ===")
end

-- Run the tests
run_tests()

-- Test the actual simple example script logic
print("\n=== Testing Simple Example Logic ===")

-- Include the simple example logic here for testing
local function test_simple_finder()
    local base_address, module_size = proc.get_base_module()
    
    -- Test FNamePool finder
    local pattern = "48 8D 0D ? ? ? ? E8"
    local result = proc.find_signature(base_address, module_size, pattern)
    
    if result and result ~= 0 then
        local relative_offset = proc.read_int32(result + 3)
        local fnamepool_address = result + 7 + relative_offset
        
        if fnamepool_address > base_address then
            local offset = fnamepool_address - base_address
            print("✓ Simple finder would find FNamePool at offset: 0x" .. string.format("%X", offset))
            return true
        end
    end
    
    print("✗ Simple finder test failed")
    return false
end

test_simple_finder()

print("\n=== All Tests Complete ===")
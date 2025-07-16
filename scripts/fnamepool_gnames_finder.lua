-- FNamePool GNames Finder
-- This script implements the same functionality as the C++ code in Dumper-7
-- for finding FNamePool GNames and TNameEntryArray GNames in Unreal Engine processes

-- Configuration
local CONFIG = {
    INIT_SRW_LOCK_SEARCH_RANGE = 0x50,
    BYTE_PROPERTY_SEARCH_RANGE = 0x2A0,
    GET_NAMES_CALL_SEARCH_RANGE = 0x100,
    GET_NAMES_CALL_SEARCH_UPWARD = 0x150,
    ASM_RELATIVE_CALL_SIZE = 0x6
}

-- Global state
local g_process_attached = false
local g_base_address = 0
local g_base_module_size = 0

-- Logging helper
local function log(message, r, g, b, a)
    r = r or 255
    g = g or 255
    b = b or 255
    a = a or 255
    engine.log(message, r, g, b, a)
end

-- Success/Error logging
local function log_success(message)
    log(message, 0, 255, 0, 255)
end

local function log_error(message)
    log(message, 255, 0, 0, 255)
end

local function log_info(message)
    log(message, 0, 255, 255, 255)
end

-- Helper function to check if address is valid
local function is_valid_address(address)
    return address and address ~= 0 and address > 0x10000
end

-- Helper function to check if address is within process range
local function is_in_process_range(address)
    return address >= g_base_address and address < (g_base_address + g_base_module_size)
end

-- Helper function to read a uint32 from memory
local function read_uint32(address)
    if not is_valid_address(address) then
        return 0
    end
    return proc.read_int32(address)
end

-- Helper function to read a uint64 from memory
local function read_uint64(address)
    if not is_valid_address(address) then
        return 0
    end
    return proc.read_int64(address)
end

-- Helper function to read a pointer from memory
local function read_pointer(address)
    if not is_valid_address(address) then
        return 0
    end
    return proc.read_int64(address)
end

-- Helper function to resolve 32-bit relative call
local function resolve_32bit_relative_call(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 1)
    return instruction_address + 5 + relative_offset
end

-- Helper function to resolve 32-bit relative move
local function resolve_32bit_relative_move(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 3)
    return instruction_address + 7 + relative_offset
end

-- Helper function to resolve 32-bit section relative call
local function resolve_32bit_section_relative_call(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 2)
    return instruction_address + 6 + relative_offset
end

-- Pattern search helper
local function find_pattern(pattern, start_address, size)
    if not start_address then
        start_address = g_base_address
    end
    if not size then
        size = g_base_module_size
    end
    
    local result = proc.find_signature(start_address, size, pattern)
    return result
end

-- String search helper (simplified version)
local function find_string_in_module(search_string, start_address, search_range)
    if not start_address then
        start_address = g_base_address
    end
    if not search_range then
        search_range = g_base_module_size
    end
    
    -- Simple string search implementation
    -- This is a simplified version - in a real implementation you'd need more sophisticated string searching
    local current_address = start_address
    local end_address = start_address + search_range
    
    while current_address < end_address do
        local str = proc.read_string(current_address, #search_string)
        if str == search_string then
            return current_address
        end
        current_address = current_address + 1
    end
    
    return nil
end

-- Try to find FNamePool
local function try_find_name_pool()
    log_info("Attempting to find FNamePool...")
    
    -- Pattern for FNamePool constructor: "48 8D 0D ? ? ? ? E8"
    local pattern = "48 8D 0D ? ? ? ? E8"
    local sig_occurrence = 0
    local name_pool_instance = nil
    
    while not name_pool_instance do
        -- Find the next occurrence of this signature
        if sig_occurrence > 0 then
            sig_occurrence = sig_occurrence + 1
        end
        
        sig_occurrence = find_pattern(pattern, sig_occurrence)
        
        if not sig_occurrence or sig_occurrence == 0 then
            break
        end
        
        -- Get the constructor address from the call
        local constructor_address = resolve_32bit_relative_call(sig_occurrence + 7)
        
        if not is_in_process_range(constructor_address) then
            goto continue
        end
        
        -- Search for InitializeSRWLock call within the constructor
        for i = 0, CONFIG.INIT_SRW_LOCK_SEARCH_RANGE, 1 do
            local instruction_addr = constructor_address + i
            local opcode = proc.read_int16(instruction_addr)
            
            -- Check for relative call with opcodes FF 15
            if opcode == 0x15FF then
                local call_target = resolve_32bit_section_relative_call(instruction_addr)
                
                if not is_in_process_range(call_target) then
                    goto continue_inner
                end
                
                -- Check if this is a call to InitializeSRWLock (simplified check)
                -- In a real implementation, you'd need to check the import table
                
                -- Try to find "ByteProperty" string reference to verify this is the right function
                local byte_property_ref = find_string_in_module("ByteProperty", constructor_address, CONFIG.BYTE_PROPERTY_SEARCH_RANGE)
                
                if byte_property_ref then
                    name_pool_instance = resolve_32bit_relative_move(sig_occurrence)
                    log_success("Found FNamePool constructor with ByteProperty reference!")
                    break
                end
            end
            
            ::continue_inner::
        end
        
        if name_pool_instance then
            break
        end
        
        ::continue::
    end
    
    if name_pool_instance and is_valid_address(name_pool_instance) then
        local offset = name_pool_instance - g_base_address
        log_success(string.format("Found 'FNamePool GNames' at offset 0x%X", offset))
        return offset, true
    end
    
    return nil, false
end

-- Try to find TNameEntryArray (fallback)
local function try_find_name_array()
    log_info("Attempting to find TNameEntryArray...")
    
    -- This is a simplified implementation
    -- The actual C++ code is more complex and involves finding FName::GetNames calls
    
    -- Look for patterns that might indicate TNameEntryArray usage
    local patterns = {
        "48 8B ? ? ? ? ? 48 8B ? E8", -- mov rax, [GNames]; mov rcx, rax; call
        "48 8B ? ? ? ? ? 48 85 ? 74", -- mov rax, [GNames]; test rax, rax; jz
    }
    
    for _, pattern in ipairs(patterns) do
        local result = find_pattern(pattern)
        if result and result ~= 0 then
            -- Try to resolve the address
            local potential_gnames = resolve_32bit_relative_move(result)
            
            if is_in_process_range(potential_gnames) then
                -- Basic validation - check if it looks like a valid pointer
                local value = read_pointer(potential_gnames)
                if is_valid_address(value) then
                    local offset = potential_gnames - g_base_address
                    log_success(string.format("Found 'TNameEntryArray GNames' at offset 0x%X", offset))
                    return offset, true
                end
            end
        end
    end
    
    return nil, false
end

-- Main function to find GNames
local function find_gnames()
    log_info("Starting FNamePool GNames search...")
    
    -- First try to find FNamePool
    local offset, found = try_find_name_pool()
    if found then
        log_success("Successfully found FNamePool GNames!")
        return offset, "FNamePool"
    end
    
    -- Fallback to TNameEntryArray
    log_info("FNamePool not found, trying TNameEntryArray fallback...")
    offset, found = try_find_name_array()
    if found then
        log_success("Successfully found TNameEntryArray GNames!")
        return offset, "TNameEntryArray"
    end
    
    log_error("Could not find GNames!")
    return nil, nil
end

-- Process attachment function
local function attach_to_process(process_name)
    log_info("Attempting to attach to process: " .. process_name)
    
    if not proc.attach_by_name(process_name) then
        log_error("Failed to attach to process: " .. process_name)
        return false
    end
    
    log_success("Successfully attached to process: " .. process_name)
    
    -- Get process information
    local process_id = proc.pid()
    g_base_address, g_base_module_size = proc.get_base_module()
    
    log_info("Process ID: " .. process_id)
    log_info(string.format("Base Address: 0x%X", g_base_address))
    log_info(string.format("Module Size: 0x%X", g_base_module_size))
    
    g_process_attached = true
    return true
end

-- Main execution function
local function main()
    log_info("=== FNamePool GNames Finder ===")
    log_info("Lua implementation based on Dumper-7 C++ code")
    log_info("Current time: " .. time.now_local())
    
    -- Example usage - you would replace this with your target process
    local target_process = "UnrealEngine4.exe"  -- Change this to your target process
    
    if not attach_to_process(target_process) then
        log_error("Failed to attach to target process")
        return
    end
    
    -- Find GNames
    local offset, gnames_type = find_gnames()
    
    if offset then
        log_success("=== RESULTS ===")
        log_success(string.format("GNames Type: %s", gnames_type))
        log_success(string.format("GNames Offset: 0x%X", offset))
        log_success(string.format("GNames Address: 0x%X", g_base_address + offset))
        
        -- Additional validation
        local gnames_address = g_base_address + offset
        if gnames_type == "FNamePool" then
            log_info("Note: This is a direct pointer to FNamePool (no dereference needed)")
        else
            log_info("Note: This is a pointer to TNameEntryArray (dereference needed)")
        end
        
    else
        log_error("=== FAILED ===")
        log_error("Could not locate GNames in the target process")
        log_error("This might be due to:")
        log_error("- Process protection/encryption")
        log_error("- Unsupported Unreal Engine version")
        log_error("- Process not being an Unreal Engine game")
    end
    
    log_info("=== END ===")
end

-- Execute main function
main()
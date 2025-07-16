-- Advanced FNamePool GNames Finder
-- Enhanced implementation with more sophisticated pattern matching and validation
-- Based on Dumper-7 C++ implementation

-- Configuration constants
local CONFIG = {
    INIT_SRW_LOCK_SEARCH_RANGE = 0x50,
    BYTE_PROPERTY_SEARCH_RANGE = 0x2A0,
    GET_NAMES_CALL_SEARCH_RANGE = 0x100,
    GET_NAMES_CALL_SEARCH_UPWARD = 0x150,
    ASM_RELATIVE_CALL_SIZE = 0x6,
    MAX_ALLOWED_COMPARISON_INDEX = 0x4000000,
    CORE_UOBJECT_UINT64 = 0x6A624F5565726F43, -- "jbOUeroC" in little endian
    NONE_UINT32 = 0x656E6F4E, -- "None" in little endian
    BYTE_PROPERTY_START_UINT32 = 0x65747942, -- "Byte" in little endian
    NAME_WIDE_MASK = 0x1
}

-- Global state
local g_process_attached = false
local g_base_address = 0
local g_base_module_size = 0
local g_process_name = ""

-- Logging helpers
local function log(message, r, g, b, a)
    r = r or 255
    g = g or 255
    b = b or 255
    a = a or 255
    engine.log(message, r, g, b, a)
end

local function log_success(message)
    log("✓ " .. message, 0, 255, 0, 255)
end

local function log_error(message)
    log("✗ " .. message, 255, 0, 0, 255)
end

local function log_info(message)
    log("ℹ " .. message, 0, 255, 255, 255)
end

local function log_warning(message)
    log("⚠ " .. message, 255, 255, 0, 255)
end

-- Address validation helpers
local function is_valid_address(address)
    return address and address ~= 0 and address > 0x10000
end

local function is_in_process_range(address)
    return address >= g_base_address and address < (g_base_address + g_base_module_size)
end

local function is_bad_read_ptr(address)
    if not is_valid_address(address) then
        return true
    end
    
    -- Try to read a small amount of data to test if the address is readable
    local test_data = proc.read_int32(address)
    return test_data == nil
end

-- Memory reading helpers
local function read_uint8(address)
    if not is_valid_address(address) then return 0 end
    return proc.read_int8(address)
end

local function read_uint16(address)
    if not is_valid_address(address) then return 0 end
    return proc.read_int16(address)
end

local function read_uint32(address)
    if not is_valid_address(address) then return 0 end
    return proc.read_int32(address)
end

local function read_uint64(address)
    if not is_valid_address(address) then return 0 end
    return proc.read_int64(address)
end

local function read_pointer(address)
    return read_uint64(address)
end

-- ASM instruction helpers
local function resolve_32bit_relative_call(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 1)
    return instruction_address + 5 + relative_offset
end

local function resolve_32bit_relative_move(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 3)
    return instruction_address + 7 + relative_offset
end

local function resolve_32bit_section_relative_call(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 2)
    return instruction_address + 6 + relative_offset
end

-- Pattern search with enhanced error handling
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

-- Enhanced string search
local function find_string_in_range(search_string, start_address, search_range)
    if not start_address or not search_range then
        return nil
    end
    
    local current_address = start_address
    local end_address = start_address + search_range
    local string_len = #search_string
    
    -- Search in chunks to avoid excessive memory reads
    local chunk_size = 4096
    
    while current_address < end_address do
        local remaining = end_address - current_address
        local read_size = math.min(chunk_size, remaining)
        
        if read_size < string_len then
            break
        end
        
        local data = proc.read_string(current_address, read_size)
        if data then
            local pos = string.find(data, search_string, 1, true)
            if pos then
                return current_address + pos - 1
            end
        end
        
        current_address = current_address + chunk_size - string_len + 1
    end
    
    return nil
end

-- Advanced FNamePool detection
local function try_find_name_pool()
    log_info("Searching for FNamePool constructor...")
    
    -- Pattern for FNamePool constructor: "48 8D 0D ? ? ? ? E8"
    local pattern = "48 8D 0D ? ? ? ? E8"
    local sig_occurrence = 0
    local name_pool_instance = nil
    local attempts = 0
    local max_attempts = 100
    
    while not name_pool_instance and attempts < max_attempts do
        attempts = attempts + 1
        
        -- Find the next occurrence of this signature
        if sig_occurrence > 0 then
            sig_occurrence = sig_occurrence + 1
        end
        
        sig_occurrence = find_pattern(pattern, sig_occurrence)
        
        if not sig_occurrence or sig_occurrence == 0 then
            break
        end
        
        log_info(string.format("Analyzing pattern match #%d at 0x%X", attempts, sig_occurrence))
        
        -- Get the constructor address from the call
        local constructor_address = resolve_32bit_relative_call(sig_occurrence + 7)
        
        if not is_in_process_range(constructor_address) then
            log_warning("Constructor address out of range, skipping...")
            goto continue
        end
        
        log_info(string.format("Found potential constructor at 0x%X", constructor_address))
        
        -- Search for InitializeSRWLock or RtlInitializeSRWLock call within the constructor
        for i = 0, CONFIG.INIT_SRW_LOCK_SEARCH_RANGE, 1 do
            local instruction_addr = constructor_address + i
            local opcode = read_uint16(instruction_addr)
            
            -- Check for relative call with opcodes FF 15
            if opcode == 0x15FF then
                local call_target = resolve_32bit_section_relative_call(instruction_addr)
                
                if not is_in_process_range(call_target) then
                    goto continue_inner
                end
                
                -- Simplified check - in a real implementation you'd verify this is actually InitializeSRWLock
                local call_value = read_pointer(call_target)
                
                if is_valid_address(call_value) then
                    -- Try to find "ByteProperty" string reference to verify this is the right function
                    local byte_property_ref = find_string_in_range("ByteProperty", constructor_address, CONFIG.BYTE_PROPERTY_SEARCH_RANGE)
                    
                    if not byte_property_ref then
                        -- Try wide string version
                        byte_property_ref = find_string_in_range("B\0y\0t\0e\0P\0r\0o\0p\0e\0r\0t\0y\0", constructor_address, CONFIG.BYTE_PROPERTY_SEARCH_RANGE)
                    end
                    
                    if byte_property_ref then
                        name_pool_instance = resolve_32bit_relative_move(sig_occurrence)
                        log_success("Found FNamePool constructor with ByteProperty reference!")
                        log_info(string.format("ByteProperty reference found at 0x%X", byte_property_ref))
                        break
                    end
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
    
    log_warning("FNamePool not found after " .. attempts .. " attempts")
    return nil, false
end

-- Enhanced TNameEntryArray detection
local function try_find_name_array()
    log_info("Searching for TNameEntryArray...")
    
    -- Look for ByteProperty string reference first
    local byte_property_ref = find_string_in_range("ByteProperty", g_base_address, g_base_module_size)
    
    if not byte_property_ref then
        log_warning("ByteProperty string not found, cannot locate TNameEntryArray")
        return nil, false
    end
    
    log_info(string.format("Found ByteProperty string at 0x%X", byte_property_ref))
    
    -- Search upward for GetNames call
    for i = 0, CONFIG.GET_NAMES_CALL_SEARCH_UPWARD, 1 do
        local check_addr = byte_property_ref - i
        local opcode = read_uint8(check_addr)
        
        -- Look for call instruction (0xE8)
        if opcode == 0xE8 then
            local call_target = resolve_32bit_relative_call(check_addr)
            
            if is_in_process_range(call_target) then
                log_info(string.format("Found potential GetNames call at 0x%X", call_target))
                
                -- Search within the GetNames function for GNames reference
                for j = 0, CONFIG.GET_NAMES_CALL_SEARCH_RANGE, 1 do
                    local instr_addr = call_target + j
                    local move_opcode = read_uint16(instr_addr)
                    
                    -- Look for "mov rax, [address]" instruction (0x8B48)
                    if move_opcode == 0x8B48 then
                        local move_target = resolve_32bit_relative_move(instr_addr)
                        
                        if is_in_process_range(move_target) then
                            local value = read_pointer(move_target)
                            
                            if is_valid_address(value) and not is_bad_read_ptr(value) then
                                local offset = move_target - g_base_address
                                log_success(string.format("Found 'TNameEntryArray GNames' at offset 0x%X", offset))
                                return offset, true
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Alternative pattern search
    local patterns = {
        "48 8B 05 ? ? ? ? 48 8B ? ? 48 85 C0",
        "48 8B 15 ? ? ? ? 48 8B ? ? 48 85 D2",
        "48 8B 0D ? ? ? ? 48 8B ? ? 48 85 C9",
    }
    
    for _, pattern in ipairs(patterns) do
        local result = find_pattern(pattern)
        if result and result ~= 0 then
            local potential_gnames = resolve_32bit_relative_move(result)
            
            if is_in_process_range(potential_gnames) then
                local value = read_pointer(potential_gnames)
                if is_valid_address(value) and not is_bad_read_ptr(value) then
                    local offset = potential_gnames - g_base_address
                    log_success(string.format("Found 'TNameEntryArray GNames' at offset 0x%X (pattern match)", offset))
                    return offset, true
                end
            end
        end
    end
    
    return nil, false
end

-- Validation helpers
local function validate_name_pool(address)
    log_info("Validating FNamePool structure...")
    
    -- Check for expected FNamePool structure
    local max_chunks = read_uint32(address)
    local byte_cursor = read_uint32(address + 4)
    
    if max_chunks <= 0 or max_chunks > 0x10000 then
        log_warning("Invalid max_chunks value: " .. max_chunks)
        return false
    end
    
    if byte_cursor <= 0 or byte_cursor > 0x100000 then
        log_warning("Invalid byte_cursor value: " .. byte_cursor)
        return false
    end
    
    -- Check for valid chunk pointers
    local chunks_start = address + 0x10
    local valid_chunks = 0
    
    for i = 0, math.min(max_chunks, 10), 1 do
        local chunk_ptr = read_pointer(chunks_start + i * 8)
        if is_valid_address(chunk_ptr) and not is_bad_read_ptr(chunk_ptr) then
            valid_chunks = valid_chunks + 1
        end
    end
    
    if valid_chunks > 0 then
        log_success(string.format("FNamePool validation passed (%d valid chunks)", valid_chunks))
        return true
    else
        log_warning("FNamePool validation failed (no valid chunks)")
        return false
    end
end

local function validate_name_array(address)
    log_info("Validating TNameEntryArray structure...")
    
    local array_ptr = read_pointer(address)
    if not is_valid_address(array_ptr) or is_bad_read_ptr(array_ptr) then
        log_warning("Invalid array pointer")
        return false
    end
    
    -- Check for reasonable array structure
    local num_elements = read_uint32(array_ptr + 0x8)
    local max_elements = read_uint32(array_ptr + 0xC)
    
    if num_elements <= 0 or num_elements > 0x1000000 then
        log_warning("Invalid num_elements: " .. num_elements)
        return false
    end
    
    if max_elements <= num_elements or max_elements > 0x2000000 then
        log_warning("Invalid max_elements: " .. max_elements)
        return false
    end
    
    log_success(string.format("TNameEntryArray validation passed (%d elements)", num_elements))
    return true
end

-- Main GNames finder
local function find_gnames()
    log_info("Starting comprehensive GNames search...")
    
    -- First try to find FNamePool
    local offset, found = try_find_name_pool()
    if found then
        local full_address = g_base_address + offset
        if validate_name_pool(full_address) then
            log_success("Successfully found and validated FNamePool GNames!")
            return offset, "FNamePool"
        else
            log_warning("FNamePool found but validation failed")
        end
    end
    
    -- Fallback to TNameEntryArray
    log_info("Trying TNameEntryArray fallback...")
    offset, found = try_find_name_array()
    if found then
        local full_address = g_base_address + offset
        if validate_name_array(full_address) then
            log_success("Successfully found and validated TNameEntryArray GNames!")
            return offset, "TNameEntryArray"
        else
            log_warning("TNameEntryArray found but validation failed")
        end
    end
    
    log_error("Could not find or validate GNames!")
    return nil, nil
end

-- Process attachment
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
    g_process_name = process_name
    
    log_info("Process ID: " .. process_id)
    log_info(string.format("Base Address: 0x%X", g_base_address))
    log_info(string.format("Module Size: 0x%X", g_base_module_size))
    
    g_process_attached = true
    return true
end

-- Interactive mode
local function interactive_mode()
    log_info("=== Interactive Mode ===")
    log_info("Press keys to perform actions:")
    log_info("[1] - Search for GNames")
    log_info("[2] - Validate current results")
    log_info("[3] - Show process info")
    log_info("[ESC] - Exit")
    
    local last_offset = nil
    local last_type = nil
    
    while true do
        if input.is_key_pressed(49) then -- '1' key
            log_info("Starting GNames search...")
            last_offset, last_type = find_gnames()
            
        elseif input.is_key_pressed(50) then -- '2' key
            if last_offset and last_type then
                log_info("Re-validating previous results...")
                local full_address = g_base_address + last_offset
                if last_type == "FNamePool" then
                    validate_name_pool(full_address)
                else
                    validate_name_array(full_address)
                end
            else
                log_warning("No previous results to validate")
            end
            
        elseif input.is_key_pressed(51) then -- '3' key
            if g_process_attached then
                log_info("=== Process Information ===")
                log_info("Process: " .. g_process_name)
                log_info("PID: " .. proc.pid())
                log_info(string.format("Base: 0x%X", g_base_address))
                log_info(string.format("Size: 0x%X", g_base_module_size))
                log_info("Attached: " .. tostring(g_process_attached))
            else
                log_warning("No process attached")
            end
            
        elseif input.is_key_pressed(27) then -- ESC key
            log_info("Exiting interactive mode...")
            break
        end
        
        -- Small delay to prevent excessive CPU usage
        -- Note: This would need to be handled differently in a real implementation
    end
end

-- Main execution
local function main()
    log_info("=== Advanced FNamePool GNames Finder ===")
    log_info("Enhanced Lua implementation based on Dumper-7 C++ code")
    log_info("Version: 2.0")
    log_info("Time: " .. time.now_local())
    
    -- You can modify this to accept command line arguments or user input
    local target_process = "UE4Game.exe"  -- Change this to your target process
    
    -- Try some common Unreal Engine process names
    local common_processes = {
        "UE4Game.exe",
        "UnrealEngine.exe",
        "Game.exe",
        "Client.exe",
        "YourGameName.exe"
    }
    
    local attached = false
    for _, process in ipairs(common_processes) do
        if attach_to_process(process) then
            attached = true
            break
        end
    end
    
    if not attached then
        log_error("Could not attach to any common Unreal Engine process")
        log_info("Available processes to try: " .. table.concat(common_processes, ", "))
        return
    end
    
    -- Perform the search
    local offset, gnames_type = find_gnames()
    
    if offset then
        log_success("=== SUCCESS ===")
        log_success(string.format("GNames Type: %s", gnames_type))
        log_success(string.format("GNames Offset: 0x%X", offset))
        log_success(string.format("GNames Address: 0x%X", g_base_address + offset))
        
        if gnames_type == "FNamePool" then
            log_info("Usage: This is a direct pointer to FNamePool")
            log_info("C++ equivalent: FNamePool* GNames = (FNamePool*)(BaseAddress + 0x" .. string.format("%X", offset) .. ");")
        else
            log_info("Usage: This is a pointer to TNameEntryArray")
            log_info("C++ equivalent: TNameEntryArray* GNames = *(TNameEntryArray**)(BaseAddress + 0x" .. string.format("%X", offset) .. ");")
        end
        
        -- Start interactive mode for further testing
        interactive_mode()
        
    else
        log_error("=== FAILED ===")
        log_error("Could not locate GNames in the target process")
        log_error("Possible reasons:")
        log_error("• Process protection/encryption")
        log_error("• Unsupported Unreal Engine version")
        log_error("• Process is not an Unreal Engine game")
        log_error("• Anti-cheat interference")
    end
    
    log_info("=== END ===")
end

-- Register the main function to be called on engine tick
engine.register_on_engine_tick(main)
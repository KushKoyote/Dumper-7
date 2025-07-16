-- Simple FNamePool GNames Finder Example
-- Demonstrates basic usage of the GNames finding functionality

-- Simple logging function
local function log_info(msg)
    engine.log("INFO: " .. msg, 255, 255, 255, 255)
end

local function log_success(msg)
    engine.log("SUCCESS: " .. msg, 0, 255, 0, 255)
end

local function log_error(msg)
    engine.log("ERROR: " .. msg, 255, 0, 0, 255)
end

-- Simple FNamePool finder
local function find_fnamepool_simple(base_address, module_size)
    log_info("Searching for FNamePool pattern...")
    
    -- Look for FNamePool constructor pattern
    local pattern = "48 8D 0D ? ? ? ? E8"
    local result = proc.find_signature(base_address, module_size, pattern)
    
    if result and result ~= 0 then
        -- Extract the address from the LEA instruction
        local relative_offset = proc.read_int32(result + 3)
        local fnamepool_address = result + 7 + relative_offset
        
        if fnamepool_address > base_address then
            local offset = fnamepool_address - base_address
            log_success(string.format("Found potential FNamePool at offset 0x%X", offset))
            return offset
        end
    end
    
    return nil
end

-- Simple TNameEntryArray finder
local function find_namearray_simple(base_address, module_size)
    log_info("Searching for TNameEntryArray pattern...")
    
    -- Look for common GNames access patterns
    local patterns = {
        "48 8B 05 ? ? ? ? 48 8B",  -- mov rax, [GNames]
        "48 8B 15 ? ? ? ? 48 8B",  -- mov rdx, [GNames]
        "48 8B 0D ? ? ? ? 48 8B"   -- mov rcx, [GNames]
    }
    
    for _, pattern in ipairs(patterns) do
        local result = proc.find_signature(base_address, module_size, pattern)
        
        if result and result ~= 0 then
            -- Extract the address from the mov instruction
            local relative_offset = proc.read_int32(result + 3)
            local gnames_address = result + 7 + relative_offset
            
            if gnames_address > base_address then
                local offset = gnames_address - base_address
                log_success(string.format("Found potential TNameEntryArray at offset 0x%X", offset))
                return offset
            end
        end
    end
    
    return nil
end

-- Main function
local function main()
    log_info("=== Simple FNamePool GNames Finder ===")
    
    -- Try to attach to a common Unreal Engine process
    local processes = {"UE4Game.exe", "UnrealEngine.exe", "Game.exe"}
    local attached = false
    
    for _, process_name in ipairs(processes) do
        if proc.attach_by_name(process_name) then
            log_success("Attached to: " .. process_name)
            attached = true
            break
        end
    end
    
    if not attached then
        log_error("Could not attach to any Unreal Engine process")
        return
    end
    
    -- Get process information
    local base_address, module_size = proc.get_base_module()
    log_info(string.format("Base Address: 0x%X", base_address))
    log_info(string.format("Module Size: 0x%X", module_size))
    
    -- Try to find FNamePool first
    local offset = find_fnamepool_simple(base_address, module_size)
    if offset then
        log_success("Found FNamePool GNames!")
        log_success(string.format("Offset: 0x%X", offset))
        log_success(string.format("Address: 0x%X", base_address + offset))
        return
    end
    
    -- Fallback to TNameEntryArray
    offset = find_namearray_simple(base_address, module_size)
    if offset then
        log_success("Found TNameEntryArray GNames!")
        log_success(string.format("Offset: 0x%X", offset))
        log_success(string.format("Address: 0x%X", base_address + offset))
        return
    end
    
    log_error("Could not find GNames in the target process")
end

-- Run the main function
main()
-- Final Validation and Usage Example
-- This script demonstrates how to use the FNamePool GNames finder in practice

-- Include the core functionality (simplified version)
local GNamesFinder = {}

-- Configuration
GNamesFinder.CONFIG = {
    INIT_SRW_LOCK_SEARCH_RANGE = 0x50,
    BYTE_PROPERTY_SEARCH_RANGE = 0x2A0,
    GET_NAMES_CALL_SEARCH_RANGE = 0x100,
    PATTERNS = {
        FNAMEPOOL_CONSTRUCTOR = "48 8D 0D ? ? ? ? E8",
        GNAMES_ACCESS = {
            "48 8B 05 ? ? ? ? 48 8B",
            "48 8B 15 ? ? ? ? 48 8B",
            "48 8B 0D ? ? ? ? 48 8B"
        }
    }
}

-- State
GNamesFinder.state = {
    attached = false,
    base_address = 0,
    module_size = 0,
    process_name = ""
}

-- Utility functions
function GNamesFinder.log(message, color)
    local colors = {
        info = {0, 255, 255, 255},
        success = {0, 255, 0, 255},
        error = {255, 0, 0, 255},
        warning = {255, 255, 0, 255}
    }
    
    local c = colors[color] or colors.info
    engine.log(message, c[1], c[2], c[3], c[4])
end

function GNamesFinder.is_valid_address(address)
    return address and address ~= 0 and address > 0x10000
end

function GNamesFinder.resolve_32bit_relative_move(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 3)
    return instruction_address + 7 + relative_offset
end

function GNamesFinder.resolve_32bit_relative_call(instruction_address)
    local relative_offset = proc.read_int32(instruction_address + 1)
    return instruction_address + 5 + relative_offset
end

-- Main search functions
function GNamesFinder.find_fnamepool()
    GNamesFinder.log("Searching for FNamePool...", "info")
    
    local pattern = GNamesFinder.CONFIG.PATTERNS.FNAMEPOOL_CONSTRUCTOR
    local result = proc.find_signature(GNamesFinder.state.base_address, GNamesFinder.state.module_size, pattern)
    
    if result and result ~= 0 then
        local fnamepool_address = GNamesFinder.resolve_32bit_relative_move(result)
        
        if fnamepool_address > GNamesFinder.state.base_address then
            local offset = fnamepool_address - GNamesFinder.state.base_address
            GNamesFinder.log(string.format("Found FNamePool at offset 0x%X", offset), "success")
            return offset, "FNamePool"
        end
    end
    
    return nil, nil
end

function GNamesFinder.find_namearray()
    GNamesFinder.log("Searching for TNameEntryArray...", "info")
    
    for _, pattern in ipairs(GNamesFinder.CONFIG.PATTERNS.GNAMES_ACCESS) do
        local result = proc.find_signature(GNamesFinder.state.base_address, GNamesFinder.state.module_size, pattern)
        
        if result and result ~= 0 then
            local gnames_address = GNamesFinder.resolve_32bit_relative_move(result)
            
            if gnames_address > GNamesFinder.state.base_address then
                local offset = gnames_address - GNamesFinder.state.base_address
                GNamesFinder.log(string.format("Found TNameEntryArray at offset 0x%X", offset), "success")
                return offset, "TNameEntryArray"
            end
        end
    end
    
    return nil, nil
end

function GNamesFinder.attach_to_process(process_name)
    GNamesFinder.log("Attaching to process: " .. process_name, "info")
    
    if not proc.attach_by_name(process_name) then
        GNamesFinder.log("Failed to attach to process", "error")
        return false
    end
    
    GNamesFinder.state.attached = true
    GNamesFinder.state.process_name = process_name
    GNamesFinder.state.base_address, GNamesFinder.state.module_size = proc.get_base_module()
    
    GNamesFinder.log("Successfully attached!", "success")
    GNamesFinder.log(string.format("Base: 0x%X, Size: 0x%X", GNamesFinder.state.base_address, GNamesFinder.state.module_size), "info")
    
    return true
end

function GNamesFinder.search()
    if not GNamesFinder.state.attached then
        GNamesFinder.log("No process attached", "error")
        return nil, nil
    end
    
    -- Try FNamePool first
    local offset, type_name = GNamesFinder.find_fnamepool()
    if offset then
        return offset, type_name
    end
    
    -- Fallback to TNameEntryArray
    offset, type_name = GNamesFinder.find_namearray()
    if offset then
        return offset, type_name
    end
    
    GNamesFinder.log("Could not find GNames", "error")
    return nil, nil
end

-- Usage example
function usage_example()
    GNamesFinder.log("=== FNamePool GNames Finder - Usage Example ===", "info")
    
    -- List of common Unreal Engine process names to try
    local target_processes = {
        "UE4Game.exe",
        "UnrealEngine.exe",
        "Game.exe",
        "Client.exe",
        "FortniteClient-Win64-Shipping.exe",
        "RocketLeague.exe",
        "DeadByDaylight-Win64-Shipping.exe"
    }
    
    local attached = false
    for _, process_name in ipairs(target_processes) do
        if GNamesFinder.attach_to_process(process_name) then
            attached = true
            break
        end
    end
    
    if not attached then
        GNamesFinder.log("Could not attach to any target process", "error")
        GNamesFinder.log("Available processes to try:", "info")
        for _, name in ipairs(target_processes) do
            GNamesFinder.log("  - " .. name, "info")
        end
        return
    end
    
    -- Perform the search
    local offset, gnames_type = GNamesFinder.search()
    
    if offset then
        GNamesFinder.log("=== RESULTS ===", "success")
        GNamesFinder.log("Process: " .. GNamesFinder.state.process_name, "info")
        GNamesFinder.log("GNames Type: " .. gnames_type, "success")
        GNamesFinder.log(string.format("Offset: 0x%X", offset), "success")
        GNamesFinder.log(string.format("Address: 0x%X", GNamesFinder.state.base_address + offset), "success")
        
        -- Provide usage instructions
        GNamesFinder.log("=== USAGE INSTRUCTIONS ===", "info")
        if gnames_type == "FNamePool" then
            GNamesFinder.log("This is a direct pointer to FNamePool:", "info")
            GNamesFinder.log("  FNamePool* GNames = (FNamePool*)(BaseAddress + 0x" .. string.format("%X", offset) .. ");", "info")
            GNamesFinder.log("  No dereferencing needed", "info")
        else
            GNamesFinder.log("This is a pointer to TNameEntryArray:", "info")
            GNamesFinder.log("  TNameEntryArray* GNames = *(TNameEntryArray**)(BaseAddress + 0x" .. string.format("%X", offset) .. ");", "info")
            GNamesFinder.log("  Dereference the pointer before use", "info")
        end
        
        -- Additional validation
        local gnames_address = GNamesFinder.state.base_address + offset
        local first_value = proc.read_int64(gnames_address)
        GNamesFinder.log(string.format("First value at GNames: 0x%X", first_value), "info")
        
        if GNamesFinder.is_valid_address(first_value) then
            GNamesFinder.log("✓ GNames appears to contain valid data", "success")
        else
            GNamesFinder.log("⚠ GNames might need dereferencing or validation", "warning")
        end
        
    else
        GNamesFinder.log("=== FAILED ===", "error")
        GNamesFinder.log("Could not locate GNames", "error")
        GNamesFinder.log("Possible issues:", "error")
        GNamesFinder.log("  • Process has anti-cheat protection", "error")
        GNamesFinder.log("  • Unsupported Unreal Engine version", "error")
        GNamesFinder.log("  • Process is not an Unreal Engine game", "error")
        GNamesFinder.log("  • Memory encryption is active", "error")
    end
end

-- Interactive mode
function interactive_mode()
    GNamesFinder.log("=== Interactive Mode ===", "info")
    GNamesFinder.log("Commands:", "info")
    GNamesFinder.log("  [F1] - Run search", "info")
    GNamesFinder.log("  [F2] - Show process info", "info")
    GNamesFinder.log("  [F3] - Exit", "info")
    
    local running = true
    while running do
        if input.is_key_pressed(112) then -- F1
            local offset, type_name = GNamesFinder.search()
            if offset then
                GNamesFinder.log("Search completed successfully!", "success")
            else
                GNamesFinder.log("Search failed", "error")
            end
            
        elseif input.is_key_pressed(113) then -- F2
            if GNamesFinder.state.attached then
                GNamesFinder.log("Process: " .. GNamesFinder.state.process_name, "info")
                GNamesFinder.log("PID: " .. proc.pid(), "info")
                GNamesFinder.log(string.format("Base: 0x%X", GNamesFinder.state.base_address), "info")
                GNamesFinder.log(string.format("Size: 0x%X", GNamesFinder.state.module_size), "info")
            else
                GNamesFinder.log("No process attached", "warning")
            end
            
        elseif input.is_key_pressed(114) then -- F3
            GNamesFinder.log("Exiting interactive mode", "info")
            running = false
        end
    end
end

-- Main execution
function main()
    usage_example()
    interactive_mode()
end

-- Register the main function
engine.register_on_engine_tick(main)
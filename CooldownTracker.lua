-- CooldownTracker.lua
local addonName = "CooldownTracker"

-- Manual table copy function
local function CopyTable(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = CopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Manual string split function for 1.12 - Optimized
local function CustomStrSplit(inputstr, sep)
    if not inputstr then return nil end
    sep = sep or " "
    local t = {}
    local i = 1
    for str in string.gfind(inputstr, "([^"..sep.."]+)") do
        t[i] = str
        i = i + 1
    end
    return unpack(t)
end

-- Define a function to wipe tables for vanilla WoW
local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

-- Create default database structure
local defaultDB = {
    config = {
        locked = true,  -- Default to locked
        iconAnchor = "CENTER",
        iconX = 0,
        iconY = 0,
        iconSpacing = 30,
        iconSize = 36,  -- Default icon size
        iconAlpha = 1.0,  -- Alpha/transparency option
        cooldownScale = (1 / 32) * 36,  -- Compute scale based on icon size
        updateInterval = 0.1,  -- Configurable update interval
    },
    
    -- This will store spell info found in spellbook
    spellCache = {}
}

-- Global tracking tables
local trackingFrames = {} -- Combined table to track all frames (spells and items)
local needsUpdate = false -- Flag to prevent unnecessary updates
local frame = CreateFrame("Frame") -- Our main addon frame
local playerInCombat = false -- Track player combat state

-- Item tracking cache
local itemCache = {} -- Stores bag and slot info for tracked items
local itemMissingFromBags = {} -- Track which items are missing from bags
local itemLocations = {} -- Quick lookup for item locations

-- Item name extraction cache to avoid repeated string operations
local itemNameCache = {}

-- Performance tracking
local trackedSpellCount = 0
local trackedItemCount = 0

-- Cache frequently used values
local function CacheFrequentValues()
    CooldownTrackerDB.config.cooldownScale = (1 / 32) * CooldownTrackerDB.config.iconSize
end

-- Initialize database with default values if needed
local function InitDB()
    if not CooldownTrackerDB then
        CooldownTrackerDB = CopyTable(defaultDB)
        CooldownTrackerDB.iconPositions = {} -- Add positions table
    else
        -- Make sure all default fields exist
        for k, v in pairs(defaultDB) do
            if CooldownTrackerDB[k] == nil then
                CooldownTrackerDB[k] = CopyTable(v)
            elseif type(v) == "table" and k == "config" then
                -- For config, make sure all default settings exist
                for configKey, configVal in pairs(v) do
                    if CooldownTrackerDB[k][configKey] == nil then
                        CooldownTrackerDB[k][configKey] = configVal
                    end
                end
            end
        end
        
        -- Ensure we have an icon positions table
        if not CooldownTrackerDB.iconPositions then
            CooldownTrackerDB.iconPositions = {}
        end
    end
    
    -- Cache frequently used values
    CacheFrequentValues()
end

-- Function to find spell info in spellbook (only run on initialization)
-- Optimized to use a more efficient tab processing method
local function FindSpellInfo(spellName)
    local lowerSpellName = string.lower(spellName)
    
    -- Iterate through spellbook tabs
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        
        -- Iterate through spells in this tab
        for i = 1, numSpells do
            local bookSpellName = GetSpellName(offset + i, BOOKTYPE_SPELL)
            
            -- Check if this is the spell we're looking for (using lower case for both)
            if bookSpellName and string.lower(bookSpellName) == lowerSpellName then
                local texture = GetSpellTexture(offset + i, BOOKTYPE_SPELL)
                
                -- Return the spell info
                return {
                    texture = texture,
                    offset = offset + i
                }
            end
        end
    end
    
    return nil
end

-- Pre-allocate texture coordinates to avoid creating tables in CreateTrackingFrame
local texCoord = {0.08, 0.92, 0.08, 0.92}

-- Function to create a tracking frame (used for both spells and items)
local function CreateTrackingFrame(name, texture, iconCount, isSpell, spellOffset)
    local config = CooldownTrackerDB.config

    -- Create main frame
    local frame = CreateFrame("Frame", addonName.."_"..name, UIParent)
    frame:SetWidth(config.iconSize)
    frame:SetHeight(config.iconSize)
    
    -- Use saved position if available
    if CooldownTrackerDB.iconPositions and CooldownTrackerDB.iconPositions[name] then
        local pos = CooldownTrackerDB.iconPositions[name]
        frame:SetPoint(pos.anchor, UIParent, pos.anchor, pos.x, pos.y)
    else
        -- Default position
        frame:SetPoint(config.iconAnchor, UIParent, config.iconAnchor,
            config.iconX + ((iconCount-1) * config.iconSpacing), config.iconY)
    end

    -- Set alpha
    frame:SetAlpha(config.iconAlpha)

    -- Properly handle locking mechanism
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(not config.locked)

    -- Icon texture with zoom
    local icon = frame:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(texture)
    icon:SetAllPoints(frame)

    -- Apply texture coordinate zoom using pre-allocated table
    icon:SetTexCoord(unpack(texCoord))

    -- Cooldown frame with enhanced positioning and scaling
    local cooldown = CreateFrame("Model", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)

    -- Compute scale based on icon size
    cooldown:SetScale(config.cooldownScale)

    -- Enhanced cooldown frame positioning
    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT", frame, "TOPLEFT")
    cooldown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")

    -- Dragging scripts
    frame:SetScript("OnDragStart", function()
        if not CooldownTrackerDB.config.locked then
            this:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function()
        if not CooldownTrackerDB.config.locked then
            this:StopMovingOrSizing()
            local anchor, _, _, x, y = this:GetPoint()
            
            -- Create positions table if it doesn't exist
            if not CooldownTrackerDB.iconPositions then
                CooldownTrackerDB.iconPositions = {}
            end
            
            -- Save this specific icon's position
            CooldownTrackerDB.iconPositions[name] = {
                anchor = anchor,
                x = x,
                y = y
            }
        end
    end)

    -- Return the constructed frame data
    return {
        frame = frame,
        icon = icon,
        cooldown = cooldown,
        isSpell = isSpell,
        spellOffset = spellOffset,
        itemName = not isSpell and name or nil,
        startTime = 0,
        duration = 0,
        lastUpdate = 0,
        active = false,
        missingFromBags = false,
        originalAlpha = config.iconAlpha,
        name = name -- Store name for reference
    }
end

-- Function to extract item name from link - optimized with caching
local function GetItemNameFromLink(link)
    if not link then return nil end
    
    -- Check cache first
    if itemNameCache[link] then
        return itemNameCache[link]
    end
    
    local start, stop = string.find(link, "%[.+%]")
    if start and stop then
        local name = string.sub(link, start + 1, stop - 1)
        itemNameCache[link] = name
        return name
    end
    return nil
end

-- Initialize item tracking frames
local function InitializeItemFrames(startIconCount)
    local iconCount = startIconCount
    
    -- Get the itemsToTrack table from the settings file
    local _, itemsToTrack = GetCooldownTrackerSettings()
    
    -- Create frames for items with icons
    for itemName, iconTexture in pairs(itemsToTrack) do
        if not trackingFrames[itemName] then
            iconCount = iconCount + 1
            
            -- Create tracking frame for this item
            trackingFrames[itemName] = CreateTrackingFrame(
                itemName,
                iconTexture,
                iconCount,
                false,  -- Not a spell
                nil     -- No spell offset
            )
            
            trackedItemCount = trackedItemCount + 1
        end
    end
    
    return iconCount
end

-- IMPROVED: Consolidated function to handle item states (missing/found)
local function UpdateItemState(itemName, isMissing)
    local frameData = trackingFrames[itemName]
    if not frameData then return end
    
    if isMissing then
        if not frameData.missingFromBags then
            frameData.missingFromBags = true
            frameData.icon:SetAlpha(0.28)  -- Set alpha to 28%
        end
    else
        if frameData.missingFromBags then
            frameData.missingFromBags = false
            frameData.icon:SetAlpha(frameData.originalAlpha) -- Restore original alpha
        end
    end
end

-- IMPROVED: Function to update item cooldown
local function UpdateItemCooldown(itemName, location)
    local frameData = trackingFrames[itemName]
    if not frameData then return end
    
    -- Get cooldown info
    local startTime, duration, enable = GetContainerItemCooldown(location.bag, location.slot)
    
    -- Only update if cooldown has changed
    if startTime and duration and (frameData.startTime ~= startTime or frameData.duration ~= duration) then
        frameData.startTime = startTime
        frameData.duration = duration
        frameData.lastUpdate = GetTime()
        
        if startTime > 0 and duration > 0 then
            CooldownFrame_SetTimer(frameData.cooldown, startTime, duration, enable)
            frameData.active = true
        else
            -- Clear cooldown if it's done
            CooldownFrame_SetTimer(frameData.cooldown, 0, 0, 0)
            frameData.active = false
        end
    end
end

-- IMPROVED: Create a lookup table of tracked items
local trackedItemLookup = {}

-- IMPROVED: Function to initialize tracked item lookup
local function InitializeTrackedItemLookup()
    wipe(trackedItemLookup)
    local _, itemsToTrack = GetCooldownTrackerSettings()
    
    for itemName in pairs(itemsToTrack) do
        trackedItemLookup[itemName] = true
    end
end

-- IMPROVED: Optimized bag scanning - handles both combat and non-combat situations
local function ScanBagsForItems()
    -- Clear current item location cache but preserve missing state
    local previouslyMissing = CopyTable(itemMissingFromBags)
    wipe(itemLocations)
    wipe(itemMissingFromBags)
    
    -- Scan all bags
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        
        for slot = 1, numSlots do
            local itemLink = GetContainerItemLink(bag, slot)
            
            if itemLink then
                -- Extract item name from link
                local itemName = GetItemNameFromLink(itemLink)
                
                -- Check if this is an item we're tracking
                if itemName and trackedItemLookup[itemName] then
                    -- Track location
                    if not itemLocations[itemName] then
                        itemLocations[itemName] = {}
                    end
                    
                    local location = {bag = bag, slot = slot}
                    table.insert(itemLocations[itemName], location)
                    
                    -- If not in combat, update cooldown for newly found items
                    if not playerInCombat and previouslyMissing[itemName] then
                        UpdateItemCooldown(itemName, location)
                    end
                end
            end
        end
    end
    
    -- Update missing item states
    for itemName in pairs(trackedItemLookup) do
        local isMissing = not itemLocations[itemName] or table.getn(itemLocations[itemName]) == 0
        itemMissingFromBags[itemName] = isMissing
        UpdateItemState(itemName, isMissing)
    end
    
    -- Force a full cooldown update after scanning if not in combat
    if not playerInCombat then
        needsUpdate = true
    end
end

-- IMPROVED: Combat-safe verification function that only checks existing locations
local function VerifyTrackedItemsInCombat()
    for itemName, locations in pairs(itemLocations) do
        if locations and table.getn(locations) > 0 then
            local validLocations = {}
            local stillValid = false
            
            -- Check each known location
            for _, location in ipairs(locations) do
                local link = GetContainerItemLink(location.bag, location.slot)
                local nameInSlot = link and GetItemNameFromLink(link)
                
                if nameInSlot and nameInSlot == itemName then
                    table.insert(validLocations, location)
                    stillValid = true
                end
            end
            
            -- Update the locations table with only valid locations
            itemLocations[itemName] = validLocations
            
            -- If no valid locations remain, mark as missing
            if not stillValid then
                itemMissingFromBags[itemName] = true
                UpdateItemState(itemName, true)
            end
        end
    end
end

-- Function to initialize all tracking icons at once
local function InitializeIcons()
    local iconCount = 0
    wipe(trackingFrames)
    trackedSpellCount = 0
    trackedItemCount = 0
    
    -- Get spell and item tables from settings file
    local spellsToTrack, _ = GetCooldownTrackerSettings()
    
    -- 1. Initialize Spell Icons
    -- Pre-process spell names to lowercase for faster comparison later
    local spellsToTrackLower = {}
    for i, spellName in ipairs(spellsToTrack) do
        spellsToTrackLower[i] = string.lower(spellName)
    end
    
    for i, spellName in ipairs(spellsToTrack) do
        -- Find spell in spellbook if not already cached
        if not CooldownTrackerDB.spellCache[spellName] then
            CooldownTrackerDB.spellCache[spellName] = FindSpellInfo(spellName)
        end
        
        local spellInfo = CooldownTrackerDB.spellCache[spellName]
        
        if spellInfo and spellInfo.texture then
            iconCount = iconCount + 1
            
            -- Create tracking frame for this spell
            trackingFrames[spellName] = CreateTrackingFrame(
                spellName,
                spellInfo.texture,
                iconCount,
                true,  -- isSpell
                spellInfo.offset
            )
            
            trackedSpellCount = trackedSpellCount + 1
        end
    end
    
    -- 2. Initialize Item Icons and Lookup Table
    InitializeTrackedItemLookup()
    iconCount = InitializeItemFrames(iconCount)
    
    return iconCount
end

-- Optimization to avoid repeated GetTime() calls
local currentTime = 0

-- IMPROVED: Function to update item cooldowns - more efficient batch processing
local function UpdateItemCooldowns()
    -- Update cooldowns for each tracked item with known locations
    for itemName, locations in pairs(itemLocations) do
        if locations and table.getn(locations) > 0 then
            -- Take the first instance for cooldown info (all instances of same item share cooldown)
            local location = locations[1]
            UpdateItemCooldown(itemName, location)
        end
    end
end

-- Efficient function to update all cooldowns at once
local function UpdateAllCooldowns()
    if not needsUpdate then return end
    
    currentTime = GetTime()
    
    -- Update spell cooldowns
    for id, frameData in pairs(trackingFrames) do
        if frameData.isSpell then
            -- Update spell cooldowns
            local startTime, duration, enable = GetSpellCooldown(frameData.spellOffset, BOOKTYPE_SPELL)
            
            -- Only update if cooldown has changed
            if startTime and duration and (frameData.startTime ~= startTime or frameData.duration ~= duration) then
                frameData.startTime = startTime
                frameData.duration = duration
                frameData.lastUpdate = currentTime
                
                if startTime > 0 and duration > 0 then
                    CooldownFrame_SetTimer(frameData.cooldown, startTime, duration, enable)
                    frameData.active = true
                else
                    -- Clear cooldown if it's done
                    CooldownFrame_SetTimer(frameData.cooldown, 0, 0, 0)
                    frameData.active = false
                end
            end
        end
    end
    
    -- Update item cooldowns
    UpdateItemCooldowns()
    
    needsUpdate = false
end

-- Utility function to add item to track
local function AddItemToTrack(itemName)
    -- Get the itemsToTrack table from the settings file
    local _, itemsToTrack = GetCooldownTrackerSettings()

    -- Skip if already tracking
    if itemsToTrack[itemName] then
        return true
    end
    
    -- Add to settings with default icon
    itemsToTrack[itemName] = "Interface\\Icons\\INV_Misc_QuestionMark" -- Default icon
    
    -- Update tracked item lookup
    trackedItemLookup[itemName] = true
    
    -- Initialize frame for this item
    local iconCount = 0
    for _ in pairs(trackingFrames) do 
        iconCount = iconCount + 1 
    end
    
    -- Create tracking frame if not exists
    if not trackingFrames[itemName] then
        trackingFrames[itemName] = CreateTrackingFrame(
            itemName,
            itemsToTrack[itemName],
            iconCount + 1,
            false,  -- Not a spell
            nil     -- No spell offset
        )
        trackedItemCount = trackedItemCount + 1
    end
    
    -- Rescan bags to find this item
    ScanBagsForItems()
    
    -- Return success/failure
    return not itemMissingFromBags[itemName]
end

-- Slash command handler - optimized to reduce string operations
local function SlashCommand(msg)
    if not msg or msg == "" then
        DEFAULT_CHAT_FRAME:AddMessage(addonName.." Commands:", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt lock - Toggle frame locking", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt size <number> - Set icon size (10-100)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt alpha <number> - Set icon transparency (0.1-1.0)", 1, 1, 1)
        return
    end
    
    -- Split the command into parts
    local cmd, value = CustomStrSplit(msg)
    local config = CooldownTrackerDB.config
    
    -- Convert value to number if possible
    local numValue = tonumber(value)
    
    if cmd == "lock" then
        config.locked = not config.locked
        
        -- Update all frames at once
        for _, frameData in pairs(trackingFrames) do
            frameData.frame:EnableMouse(not config.locked)
        end
        
        DEFAULT_CHAT_FRAME:AddMessage(addonName..": Frames "..(config.locked and "locked" or "unlocked"), config.locked and 0 or 1, config.locked and 1 or 0, 0)
    
    elseif cmd == "size" and numValue then
        if numValue >= 10 and numValue <= 100 then
            config.iconSize = numValue
            CacheFrequentValues() -- Update cached values
            
            -- Resize all frames at once
            for _, frameData in pairs(trackingFrames) do
                frameData.frame:SetWidth(numValue)
                frameData.frame:SetHeight(numValue)
                
                -- Adjust cooldown frame scaling and positioning
                frameData.cooldown:SetScale(config.cooldownScale)
                
                frameData.cooldown:ClearAllPoints()
                frameData.cooldown:SetPoint("TOPLEFT", frameData.frame, "TOPLEFT")
                frameData.cooldown:SetPoint("BOTTOMRIGHT", frameData.frame, "BOTTOMRIGHT")
            end
            
            DEFAULT_CHAT_FRAME:AddMessage(addonName..": Icon size set to "..numValue, 0, 1, 1)
        else
            DEFAULT_CHAT_FRAME:AddMessage(addonName..": Invalid size. Use /cdt size <number> between 10 and 100", 1, 0, 0)
        end
    
    elseif cmd == "alpha" and numValue then
        if numValue >= 0.1 and numValue <= 1.0 then
            config.iconAlpha = numValue
            
            -- Update all frames at once
            for _, frameData in pairs(trackingFrames) do
                frameData.frame:SetAlpha(numValue)
            end
            
            DEFAULT_CHAT_FRAME:AddMessage(addonName..": Icon alpha set to "..numValue, 0, 1, 1)
        else
            DEFAULT_CHAT_FRAME:AddMessage(addonName..": Invalid alpha. Use /cdt alpha <number> between 0.1 and 1.0", 1, 0, 0)
        end
    
    else
        -- Show help message for any unrecognized command
        DEFAULT_CHAT_FRAME:AddMessage(addonName.." Commands:", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt lock - Toggle frame locking", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt size <number> - Set icon size (10-100)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt alpha <number> - Set icon transparency (0.1-1.0)", 1, 1, 1)
    end
end

local lastUpdate = 0

-- Optimized OnUpdate handler with configurable update interval
local function OnUpdate()
    currentTime = GetTime()
    
    -- Check if enough time has passed according to config
    if currentTime - lastUpdate >= CooldownTrackerDB.config.updateInterval then
        UpdateAllCooldowns()
        lastUpdate = currentTime
    end
end

-- IMPROVED: Throttled event handler for BAG_UPDATE with combat awareness
local bagUpdateThrottle = 0
local bagUpdatePending = false

-- IMPROVED: Combat state tracking functions
local function OnPlayerEnterCombat()
    playerInCombat = true
end

local function OnPlayerLeaveCombat()
    playerInCombat = false
    
    -- Do a full bag scan when leaving combat if pending
    if bagUpdatePending then
        ScanBagsForItems()
        bagUpdatePending = false
        bagUpdateThrottle = GetTime()
    end
end

-- IMPROVED: BAG_UPDATE handler with combat awareness
local function OnBagUpdate()
    -- If in combat, only verify existing items
    if playerInCombat then
        VerifyTrackedItemsInCombat()
        bagUpdatePending = true
        return
    end
    
    -- Out of combat - schedule a full scan if not done recently
    bagUpdatePending = true
    
    if GetTime() - bagUpdateThrottle > 0.5 then
        ScanBagsForItems()
        bagUpdateThrottle = GetTime()
        bagUpdatePending = false
    end
end

-- In the OnEvent function, handle combat events and improve event handling
local function OnEvent()
    if event == "VARIABLES_LOADED" then
        -- Initialize the database
        InitDB()
        
        -- Register for PLAYER_ENTERING_WORLD to ensure spellbook is loaded
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Initialize all icons after spellbook is loaded
        local iconCount = InitializeIcons()
        
        -- Initial bag scan
        ScanBagsForItems()
        
        -- Set up the OnUpdate handler for efficient updates
        frame:SetScript("OnUpdate", OnUpdate)
        
        -- Print initialization message
        DEFAULT_CHAT_FRAME:AddMessage(addonName.." loaded. Tracking "..trackedSpellCount.." spell(s) and "..trackedItemCount.." item(s).", 0, 1, 0)
        
        -- Register slash commands if not already done
        if not SlashCmdList["COOLDOWNTRACKER"] then
            SLASH_COOLDOWNTRACKER1 = "/cdt"
            SLASH_COOLDOWNTRACKER2 = "/cooldowntracker"
            SlashCmdList["COOLDOWNTRACKER"] = SlashCommand
        end
        
        -- Unregister this event to avoid repeated initialization
        frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        
        -- Register for spell changes and combat events
        frame:RegisterEvent("SPELLS_CHANGED")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Enter combat
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leave combat
        
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnPlayerEnterCombat()
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnPlayerLeaveCombat()
        
    elseif event == "SPELLS_CHANGED" then
        -- Don't completely reinitialize frames, just update spell info if needed
        for spellName, frameData in pairs(trackingFrames) do
            if frameData.isSpell then
                -- Re-check spell info in case rank or texture changed
                local updatedInfo = FindSpellInfo(spellName)
                if updatedInfo and updatedInfo.offset ~= frameData.spellOffset then
                    -- Update the spell offset for cooldown tracking
                    frameData.spellOffset = updatedInfo.offset
                    
                    -- Update texture if it changed
                    if updatedInfo.texture ~= frameData.icon:GetTexture() then
                        frameData.icon:SetTexture(updatedInfo.texture)
                    end
                    
                    -- Update cached spell info
                    CooldownTrackerDB.spellCache[spellName] = updatedInfo
                end
            end
        end
        
        -- Mark for cooldown update
        needsUpdate = true
    
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Mark that we need to update cooldowns
        needsUpdate = true
    
    elseif event == "BAG_UPDATE" then
        -- Throttled bag update handling with combat awareness
        OnBagUpdate()
    
    elseif event == "BAG_UPDATE_COOLDOWN" then
        -- Item cooldowns changed, mark for update
        needsUpdate = true
        
        -- If in combat, verify tracked items
        if playerInCombat then
            VerifyTrackedItemsInCombat()
        else
            -- If we have a pending bag update, process it now
            if bagUpdatePending then
                ScanBagsForItems()
                bagUpdatePending = false
                bagUpdateThrottle = GetTime()
            end
        end
    end
end

-- Register events
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:SetScript("OnEvent", OnEvent)
--[[
    CooldownTracker.lua
    
    A World of Warcraft (1.12) addon for tracking cooldowns of spells and items.
    
    Features:
    - Tracks spell cooldowns
    - Tracks item cooldowns
    - Configurable icon size, transparency, and positioning
    - Performance optimizations
    - Drag-and-drop positioning for each icon
    
    Version: 1.0
    Author: Abstractz
    Last updated: 2025-03-15
]]

-- Addon namespace
local addonName = "CooldownTracker"

--- **************************************************************************
-- CONSTANTS AND DEFAULT VALUES
-- **************************************************************************

-- Default database structure
local defaultDB = {
    config = {
        locked = true,                  -- Default to locked
        iconAnchor = "CENTER",          -- Default anchor point
        iconX = 0,                      -- Default X position
        iconY = 0,                      -- Default Y position
        iconSpacing = 30,               -- Default spacing between icons
        iconSize = 36,                  -- Default icon size
        iconAlpha = 1.0,                -- Default alpha/transparency
        cooldownScale = (1 / 32) * 36,  -- Computed scale based on icon size
        updateInterval = 0.1,           -- Update interval in seconds
    },
    
    -- Stores spell info found in spellbook
    spellCache = {},
    
    -- Stores individual icon sizes
    individualIconSizes = {},
    
    -- Stores icon positions
    iconPositions = {}
}

-- Pre-allocate texture coordinates to avoid creating tables in CreateTrackingFrame
local TEXTURE_COORDINATES = {0.08, 0.92, 0.08, 0.92}

-- Constants for icon size limits
local MIN_ICON_SIZE = 10
local MAX_ICON_SIZE = 100

-- Constants for alpha limits
local MIN_ICON_ALPHA = 0.1
local MAX_ICON_ALPHA = 1.0

-- **************************************************************************
-- GLOBAL TRACKING VARIABLES
-- **************************************************************************

-- Main addon frame
local frame = CreateFrame("Frame")

-- Global tracking tables
local trackingFrames = {}      -- Combined table to track all frames (spells and items)
local needsUpdate = false      -- Flag to prevent unnecessary updates
local playerInCombat = false   -- Track player combat state

-- Item tracking cache
local itemMissingFromBags = {} -- Track which items are missing from bags
local itemLocations = {}       -- Quick lookup for item locations
local trackedItemLookup = {}   -- Quick lookup for tracked items
local itemNameCache = {}       -- Item name extraction cache to avoid repeated string operations

-- Performance tracking
local trackedSpellCount = 0
local trackedItemCount = 0

-- Time tracking
local lastUpdate = 0
local currentTime = 0
local bagUpdateThrottle = 0
local bagUpdatePending = false

-- Message colors
local COLOR_SUCCESS = {r = 0, g = 1, b = 0}
local COLOR_ERROR = {r = 1, g = 0, b = 0}
local COLOR_WARNING = {r = 1, g = 0.5, b = 0}
local COLOR_INFO = {r = 0, g = 1, b = 1}
local COLOR_TITLE = {r = 1, g = 1, b = 0}
local COLOR_HELP = {r = 1, g = 1, b = 1}

-- **************************************************************************
-- UTILITY FUNCTIONS
-- **************************************************************************

---
-- Deep copies a table
-- @param original The table to copy
-- @return A new table with all values copied
local function CopyTable(original)
    if type(original) ~= "table" then return original end
    
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

---
-- Splits a string by a separator
-- @param inputstr The string to split
-- @param sep The separator (default: space)
-- @return Multiple return values, one for each part
local function SplitString(inputstr, sep)
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

---
-- Clears all keys from a table
-- @param t The table to clear
-- @return The cleared table
local function WipeTable(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

---
-- Extracts item name from item link with caching
-- @param link The item link
-- @return The item name or nil if not found
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

---
-- Updates cached values that are frequently used
local function UpdateCachedValues()
    if CooldownTrackerDB and CooldownTrackerDB.config then
        CooldownTrackerDB.config.cooldownScale = (1 / 32) * CooldownTrackerDB.config.iconSize
    end
end

---
-- Prints a message to the chat frame with color
-- @param message The message to print
-- @param color Table with r, g, b values
local function PrintMessage(message, color)
    if not message then return end
    if not color then color = COLOR_INFO end
    
    DEFAULT_CHAT_FRAME:AddMessage(addonName..": "..message, color.r, color.g, color.b)
end

-- **************************************************************************
-- DATABASE MANAGEMENT
-- **************************************************************************

---
-- Initializes the database with default values if needed
-- Ensures all required fields exist in the database
local function InitializeDatabase()
    -- Create new database if it doesn't exist
    if not CooldownTrackerDB then
        CooldownTrackerDB = CopyTable(defaultDB)
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
        
        -- Ensure we have individual icon sizes table
        if not CooldownTrackerDB.individualIconSizes then
            CooldownTrackerDB.individualIconSizes = {}
        end
    end
    
    -- Cache frequently used values
    UpdateCachedValues()
end

-- **************************************************************************
-- SPELL MANAGEMENT
-- **************************************************************************

---
-- Finds spell information in the spellbook
-- @param spellName The name of the spell to find
-- @return Table with texture and offset, or nil if not found
local function FindSpellInfo(spellName)
    if not spellName or spellName == "" then return nil end
    
    local lowerSpellName = string.lower(spellName)
    
    -- Iterate through spellbook tabs
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        if offset and numSpells then
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
    end
    
    return nil
end

-- **************************************************************************
-- ITEM MANAGEMENT
-- **************************************************************************

---
-- Initializes the lookup table for tracked items
local function InitializeTrackedItemLookup()
    WipeTable(trackedItemLookup)
    local _, itemsToTrack = GetCooldownTrackerSettings()
    
    for itemName in pairs(itemsToTrack) do
        trackedItemLookup[itemName] = true
    end
end

---
-- Updates the visual state of an item based on whether it's missing from bags
-- @param itemName The name of the item
-- @param isMissing Boolean indicating if the item is missing
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

---
-- Updates the cooldown display for a specific item
-- @param itemName The name of the item
-- @param location Table with bag and slot information
local function UpdateItemCooldown(itemName, location)
    local frameData = trackingFrames[itemName]
    if not frameData or not location then return end
    
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

---
-- Verifies tracked items during combat (optimized for combat)
-- Only checks existing locations rather than scanning all bags
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

---
-- Performs a full scan of all bags to find tracked items
local function ScanBagsForItems()
    -- Clear current item location cache but preserve missing state
    local previouslyMissing = CopyTable(itemMissingFromBags)
    WipeTable(itemLocations)
    WipeTable(itemMissingFromBags)
    
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

---
-- Updates cooldowns for all tracked items with known locations
local function UpdateItemCooldowns()
    for itemName, locations in pairs(itemLocations) do
        if locations and table.getn(locations) > 0 then
            -- Take the first instance for cooldown info (all instances of same item share cooldown)
            local location = locations[1]
            UpdateItemCooldown(itemName, location)
        end
    end
end

-- **************************************************************************
-- UI AND FRAME CREATION
-- **************************************************************************

-- Function to get icon size for a specific frame
local function GetIconSize(name)
    -- Check if this icon has an individual size set
    if CooldownTrackerDB.individualIconSizes and CooldownTrackerDB.individualIconSizes[name] then
        return CooldownTrackerDB.individualIconSizes[name]
    end
    
    -- Otherwise return the global size
    return CooldownTrackerDB.config.iconSize
end

-- Calculate cooldown scale for a specific icon size
local function CalculateCooldownScale(iconSize)
    return (1 / 32) * iconSize
end

---
-- Creates a tracking frame for a spell or item
-- @param name The name of the spell or item
-- @param texture The texture to display
-- @param iconCount The position index for default positioning
-- @param isSpell Boolean indicating if this is a spell (true) or item (false)
-- @param spellOffset The spell offset in the spellbook (for spells only)
-- @return Table containing the frame data
local function CreateTrackingFrame(name, texture, iconCount, isSpell, spellOffset)
    if not name or not texture then
        PrintMessage("Cannot create tracking frame: missing name or texture", COLOR_ERROR)
        return nil
    end
    
    local config = CooldownTrackerDB.config
    
    -- Get size for this specific icon
    local iconSize = GetIconSize(name)

    -- Create main frame
    local frame = CreateFrame("Frame", addonName.."_"..name, UIParent)
    frame:SetWidth(iconSize)
    frame:SetHeight(iconSize)
    
    -- Add marker for CooldownTrackerTimers module
    frame.cooldownTrackerData = true
    
    -- Use saved position if available
    if CooldownTrackerDB.iconPositions and CooldownTrackerDB.iconPositions[name] then
        local pos = CooldownTrackerDB.iconPositions[name]
        frame:SetPoint(pos.anchor, UIParent, pos.anchor, pos.x, pos.y)
    else
        -- Default position - all icons stacked at the same point
        frame:SetPoint(config.iconAnchor, UIParent, config.iconAnchor, config.iconX, config.iconY)
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
    icon:SetTexCoord(unpack(TEXTURE_COORDINATES))

    -- Cooldown frame with enhanced positioning and scaling
    local cooldown = CreateFrame("Model", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)

    -- Compute scale based on icon's specific size
    local cooldownScale = CalculateCooldownScale(iconSize)
    cooldown:SetScale(cooldownScale)

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

-- **************************************************************************
-- COOLDOWN TRACKING FUNCTIONS
-- **************************************************************************

---
-- Updates all cooldowns for spells and items
-- Only performs updates when needsUpdate flag is set
local function UpdateAllCooldowns()
    if not needsUpdate then return end
    
    currentTime = GetTime()
    
    -- Update spell cooldowns
    for id, frameData in pairs(trackingFrames) do
        if frameData.isSpell and frameData.spellOffset then
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

---
-- OnUpdate handler with configurable update interval
-- Throttles updates based on the configured interval
local function OnUpdate()
    currentTime = GetTime()
    
    -- Check if enough time has passed according to config
    if currentTime - lastUpdate >= CooldownTrackerDB.config.updateInterval then
        UpdateAllCooldowns()
        lastUpdate = currentTime
    end
end

-- **************************************************************************
-- TIMER MODULE INTEGRATION
-- **************************************************************************

--- Loads the CooldownTrackerTimers module
local function LoadTimersModule()
    -- In WoW 1.12, modules are typically loaded via the TOC file
    -- and their functions are accessed through global variables
    if CooldownTrackerTimers then
        CooldownTrackerTimers:Initialize()
    end
end

-- **************************************************************************
-- INITIALIZATION FUNCTIONS
-- **************************************************************************

---
-- Initializes tracking frames for items
-- @param startIconCount The starting icon count for positioning
-- @return The updated icon count
local function InitializeItemFrames(startIconCount)
    if not startIconCount or type(startIconCount) ~= "number" then
        startIconCount = 0
    end
    
    local iconCount = startIconCount
    
    -- Get the itemsToTrack table from the settings file
    local _, itemsToTrack = GetCooldownTrackerSettings()
    
    -- Create frames for items with icons
    for itemName, iconTexture in pairs(itemsToTrack) do
        if not trackingFrames[itemName] then
            iconCount = iconCount + 1
            
            -- Create tracking frame for this item
            local frameData = CreateTrackingFrame(
                itemName,
                iconTexture,
                iconCount,
                false,  -- Not a spell
                nil     -- No spell offset
            )
            
            if frameData then
                trackingFrames[itemName] = frameData
                trackedItemCount = trackedItemCount + 1
            end
        end
    end
    
    return iconCount
end

---
-- Initializes all tracking icons for spells and items
-- Updates existing frames and creates new ones as needed
-- @return The total number of icons created/updated
local function InitializeIcons()
    -- Reset counters but preserve existing frames
    trackedSpellCount = 0
    trackedItemCount = 0
    
    -- Get highest current icon count for positioning new icons
    local iconCount = 0
    for _ in pairs(trackingFrames) do
        iconCount = iconCount + 1
    end
    
    -- Track which frames we've processed to detect and remove orphaned frames
    local processedFrames = {}
    
    -- Get spell and item tables from settings file
    local spellsToTrack, itemsToTrack = GetCooldownTrackerSettings()
    
    -- 1. Initialize/Update Spell Icons
    for i, spellName in ipairs(spellsToTrack) do
        if spellName and spellName ~= "" then
            processedFrames[spellName] = true
            
            -- Update or create spell info if needed
            local spellInfo
            if not CooldownTrackerDB.spellCache[spellName] then
                -- Find and cache new spell
                spellInfo = FindSpellInfo(spellName)
                if spellInfo then
                    CooldownTrackerDB.spellCache[spellName] = spellInfo
                end
            else
                -- Use existing cached info
                spellInfo = CooldownTrackerDB.spellCache[spellName]
            end
            
            if spellInfo and spellInfo.texture then
                if trackingFrames[spellName] then
                    -- Update existing frame if needed
                    local frameData = trackingFrames[spellName]
                    
                    -- Update spell offset if it changed
                    if frameData.spellOffset ~= spellInfo.offset then
                        frameData.spellOffset = spellInfo.offset
                    end
                    
                    -- Update texture if it changed
                    if frameData.icon:GetTexture() ~= spellInfo.texture then
                        frameData.icon:SetTexture(spellInfo.texture)
                    end
                else
                    -- Create new frame for this spell
                    iconCount = iconCount + 1
                    local frameData = CreateTrackingFrame(
                        spellName,
                        spellInfo.texture,
                        iconCount,
                        true,  -- isSpell
                        spellInfo.offset
                    )
                    
                    if frameData then
                        trackingFrames[spellName] = frameData
                    end
                end
                
                trackedSpellCount = trackedSpellCount + 1
            end
        end
    end
    
    -- 2. Initialize Item Icons and Lookup Table
    InitializeTrackedItemLookup()
    
    -- Process all items
    for itemName, iconTexture in pairs(itemsToTrack) do
        if itemName and itemName ~= "" then
            processedFrames[itemName] = true
            
            if not trackingFrames[itemName] then
                -- Create new frame for this item
                iconCount = iconCount + 1
                local frameData = CreateTrackingFrame(
                    itemName,
                    iconTexture,
                    iconCount,
                    false,  -- Not a spell
                    nil     -- No spell offset
                )
                
                if frameData then
                    trackingFrames[itemName] = frameData
                    trackedItemCount = trackedItemCount + 1
                end
            else
                trackedItemCount = trackedItemCount + 1
            end
        end
    end
    
    -- Remove any orphaned frames (items or spells that were removed from settings)
    for name, frameData in pairs(trackingFrames) do
        if not processedFrames[name] then
            -- This frame is no longer in the settings, so remove it
            frameData.frame:Hide()
            frameData.frame:SetParent(nil)
            trackingFrames[name] = nil
        end
    end
    
    return iconCount
end

-- **************************************************************************
-- COMMAND HANDLING
-- **************************************************************************

---
-- Finds an item in the player's bags by name
-- @param itemName The name of the item to find
-- @return Table with item information or nil if not found
local function FindItemInBags(itemName)
    if not itemName or itemName == "" then return nil end
    
    local lowerItemName = string.lower(itemName)
    
    -- Scan all bags
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        
        for slot = 1, numSlots do
            local itemLink = GetContainerItemLink(bag, slot)
            
            if itemLink then
                -- Extract item name from link
                local name = GetItemNameFromLink(itemLink)
                
                if name and string.lower(name) == lowerItemName then
                    -- Found the item, get texture
                    local texture = GetContainerItemInfo(bag, slot)
                    
                    return {
                        name = name, -- Return actual case from the item
                        texture = texture,
                        bag = bag,
                        slot = slot
                    }
                end
            end
        end
    end
    
    return nil
end

---
-- Adds a spell or item to track
-- @param name The name of the spell or item to add
local function AddCommand(name)
    if not name or name == "" then
        PrintMessage("Invalid name. Use /cdt add <spell or item name>", COLOR_ERROR)
        return
    end
    
    -- Get the list of spells and items being tracked
    local spellsToTrack, itemsToTrack = GetCooldownTrackerSettings()
    
    -- 1. First check if we're already tracking this spell or item
    -- Check spells (using lowercase comparison for case-insensitive matching)
    local lowerName = string.lower(name)
    local alreadyTrackingSpell = false
    for _, spellName in ipairs(spellsToTrack) do
        if string.lower(spellName) == lowerName then
            alreadyTrackingSpell = true
            PrintMessage("Already tracking spell: "..spellName, COLOR_WARNING)
            return
        end
    end
    
    -- Check items (using lowercase comparison for case-insensitive matching)
    for itemName, _ in pairs(itemsToTrack) do
        if string.lower(itemName) == lowerName then
            PrintMessage("Already tracking item: "..itemName, COLOR_WARNING)
            return
        end
    end
    
    -- 2. Try to find it as a spell
    local spellInfo = FindSpellInfo(name)
    
    if spellInfo then
        -- Add to spells list
        table.insert(spellsToTrack, name)
        CooldownTrackerDB.spellCache[name] = spellInfo
        
        -- Create the tracking frame
        local iconCount = 0
        for _ in pairs(trackingFrames) do iconCount = iconCount + 1 end
        local frameData = CreateTrackingFrame(
            name,
            spellInfo.texture,
            iconCount + 1,
            true,  -- isSpell
            spellInfo.offset
        )
        
        if frameData then
            trackingFrames[name] = frameData
            trackedSpellCount = trackedSpellCount + 1
            needsUpdate = true
            
            PrintMessage("Added spell "..name, COLOR_SUCCESS)
        end
        return
    end
    
    -- 3. Try to find it as an item
    local itemInfo = FindItemInBags(name)
    
    if itemInfo then
        -- Add to items list
        itemsToTrack[itemInfo.name] = itemInfo.texture
        
        -- Update tracked item lookup
        trackedItemLookup[itemInfo.name] = true
        
        -- Create the tracking frame
        local iconCount = 0
        for _ in pairs(trackingFrames) do iconCount = iconCount + 1 end
        local frameData = CreateTrackingFrame(
            itemInfo.name,
            itemInfo.texture,
            iconCount + 1,
            false,  -- Not a spell
            nil     -- No spell offset
        )
        
        if frameData then
            trackingFrames[itemInfo.name] = frameData
            trackedItemCount = trackedItemCount + 1
            
            -- Scan bags to find all instances of this item
            ScanBagsForItems()
            
            PrintMessage("Added item "..itemInfo.name, COLOR_SUCCESS)
        end
        return
    end
    
    -- 4. Not found as either spell or item
    PrintMessage("Could not find '"..name.."' in your spellbook or bags.", COLOR_ERROR)
end

---
-- Removes a spell or item from tracking
-- @param name The name of the spell or item to remove
local function RemoveCommand(name)
    if not name or name == "" then
        PrintMessage("Invalid name. Use /cdt remove <spell or item name>", COLOR_ERROR)
        return
    end
    
    -- Get the list of spells and items being tracked
    local spellsToTrack, itemsToTrack = GetCooldownTrackerSettings()
    
    -- 1. Try to remove from spell list
    local lowerName = string.lower(name)
    local spellFound = false
    local spellIndex = nil
    local actualSpellName = nil
    
    for i, spellName in ipairs(spellsToTrack) do
        if spellName and string.lower(spellName) == lowerName then
            spellIndex = i
            spellFound = true
            actualSpellName = spellName
            break
        end
    end
    
    if spellFound then
        -- Remove the spell from the list
        table.remove(spellsToTrack, spellIndex)
        
        -- Remove from DB cache if exists
        if CooldownTrackerDB.spellCache[actualSpellName] then
            CooldownTrackerDB.spellCache[actualSpellName] = nil
        end
        
        -- Hide and remove the tracking frame
        if trackingFrames[actualSpellName] then
            trackingFrames[actualSpellName].frame:Hide()
            trackingFrames[actualSpellName].frame:SetParent(nil)
            trackingFrames[actualSpellName] = nil
        end
        
        -- Update counter
        if trackedSpellCount > 0 then
            trackedSpellCount = trackedSpellCount - 1
        end
        
        PrintMessage("Removed spell "..actualSpellName, COLOR_SUCCESS)
        return
    end
    
    -- 2. Try to remove from item list
    local itemFound = false
    local actualItemName = nil
    
    for itemName, _ in pairs(itemsToTrack) do
        if itemName and string.lower(itemName) == lowerName then
            itemFound = true
            actualItemName = itemName
            break
        end
    end
    
    if itemFound then
        -- Remove the item from the table
        itemsToTrack[actualItemName] = nil
        
        -- Remove from tracked item lookup
        trackedItemLookup[actualItemName] = nil
        
        -- Hide and remove the tracking frame
        if trackingFrames[actualItemName] then
            trackingFrames[actualItemName].frame:Hide()
            trackingFrames[actualItemName].frame:SetParent(nil)
            trackingFrames[actualItemName] = nil
        end
        
        -- Update counter
        if trackedItemCount > 0 then
            trackedItemCount = trackedItemCount - 1
        end
        
        PrintMessage("Removed item "..actualItemName, COLOR_SUCCESS)
        return
    end
    
    -- 3. Not found in either list
    PrintMessage("'"..name.."' not found in tracked spells or items.", COLOR_ERROR)
end

---
-- Adds an item to track with default settings
-- @param itemName The name of the item to track
-- @return Boolean indicating success or failure
local function AddItemToTrack(itemName)
    if not itemName or itemName == "" then
        return false
    end
    
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
        local frameData = CreateTrackingFrame(
            itemName,
            itemsToTrack[itemName],
            iconCount + 1,
            false,  -- Not a spell
            nil     -- No spell offset
        )
        
        if frameData then
            trackingFrames[itemName] = frameData
            trackedItemCount = trackedItemCount + 1
        else
            return false
        end
    end
    
    -- Rescan bags to find this item
    ScanBagsForItems()
    
    -- Return success/failure
    return not itemMissingFromBags[itemName]
end

---
-- Resizes a specific icon to a new size
-- @param frameData The frame data for the icon
-- @param newSize The new size to set
-- @return Boolean indicating success or failure
local function ResizeIcon(frameData, newSize)
    if not frameData or not newSize or newSize < MIN_ICON_SIZE or newSize > MAX_ICON_SIZE then
        return false
    end
    
    -- Set the width and height
    frameData.frame:SetWidth(newSize)
    frameData.frame:SetHeight(newSize)
    
    -- Calculate and apply the new cooldown scale
    local cooldownScale = CalculateCooldownScale(newSize)
    frameData.cooldown:SetScale(cooldownScale)
    
    -- Reposition the cooldown
    frameData.cooldown:ClearAllPoints()
    frameData.cooldown:SetPoint("TOPLEFT", frameData.frame, "TOPLEFT")
    frameData.cooldown:SetPoint("BOTTOMRIGHT", frameData.frame, "BOTTOMRIGHT")
    
    -- Save the individual size
    CooldownTrackerDB.individualIconSizes[frameData.name] = newSize
    
    return true
end

---
-- Handles slash commands for the addon
-- @param msg The message after the slash command
local function SlashCommand(msg)
    if not msg or msg == "" then
        DEFAULT_CHAT_FRAME:AddMessage(addonName.." Commands:", COLOR_TITLE.r, COLOR_TITLE.g, COLOR_TITLE.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt lock - Toggle frame locking", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt size <number> - Set all icons size (10-100)", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt size <spell or item name> <number> - Set specific icon size (10-100)", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt alpha <number> - Set icon transparency (0.1-1.0)", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt add <spell or item name> - Add a spell or item to track", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt remove <spell or item name> - Remove a spell or item from tracking", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt list - List all spells and items currently being tracked", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt timers - Toggle timer text display on cooldown icons", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        return
    end
    
    -- Get all arguments from the message
    local parts = {}
    local i = 1
    for str in string.gfind(msg, "([^%s]+)") do
        parts[i] = str
        i = i + 1
    end
    
    local cmd = parts[1]
    local config = CooldownTrackerDB.config
    
    if cmd == "lock" then
        config.locked = not config.locked
        
        -- Update all frames at once
        for _, frameData in pairs(trackingFrames) do
            frameData.frame:EnableMouse(not config.locked)
        end
        
        PrintMessage("Frames "..(config.locked and "locked" or "unlocked"), config.locked and COLOR_SUCCESS or COLOR_WARNING)
    
    elseif cmd == "size" then
        -- Individual icon size: /cdt size <name> <size>
        if parts[2] and parts[3] then
            -- Check if the last part is a number (size value)
            local lastPart = parts[table.getn(parts)]
            local sizeValue = tonumber(lastPart)
            
            if not sizeValue or sizeValue < MIN_ICON_SIZE or sizeValue > MAX_ICON_SIZE then
                PrintMessage("Invalid size. Use a number between "..MIN_ICON_SIZE.." and "..MAX_ICON_SIZE, COLOR_ERROR)
                return
            end
            
            -- Combine all parts between the command and the size as the icon name
            local iconName = parts[2]
            for i = 3, table.getn(parts) - 1 do
                iconName = iconName .. " " .. parts[i]
            end
            
            -- Find the frame data for this icon
            local found = false
            for name, frameData in pairs(trackingFrames) do
                if string.lower(name) == string.lower(iconName) then
                    found = true
                    if ResizeIcon(frameData, sizeValue) then
                        PrintMessage("Set "..name.." size to "..sizeValue, COLOR_INFO)
                    else
                        PrintMessage("Failed to resize "..name, COLOR_ERROR)
                    end
                    break
                end
            end
            
            if not found then
                PrintMessage("Icon '"..iconName.."' not found", COLOR_ERROR)
            end
        
        -- Global resize: /cdt size <size>
        elseif parts[2] then
            local sizeValue = tonumber(parts[2])
            
            if not sizeValue or sizeValue < MIN_ICON_SIZE or sizeValue > MAX_ICON_SIZE then
                PrintMessage("Invalid size. Use a number between "..MIN_ICON_SIZE.." and "..MAX_ICON_SIZE, COLOR_ERROR)
                return
            end
            
            config.iconSize = sizeValue
            UpdateCachedValues() -- Update cached values
            
            -- Resize all frames that don't have individual sizes
            for name, frameData in pairs(trackingFrames) do
                if not CooldownTrackerDB.individualIconSizes[name] then
                    frameData.frame:SetWidth(sizeValue)
                    frameData.frame:SetHeight(sizeValue)
                    
                    -- Adjust cooldown frame scaling and positioning
                    frameData.cooldown:SetScale(config.cooldownScale)
                    
                    frameData.cooldown:ClearAllPoints()
                    frameData.cooldown:SetPoint("TOPLEFT", frameData.frame, "TOPLEFT")
                    frameData.cooldown:SetPoint("BOTTOMRIGHT", frameData.frame, "BOTTOMRIGHT")
                end
            end
            
            PrintMessage("Default icon size set to "..sizeValue, COLOR_INFO)
        else
            PrintMessage("Invalid size command. Use /cdt size <number> or /cdt size <name> <number>", COLOR_ERROR)
        end
    
    elseif cmd == "alpha" and parts[2] then
        local alphaValue = tonumber(parts[2])
        if alphaValue and alphaValue >= MIN_ICON_ALPHA and alphaValue <= MAX_ICON_ALPHA then
            config.iconAlpha = alphaValue
            
            -- Update all frames at once
            for _, frameData in pairs(trackingFrames) do
                frameData.frame:SetAlpha(alphaValue)
                frameData.originalAlpha = alphaValue
            end
            
            PrintMessage("Icon alpha set to "..alphaValue, COLOR_INFO)
        else
            PrintMessage("Invalid alpha. Use /cdt alpha <number> between "..MIN_ICON_ALPHA.." and "..MAX_ICON_ALPHA, COLOR_ERROR)
        end
    
    elseif cmd == "add" and parts[2] then
        -- Combine all remaining parts for the name
        local nameToAdd = parts[2]
        for i = 3, table.getn(parts) do
            nameToAdd = nameToAdd .. " " .. parts[i]
        end
        
        -- Call the Add command handler
        AddCommand(nameToAdd)
    
    elseif cmd == "remove" and parts[2] then
        -- Combine all remaining parts for the name
        local nameToRemove = parts[2]
        for i = 3, table.getn(parts) do
            nameToRemove = nameToRemove .. " " .. parts[i]
        end
        
        -- Call the Remove command handler
        RemoveCommand(nameToRemove)
    
    elseif cmd == "timers" then
        if CooldownTrackerTimers then
            local enabled = CooldownTrackerTimers:ToggleTimerText()
            PrintMessage("Timer text display " .. (enabled and "enabled" or "disabled"), enabled and COLOR_SUCCESS or COLOR_INFO)
        else
            PrintMessage("Timer module not loaded", COLOR_ERROR)
        end
    
    elseif cmd == "list" then
        -- Get the list of spells and items being tracked
        local spellsToTrack, itemsToTrack = GetCooldownTrackerSettings()
        
        -- Print header
        DEFAULT_CHAT_FRAME:AddMessage(addonName.." - Tracked Spells and Items:", COLOR_TITLE.r, COLOR_TITLE.g, COLOR_TITLE.b)
        
        -- Print spells
        if table.getn(spellsToTrack) > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("Spells:", COLOR_INFO.r, COLOR_INFO.g, COLOR_INFO.b)
            for i, spellName in ipairs(spellsToTrack) do
                DEFAULT_CHAT_FRAME:AddMessage("  "..i..". "..spellName, COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("No spells being tracked.", COLOR_WARNING.r, COLOR_WARNING.g, COLOR_WARNING.b)
        end
        
        -- Print items
        local itemCount = 0
        for _ in pairs(itemsToTrack) do itemCount = itemCount + 1 end
        
        if itemCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("Items:", COLOR_INFO.r, COLOR_INFO.g, COLOR_INFO.b)
            local index = 1
            for itemName, _ in pairs(itemsToTrack) do
                local status = itemMissingFromBags[itemName] and " (missing)" or ""
                DEFAULT_CHAT_FRAME:AddMessage("  "..index..". "..itemName..status, COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
                index = index + 1
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("No items being tracked.", COLOR_WARNING.r, COLOR_WARNING.g, COLOR_WARNING.b)
        end
        
        -- Print summary
        DEFAULT_CHAT_FRAME:AddMessage("Total: "..trackedSpellCount.." spell(s) and "..trackedItemCount.." item(s)", COLOR_SUCCESS.r, COLOR_SUCCESS.g, COLOR_SUCCESS.b)
    
    else
        -- Show help message for any unrecognized command
        DEFAULT_CHAT_FRAME:AddMessage(addonName.." Commands:", COLOR_TITLE.r, COLOR_TITLE.g, COLOR_TITLE.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt lock - Toggle frame locking", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt size <number> - Set all icons size (10-100)", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt size <spell or item name> <number> - Set specific icon size (10-100)", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt alpha <number> - Set icon transparency (0.1-1.0)", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt add <spell or item name> - Add a spell or item to track", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
        DEFAULT_CHAT_FRAME:AddMessage("/cdt remove <spell or item name> - Remove a spell or item from tracking", COLOR_HELP.r, COLOR_HELP.g, COLOR_HELP.b)
    end
end

-- **************************************************************************
-- EVENT HANDLERS
-- **************************************************************************

-- Combat state tracking functions
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

-- BAG_UPDATE handler with combat awareness
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

---
-- Main event handler for all registered events
local function OnEvent()
    if event == "VARIABLES_LOADED" then
        -- Initialize the database
        InitializeDatabase()
        
        -- Load the timers module
        LoadTimersModule()
        
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
        PrintMessage("Loaded. Tracking "..trackedSpellCount.." spell(s) and "..trackedItemCount.." item(s).", COLOR_SUCCESS)
        
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

-- **************************************************************************
-- INITIALIZATION AND SETUP
-- **************************************************************************

-- Register events
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:SetScript("OnEvent", OnEvent)

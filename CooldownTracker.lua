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
    
    spellsToTrack = {
        "Earth Shock",
        "Chain Lightning",
        "Fire Nova Totem",
        "Earthbind Totem",
        "Elemental Mastery",
        "Grounding Totem",
        "Blood Fury",
    },
    
    -- Table for items to track by item name with hardcoded icon paths using simplified format
    itemsToTrack = {
        ["Thorium Grenade"] = "Interface\\Icons\\INV_Misc_Bomb_08",
        ["Goblin Sapper Charge"] = "Interface\\Icons\\Spell_Fire_SelfDestruct",
		["Nordanaar Herbal Tea"] = "Interface\\Icons\\INV_Drink_Milk_05",
		["Limited Invulnerability Potion"] = "Interface\\Icons\\INV_Potion_62",
    },
    
    -- This will store spell info found in spellbook
    spellCache = {}
}

-- Global tracking tables
local trackingFrames = {} -- Combined table to track all frames (spells and items)
local needsUpdate = false -- Flag to prevent unnecessary updates
local frame = CreateFrame("Frame") -- Our main addon frame

-- New item tracking cache
local itemCache = {} -- Stores bag and slot info for tracked items
local itemMissingFromBags = {} -- Track which items are missing from bags

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
        
        -- Convert complex format to simple format if needed
        if type(CooldownTrackerDB.itemsToTrack) == "table" then
            for itemName, value in pairs(CooldownTrackerDB.itemsToTrack) do
                if type(value) == "table" and value.icon then
                    -- Convert from complex format to simple format
                    CooldownTrackerDB.itemsToTrack[itemName] = value.icon
                end
            end
        end
        
        -- Remove scale setting if it exists (as it's redundant with size)
        if CooldownTrackerDB.config.iconScale then
            CooldownTrackerDB.config.iconScale = nil
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

-- Item name extraction cache to avoid repeated string operations
local itemNameCache = {}

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

-- Initialize item tracking frames using the simplified format
local function InitializeItemFrames(startIconCount)
    local iconCount = startIconCount
    
    -- Create frames for items with icons
    for itemName, iconTexture in pairs(CooldownTrackerDB.itemsToTrack) do
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

-- Function to scan bags and find tracked items - optimized to reduce iterations
local function ScanBagsForItems()
    -- Clear current item cache but remember which items were missing
    local previouslyMissing = {}
    for itemName in pairs(itemMissingFromBags) do
        previouslyMissing[itemName] = true
    end

    wipe(itemCache)
    wipe(itemMissingFromBags)

    -- Pre-create a lookup table of tracked items for faster checks
    local trackedItemLookup = {}
    for itemName in pairs(CooldownTrackerDB.itemsToTrack) do
        trackedItemLookup[itemName] = true
    end

    -- Scan all bags
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)

        for slot = 1, numSlots do
            local itemLink = GetContainerItemLink(bag, slot)

            if itemLink then
                -- Extract item name from link
                local itemName = GetItemNameFromLink(itemLink)

                -- Check if this is an item we're tracking using the lookup table
                if itemName and trackedItemLookup[itemName] then
                    -- Add to cache
                    if not itemCache[itemName] then
                        itemCache[itemName] = {}
                    end

                    -- Store location
                    table.insert(itemCache[itemName], {bag = bag, slot = slot})
                end
            end
        end
    end

  -- Check which tracked items are missing from bags
    for itemName in pairs(trackedItemLookup) do
        local frameData = trackingFrames[itemName]
        if not itemCache[itemName] or table.getn(itemCache[itemName]) == 0 then
            itemMissingFromBags[itemName] = true

            -- Update the frame only if it's a new missing item
            if frameData and not frameData.missingFromBags then
                frameData.missingFromBags = true
                frameData.icon:SetAlpha(0.28)  -- Set alpha to 30% (1 - 0.7 = 0.3)
            end
        elseif previouslyMissing[itemName] then
            -- Item was missing before but now found - update frame
            if frameData then
                frameData.missingFromBags = false
                frameData.icon:SetAlpha(frameData.originalAlpha) -- Restore original alpha
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
    
    -- 1. Initialize Spell Icons
    -- Pre-process spell names to lowercase for faster comparison later
    local spellsToTrackLower = {}
    for i, spellName in ipairs(CooldownTrackerDB.spellsToTrack) do
        spellsToTrackLower[i] = string.lower(spellName)
    end
    
    for i, spellName in ipairs(CooldownTrackerDB.spellsToTrack) do
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
    
    -- 2. Initialize Item Icons
    iconCount = InitializeItemFrames(iconCount)
    
    return iconCount
end

-- Optimization to avoid repeated GetTime() calls
local currentTime = 0

-- Function to update item cooldowns - optimized but fixed to handle all instances
local function UpdateItemCooldowns()
    -- Update cooldowns for each tracked item
    for itemName, frameData in pairs(trackingFrames) do
        if not frameData.isSpell then
            local locations = itemCache[itemName]
            local hasItem = locations and table.getn(locations) > 0
            
            if hasItem then
                -- Get cooldown info from the first instance
                local bag, slot = locations[1].bag, locations[1].slot
                local startTime, duration, enable = GetContainerItemCooldown(bag, slot)
                
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
            elseif frameData.active then
                -- Item is missing but was on cooldown - maintain cooldown display
                -- We don't need to do anything as the cooldown animation continues
            end
        end
    end
end

-- Efficient function to update all cooldowns at once - optimized to reduce redundant processing
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
    -- Skip if already tracking
    if CooldownTrackerDB.itemsToTrack[itemName] then
        return true
    end
    
    -- Add to database with default icon
    CooldownTrackerDB.itemsToTrack[itemName] = "Interface\\Icons\\INV_Misc_QuestionMark" -- Default icon
    
    -- Initialize frame for this item
    local iconCount = 0
    for _ in pairs(trackingFrames) do 
        iconCount = iconCount + 1 
    end
    
    -- Create tracking frame if not exists
    if not trackingFrames[itemName] then
        trackingFrames[itemName] = CreateTrackingFrame(
            itemName,
            CooldownTrackerDB.itemsToTrack[itemName],
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

-- Throttled event handler for BAG_UPDATE to prevent excessive scanning
local bagUpdateThrottle = 0
local bagUpdatePending = false

local function OnBagUpdate()
    bagUpdatePending = true
    
    -- Only scan bags if we haven't done so recently
    if GetTime() - bagUpdateThrottle > 0.5 then
        ScanBagsForItems()
        bagUpdateThrottle = GetTime()
        bagUpdatePending = false
    end
end

-- Event handler for all events
local function OnEvent()
    if event == "VARIABLES_LOADED" then
        -- Initialize the database
        InitDB()
        
        -- Register for PLAYER_ENTERING_WORLD to ensure spellbook is loaded
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        
    elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
        -- Initialize all icons after spellbook is loaded
        local iconCount = 0
        wipe(trackingFrames)
        trackedSpellCount = 0
        trackedItemCount = 0
        
        -- 1. Initialize Spell Icons
        for i, spellName in ipairs(CooldownTrackerDB.spellsToTrack) do
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
        
        -- 2. Initialize Item Icons
        iconCount = InitializeItemFrames(iconCount)
        
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
        
        -- Unregister these events to avoid repeated initialization
        if event == "PLAYER_ENTERING_WORLD" then
            frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            frame:RegisterEvent("SPELLS_CHANGED") -- Register for spell changes
        end
        
    -- Rest of the event handlers remain the same
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Mark that we need to update cooldowns
        needsUpdate = true
    
    elseif event == "BAG_UPDATE" then
        -- Throttled bag update handling
        OnBagUpdate()
    
    elseif event == "BAG_UPDATE_COOLDOWN" then
        -- Item cooldowns changed, mark for update
        needsUpdate = true
        
        -- If we have a pending bag update, process it now
        if bagUpdatePending then
            ScanBagsForItems()
            bagUpdatePending = false
            bagUpdateThrottle = GetTime()
        end
    end
end

-- Register events
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:SetScript("OnEvent", OnEvent)
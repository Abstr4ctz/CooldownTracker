--[[
    CooldownTrackerTimers.lua
    
    Module for CooldownTracker that adds text display to cooldown icons.
    
    Features:
    - Adds remaining time text to cooldown icons
    - Configurable via slash command (/cdt timers)
    - Color-coded time display based on remaining time
    
    Version: 1.0
    Author: Abstractz
    Last updated: 2025-03-15
]]

-- Module namespace
CooldownTrackerTimers = {}

-- **************************************************************************
-- CONSTANTS AND DEFAULT VALUES
-- **************************************************************************

-- Text display settings
local COOLDOWN_TEXT_FONT         = "Fonts\\FRIZQT__.TTF" -- Font to be used for cooldown text
local COOLDOWN_TEXT_SIZE         = 12                    -- Font size for cooldown text
local COOLDOWN_TEXT_FLAGS        = "OUTLINE"             -- Font flags for cooldown text
local COOLDOWN_TEXT_MIN_DURATION = 2                     -- Minimum cooldown duration in seconds for text to be displayed

-- **************************************************************************
-- HELPER FUNCTIONS
-- **************************************************************************

--- Formats cooldown time in seconds into a human-readable string
local function formatCooldownTime(seconds)
    if seconds <= 0 then
        return ""
    end
    
    local color = "|cffffffff"
    
    if seconds < 5 then
        color = "|cffff5555"  -- red
    elseif seconds < 10 then
        color = "|cffffff55"  -- yellow
    end
    
    if seconds < 60 then
        return color .. ceil(seconds)
    elseif seconds < 3600 then
        return color .. ceil(seconds/60) .. "m"
    else
        return color .. ceil(seconds/60/60) .. "h"
    end
end

--- Creates cooldown text display for a cooldown frame
local function createCooldownText(cooldown)
    -- Skip if not enabled
    if not CooldownTrackerDB.config.enableTimerText then
        return
    end
    
    -- Skip if not a CooldownTracker cooldown frame
    local parent = cooldown:GetParent()
    if not parent or not parent.cooldownTrackerData then
        return
    end
    
    local frameName = "CooldownTracker_CooldownText_" .. tostring(cooldown)
    local textFrame = CreateFrame("Frame", frameName, cooldown)
    textFrame:SetAllPoints(cooldown)
    textFrame:SetFrameLevel(cooldown:GetFrameLevel() + 5)

    local fontString = textFrame:CreateFontString(frameName .. "_FontString", "OVERLAY")
    fontString:SetFont(COOLDOWN_TEXT_FONT, COOLDOWN_TEXT_SIZE, COOLDOWN_TEXT_FLAGS)
    fontString:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    
    textFrame.text = fontString
    textFrame:Hide()
    
    -- Set up the OnUpdate script for dynamic text updates
    textFrame:SetScript("OnUpdate", function()
        if not this.tick then this.tick = GetTime() + 0.1 end
        if this.tick > GetTime() then return end
        this.tick = GetTime() + 0.1

        if this.start < GetTime() then
            -- Normal time calculation (no rollover)
            local remaining = this.duration - (GetTime() - this.start)
            if remaining > 0 then
                this.text:SetText(formatCooldownTime(remaining))
            else
                this:Hide()
            end
        else
            -- Handle 32-bit timestamp rollover issue
            local currentTime = time()
            local startupTime = currentTime - GetTime()
            -- Calculate the "wrapped" time: ((2^32) - (start * 1000)) / 1000
            local cdTime = (2^32) / 1000 - this.start
            local cdStartTime = startupTime - cdTime
            local cdEndTime = cdStartTime + this.duration
            local remaining = cdEndTime - currentTime

            if remaining > 0 then
                this.text:SetText(formatCooldownTime(remaining))
            else
                this:Hide()
            end
        end
    end)
    
    return textFrame
end

--- Updates cooldown text display
local function updateCooldownText(cooldown, start, duration, enable)
    -- Skip if not enabled
    if not CooldownTrackerDB.config.enableTimerText then
        return
    end
    
    if not cooldown.cooldownText then
        cooldown.cooldownText = createCooldownText(cooldown)
        if not cooldown.cooldownText then return end
    end
    
    if not duration or duration < COOLDOWN_TEXT_MIN_DURATION then
        if cooldown.cooldownText then
            cooldown.cooldownText:Hide()
        end
        return
    end
    
    if start > 0 and duration > 0 and (not enable or enable > 0) then
        cooldown.cooldownText:Show()
        cooldown.cooldownText.start = start
        cooldown.cooldownText.duration = duration
    else
        cooldown.cooldownText:Hide()
    end
end

-- **************************************************************************
-- HOOK IMPLEMENTATION
-- **************************************************************************

--- Custom CooldownFrame_SetTimer hook for adding text display
local function cooldownTracker_CooldownFrame_SetTimer(cooldown, start, duration, enable)
    -- Only apply text to CooldownTracker cooldown frames
    local parent = cooldown:GetParent()
    if not parent or not parent.cooldownTrackerData then
        return
    end
    
    updateCooldownText(cooldown, start, duration, enable)
end

-- Hook the original CooldownFrame_SetTimer function
local function InitializeHook()
    if not CooldownTrackerTimers.originalCooldownFrame_SetTimer then
        CooldownTrackerTimers.originalCooldownFrame_SetTimer = CooldownFrame_SetTimer
        
        CooldownFrame_SetTimer = function(cooldown, start, duration, enable)
            CooldownTrackerTimers.originalCooldownFrame_SetTimer(cooldown, start, duration, enable)
            if CooldownTrackerDB.config.enableTimerText then
                cooldownTracker_CooldownFrame_SetTimer(cooldown, start, duration, enable)
            end
        end
    end
end

-- **************************************************************************
-- INITIALIZATION AND PUBLIC FUNCTIONS
-- **************************************************************************

--- Initializes the timer module
function CooldownTrackerTimers:Initialize()
    -- Add the enableTimerText option to the config if it doesn't exist
    if CooldownTrackerDB.config.enableTimerText == nil then
        CooldownTrackerDB.config.enableTimerText = false
    end
    
    -- Initialize the hook
    InitializeHook()
    
    -- Return success
    return true
end

--- Toggles the timer text display
function CooldownTrackerTimers:ToggleTimerText()
    CooldownTrackerDB.config.enableTimerText = not CooldownTrackerDB.config.enableTimerText
    return CooldownTrackerDB.config.enableTimerText
end

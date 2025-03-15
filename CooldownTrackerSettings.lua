--[[
    CooldownTrackerSettings.lua
    
    Configuration file for CooldownTracker addon for World of Warcraft (1.12).
    
    This file contains default settings for:
    - Spells to track cooldowns for
    - Items to track cooldowns for with their icon paths
    
    Add or remove entries as needed to customize which cooldowns you want to track.
    
    Version: 1.0
    Author: Abstractz
    Last updated: 2025-03-15
]]

-- **************************************************************************
-- DEFAULT SETTINGS
-- **************************************************************************

-- Create defaults table if not already loaded
if not CooldownTrackerSettings then
    CooldownTrackerSettings = {
        -- Array of spell names to track (default set for Shaman)
        spellsToTrack = {
            -- Shaman abilities
            "Earth Shock",
            "Chain Lightning",
            "Fire Nova Totem",
            "Earthbind Totem",
            "Elemental Mastery",
            "Grounding Totem",
            
            -- Racial abilities
            "Blood Fury",
        },
        
        -- Table for items to track by item name with hardcoded icon paths
        itemsToTrack = {
            -- Engineering items
            ["Thorium Grenade"] = "Interface\\Icons\\INV_Misc_Bomb_08",
            ["Goblin Sapper Charge"] = "Interface\\Icons\\Spell_Fire_SelfDestruct",
            
            -- Consumables
            ["Nordanaar Herbal Tea"] = "Interface\\Icons\\INV_Drink_Milk_05",
            ["Limited Invulnerability Potion"] = "Interface\\Icons\\INV_Potion_62",
        }
    }
end

-- **************************************************************************
-- ACCESSOR FUNCTIONS
-- **************************************************************************

---
-- Returns the spell and item tracking tables for use in the main addon file
-- @return spellsToTrack table, itemsToTrack table
function GetCooldownTrackerSettings()
    return CooldownTrackerSettings.spellsToTrack, CooldownTrackerSettings.itemsToTrack
end

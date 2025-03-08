-- CooldownTrackerSettings.lua
-- Configuration file for CooldownTracker addon

-- Create defaults table if not already loaded
if not CooldownTrackerSettings then
    CooldownTrackerSettings = {
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
        }
    }
end

-- Return the tables for easy access
function GetCooldownTrackerSettings()
    return CooldownTrackerSettings.spellsToTrack, CooldownTrackerSettings.itemsToTrack
end
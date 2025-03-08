# CooldownTracker
![WoW 2025-03-07 15-34-05-451](https://github.com/user-attachments/assets/ecd3afeb-6486-45ca-ba3b-45438e9a8afa)

### ⚠️ Edit CooldownTrackedSettings.lua to add and remove tracked spells and items! ⚠️

## Description

**CooldownTracker** is a lightweight addon for World of Warcraft 1.12 (Vanilla) that helps you track the cooldowns of your important spells and items. It displays simple, movable icons on your screen that visually represent when your abilities are ready to use again. This addon is designed to be easy to use and configure, allowing you to keep track of vital cooldowns without cluttering your interface.

**Key Features:**

*   **Spell Cooldown Tracking:** Automatically tracks cooldowns for a predefined list of spells.
*   **Item Cooldown Tracking:**  Tracks cooldowns for specified items, like grenades, potions, and consumables.
*   **Easy to Configure:**  Add or remove spells and items directly in the `CooldownTrackedSettings.lua` file.
*   **Performance Optimized:** Designed to be lightweight and have minimal impact on game performance, suitable for Vanilla WoW.

## Usage

Once installed and loaded, CooldownTracker will automatically start tracking the default spells and items. You will see icons appear on your screen representing these tracked abilities and items.

**Default Functionality:**

*   The addon will display icons for the spells and items listed in its configuration.
*   When you use a tracked spell or item, the corresponding icon will show a cooldown timer, visually indicating when it will be ready again.
*   By default, the icons are **locked** in place.

## Adding Your Own Spells and Items

You can easily customize CooldownTracker to track additional spells and items by editing the `CooldownTrackedSettings.lua` file.

**Important:**

*   **Make sure World of Warcraft is closed before editing the `CooldownTrackedSettings.lua` file.**
*   **Use a plain text editor** like Notepad, or a code editor like Notepad++. **Do not use programs like Microsoft Word**, as they can add formatting that will break the addon.

**Steps to Edit `CooldownTrackedSettings.lua`:**

1.  **Locate the `CooldownTrackedSettings.lua` file:**
    *   Navigate to your World of Warcraft directory, then `Interface\AddOns\CooldownTracker`.
    *   Find the file named `CooldownTracker.lua`.

2.  **Open `CooldownTrackedSettings.lua` with a text editor.**

3.  **Adding Spells:**
    *   Scroll down in the file until you find the section that looks like this:

    ```lua
    spellsToTrack = {
        "Earth Shock",
        "Chain Lightning",
        "Fire Nova Totem",
        "Earthbind Totem",
        "Elemental Mastery",
        "Grounding Totem",
        "Blood Fury",
    },
    ```

    *   This is a list of spells that CooldownTracker will track by default. To add a new spell, simply add its **exact spell name** (as it appears in your spellbook) to this list, inside the curly braces `{}` and within quotes `""`, and separated by commas `,`.

    *   **Example:** To add "Frostbolt" and "Polymorph", modify the section to look like this:

    ```lua
    spellsToTrack = {
        "Earth Shock",
        "Chain Lightning",
        "Fire Nova Totem",
        "Earthbind Totem",
        "Elemental Mastery",
        "Grounding Totem",
        "Blood Fury",
        "Frostbolt",
        "Polymorph",
    },
    ```

4.  **Adding Items:**
    *   Scroll further down until you find the section for items:

    ```lua
    itemsToTrack = {
        ["Thorium Grenade"] = "Interface\\Icons\\INV_Misc_Bomb_08",
        ["Goblin Sapper Charge"] = "Interface\\Icons\\Spell_Fire_SelfDestruct",
        ["Nordanaar Herbal Tea"] = "Interface\\Icons\\INV_Drink_Milk_05",
        ["Limited Invulnerability Potion"] = "Interface\\Icons\\INV_Potion_62",
    },
    ```

    *   This section lists items to track and their corresponding icon paths. To add a new item, you need to know its **exact item name** and the **path to its icon**.

    *   **Finding Item Icon Paths:**  Icon paths are usually found within the World of Warcraft game files. A common method (though potentially requiring external tools or websites, which are outside the scope of this readme for 1.12) is to inspect item data or use online databases that list icon paths for Vanilla WoW.  If you don't know the icon path, you can use a default question mark icon, and replace it later if you find the correct path.

    *   **Adding an Item Example (with known icon path):** Let's say you want to track "Health Potion" and you know its icon path is `Interface\Icons\INV_Potion_21`.  Add a new line to the `itemsToTrack` section like this:

    ```lua
    itemsToTrack = {
        ["Thorium Grenade"] = "Interface\\Icons\\INV_Misc_Bomb_08",
        ["Goblin Sapper Charge"] = "Interface\\Icons\\Spell_Fire_SelfDestruct",
        ["Nordanaar Herbal Tea"] = "Interface\\Icons\\INV_Drink_Milk_05",
        ["Limited Invulnerability Potion"] = "Interface\\Icons\\INV_Potion_62",
        ["Health Potion"] = "Interface\\Icons\\INV_Potion_21", -- Added Health Potion
    },
    ```

    *   **Adding an Item Example (with default question mark icon):** If you don't know the icon path for "Mana Potion", you can use a default question mark icon: `Interface\Icons\INV_Misc_QuestionMark`.

    ```lua
    itemsToTrack = {
        ["Thorium Grenade"] = "Interface\\Icons\\INV_Misc_Bomb_08",
        ["Goblin Sapper Charge"] = "Interface\\Icons\\Spell_Fire_SelfDestruct",
        ["Nordanaar Herbal Tea"] = "Interface\\Icons\\INV_Drink_Milk_05",
        ["Limited Invulnerability Potion"] = "Interface\\Icons\\INV_Potion_62",
        ["Mana Potion"] = "Interface\\Icons\\INV_Misc_QuestionMark", -- Mana Potion with default icon
    },
    ```

5.  **Save the `CooldownTrackedSettings.lua` file.**  Make sure you save it as a `.lua` file and not as `.txt` or any other format.

6.  **Launch World of Warcraft.** The addon will now track the newly added spells and items. If you added items, ensure you have them in your bags for the addon to detect them.


**Slash Commands:**

You can use the following slash commands in the game chat to control CooldownTracker:

*   **/cdt** or **/cooldowntracker**:  Displays a list of available commands in the chat window.

*   **/cdt lock**: Toggles the lock status of the icons.
    *   `/cdt lock` (once): Unlocks the icons, allowing you to drag them around your screen.
    *   `/cdt lock` (again): Locks the icons in their current positions.
    *   When unlocked, you can click and drag the icons to reposition them. Once you are satisfied with their placement, use `/cdt lock` to lock them.

*   **/cdt size \<number\>**:  Sets the size of the cooldown icons.
    *   Replace `\<number\>` with a value between `10` and `100`. For example, `/cdt size 40` will set the icon size to 40 pixels.

*   **/cdt alpha \<number\>**: Sets the transparency (alpha) of the cooldown icons.
    *   Replace `\<number\>` with a value between `0.1` (very transparent) and `1.0` (fully opaque). For example, `/cdt alpha 0.8` will set the icon transparency to 80%.

**Moving Icons:**

1.  Type `/cdt lock` in chat to **unlock** the icons.
2.  Click and drag any icon to move all icons together to your desired location on the screen.
3.  Type `/cdt lock` again to **lock** the icons in their new positions.

**Important Notes After Editing:**

*   If you have trouble getting the addon to recognize your changes, try completely exiting World of Warcraft and restarting it. Sometimes a simple `/reloadui` command in-game is not enough after modifying addon files.
*   Double-check that you have entered the spell and item names correctly and that the icon paths (if you added them) are also correct. Typos are a common cause of issues.
*   If you use a default question mark icon for an item and later find the correct icon path, you can edit the `CooldownTrackedSettings.lua` file again and replace the question mark icon path with the correct one.

Enjoy using CooldownTracker to keep track of your important cooldowns in World of Warcraft 1.12!

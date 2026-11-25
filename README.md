# Buff Bar

Buff Bar is a movable bar of buttons for casting your class buffs and using buffing consumables. It is made for World of Warcraft Forever and pairs with [Consumable Bar](https://github.com/MechanicalFerret/wowf-consumable-bar).

## Buttons

- **Class buffs** (up to 4): buffs such as Power Word: Fortitude, Battle Shout, Mark of the Wild, Arcane Intellect, blessings and armors, depending on your class. They are cast on your friendly target, or on you if you have none, at your highest known rank.
- **Flask, Battle Elixir, Guardian Elixir**: the highest level one in your bags.
- **Scrolls**: one button per stat (Agility, Intellect, Protection, Spirit, Stamina, Strength), using your highest rank.
- **Weapon buff**: oils, stones and poisons. Left click applies to your main hand, right click to your off hand.
- **Buff potion**: potions that give a buff, not healing or mana potions.
- **Other buffs**: juju, zanza and similar items.
- **Tracking**: Find Minerals, Find Herbs, Find Fish and Find Treasure, shown only for spells you know.

A buff you already have can be dimmed with its time left, hidden until it fades, or ignored. Buffs that cannot stack with each other (armors, aspects, blessings, shields, weapon imbues) count as active when any one of them is on you. Each class buff can be turned off individually. This setting is account-wide and can be edited for any class from any character.

With a friendly player targeted, buffs you can cast on others (Fortitude, Divine Spirit, Shadow Protection, Arcane Intellect, Mark of the Wild, Thorns, Unending Breath, blessings) are checked on your target instead of you. You can turn this off with the "Check friendly target" setting.

## Settings

Open them from Game Menu > Options > AddOns > Buff Bar, or with `/bbar`. You can set the grow direction, size, spacing, scale, which groups are shown, and whether the smaller or larger stack is used first. Hover an option for a description. The bar can be moved by unlocking it or in Edit Mode.

## Commands

- `/bbar`: open settings
- `/bbar unlock` and `/bbar lock`: unlock or lock the bar for moving
- `/bbar reset`: reset the bar position
- `/bbar debug`: print how each consumable in your bags was classified

## Notes

- The bar does not update during combat. It catches up when combat ends, and using a button in combat refreshes that button.
- Items are detected from English tooltip text, and class buffs are looked up by English spell name, so the addon only works on an English client.
- Elixirs without a Battle or Guardian label are sorted by what they do. Armor, stamina, defense, health and resistance elixirs count as guardian.

## Installation

### WoWUp
1. Open WoWUp and select the World of Warcraft Forever client.
2. Go to **Get Addons** and click **Install from URL**.
3. Paste `https://github.com/MechanicalFerret/wowf-buff-bar` and click **Install**.

WoWUp will then update the addon for you when a new release is published.

### Manual
1. Download the latest zip from the [Releases](https://github.com/MechanicalFerret/wowf-buff-bar/releases) page.
2. Extract it so the folder is named `BuffBar` and sits inside `World of Warcraft/_forever_/Interface/AddOns`.
3. Restart the game, or run `/reload` if it is already open.

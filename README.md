# Buff Bar

A bar of clickable buttons for your class buffs, flasks, elixirs, scrolls, weapon buffs and other buffing consumables. Sister addon to Consumable Bar.

## Buttons
- **Class buffs** (up to 4): Power Word: Fortitude, Battle Shout, Mark of the Wild, Arcane Intellect, blessings, armors and more, depending on your class. Cast on your friendly target, otherwise on you, at your highest known rank.
- **Flask**, **Battle Elixir**, **Guardian Elixir**: the highest level one in your bags.
- **Scrolls**: one button per stat (Agility, Intellect, Protection, Spirit, Stamina, Strength) showing your highest rank.
- **Weapon buff**: oils, stones and poisons. Left click applies to your main hand, right click to your off hand. Shaman imbues, oils, stones and poisons all count as active once every weapon you wield has one.
- **Buff potion**: potions that give a buff (not healing or mana potions).
- **Other buffs**: juju, zanza and similar.
- **Tracking**: Find Minerals, Find Herbs, Find Fish and Find Treasure (profession and racial spells), shown only for spells you know.

A buff that is already on you can be dimmed with its time left, hidden until it fades, or ignored (setting). Buffs that exclude each other (armors, aspects, blessings, shields, weapon imbues) all count as active when any one of them is on you. Each class buff can be switched off individually; these are account-wide and editable for any class from any character.

## Target check
With a friendly player selected, buffs you can cast on others (Fortitude, Divine Spirit, Shadow Protection, Arcane Intellect, Mark of the Wild, Thorns, Unending Breath, blessings) are checked on your target instead of you, so the button shows (or un-dims) when they are missing it. Self-only buffs still check you. Can be turned off in settings ("Check friendly target", on by default).

## Settings
Game Menu > Options > AddOns > Buff Bar. Grow direction (left or right from a fixed anchor edge), size, spacing, scale, lock, which groups show, and how ties between equal items are broken (smaller or larger stack first). Hover any option for an explanation. The bar can also be moved in Edit Mode.

## Commands
- `/bbar` open settings
- `/bbar unlock` / `/bbar lock`
- `/bbar reset` reset position
- `/bbar debug` print how each consumable in your bags was classified

## Notes
- Nothing is scanned or updated in combat; the bar catches up when combat ends. Using a bar button in combat refreshes just that button.
- Item detection reads English tooltip text. Class buffs are looked up by English spell name.
- Elixirs without a Battle/Guardian label are sorted by what they do (armor, stamina, defense, health and resistance count as guardian).

## Install
Copy the folder to `Interface/AddOns/BuffBar`.

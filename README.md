# l4d2_weapon_vote
The plugin adds the ability to get weapons by voting.

Use the `!wv` command to access the list of available weapons.

To add a weapon to the list, edit the `config/weapon_vote.ini` file:
```
; "Weapon const (weapon_*)" "Name in menu" "command (sm_*)"
"weapon_sniper_scout" "Scout" "sm_scout" ; Adds a Scout, available with the !scout command.
"weapon_pistol_magnum" "Magnum" "sm_magnum" Adds a Magnum, available with the !magnum command.
```

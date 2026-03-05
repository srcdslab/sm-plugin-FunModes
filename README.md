# FunModes

A bunch of funmodes especially made for Zombie Escape

# Global Admin Commands

- sm_funmodes - "Show all available funmodes"

# Global Cvars

- sm_funmodes_hud_channel - "The channel for the hud if using DynamicChannels"

# Plugin Structure
- Each funmode will need to be included in Fun_Modes/Core.sp file, editing macros to include the funmode is required
- You can remove any funmode you want from the Fun_Modes/ folder

# Current FunModes Available

## HealBeacon

Picks random humans (based on a cvar) and beacons them, other humans need to be close to their beacons to get healed, they will get damaged otherwise

### Admin Commands
- sm_fm_healbeacon - "Toggle On/Off Healbeacon"
- sm_healbeacon - "Shows healbeacon menu"
- sm_beacon_distance - "Change beacon distance"
- sm_replacebeacon - "Replace an already heal beaconed player with another one"
- sm_addnewbeacon - "Add a new heal beaconed player"
- sm_removebeacon - "Remove heal beacon player"

### Player Commands
- sm_checkdistance - "Check the distance between the player and the target"

### Cvars
- sm_beacon_timer - "The time that will start picking random players at round start"
- sm_beacon_alert_timer - "How much time in seconds the damage will start being applied from heal beacon as an alert for the other humans"
- sm_beacon_damage - "The damage that the heal beacon will give"
- sm_beacon_heal - "How much heal beacon should heal the players in 1 second"
- sm_healbeacon_randoms - "How many random players should get the heal beacon"
- sm_healbeacon_distance - "Default distance of beacon to give"
- sm_healbeacon_enable - "Enable/Disable HealBeacon mode"

## VIPMode
Picks random humans (based on a cvar) and beacons them, if all selected humans died, the rest of the team die

### Admin Commands
- sm_fm_vipmode - "Toggle On/Off VIP Mode"
- sm_vipmode_settings - "Opens VIPMode Settings Menu"
- sm_vipmode_setvip - "Set a specific human as VIP"

### Player Commands
- sm_checkvip - "Check the current VIPs list"

### Cvars
- sm_vipmode_timer - "After how many seconds from round start to pick VIP"
- sm_vipmode_counter - "After how many seconds all the other humans will be slayed after the vip dies"
- sm_vipmode_laser - "Don't Kill all humans when vip dies to a laser, 1 = Enabled, 0 = Disabled"
- sm_vipmode_max_vips - "How many VIPs to be picked"
- sm_vipmode_enable - "Enable/Disable the VIP Mode (This differes from turning it on/off)"

## Fog
Adds an env_fog_controller to the map

### Admin Commands
- sm_fm_fog - "Toggle fog on/off"
- sm_fogmode - "Fog Settings"
- sm_fog_start - "Fog Start"
- sm_fog_end - "Fog End"

### Cvars
- sm_fog_enable - "Enable/Disable Fog Mode (This differs from turning it on/off)"

## RedLightGreenLight
Red Light Green Light game, where humans get hurt if they moved if it was red light

### Admin Commands
- sm_fm_rlgl - "Toggle On/Off RedLightGreenLight mode"
- sm_rlgl_settings - "Open RLGL Settings Menu"

### Cvars
- sm_rlgl_time_between_damage - "The timer interval for player to detect their movement"
- sm_rlgl_freeze_time - "How many seconds the movement detection should be disabled after"
- sm_rlgl_time_between_redlights_min - "After how many seconds to keep repeating the redlights (MIN VALUE)"
- sm_rlgl_time_between_redlights_max - "After how many seconds to keep repeating the redlights (MAX VALUE, SET TO 0 to disable min/max)"
- sm_rlgl_damage - "Damage to apply to the player that is moving while its a red light"
- sm_rlgl_warning_time - "Time in seconds to warn the players before red light is on"
- sm_rlgl_zombies_speed - "Zombies speed during red light, if set to 0 then it is disabled"
- sm_rlgl_countdown_folder - "Countdown folder and the files that can be used for sound"
- sm_rlgl_enable - "Enable/Disable the RLGL Mode (This differes from turning it on/off)"

## DoubleJump
X extra jumps for either humans/zombies (depending on a cvar)

### Admin Commands
- sm_fm_doublejump - "Toggle On/Off Double Jump Mode"
- sm_doublejump_settings - "Open DoubleJump Settings Menu"

### Cvars
- sm_doublejump_boost - "The amount of vertical boost to apply to double jumps."
- sm_doublejump_max_jumps - "How many re-jumps the player can do while he is in the air."
- sm_doublejump_humans - "Enable/Disable Double jump for humans."
- sm_doublejump_zombies - "Enable/Disable Double jump zombies."
- sm_doublejump_enable - "Enable/Disable Double Jump mode"

## InvertedControls
Changes the value of sv_accelerate, Invert the players' controls

### Admin Commands
- sm_fm_ic - "Toggle On/Off InvertedControls Mode"
- sm_ic_settings - "Open InvertedControl Settings Menu"

### Cvars
- sm_ic_enable - "Enable/Disable InvertedControls mode, (this differs from turning it on/off)

## DamageGame
Damage Players who keep doorhugging and not help defending

### Admin Commands
- sm_fm_damagegame - "Toggle On/Off DamageGame Mode"
- sm_damagegame_settings - "Open DamageGame Settings Menu"

### Cvars
- sm_damagegame_time_interval - "Damage Game Timer Interval"
- sm_damagegame_damage - "The amount of damage to apply to players who don't shoot zombies"
- sm_damagegame_mode - "DamageGame Mode (0 = Worst defenders, 1 = Doesn't defend for x time, 2 = Both)"
- sm_damagegame_enable - "Enable/Disable Damage Game"

## BlindMode
Give Random zombies flashbang and blind humans with it

### Admin Commands
- sm_fm_blindmode - "Toggle On/Off BlindMode Mode"
- sm_blindmode_settings - "Open BlindMode Settings Menu"

### Cvars
- sm_blindmode_time_interval - "Every how many seconds to keep giving the zombies flashbang?"
- sm_blindmode_percentage - "Percentage value of zombies to give flashbang to"
- sm_blindmode_max_distance - "Max distance between humans and flashbang to apply blind in units"
- sm_blindmode_blind_time - "How many seconds should the humans be blind for?"
- sm_blindmode_enable - "Enable/Disable BlindMode Mode (This differs from turning it on/off)"

## SlapMode
Slap a random player every x seconds

### Admin Commands
- sm_fm_slapmode - "Toggle On/Off SlapMode Mode"
- sm_slapmode_settings - "Open SlapMode Settings Menu"

### Cvars
- sm_slapmode_time_interval - "Every how many seconds to keep slapping a random human?"
- sm_slapmode_randoms_count - "How many random humans to keep slapping?"
- sm_slapmode_enable - "Enable/Disable SlapMode Mode (This differs from turning it on/off)"

## ChaosWeapons
A random weapon gets chosen every x seconds to be the only weapon dealing knockback to zombies

### Admin Commands
- sm_fm_chaosweapons - "Toggle On/Off ChaosWeapons Mode"
- sm_chaosweapons_settings - "Open ChaosWeapons Settings Menu"

### Cvars
- sm_chaosweapons_timer_interval - "Every how many seconds to keep picking a random weapon?"
- sm_chaosweapons_knockback - "Knockback to set of other weapons"
- sm_chaosweapons_countdown - "How many seconds for the countdown"
- sm_chaosweapons_enable - "Enable/Disable ChaosWeapons Mode (This differs from turning it on/off)"

## GunGame
The same as the normal GunGame mode, humans need to defend and shoot the zombies in order to upgrade their weapons, there will also be different rewards when finishing a cycle

### Admin Commands
- sm_fm_gungame - "Toggle On/Off GunGame Mode"
- sm_gungame_settings - "Open GunGame Settings Menu"

### Cvars
- sm_gungame_pistols_damage - "The required damage needed for pistols to upgrade"
- sm_gungame_shotguns_damage - "The required damage needed for shotguns to upgrade"
- sm_gungame_smgs_damage - "The required damage needed for smgs to upgrade"
- sm_gungame_rifles_damage - "The required damage needed for rifles to upgrade"
- sm_gungame_m249_damage - "The required damage needed for m249 to finish the gungame cycle"
- sm_gungame_smokegrenades_reward - "How many smokegrenades to give to the player when completing a cycle"
- sm_gungame_gravity_reward - "How many seconds can the player keep their low gravity hold"
- sm_gungame_speed_reward - "How many seconds can the player keep their high speed hold"
- sm_gungame_allow_change_weapon - "Enable/Disable allowing players to change their weapon to lower level"
- sm_gungame_enable - "Enable/Disable GunGame Mode (This differs from turning it on/off)"

## MathGame
Humans and/or zombies need to answer math questions or they will get hurt!

### Admin Commands
- sm_fm_mathgame - "Toggle On/Off MathGame Mode"
- sm_mathgame_settings - "Open MathGame Settings Menu"

### Cvars
- sm_mathgame_easy_time - "The time needed to answer easy math questions"
- sm_mathgame_medium_time - "The time needed to answer medium math questions"
- sm_mathgame_hard_time - "The time needed to answer hard math questions"
- sm_mathgame_easy_damage - "The amount of damage to apply to those who can't answer easy questions"
- sm_mathgame_medium_damage - "The amount of damage to apply to those who can't answer medium questions"
- sm_mathgame_hard_damage - "The amount of damage to apply to those who can't answer hard questions"
- sm_mathgame_include_zombies - "Include zombies to the math game (1 = Enabled, 0 = Disabled)"
- sm_mathgame_max_tries - "How many failed tries for zombies to answer question until they can never respawn again?"
- sm_mathgame_time_delay - "The delayed time after each math question"
- sm_mathgame_enable - "Enable/Disable MathGame Mode (This differs from turning it on/off)"

## CrazyShop
A bunch of powerful items that can be bought by earing credits by shooting the zombies

### Admin Commands
- sm_fm_crazyshop - "Toggle On/Off CrazyShop Mode"
- sm_crazyshop_settings - "Open CrazyShop Settings Menu"

### Player Commands
- sm_crazyshop - "Open the crazyshop menu"
- sm_myitems - "Open the list of items available to activate"

### Cvars
- sm_crazyshop_damage - "The needed damage for humans to be rewarded with credits"
- sm_crazyshop_credits - "How many credits to reward the human when they reach the needed damage?"
- sm_crazyshop_savecredits - "Save credits to a database or not"
- sm_crazyshop_slowbeacon_radius - "Slow Beacon Radius"
- sm_crazyshop_disable_shop - "Enable/Disable the !crazyshop command"
- sm_crazyshop_enable - "Enable/Disable CrazyShop Mode (This differs from turning it on/off)"

## RealityShift
Each human will swap their position with another every x seconds

### Admin Commands
- sm_fm_rs - "Toggle On/Off RealityShift Mode"
- sm_realityshift_settings - "Open RealityShift Settings Menu"

### Cvars
- sm_realityshift_timer_interval - "After how many seconds to keep swapping positions"
- sm_realityshift_mode - "RealityShift Mode [0 = Random Swaps, 1 = Assigned Swaps [At round start]]"
- sm_realityshift_enable - "Enable/Disable RealityShift Mode (This differs from turning it on/off)"

## PullGame
Random zombies will be chosen to have the pull item that can pull a human based on their aim, in the other hand, humans can pull the human that's being pulled

### Admin Commands
- sm_fm_pullgame - "Toggle On/Off PullGame Mode"
- sm_pullgame_settings - "Open PullGame Settings Menu"

### Cvars
- sm_pullgame_timer_interval - "After how many seconds to keep giving pull access to a random zm?"
- sm_pullgame_speed - "Pulling Speed Value"
- sm_pullgame_pull_time - "Pulling Time"

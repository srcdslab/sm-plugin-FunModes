# FunModes

A bunch of funmodes especially made for Zombie Escape

The modes are grouped by category in the menu: Survival rules, Weapons, Hazards & disasters, Weather & nature, Chaos & tricks, Mini-games and Zombies. The Event Roulette sits at the top of the menu.

Many of the modes (most of the hazards, weather, mini-games and zombie modes, the Event Roulette and the Dynamic Fog engine) were made by Hobbitten.

# Global Admin Commands

- sm_funmodes / sm_fm - "Open the FunModes menu: category -> mode page, where each setting shows its value and goes to the next one when picked"
- sm_em - "Alias of sm_fm"
- sm_fm <mode> [on|off] - "Turn a mode on/off from chat, console or rcon (no on/off = switch it)"
- sm_fm list - "List the modes and which ones are on"
- sm_fm stop - "Turn every mode off"
- sm_fmcvar <cvar> [value] - "Show or change a FunModes cvar"

# Global Cvars

- sm_funmodes_hud_channel - "The channel for the hud if using DynamicChannels"

# Plugin Structure
- Each funmode will need to be included in `Fun_Modes/Core/ModesInclude.sp` file, The order matters.
- Each funmode will also need to be included in `FunModes/Core/ModesInclude.sp` in Forwards_OnPluginStart function.
- You can remove any funmode you want by removing or commenting the line that includes the mode file in `FunModes/Core/ModesInclude.sp`
- `EventRoulette.sp` must stay the last included mode: it turns the other modes on and off.
- `Fun_Modes/Core/Shared.sp` holds the helpers the modes share: round tracking (`g_bRoundLive`, `g_bZombiesSeen`, `g_iRoundNum`), hazards (`HazardDue`, `ExplodeAt`, `DrawRingAt`...), stacked speed and gravity (`SetSpeedMult`, `SetGravityMult`) and hud slots (`CreateModeHud`, `ShowModeHud`).
- Besides the usual forwards, a mode can define `OnTick_<Mode>()` (every second), `OnCheck_<Mode>(bool zombiesNow)` (every 0.2 seconds), `OnPlayerRunCmd_<Mode>(client, &buttons, vel[3], &changed)`, `OnClientSayCommand_<Mode>(client, text, &result)` and `OnBuyCommand_<Mode>(client, weapon, &result)`. The tick, check, run cmd, chat and buy forwards are only called while the mode is on.
- Set `THIS_MODE_INFO.category` to one of the `FM_CAT_*` categories, and `THIS_MODE_INFO.roulette = false` if the Event Roulette should never pick the mode.
- `configs/FunModes/ConVars.cfg` is matched by cvar name, so adding a mode or a cvar never shifts the saved values. Cvars missing from the file use their default and are added the first time they are changed.
- Read and write the config files with `FunModes_LoadKV` / `FunModes_SaveKV` (Shared.sp), not `ImportFromFile` / `ExportToFile` directly: on some servers the engine's KeyValues reader refuses the files, and these fall back to SourceMod's own parser.
- No mode restarts the round when it's turned on: a mode turned on mid-round starts in that round.
- Each mode text has its own row on the screen (`HUD_Y_*` in Shared.sp) and its own hud slot (`CreateModeHud`), so two modes never draw over each other.

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
- sm_healbeacon_choose <player> - "Chosen carrier: a heal beacon every round until they leave the server, never picked as mother zombie (again to undo)"

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
- sm_healbeacon_on_lost - "When a carrier dies or gets infected [0 = the beacon is gone, 1 = a random human gets it, 2 = all humans are slain]"
- sm_healbeacon_sound - "The heal beacons beep every second"

## VIPMode
Picks random humans (based on a cvar) and beacons them, if all selected humans died, the rest of the team die. A VIP who gets infected falls too, a VIP who becomes a mother zombie is replaced.

### Admin Commands
- sm_fm_vipmode - "Toggle On/Off VIP Mode"
- sm_vipmode_settings - "Opens VIPMode Settings Menu"
- sm_vipmode_setvip <player> - "Chosen VIP: VIP every round until they leave the server, never picked as mother zombie (again to undo)"

### Player Commands
- sm_checkvip - "Check the current VIPs list"

### Cvars
- sm_vipmode_timer - "After how many seconds from round start to pick VIP"
- sm_vipmode_counter - "After how many seconds all the other humans will be slayed after the vip dies"
- sm_vipmode_laser - "Don't Kill all humans when vip dies to a laser, 1 = Enabled, 0 = Disabled"
- sm_vipmode_max_vips - "How many VIPs to be picked"
- sm_vipmode_enable - "Enable/Disable the VIP Mode (This differes from turning it on/off)"
- sm_vipmode_replace - "When all the VIPs die pick new VIPs instead of killing all the humans"
- sm_vipmode_hud - "Show the VIPs names on everyone's screen"

## Fog
Dynamic fog on any map: every env_fog_controller of the map (plus one of our own for maps without fog) and the 3D skybox fog show the admins' values, re-applied so the map logic can't undo them. Presets are in `configs/FunModes/Fog.cfg` (its `MapPresets` section gives a map its own preset), changes blend in over time and turning the mode off gives the map its own fog back.

### Admin Commands
- sm_fm_fog - "Toggle fog on/off (applies sm_fog_preset)"
- sm_fogmode - "Fog Settings: presets, thicker/thinner, fade time, skybox"
- sm_fog_start <distance> - "Fog Start"
- sm_fog_end <distance> - "Fog End"
- sm_fog - "Fine-tune the fog in chat: on, off, reset, start, end, range, color, color2, density, farz, blend, preset, presets, fade, sky, status (sm_fog help)"

### Cvars
- sm_fog_enable - "Enable/Disable Fog Mode (This differs from turning it on/off)"
- sm_fog_fade - "Default seconds a fog change blends in"
- sm_fog_skybox - "Also override the 3D skybox fog"
- sm_fog_announce - "Tell everyone in chat when an admin changes the fog"
- sm_fog_interval - "Seconds between re-applying the fog so the map can't undo it"
- sm_fog_preset - "Preset applied when the mode is turned on (random = a random one)"

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
- sm_rlgl_grace - "Seconds the players have to stop once the red light is on"
- sm_rlgl_everyone - "The zombies have to stop moving on red light too"

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
Inverts the players' controls: everyone all the time (sv_accelerate), or random players for a few seconds every so often (sm_ic_mode 1)

### Admin Commands
- sm_fm_ic - "Toggle On/Off InvertedControls Mode"
- sm_ic_settings - "Open InvertedControl Settings Menu"

### Cvars
- sm_ic_enable - "Enable/Disable InvertedControls mode, (this differs from turning it on/off)
- sm_ic_mode - "Inverted Controls mode [0 = everyone all the time (sv_accelerate), 1 = random players every few seconds]"
- sm_ic_every - "Mode 1: seconds between two inversions"
- sm_ic_last - "Mode 1: seconds an inversion lasts"
- sm_ic_who - "Mode 1: who gets inverted [0 = all humans, 1 = half the humans, 2 = one random human, 3 = everyone]"

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
- sm_gungame_scale - "Multiplier on the damage needed for every weapon"
- sm_gungame_keep - "Keep the players weapon level between rounds"
- sm_gungame_hud - "Show the players their weapon and the damage left to the next one"

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
- sm_mathgame_time_delay - "The delayed time after each math question"
- sm_mathgame_enable - "Enable/Disable MathGame Mode (This differs from turning it on/off)"
- sm_mathgame_reward - "Reward for a right answer [0 = nothing, 1 = +25 HP, 2 = +50 HP, 3 = HE grenade]"
- sm_mathgame_same - "Everyone gets the same question (else each player their own)"

## RealityShift
Each human will swap their position with another every x seconds (after a countdown). Players carrying a map item are never moved

### Admin Commands
- sm_fm_rs - "Toggle On/Off RealityShift Mode"
- sm_realityshift_settings - "Open RealityShift Settings Menu"

### Cvars
- sm_realityshift_timer_interval - "After how many seconds to keep swapping positions"
- sm_realityshift_mode - "RealityShift Mode [0 = Random Swaps, 1 = Assigned Swaps [At round start]]"
- sm_realityshift_enable - "Enable/Disable RealityShift Mode (This differs from turning it on/off)"
- sm_realityshift_pairs - "Random swaps: how many pairs swap each time (0 = everyone)"
- sm_realityshift_mixed - "Zombies are swapped too"
- sm_realityshift_warn - "Seconds of countdown with beeps before each swap (0 = none)"

## PullGame
Random zombies will be chosen to have the pull item that can pull a human based on their aim, in the other hand, humans can pull the human that's being pulled

### Admin Commands
- sm_fm_pullgame - "Toggle On/Off PullGame Mode"
- sm_pullgame_settings - "Open PullGame Settings Menu"

### Cvars
- sm_pullgame_timer_interval - "After how many seconds to keep giving pull access to a random zm?"
- sm_pullgame_speed - "Pulling Speed Value"
- sm_pullgame_pull_time - "Pulling Time"

## MeteorShower
Once the zombies are out, every few seconds meteors are aimed near random humans: an orange ring and a trail from the sky warn where they land, then each one explodes.

### Admin Commands
- sm_fm_meteor - "Toggle On/Off Meteor Shower"
- sm_meteor_settings - "Open Meteor Shower Settings Menu"

### Cvars
- sm_meteor_every - "Seconds between two meteor showers"
- sm_meteor_count - "Meteors per shower"
- sm_meteor_damage - "Damage at the centre of a meteor (1000 = kill)"
- sm_meteor_radius - "Blast radius of a meteor"
- sm_meteor_knockback - "Meteors push the players away"
- sm_meteor_zombies - "Meteors hit the zombies too"
- sm_meteor_enable - "Enable/Disable Meteor Shower Mode (This differs from turning it on/off)"

## Airstrike
Once the zombies are out, every few seconds a siren warns of an airstrike, then bombs fall one by one around where the humans were standing.

### Admin Commands
- sm_fm_airstrike - "Toggle On/Off Airstrike"
- sm_airstrike_settings - "Open Airstrike Settings Menu"

### Cvars
- sm_airstrike_every - "Seconds between two airstrikes"
- sm_airstrike_bombs - "Bombs per airstrike"
- sm_airstrike_warn - "Seconds of warning before the bombs fall"
- sm_airstrike_damage - "Damage at the centre of a bomb (1000 = kill)"
- sm_airstrike_radius - "Blast radius of a bomb"
- sm_airstrike_zombies - "Bombs hit the zombies too"
- sm_airstrike_enable - "Enable/Disable Airstrike Mode (This differs from turning it on/off)"

## Shockwave
Once the zombies are out, every few seconds a blue ring spreads out from near a human: whoever is on the ground when it goes by gets hurt and thrown up, so jump over it.

### Admin Commands
- sm_fm_shockwave - "Toggle On/Off Shockwave"
- sm_shockwave_settings - "Open Shockwave Settings Menu"

### Cvars
- sm_shockwave_every - "Seconds between two shockwaves"
- sm_shockwave_damage - "Damage of the shockwave (1000 = kill)"
- sm_shockwave_size - "How far the shockwave travels"
- sm_shockwave_speed - "Speed of the shockwave (units per second)"
- sm_shockwave_zombies - "The shockwave hits the zombies too"
- sm_shockwave_enable - "Enable/Disable Shockwave Mode (This differs from turning it on/off)"

## Nuke
Once the zombies are out, a nuclear strike is announced with a countdown: a green bunker appears near a random human, and whoever is outside it when the countdown ends gets hurt.

### Admin Commands
- sm_fm_nuke - "Toggle On/Off Nuke Countdown"
- sm_nuke_settings - "Open Nuke Countdown Settings Menu"

### Cvars
- sm_nuke_every - "Seconds between two nukes (0 = once a round, a little after the zombies come)"
- sm_nuke_countdown - "Seconds of countdown before the strike"
- sm_nuke_bunker - "Radius of the bunker"
- sm_nuke_damage - "Damage outside the bunker (1000 = kill)"
- sm_nuke_zombies - "Zombies outside the bunker get hit too"
- sm_nuke_enable - "Enable/Disable Nuke Countdown Mode (This differs from turning it on/off)"

## ToxicGas
Once the zombies are out, every few seconds green clouds of gas appear where some humans stand, hurting whoever stays inside them until they fade away.

### Admin Commands
- sm_fm_gas - "Toggle On/Off Toxic Gas"
- sm_gas_settings - "Open Toxic Gas Settings Menu"

### Cvars
- sm_gas_every - "Seconds between two gas leaks"
- sm_gas_count - "Gas clouds per leak"
- sm_gas_last - "Seconds a gas cloud lasts"
- sm_gas_radius - "Radius of a gas cloud"
- sm_gas_damage - "Damage per second inside a gas cloud"
- sm_gas_zombies - "The gas hurts the zombies too"
- sm_gas_enable - "Enable/Disable Toxic Gas Mode (This differs from turning it on/off)"

## AcidRain
Once the zombies are out, every few seconds it rains acid for a while: whoever has nothing but sky above their head gets hurt, so get under a roof.

### Admin Commands
- sm_fm_acid - "Toggle On/Off Acid Rain"
- sm_acid_settings - "Open Acid Rain Settings Menu"

### Cvars
- sm_acid_every - "Seconds between two acid rains"
- sm_acid_last - "Seconds an acid rain lasts"
- sm_acid_damage - "Damage per second under the acid rain"
- sm_acid_zombies - "The acid rain hurts the zombies too"
- sm_acid_enable - "Enable/Disable Acid Rain Mode (This differs from turning it on/off)"

## FreezingCold
Once the zombies are out, cold snaps come every few seconds (or it's cold all the time): humans who don't have enough other humans close by freeze and lose health.

### Admin Commands
- sm_fm_cold - "Toggle On/Off Freezing Cold"
- sm_cold_settings - "Open Freezing Cold Settings Menu"

### Cvars
- sm_cold_every - "Seconds between two cold snaps (0 = cold all the time)"
- sm_cold_last - "Seconds a cold snap lasts"
- sm_cold_damage - "Damage per second while freezing"
- sm_cold_huddle - "How close the other humans must be to keep warm"
- sm_cold_need - "Other humans needed close by to keep warm"
- sm_cold_enable - "Enable/Disable Freezing Cold Mode (This differs from turning it on/off)"

## Darkness
Once the zombies are out, every few seconds the lights go out: the screens of the humans (and the zombies, if set) go dark for a few seconds, then slowly come back.

### Admin Commands
- sm_fm_darkness - "Toggle On/Off Sudden Darkness"
- sm_darkness_settings - "Open Sudden Darkness Settings Menu"

### Cvars
- sm_darkness_every - "Seconds between two blackouts of the lights"
- sm_darkness_last - "Seconds the lights stay out"
- sm_darkness_level - "How dark it gets [0 = dim, 1 = dark, 2 = very dark, 3 = pitch black]"
- sm_darkness_zombies - "The zombies are in the dark too"
- sm_darkness_enable - "Enable/Disable Sudden Darkness Mode (This differs from turning it on/off)"

## GravityWaves
Once the zombies are out, every few seconds a gravity wave gives everyone low gravity for a few seconds (on top of their own gravity).

### Admin Commands
- sm_fm_gravity - "Toggle On/Off Gravity Waves"
- sm_gravity_settings - "Open Gravity Waves Settings Menu"

### Cvars
- sm_gravity_every - "Seconds between two gravity waves"
- sm_gravity_last - "Seconds a gravity wave lasts"
- sm_gravity_gravity - "Gravity during a wave (x normal gravity)"
- sm_gravity_everyone - "The zombies float too"
- sm_gravity_enable - "Enable/Disable Gravity Waves Mode (This differs from turning it on/off)"

## IceFloor
Once the zombies are out, every few seconds the floor freezes for a while: sv_friction is lowered so everyone slides, then put back.

### Admin Commands
- sm_fm_ice - "Toggle On/Off Ice Floor"
- sm_ice_settings - "Open Ice Floor Settings Menu"

### Cvars
- sm_ice_every - "Seconds between two frozen floors"
- sm_ice_last - "Seconds the floor stays frozen"
- sm_ice_level - "How slippery [0 = slippery, 1 = very slippery, 2 = ice rink, 3 = pure ice]"
- sm_ice_enable - "Enable/Disable Ice Floor Mode (This differs from turning it on/off)"

## WindGusts
Once the zombies are out, every few seconds (or all the time) the wind blows and pushes everyone in one direction, turning every few seconds.

### Admin Commands
- sm_fm_wind - "Toggle On/Off Wind Gusts"
- sm_wind_settings - "Open Wind Gusts Settings Menu"

### Cvars
- sm_wind_every - "Seconds between two gusts of wind (0 = windy all the time)"
- sm_wind_last - "Seconds a gust of wind lasts"
- sm_wind_level - "Wind strength [0 = breeze, 1 = windy, 2 = strong wind, 3 = storm, 4 = hurricane]"
- sm_wind_turn - "Seconds between two changes of direction"
- sm_wind_everyone - "The wind pushes the zombies too"
- sm_wind_enable - "Enable/Disable Wind Gusts Mode (This differs from turning it on/off)"

## Tornado
Once the zombies are out, every few seconds a tornado forms near a human and wanders after the humans for a while, pulling in, spinning and lifting whoever gets too close.

### Admin Commands
- sm_fm_tornado - "Toggle On/Off Tornado"
- sm_tornado_settings - "Open Tornado Settings Menu"

### Cvars
- sm_tornado_every - "Seconds between two tornadoes"
- sm_tornado_last - "Seconds a tornado lasts"
- sm_tornado_radius - "Radius the tornado pulls in"
- sm_tornado_power - "Tornado power [0 = gentle, 1 = strong, 2 = violent, 3 = F5]"
- sm_tornado_speed - "How fast the tornado wanders"
- sm_tornado_everyone - "The tornado pulls the zombies too"
- sm_tornado_enable - "Enable/Disable Tornado Mode (This differs from turning it on/off)"

## Quicksand
Once the zombies are out, every few seconds brown patches of quicksand appear where some humans stand: whoever is inside one is slowed down until it dries out.

### Admin Commands
- sm_fm_quicksand - "Toggle On/Off Quicksand"
- sm_quicksand_settings - "Open Quicksand Settings Menu"

### Cvars
- sm_quicksand_every - "Seconds between two quicksand patches"
- sm_quicksand_count - "Quicksand patches each time"
- sm_quicksand_last - "Seconds a quicksand patch lasts"
- sm_quicksand_radius - "Radius of a quicksand patch"
- sm_quicksand_slow - "Speed inside the quicksand (x normal speed)"
- sm_quicksand_zombies - "The zombies sink too"
- sm_quicksand_enable - "Enable/Disable Quicksand Mode (This differs from turning it on/off)"

## MagnetPull
Once the zombies are out, every few seconds a magnetic pulse pulls the humans towards the middle of the zombies (or towards each other) for a few seconds.

### Admin Commands
- sm_fm_magnet - "Toggle On/Off Magnet Pull"
- sm_magnet_settings - "Open Magnet Pull Settings Menu"

### Cvars
- sm_magnet_every - "Seconds between two magnetic pulses"
- sm_magnet_last - "Seconds a magnetic pulse lasts"
- sm_magnet_level - "Pull strength [0 = weak, 1 = medium, 2 = strong, 3 = very strong]"
- sm_magnet_target - "Where the humans are pulled [0 = towards the zombies, 1 = towards each other]"
- sm_magnet_enable - "Enable/Disable Magnet Pull Mode (This differs from turning it on/off)"

## Hallucinations
Once the zombies are out, every few seconds some humans see or hear things that aren't there: a growl behind them, a colour flash, a lie on screen or a fake danger ring.

### Admin Commands
- sm_fm_halluc - "Toggle On/Off Hallucinations"
- sm_halluc_settings - "Open Hallucinations Settings Menu"

### Cvars
- sm_halluc_every - "Seconds between two hallucinations"
- sm_halluc_count - "Humans who hallucinate each time (64 = everyone)"
- sm_halluc_sounds - "Hallucinations can be fake zombie sounds"
- sm_halluc_visuals - "Hallucinations can be flashes, texts and fake rings"
- sm_halluc_enable - "Enable/Disable Hallucinations Mode (This differs from turning it on/off)"

## Leech
Once the zombies are out, the humans' health drains unless they keep hurting zombies, and/or every few seconds the humans who dealt the least damage get hurt. Dealing damage can also heal a little.

### Admin Commands
- sm_fm_leech - "Toggle On/Off Leech"
- sm_leech_settings - "Open Leech Settings Menu"

### Cvars
- sm_leech_mode - "Leech mode [0 = drain unless you hurt zombies, 1 = punish the worst defenders, 2 = both]"
- sm_leech_worst_every - "Seconds between two worst defenders checks"
- sm_leech_worst_count - "How many of the worst defenders get hurt"
- sm_leech_worst_damage - "Damage given to the worst defenders"
- sm_leech_drain - "Health drained per second"
- sm_leech_grace - "Seconds without drain after hurting a zombie"
- sm_leech_heal - "Health back per 100 damage dealt to zombies (up to 150 HP)"
- sm_leech_enable - "Enable/Disable Leech Mode (This differs from turning it on/off)"

## JammedGuns
Once the zombies are out, every few seconds the guns of some humans jam for a few seconds: they can't shoot until it's over.

### Admin Commands
- sm_fm_jam - "Toggle On/Off Jammed Guns"
- sm_jam_settings - "Open Jammed Guns Settings Menu"

### Cvars
- sm_jam_every - "Seconds between two jams"
- sm_jam_count - "Guns that jam each time (64 = everyone)"
- sm_jam_last - "Seconds a gun stays jammed"
- sm_jam_enable - "Enable/Disable Jammed Guns Mode (This differs from turning it on/off)"

## Butterfingers
Once the zombies are out, every few seconds some humans drop their gun on the floor (never a map item).

### Admin Commands
- sm_fm_butter - "Toggle On/Off Butterfingers"
- sm_butter_settings - "Open Butterfingers Settings Menu"

### Cvars
- sm_butter_every - "Seconds between two drops"
- sm_butter_count - "Humans who drop their gun each time (64 = everyone)"
- sm_butter_which - "Gun dropped [0 = the gun in their hands, 1 = their main gun, 2 = their pistol]"
- sm_butter_enable - "Enable/Disable Butterfingers Mode (This differs from turning it on/off)"

## ZombieFrenzy
Once the zombies are out, every few seconds the humans' screens flash red and the zombies get faster for a few seconds.

### Admin Commands
- sm_fm_frenzy - "Toggle On/Off Zombie Frenzy"
- sm_frenzy_settings - "Open Zombie Frenzy Settings Menu"

### Cvars
- sm_frenzy_every - "Seconds between two frenzies"
- sm_frenzy_last - "Seconds a frenzy lasts"
- sm_frenzy_speed - "Zombie speed during a frenzy (x normal speed)"
- sm_frenzy_enable - "Enable/Disable Zombie Frenzy Mode (This differs from turning it on/off)"

## Lightning
Once the zombies are out, every few seconds bolts land near random humans after a red warning ring, hurting anyone inside.

### Admin Commands
- sm_fm_lightning - "Toggle On/Off Lightning Strikes"
- sm_lightning_settings - "Open Lightning Strikes Settings Menu"

### Cvars
- sm_lightning_every - "Seconds between two waves of lightning"
- sm_lightning_count - "Bolts per wave"
- sm_lightning_damage - "Damage of a bolt (1000 = kill)"
- sm_lightning_radius - "Radius of a bolt"
- sm_lightning_zombies - "The bolts hurt the zombies too"
- sm_lightning_enable - "Enable/Disable Lightning Strikes Mode (This differs from turning it on/off)"

## Earthquake
Once the zombies are out, every few seconds an earthquake shakes everyone's screen and shoves the players around for a few seconds. Sets sm_force_shake 1 while it's on.

### Admin Commands
- sm_fm_quake - "Toggle On/Off Earthquake"
- sm_quake_settings - "Open Earthquake Settings Menu"

### Cvars
- sm_quake_every - "Seconds between two earthquakes"
- sm_quake_last - "Seconds an earthquake lasts"
- sm_quake_shake - "Screen shake [0 = off, 1 = tiny ... 7 = insane]"
- sm_quake_speed - "Shake speed [0 = slow rumble, 1 = normal, 2 = fast, 3 = violent]"
- sm_quake_shove - "How hard the players get shoved [0 = off, 1 = tiny ... 7 = insane]"
- sm_quake_shove_every - "Seconds between two shoves"
- sm_quake_everyone - "The zombies are shaken too"
- sm_quake_enable - "Enable/Disable Earthquake Mode (This differs from turning it on/off)"

## FloorIsLava
Once the zombies are out, whoever stands still for more than a few seconds starts burning.

### Admin Commands
- sm_fm_lava - "Toggle On/Off Floor is Lava"
- sm_lava_settings - "Open Floor is Lava Settings Menu"

### Cvars
- sm_lava_after - "Seconds standing still before it burns"
- sm_lava_damage - "Damage per second while standing still (1000 = slay)"
- sm_lava_everyone - "The zombies burn too"
- sm_lava_enable - "Enable/Disable Floor is Lava Mode (This differs from turning it on/off)"

## ZombieDrop
Once the zombies are out, every few seconds a red ring appears under some humans: after a short warning a random zombie is teleported onto that spot.

### Admin Commands
- sm_fm_drop - "Toggle On/Off Zombie Drop"
- sm_drop_settings - "Open Zombie Drop Settings Menu"

### Cvars
- sm_drop_every - "Seconds between two zombie drops"
- sm_drop_count - "Zombies dropped each time"
- sm_drop_warn - "Seconds of warning before the zombie lands"
- sm_drop_enable - "Enable/Disable Zombie Drop Mode (This differs from turning it on/off)"

## Blackout
Once the zombies are out, every few seconds the screens of a few random players go black (blackout) or white (flashbang) for a moment, then fade back.

### Admin Commands
- sm_fm_blackout - "Toggle On/Off Blackout"
- sm_blackout_settings - "Open Blackout Settings Menu"

### Cvars
- sm_blackout_every - "Seconds between two blackouts"
- sm_blackout_count - "Players hit each time (64 = everyone)"
- sm_blackout_last - "Seconds the screen stays fully dark or bright"
- sm_blackout_type - "Blackout type [0 = black (blackout), 1 = white (flashbang), 2 = random]"
- sm_blackout_everyone - "The zombies can be hit too"
- sm_blackout_enable - "Enable/Disable Blackout Mode (This differs from turning it on/off)"

## BossZombie
A little after the first zombies come, a random zombie becomes the boss: huge health (more for every living human), faster, red, with a health bar for everyone. Killing it rewards the humans.

### Admin Commands
- sm_fm_boss - "Toggle On/Off Boss Zombie"
- sm_boss_settings - "Open Boss Zombie Settings Menu"

### Cvars
- sm_boss_health - "Base health of the boss"
- sm_boss_per_human - "Extra health of the boss per living human"
- sm_boss_speed - "Speed of the boss (x normal speed)"
- sm_boss_delay - "Seconds after the first zombie before the boss rises"
- sm_boss_reward - "Reward for killing the boss [0 = nothing, 1 = +50 HP to every human, 2 = HE grenade to every human]"
- sm_boss_enable - "Enable/Disable Boss Zombie Mode (This differs from turning it on/off)"

## Hero
When the zombies come, a random human becomes the hero: more health, faster, blue. If the hero falls, the other humans lose health or are all slain (if set).

### Admin Commands
- sm_fm_hero - "Toggle On/Off Hero"
- sm_hero_settings - "Open Hero Settings Menu"

### Cvars
- sm_hero_health - "Health of the hero"
- sm_hero_speed - "Speed of the hero (x normal speed)"
- sm_hero_delay - "Seconds after the first zombie before the hero is picked"
- sm_hero_fall - "When the hero falls [0 = nothing happens, 1 = every human loses 25 HP, 2 = all humans are slain]"
- sm_hero_enable - "Enable/Disable Hero Mode (This differs from turning it on/off)"

## LastStand
When only a few humans are left, they get a power boost: more health and more speed.

### Admin Commands
- sm_fm_laststand - "Toggle On/Off Last Stand"
- sm_laststand_settings - "Open Last Stand Settings Menu"

### Cvars
- sm_laststand_at - "Humans left that triggers the last stand"
- sm_laststand_health - "Health added to the last humans"
- sm_laststand_speed - "Speed of the last humans (x normal speed)"
- sm_laststand_enable - "Enable/Disable Last Stand Mode (This differs from turning it on/off)"

## GhostZombies
The zombies are see-through, flicker in and out of sight, or both.

### Admin Commands
- sm_fm_ghost - "Toggle On/Off Ghost Zombies"
- sm_ghost_settings - "Open Ghost Zombies Settings Menu"

### Cvars
- sm_ghost_style - "Ghost style [0 = see-through, 1 = flickering, 2 = see-through + flickering]"
- sm_ghost_alpha - "How visible the see-through zombies are (0 = invisible, 255 = solid)"
- sm_ghost_flicker - "Flicker speed [0 = slow, 1 = normal, 2 = fast]"
- sm_ghost_enable - "Enable/Disable Ghost Zombies Mode (This differs from turning it on/off)"

## HotPotato
Once the zombies are out, a human holds a potato with a countdown and passes it on by knifing another human or pressing E next to one. Whoever holds it at zero explodes, hurting humans close by.

### Admin Commands
- sm_fm_potato - "Toggle On/Off Hot Potato"
- sm_potato_settings - "Open Hot Potato Settings Menu"

### Cvars
- sm_potato_time - "Seconds before the potato explodes"
- sm_potato_blast - "Damage to the humans close to the explosion"
- sm_potato_enable - "Enable/Disable Hot Potato Mode (This differs from turning it on/off)"

## Buddy
When the zombies come, the humans are paired up. If your buddy falls, you die (or bleed). Optionally you also bleed while you're too far from your buddy.

### Admin Commands
- sm_fm_buddy - "Toggle On/Off Buddy System"
- sm_buddy_settings - "Open Buddy System Settings Menu"

### Cvars
- sm_buddy_die - "When your buddy falls you die (else you bleed)"
- sm_buddy_bleed - "Health lost per second when bleeding or too far from your buddy"
- sm_buddy_max_distance - "Bleed when further than this from your buddy (0 = no distance rule)"
- sm_buddy_enable - "Enable/Disable Buddy System Mode (This differs from turning it on/off)"

## SimonSays
Once the zombies are out, every few seconds a command shows up (crouch, jump, shoot, reload, press E, stand still). Do it in time when SIMON SAYS so, don't when he doesn't. Wrong costs health.

### Admin Commands
- sm_fm_simon - "Toggle On/Off Simon Says"
- sm_simon_settings - "Open Simon Says Settings Menu"

### Cvars
- sm_simon_every - "Seconds between two commands"
- sm_simon_window - "Seconds to do the command"
- sm_simon_damage - "Damage for getting it wrong (1000 = slay)"
- sm_simon_trick - "Percent of the commands given without Simon says"
- sm_simon_everyone - "The zombies play too"
- sm_simon_enable - "Enable/Disable Simon Says Mode (This differs from turning it on/off)"

## Trivia
Every so often a question from configs/FunModes/Trivia.cfg pops up and the players type the answer in chat: the first ones to get it right win a reward. A hint shows half way through.

### Admin Commands
- sm_fm_trivia - "Toggle On/Off Trivia"
- sm_trivia_settings - "Open Trivia Settings Menu"

### Cvars
- sm_trivia_every - "Seconds between two questions"
- sm_trivia_time - "Seconds to answer"
- sm_trivia_winners - "How many players win (64 = everyone who gets it)"
- sm_trivia_reward - "Reward for a right answer [0 = +25 HP, 1 = +50 HP, 2 = HE grenade, 3 = nothing]"
- sm_trivia_hint - "Show a hint half way through"
- sm_trivia_hide - "Right answers don't show in chat (so nobody copies them)"
- sm_trivia_humans_only - "Only the living humans can answer"
- sm_trivia_enable - "Enable/Disable Trivia Mode (This differs from turning it on/off)"

## HotSeat
Every so often a few players get a TRUE / FALSE menu (a statement from configs/FunModes/HotSeat.cfg or a quick sum) and must answer in time: right earns health, wrong or no answer costs health.

### Admin Commands
- sm_fm_hotseat - "Toggle On/Off Hot Seat"
- sm_hotseat_settings - "Open Hot Seat Settings Menu"

### Cvars
- sm_hotseat_every - "Seconds between two hot seats"
- sm_hotseat_time - "Seconds to answer"
- sm_hotseat_source - "Questions [0 = statements file, 1 = quick sums, 2 = mix of both]"
- sm_hotseat_penalty - "Damage for a wrong or missing answer (1000 = slay)"
- sm_hotseat_reward - "Reward for a right answer [0 = nothing, 1 = +25 HP, 2 = +50 HP]"
- sm_hotseat_players - "Players in the hot seat at once"
- sm_hotseat_humans_only - "Only the living humans are put in the hot seat"
- sm_hotseat_enable - "Enable/Disable Hot Seat Mode (This differs from turning it on/off)"

## RandomWeapons
Every human gets a random weapon set (each their own, or everyone the same) on spawn, when the mode is turned on and on reroll. While the set is locked, only kevlar, HE grenades and ammo can be bought and no other guns picked up, except map items. Turns GunGame off.

### Admin Commands
- sm_fm_rw - "Toggle On/Off Random Weapons"
- sm_fm_randomweapons - "Toggle On/Off Random Weapons"
- sm_rw_settings - "Open Random Weapons Settings Menu"

### Player Commands
- sm_rwgun - "Random Weapons: get your weapons back"

### Cvars
- sm_rw_shared - "Everyone gets the same set (else one per player)"
- sm_rw_kind - "What the set holds [0 = primary + pistol, 1 = primary only, 2 = pistol only]"
- sm_rw_pool - "Primary guns picked from [0 = all, 1 = rifles, 2 = SMGs, 3 = shotguns, 4 = snipers]"
- sm_rw_lock - "No buying or picking up other guns once the set is given"
- sm_rw_enable - "Enable/Disable Random Weapons Mode (This differs from turning it on/off)"

## EventRoulette
At each round start it turns on random modes from the pool the admins chose and turns them off at round end. With a shuffle time set, it also picks again during the round. Modes an admin switched on by hand are never touched. The pool is saved in configs/FunModes/Roulette.cfg.

### Admin Commands
- sm_fm_roulette - "Toggle On/Off Event Roulette"
- sm_roulette_settings - "Open Event Roulette Settings Menu"

### Cvars
- sm_roulette_modes - "Modes turned on at a time"
- sm_roulette_norepeat - "The modes picked last time can't be picked again"
- sm_roulette_shuffle_min - "Least seconds before picking again during the round (0 = once a round)"
- sm_roulette_shuffle_max - "Most seconds before picking again during the round"
- sm_roulette_enable - "Enable/Disable Event Roulette Mode (This differs from turning it on/off)"

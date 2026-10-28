/*
    (). FunModes V2:
        
    @file           Core/ModesInclude.sp
    @Usage          Modes Include, Any new mode that's added should be included to the plugin by this file.
*/

#pragma newdecls required
#pragma semicolon 1

/* For the existing FunModes, you can remove or comment the line where it includes the mode file if you want get rid of it. */
#include "../HealBeacon.sp"
#include "../VIPMode.sp"
#include "../Fog.sp"
#include "../RedLightGreenLight.sp"
#include "../DoubleJump.sp"
#include "../InvertedControls.sp"
#include "../DamageGame.sp"
#include "../BlindMode.sp"
#include "../SlapMode.sp"
#include "../ChaosWeapons.sp"
#include "../GunGame.sp"
#include "../MathGame.sp"
#include "../CrazyShop.sp"
#include "../RealityShift.sp"
#include "../PullGame.sp"
#include "../MeteorShower.sp"
#include "../Airstrike.sp"
#include "../Shockwave.sp"
#include "../Nuke.sp"
#include "../ToxicGas.sp"
#include "../AcidRain.sp"
#include "../FreezingCold.sp"
#include "../Darkness.sp"
#include "../GravityWaves.sp"
#include "../IceFloor.sp"
#include "../WindGusts.sp"
#include "../Tornado.sp"
#include "../Quicksand.sp"
#include "../MagnetPull.sp"
#include "../Hallucinations.sp"
#include "../Leech.sp"
#include "../JammedGuns.sp"
#include "../Butterfingers.sp"
#include "../ZombieFrenzy.sp"
#include "../Lightning.sp"
#include "../Earthquake.sp"
#include "../FloorIsLava.sp"
#include "../ZombieDrop.sp"
#include "../Blackout.sp"
#include "../BossZombie.sp"
#include "../Hero.sp"
#include "../LastStand.sp"
#include "../GhostZombies.sp"
#include "../HotPotato.sp"
#include "../Buddy.sp"
#include "../SimonSays.sp"
#include "../Trivia.sp"
#include "../HotSeat.sp"
#include "../RandomWeapons.sp"
#include "../EventRoulette.sp"

/*
* Called on plugin start, kindly put your new mode's OnPluginStart call here if you are willing to add a new mode.
*
* @noparams
*/
public void Forwards_OnPluginStart()
{
#if defined _FM_HealBeacon
    OnPluginStart_HealBeacon();
#endif

#if defined _FM_VIPMode
    OnPluginStart_VIPMode();
#endif

#if defined _FM_Fog
    OnPluginStart_Fog();
#endif

#if defined _FM_RLGL
    OnPluginStart_RLGL();
#endif

#if defined _FM_DoubleJump
    OnPluginStart_DoubleJump();
#endif

#if defined _FM_IC
    OnPluginStart_IC();
#endif

#if defined _FM_DamageGame
    OnPluginStart_DamageGame();
#endif

#if defined _FM_BlindMode
    OnPluginStart_BlindMode();
#endif

#if defined _FM_SlapMode
    OnPluginStart_SlapMode();
#endif

#if defined _FM_ChaosWeapons
    OnPluginStart_ChaosWeapons();
#endif

#if defined _FM_GunGame
    OnPluginStart_GunGame();
#endif

#if defined _FM_MathGame
    OnPluginStart_MathGame();
#endif

#if defined _FM_CrazyShop
    OnPluginStart_CrazyShop();
#endif

#if defined _FM_RealityShift
    OnPluginStart_RealityShift();
#endif

#if defined _FM_PullGame
    OnPluginStart_PullGame();
#endif

#if defined _FM_MeteorShower
    OnPluginStart_MeteorShower();
#endif

#if defined _FM_Airstrike
    OnPluginStart_Airstrike();
#endif

#if defined _FM_Shockwave
    OnPluginStart_Shockwave();
#endif

#if defined _FM_Nuke
    OnPluginStart_Nuke();
#endif

#if defined _FM_ToxicGas
    OnPluginStart_ToxicGas();
#endif

#if defined _FM_AcidRain
    OnPluginStart_AcidRain();
#endif

#if defined _FM_FreezingCold
    OnPluginStart_FreezingCold();
#endif

#if defined _FM_Darkness
    OnPluginStart_Darkness();
#endif

#if defined _FM_GravityWaves
    OnPluginStart_GravityWaves();
#endif

#if defined _FM_IceFloor
    OnPluginStart_IceFloor();
#endif

#if defined _FM_WindGusts
    OnPluginStart_WindGusts();
#endif

#if defined _FM_Tornado
    OnPluginStart_Tornado();
#endif

#if defined _FM_Quicksand
    OnPluginStart_Quicksand();
#endif

#if defined _FM_MagnetPull
    OnPluginStart_MagnetPull();
#endif

#if defined _FM_Hallucinations
    OnPluginStart_Hallucinations();
#endif

#if defined _FM_Leech
    OnPluginStart_Leech();
#endif

#if defined _FM_JammedGuns
    OnPluginStart_JammedGuns();
#endif

#if defined _FM_Butterfingers
    OnPluginStart_Butterfingers();
#endif

#if defined _FM_ZombieFrenzy
    OnPluginStart_ZombieFrenzy();
#endif

#if defined _FM_Lightning
    OnPluginStart_Lightning();
#endif

#if defined _FM_Earthquake
    OnPluginStart_Earthquake();
#endif

#if defined _FM_FloorIsLava
    OnPluginStart_FloorIsLava();
#endif

#if defined _FM_ZombieDrop
    OnPluginStart_ZombieDrop();
#endif

#if defined _FM_Blackout
    OnPluginStart_Blackout();
#endif

#if defined _FM_BossZombie
    OnPluginStart_BossZombie();
#endif

#if defined _FM_Hero
    OnPluginStart_Hero();
#endif

#if defined _FM_LastStand
    OnPluginStart_LastStand();
#endif

#if defined _FM_GhostZombies
    OnPluginStart_GhostZombies();
#endif

#if defined _FM_HotPotato
    OnPluginStart_HotPotato();
#endif

#if defined _FM_Buddy
    OnPluginStart_Buddy();
#endif

#if defined _FM_SimonSays
    OnPluginStart_SimonSays();
#endif

#if defined _FM_Trivia
    OnPluginStart_Trivia();
#endif

#if defined _FM_HotSeat
    OnPluginStart_HotSeat();
#endif

#if defined _FM_RandomWeapons
    OnPluginStart_RandomWeapons();
#endif

#if defined _FM_EventRoulette
    OnPluginStart_EventRoulette();
#endif
}

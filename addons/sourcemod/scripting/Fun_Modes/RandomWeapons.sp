/*
    (). FunModes V2:

    @file           RandomWeapons.sp
    @Usage          Functions for the RandomWeapons mode.
                    Every human gets a random weapon set (each their own, or everyone the same) on spawn, when the
                    mode is turned on and on reroll. While the set is locked, only kevlar, HE grenades and ammo can be
                    bought and no other guns picked up, except map items. Turns GunGame off.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_RandomWeapons

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "RandomWeapons"

static int g_iRandomWeaponsIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iRandomWeaponsIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define RW_CONVAR_SHARED 0
#define RW_CONVAR_KIND   1
#define RW_CONVAR_POOL   2
#define RW_CONVAR_LOCK   3
#define RW_CONVAR_TOGGLE 4

bool g_bRW_Shared;
int g_iRW_Kind;
int g_iRW_Pool;
bool g_bRW_Lock;
bool g_bRandomWeapons_Enabled;

public void OnPluginStart_RandomWeapons()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEAPONS;

	/* COMMANDS */
	static const char commands[][] =
	{
		"sm_fm_rw",
		"sm_fm_randomweapons"
	};

	for (int i = 0; i < sizeof(commands); i++)
		RegAdminCmd(commands[i], Cmd_RandomWeaponsToggle, ADMFLAG_CONVARS, "Turn Random Weapons On/Off");

	RegAdminCmd("sm_rw_settings", Cmd_RandomWeaponsSettings, ADMFLAG_CONVARS, "Open Random Weapons Settings Menu");
	RegConsoleCmd("sm_rwgun", Cmd_RandomWeaponsGun, "Random Weapons: get your weapons back");

	/* CONVARS */
	DECLARE_FM_CVAR(
		RW_CONVAR_SHARED, "sm_rw_shared",
		"0", "Everyone gets the same set (else one per player)",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		RW_CONVAR_KIND, "sm_rw_kind",
		"0", ("What the set holds [0 = primary + pistol, 1 = primary only, 2 = pistol only]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		RW_CONVAR_POOL, "sm_rw_pool",
		"0", ("Primary guns picked from [0 = all, 1 = rifles, 2 = SMGs, 3 = shotguns, 4 = snipers]"),
		("0,1,2,3,4"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		RW_CONVAR_LOCK, "sm_rw_lock",
		"1", "No buying or picking up other guns once the set is given",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		RW_CONVAR_TOGGLE, "sm_rw_enable",
		"1", "Enable/Disable Random Weapons Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= RW_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(RandomWeapons_OnConVarChange);

	THIS_MODE_INFO.enableIndex = RW_CONVAR_TOGGLE;

	RandomWeapons_OnPluginStart();
}

public void InitCvarsValues_RandomWeapons()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_bRW_Shared = _FUNMODES_CVAR_GET_VALUE(modeIndex, RW_CONVAR_SHARED, Bool);
	g_iRW_Kind = _FUNMODES_CVAR_GET_VALUE(modeIndex, RW_CONVAR_KIND, Int);
	g_iRW_Pool = _FUNMODES_CVAR_GET_VALUE(modeIndex, RW_CONVAR_POOL, Int);
	g_bRW_Lock = _FUNMODES_CVAR_GET_VALUE(modeIndex, RW_CONVAR_LOCK, Bool);
	g_bRandomWeapons_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, RW_CONVAR_TOGGLE, Bool);
}

void RandomWeapons_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case RW_CONVAR_SHARED:
			g_bRW_Shared = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case RW_CONVAR_KIND:
			g_iRW_Kind = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case RW_CONVAR_POOL:
			g_iRW_Pool = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case RW_CONVAR_LOCK:
			g_bRW_Lock = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case RW_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				RandomWeapons_Reset();
			}

			g_bRandomWeapons_Enabled = val;
		}
	}
}

public void OnMapEnd_RandomWeapons()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	RandomWeapons_Reset();
}

char g_sRW_Primaries[][] =
{
	"ak47", "m4a1", "galil", "famas", "sg552", "aug", "m249",
	"mac10", "tmp", "mp5navy", "ump45", "p90",
	"m3", "xm1014",
	"scout", "awp", "sg550", "g3sg1"
};

char g_sRW_PrimaryNames[][] =
{
	"AK-47", "M4A1", "Galil", "FAMAS", "SG 552", "AUG", "M249",
	"MAC-10", "TMP", "MP5", "UMP-45", "P90",
	"M3 Shotgun", "XM1014",
	"Scout", "AWP", "SG 550", "G3SG1"
};

/* 1 rifles, 2 SMGs, 3 shotguns, 4 snipers */
int g_iRW_PrimaryPool[] =
{
	1, 1, 1, 1, 1, 1, 1,
	2, 2, 2, 2, 2,
	3, 3,
	4, 4, 4, 4
};

char g_sRW_Pistols[][] = { "glock", "usp", "p228", "deagle", "elite", "fiveseven" };
char g_sRW_PistolNames[][] = { "Glock", "USP", "P228", "Desert Eagle", "Dual Elites", "Five-SeveN" };

#define RW_KIND_BOTH    0
#define RW_KIND_PRIMARY 1
#define RW_KIND_PISTOL  2

int g_iRW_SharedPrim = -1;          // this round's shared set
int g_iRW_SharedSec = -1;
bool g_bRW_Unrestricted;            // zr_unrestrict already sent this round
bool g_bRW_Has[MAXPLAYERS + 1];     // has a random set this life
int g_iRW_Prim[MAXPLAYERS + 1];
int g_iRW_Sec[MAXPLAYERS + 1];
float g_fRW_GunCooldown[MAXPLAYERS + 1];

void RandomWeapons_OnPluginStart()
{
	// Late load
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			OnClientPutInServer_RandomWeapons(i);
	}
}

public void OnClientPutInServer_RandomWeapons(int client)
{
	g_bRW_Has[client] = false;
	g_fRW_GunCooldown[client] = 0.0;
	SDKHook(client, SDKHook_WeaponCanUse, RandomWeapons_WeaponCanUse);
}

void RandomWeapons_Reset()
{
	g_iRW_SharedPrim = -1;
	g_iRW_SharedSec = -1;
	for (int i = 1; i <= MaxClients; i++)
		g_bRW_Has[i] = false;
}

void RandomWeapons_OnToggle(bool on)
{
	if (!on)
		return;

	// Both lock the weapons, they can't run together
	int gunGame = FunModes_FindMode("GunGame");
	if (gunGame != -1 && g_ModesInfo[gunGame].isOn)
		FunModes_SetModeState(gunGame, false);

	FunModes_HookEvent(g_bEvent_PlayerSpawn, "player_spawn", Event_PlayerSpawn);
	RandomWeapons_GiveAll();
}

public void Event_RoundStart_RandomWeapons()
{
	// The map may restrict again at round start
	g_bRW_Unrestricted = false;
	if (!THIS_MODE_INFO.isOn)
		return;

	if (g_bRW_Shared)
	{
		RandomWeapons_PickShared();

		char set[64];
		RandomWeapons_SetName(g_iRW_SharedPrim, g_iRW_SharedSec, set, sizeof(set));
		CPrintToChatAll("%s This round everyone gets: {olive}%s", THIS_MODE_INFO.tag, set);
	}
	else
		CPrintToChatAll("%s Random Weapons is on: everyone gets their own random set.", THIS_MODE_INFO.tag);
}

public void Event_PlayerSpawn_RandomWeapons(int client)
{
	if (!client)
		return;

	// The spawn weapons are fine until the set arrives
	g_bRW_Has[client] = false;
	if (THIS_MODE_INFO.isOn)
		CreateTimer(0.5, RandomWeapons_GiveTimer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

Action RandomWeapons_GiveTimer(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (THIS_MODE_INFO.isOn && IsHumanAlive(client))
	{
		RandomWeapons_Unrestrict();
		RandomWeapons_GiveFor(client, true);
	}

	return Plugin_Stop;
}

/* Lifts the zombie reloaded restrictions on every gun type the mode can give (once a round, run at once so the next GivePlayerItem isn't blocked) */
void RandomWeapons_Unrestrict()
{
	if (g_bRW_Unrestricted)
		return;

	g_bRW_Unrestricted = true;
	if (!CommandExists("zr_unrestrict"))
		return;

	ServerCommand("zr_unrestrict pistol shotgun smg rifle sniper m249");
	ServerExecute();
}

int RandomWeapons_RandomPrimary()
{
	int list[sizeof(g_sRW_Primaries)], count;
	for (int i = 0; i < sizeof(g_sRW_Primaries); i++)
	{
		if (g_iRW_Pool <= 0 || g_iRW_Pool > 4 || g_iRW_PrimaryPool[i] == g_iRW_Pool)
			list[count++] = i;
	}

	return list[GetRandomInt(0, count - 1)];
}

void RandomWeapons_RandomSet(int &prim, int &sec)
{
	prim = g_iRW_Kind == RW_KIND_PISTOL ? -1 : RandomWeapons_RandomPrimary();
	sec = g_iRW_Kind == RW_KIND_PRIMARY ? -1 : GetRandomInt(0, sizeof(g_sRW_Pistols) - 1);
}

void RandomWeapons_PickShared()
{
	RandomWeapons_RandomSet(g_iRW_SharedPrim, g_iRW_SharedSec);
}

void RandomWeapons_SetName(int prim, int sec, char[] buffer, int maxlen)
{
	if (prim >= 0 && sec >= 0)
		FormatEx(buffer, maxlen, "%s + %s", g_sRW_PrimaryNames[prim], g_sRW_PistolNames[sec]);
	else if (prim >= 0)
		strcopy(buffer, maxlen, g_sRW_PrimaryNames[prim]);
	else if (sec >= 0)
		strcopy(buffer, maxlen, g_sRW_PistolNames[sec]);
	else
		strcopy(buffer, maxlen, "nothing");
}

/* Empties a weapon slot, returns false if a map item is in it (left alone) */
bool RandomWeapons_StripSlot(int client, int slot)
{
	int weapon = GetPlayerWeaponSlot(client, slot);
	if (weapon == -1)
		return true;

	if (IsMapItem(weapon))
		return false;

	RemovePlayerItem(client, weapon);
	AcceptEntityInput(weapon, "Kill");
	return true;
}

void RandomWeapons_Give(int client, int prim, int sec, bool tell)
{
	// Mark first: the lock must already allow these weapons when they're handed over
	g_bRW_Has[client] = true;
	g_iRW_Prim[client] = prim;
	g_iRW_Sec[client] = sec;

	char className[32];
	if (RandomWeapons_StripSlot(client, CS_SLOT_PRIMARY) && prim >= 0)
	{
		FormatEx(className, sizeof(className), "weapon_%s", g_sRW_Primaries[prim]);
		GivePlayerItem(client, className);
	}

	if (RandomWeapons_StripSlot(client, CS_SLOT_SECONDARY) && sec >= 0)
	{
		FormatEx(className, sizeof(className), "weapon_%s", g_sRW_Pistols[sec]);
		GivePlayerItem(client, className);
	}

	if (tell)
	{
		char set[64];
		RandomWeapons_SetName(prim, sec, set, sizeof(set));
		CPrintToChat(client, "%s Your weapons: {olive}%s", THIS_MODE_INFO.tag, set);
	}
}

void RandomWeapons_GiveFor(int client, bool tell)
{
	if (!g_bRW_Shared)
	{
		int prim, sec;
		RandomWeapons_RandomSet(prim, sec);
		RandomWeapons_Give(client, prim, sec, tell);
		return;
	}

	if (g_iRW_SharedPrim == -1 && g_iRW_SharedSec == -1)
		RandomWeapons_PickShared();

	// The shared sets are announced to everyone at once
	RandomWeapons_Give(client, g_iRW_SharedPrim, g_iRW_SharedSec, false);
}

/* New sets for every living human right now */
void RandomWeapons_GiveAll()
{
	// The map may have restricted something since
	g_bRW_Unrestricted = false;
	RandomWeapons_Unrestrict();

	if (g_bRW_Shared)
	{
		RandomWeapons_PickShared();

		char set[64];
		RandomWeapons_SetName(g_iRW_SharedPrim, g_iRW_SharedSec, set, sizeof(set));
		CPrintToChatAll("%s Everyone gets: {olive}%s", THIS_MODE_INFO.tag, set);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanAlive(i))
			RandomWeapons_GiveFor(i, true);
	}
}

bool RandomWeapons_Locked(int client)
{
	return THIS_MODE_INFO.isOn && g_bRW_Lock && g_bRW_Has[client] && IsClientInGame(client) && ZR_IsClientHuman(client);
}

public void OnBuyCommand_RandomWeapons(int client, const char[] weapon, Action &result)
{
	if (!RandomWeapons_Locked(client))
		return;

	if (strcmp(weapon, "vest", false) == 0 || strcmp(weapon, "vesthelm", false) == 0 || strcmp(weapon, "hegrenade", false) == 0
		|| strcmp(weapon, "primammo", false) == 0 || strcmp(weapon, "secammo", false) == 0)
		return;

	CPrintToChat(client, "%s You keep your random weapons - only kevlar and HE grenades can be bought.", THIS_MODE_INFO.tag);
	result = Plugin_Handled;
}

Action RandomWeapons_WeaponCanUse(int client, int weapon)
{
	if (!RandomWeapons_Locked(client) || !IsValidEntity(weapon))
		return Plugin_Continue;

	char className[32];
	GetEntityClassname(weapon, className, sizeof(className));
	if (strcmp(className, "weapon_knife") == 0 || strcmp(className, "weapon_hegrenade") == 0 || IsMapItem(weapon))
		return Plugin_Continue;

	if (StrContains(className, "weapon_") == 0)
	{
		int prim = g_iRW_Prim[client], sec = g_iRW_Sec[client];
		if ((prim >= 0 && strcmp(className[7], g_sRW_Primaries[prim]) == 0) || (sec >= 0 && strcmp(className[7], g_sRW_Pistols[sec]) == 0))
			return Plugin_Continue;
	}

	return Plugin_Handled;
}

/* !rwgun: lost your weapons (dropped them, the map took them)? Get your set back */
Action Cmd_RandomWeaponsGun(int client, int args)
{
	if (!client || !IsHumanAlive(client))
	{
		CReplyToCommand(client, "%s You have to be an alive human for this.", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	if (!THIS_MODE_INFO.isOn)
	{
		CReplyToCommand(client, "%s Random Weapons is not on.", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	float now = GetGameTime();
	if (now < g_fRW_GunCooldown[client])
	{
		CReplyToCommand(client, "%s Wait {olive}%d {lightgreen}more seconds.", THIS_MODE_INFO.tag, RoundToCeil(g_fRW_GunCooldown[client] - now));
		return Plugin_Handled;
	}

	g_fRW_GunCooldown[client] = now + 15.0;

	if (g_bRW_Has[client])
		RandomWeapons_Give(client, g_iRW_Prim[client], g_iRW_Sec[client], true);
	else
		RandomWeapons_GiveFor(client, true);

	return Plugin_Handled;
}

public Action Cmd_RandomWeaponsToggle(int client, int args)
{
	if (!g_bRandomWeapons_Enabled)
	{
		CReplyToCommand(client, "%s Random Weapons is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	RandomWeapons_Reset();

	CPrintToChatAll("%s Random Weapons is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Everyone gets random weapons!", THIS_MODE_INFO.tag);

	RandomWeapons_OnToggle(THIS_MODE_INFO.isOn);

	return Plugin_Handled;
}

/* RandomWeapons Settings */
public Action Cmd_RandomWeaponsSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_RandomWeaponsSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("reroll", "Reroll everyone's weapons now", (THIS_MODE_INFO.isOn) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_RandomWeaponsSettings(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				DisplayModeInfo(param1, g_iPreviousModeIndex[param1]);
		}

		case MenuAction_Select:
		{
			char info[16];
			menu.GetItem(param2, info, sizeof(info));

			if (strcmp(info, "reroll") == 0)
			{
				RandomWeapons_GiveAll();
				Cmd_RandomWeaponsSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}

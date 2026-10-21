// Random Weapons module of eventmodes.sp.
// eventmodes.sp calls RW_PluginStart / RW_MapStart / RW_MapEnd / RW_ClientPutInServer from its own forwards.
//
// Every human gets a random weapon set (each a different one, or everyone the same) on spawn, when the
// mode is turned on, and on "Reroll". While the set is locked, humans can only buy kevlar, HE grenades
// and ammo, and can't pick up other guns - except map items (weapons with a targetname), so ZE map
// items keep working. Maps can restrict weapons through Zombie Reloaded (zr_restrict), which would
// block the given guns, so the gun types are unrestricted right before sets are handed out.

#if defined _em_weapons_included
 #endinput
#endif
#define _em_weapons_included

#define RW_TAG "\x07" ... "FF8C00[Random Weapons]\x01 "   // kept apart: \x would eat the hex digits

char g_RwPrimaries[][] =
{
	"ak47", "m4a1", "galil", "famas", "sg552", "aug", "m249",
	"mac10", "tmp", "mp5navy", "ump45", "p90",
	"m3", "xm1014",
	"scout", "awp", "sg550", "g3sg1"
};
char g_RwPrimaryNames[][] =
{
	"AK-47", "M4A1", "Galil", "FAMAS", "SG 552", "AUG", "M249",
	"MAC-10", "TMP", "MP5", "UMP-45", "P90",
	"M3 Shotgun", "XM1014",
	"Scout", "AWP", "SG 550", "G3SG1"
};
int g_RwPrimaryPool[] =    // 1 rifles, 2 SMGs, 3 shotguns, 4 snipers
{
	1, 1, 1, 1, 1, 1, 1,
	2, 2, 2, 2, 2,
	3, 3,
	4, 4, 4, 4
};
char g_RwPools[][] = { "All", "Rifles", "SMGs", "Shotguns", "Snipers" };

char g_RwPistols[][] = { "glock", "usp", "p228", "deagle", "elite", "fiveseven" };
char g_RwPistolNames[][] = { "Glock", "USP", "P228", "Desert Eagle", "Dual Elites", "Five-SeveN" };

enum
{
	RW_BOTH = 0,      // primary + pistol
	RW_PRIMARY,       // primary only
	RW_PISTOL,        // pistol only
	RW_KINDS
}
char g_RwKinds[][] = { "Primary + pistol", "Primary only", "Pistol only" };

bool g_RwOn;
bool g_RwShared;           // everyone gets the same set (else one per player)
bool g_RwLock = true;      // no buying / picking up other guns once the set is given
int g_RwKind = RW_BOTH;
int g_RwPool;              // index into g_RwPools
int g_RwSharedPrim = -1;   // this round's shared set
int g_RwSharedSec = -1;

bool g_RwUnrestricted;          // zr_unrestrict already sent this round
bool g_RwHas[MAXPLAYERS + 1];   // has a random set this life
int g_RwPrim[MAXPLAYERS + 1];
int g_RwSec[MAXPLAYERS + 1];

// ---------------------------------------------------------------- lifecycle

void RW_PluginStart()
{
	HookEvent("round_start", RW_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", RW_PlayerSpawn);
	for (int i = 1; i <= MaxClients; i++)   // late load
		if (IsClientInGame(i))
			RW_ClientPutInServer(i);
}

void RW_MapStart()
{
	RW_Reset();
}

// Never carries over to the next map.
void RW_MapEnd()
{
	RW_Reset();
}

void RW_Reset()
{
	g_RwOn = false;
	g_RwSharedPrim = -1;
	g_RwSharedSec = -1;
	for (int i = 1; i <= MaxClients; i++)
		g_RwHas[i] = false;
}

void RW_ClientPutInServer(int client)
{
	g_RwHas[client] = false;
	SDKHook(client, SDKHook_WeaponCanUse, RW_WeaponCanUse);
}

public void RW_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_RwUnrestricted = false;   // the map may restrict again at round start
	if (!g_RwOn)
		return;
	if (g_RwShared)
	{
		RW_PickShared();
		char set[64];
		RW_SetName(g_RwSharedPrim, g_RwSharedSec, set, sizeof(set));
		PrintToChatAll(RW_TAG ... "This round everyone gets: \x07" ... "FF8C00%s", set);
	}
	else
		PrintToChatAll(RW_TAG ... "Random Weapons is on: everyone gets their own random set.");
}

public void RW_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client == 0)
		return;
	g_RwHas[client] = false;   // spawn weapons are fine until the set arrives
	if (g_RwOn)
		CreateTimer(0.5, RW_Timer_Give, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
}

public Action RW_Timer_Give(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (g_RwOn && IsHuman(client))
	{
		RW_Unrestrict();
		RW_GiveFor(client, true);
	}
	return Plugin_Stop;
}

// Lift Zombie Reloaded restrictions on every gun type the mode can give (once a round; the map's own
// round-start restrictions have run by the time the first set is given 0.5 s after spawn). Run at once,
// not queued, so the very next GivePlayerItem isn't blocked. ZR resets restrictions on map change.
void RW_Unrestrict()
{
	if (g_RwUnrestricted)
		return;
	g_RwUnrestricted = true;
	if (!CommandExists("zr_unrestrict"))
		return;
	ServerCommand("zr_unrestrict pistol shotgun smg rifle sniper m249");
	ServerExecute();
}

// ---------------------------------------------------------------- loadouts

int RW_RandomPrimary()
{
	int list[sizeof(g_RwPrimaries)], n = 0;
	for (int i = 0; i < sizeof(g_RwPrimaries); i++)
		if (g_RwPool == 0 || g_RwPrimaryPool[i] == g_RwPool)
			list[n++] = i;
	return list[GetRandomInt(0, n - 1)];
}

int RW_RandomPistol()
{
	return GetRandomInt(0, sizeof(g_RwPistols) - 1);
}

void RW_RandomSet(int &prim, int &sec)
{
	prim = g_RwKind == RW_PISTOL ? -1 : RW_RandomPrimary();
	sec = g_RwKind == RW_PRIMARY ? -1 : RW_RandomPistol();
}

void RW_PickShared()
{
	RW_RandomSet(g_RwSharedPrim, g_RwSharedSec);
}

void RW_SetName(int prim, int sec, char[] buf, int len)
{
	if (prim >= 0 && sec >= 0)
		Format(buf, len, "%s + %s", g_RwPrimaryNames[prim], g_RwPistolNames[sec]);
	else if (prim >= 0)
		strcopy(buf, len, g_RwPrimaryNames[prim]);
	else if (sec >= 0)
		strcopy(buf, len, g_RwPistolNames[sec]);
	else
		strcopy(buf, len, "nothing");
}

// Map items are weapons with a targetname: never take or block those.
bool RW_IsMapItem(int weapon)
{
	return EM_IsMapItem(weapon);   // EntWatch when loaded, else "has a name on the map"
}

// Empties a weapon slot; returns false if a map item is in it (left alone).
bool RW_StripSlot(int client, int slot)
{
	int weapon = GetPlayerWeaponSlot(client, slot);
	if (weapon == -1)
		return true;
	if (RW_IsMapItem(weapon))
		return false;
	RemovePlayerItem(client, weapon);
	AcceptEntityInput(weapon, "Kill");
	return true;
}

void RW_Give(int client, int prim, int sec, bool tell)
{
	// Mark first: the lock must already allow these weapons when they're handed over.
	g_RwHas[client] = true;
	g_RwPrim[client] = prim;
	g_RwSec[client] = sec;

	char cls[32];
	if (RW_StripSlot(client, CS_SLOT_PRIMARY) && prim >= 0)
	{
		Format(cls, sizeof(cls), "weapon_%s", g_RwPrimaries[prim]);
		GivePlayerItem(client, cls);
	}
	if (RW_StripSlot(client, CS_SLOT_SECONDARY) && sec >= 0)
	{
		Format(cls, sizeof(cls), "weapon_%s", g_RwPistols[sec]);
		GivePlayerItem(client, cls);
	}
	if (tell)
	{
		char set[64];
		RW_SetName(prim, sec, set, sizeof(set));
		PrintToChat(client, RW_TAG ... "Your weapons: \x07" ... "FF8C00%s", set);
	}
}

void RW_GiveFor(int client, bool tell)
{
	if (g_RwShared)
	{
		if (g_RwSharedPrim == -1 && g_RwSharedSec == -1)
			RW_PickShared();
		RW_Give(client, g_RwSharedPrim, g_RwSharedSec, false);   // shared sets are announced to everyone at once
	}
	else
	{
		int prim, sec;
		RW_RandomSet(prim, sec);
		RW_Give(client, prim, sec, tell);
	}
}

// New sets for every living human right now.
void RW_GiveAll()
{
	g_RwUnrestricted = false;   // the map may have restricted something since
	RW_Unrestrict();
	if (g_RwShared)
	{
		RW_PickShared();
		char set[64];
		RW_SetName(g_RwSharedPrim, g_RwSharedSec, set, sizeof(set));
		PrintToChatAll(RW_TAG ... "Everyone gets: \x07" ... "FF8C00%s", set);
	}
	for (int i = 1; i <= MaxClients; i++)
		if (IsHuman(i))
			RW_GiveFor(i, true);
}

// ---------------------------------------------------------------- the lock

bool RW_Locked(int client)
{
	return g_RwOn && g_RwLock && g_RwHas[client] && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_CT;
}

public Action CS_OnBuyCommand(int client, const char[] weapon)
{
	if (!RW_Locked(client) && !GG_Locked(client))
		return Plugin_Continue;
	char item[32];
	strcopy(item, sizeof(item), weapon);
	StringToLower(item);
	if (StrEqual(item, "vest") || StrEqual(item, "vesthelm") || StrEqual(item, "hegrenade")
		|| StrEqual(item, "primammo") || StrEqual(item, "secammo"))
		return Plugin_Continue;
	if (GG_Locked(client))
		PrintToChat(client, GG_TAG ... "Earn your guns by damaging zombies - only kevlar and HE grenades can be bought.");
	else
		PrintToChat(client, RW_TAG ... "You keep your random weapons - only kevlar and HE grenades can be bought.");
	return Plugin_Handled;
}

public Action RW_WeaponCanUse(int client, int weapon)
{
	bool rw = RW_Locked(client), gg = GG_Locked(client);
	if ((!rw && !gg) || !IsValidEntity(weapon))
		return Plugin_Continue;
	char cls[32];
	GetEntityClassname(weapon, cls, sizeof(cls));
	if (StrEqual(cls, "weapon_knife") || StrEqual(cls, "weapon_hegrenade") || RW_IsMapItem(weapon))
		return Plugin_Continue;
	if (gg && GG_IsLevelWeapon(client, cls))
		return Plugin_Continue;
	if (rw && StrContains(cls, "weapon_") == 0)
	{
		int prim = g_RwPrim[client], sec = g_RwSec[client];
		if ((prim >= 0 && StrEqual(cls[7], g_RwPrimaries[prim])) || (sec >= 0 && StrEqual(cls[7], g_RwPistols[sec])))
			return Plugin_Continue;
	}
	return Plugin_Handled;
}

// ---------------------------------------------------------------- menu

void RW_Stop()
{
	g_RwOn = false;
}

void RwMenu(int client)
{
	Menu menu = new Menu(RwHandler);
	char title[192], line[64];
	if (!g_RwOn)
		strcopy(title, sizeof(title), "Random Weapons - OFF");
	else if (g_RwShared && (g_RwSharedPrim != -1 || g_RwSharedSec != -1))
	{
		char set[64];
		RW_SetName(g_RwSharedPrim, g_RwSharedSec, set, sizeof(set));
		Format(title, sizeof(title), "Random Weapons - ON\nThis round: %s", set);
	}
	else
		strcopy(title, sizeof(title), "Random Weapons - ON");
	Format(title, sizeof(title), "%s\nSettings apply on the next reroll / round\n ", title);
	menu.SetTitle(title);

	menu.AddItem("toggle", g_RwOn ? "Turn Random Weapons OFF" : "Turn Random Weapons ON (gives sets now)");
	menu.AddItem("reroll", "Reroll everyone's weapons now", g_RwOn ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Sets: %s", g_RwShared ? "same for everyone" : "different per player");
	menu.AddItem("shared", line);
	Format(line, sizeof(line), "Weapons: %s", g_RwKinds[g_RwKind]);
	menu.AddItem("kind", line);
	Format(line, sizeof(line), "Primary pool: %s", g_RwPools[g_RwPool]);
	menu.AddItem("pool", line, g_RwKind == RW_PISTOL ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	Format(line, sizeof(line), "Buying: %s", g_RwLock ? "only kevlar + HE" : "allowed");
	menu.AddItem("lock", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int RwHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		ModeBack(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "toggle"))
		{
			g_RwOn = !g_RwOn;
			if (g_RwOn)
			{
				if (GG_IsOn())
				{
					GG_Stop();
					PrintToChatAll(GG_TAG ... "Gun Game was turned off for Random Weapons.");
				}
				PrintToChatAll(RW_TAG ... "%N turned Random Weapons ON%s.", client,
					g_RwLock ? " - only kevlar and HE grenades can be bought" : "");
				RW_GiveAll();
			}
			else
				PrintToChatAll(RW_TAG ... "%N turned Random Weapons OFF - buying is back to normal.", client);
			LogAction(client, -1, "\"%L\" turned random weapons %s", client, g_RwOn ? "on" : "off");
		}
		else if (StrEqual(info, "reroll"))
		{
			PrintToChatAll(RW_TAG ... "%N rerolled everyone's weapons!", client);
			RW_GiveAll();
		}
		else if (StrEqual(info, "shared"))
			g_RwShared = !g_RwShared;
		else if (StrEqual(info, "kind"))
			g_RwKind = (g_RwKind + 1) % RW_KINDS;
		else if (StrEqual(info, "pool"))
			g_RwPool = (g_RwPool + 1) % sizeof(g_RwPools);
		else if (StrEqual(info, "lock"))
			g_RwLock = !g_RwLock;
		RwMenu(client);
	}
	return 0;
}

bool RW_IsOn()
{
	return g_RwOn;
}

// ---------------------------------------------------------------- Zombie Reloaded's market

// While Random Weapons (with its buy lock) or Gun Game is on, Zombie Reloaded's weapon market (!zmarket)
// is switched off, so nobody pays for a gun the lock would throw on the floor. Put back as it was after.
bool g_ZMarketBlocked;
int g_ZMarketOld = -1;
int g_ZMarketRebuyOld = -1;

void ZMarket_SetQuietly(const char[] name, int value)
{
	ConVar cv = FindConVar(name);
	if (cv == null)
		return;
	int flags = cv.Flags;
	cv.Flags = flags & ~FCVAR_NOTIFY;
	cv.IntValue = value;
	cv.Flags = flags;
}

int ZMarket_Get(const char[] name)
{
	ConVar cv = FindConVar(name);
	return cv == null ? -1 : cv.IntValue;
}

// Called every 0.2 s (modes.sp) and when the plugin unloads (block = false).
void ZMarket_Sync(bool allowBlock = true)
{
	bool want = allowBlock && ((RW_IsOn() && g_RwLock) || GG_IsOn());
	if (want == g_ZMarketBlocked)
		return;
	if (want)
	{
		g_ZMarketOld = ZMarket_Get("zr_weapons_zmarket");
		g_ZMarketRebuyOld = ZMarket_Get("zr_weapons_zmarket_rebuy");
		if (g_ZMarketOld == -1)
			return;   // Zombie Reloaded isn't running
		ZMarket_SetQuietly("zr_weapons_zmarket", 0);
		ZMarket_SetQuietly("zr_weapons_zmarket_rebuy", 0);
		g_ZMarketBlocked = true;
	}
	else
	{
		if (g_ZMarketOld != -1)
			ZMarket_SetQuietly("zr_weapons_zmarket", g_ZMarketOld);
		if (g_ZMarketRebuyOld != -1)
			ZMarket_SetQuietly("zr_weapons_zmarket_rebuy", g_ZMarketRebuyOld);
		g_ZMarketBlocked = false;
	}
}

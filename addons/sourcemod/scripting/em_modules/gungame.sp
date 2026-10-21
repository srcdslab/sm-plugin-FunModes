// Gun Game module of eventmodes.sp.
// eventmodes.sp calls GG_PluginStart; modes.sp calls GG_Tick (every second) and GG_Stop;
// weapons.sp asks GG_Locked / GG_IsLevelWeapon for the shared buy and pickup lock.
//
// Every human starts on a pistol. Damage dealt to zombies fills a bar; a full bar moves you up to the
// next gun on the ladder. Each gun has its own damage to reach (weak pistols less, an M249 more),
// changeable in game and saved to configs/eventmodes/gungame.cfg, with an overall multiplier on top.
// After the last gun you prestige: back to the first pistol, prestige +1 and
// an HE grenade. Progress is kept between rounds (or reset every round) and resets on map change.
// While Gun Game is on, only kevlar and HE grenades can be bought and no other guns picked up
// (map items still can). Can't run together with Random Weapons.

#if defined _em_gungame_included
 #endinput
#endif
#define _em_gungame_included

#define GG_PISTOLS 6                                 // the first 6 rungs are pistols (secondary slot)

char g_GgLadder[][] =
{
	"glock", "usp", "p228", "fiveseven", "elite", "deagle",
	"tmp", "mac10", "mp5navy", "ump45", "p90",
	"m3", "xm1014",
	"galil", "famas", "ak47", "m4a1", "sg552", "aug",
	"scout", "awp", "sg550", "g3sg1", "m249"
};
char g_GgNames[][] =
{
	"Glock", "USP", "P228", "Five-SeveN", "Dual Elites", "Desert Eagle",
	"TMP", "MAC-10", "MP5", "UMP-45", "P90",
	"M3 Shotgun", "XM1014",
	"Galil", "FAMAS", "AK-47", "M4A1", "SG 552", "AUG",
	"Scout", "AWP", "SG 550", "G3SG1", "M249"
};

#define GG_CONFIG "configs/eventmodes/gungame.cfg"

// Damage to zombies needed to move on from each gun, before the multiplier. Weak or slow guns need
// less, strong automatic ones more. Changed in game (Gun Game -> Damage needed per gun) and saved to
// GG_CONFIG; these are only the defaults.
// ZE zombies soak up a lot of damage: these match what FunModes used (pistols 1200 ... M249 8000).
int g_GgDefaultNeed[] =
{
	1200, 1200, 1200, 1200, 1200, 1200,
	4200, 4200, 4200, 4200, 4200,
	2200, 2200,
	3800, 3800, 3800, 3800, 3800, 3800,
	2500, 3000, 5000, 5000, 8000
};
int g_GgNeedSteps[] = { 300, 500, 800, 1000, 1200, 1500, 2000, 2200, 2500, 3000, 3800, 4200, 5000, 6000, 8000, 10000 };

enum { GG_R_HE = 0, GG_R_CHOOSE, GG_REWARD_MODES }
char g_GgRewardModeNames[][] = { "HE grenade", "they choose (HE, freeze grenade or speed)" };
int g_GgSpeedTimeSteps[] = { 30, 60, 100 };
int g_GgScaleSteps[] = { 25, 50, 75, 100, 150, 200, 300 };   // % of each gun's number

bool g_GgOn;
bool g_GgKeep = true;       // progress kept between rounds (else everyone restarts each round)
int g_GgNeed[sizeof(g_GgLadder)];   // per gun, loaded from GG_CONFIG
int g_GgScale = 100;        // % applied to every gun's number
int g_GgLevel[MAXPLAYERS + 1];
int g_GgDamage[MAXPLAYERS + 1];     // damage towards the next level
int g_GgPrestige[MAXPLAYERS + 1];
bool g_GgArmed[MAXPLAYERS + 1];     // got their gun-game gun this life (the lock starts then)
int g_GgPendingHE[MAXPLAYERS + 1];  // prestige grenades to hand over
int g_GgRewardOwed[MAXPLAYERS + 1]; // prestige rewards still to choose
float g_GgSpeedUntil[MAXPLAYERS + 1];   // speed reward runs until then
float g_GgGunCooldown[MAXPLAYERS + 1];  // !emgun
int g_GgRewardMode = GG_R_CHOOSE;
int g_GgSpeedTime = 60;     // seconds the speed reward lasts
Handle g_HudGG;

// ---------------------------------------------------------------- lifecycle

void GG_PluginStart()
{
	g_HudGG = EM_HudSync();
	HookEvent("player_hurt", GG_PlayerHurt);
	HookEvent("player_spawn", GG_PlayerSpawn);
	HookEvent("round_start", GG_RoundStart, EventHookMode_PostNoCopy);
	RegConsoleCmd("sm_emgun", Cmd_EmGun, "Gun Game / Random Weapons: get your gun back");
	GG_LoadNeeds();
}

// Speed reward for finishing a cycle, stacked with other modes by physics.sp.
float GG_SpeedMult(int client)
{
	return g_GgOn && g_GgSpeedUntil[client] > GetGameTime() && GetClientTeam(client) == CS_TEAM_CT ? 1.3 : 1.0;
}

// !emgun: lost your gun (dropped it, map took it)? Get the Gun Game gun or your Random Weapons set back.
public Action Cmd_EmGun(int client, int args)
{
	if (client == 0 || !IsHuman(client))
	{
		ReplyToCommand(client, "[Event] You have to be an alive human for this.");
		return Plugin_Handled;
	}
	if (!g_GgOn && !RW_IsOn())
	{
		ReplyToCommand(client, "[Event] Neither Gun Game nor Random Weapons is on.");
		return Plugin_Handled;
	}
	float now = GetGameTime();
	if (now < g_GgGunCooldown[client])
	{
		ReplyToCommand(client, "[Event] Wait %d more seconds.", RoundToCeil(g_GgGunCooldown[client] - now));
		return Plugin_Handled;
	}
	g_GgGunCooldown[client] = now + 15.0;
	if (g_GgOn)
		GG_GiveLevel(client, false);
	else
		RW_GiveFor(client, true);
	return Plugin_Handled;
}

// Finished a cycle: pick a reward (20 s to choose, then it's an HE grenade).
void GG_RewardMenu(int client)
{
	Menu menu = new Menu(GGRewardHandler);
	menu.SetTitle("GUN GAME - CYCLE COMPLETE!\nPick your reward:\n ");
	menu.AddItem("he", "HE grenade");
	menu.AddItem("smoke", "Freeze grenade (smoke)");
	char line[48];
	Format(line, sizeof(line), "Speed boost for %d seconds", g_GgSpeedTime);
	menu.AddItem("speed", line);
	menu.ExitButton = false;
	menu.Display(client, 20);
}

public int GGRewardHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select || action == MenuAction_Cancel)
	{
		if (client <= 0 || client > MaxClients || !IsClientInGame(client) || g_GgRewardOwed[client] <= 0)
			return 0;
		g_GgRewardOwed[client]--;
		char info[8] = "he";
		if (action == MenuAction_Select)
			menu.GetItem(item, info, sizeof(info));
		if (!IsHuman(client))
			return 0;
		if (StrEqual(info, "smoke"))
		{
			GivePlayerItem(client, "weapon_smokegrenade");
			PrintToChat(client, GG_TAG ... "Freeze grenade granted!");
		}
		else if (StrEqual(info, "speed"))
		{
			g_GgSpeedUntil[client] = GetGameTime() + float(g_GgSpeedTime);
			PrintToChat(client, GG_TAG ... "Speed boost for %d seconds!", g_GgSpeedTime);
		}
		else
		{
			GivePlayerItem(client, "weapon_hegrenade");
			PrintToChat(client, GG_TAG ... "HE grenade granted!");
		}
		if (g_GgRewardOwed[client] > 0)
			GG_RewardMenu(client);   // prestiged more than once at a time
	}
	return 0;
}

// ---------------------------------------------------------------- damage needed per gun

// Damage needed to move on from this gun, with the multiplier.
int GG_Need(int level)
{
	int need = g_GgNeed[level] * g_GgScale / 100;
	return need < 1 ? 1 : need;
}

void GG_DefaultNeeds()
{
	for (int i = 0; i < sizeof(g_GgLadder); i++)
		g_GgNeed[i] = g_GgDefaultNeed[i];
}

// Defaults first, then whatever the saved file has (guns missing from it keep their default).
bool GG_LoadNeeds()
{
	GG_DefaultNeeds();
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), GG_CONFIG);
	KeyValues kv = new KeyValues("GunGame");
	bool ok = kv.ImportFromFile(path);
	if (ok)
	{
		for (int i = 0; i < sizeof(g_GgLadder); i++)
		{
			int need = kv.GetNum(g_GgLadder[i], g_GgNeed[i]);
			if (need > 0)
				g_GgNeed[i] = need;
		}
		g_GgScale = kv.GetNum("multiplier_percent", g_GgScale);
	}
	delete kv;
	return ok;
}

bool GG_SaveNeeds()
{
	char path[PLATFORM_MAX_PATH], dir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, dir, sizeof(dir), "configs/eventmodes");
	if (!DirExists(dir))
		CreateDirectory(dir, 511);
	BuildPath(Path_SM, path, sizeof(path), GG_CONFIG);
	KeyValues kv = new KeyValues("GunGame");
	kv.SetNum("multiplier_percent", g_GgScale);
	for (int i = 0; i < sizeof(g_GgLadder); i++)
		kv.SetNum(g_GgLadder[i], g_GgNeed[i]);
	bool ok = kv.ExportToFile(path);
	delete kv;
	return ok;
}

bool GG_IsOn()
{
	return g_GgOn;
}

void GG_ResetPlayer(int client)
{
	g_GgLevel[client] = 0;
	g_GgDamage[client] = 0;
	g_GgPrestige[client] = 0;
	g_GgArmed[client] = false;
	g_GgPendingHE[client] = 0;
	g_GgRewardOwed[client] = 0;
	g_GgSpeedUntil[client] = 0.0;
}

void GG_ResetAll()
{
	for (int i = 1; i <= MaxClients; i++)
		GG_ResetPlayer(i);
}

void GG_ClientPutInServer(int client)
{
	GG_ResetPlayer(client);
}

void GG_Stop()
{
	g_GgOn = false;
	GG_ResetAll();
}

public void GG_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_GgOn)
		return;
	if (!g_GgKeep)
		GG_ResetAll();
	PrintToChatAll(GG_TAG ... "Gun Game is on: damage zombies to level up your gun! Lost your gun? Type !emgun");
}

public void GG_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client == 0)
		return;
	g_GgArmed[client] = false;   // spawn weapons are fine until their gun arrives
	if (g_GgOn)
		CreateTimer(0.5, GG_Timer_Give, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
}

public Action GG_Timer_Give(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (g_GgOn && IsHuman(client))
		GG_GiveLevel(client, false);
	return Plugin_Stop;
}

// ---------------------------------------------------------------- weapons

bool GG_Locked(int client)
{
	return g_GgOn && g_GgArmed[client] && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_CT;
}

// cls is a classname like "weapon_ak47".
bool GG_IsLevelWeapon(int client, const char[] cls)
{
	return StrContains(cls, "weapon_") == 0 && StrEqual(cls[7], g_GgLadder[g_GgLevel[client]]);
}

void GG_GiveLevel(int client, bool tell)
{
	// Mark first: the lock must already allow this gun when it's handed over.
	g_GgArmed[client] = true;
	RW_Unrestrict();   // maps can restrict weapons through Zombie Reloaded

	// One gun at a time: both gun slots are emptied (map items stay).
	bool primaryFree = RW_StripSlot(client, CS_SLOT_PRIMARY);
	bool pistolFree = RW_StripSlot(client, CS_SLOT_SECONDARY);
	int level = g_GgLevel[client];
	if (level < GG_PISTOLS ? pistolFree : primaryFree)
	{
		char cls[32];
		Format(cls, sizeof(cls), "weapon_%s", g_GgLadder[level]);
		GivePlayerItem(client, cls);
		FakeClientCommandEx(client, "use %s", cls);
	}
	for (; g_GgPendingHE[client] > 0; g_GgPendingHE[client]--)
		GivePlayerItem(client, "weapon_hegrenade");

	if (tell)
		PrintToChat(client, GG_TAG ... "Level up! \x07" ... "C080FF%s\x01 (level %d/%d)", g_GgNames[level], level + 1, sizeof(g_GgLadder));
}

// ---------------------------------------------------------------- levelling

public void GG_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_GgOn || !g_RoundLive)
		return;
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (victim == 0 || attacker == 0 || attacker == victim || !IsHuman(attacker) || GetClientTeam(victim) != CS_TEAM_T)
		return;

	g_GgDamage[attacker] += event.GetInt("dmg_health");
	bool levelled = false;
	while (g_GgDamage[attacker] >= GG_Need(g_GgLevel[attacker]))
	{
		g_GgDamage[attacker] -= GG_Need(g_GgLevel[attacker]);
		g_GgLevel[attacker]++;
		levelled = true;
		if (g_GgLevel[attacker] >= sizeof(g_GgLadder))
		{
			g_GgLevel[attacker] = 0;
			g_GgPrestige[attacker]++;
			if (g_GgRewardMode == GG_R_CHOOSE)
				g_GgRewardOwed[attacker]++;
			else
				g_GgPendingHE[attacker]++;
			PrintToChatAll(GG_TAG ... "\x07" ... "C080FF%N\x01 PRESTIGED! (prestige %d) - back to the Glock, plus a reward.",
				attacker, g_GgPrestige[attacker]);
		}
	}
	// Swap the gun next frame, not in the middle of the damage being dealt.
	if (levelled)
		RequestFrame(GG_FrameGive, GetClientUserId(attacker));
}

public void GG_FrameGive(int userid)
{
	int client = GetClientOfUserId(userid);
	if (g_GgOn && IsHuman(client))
	{
		GG_GiveLevel(client, true);
		if (g_GgRewardOwed[client] > 0)
			GG_RewardMenu(client);
	}
}

void GG_Tick()
{
	if (!g_GgOn)
		return;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHuman(i) || IsFakeClient(i))
			continue;
		int level = g_GgLevel[i];
		char prestige[24];
		if (g_GgPrestige[i] > 0)
			Format(prestige, sizeof(prestige), " | prestige %d", g_GgPrestige[i]);
		SetHudTextParams(-1.0, 0.88, 1.1, 192, 128, 255, 255, 0, 0.0, 0.0, 0.0);
		EM_ShowHud(i, g_HudGG, "Gun Game: %s (level %d/%d) | %d/%d damage%s",
			g_GgNames[level], level + 1, sizeof(g_GgLadder), g_GgDamage[i], GG_Need(level), prestige);
	}
}

// The best player for the menu: 0 if nobody has levelled yet.
int GG_Leader()
{
	int best = 0, bestScore = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		int score = (g_GgPrestige[i] * sizeof(g_GgLadder) + g_GgLevel[i]) * 100000 + g_GgDamage[i];
		if (score > bestScore)
		{
			best = i;
			bestScore = score;
		}
	}
	return best;
}

// ---------------------------------------------------------------- menu

void GGMenu(int client)
{
	Menu menu = new Menu(GGHandler);
	char title[160], line[64];
	if (!g_GgOn)
		strcopy(title, sizeof(title), "Gun Game - OFF\n ");
	else
	{
		int leader = GG_Leader();
		if (leader == 0)
			strcopy(title, sizeof(title), "Gun Game - ON\nNobody has levelled up yet\n ");
		else
			Format(title, sizeof(title), "Gun Game - ON\nLeader: %N - %s, prestige %d\n ",
				leader, g_GgNames[g_GgLevel[leader]], g_GgPrestige[leader]);
	}
	menu.SetTitle(title);

	menu.AddItem("toggle", g_GgOn ? "Turn Gun Game OFF" : "Turn Gun Game ON (everyone starts on a Glock)");
	menu.AddItem("needs", "Damage needed per gun...");
	Format(line, sizeof(line), "Overall multiplier: x%.2f", float(g_GgScale) / 100.0);
	menu.AddItem("scale", line);
	Format(line, sizeof(line), "Progress: %s", g_GgKeep ? "kept between rounds" : "reset every round");
	menu.AddItem("keep", line);
	Format(line, sizeof(line), "Cycle reward: %s", g_GgRewardModeNames[g_GgRewardMode]);
	menu.AddItem("reward", line);
	Format(line, sizeof(line), "Speed reward lasts: %d s", g_GgSpeedTime);
	menu.AddItem("speedtime", line, g_GgRewardMode == GG_R_CHOOSE ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("reset", "Reset everyone to the Glock now", g_GgOn ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void GG_GiveAll()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsHuman(i))
			GG_GiveLevel(i, false);
}

public int GGHandler(Menu menu, MenuAction action, int client, int item)
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
			if (g_GgOn)
			{
				GG_Stop();
				PrintToChatAll(GG_TAG ... "%N turned Gun Game OFF - buying is back to normal.", client);
			}
			else
			{
				if (RW_IsOn())
				{
					RW_Stop();
					PrintToChatAll(RW_TAG ... "Random Weapons was turned off for Gun Game.");
				}
				GG_ResetAll();
				g_GgOn = true;
				PrintToChatAll(GG_TAG ... "%N turned Gun Game ON! Damage zombies to level up through %d guns - prestige gives an HE grenade.",
					client, sizeof(g_GgLadder));
				GG_GiveAll();
			}
			LogAction(client, -1, "\"%L\" turned gun game %s", client, g_GgOn ? "on" : "off");
		}
		else if (StrEqual(info, "needs"))
		{
			GGNeedsMenu(client, 0);
			return 0;
		}
		else if (StrEqual(info, "scale"))
			g_GgScale = NextInt(g_GgScaleSteps, sizeof(g_GgScaleSteps), g_GgScale);
		else if (StrEqual(info, "keep"))
			g_GgKeep = !g_GgKeep;
		else if (StrEqual(info, "reward"))
			g_GgRewardMode = (g_GgRewardMode + 1) % GG_REWARD_MODES;
		else if (StrEqual(info, "speedtime"))
			g_GgSpeedTime = NextInt(g_GgSpeedTimeSteps, sizeof(g_GgSpeedTimeSteps), g_GgSpeedTime);
		else if (StrEqual(info, "reset"))
		{
			GG_ResetAll();
			GG_GiveAll();
			PrintToChatAll(GG_TAG ... "%N reset Gun Game - everyone is back on the Glock.", client);
		}
		GGMenu(client);
	}
	return 0;
}

// Every gun with its damage needed; picking one steps its number up (wrapping round). Save writes the
// numbers to GG_CONFIG so they survive map changes and restarts.
void GGNeedsMenu(int client, int firstItem)
{
	Menu menu = new Menu(GGNeedsHandler);
	char title[160], line[64], key[8];
	Format(title, sizeof(title), "Damage needed per gun\nPick a gun to raise its number (wraps round)\nMultiplier x%.2f is applied on top\n ",
		float(g_GgScale) / 100.0);
	menu.SetTitle(title);
	menu.AddItem("save", "Save these numbers");
	menu.AddItem("load", "Reload the saved numbers");
	menu.AddItem("defaults", "Back to the default numbers");
	for (int i = 0; i < sizeof(g_GgLadder); i++)
	{
		IntToString(i, key, sizeof(key));
		if (g_GgScale == 100)
			Format(line, sizeof(line), "%d. %s: %d", i + 1, g_GgNames[i], g_GgNeed[i]);
		else
			Format(line, sizeof(line), "%d. %s: %d (= %d)", i + 1, g_GgNames[i], g_GgNeed[i], GG_Need(i));
		menu.AddItem(key, line);
	}
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int GGNeedsHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		GGMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char key[16];
		menu.GetItem(item, key, sizeof(key));
		if (StrEqual(key, "save"))
		{
			if (GG_SaveNeeds())
			{
				PrintToChat(client, GG_TAG ... "Saved to addons/sourcemod/%s.", GG_CONFIG);
				LogAction(client, -1, "\"%L\" saved the gun game damage numbers", client);
			}
			else
				PrintToChat(client, GG_TAG ... "Couldn't write addons/sourcemod/%s - check the folder's permissions.", GG_CONFIG);
		}
		else if (StrEqual(key, "load"))
			PrintToChat(client, GG_LoadNeeds() ? (GG_TAG ... "Saved numbers loaded.") : (GG_TAG ... "No saved file yet - using the defaults."));
		else if (StrEqual(key, "defaults"))
		{
			GG_DefaultNeeds();
			g_GgScale = 100;
			PrintToChat(client, GG_TAG ... "Default numbers back (not saved until you press Save).");
		}
		else
		{
			int i = StringToInt(key);
			g_GgNeed[i] = NextInt(g_GgNeedSteps, sizeof(g_GgNeedSteps), g_GgNeed[i]);
		}
		GGNeedsMenu(client, GetMenuSelectionPosition());   // stay on the same page
	}
	return 0;
}

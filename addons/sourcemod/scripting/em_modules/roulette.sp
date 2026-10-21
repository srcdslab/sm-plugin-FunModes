// Event Roulette module of eventmodes.sp. Included last: it switches the other modes on and off.
// modes.sp calls Roulette_RoundStart, Roulette_RoundEnd and Roulette_Stop.
//
// A second into each round, it picks random modes from the pool the admins chose and turns them on for
// that round only; at round end it turns off what it turned on. With a shuffle timer set, it also
// re-picks during the round (every N seconds, or a random time in a range). Modes an admin switched on
// by hand are never touched, and never picked while they're on.
// modes.sp also calls Roulette_Tick every second.

#if defined _em_roulette_included
 #endinput
#endif
#define _em_roulette_included

#define RO_TAG "\x07" ... "FF60FF[Event Roulette]\x01 "   // kept apart: \x would eat the hex digits

enum
{
	RO_VIP = 0,
	RO_HB,
	RO_RW,
	RO_GG,
	RO_POTATO,
	RO_BUDDY,
	RO_LIGHTNING,
	RO_QUIZ,
	RO_RLGL,
	RO_SIMON,
	RO_FOG,
	RO_TELEPORT,
	RO_INVERT,
	RO_BLACKOUT,
	RO_GHOST,
	RO_BOSS,
	RO_QUAKE,
	RO_HERO,
	RO_LASTSTAND,
	RO_LAVA,
	RO_DROP,
	RO_TRIVIA,
	RO_HOTSEAT,
	RO_H_MT,
	RO_H_AS,
	RO_H_SW,
	RO_H_NK,
	RO_H_TG,
	RO_H_RD,
	RO_H_AR,
	RO_H_FC,
	RO_H_SD,
	RO_H_GW,
	RO_H_IF,
	RO_H_WG,
	RO_H_TN,
	RO_H_QS,
	RO_H_MG,
	RO_H_HL,
	RO_H_LC,
	RO_H_JG,
	RO_H_BF,
	RO_H_ZF,
	RO_DOUBLEJUMP,
	RO_COUNT
}
char g_RoNames[][] =
{
	"VIP Mode", "Heal Beacon", "Random Weapons", "Gun Game", "Hot Potato", "Buddy System",
	"Lightning Strikes", "Math Quiz", "Red Light, Green Light", "Simon Says", "Random fog",
	"Teleport Shuffle", "Inverted Controls", "Blackout / Flashbang", "Ghost Zombies", "Boss Zombie", "Earthquake",
	"Hero", "Last Stand", "Floor is Lava", "Zombie Drop", "Trivia", "Hot Seat",
	"Meteor Shower", "Airstrike", "Shockwave", "Nuke Countdown", "Toxic Gas", "Radiation", "Acid Rain", "Freezing Cold", "Sudden Darkness", "Gravity Waves", "Ice Floor", "Wind Gusts", "Tornado", "Quicksand", "Magnet Pull", "Hallucinations", "Leech", "Jammed Guns", "Butterfingers", "Zombie Frenzy", "Double Jump"
};

// The !em menu key of each mode, in the same order (for "sm_em <mode> on|off").
char g_RoKeys[][] =
{
	"vip", "hb", "rw", "gg", "potato", "buddy", "lightning", "quiz", "rlgl", "simon", "fog", "teleport",
	"invert", "blackout", "ghost", "boss", "quake", "hero", "laststand", "lava", "drop", "trivia", "hotseat", "meteor",
	"airstrike", "shockwave", "nuke", "gas", "radiation", "acid", "cold", "darkness", "gravity", "ice", "wind", "tornado",
	"quicksand", "magnet", "halluc", "leech", "jam", "butter", "frenzy", "doublejump"
};

bool g_RoOn;
int g_RoPerRound = 1;
bool g_RoNoRepeat = true;       // don't pick last round's modes again
bool g_RoPool[RO_COUNT] = { true, ... };
bool g_RoActive[RO_COUNT];      // turned on by the roulette this round
bool g_RoLast[RO_COUNT];        // what it picked last time
char g_RoThisRound[192];

// Shuffle timer choices: seconds from min to max (equal = fixed), 0 = once per round.
int g_RoShuffleMin[] = { 0, 30, 45, 60, 30, 90, 120, 60, 180, 300 };
int g_RoShuffleMax[] = { 0, 30, 45, 60, 60, 90, 120, 120, 180, 300 };
int g_RoShuffle;                // index into the choices above
float g_RoNextShuffle;          // game time of the next re-pick, 0 = none planned

bool RO_IsModeOn(int m)
{
	switch (m)
	{
		case RO_VIP: return g_VipOn;
		case RO_HB: return g_HbOn;
		case RO_RW: return g_RwOn;
		case RO_GG: return g_GgOn;
		case RO_POTATO: return g_PtOn;
		case RO_BUDDY: return g_BdOn;
		case RO_LIGHTNING: return g_LtOn;
		case RO_QUIZ: return g_MqOn;
		case RO_RLGL: return g_RlglOn;
		case RO_SIMON: return g_SsOn;
		case RO_FOG: return g_Active;
		case RO_TELEPORT: return g_TsOn;
		case RO_INVERT: return g_IcOn;
		case RO_BLACKOUT: return g_BoOn;
		case RO_GHOST: return g_GzOn;
		case RO_BOSS: return g_BzOn;
		case RO_QUAKE: return g_EqOn;
		case RO_HERO: return g_HrOn;
		case RO_LASTSTAND: return g_LsOn;
		case RO_LAVA: return g_FlOn;
		case RO_DROP: return g_ZdOn;
		case RO_TRIVIA: return g_TvOn;
		case RO_HOTSEAT: return g_HsOn;
		case RO_H_MT: return MT_IsOn();
		case RO_H_AS: return AS_IsOn();
		case RO_H_SW: return SW_IsOn();
		case RO_H_NK: return NK_IsOn();
		case RO_H_TG: return TG_IsOn();
		case RO_H_RD: return RD_IsOn();
		case RO_H_AR: return AR_IsOn();
		case RO_H_FC: return FC_IsOn();
		case RO_H_SD: return SD_IsOn();
		case RO_H_GW: return GW_IsOn();
		case RO_H_IF: return IF_IsOn();
		case RO_H_WG: return WG_IsOn();
		case RO_H_TN: return TN_IsOn();
		case RO_H_QS: return QS_IsOn();
		case RO_H_MG: return MG_IsOn();
		case RO_H_HL: return HL_IsOn();
		case RO_H_LC: return LC_IsOn();
		case RO_H_JG: return JG_IsOn();
		case RO_H_BF: return BF_IsOn();
		case RO_H_ZF: return ZF_IsOn();
		case RO_DOUBLEJUMP: return DJ_IsOn();
	}
	return false;
}

// A random fog preset name from the config; false if there are none.
bool RO_RandomPreset(char[] name, int len)
{
	if (g_Config == null)
		return false;
	int count = 0;
	g_Config.Rewind();
	if (g_Config.JumpToKey("Presets") && g_Config.GotoFirstSubKey())
	{
		do
			count++;
		while (g_Config.GotoNextKey());
	}
	g_Config.Rewind();
	if (count == 0)
		return false;

	int pick = GetRandomInt(0, count - 1), k = 0;
	bool found = false;
	if (g_Config.JumpToKey("Presets") && g_Config.GotoFirstSubKey())
	{
		do
		{
			if (k++ == pick)
			{
				g_Config.GetSectionName(name, len);
				found = true;
				break;
			}
		}
		while (g_Config.GotoNextKey());
	}
	g_Config.Rewind();
	return found;
}

// Switch one mode on or off the same way its menu does. `label` gets a note for the announcement.
void RO_Set(int m, bool on, char[] label, int len)
{
	strcopy(label, len, g_RoNames[m]);
	switch (m)
	{
		case RO_VIP:
		{
			g_VipOn = on;
			ClearVips();
		}
		case RO_HB:
		{
			g_HbOn = on;
			ClearBeacons();
		}
		case RO_RW:
		{
			if (on)
			{
				if (g_GgOn)
					GG_Stop();
				g_RwOn = true;
				RW_GiveAll();
			}
			else
				RW_Stop();
		}
		case RO_GG:
		{
			if (on)
			{
				if (g_RwOn)
					RW_Stop();
				GG_ResetAll();
				g_GgOn = true;
				GG_GiveAll();
			}
			else
				GG_Stop();
		}
		case RO_POTATO:
		{
			if (on)
			{
				g_PtOn = true;
				g_PtNextAt = 0.0;
			}
			else
				Potato_Stop();
		}
		case RO_BUDDY:
		{
			Buddy_Stop();
			g_BdOn = on;
		}
		case RO_LIGHTNING:
		{
			g_LtOn = on;
			g_LtNext = 0.0;
		}
		case RO_QUIZ:
		{
			MQ_Stop();
			g_MqOn = on;
		}
		case RO_RLGL:
		{
			RLGL_Stop();
			g_RlglOn = on;
		}
		case RO_SIMON:
		{
			Simon_Stop();
			g_SsOn = on;
		}
		case RO_FOG:
		{
			if (on)
			{
				char preset[32];
				if (RO_RandomPreset(preset, sizeof(preset)) && ApplyPreset(0, preset, 3.0, true))
					Format(label, len, "Fog: %s", preset);
			}
			else if (g_Active)
				Restore();
		}
		case RO_TELEPORT:
		{
			TS_Stop();
			g_TsOn = on;
		}
		case RO_INVERT:
		{
			IC_Stop();
			g_IcOn = on;
		}
		case RO_BLACKOUT:
		{
			BO_Stop();
			g_BoOn = on;
		}
		case RO_GHOST:
		{
			if (on)
				g_GzOn = true;
			else
				GZ_Stop();
		}
		case RO_BOSS:
		{
			BZ_Stop();
			g_BzOn = on;
		}
		case RO_QUAKE:
		{
			if (on)
				EQ_Enable();
			else
				EQ_Stop();
		}
		case RO_HERO:
		{
			Hero_Stop();
			g_HrOn = on;
		}
		case RO_LASTSTAND:
		{
			LS_Stop();
			g_LsOn = on;
		}
		case RO_LAVA:
		{
			FL_Stop();
			g_FlOn = on;
		}
		case RO_DROP:
		{
			ZD_Stop();
			g_ZdOn = on;
		}
		case RO_TRIVIA:
		{
			TV_Stop();
			g_TvOn = on;
		}
		case RO_HOTSEAT:
		{
			HS_Stop();
			g_HsOn = on;
		}
		case RO_H_MT:
			MT_Set(on);
		case RO_H_AS:
			AS_Set(on);
		case RO_H_SW:
			SW_Set(on);
		case RO_H_NK:
			NK_Set(on);
		case RO_H_TG:
			TG_Set(on);
		case RO_H_RD:
			RD_Set(on);
		case RO_H_AR:
			AR_Set(on);
		case RO_H_FC:
			FC_Set(on);
		case RO_H_SD:
			SD_Set(on);
		case RO_H_GW:
			GW_Set(on);
		case RO_H_IF:
			IF_Set(on);
		case RO_H_WG:
			WG_Set(on);
		case RO_H_TN:
			TN_Set(on);
		case RO_H_QS:
			QS_Set(on);
		case RO_H_MG:
			MG_Set(on);
		case RO_H_HL:
			HL_Set(on);
		case RO_H_LC:
			LC_Set(on);
		case RO_H_JG:
			JG_Set(on);
		case RO_H_BF:
			BF_Set(on);
		case RO_H_ZF:
			ZF_Set(on);
		case RO_DOUBLEJUMP:
			DJ_Set(on);
	}
}

void RO_TurnOffMine()
{
	char unused[64];
	for (int m = 0; m < RO_COUNT; m++)
	{
		if (!g_RoActive[m])
			continue;
		g_RoActive[m] = false;
		if (RO_IsModeOn(m))
			RO_Set(m, false, unused, sizeof(unused));
	}
	g_RoThisRound[0] = '\0';
}

bool RO_Candidate(int m, bool allowRepeat)
{
	if (!g_RoPool[m] || RO_IsModeOn(m))
		return false;
	if (m == RO_FOG && g_Config == null)
		return false;
	return allowRepeat || !g_RoNoRepeat || !g_RoLast[m];
}

void RO_Spin()
{
	RO_TurnOffMine();

	int list[RO_COUNT], n = 0;
	for (int m = 0; m < RO_COUNT; m++)
		if (RO_Candidate(m, false))
			list[n++] = m;
	if (n == 0)   // everything was picked last round: allow repeats rather than nothing
		for (int m = 0; m < RO_COUNT; m++)
			if (RO_Candidate(m, true))
				list[n++] = m;
	if (n == 0)
	{
		PrintToChatAll(RO_TAG ... "No modes left to pick - check the roulette pool.");
		return;
	}
	for (int i = n - 1; i > 0; i--)   // shuffle
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}

	char label[64];
	int picked = 0;
	for (int k = 0; k < n && picked < g_RoPerRound; k++)
	{
		int m = list[k];
		if ((m == RO_RW && g_RoActive[RO_GG]) || (m == RO_GG && g_RoActive[RO_RW]))
			continue;   // they can't run together
		RO_Set(m, true, label, sizeof(label));
		g_RoActive[m] = true;
		Format(g_RoThisRound, sizeof(g_RoThisRound), "%s%s%s", g_RoThisRound, picked == 0 ? "" : " + ", label);
		picked++;
	}
	for (int m = 0; m < RO_COUNT; m++)
		g_RoLast[m] = g_RoActive[m];

	RO_PlanShuffle();
	char next[48];
	RO_NextText(next, sizeof(next));
	PrintToChatAll(RO_TAG ... "Now: \x07" ... "FF60FF%s\x01!%s", g_RoThisRound, next);
	PrintCenterTextAll("EVENT ROULETTE: %s", g_RoThisRound);
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 160);
	LogMessage("Event roulette picked: %s", g_RoThisRound);
}

// ---------------------------------------------------------------- shuffle timer

void RO_PlanShuffle()
{
	if (g_RoShuffle == 0)
		g_RoNextShuffle = 0.0;
	else
		g_RoNextShuffle = GetGameTime() + float(GetRandomInt(g_RoShuffleMin[g_RoShuffle], g_RoShuffleMax[g_RoShuffle]));
}

// " Next shuffle in 45 s." for the announcement, or nothing when it's once per round.
void RO_NextText(char[] buf, int len)
{
	buf[0] = '\0';
	if (g_RoNextShuffle > 0.0)
		Format(buf, len, " Next shuffle in %d s.", RoundToCeil(g_RoNextShuffle - GetGameTime()));
}

void RO_ShuffleName(int index, char[] buf, int len)
{
	int lo = g_RoShuffleMin[index], hi = g_RoShuffleMax[index];
	if (lo == 0)
	{
		strcopy(buf, len, "once per round");
		return;
	}
	char a[16], b[16];
	RO_Duration(lo, a, sizeof(a));
	RO_Duration(hi, b, sizeof(b));
	if (lo == hi)
		Format(buf, len, "every %s", a);
	else
		Format(buf, len, "every %s to %s (random)", a, b);
}

void RO_Duration(int seconds, char[] buf, int len)
{
	if (seconds >= 60 && seconds % 60 == 0)
		Format(buf, len, "%d min", seconds / 60);
	else
		Format(buf, len, "%d s", seconds);
}

void Roulette_Tick()
{
	if (!g_RoOn || !g_RoundLive || g_RoNextShuffle == 0.0)
		return;
	int left = RoundToCeil(g_RoNextShuffle - GetGameTime());
	if (left > 0 && left <= 3)
		PrintCenterTextAll("Event shuffle in %d...", left);
	if (left <= 0)
		RO_Spin();
}

// ---------------------------------------------------------------- round

bool Roulette_IsOn()
{
	return g_RoOn;
}

void Roulette_Stop()
{
	RO_TurnOffMine();
	g_RoOn = false;
	g_RoNextShuffle = 0.0;
	for (int m = 0; m < RO_COUNT; m++)
		g_RoLast[m] = false;
}

void Roulette_RoundStart()
{
	if (g_RoOn)
		CreateTimer(1.0, RO_Timer_Spin, g_RoundNum, TIMER_FLAG_NO_MAPCHANGE);   // after everyone has spawned
}

public Action RO_Timer_Spin(Handle timer, int round)
{
	if (g_RoOn && g_RoundLive && round == g_RoundNum)
		RO_Spin();
	return Plugin_Stop;
}

void Roulette_RoundEnd()
{
	RO_TurnOffMine();
	g_RoNextShuffle = 0.0;   // the next round starts with a fresh spin
}

// ---------------------------------------------------------------- menu

void RouletteMenu(int client)
{
	Menu menu = new Menu(RouletteHandler);
	char title[256], line[64];
	if (!g_RoOn)
		strcopy(title, sizeof(title), "Event Roulette - OFF\n ");
	else if (g_RoThisRound[0] == '\0')
		strcopy(title, sizeof(title), "Event Roulette - ON\nSpins a second into each round\n ");
	else
	{
		char next[48];
		RO_NextText(next, sizeof(next));
		Format(title, sizeof(title), "Event Roulette - ON\nNow: %s\n%s\n ", g_RoThisRound, next);
	}
	menu.SetTitle(title);

	menu.AddItem("toggle", g_RoOn ? "Turn Event Roulette OFF" : "Turn Event Roulette ON (spins now)");
	menu.AddItem("spin", "Spin again now", (g_RoOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	char shuffle[48];
	RO_ShuffleName(g_RoShuffle, shuffle, sizeof(shuffle));
	Format(line, sizeof(line), "Shuffle: %s", shuffle);
	menu.AddItem("shuffle", line);
	Format(line, sizeof(line), "Modes at a time: %d", g_RoPerRound);
	menu.AddItem("per", line);
	Format(line, sizeof(line), "Previous modes: %s", g_RoNoRepeat ? "not picked again" : "can repeat");
	menu.AddItem("repeat", line);
	int inPool = 0;
	for (int m = 0; m < RO_COUNT; m++)
		if (g_RoPool[m])
			inPool++;
	Format(line, sizeof(line), "Modes in the roulette... (%d/%d)", inPool, RO_COUNT);
	menu.AddItem("pool", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int RouletteHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		MainMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "toggle"))
		{
			if (g_RoOn)
			{
				Roulette_Stop();
				PrintToChatAll(RO_TAG ... "%N turned Event Roulette OFF.", client);
			}
			else
			{
				g_RoOn = true;
				PrintToChatAll(RO_TAG ... "%N turned Event Roulette ON - a random event every round!", client);
				if (g_RoundLive)
					RO_Spin();
			}
			LogAction(client, -1, "\"%L\" turned event roulette %s", client, g_RoOn ? "on" : "off");
		}
		else if (StrEqual(info, "spin"))
			RO_Spin();
		else if (StrEqual(info, "shuffle"))
		{
			g_RoShuffle = (g_RoShuffle + 1) % sizeof(g_RoShuffleMin);
			// Takes effect now: the timer starts from this moment (or stops for "once per round").
			if (g_RoOn && g_RoundLive && g_RoThisRound[0] != '\0')
				RO_PlanShuffle();
			else
				g_RoNextShuffle = 0.0;
		}
		else if (StrEqual(info, "per"))
			g_RoPerRound = g_RoPerRound >= 3 ? 1 : g_RoPerRound + 1;
		else if (StrEqual(info, "repeat"))
			g_RoNoRepeat = !g_RoNoRepeat;
		else if (StrEqual(info, "pool"))
		{
			PoolMenu(client, 0);
			return 0;
		}
		RouletteMenu(client);
	}
	return 0;
}

void PoolMenu(int client, int firstItem)
{
	Menu menu = new Menu(PoolHandler);
	menu.SetTitle("Modes the roulette can pick\n ");
	char key[8], line[64];
	for (int m = 0; m < RO_COUNT; m++)
	{
		IntToString(m, key, sizeof(key));
		Format(line, sizeof(line), "[%s] %s", g_RoPool[m] ? "ON" : "  -  ", g_RoNames[m]);
		menu.AddItem(key, line);
	}
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int PoolHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		RouletteMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char key[8];
		menu.GetItem(item, key, sizeof(key));
		int m = StringToInt(key);
		g_RoPool[m] = !g_RoPool[m];
		PoolMenu(client, GetMenuSelectionPosition());
	}
	return 0;
}

// ---------------------------------------------------------------- console / rcon: sm_em <mode> [on|off]

int RO_FromKey(const char[] key)
{
	for (int m = 0; m < RO_COUNT && m < sizeof(g_RoKeys); m++)
		if (StrEqual(key, g_RoKeys[m], false))
			return m;
	return -1;
}

// "on"/"1" -> 1, "off"/"0" -> 0, anything else -1.
int EM_OnOff(const char[] arg)
{
	if (StrEqual(arg, "on", false) || StrEqual(arg, "1"))
		return 1;
	if (StrEqual(arg, "off", false) || StrEqual(arg, "0"))
		return 0;
	return -1;
}

void EM_Console(int client, int args)
{
	char key[32], arg[8];
	GetCmdArg(1, key, sizeof(key));
	StringToLower(key);

	if (StrEqual(key, "list"))
	{
		char line[256], entry[40];
		line[0] = '\0';
		for (int m = 0; m < RO_COUNT; m++)
		{
			Format(entry, sizeof(entry), "%s%s", g_RoKeys[m], RO_IsModeOn(m) ? " [ON]" : "");
			if (strlen(line) + strlen(entry) > 180)
			{
				ReplyToCommand(client, "[Event] %s", line);
				line[0] = '\0';
			}
			if (line[0] != '\0')
				StrCat(line, sizeof(line), ", ");
			StrCat(line, sizeof(line), entry);
		}
		ReplyToCommand(client, "[Event] %s", line);
		ReplyToCommand(client, "[Event] Also: roulette, stop, save, load. Usage: sm_em <mode> [on|off] (no on/off = switch)");
		return;
	}
	if (StrEqual(key, "save"))
	{
		ReplyToCommand(client, "[Event] %s", Settings_Save() ? "Settings saved." : "Couldn't write the settings file.");
		return;
	}
	if (StrEqual(key, "load"))
	{
		ReplyToCommand(client, "[Event] %s", Settings_Load() ? "Saved settings loaded." : "No saved settings yet.");
		return;
	}
	if (StrEqual(key, "stop"))
	{
		StopAllModes();
		PrintToChatAll("\x07" ... "FFD700[Event]\x01 %N stopped all event modes.", client);
		LogAction(client, -1, "\"%L\" stopped all event modes (command)", client);
		return;
	}

	int want = -1;
	if (args >= 2)
	{
		GetCmdArg(2, arg, sizeof(arg));
		want = EM_OnOff(arg);
		if (want == -1)
		{
			ReplyToCommand(client, "[Event] Usage: sm_em <mode> [on|off]");
			return;
		}
	}

	if (StrEqual(key, "roulette"))
	{
		bool on = want == -1 ? !g_RoOn : want == 1;
		if (on && !g_RoOn)
		{
			g_RoOn = true;
			if (g_RoundLive)
				RO_Spin();
		}
		else if (!on && g_RoOn)
			Roulette_Stop();
		PrintToChatAll(RO_TAG ... "%N turned Event Roulette %s.", client, on ? "ON" : "OFF");
		LogAction(client, -1, "\"%L\" turned event roulette %s (command)", client, on ? "on" : "off");
		return;
	}

	int m = RO_FromKey(key);
	if (m == -1)
	{
		ReplyToCommand(client, "[Event] Unknown mode '%s' - type sm_em list", key);
		return;
	}
	bool on = want == -1 ? !RO_IsModeOn(m) : want == 1;
	char label[64];
	RO_Set(m, on, label, sizeof(label));
	PrintToChatAll("\x07" ... "FFD700[Event]\x01 %N turned %s %s.", client, label, on ? "ON" : "OFF");
	LogAction(client, -1, "\"%L\" turned %s %s (command)", client, label, on ? "on" : "off");
}

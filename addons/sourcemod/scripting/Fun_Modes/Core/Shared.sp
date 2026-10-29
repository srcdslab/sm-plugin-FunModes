/*
    (). FunModes V2:

    @file           Core/Shared.sp
    @Usage          Helpers shared by the modes: round tracking, the tick and check timers,
                    hazards (rings, beams, explosions), stacked speed and gravity, and the hud slots.
*/

#pragma semicolon 1
#pragma newdecls required

#define Explode_Sound       "weapons/hegrenade/explode3.wav"

/* Round Tracking */
bool g_bRoundLive = true;       // false between round end and the next round start (or once the humans are slain)
bool g_bZombiesSeen;            // the first zombies are out this round
int g_iRoundNum;                // bumped every round, so delayed actions can tell they are stale
bool g_bCheckRunning;           // FunModes_RunCheck is running (cleared every map and round, in case a check errored)

int g_iExplosionSprite = -1;

Handle g_hCheckTimer = null;
Handle g_hTickTimer = null;

/* At least one mode is on. With none on the plugin is idle: no timers, and the per-player hooks return at once */
bool g_bFunModesActive;

/* Stacked Speed And Gravity: each mode reports a multiplier, the product is applied on top of the player's own value.
   Several modes can slow or speed up the same player (Boss, Quicksand, Last Stand, RLGL...) without overwriting each other,
   and when they stop the player gets their own speed back (the zombie class speed), not a hard 1.0.
   0.0 in the arrays means "this mode doesn't change it": the globals start at 0, so nothing needs filling in first */
#define SPEED_PROP "m_flLaggedMovementValue"

float g_fSpeedMult[MAXPLAYERS + 1][MAX_MODES_NUM];
float g_fGravityMult[MAXPLAYERS + 1][MAX_MODES_NUM];

bool g_bSpeedTouched[MAXPLAYERS + 1];
float g_fSpeedBase[MAXPLAYERS + 1];
float g_fSpeedSet[MAXPLAYERS + 1];
bool g_bGravityTouched[MAXPLAYERS + 1];
float g_fGravityBase[MAXPLAYERS + 1];
float g_fGravitySet[MAXPLAYERS + 1];

/* Hud Slots: one per mode text, so the modes don't overwrite each other */
#define MAX_HUD_SLOTS 32

/* Where each mode's text sits on the screen (y), so two modes never draw on top of each other */
#define HUD_Y_BOSS        0.020    // Boss Zombie (2 lines)
#define HUD_Y_VIP         0.090    // VIP Mode
#define HUD_Y_HEALBEACON  0.125    // Heal Beacon
#define HUD_Y_POTATO      0.160    // Hot Potato
#define HUD_Y_BUDDY       0.195    // Buddy System
#define HUD_Y_HERO        0.230    // Hero
#define HUD_Y_TRIVIA      0.265    // Trivia (2 lines)
#define HUD_Y_SIMON       0.335    // Simon Says
#define HUD_Y_IC          0.370    // Inverted Controls
#define HUD_Y_RLGL        0.405    // Red Light, Green Light
#define HUD_Y_NUKE        0.440    // Nuke Countdown (2 lines)
#define HUD_Y_ACID        0.510    // Acid Rain
#define HUD_Y_COLD        0.545    // Freezing Cold
#define HUD_Y_WIND        0.580    // Wind Gusts
#define HUD_Y_LAVA        0.615    // Floor is Lava
#define HUD_Y_MATHGAME    0.650    // MathGame (2 lines)
#define HUD_Y_CHAOS       0.720    // Chaos Weapons
#define HUD_Y_PULLGAME    0.755    // Pull Game
#define HUD_Y_LEECH       0.790    // Leech
#define HUD_Y_GUNGAME     0.825    // GunGame

Handle g_hHudSlots[MAX_HUD_SLOTS];
int g_iHudSlotsCount;

void Shared_OnPluginStart()
{
	FunModes_HookEvent(g_bEvent_RoundStart, "round_start", Event_RoundStart);
	FunModes_HookEvent(g_bEvent_RoundEnd, "round_end", Event_RoundEnd);
}

void Shared_OnMapStart()
{
	g_iExplosionSprite = PrecacheModel("sprites/zerogxplode.spr");
	PrecacheSound(Explode_Sound, true);

	g_bRoundLive = true;
	g_bZombiesSeen = false;
	g_bCheckRunning = false;

	// The timers of the last map died with it (TIMER_FLAG_NO_MAPCHANGE): they start again with the first mode turned on
	g_hCheckTimer = null;
	g_hTickTimer = null;
	FunModes_UpdateActive();
}

/* Every mode is turned on and off through here (CHANGE_MODE_INFO) */
void FunModes_SetModeOn(int modeIndex, bool on)
{
	g_ModesInfo[modeIndex].isOn = on;
	FunModes_UpdateActive();
}

/* Starts the check and tick timers when the first mode is on. They stop by themselves when none is on any more */
void FunModes_UpdateActive()
{
	bool active = false;
	for (int i = 0; i < g_iLastModeIndex && !active; i++)
		active = g_ModesInfo[i].isOn;

	g_bFunModesActive = active;
	if (!active)
		return;

	if (g_hCheckTimer == null)
		g_hCheckTimer = CreateTimer(0.2, Shared_CheckTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	if (g_hTickTimer == null)
		g_hTickTimer = CreateTimer(1.0, Shared_TickTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void Shared_OnMapEnd()
{
	// TIMER_FLAG_NO_MAPCHANGE already killed them
	g_hCheckTimer = null;
	g_hTickTimer = null;
}

void Shared_RoundStart()
{
	g_bRoundLive = true;
	g_bZombiesSeen = false;
	g_bCheckRunning = false;
	g_iRoundNum++;
}

void Shared_RoundEnd()
{
	g_bRoundLive = false;
}

/* Runs the OnCheck forward right away, used when someone dies or gets infected */
void FunModes_RunCheck()
{
	// A mode killing someone in its OnCheck fires player_death, which calls this again: don't run the checks inside themselves
	if (g_bCheckRunning)
		return;

	// Nothing is on: nothing to check (the first check once a mode is on catches up on the zombies)
	if (!g_bFunModesActive)
		return;

	g_bCheckRunning = true;

	bool zombiesNow = ZombiesAlive();

	if (g_bRoundLive)
	{
		DECLARE_FM_FORWARD_ON_PARAM1(OnCheck, zombiesNow)
	}

	if (zombiesNow)
		g_bZombiesSeen = true;

	g_bCheckRunning = false;
}

Action Shared_CheckTimer(Handle timer)
{
	FunModes_RunCheck();
	Physics_Apply();

	// The last mode was turned off: once every player has their own speed and gravity back, the timer stops
	if (!g_bFunModesActive && !Physics_AnyTouched())
	{
		g_hCheckTimer = null;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

Action Shared_TickTimer(Handle timer)
{
	if (!g_bFunModesActive)
	{
		g_hTickTimer = null;
		return Plugin_Stop;
	}

	if (!g_bRoundLive)
		return Plugin_Continue;

	DECLARE_FM_FORWARD_ON_PARAM0(OnTick)
	return Plugin_Continue;
}

/* ---------------------------------------------------------------- players */

/* A living human (zombie reloaded decides) */
stock bool IsHumanAlive(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return false;

	return ZR_IsClientHuman(client);
}

stock bool ZombiesAlive()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && ZR_IsClientZombie(i))
			return true;
	}

	return false;
}

/* Alive and on a team the hazard hits: humans, plus zombies when everyone is true */
stock bool HazardHits(int client, bool everyone)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return false;

	return ZR_IsClientHuman(client) || (everyone && ZR_IsClientZombie(client));
}

/* For hazards that come every N seconds once the zombies are out: true when it's time (and plans the next one) */
stock bool HazardDue(float &next, int every)
{
	if (!g_bRoundLive || !g_bZombiesSeen)
		return false;

	float now = GetGameTime();
	if (next == 0.0)
		next = now + float(every);

	if (now < next)
		return false;

	next = now + float(every);
	return true;
}

/* Living humans in random order, returns how many */
stock int GetShuffledHumans(int list[MAXPLAYERS + 1])
{
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanAlive(i))
			list[count++] = i;
	}

	for (int i = count - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i);
		int tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}

	return count;
}

/* A random living human, real players before bots, 0 if there is none */
stock int PickRandomHuman(int exclude = 0)
{
	int list[MAXPLAYERS + 1];
	int count;
	for (int pass = 0; pass < 2 && count == 0; pass++)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (i == exclude || !IsHumanAlive(i))
				continue;

			if (pass == 0 && IsFakeClient(i))
				continue;

			list[count++] = i;
		}
	}

	return count == 0 ? 0 : list[GetRandomInt(0, count - 1)];
}

/* A random living zombie, real players before bots, 0 if there is none */
stock int PickRandomZombie()
{
	int list[MAXPLAYERS + 1];
	int count;
	for (int pass = 0; pass < 2 && count == 0; pass++)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsPlayerAlive(i) || !ZR_IsClientZombie(i))
				continue;

			if (pass == 0 && IsFakeClient(i))
				continue;

			list[count++] = i;
		}
	}

	return count == 0 ? 0 : list[GetRandomInt(0, count - 1)];
}

/* The round is lost: the modes stop checking until the next round */
stock void SlayAllHumans()
{
	g_bRoundLive = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanAlive(i))
			ForcePlayerSuicide(i);
	}
}

/* Takes health, 1000 or more (or running out) slays */
stock void HurtPlayer(int client, int damage)
{
	int hp = GetClientHealth(client) - damage;
	if (damage >= 1000 || hp <= 0)
		ForcePlayerSuicide(client);
	else
		SetEntityHealth(client, hp);
}

/* Adds to a player's velocity (shoves, pulls, winds) */
stock void ShovePlayer(int client, float x, float y, float z)
{
	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
	vel[0] += x;
	vel[1] += y;
	vel[2] += z;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
}

/* Colours the screen, holds it, then fades back */
stock void ScreenTint(int client, int r, int g, int b, int a, float hold, float fadeBack)
{
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("Fade", client, USERMSG_RELIABLE));
	bf.WriteShort(RoundToNearest(fadeBack * 512.0));
	bf.WriteShort(RoundToNearest(hold * 512.0));
	bf.WriteShort(FFADE_IN | FFADE_PURGE);
	bf.WriteByte(r);
	bf.WriteByte(g);
	bf.WriteByte(b);
	bf.WriteByte(a);
	EndMessage();
}

/* A special map item (EntWatch knows best, otherwise any weapon with a name on the map) */
stock bool IsMapItem(int weapon)
{
	if (EW_IsEntityItem(weapon))
		return true;

	char name[64];
	GetEntPropString(weapon, Prop_Data, "m_iName", name, sizeof(name));
	return name[0] != '\0';
}

/* ---------------------------------------------------------------- config files */

/* On some servers the engine's KeyValues reader refuses the FunModes configs (ImportFromFile fails although
   the file is there and valid). SourceMod's own config parser reads the same format, so it's the fallback,
   and saving falls back to writing the file by hand. */

char g_sKvError[192];           // why the last FunModes_LoadKV failed
KeyValues g_hKvParsing;
int g_iKvParseDepth;

/* Reads the file into kv (a fresh KeyValues), false if it's missing or broken (the reason in g_sKvError) */
stock bool FunModes_LoadKV(KeyValues kv, const char[] path)
{
	g_sKvError[0] = '\0';

	if (!FileExists(path))
	{
		FormatEx(g_sKvError, sizeof(g_sKvError), "%s is missing", path);
		return false;
	}

	if (kv.ImportFromFile(path))
		return true;

	g_hKvParsing = kv;
	g_iKvParseDepth = 0;

	SMCParser parser = new SMCParser();
	parser.OnEnterSection = FunModes_KvEnterSection;
	parser.OnKeyValue = FunModes_KvKeyValue;
	parser.OnLeaveSection = FunModes_KvLeaveSection;

	int line, col;
	SMCError error = parser.ParseFile(path, line, col);

	char reason[96];
	if (error != SMCError_Okay)
		parser.GetErrorString(error, reason, sizeof(reason));

	delete parser;
	g_hKvParsing = null;
	kv.Rewind();

	if (error != SMCError_Okay)
	{
		FormatEx(g_sKvError, sizeof(g_sKvError), "%s line %d: %s", path, line, reason);
		return false;
	}

	return true;
}

SMCResult FunModes_KvEnterSection(SMCParser smc, const char[] name, bool opt_quotes)
{
	// The file's outer section is the KeyValues root itself
	if (g_iKvParseDepth++ > 0)
		g_hKvParsing.JumpToKey(name, true);

	return SMCParse_Continue;
}

SMCResult FunModes_KvKeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	if (g_iKvParseDepth > 0)
		g_hKvParsing.SetString(key, value);

	return SMCParse_Continue;
}

SMCResult FunModes_KvLeaveSection(SMCParser smc)
{
	if (--g_iKvParseDepth > 0)
		g_hKvParsing.GoBack();

	return SMCParse_Continue;
}

/* Writes kv to the file, by hand when the engine's writer refuses it too */
stock bool FunModes_SaveKV(KeyValues kv, const char[] path)
{
	kv.Rewind();
	if (kv.ExportToFile(path))
		return true;

	File file = OpenFile(path, "w");
	if (file == null)
	{
		LogError("[FunModes] Couldn't write %s", path);
		return false;
	}

	char name[128];
	kv.GetSectionName(name, sizeof(name));
	file.WriteLine("\"%s\"", name);
	file.WriteLine("{");
	FunModes_WriteKvSection(kv, file, 1);
	file.WriteLine("}");

	delete file;
	kv.Rewind();
	return true;
}

void FunModes_WriteKvSection(KeyValues kv, File file, int depth)
{
	if (!kv.GotoFirstSubKey(false))
		return;

	char indent[16];
	for (int i = 0; i < depth && i < sizeof(indent) - 1; i++)
		indent[i] = '\t';

	char name[128], value[512];
	do
	{
		kv.GetSectionName(name, sizeof(name));
		if (kv.GetDataType(NULL_STRING) == KvData_None)
		{
			file.WriteLine("%s\"%s\"", indent, name);
			file.WriteLine("%s{", indent);
			FunModes_WriteKvSection(kv, file, depth + 1);
			file.WriteLine("%s}", indent);
		}
		else
		{
			kv.GetString(NULL_STRING, value, sizeof(value));
			ReplaceString(value, sizeof(value), "\"", "'");
			file.WriteLine("%s\"%s\"\t\t\"%s\"", indent, name, value);
		}
	} while (kv.GotoNextKey(false));

	kv.GoBack();
}

/* ---------------------------------------------------------------- chosen players */

/* The key a chosen player is saved by: the Steam ID, or the user id for a bot */
stock void GetChosenKey(int client, char[] key, int maxlen)
{
	if (IsFakeClient(client) || !GetClientAuthId(client, AuthId_Steam2, key, maxlen))
		FormatEx(key, maxlen, "#%d", GetClientUserId(client));
}

stock bool ChosenListHas(ArrayList list, int client)
{
	if (list == null)
		return false;

	char key[32];
	GetChosenKey(client, key, sizeof(key));
	return list.FindString(key) != -1;
}

/* Adds the player, or removes them when they're in it already. Returns true when they're in it now */
stock bool ChosenListToggle(ArrayList list, int client)
{
	char key[32];
	GetChosenKey(client, key, sizeof(key));

	int index = list.FindString(key);
	if (index != -1)
	{
		list.Erase(index);
		return false;
	}

	list.PushString(key);
	return true;
}

/* The player left the server (not a map change): they're no longer chosen */
stock void ChosenListForget(ArrayList list, int client)
{
	if (list == null)
		return;

	char key[32];
	GetChosenKey(client, key, sizeof(key));

	int index = list.FindString(key);
	if (index != -1)
		list.Erase(index);
}

/* ---------------------------------------------------------------- effects */

/* A ring on the ground at a spot, from startRadius to endRadius over life seconds */
stock void DrawRingAt(const float pos[3], float startRadius, float endRadius, float life, const int color[4], float width = 8.0)
{
	float p[3];
	p = pos;
	p[2] += 8.0;

	// The ring's radius values draw as diameters, so double them to match real distances
	TE_SetupBeamRingPoint(p, startRadius * 2.0, endRadius * 2.0, g_LaserSprite, g_HaloSprite, 0, 15, life, width, 0.0, color, 10, 0);
	TE_SendToAll();
}

/* A ring growing around a player */
stock void DrawPlayerRing(int client, const int color[4], float radius)
{
	float pos[3];
	GetClientAbsOrigin(client, pos);
	pos[2] += 10.0;

	TE_SetupBeamRingPoint(pos, 10.0, radius * 2.0, g_LaserSprite, g_HaloSprite, 0, 15, 0.9, 8.0, 0.0, color, 10, 0);
	TE_SendToAll();
}

/* A beam from high above down to a spot (falling meteors, bombs, pillars) */
stock void DrawBeamDown(const float pos[3], float height, float life, float width, const int color[4], float jitter = 0.0)
{
	float top[3];
	top = pos;
	top[2] += height;

	TE_SetupBeamPoints(top, pos, g_LaserSprite, g_HaloSprite, 0, 30, life, width, width, 0, jitter, color, 10);
	TE_SendToAll();
}

/* Explosion at a spot: full damage at the centre, half at the edge, knockback away from it. 1000 damage or more kills */
stock void ExplodeAt(const float pos[3], float radius, int damage, float knock, bool zombiesToo)
{
	if (g_iExplosionSprite != -1)
	{
		TE_SetupExplosion(pos, g_iExplosionSprite, 5.0, 1, 0, RoundToNearest(radius), 300);
		TE_SendToAll();
	}

	EmitAmbientSound(Explode_Sound, pos, SOUND_FROM_WORLD, SNDLEVEL_RAIDSIREN);

	float other[3], dir[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, zombiesToo))
			continue;

		GetClientAbsOrigin(i, other);
		float dist = GetVectorDistance(pos, other);
		if (dist > radius)
			continue;

		float scale = 1.0 - (dist / radius) * 0.5;
		if (knock > 0.0)
		{
			MakeVectorFromPoints(pos, other, dir);
			dir[2] = 0.0;
			NormalizeVector(dir, dir);
			ShovePlayer(i, dir[0] * knock * scale, dir[1] * knock * scale, knock * 0.5 * scale);
		}

		HurtPlayer(i, damage >= 1000 ? 1000 : RoundToNearest(float(damage) * scale));
	}
}

/* ---------------------------------------------------------------- speed and gravity */

/* 1.0 (or anything not above 0) = no change from this mode */
stock void SetSpeedMult(int client, int modeIndex, float mult)
{
	g_fSpeedMult[client][modeIndex] = (mult > 0.0 && !Physics_Near(mult, 1.0)) ? mult : 0.0;
}

stock void SetGravityMult(int client, int modeIndex, float mult)
{
	g_fGravityMult[client][modeIndex] = (mult > 0.0 && !Physics_Near(mult, 1.0)) ? mult : 0.0;
}

/* Puts every player's speed and gravity of a mode back to normal (when the mode stops) */
stock void ResetModeMults(int modeIndex)
{
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_fSpeedMult[i][modeIndex] = 0.0;
		g_fGravityMult[i][modeIndex] = 0.0;
	}
}

/* A player joined or left: nothing of the slot's last player carries over */
void Physics_ResetClient(int client)
{
	for (int m = 0; m < MAX_MODES_NUM; m++)
	{
		g_fSpeedMult[client][m] = 0.0;
		g_fGravityMult[client][m] = 0.0;
	}

	g_bSpeedTouched[client] = false;
	g_bGravityTouched[client] = false;
}

bool Physics_Near(float a, float b)
{
	return FloatAbs(a - b) < 0.001;
}

void Physics_ApplySpeed(int client, float mult)
{
	float cur = GetEntPropFloat(client, Prop_Data, SPEED_PROP);

	// Something else froze them (a map, another plugin): leave them alone, and never build on a speed of 0
	if (cur <= 0.0)
		return;

	// The value to build on (zombie reloaded may have set it)
	if (!g_bSpeedTouched[client] || !Physics_Near(cur, g_fSpeedSet[client]))
		g_fSpeedBase[client] = cur;

	if (Physics_Near(mult, 1.0))
	{
		if (g_bSpeedTouched[client])
			SetEntPropFloat(client, Prop_Data, SPEED_PROP, g_fSpeedBase[client]);

		g_bSpeedTouched[client] = false;
		return;
	}

	float want = g_fSpeedBase[client] * mult;
	if (!Physics_Near(cur, want))
		SetEntPropFloat(client, Prop_Data, SPEED_PROP, want);

	g_fSpeedSet[client] = want;
	g_bSpeedTouched[client] = true;
}

void Physics_ApplyGravity(int client, float mult)
{
	float cur = GetEntityGravity(client);

	// 0 means normal gravity
	if (!g_bGravityTouched[client] || !Physics_Near(cur, g_fGravitySet[client]))
		g_fGravityBase[client] = cur > 0.0 ? cur : 1.0;

	if (Physics_Near(mult, 1.0))
	{
		if (g_bGravityTouched[client])
			SetEntityGravity(client, g_fGravityBase[client]);

		g_bGravityTouched[client] = false;
		return;
	}

	float want = g_fGravityBase[client] * mult;
	if (!Physics_Near(cur, want))
		SetEntityGravity(client, want);

	g_fGravitySet[client] = want;
	g_bGravityTouched[client] = true;
}

/* Every player back to the speed and gravity they had under the modes (plugin unload) */
void Physics_ResetAll()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		if (g_bSpeedTouched[i])
			SetEntPropFloat(i, Prop_Data, SPEED_PROP, g_fSpeedBase[i]);

		if (g_bGravityTouched[i])
			SetEntityGravity(i, g_fGravityBase[i]);

		g_bSpeedTouched[i] = false;
		g_bGravityTouched[i] = false;
	}
}

/* A mode still has a speed or gravity of its own on someone */
bool Physics_AnyTouched()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bSpeedTouched[i] || g_bGravityTouched[i])
			return true;
	}

	return false;
}

void Physics_Apply()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			g_bSpeedTouched[i] = false;
			g_bGravityTouched[i] = false;
			continue;
		}

		float speed = 1.0, gravity = 1.0;
		if (IsPlayerAlive(i))
		{
			for (int m = 0; m < g_iLastModeIndex; m++)
			{
				if (g_fSpeedMult[i][m] > 0.0)
					speed *= g_fSpeedMult[i][m];

				if (g_fGravityMult[i][m] > 0.0)
					gravity *= g_fGravityMult[i][m];
			}
		}

		// No mode changes this player and none did before: nothing to do
		if (Physics_Near(speed, 1.0) && Physics_Near(gravity, 1.0) && !g_bSpeedTouched[i] && !g_bGravityTouched[i])
			continue;

		Physics_ApplySpeed(i, speed);
		Physics_ApplyGravity(i, gravity);
	}
}

/* ---------------------------------------------------------------- hud */

/* A text slot for one mode. Without DynamicChannels it's a normal hud synchronizer */
stock Handle CreateModeHud()
{
	Handle sync = CreateHudSynchronizer();
	if (g_iHudSlotsCount < MAX_HUD_SLOTS)
		g_hHudSlots[g_iHudSlotsCount++] = sync;

	return sync;
}

/* Shows a text on the client's screen (after SetHudTextParams). With DynamicChannels each slot gets a channel other plugins won't overwrite */
stock void ShowModeHud(int client, Handle sync, const char[] format, any ...)
{
	char text[256];
	SetGlobalTransTarget(client);
	VFormat(text, sizeof(text), format, 4);

#if defined _DynamicChannels_included_
	if (g_bPlugin_DynamicChannels && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available)
	{
		int slot;
		for (int i = 0; i < g_iHudSlotsCount; i++)
		{
			if (g_hHudSlots[i] == sync)
				slot = i;
		}

		int channel = GetDynamicChannel(slot % 5);
		if (channel >= 0)
		{
			ShowHudText(client, channel, "%s", text);
			return;
		}
	}
#endif

	ShowSyncHudText(client, sync, "%s", text);
}

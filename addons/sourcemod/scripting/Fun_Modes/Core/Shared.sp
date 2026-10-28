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

int g_iExplosionSprite = -1;

Handle g_hCheckTimer = null;
Handle g_hTickTimer = null;

/* Stacked Speed And Gravity: each mode reports a multiplier, the product is applied on top of the player's own value */
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

Handle g_hHudSlots[MAX_HUD_SLOTS];
int g_iHudSlotsCount;

void Shared_OnPluginStart()
{
	for (int i = 0; i <= MaxClients; i++)
	{
		for (int j = 0; j < MAX_MODES_NUM; j++)
		{
			g_fSpeedMult[i][j] = 1.0;
			g_fGravityMult[i][j] = 1.0;
		}
	}

	FunModes_HookEvent(g_bEvent_RoundStart, "round_start", Event_RoundStart);
	FunModes_HookEvent(g_bEvent_RoundEnd, "round_end", Event_RoundEnd);
}

void Shared_OnMapStart()
{
	g_iExplosionSprite = PrecacheModel("sprites/zerogxplode.spr");
	PrecacheSound(Explode_Sound, true);

	g_bRoundLive = true;
	g_bZombiesSeen = false;

	delete g_hCheckTimer;
	delete g_hTickTimer;
	g_hCheckTimer = CreateTimer(0.2, Shared_CheckTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
	g_iRoundNum++;
}

void Shared_RoundEnd()
{
	g_bRoundLive = false;
}

/* Runs the OnCheck forward right away, used when someone dies or gets infected */
void FunModes_RunCheck()
{
	bool zombiesNow = ZombiesAlive();

	if (g_bRoundLive)
	{
		DECLARE_FM_FORWARD_ON_PARAM1(OnCheck, zombiesNow)
	}

	if (zombiesNow)
		g_bZombiesSeen = true;
}

Action Shared_CheckTimer(Handle timer)
{
	FunModes_RunCheck();
	Physics_Apply();
	return Plugin_Continue;
}

Action Shared_TickTimer(Handle timer)
{
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

stock void SetSpeedMult(int client, int modeIndex, float mult)
{
	g_fSpeedMult[client][modeIndex] = mult;
}

stock void SetGravityMult(int client, int modeIndex, float mult)
{
	g_fGravityMult[client][modeIndex] = mult;
}

/* Puts every player's speed and gravity of a mode back to normal (when the mode stops) */
stock void ResetModeMults(int modeIndex)
{
	for (int i = 0; i <= MaxClients; i++)
	{
		g_fSpeedMult[i][modeIndex] = 1.0;
		g_fGravityMult[i][modeIndex] = 1.0;
	}
}

bool Physics_Near(float a, float b)
{
	return FloatAbs(a - b) < 0.001;
}

void Physics_ApplySpeed(int client, float mult)
{
	float cur = GetEntPropFloat(client, Prop_Data, SPEED_PROP);

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
				speed *= g_fSpeedMult[i][m];
				gravity *= g_fGravityMult[i][m];
			}
		}

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

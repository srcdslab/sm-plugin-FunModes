// VIP mode + Heal Beacon module of eventmodes.sp.
// eventmodes.sp calls Modes_PluginStart / Modes_MapStart / Modes_MapEnd from its own forwards.
// It also drives the round for the other modes (weapons, potato, buddy, lightning) and holds the main menu.

#if defined _em_modes_included
 #endinput
#endif
#define _em_modes_included

#define VIP_TAG        "\x07" ... "FFD700[VIP]\x01 "         // kept apart: \x would eat the hex digits
#define HB_TAG         "\x07" ... "55FF55[Heal Beacon]\x01 "
#define BEACON_SOUND   "buttons/blip1.wav"
#define EXPLODE_SOUND  "weapons/hegrenade/explode3.wav"
#define MAX_BEACONS    5

// Menu cycles
float g_RadiusSteps[] = { 300.0, 400.0, 500.0, 600.0, 800.0, 1000.0 };
int g_HealSteps[] = { 0, 1, 2, 3, 5, 10 };
int g_DamageSteps[] = { 1, 2, 3, 5, 10, 20 };

int g_VipColor[4] = { 255, 215, 0, 255 };
int g_HbColor[4] = { 60, 255, 60, 255 };

ConVar g_cvRadius;
ConVar g_cvHeal;
ConVar g_cvDamage;
ConVar g_cvCount;
ConVar g_cvSound;

// round
bool g_RoundLive;
bool g_ZombiesSeen;        // a zombie existed at an earlier check this round (first infection is over)
int g_RoundNum;            // bumped every round, so delayed actions can tell they're stale
bool g_InfectedAsMother[MAXPLAYERS + 1];   // this round's infection was a mother infection (needs ZR)

// VIP
bool g_VipOn;
#define MAX_VIPS 5
int g_VipDelaySteps[] = { 0, 3, 5, 10 };
bool g_VipSlay = true;     // every VIP falls -> slay all humans (else new VIPs are picked)
bool g_VipBeacon = true;   // ring on the VIPs so humans can find them
int g_VipCount = 1;        // VIPs at once
int g_VipDelay = 3;        // seconds of countdown before the slay
bool g_VipLaserSafe = true;   // a VIP killed by a map laser doesn't count
int g_VipList[MAX_VIPS];   // userids; 0 = free spot, -1 = fallen (not replaced while slaying)
float g_VipSlayAt;         // countdown running until then, 0 = none
float g_VipLaserAt[MAXPLAYERS + 1];   // last hurt by a map laser

// Heal beacon
bool g_HbOn;
bool g_HbSlay;             // a carrier dies -> slay all humans (else the beacon passes on)
int g_HbWarnSteps[] = { 0, 5, 10, 15 };
int g_HbWarn = 5;          // seconds after the beacons appear before standing outside hurts
float g_HbArmedAt;         // damage outside starts then (0 = beacons not handed out yet)
bool g_HbLightOn = true;   // a coloured glow follows each carrier
bool g_HbColors = true;    // each beacon its own colour (else all green)
int g_HbPalette[MAX_BEACONS][4] = { { 60, 255, 60, 255 }, { 60, 200, 255, 255 }, { 255, 230, 60, 255 }, { 255, 80, 255, 255 }, { 255, 150, 40, 255 } };
int g_HbLight[MAX_BEACONS] = { INVALID_ENT_REFERENCE, ... };
int g_HbLightOwner[MAX_BEACONS];
bool g_HbSound = true;     // beep from every beacon each second
int g_HbCount = 1;         // how many beacons are handed out
int g_HbList[MAX_BEACONS]; // carriers' userids, 0 = slot empty (filled when zombies are out)
float g_HbRadius;
int g_HbHeal;
int g_HbDamage;
int g_MaxHp[MAXPLAYERS + 1];
bool g_Outside[MAXPLAYERS + 1];

int g_BeamSprite = -1;
int g_HaloSprite = -1;
int g_ExplosionSprite = -1;
Handle g_HudVip;
Handle g_HudHb;
Handle g_CheckTimer;
Handle g_TickTimer;
bool g_Late;

// ---------------------------------------------------------------- lifecycle

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_Late = late;
	Integrations_MarkOptional();   // ZR, EntWatch and DynamicChannels are all optional
	return APLRes_Success;
}

void Modes_PluginStart()
{
	RegConsoleCmd("sm_em", Cmd_Menu, "Event modes admin menu");
	RegConsoleCmd("sm_eventmode", Cmd_Menu, "Event modes admin menu");
	RegConsoleCmd("sm_emvip", Cmd_Who, "Who is the VIP / heal beacon");

	g_cvRadius = CreateConVar("sm_eventmodes_beacon_radius", "500", "Heal beacon radius at map start", _, true, 100.0, true, 3000.0);
	g_cvHeal = CreateConVar("sm_eventmodes_beacon_heal", "2", "HP per second healed inside the heal beacon at map start", _, true, 0.0, true, 100.0);
	g_cvDamage = CreateConVar("sm_eventmodes_beacon_damage", "5", "HP per second lost outside the heal beacons at map start", _, true, 1.0, true, 100.0);
	g_cvCount = CreateConVar("sm_eventmodes_beacon_count", "1", "Number of heal beacons at map start", _, true, 1.0, true, float(MAX_BEACONS));
	g_cvSound = CreateConVar("sm_eventmodes_beacon_sound", "1", "Heal beacons beep every second (at map start)", _, true, 0.0, true, 1.0);
	CreateConVar("sm_eventmodes_version", PLUGIN_VERSION, "Event Modes version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "eventmodes");

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath);

	g_HudVip = EM_HudSync();
	g_HudHb = EM_HudSync();

	ReadDefaults();
	ResetModes();
	for (int i = 1; i <= MaxClients; i++)   // late load
		if (IsClientInGame(i))
			Modes_ClientPutInServer(i);
	if (g_Late)
		Modes_MapStart();   // loaded mid-map: OnMapStart won't be called for this map
}

public void OnConfigsExecuted()
{
	ReadDefaults();
	Settings_Load();   // the admins' saved menu settings win over the cvar defaults
}

void ReadDefaults()
{
	g_HbRadius = g_cvRadius.FloatValue;
	g_HbHeal = g_cvHeal.IntValue;
	g_HbDamage = g_cvDamage.IntValue;
	g_HbCount = g_cvCount.IntValue;
	g_HbSound = g_cvSound.BoolValue;
}

void Modes_MapStart()
{
	g_BeamSprite = PrecacheModel("materials/sprites/laser.vmt");
	g_HaloSprite = PrecacheModel("materials/sprites/halo01.vmt");
	g_ExplosionSprite = PrecacheModel("sprites/zerogxplode.spr");
	PrecacheSound(BEACON_SOUND, true);
	PrecacheSound(EXPLODE_SOUND, true);
	ResetModes();
	g_RoundLive = true;
	delete g_CheckTimer;
	delete g_TickTimer;
	g_CheckTimer = CreateTimer(0.2, Timer_Check, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	g_TickTimer = CreateTimer(1.0, Timer_Tick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// Modes never carry over to the next map.
void Modes_MapEnd()
{
	ResetModes();
	g_CheckTimer = null;   // TIMER_FLAG_NO_MAPCHANGE already killed them
	g_TickTimer = null;
}

void ResetModes()
{
	g_VipOn = false;
	g_HbOn = false;
	ClearVips();
	ClearBeacons();
	g_ZombiesSeen = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_MaxHp[i] = 0;
		g_Outside[i] = false;
	}
	Potato_Stop();
	Buddy_Stop();
	Lightning_Stop();
	GG_Stop();
	MQ_Stop();
	RLGL_Stop();
	Simon_Stop();
	TS_Stop();
	IC_Stop();
	BO_Stop();
	GZ_Stop();
	BZ_Stop();
	EQ_Stop();
	Hero_Stop();
	LS_Stop();
	FL_Stop();
	ZD_Stop();
	TV_Stop();
	HS_Stop();
	MT_Stop();
	AS_Stop();
	SW_Stop();
	NK_Stop();
	TG_Stop();
	RD_Stop();
	AR_Stop();
	FC_Stop();
	SD_Stop();
	GW_Stop();
	IF_Stop();
	WG_Stop();
	TN_Stop();
	QS_Stop();
	MG_Stop();
	HL_Stop();
	LC_Stop();
	JG_Stop();
	BF_Stop();
	ZF_Stop();
	DJ_Stop();
	Roulette_Stop();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_RoundLive = true;
	g_ZombiesSeen = false;
	g_RoundNum++;
	for (int i = 1; i <= MaxClients; i++)
		g_InfectedAsMother[i] = false;
	ClearVips();
	ClearBeacons();
	for (int i = 1; i <= MaxClients; i++)
	{
		g_MaxHp[i] = 0;
		g_Outside[i] = false;
	}
	if (g_VipOn)
		PrintToChatAll(VIP_TAG ... "VIP mode is on: a VIP is chosen when the first zombie appears.");
	if (g_HbOn)
		PrintToChatAll(HB_TAG ... "Heal Beacon is on: stay inside a beacon once the zombies come!");
	Potato_RoundStart();
	Buddy_RoundStart();
	Lightning_RoundStart();
	MQ_RoundStart();
	RLGL_RoundStart();
	Simon_RoundStart();
	TS_RoundStart();
	IC_RoundStart();
	BO_RoundStart();
	BZ_RoundStart();
	EQ_RoundStart();
	Hero_RoundStart();
	LS_RoundStart();
	FL_RoundStart();
	ZD_RoundStart();
	TV_RoundStart();
	HS_RoundStart();
	MT_RoundStart();
	AS_RoundStart();
	SW_RoundStart();
	NK_RoundStart();
	TG_RoundStart();
	RD_RoundStart();
	AR_RoundStart();
	FC_RoundStart();
	SD_RoundStart();
	GW_RoundStart();
	IF_RoundStart();
	WG_RoundStart();
	TN_RoundStart();
	QS_RoundStart();
	MG_RoundStart();
	HL_RoundStart();
	LC_RoundStart();
	JG_RoundStart();
	BF_RoundStart();
	ZF_RoundStart();
	Roulette_RoundStart();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_RoundLive = false;
	ClearVips();
	ClearBeacons();
	Potato_Drop();
	MQ_RoundEnd();
	GZ_RoundEnd();
	BZ_RoundEnd();
	Hero_RoundEnd();
	TV_RoundEnd();
	IF_RoundEnd();
	Roulette_RoundEnd();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// React at once instead of waiting for the next check.
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client == 0)
		return;
	if (g_RoundLive && AnyRoundMode())
		Check();
}

// ---------------------------------------------------------------- helpers

// Takes health; 1000 or more (or running out) slays.
// ---- shared by the hazards

// Alive and on a team the hazard hits: humans, plus zombies when `everyone`.
bool HazardHits(int client, bool everyone)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return false;
	int team = GetClientTeam(client);
	return team == CS_TEAM_CT || (everyone && team == CS_TEAM_T);
}

// For hazards that come every N seconds once the zombies are out: true when it's time (and plans the next).
bool HazardDue(bool on, float &next, int every)
{
	if (!on || !g_RoundLive || !g_ZombiesSeen)
		return false;
	float now = GetGameTime();
	if (next == 0.0)
		next = now + float(every);
	if (now < next)
		return false;
	next = now + float(every);
	return true;
}

// Living humans in random order; returns how many.
int ShuffledHumans(int list[MAXPLAYERS + 1])
{
	int n = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (IsHuman(i))
			list[n++] = i;
	for (int i = n - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}
	return n;
}

// A ring on the ground at a spot, growing or shrinking from startRadius to endRadius over `life` seconds.
void RingAt(const float pos[3], float startRadius, float endRadius, float life, const int color[4], float width = 8.0)
{
	if (g_BeamSprite == -1)
		return;
	float p[3];
	p = pos;
	p[2] += 8.0;
	// The ring's radius values draw as diameters, so double them to match real distances.
	TE_SetupBeamRingPoint(p, startRadius * 2.0, endRadius * 2.0, g_BeamSprite, g_HaloSprite, 0, 15, life, width, 0.0, color, 10, 0);
	TE_SendToAll();
}

// A beam from high above down to a spot (falling meteors, bombs, pillars).
void BeamDown(const float pos[3], float height, float life, float width, const int color[4], float jitter = 0.0)
{
	if (g_BeamSprite == -1)
		return;
	float top[3];
	top = pos;
	top[2] += height;
	TE_SetupBeamPoints(top, pos, g_BeamSprite, g_HaloSprite, 0, 30, life, width, width, 0, jitter, color, 10);
	TE_SendToAll();
}

// Colours the screen, holds it, then fades back (blackouts, flashes, tints).
void ScreenTint(int client, int r, int g, int b, int a, float hold, float fadeBack)
{
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("Fade", client, USERMSG_RELIABLE));
	bf.WriteShort(RoundToNearest(fadeBack * 512.0));   // units of 1/512 s
	bf.WriteShort(RoundToNearest(hold * 512.0));
	bf.WriteShort(0x0001 | 0x0010);                    // FFADE_IN | FFADE_PURGE: start at the colour, fade back
	bf.WriteByte(r);
	bf.WriteByte(g);
	bf.WriteByte(b);
	bf.WriteByte(a);
	EndMessage();
}

// Adds to a player's velocity (shoves, pulls, winds).
void Shove(int client, float x, float y, float z)
{
	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
	vel[0] += x;
	vel[1] += y;
	vel[2] += z;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
}

// Explosion at a spot: full damage at the centre, half at the edge, knockback away from it.
// damage 1000 or more kills everyone inside.
void Explode(const float pos[3], float radius, int damage, float knock, bool zombiesToo)
{
	if (g_ExplosionSprite != -1)
	{
		TE_SetupExplosion(pos, g_ExplosionSprite, 5.0, 1, 0, RoundToNearest(radius), 300);
		TE_SendToAll();
	}
	EmitAmbientSound(EXPLODE_SOUND, pos, SOUND_FROM_WORLD, SNDLEVEL_RAIDSIREN);
	float other[3], dir[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, zombiesToo))
			continue;
		GetClientAbsOrigin(i, other);
		float d = GetVectorDistance(pos, other);
		if (d > radius)
			continue;
		float scale = 1.0 - (d / radius) * 0.5;
		if (knock > 0.0)
		{
			MakeVectorFromPoints(pos, other, dir);
			dir[2] = 0.0;
			NormalizeVector(dir, dir);
			Shove(i, dir[0] * knock * scale, dir[1] * knock * scale, knock * 0.5 * scale);
		}
		HurtPlayer(i, damage >= 1000 ? 1000 : RoundToNearest(float(damage) * scale));
	}
}

void HurtPlayer(int client, int damage)
{
	int hp = GetClientHealth(client) - damage;
	if (damage >= 1000 || hp <= 0)
		ForcePlayerSuicide(client);
	else
		SetEntityHealth(client, hp);
}

bool IsHuman(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return false;
	if (g_HasZR)
		return ZR_IsClientHuman(client);
	return GetClientTeam(client) == CS_TEAM_CT;
}

// Zombie Reloaded reports an infection: remember mother zombies and react right away.
void EM_OnInfected(int client, bool mother)
{
	if (client > 0 && client <= MaxClients)
		g_InfectedAsMother[client] = mother;
	if (g_RoundLive && AnyRoundMode())
		Check();
}

bool ZombiesAlive()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T)
			return true;
	return false;
}

// A random living human, real players before bots; 0 if there is none.
int RandomHuman(int exclude, bool skipBeacons = false)
{
	int list[MAXPLAYERS + 1], count = 0;
	for (int pass = 0; pass < 2 && count == 0; pass++)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (i == exclude || !IsHuman(i) || (skipBeacons && IsBeacon(i)))
				continue;
			if (pass == 0 && IsFakeClient(i))
				continue;
			list[count++] = i;
		}
	}
	return count == 0 ? 0 : list[GetRandomInt(0, count - 1)];
}

void SlayHumans()
{
	// The round is lost: stop checking until the next round, so the other carriers / the VIP dying
	// from this slay don't each announce another "has fallen".
	g_RoundLive = false;
	for (int i = 1; i <= MaxClients; i++)
		if (IsHuman(i))
			ForcePlayerSuicide(i);
}

void Ring(int client, const int color[4], float radius)
{
	if (g_BeamSprite == -1)
		return;
	float pos[3];
	GetClientAbsOrigin(client, pos);
	pos[2] += 10.0;
	// The ring's end "radius" draws as a diameter, so double it to match the real distance.
	TE_SetupBeamRingPoint(pos, 10.0, radius * 2.0, g_BeamSprite, g_HaloSprite, 0, 15, 0.9, 8.0, 0.0, color, 10, 0);
	TE_SendToAll();
}

// ---------------------------------------------------------------- VIP

void ClearVips()
{
	for (int s = 0; s < MAX_VIPS; s++)
		g_VipList[s] = 0;
	g_VipSlayAt = 0.0;
}

bool IsVip(int client)
{
	int uid = GetClientUserId(client);
	for (int s = 0; s < MAX_VIPS; s++)
		if (g_VipList[s] > 0 && g_VipList[s] == uid)
			return true;
	return false;
}

// Living VIPs right now; returns how many were written to `out`.
int LiveVips(int out[MAX_VIPS])
{
	int n = 0;
	for (int s = 0; s < g_VipCount && s < MAX_VIPS; s++)
	{
		if (g_VipList[s] <= 0)
			continue;
		int c = GetClientOfUserId(g_VipList[s]);
		if (IsHuman(c))
			out[n++] = c;
	}
	return n;
}

// "Name, Name" of the living VIPs.
void VipNames(char[] buf, int len)
{
	int list[MAX_VIPS];
	int n = g_VipOn ? LiveVips(list) : 0;
	buf[0] = '\0';
	for (int k = 0; k < n; k++)
		Format(buf, len, "%s%s%N", buf, k == 0 ? "" : ", ", list[k]);
}

// A random living human who isn't a VIP yet, real players before bots.
int RandomNonVip()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);
	for (int pass = 0; pass < 2; pass++)
		for (int k = 0; k < n; k++)
			if (!IsVip(list[k]) && (pass == 1 || !IsFakeClient(list[k])))
				return list[k];
	return 0;
}

void GiveVip(int slot, int client)
{
	g_VipList[slot] = GetClientUserId(client);
	if (!g_VipSlay)
		PrintToChatAll(VIP_TAG ... "\x07" ... "FFD700%N\x01 is a VIP! Protect them - fallen VIPs are replaced.", client);
	else if (g_VipCount > 1)
		PrintToChatAll(VIP_TAG ... "\x07" ... "FFD700%N\x01 is a VIP! Protect them - if every VIP falls, all humans die.", client);
	else
		PrintToChatAll(VIP_TAG ... "\x07" ... "FFD700%N\x01 is the VIP! Protect them - if the VIP dies, all humans die.", client);
	PrintCenterTextAll("%N is a VIP!", client);
}

// Empty spots (up to the VIP count) get a new random VIP. Fallen VIPs (-1) are not replaced while
// "slay all humans" is on - when every spot has fallen, the humans lose.
void FillVips()
{
	for (int s = 0; s < g_VipCount && s < MAX_VIPS; s++)
	{
		if (g_VipList[s] != 0)
			continue;
		int pick = RandomNonVip();
		if (pick == 0)
			return;
		GiveVip(s, pick);
	}
}

// Chosen by an admin: a free spot if there is one, else the first VIP hands over.
void GiveChosenVip(int target)
{
	for (int s = 0; s < g_VipCount && s < MAX_VIPS; s++)
	{
		if (g_VipList[s] <= 0 || !IsHuman(GetClientOfUserId(g_VipList[s])))
		{
			GiveVip(s, target);
			return;
		}
	}
	GiveVip(0, target);
}

void Modes_ClientPutInServer(int client)
{
	g_VipLaserAt[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamage, VIP_OnTakeDamage);
}

// Remembers when a VIP was hurt by a map laser: a trigger_hurt riding on a moving part of the map
// (func_movelinear, func_door, trains, rotators) - the usual ZE laser build.
public Action VIP_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!g_VipOn || !g_VipLaserSafe || inflictor <= MaxClients || !IsValidEntity(inflictor) || !IsVip(victim))
		return Plugin_Continue;
	char cls[64];
	GetEntityClassname(inflictor, cls, sizeof(cls));
	if (!StrEqual(cls, "trigger_hurt"))
		return Plugin_Continue;
	int parent = HasEntProp(inflictor, Prop_Data, "m_hMoveParent") ? GetEntPropEnt(inflictor, Prop_Data, "m_hMoveParent") : -1;
	if (parent <= MaxClients || !IsValidEntity(parent))
		return Plugin_Continue;
	GetEntityClassname(parent, cls, sizeof(cls));
	if (StrContains(cls, "func_movelinear") == 0 || StrContains(cls, "func_door") == 0 || StrContains(cls, "func_tracktrain") == 0
		|| StrContains(cls, "func_train") == 0 || StrContains(cls, "func_rotating") == 0)
		g_VipLaserAt[victim] = GetGameTime();
	return Plugin_Continue;
}

void CheckVip(bool zombiesNow)
{
	if (!g_VipOn || !g_RoundLive)
		return;
	float now = GetGameTime();

	// Every VIP fell: the countdown runs, then the humans are slain.
	if (g_VipSlayAt > 0.0)
	{
		if (now >= g_VipSlayAt)
		{
			g_VipSlayAt = 0.0;
			PrintToChatAll(VIP_TAG ... "Time's up - all humans are slain!");
			SlayHumans();
		}
		return;
	}

	int fell = 0, alive = 0;
	for (int s = 0; s < MAX_VIPS; s++)
	{
		if (g_VipList[s] == 0 || g_VipList[s] == -1)
			continue;
		if (s >= g_VipCount)
		{
			g_VipList[s] = 0;   // the count was lowered
			continue;
		}
		int c = GetClientOfUserId(g_VipList[s]);
		if (c == 0)
		{
			g_VipList[s] = 0;
			PrintToChatAll(VIP_TAG ... "A VIP left the server - choosing a new one.");
			continue;
		}
		if (IsHuman(c))
		{
			alive++;
			continue;
		}

		// This VIP is down. A mother-zombie infection or a map laser doesn't count against the humans.
		bool mother = g_HasZR ? g_InfectedAsMother[c] : !g_ZombiesSeen;
		bool laser = g_VipLaserSafe && g_VipLaserAt[c] > 0.0 && now - g_VipLaserAt[c] < 1.5;
		if (mother || laser)
		{
			g_VipList[s] = 0;
			PrintToChatAll(VIP_TAG ... "%N %s - that doesn't count, choosing a new VIP.", c,
				mother ? "became a mother zombie" : "was killed by a laser");
			continue;
		}
		fell++;
		if (g_VipSlay)
		{
			g_VipList[s] = -1;
			PrintToChatAll(VIP_TAG ... "The VIP \x07" ... "FFD700%N\x01 has fallen!", c);
		}
		else
		{
			g_VipList[s] = 0;
			PrintToChatAll(VIP_TAG ... "The VIP \x07" ... "FFD700%N\x01 has fallen! Choosing a new VIP.", c);
		}
	}

	bool allFallen = g_VipSlay;
	for (int s = 0; s < g_VipCount && s < MAX_VIPS && allFallen; s++)
		allFallen = g_VipList[s] == -1;
	if (allFallen)
	{
		if (g_VipDelay <= 0)
		{
			PrintToChatAll(VIP_TAG ... "Every VIP has fallen! All humans are slain.");
			PrintCenterTextAll("EVERY VIP HAS FALLEN!");
			SlayHumans();
		}
		else
		{
			g_VipSlayAt = now + float(g_VipDelay);
			PrintToChatAll(VIP_TAG ... "Every VIP has fallen! All humans die in %d seconds!", g_VipDelay);
			PrintCenterTextAll("EVERY VIP HAS FALLEN!");
		}
		return;
	}
	if (fell > 0 && alive > 0 && g_VipSlay)
		PrintToChatAll(VIP_TAG ... "%d VIP%s still standing - protect %s!", alive, alive == 1 ? "" : "s", alive == 1 ? "them" : "them all");

	// VIPs are handed out once the first zombie is out.
	if (zombiesNow)
		FillVips();
}

// ---------------------------------------------------------------- heal beacon

void ClearBeacons()
{
	for (int s = 0; s < MAX_BEACONS; s++)
	{
		g_HbList[s] = 0;
		HB_RemoveLight(s);
	}
	g_HbArmedAt = 0.0;
}

bool IsBeacon(int client)
{
	int uid = GetClientUserId(client);
	for (int s = 0; s < MAX_BEACONS; s++)
		if (g_HbList[s] != 0 && g_HbList[s] == uid)
			return true;
	return false;
}

// Living carriers right now; returns how many were written to `out`.
int LiveBeacons(int out[MAX_BEACONS])
{
	int n = 0;
	for (int s = 0; s < g_HbCount && s < MAX_BEACONS; s++)
	{
		if (g_HbList[s] == 0)
			continue;
		int c = GetClientOfUserId(g_HbList[s]);
		if (IsHuman(c))
			out[n++] = c;
	}
	return n;
}

int LiveCount()
{
	int list[MAX_BEACONS];
	return LiveBeacons(list);
}

// "Name, Name" of the living carriers.
void BeaconNames(char[] buf, int len)
{
	int list[MAX_BEACONS];
	int n = g_HbOn ? LiveBeacons(list) : 0;
	buf[0] = '\0';
	for (int k = 0; k < n; k++)
		Format(buf, len, "%s%s%N", buf, k == 0 ? "" : ", ", list[k]);
}

void GiveBeacon(int slot, int client, bool announce)
{
	g_HbList[slot] = client == 0 ? 0 : GetClientUserId(client);
	if (client != 0 && g_HbArmedAt == 0.0)
	{
		g_HbArmedAt = GetGameTime() + float(g_HbWarn);
		if (g_HbWarn > 0)
			PrintToChatAll(HB_TAG ... "Get to a beacon - standing outside starts hurting in %d seconds!", g_HbWarn);
	}
	if (client != 0 && announce)
	{
		PrintToChatAll(HB_TAG ... "\x07" ... "55FF55%N\x01 carries a heal beacon! Stay within %d units of a beacon: inside heals %d HP/s, outside costs %d HP/s.",
			client, RoundToNearest(g_HbRadius), g_HbHeal, g_HbDamage);
		PrintCenterTextAll("%N carries a heal beacon!", client);
	}
}

// Hand empty slots (up to the beacon count) to random humans who don't carry one yet.
void FillBeacons()
{
	for (int s = 0; s < g_HbCount && s < MAX_BEACONS; s++)
	{
		if (g_HbList[s] != 0)
			continue;
		int pick = RandomHuman(0, true);
		if (pick == 0)
			return;
		GiveBeacon(s, pick, true);
	}
}

// An empty slot if there is one, else the first carrier hands their beacon over.
void GiveChosenBeacon(int target)
{
	for (int s = 0; s < g_HbCount && s < MAX_BEACONS; s++)
	{
		if (g_HbList[s] == 0 || !IsHuman(GetClientOfUserId(g_HbList[s])))
		{
			GiveBeacon(s, target, true);
			return;
		}
	}
	int old = GetClientOfUserId(g_HbList[0]);
	if (old != 0)
		PrintToChatAll(HB_TAG ... "%N hands their heal beacon over.", old);
	GiveBeacon(0, target, true);
}

void CheckBeacon(bool zombiesNow)
{
	if (!g_HbOn || !g_RoundLive)
		return;

	for (int s = 0; s < MAX_BEACONS; s++)
	{
		if (g_HbList[s] == 0)
			continue;
		if (s >= g_HbCount)
		{
			g_HbList[s] = 0;   // the count was lowered
			continue;
		}
		int hb = GetClientOfUserId(g_HbList[s]);
		if (hb == 0)
		{
			g_HbList[s] = 0;
			PrintToChatAll(HB_TAG ... "A beacon carrier left the server - the beacon passes on.");
			continue;
		}
		if (IsHuman(hb))
			continue;

		g_HbList[s] = 0;
		if (g_HbSlay && g_ZombiesSeen)
		{
			PrintToChatAll(HB_TAG ... "The beacon carrier %N has fallen! All humans are slain.", hb);
			PrintCenterTextAll("The heal beacon %N has fallen!", hb);
			SlayHumans();
			return;
		}
		PrintToChatAll(HB_TAG ... "The beacon carrier %N has fallen! The beacon passes on.", hb);
	}

	// Beacons are handed out once the first zombie is out, so a carrier can't start as the mother zombie.
	if (zombiesNow)
		FillBeacons();
}

// Inside any beacon heals, outside all of them hurts.
void BeaconTick(const int[] carriers, int count)
{
	float centers[MAX_BEACONS][3];
	float pos[3];
	for (int k = 0; k < count; k++)
		GetClientAbsOrigin(carriers[k], centers[k]);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHuman(i))
			continue;
		int hp = GetClientHealth(i);
		if (g_MaxHp[i] == 0)
		{
			// The most they can be healed back to this round: their real max health (ZR classes set it).
			int most = GetEntProp(i, Prop_Data, "m_iMaxHealth");
			if (most < hp)
				most = hp;
			g_MaxHp[i] = most > 100 ? most : 100;
		}

		GetClientAbsOrigin(i, pos);
		g_Outside[i] = true;
		for (int k = 0; k < count; k++)
		{
			if (GetVectorDistance(centers[k], pos) <= g_HbRadius)
			{
				g_Outside[i] = false;
				break;
			}
		}
		if (!g_Outside[i])
		{
			if (g_HbHeal > 0 && hp < g_MaxHp[i])
				SetEntityHealth(i, hp + g_HbHeal > g_MaxHp[i] ? g_MaxHp[i] : hp + g_HbHeal);
		}
		else if (GetGameTime() < g_HbArmedAt)
			continue;   // still the warning period
		else if (hp - g_HbDamage <= 0)
		{
			PrintToChat(i, HB_TAG ... "You strayed too far from the heal beacons.");
			ForcePlayerSuicide(i);
		}
		else
			SetEntityHealth(i, hp - g_HbDamage);
	}
}

// The ring (and light) colour of a carrier's beacon: each beacon its own, or all the same green.
void BeaconColor(int client, int color[4])
{
	int slot = 0, uid = GetClientUserId(client);
	for (int s = 0; s < MAX_BEACONS; s++)
		if (g_HbList[s] == uid)
			slot = s;
	for (int k = 0; k < 4; k++)
		color[k] = g_HbColors ? g_HbPalette[slot][k] : g_HbColor[k];
}

void HB_RemoveLight(int s)
{
	int ent = EntRefToEntIndex(g_HbLight[s]);
	if (ent != INVALID_ENT_REFERENCE && ent > MaxClients)
		AcceptEntityInput(ent, "Kill");
	g_HbLight[s] = INVALID_ENT_REFERENCE;
	g_HbLightOwner[s] = 0;
}

// A coloured glow that follows each carrier (a light_dynamic parented to them), so humans can find
// the beacon in the dark. Made, moved to a new carrier or removed as needed every second.
void HB_SyncLights()
{
	for (int s = 0; s < MAX_BEACONS; s++)
	{
		int c = (g_HbOn && g_HbLightOn && s < g_HbCount && g_HbList[s] > 0) ? GetClientOfUserId(g_HbList[s]) : 0;
		if (c != 0 && !IsHuman(c))
			c = 0;
		bool have = EntRefToEntIndex(g_HbLight[s]) != INVALID_ENT_REFERENCE;
		if (c == 0)
		{
			if (g_HbLight[s] != INVALID_ENT_REFERENCE)
				HB_RemoveLight(s);
			continue;
		}
		if (have && g_HbLightOwner[s] == g_HbList[s])
			continue;
		HB_RemoveLight(s);

		int light = CreateEntityByName("light_dynamic");
		if (light == -1)
			continue;
		int col[4];
		BeaconColor(c, col);
		char value[32];
		Format(value, sizeof(value), "%d %d %d 255", col[0], col[1], col[2]);
		DispatchKeyValue(light, "_light", value);
		DispatchKeyValue(light, "brightness", "4");
		DispatchKeyValueFloat(light, "distance", 220.0);
		DispatchKeyValue(light, "style", "0");
		DispatchSpawn(light);
		float pos[3];
		GetClientAbsOrigin(c, pos);
		pos[2] += 36.0;
		TeleportEntity(light, pos, NULL_VECTOR, NULL_VECTOR);
		SetVariantString("!activator");
		AcceptEntityInput(light, "SetParent", c, light);
		AcceptEntityInput(light, "TurnOn");
		g_HbLight[s] = EntIndexToEntRef(light);
		g_HbLightOwner[s] = g_HbList[s];
	}
}

// ---- admin actions on a carrier

void CarrierListMenu(int client)
{
	Menu menu = new Menu(CarrierListHandler);
	menu.SetTitle("Heal beacon carriers\nPick one for actions\n ");
	char uid[12], name[MAX_NAME_LENGTH];
	for (int s = 0; s < g_HbCount && s < MAX_BEACONS; s++)
	{
		int c = g_HbList[s] > 0 ? GetClientOfUserId(g_HbList[s]) : 0;
		if (c == 0 || !IsHuman(c))
			continue;
		IntToString(g_HbList[s], uid, sizeof(uid));
		GetClientName(c, name, sizeof(name));
		menu.AddItem(uid, name);
	}
	if (menu.ItemCount == 0)
		menu.AddItem("", "No carriers right now", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int CarrierListHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		BeaconMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char uid[12];
		menu.GetItem(item, uid, sizeof(uid));
		CarrierActionMenu(client, StringToInt(uid));
	}
	return 0;
}

void CarrierActionMenu(int client, int uid)
{
	int c = GetClientOfUserId(uid);
	if (c == 0 || !IsHuman(c) || !IsBeacon(c))
	{
		PrintToChat(client, HB_TAG ... "That player doesn't carry a beacon any more.");
		CarrierListMenu(client);
		return;
	}
	Menu menu = new Menu(CarrierActionHandler);
	char title[96], info[24];
	Format(title, sizeof(title), "Heal beacon: %N\n ", c);
	menu.SetTitle(title);
	bool alive = IsPlayerAlive(client);
	Format(info, sizeof(info), "tp:%d", uid);
	menu.AddItem(info, "Teleport to them", alive ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(info, sizeof(info), "bring:%d", uid);
	menu.AddItem(info, "Bring them to me", alive ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(info, sizeof(info), "take:%d", uid);
	menu.AddItem(info, "Give their beacon to someone random");
	Format(info, sizeof(info), "slay:%d", uid);
	menu.AddItem(info, "Slay them");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int CarrierActionHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		CarrierListMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char info[24], parts[2][12];
		menu.GetItem(item, info, sizeof(info));
		ExplodeString(info, ":", parts, sizeof(parts), sizeof(parts[]));
		int uid = StringToInt(parts[1]);
		int c = GetClientOfUserId(uid);
		if (c == 0 || !IsHuman(c) || !IsBeacon(c))
		{
			PrintToChat(client, HB_TAG ... "That player doesn't carry a beacon any more.");
			CarrierListMenu(client);
			return 0;
		}
		float pos[3];
		if (StrEqual(parts[0], "tp") && IsPlayerAlive(client))
		{
			GetClientAbsOrigin(c, pos);
			TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
			LogAction(client, c, "\"%L\" teleported to \"%L\" (heal beacon carrier)", client, c);
		}
		else if (StrEqual(parts[0], "bring") && IsPlayerAlive(client))
		{
			GetClientAbsOrigin(client, pos);
			TeleportEntity(c, pos, NULL_VECTOR, NULL_VECTOR);
			LogAction(client, c, "\"%L\" brought \"%L\" (heal beacon carrier)", client, c);
		}
		else if (StrEqual(parts[0], "take"))
		{
			for (int s = 0; s < MAX_BEACONS; s++)
				if (g_HbList[s] == uid)
					g_HbList[s] = 0;
			PrintToChatAll(HB_TAG ... "%N's heal beacon was handed to someone else.", c);
			FillBeacons();
			LogAction(client, c, "\"%L\" took the heal beacon from \"%L\"", client, c);
			CarrierListMenu(client);
			return 0;
		}
		else if (StrEqual(parts[0], "slay"))
		{
			PrintToChatAll(HB_TAG ... "An admin slayed the beacon carrier %N.", c);
			ForcePlayerSuicide(c);
			LogAction(client, c, "\"%L\" slayed \"%L\" (heal beacon carrier)", client, c);
			CarrierListMenu(client);
			return 0;
		}
		CarrierActionMenu(client, uid);
	}
	return 0;
}

// ---------------------------------------------------------------- timers

// Modes that follow the round (who's human, who's zombie).
bool AnyRoundMode()
{
	return g_VipOn || g_HbOn || Potato_IsOn() || Buddy_IsOn() || Lightning_IsOn() || RLGL_IsOn() || Simon_IsOn()
		|| TS_IsOn() || IC_IsOn() || BO_IsOn() || GZ_IsOn() || BZ_IsOn() || EQ_IsOn() || Hero_IsOn() || LS_IsOn() || FL_IsOn()
		|| SW_IsOn() || TG_IsOn() || RD_IsOn() || WG_IsOn() || TN_IsOn() || MG_IsOn();
}

void Check()
{
	bool zombiesNow = ZombiesAlive();
	CheckVip(zombiesNow);
	CheckBeacon(zombiesNow);
	Potato_Check(zombiesNow);
	Buddy_Check(zombiesNow);
	RLGL_Check();
	Simon_Check();
	GZ_Check();
	BZ_Check(zombiesNow);
	EQ_Check();
	Hero_Check(zombiesNow);
	LS_Check();
	FL_Check();
	SW_Check();
	TG_Check();
	RD_Check();
	WG_Check();
	TN_Check();
	MG_Check();
	if (zombiesNow)
		g_ZombiesSeen = true;
}

public Action Timer_Check(Handle timer)
{
	if (g_RoundLive && AnyRoundMode())
		Check();
	Physics_Apply();   // shared speed (Boss, Hero, Last Stand)
	ZMarket_Sync();    // !zmarket off during Random Weapons / Gun Game
	return Plugin_Continue;
}

public Action Timer_Tick(Handle timer)
{
	if (!g_RoundLive)
		return Plugin_Continue;

	int vips[MAX_VIPS];
	int vipCount = g_VipOn ? LiveVips(vips) : 0;
	char vipNames[160];
	VipNames(vipNames, sizeof(vipNames));
	int carriers[MAX_BEACONS];
	int hbCount = g_HbOn ? LiveBeacons(carriers) : 0;
	char hbNames[192];
	BeaconNames(hbNames, sizeof(hbNames));

	if (g_VipBeacon)
		for (int k = 0; k < vipCount; k++)
			Ring(vips[k], g_VipColor, 80.0);
	for (int k = 0; k < hbCount; k++)
	{
		int col[4];
		BeaconColor(carriers[k], col);
		Ring(carriers[k], col, g_HbRadius);
		if (g_HbSound)
		{
			float pos[3];
			GetClientAbsOrigin(carriers[k], pos);
			EmitAmbientSound(BEACON_SOUND, pos, carriers[k], SNDLEVEL_NORMAL);
		}
	}
	if (hbCount > 0)
		BeaconTick(carriers, hbCount);
	HB_SyncLights();

	// On-screen names for everyone (held a bit over a second, refreshed every second).
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		if (g_VipOn && g_VipSlayAt > 0.0)
		{
			SetHudTextParams(-1.0, 0.10, 1.1, 255, 40, 40, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudVip, "EVERY VIP HAS FALLEN - HUMANS DIE IN %d", RoundToCeil(g_VipSlayAt - GetGameTime()));
		}
		else if (vipCount > 0)
		{
			SetHudTextParams(-1.0, 0.10, 1.1, 255, 215, 0, 255, 0, 0.0, 0.0, 0.0);
			if (IsVip(i) && IsHuman(i))
				EM_ShowHud(i, g_HudVip, "YOU ARE A VIP - STAY ALIVE!");
			else
				EM_ShowHud(i, g_HudVip, vipCount > 1 ? "VIPs: %s" : "VIP: %s", vipNames);
		}
		if (hbCount > 0)
		{
			if (IsBeacon(i) && IsHuman(i))
			{
				SetHudTextParams(-1.0, 0.14, 1.1, 60, 255, 60, 255, 0, 0.0, 0.0, 0.0);
				EM_ShowHud(i, g_HudHb, "YOU CARRY A HEAL BEACON - STAY ALIVE!");
			}
			else if (IsHuman(i) && g_Outside[i])
			{
				SetHudTextParams(-1.0, 0.14, 1.1, 255, 60, 60, 255, 0, 0.0, 0.0, 0.0);
				EM_ShowHud(i, g_HudHb, "OUTSIDE THE HEAL BEACON%s (%s) - GET BACK! -%d HP/s",
					hbCount > 1 ? "S" : "", hbNames, g_HbDamage);
			}
			else
			{
				SetHudTextParams(-1.0, 0.14, 1.1, 60, 255, 60, 255, 0, 0.0, 0.0, 0.0);
				EM_ShowHud(i, g_HudHb, "Heal beacon%s: %s", hbCount > 1 ? "s" : "", hbNames);
			}
		}
	}
	Potato_Tick();
	Buddy_Tick();
	Lightning_Tick();
	GG_Tick();
	MQ_Tick();
	RLGL_Tick();
	Simon_Tick();
	TS_Tick();
	IC_Tick();
	BO_Tick();
	BZ_Tick();
	EQ_Tick();
	Hero_Tick();
	LS_Tick();
	FL_Tick();
	ZD_Tick();
	TV_Tick();
	HS_Tick();
	MT_Tick();
	AS_Tick();
	SW_Tick();
	NK_Tick();
	TG_Tick();
	RD_Tick();
	AR_Tick();
	FC_Tick();
	SD_Tick();
	GW_Tick();
	IF_Tick();
	WG_Tick();
	TN_Tick();
	QS_Tick();
	MG_Tick();
	HL_Tick();
	LC_Tick();
	JG_Tick();
	BF_Tick();
	ZF_Tick();
	Roulette_Tick();
	return Plugin_Continue;
}

// ---------------------------------------------------------------- commands

public Action Cmd_Who(int client, int args)
{
	char vipNames[160];
	VipNames(vipNames, sizeof(vipNames));
	if (!g_VipOn)
		ReplyToCommand(client, "[VIP] VIP mode is off.");
	else if (vipNames[0] == '\0')
		ReplyToCommand(client, "[VIP] No VIPs yet - they're chosen when the first zombie appears.");
	else
		ReplyToCommand(client, "[VIP] VIPs: %s", vipNames);
	if (g_HbOn)
	{
		char names[192];
		BeaconNames(names, sizeof(names));
		if (names[0] == '\0')
			ReplyToCommand(client, "[Heal Beacon] No beacon carriers yet.");
		else
			ReplyToCommand(client, "[Heal Beacon] Carriers: %s (radius %d).", names, RoundToNearest(g_HbRadius));
	}
	return Plugin_Handled;
}

// !em opens the menu; "sm_em <mode> [on|off]", "sm_em list" and "sm_em stop" work from chat, console and rcon.
public Action Cmd_Menu(int client, int args)
{
	if (!HasAccess(client))
	{
		ReplyToCommand(client, "[Event] You don't have access to the event modes.");
		return Plugin_Handled;
	}
	if (args >= 1)
	{
		EM_Console(client, args);
		return Plugin_Handled;
	}
	if (client == 0)
	{
		ReplyToCommand(client, "[Event] Usage: sm_em <mode> [on|off]  |  sm_em list  |  sm_em stop");
		return Plugin_Handled;
	}
	MainMenu(client);
	return Plugin_Handled;
}

// ---------------------------------------------------------------- menus
//
// !em: Event Roulette, five categories of modes, Fog and Stop all. A mode's Back button goes back to
// the category it was opened from (ModeBack).

enum { CAT_SURVIVAL = 0, CAT_WEAPONS, CAT_HAZARDS, CAT_WEATHER, CAT_CHAOS, CAT_GAMES, CAT_ZOMBIES, CAT_COUNT }
char g_CatNames[][] = { "Survival rules", "Weapons", "Hazards & disasters", "Weather & nature", "Chaos & tricks", "Mini-games", "Zombies" };
#define CAT_SLOTS 10
char g_CatModes[CAT_COUNT][CAT_SLOTS][12] =
{
	{ "vip", "hb", "potato", "buddy", "hero", "laststand", "", "", "", "" },
	{ "rw", "gg", "jam", "butter", "", "", "", "", "", "" },
	{ "lightning", "quake", "lava", "drop", "meteor", "airstrike", "shockwave", "nuke", "gas", "radiation" },
	{ "fog", "acid", "cold", "darkness", "gravity", "ice", "wind", "tornado", "quicksand", "" },
	{ "teleport", "invert", "blackout", "magnet", "halluc", "leech", "doublejump", "", "", "" },
	{ "quiz", "trivia", "hotseat", "rlgl", "simon", "", "", "", "", "" },
	{ "boss", "ghost", "frenzy", "", "", "", "", "", "", "" }
};
char g_ModeKeys[][] =
{
	"vip", "hb", "potato", "buddy", "rw", "gg", "lightning", "quake", "teleport", "invert", "blackout",
	"quiz", "rlgl", "simon", "boss", "ghost", "hero", "laststand", "lava", "drop", "trivia", "hotseat", "fog",
	"meteor", "airstrike", "shockwave", "nuke", "gas", "radiation", "acid", "cold", "darkness", "gravity", "ice", "wind", "tornado", "quicksand", "magnet", "halluc", "leech", "jam", "butter", "frenzy", "doublejump"
};
char g_ModeNames[][] =
{
	"VIP Mode", "Heal Beacon", "Hot Potato", "Buddy System", "Random Weapons", "Gun Game",
	"Lightning Strikes", "Earthquake", "Teleport Shuffle", "Inverted Controls", "Blackout / Flashbang",
	"Math Quiz", "Red Light, Green Light", "Simon Says", "Boss Zombie", "Ghost Zombies", "Hero", "Last Stand",
	"Floor is Lava", "Zombie Drop", "Trivia", "Hot Seat", "Fog",
	"Meteor Shower", "Airstrike", "Shockwave", "Nuke Countdown", "Toxic Gas", "Radiation", "Acid Rain", "Freezing Cold", "Sudden Darkness", "Gravity Waves", "Ice Floor", "Wind Gusts", "Tornado", "Quicksand", "Magnet Pull", "Hallucinations", "Leech", "Jammed Guns", "Butterfingers", "Zombie Frenzy", "Double Jump"
};
int g_MenuCat[MAXPLAYERS + 1] = { -1, ... };   // category the client's open mode page came from

bool ModeOn(const char[] key)
{
	if (StrEqual(key, "vip")) return g_VipOn;
	if (StrEqual(key, "hb")) return g_HbOn;
	if (StrEqual(key, "potato")) return Potato_IsOn();
	if (StrEqual(key, "buddy")) return Buddy_IsOn();
	if (StrEqual(key, "rw")) return RW_IsOn();
	if (StrEqual(key, "gg")) return GG_IsOn();
	if (StrEqual(key, "lightning")) return Lightning_IsOn();
	if (StrEqual(key, "quake")) return EQ_IsOn();
	if (StrEqual(key, "teleport")) return TS_IsOn();
	if (StrEqual(key, "invert")) return IC_IsOn();
	if (StrEqual(key, "blackout")) return BO_IsOn();
	if (StrEqual(key, "quiz")) return MQ_IsOn();
	if (StrEqual(key, "rlgl")) return RLGL_IsOn();
	if (StrEqual(key, "simon")) return Simon_IsOn();
	if (StrEqual(key, "boss")) return BZ_IsOn();
	if (StrEqual(key, "ghost")) return GZ_IsOn();
	if (StrEqual(key, "hero")) return Hero_IsOn();
	if (StrEqual(key, "laststand")) return LS_IsOn();
	if (StrEqual(key, "lava")) return FL_IsOn();
	if (StrEqual(key, "drop")) return ZD_IsOn();
	if (StrEqual(key, "trivia")) return TV_IsOn();
	if (StrEqual(key, "hotseat")) return HS_IsOn();
	if (StrEqual(key, "fog")) return FogIsOn();
	if (StrEqual(key, "meteor")) return MT_IsOn();
	if (StrEqual(key, "airstrike")) return AS_IsOn();
	if (StrEqual(key, "shockwave")) return SW_IsOn();
	if (StrEqual(key, "nuke")) return NK_IsOn();
	if (StrEqual(key, "gas")) return TG_IsOn();
	if (StrEqual(key, "radiation")) return RD_IsOn();
	if (StrEqual(key, "acid")) return AR_IsOn();
	if (StrEqual(key, "cold")) return FC_IsOn();
	if (StrEqual(key, "darkness")) return SD_IsOn();
	if (StrEqual(key, "gravity")) return GW_IsOn();
	if (StrEqual(key, "ice")) return IF_IsOn();
	if (StrEqual(key, "wind")) return WG_IsOn();
	if (StrEqual(key, "tornado")) return TN_IsOn();
	if (StrEqual(key, "quicksand")) return QS_IsOn();
	if (StrEqual(key, "magnet")) return MG_IsOn();
	if (StrEqual(key, "halluc")) return HL_IsOn();
	if (StrEqual(key, "leech")) return LC_IsOn();
	if (StrEqual(key, "jam")) return JG_IsOn();
	if (StrEqual(key, "butter")) return BF_IsOn();
	if (StrEqual(key, "frenzy")) return ZF_IsOn();
	if (StrEqual(key, "doublejump")) return DJ_IsOn();
	return false;
}

void OpenMode(int client, const char[] key)
{
	if (StrEqual(key, "vip")) VipMenu(client);
	else if (StrEqual(key, "hb")) BeaconMenu(client);
	else if (StrEqual(key, "potato")) PotatoMenu(client);
	else if (StrEqual(key, "buddy")) BuddyMenu(client);
	else if (StrEqual(key, "rw")) RwMenu(client);
	else if (StrEqual(key, "gg")) GGMenu(client);
	else if (StrEqual(key, "lightning")) LightningMenu(client);
	else if (StrEqual(key, "quake")) EQMenu(client);
	else if (StrEqual(key, "teleport")) TSMenu(client);
	else if (StrEqual(key, "invert")) ICMenu(client);
	else if (StrEqual(key, "blackout")) BOMenu(client);
	else if (StrEqual(key, "quiz")) QuizMenu(client);
	else if (StrEqual(key, "rlgl")) RLGLMenu(client);
	else if (StrEqual(key, "simon")) SimonMenu(client);
	else if (StrEqual(key, "boss")) BZMenu(client);
	else if (StrEqual(key, "ghost")) GZMenu(client);
	else if (StrEqual(key, "hero")) HeroMenu(client);
	else if (StrEqual(key, "laststand")) LSMenu(client);
	else if (StrEqual(key, "lava")) FLMenu(client);
	else if (StrEqual(key, "drop")) ZDMenu(client);
	else if (StrEqual(key, "trivia")) TVMenu(client);
	else if (StrEqual(key, "hotseat")) HSMenu(client);
	else if (StrEqual(key, "fog")) FogMenu(client);
	else if (StrEqual(key, "meteor")) MTMenu(client);
	else if (StrEqual(key, "airstrike")) ASMenu(client);
	else if (StrEqual(key, "shockwave")) SWMenu(client);
	else if (StrEqual(key, "nuke")) NKMenu(client);
	else if (StrEqual(key, "gas")) TGMenu(client);
	else if (StrEqual(key, "radiation")) RDMenu(client);
	else if (StrEqual(key, "acid")) ARMenu(client);
	else if (StrEqual(key, "cold")) FCMenu(client);
	else if (StrEqual(key, "darkness")) SDMenu(client);
	else if (StrEqual(key, "gravity")) GWMenu(client);
	else if (StrEqual(key, "ice")) IFMenu(client);
	else if (StrEqual(key, "wind")) WGMenu(client);
	else if (StrEqual(key, "tornado")) TNMenu(client);
	else if (StrEqual(key, "quicksand")) QSMenu(client);
	else if (StrEqual(key, "magnet")) MGMenu(client);
	else if (StrEqual(key, "halluc")) HLMenu(client);
	else if (StrEqual(key, "leech")) LCMenu(client);
	else if (StrEqual(key, "jam")) JGMenu(client);
	else if (StrEqual(key, "butter")) BFMenu(client);
	else if (StrEqual(key, "frenzy")) ZFMenu(client);
	else if (StrEqual(key, "doublejump")) DJMenu(client);
}

void ModeName(const char[] key, char[] buf, int len)
{
	strcopy(buf, len, key);
	for (int i = 0; i < sizeof(g_ModeKeys); i++)
		if (StrEqual(key, g_ModeKeys[i]))
			strcopy(buf, len, g_ModeNames[i]);
}

int CategoryOnCount(int cat)
{
	int n = 0;
	for (int k = 0; k < CAT_SLOTS; k++)
		if (g_CatModes[cat][k][0] != '\0' && ModeOn(g_CatModes[cat][k]))
			n++;
	return n;
}

void ModeBack(int client)
{
	if (g_MenuCat[client] >= 0)
		CategoryMenu(client, g_MenuCat[client]);
	else
		MainMenu(client);
}

void MainMenu(int client)
{
	g_MenuCat[client] = -1;
	Menu menu = new Menu(MainHandler);
	menu.SetTitle("Event Modes\n ");
	char line[64], key[8];
	Format(line, sizeof(line), "Event Roulette [%s]", Roulette_IsOn() ? "ON" : "OFF");
	menu.AddItem("roulette", line);
	for (int cat = 0; cat < CAT_COUNT; cat++)
	{
		int on = CategoryOnCount(cat);
		if (on > 0)
			Format(line, sizeof(line), "%s  (%d on)", g_CatNames[cat], on);
		else
			strcopy(line, sizeof(line), g_CatNames[cat]);
		Format(key, sizeof(key), "cat%d", cat);
		menu.AddItem(key, line);
	}
	bool anything = Roulette_IsOn();
	for (int m = 0; m < sizeof(g_ModeKeys) && !anything; m++)
		anything = ModeOn(g_ModeKeys[m]);
	menu.AddItem("tools", anything ? "Admin tools (stop all, save settings)" : "Admin tools (save settings)");
	menu.Pagination = MENU_NO_PAGINATION;   // all 9 on one page
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void StopAllModes()
{
	Roulette_Stop();   // first: it switches off what it turned on
	g_VipOn = false;
	g_HbOn = false;
	ClearVips();
	ClearBeacons();
	RW_Stop();
	GG_Stop();
	Potato_Stop();
	Buddy_Stop();
	Lightning_Stop();
	MQ_Stop();
	RLGL_Stop();
	Simon_Stop();
	TS_Stop();
	IC_Stop();
	BO_Stop();
	GZ_Stop();
	BZ_Stop();
	EQ_Stop();
	Hero_Stop();
	LS_Stop();
	FL_Stop();
	ZD_Stop();
	TV_Stop();
	HS_Stop();
	MT_Stop();
	AS_Stop();
	SW_Stop();
	NK_Stop();
	TG_Stop();
	RD_Stop();
	AR_Stop();
	FC_Stop();
	SD_Stop();
	GW_Stop();
	IF_Stop();
	WG_Stop();
	TN_Stop();
	QS_Stop();
	MG_Stop();
	HL_Stop();
	LC_Stop();
	JG_Stop();
	BF_Stop();
	ZF_Stop();
	DJ_Stop();
	if (g_Active)
		Restore();   // fog back to the map's own
}

public int MainHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "roulette"))
			RouletteMenu(client);
		else if (StrContains(info, "cat") == 0)
			CategoryMenu(client, StringToInt(info[3]));
		else if (StrEqual(info, "tools"))
			ToolsMenu(client);
	}
	return 0;
}

// Stop everything, and the saved settings (saved automatically at every map change too).
void ToolsMenu(int client)
{
	Menu menu = new Menu(ToolsHandler);
	menu.SetTitle("Event Modes - Admin tools\nSettings are saved automatically at every map change\n ");
	bool anything = Roulette_IsOn();
	for (int m = 0; m < sizeof(g_ModeKeys) && !anything; m++)
		anything = ModeOn(g_ModeKeys[m]);
	menu.AddItem("stop", "Stop all modes", anything ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("save", "Save all settings now");
	menu.AddItem("load", "Reload the saved settings");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ToolsHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		MainMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "stop"))
		{
			StopAllModes();
			PrintToChatAll("\x07" ... "FFD700[Event]\x01 %N stopped all event modes.", client);
			LogAction(client, -1, "\"%L\" stopped all event modes", client);
		}
		else if (StrEqual(info, "save"))
		{
			if (Settings_Save())
				PrintToChat(client, "\x07" ... "FFD700[Event]\x01 Settings saved to addons/sourcemod/%s.", SETTINGS_FILE);
			else
				PrintToChat(client, "\x07" ... "FFD700[Event]\x01 Couldn't write addons/sourcemod/%s - check the folder's permissions.", SETTINGS_FILE);
			LogAction(client, -1, "\"%L\" saved the event mode settings", client);
		}
		else if (StrEqual(info, "load"))
		{
			if (Settings_Load())
				PrintToChat(client, "\x07" ... "FFD700[Event]\x01 Saved settings loaded.");
			else
				PrintToChat(client, "\x07" ... "FFD700[Event]\x01 No saved settings yet.");
		}
		ToolsMenu(client);
	}
	return 0;
}

void CategoryMenu(int client, int cat)
{
	g_MenuCat[client] = cat;
	Menu menu = new Menu(CategoryHandler);
	char title[64], line[64], name[48];
	Format(title, sizeof(title), "Event Modes - %s\n ", g_CatNames[cat]);
	menu.SetTitle(title);
	for (int k = 0; k < CAT_SLOTS; k++)
	{
		if (g_CatModes[cat][k][0] == '\0')
			continue;
		ModeName(g_CatModes[cat][k], name, sizeof(name));
		Format(line, sizeof(line), "%s [%s]", name, ModeOn(g_CatModes[cat][k]) ? "ON" : "OFF");
		menu.AddItem(g_CatModes[cat][k], line);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int CategoryHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		MainMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char key[16];
		menu.GetItem(item, key, sizeof(key));
		OpenMode(client, key);
	}
	return 0;
}

void VipMenu(int client)
{
	Menu menu = new Menu(VipHandler);
	char title[256], line[64], names[160];
	VipNames(names, sizeof(names));
	if (!g_VipOn)
		Format(title, sizeof(title), "VIP Mode - OFF\n ");
	else if (g_VipSlayAt > 0.0)
		Format(title, sizeof(title), "VIP Mode - ON\nEvery VIP has fallen!\n ");
	else if (names[0] == '\0')
		Format(title, sizeof(title), "VIP Mode - ON\nVIPs: chosen when the first zombie appears\n ");
	else
		Format(title, sizeof(title), "VIP Mode - ON\nVIPs: %s\n ", names);
	menu.SetTitle(title);

	menu.AddItem("toggle", g_VipOn ? "Turn VIP mode OFF" : "Turn VIP mode ON");
	int draw = (g_VipOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
	menu.AddItem("random", "New random VIPs now", draw);
	menu.AddItem("choose", "Make someone a VIP...", draw);
	Format(line, sizeof(line), "VIPs: %d", g_VipCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "If every VIP falls: %s", g_VipSlay ? "slay all humans" : "pick new VIPs");
	menu.AddItem("slay", line);
	if (g_VipDelay == 0)
		strcopy(line, sizeof(line), "Countdown before the slay: none");
	else
		Format(line, sizeof(line), "Countdown before the slay: %d s", g_VipDelay);
	menu.AddItem("delay", line, g_VipSlay ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Killed by a map laser: %s", g_VipLaserSafe ? "doesn't count" : "counts");
	menu.AddItem("laser", line);
	Format(line, sizeof(line), "Ring on the VIPs: %s", g_VipBeacon ? "ON" : "OFF");
	menu.AddItem("beacon", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int VipHandler(Menu menu, MenuAction action, int client, int item)
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
			g_VipOn = !g_VipOn;
			ClearVips();
			if (g_VipOn)
				PrintToChatAll(VIP_TAG ... "%N turned VIP mode ON. VIPs are chosen when the first zombie appears.", client);
			else
				PrintToChatAll(VIP_TAG ... "%N turned VIP mode OFF.", client);
			LogAction(client, -1, "\"%L\" turned VIP mode %s", client, g_VipOn ? "on" : "off");
		}
		else if (StrEqual(info, "random"))
		{
			ClearVips();
			FillVips();
		}
		else if (StrEqual(info, "choose"))
		{
			PlayerMenu(client, true);
			return 0;
		}
		else if (StrEqual(info, "count"))
		{
			g_VipCount = g_VipCount >= MAX_VIPS ? 1 : g_VipCount + 1;
			for (int s = g_VipCount; s < MAX_VIPS; s++)
				g_VipList[s] = 0;
		}
		else if (StrEqual(info, "slay"))
			g_VipSlay = !g_VipSlay;
		else if (StrEqual(info, "delay"))
			g_VipDelay = NextInt(g_VipDelaySteps, sizeof(g_VipDelaySteps), g_VipDelay);
		else if (StrEqual(info, "laser"))
			g_VipLaserSafe = !g_VipLaserSafe;
		else if (StrEqual(info, "beacon"))
			g_VipBeacon = !g_VipBeacon;
		VipMenu(client);
	}
	return 0;
}

void BeaconMenu(int client, int firstItem = 0)
{
	Menu menu = new Menu(BeaconHandler);
	char title[256], line[64], names[192];
	BeaconNames(names, sizeof(names));
	if (!g_HbOn)
		Format(title, sizeof(title), "Heal Beacon - OFF\n ");
	else if (names[0] == '\0')
		Format(title, sizeof(title), "Heal Beacon - ON\nCarriers: chosen when the first zombie appears\n ");
	else
		Format(title, sizeof(title), "Heal Beacon - ON\nCarriers: %s\n ", names);
	menu.SetTitle(title);

	menu.AddItem("toggle", g_HbOn ? "Turn Heal Beacon OFF" : "Turn Heal Beacon ON");
	int draw = (g_HbOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
	menu.AddItem("random", "New random carriers now", draw);
	menu.AddItem("choose", "Give a beacon to...", draw);
	Format(line, sizeof(line), "Beacons: %d", g_HbCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "Radius: %d", RoundToNearest(g_HbRadius));
	menu.AddItem("radius", line);
	Format(line, sizeof(line), "Heal inside: %d HP/s", g_HbHeal);
	menu.AddItem("heal", line);
	Format(line, sizeof(line), "Damage outside: %d HP/s", g_HbDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Beep sound: %s", g_HbSound ? "ON" : "OFF");
	menu.AddItem("sound", line);
	Format(line, sizeof(line), "If a carrier dies: %s", g_HbSlay ? "slay all humans" : "pass the beacon on");
	menu.AddItem("slay", line);
	if (g_HbWarn == 0)
		strcopy(line, sizeof(line), "Warning before it hurts: none");
	else
		Format(line, sizeof(line), "Warning before it hurts: %d s", g_HbWarn);
	menu.AddItem("warn", line);
	Format(line, sizeof(line), "Glow light on carriers: %s", g_HbLightOn ? "ON" : "OFF");
	menu.AddItem("light", line);
	Format(line, sizeof(line), "Colours: %s", g_HbColors ? "different per beacon" : "all green");
	menu.AddItem("colors", line);
	menu.AddItem("actions", "Carrier actions (teleport, bring, slay...)", (g_HbOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int BeaconHandler(Menu menu, MenuAction action, int client, int item)
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
			g_HbOn = !g_HbOn;
			ClearBeacons();
			if (g_HbOn)
				PrintToChatAll(HB_TAG ... "%N turned the Heal Beacon ON (%d beacon%s). Stay inside a beacon once the zombies come!",
					client, g_HbCount, g_HbCount > 1 ? "s" : "");
			else
				PrintToChatAll(HB_TAG ... "%N turned the Heal Beacon OFF.", client);
			LogAction(client, -1, "\"%L\" turned the heal beacon %s", client, g_HbOn ? "on" : "off");
		}
		else if (StrEqual(info, "random"))
		{
			ClearBeacons();
			FillBeacons();
			if (LiveCount() == 0)
				PrintToChat(client, HB_TAG ... "No living human to pick.");
		}
		else if (StrEqual(info, "choose"))
		{
			PlayerMenu(client, false);
			return 0;
		}
		else if (StrEqual(info, "count"))
		{
			g_HbCount = g_HbCount >= MAX_BEACONS ? 1 : g_HbCount + 1;
			for (int s = g_HbCount; s < MAX_BEACONS; s++)
			{
				int c = g_HbList[s] != 0 ? GetClientOfUserId(g_HbList[s]) : 0;
				if (c != 0 && g_HbOn)
					PrintToChatAll(HB_TAG ... "%N no longer carries a heal beacon.", c);
				g_HbList[s] = 0;
			}
			if (g_HbOn)
				PrintToChatAll(HB_TAG ... "%N set the number of heal beacons to %d.", client, g_HbCount);
		}
		else if (StrEqual(info, "radius"))
			g_HbRadius = NextFloat(g_RadiusSteps, sizeof(g_RadiusSteps), g_HbRadius);
		else if (StrEqual(info, "heal"))
			g_HbHeal = NextInt(g_HealSteps, sizeof(g_HealSteps), g_HbHeal);
		else if (StrEqual(info, "damage"))
			g_HbDamage = NextInt(g_DamageSteps, sizeof(g_DamageSteps), g_HbDamage);
		else if (StrEqual(info, "sound"))
			g_HbSound = !g_HbSound;
		else if (StrEqual(info, "slay"))
			g_HbSlay = !g_HbSlay;
		else if (StrEqual(info, "warn"))
			g_HbWarn = NextInt(g_HbWarnSteps, sizeof(g_HbWarnSteps), g_HbWarn);
		else if (StrEqual(info, "light"))
			g_HbLightOn = !g_HbLightOn;
		else if (StrEqual(info, "colors"))
		{
			g_HbColors = !g_HbColors;
			for (int s = 0; s < MAX_BEACONS; s++)
				HB_RemoveLight(s);   // re-made in the new colour
		}
		else if (StrEqual(info, "actions"))
		{
			CarrierListMenu(client);
			return 0;
		}
		BeaconMenu(client, GetMenuSelectionPosition());
	}
	return 0;
}

// The next value in a cycle after `cur` (wraps around; an off-list value goes to the first one above it).
// Same for small decimal steps (speeds, seconds): the first one above cur, else wrap round.
float NextStep(const float[] steps, int count, float cur)
{
	for (int i = 0; i < count; i++)
		if (steps[i] > cur + 0.01)
			return steps[i];
	return steps[0];
}

float NextFloat(const float[] steps, int count, float cur)
{
	for (int i = 0; i < count; i++)
		if (steps[i] > cur + 0.5)
			return steps[i];
	return steps[0];
}

int NextInt(const int[] steps, int count, int cur)
{
	for (int i = 0; i < count; i++)
		if (steps[i] > cur)
			return steps[i];
	return steps[0];
}

// Living humans to pick from; forVip says which role the pick is for.
void PlayerMenu(int client, bool forVip)
{
	Menu menu = new Menu(forVip ? PickVipHandler : PickBeaconHandler);
	menu.SetTitle(forVip ? "Choose the VIP\n " : "Give a heal beacon to\n(when all beacons are taken, the first carrier hands theirs over)\n ");
	char uid[12], name[MAX_NAME_LENGTH + 12];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHuman(i))
			continue;
		IntToString(GetClientUserId(i), uid, sizeof(uid));
		GetClientName(i, name, sizeof(name));
		if (!forVip && g_HbOn && IsBeacon(i))
			Format(name, sizeof(name), "%s [beacon]", name);
		menu.AddItem(uid, name);
	}
	if (menu.ItemCount == 0)
		menu.AddItem("", "No living humans", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int PickedClient(Menu menu, int item)
{
	char uid[12];
	menu.GetItem(item, uid, sizeof(uid));
	int target = GetClientOfUserId(StringToInt(uid));
	return IsHuman(target) ? target : 0;
}

public int PickVipHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		VipMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		int target = PickedClient(menu, item);
		if (target == 0)
			PrintToChat(client, VIP_TAG ... "That player is no longer a living human.");
		else
		{
			GiveChosenVip(target);
			LogAction(client, target, "\"%L\" made \"%L\" a VIP", client, target);
		}
		VipMenu(client);
	}
	return 0;
}

public int PickBeaconHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		BeaconMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		int target = PickedClient(menu, item);
		if (target == 0)
			PrintToChat(client, HB_TAG ... "That player is no longer a living human.");
		else if (IsBeacon(target))
			PrintToChat(client, HB_TAG ... "%N already carries a beacon.", target);
		else
		{
			GiveChosenBeacon(target);
			LogAction(client, target, "\"%L\" gave a heal beacon to \"%L\"", client, target);
		}
		BeaconMenu(client);
	}
	return 0;
}

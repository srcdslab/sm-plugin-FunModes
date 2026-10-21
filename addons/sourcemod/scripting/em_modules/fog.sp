// Fog module of eventmodes.sp: admin-controlled fog on any map (sm_fog / !fog and the menu's Fog page).
// eventmodes.sp calls Fog_PluginStart / Fog_MapStart / Fog_MapEnd from its own forwards.

#if defined _em_fog_included
 #endinput
#endif
#define _em_fog_included

#define OUR_NAME         "fogadmin_ctrl"
#define PLAYER_CTRL_PROP "m_PlayerFog.m_hCtrl"
#define FOG_TAG          "\x07" ... "99CCFF[Fog]\x01 "   // kept apart: \x would eat the hex colour digits

enum
{
	F_ENABLE = 0,
	F_BLEND,
	F_FARZ,
	F_START,
	F_END,
	F_DENSITY,
	F_C1,
	F_C2,
	F_COUNT
}

char g_CtrlProp[F_COUNT][] =
{
	"m_fog.enable", "m_fog.blend", "m_fog.farz", "m_fog.start", "m_fog.end",
	"m_fog.maxdensity", "m_fog.colorPrimary", "m_fog.colorSecondary"
};

char g_SkyProp[F_COUNT][] =
{
	"m_skybox3d.fog.enable", "m_skybox3d.fog.blend", "", "m_skybox3d.fog.start", "m_skybox3d.fog.end",
	"m_skybox3d.fog.maxdensity", "m_skybox3d.fog.colorPrimary", "m_skybox3d.fog.colorSecondary"
};

enum
{
	MODE_UNKNOWN = 0,
	MODE_PROPS,    // netprops: exact values, smooth fades, exact reset
	MODE_INPUTS    // fallback: entity inputs, can't read values back (reset can't restore the map's own)
}

enum struct FogVals
{
	bool enable;
	bool blend;
	float farz;
	float startDist;
	float endDist;
	float density;
	float c1[3];
	float c2[3];

	void Defaults()
	{
		this.enable = true;
		this.blend = false;
		this.farz = -1.0;
		this.startDist = 0.0;
		this.endDist = 2000.0;
		this.density = 1.0;
		for (int i = 0; i < 3; i++)
		{
			this.c1[i] = 125.0;
			this.c2[i] = 125.0;
		}
	}
}

ConVar g_cvFade;
ConVar g_cvSky;
ConVar g_cvAnnounce;
ConVar g_cvInterval;

bool g_Active;              // admin override on?
bool g_Lerping;
float g_Fade = -1.0;        // "sm_fog fade" for this map; -1 = use sm_dynamicfog_fade
int g_SkyOverride = -1;     // "sm_fog sky" for this map; -1 = use sm_dynamicfog_skybox
FogVals g_Cur;              // values shown right now
FogVals g_From;
FogVals g_To;
float g_T0;
float g_T1;
float g_NextLerpApply;

ArrayList g_OrigRefs;       // map controllers as they were before the takeover (entity refs) ...
ArrayList g_OrigVals;       // ... and their values, same order
FogVals g_OrigSky;          // skybox fog before the takeover
bool g_HaveOrigSky;

int g_OurRef = INVALID_ENT_REFERENCE;
Handle g_Timer;

int g_Mode = MODE_UNKNOWN;
bool g_HasCtrl[F_COUNT];
bool g_HasSky[F_COUNT];
bool g_HasPlayerCtrl;
bool g_PlayerProbed;
int g_Version;              // bumped on every change (inputs mode sends only on change)
int g_SentVersion[2049];

KeyValues g_Config;
char g_PendingPreset[64];
char g_LastPreset[64];      // last preset applied, shown by !fog
bool g_PresetEdited;        // changed by hand since then
float g_PendingAt;

// ---------------------------------------------------------------- plugin lifecycle

void Fog_PluginStart()
{
	RegConsoleCmd("sm_fog", Cmd_Fog, "Admin fog control - sm_fog help");

	g_cvFade = CreateConVar("sm_dynamicfog_fade", "1.0", "Default seconds a fog change blends in", _, true, 0.0, true, 120.0);
	g_cvSky = CreateConVar("sm_dynamicfog_skybox", "1", "Also override the 3D skybox fog", _, true, 0.0, true, 1.0);
	g_cvAnnounce = CreateConVar("sm_dynamicfog_announce", "1", "Tell everyone in chat when an admin changes the fog", _, true, 0.0, true, 1.0);
	g_cvInterval = CreateConVar("sm_dynamicfog_interval", "0.3", "Seconds between re-applying the override (applies next map)", _, true, 0.1, true, 5.0);
	CreateConVar("sm_dynamicfog_version", PLUGIN_VERSION, "Dynamic Fog version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "dynamicfog");

	g_OrigRefs = new ArrayList();
	g_OrigVals = new ArrayList(sizeof(FogVals));

	HookEvent("player_spawn", Event_PlayerSpawn);

	// Late load (plugin reloaded mid-map): OnMapStart won't run, so set up here.
	ResetState();
	LoadConfig();
	StartTimer();
}

// Called from eventmodes.sp's OnPluginEnd.
void Fog_PluginEnd()
{
	if (g_Active)
		Restore();
}

void Fog_MapStart()
{
	ResetState();
	RemoveLeftoverCtrl();
	LoadConfig();
	StartTimer();

	// Automatic preset for this map (configs/eventmodes/dynamicfog.cfg "MapPresets"), applied once entities are up.
	if (g_Config != null)
	{
		char map[PLATFORM_MAX_PATH];
		GetCurrentMap(map, sizeof(map));
		g_Config.Rewind();
		if (g_Config.JumpToKey("MapPresets"))
		{
			g_Config.GetString(map, g_PendingPreset, sizeof(g_PendingPreset), "");
			g_PendingAt = GetGameTime() + 0.5;
		}
		g_Config.Rewind();
	}
}

// The fog never carries over to the next map: switch it off and forget everything now, so nothing
// (a running fade in OnGameFrame, a spawn timer) can touch the next map before OnMapStart.
void Fog_MapEnd()
{
	if (g_Active)
		Restore();
	ResetState();
	g_Timer = null;   // TIMER_FLAG_NO_MAPCHANGE already killed it
}

// Safety net at map start: our controller should be gone with the old map's entities. If one is still
// there, point anyone on it back to nothing, switch it off and remove it.
void RemoveLeftoverCtrl()
{
	char name[64];
	int e = -1;
	while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
	{
		GetEntPropString(e, Prop_Data, "m_iName", name, sizeof(name));
		if (!StrEqual(name, OUR_NAME))
			continue;
		if (g_HasPlayerCtrl)
		{
			for (int i = 1; i <= MaxClients; i++)
				if (IsClientInGame(i) && GetEntPropEnt(i, Prop_Send, PLAYER_CTRL_PROP) == e)
					SetEntPropEnt(i, Prop_Send, PLAYER_CTRL_PROP, -1);
		}
		AcceptEntityInput(e, "TurnOff");
		AcceptEntityInput(e, "Kill");
		LogMessage("Removed a leftover %s at map start", OUR_NAME);
	}
}

void ResetState()
{
	g_Active = false;
	g_Lerping = false;
	g_Fade = -1.0;
	g_SkyOverride = -1;
	g_OrigRefs.Clear();
	g_OrigVals.Clear();
	g_HaveOrigSky = false;
	g_OurRef = INVALID_ENT_REFERENCE;
	g_PendingPreset[0] = '\0';
	g_LastPreset[0] = '\0';
	g_Version++;
}

void StartTimer()
{
	delete g_Timer;
	g_Timer = CreateTimer(g_cvInterval.FloatValue, Timer_Enforce, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void LoadConfig()
{
	delete g_Config;
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/eventmodes/dynamicfog.cfg");
	g_Config = new KeyValues("DynamicFog");
	if (!g_Config.ImportFromFile(path))
	{
		LogError("Couldn't read %s - no presets available", path);
		delete g_Config;
	}
}

float FadeDefault()
{
	return g_Fade >= 0.0 ? g_Fade : g_cvFade.FloatValue;
}

bool SkyOn()
{
	return g_SkyOverride >= 0 ? g_SkyOverride == 1 : g_cvSky.BoolValue;
}

// ---------------------------------------------------------------- timers / frames

public Action Timer_Enforce(Handle timer)
{
	if (g_PendingPreset[0] != '\0' && GetGameTime() >= g_PendingAt)
	{
		char name[64];
		strcopy(name, sizeof(name), g_PendingPreset);
		g_PendingPreset[0] = '\0';
		if (!ApplyPreset(0, name, 0.0, true))
			LogError("MapPresets: no preset \"%s\"", name);
	}
	if (g_Active && !g_Lerping)
		ApplyAll();
	return Plugin_Continue;
}

public void OnGameFrame()
{
	if (!g_Lerping || !g_Active)
		return;
	float now = GetEngineTime();
	if (now < g_NextLerpApply)
		return;
	g_NextLerpApply = now + 0.03;
	StepLerp(now);
	ApplyAll();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	// The engine points a spawning player at the map's master controller (or none): fix them up quickly.
	if (g_Active)
		CreateTimer(0.1, Timer_Spawned, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Spawned(Handle timer)
{
	if (g_Active)
		ApplyAll();
	return Plugin_Stop;
}

// ---------------------------------------------------------------- values

int PackColor(const float c[3])
{
	int r = RoundToNearest(c[0]) & 255, g = RoundToNearest(c[1]) & 255, b = RoundToNearest(c[2]) & 255;
	return r | (g << 8) | (b << 16) | (255 << 24);
}

void UnpackColor(int i, float c[3])
{
	c[0] = float(i & 255);
	c[1] = float((i >> 8) & 255);
	c[2] = float((i >> 16) & 255);
}

bool PropName(bool sky, int f, char[] name, int len)
{
	if (sky)
	{
		if (!g_HasSky[f])
			return false;
		strcopy(name, len, g_SkyProp[f]);
	}
	else
	{
		if (!g_HasCtrl[f])
			return false;
		strcopy(name, len, g_CtrlProp[f]);
	}
	return true;
}

void ReadFog(int ent, bool sky, FogVals v)
{
	v.Defaults();
	char n[64];
	if (PropName(sky, F_ENABLE, n, sizeof(n))) v.enable = GetEntProp(ent, Prop_Send, n) != 0;
	if (PropName(sky, F_BLEND, n, sizeof(n))) v.blend = GetEntProp(ent, Prop_Send, n) != 0;
	if (PropName(sky, F_FARZ, n, sizeof(n))) v.farz = GetEntPropFloat(ent, Prop_Send, n);
	if (PropName(sky, F_START, n, sizeof(n))) v.startDist = GetEntPropFloat(ent, Prop_Send, n);
	if (PropName(sky, F_END, n, sizeof(n))) v.endDist = GetEntPropFloat(ent, Prop_Send, n);
	if (PropName(sky, F_DENSITY, n, sizeof(n))) v.density = GetEntPropFloat(ent, Prop_Send, n);
	float c[3];
	if (PropName(sky, F_C1, n, sizeof(n)))
	{
		UnpackColor(GetEntProp(ent, Prop_Send, n), c);
		v.c1 = c;
	}
	if (PropName(sky, F_C2, n, sizeof(n)))
	{
		UnpackColor(GetEntProp(ent, Prop_Send, n), c);
		v.c2 = c;
	}
}

// Only writes what differs, so unchanged entities aren't flagged for networking.
void SetIntIfChanged(int ent, const char[] prop, int value)
{
	if (GetEntProp(ent, Prop_Send, prop) != value)
		SetEntProp(ent, Prop_Send, prop, value);
}

void SetFloatIfChanged(int ent, const char[] prop, float value)
{
	if (GetEntPropFloat(ent, Prop_Send, prop) != value)
		SetEntPropFloat(ent, Prop_Send, prop, value);
}

void WriteFog(int ent, bool sky, FogVals v)
{
	char n[64];
	if (PropName(sky, F_ENABLE, n, sizeof(n))) SetIntIfChanged(ent, n, v.enable ? 1 : 0);
	if (PropName(sky, F_BLEND, n, sizeof(n))) SetIntIfChanged(ent, n, v.blend ? 1 : 0);
	if (PropName(sky, F_FARZ, n, sizeof(n))) SetFloatIfChanged(ent, n, v.farz);
	if (PropName(sky, F_START, n, sizeof(n))) SetFloatIfChanged(ent, n, v.startDist);
	if (PropName(sky, F_END, n, sizeof(n))) SetFloatIfChanged(ent, n, v.endDist);
	if (PropName(sky, F_DENSITY, n, sizeof(n))) SetFloatIfChanged(ent, n, v.density);
	float c[3];
	if (PropName(sky, F_C1, n, sizeof(n)))
	{
		c = v.c1;
		SetIntIfChanged(ent, n, PackColor(c));
	}
	if (PropName(sky, F_C2, n, sizeof(n)))
	{
		c = v.c2;
		SetIntIfChanged(ent, n, PackColor(c));
	}
}

// ---------------------------------------------------------------- entities

void Detect(int ctrl)
{
	if (g_Mode != MODE_UNKNOWN)
		return;
	int found = 0;
	for (int f = 0; f < F_COUNT; f++)
	{
		g_HasCtrl[f] = HasEntProp(ctrl, Prop_Send, g_CtrlProp[f]);
		if (g_HasCtrl[f])
			found++;
	}
	g_Mode = (g_HasCtrl[F_START] && g_HasCtrl[F_END] && g_HasCtrl[F_C1]) ? MODE_PROPS : MODE_INPUTS;
	LogMessage("Fog controller props found: %d/%d, mode: %s", found, F_COUNT, g_Mode == MODE_PROPS ? "props" : "inputs (fallback)");
}

// Player props are probed on the first player we touch.
void DetectPlayer(int client)
{
	if (g_PlayerProbed)
		return;
	g_PlayerProbed = true;
	int found = 0;
	for (int f = 0; f < F_COUNT; f++)
	{
		g_HasSky[f] = g_SkyProp[f][0] != '\0' && HasEntProp(client, Prop_Send, g_SkyProp[f]);
		if (g_HasSky[f])
			found++;
	}
	g_HasPlayerCtrl = HasEntProp(client, Prop_Send, PLAYER_CTRL_PROP);
	LogMessage("Skybox fog props found: %d, player fog controller prop: %s", found, g_HasPlayerCtrl ? "yes" : "no");
}

int OurCtrl(bool create)
{
	int ent = EntRefToEntIndex(g_OurRef);
	if (ent == INVALID_ENT_REFERENCE)
	{
		// Fog controllers survive round restarts in CS:S: find ours before making another one.
		ent = -1;
		char name[64];
		int e = -1;
		while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
		{
			GetEntPropString(e, Prop_Data, "m_iName", name, sizeof(name));
			if (StrEqual(name, OUR_NAME))
			{
				ent = e;
				break;
			}
		}
		if (ent == -1 && create)
		{
			ent = CreateEntityByName("env_fog_controller");
			if (ent != -1)
			{
				// No Master flag: the engine picks the master at map load and we never want to steal the map's.
				DispatchKeyValue(ent, "targetname", OUR_NAME);
				DispatchKeyValue(ent, "spawnflags", "0");
				DispatchKeyValue(ent, "fogenable", "0");
				DispatchKeyValue(ent, "fogblend", "0");
				DispatchKeyValue(ent, "fogstart", "0");
				DispatchKeyValue(ent, "fogend", "2000");
				DispatchKeyValue(ent, "fogcolor", "125 125 125");
				DispatchKeyValue(ent, "fogcolor2", "125 125 125");
				DispatchKeyValue(ent, "farz", "-1");
				DispatchKeyValue(ent, "fogmaxdensity", "1");
				DispatchSpawn(ent);
			}
		}
		g_OurRef = ent == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(ent);
	}
	if (ent != -1)
		Detect(ent);
	return ent;
}

void ReadCtrl(int ent, FogVals v)
{
	if (g_Mode == MODE_PROPS)
		ReadFog(ent, false, v);
	else
		v.Defaults();   // inputs mode can't read values back
}

void WriteCtrl(int ent, FogVals v)
{
	if (g_Mode == MODE_PROPS)
	{
		WriteFog(ent, false, v);
		return;
	}
	// Fallback: inputs, only when something changed. Variant floats/colours add nothing to the string pool.
	if (g_SentVersion[ent] == g_Version)
		return;
	g_SentVersion[ent] = g_Version;
	AcceptEntityInput(ent, v.enable ? "TurnOn" : "TurnOff");
	SetVariantFloat(v.startDist);
	AcceptEntityInput(ent, "SetStartDist");
	SetVariantFloat(v.endDist);
	AcceptEntityInput(ent, "SetEndDist");
	SetVariantInt(RoundToNearest(v.farz));
	AcceptEntityInput(ent, "SetFarZ");
	int col[4];
	col[3] = 255;
	for (int i = 0; i < 3; i++)
		col[i] = RoundToNearest(v.c1[i]);
	SetVariantColor(col);
	AcceptEntityInput(ent, "SetColor");
	for (int i = 0; i < 3; i++)
		col[i] = RoundToNearest(v.c2[i]);
	SetVariantColor(col);
	AcceptEntityInput(ent, "SetColorSecondary");
}

void Remember(int ent)
{
	int ref = EntIndexToEntRef(ent);
	if (g_OrigRefs.FindValue(ref) != -1)
		return;
	FogVals v;
	ReadCtrl(ent, v);
	g_OrigRefs.Push(ref);
	g_OrigVals.PushArray(v, sizeof(v));
}

// A player with no fog controller (map without fog) gets ours. Players on a map controller stay there:
// every map controller carries the override too.
void FixPlayer(int client, int ours, int mapCount)
{
	DetectPlayer(client);
	if (g_HasPlayerCtrl)
	{
		int c = GetEntPropEnt(client, Prop_Send, PLAYER_CTRL_PROP);
		if (c == -1 || !IsValidEntity(c))
			SetEntPropEnt(client, Prop_Send, PLAYER_CTRL_PROP, ours);
	}
	else if (mapCount == 0)
	{
		SetVariantString(OUR_NAME);
		AcceptEntityInput(client, "SetFogController");
	}
}

// ---------------------------------------------------------------- override

void TakeOver(int admin)
{
	if (g_Active)
		return;
	int ours = OurCtrl(true);
	g_OrigRefs.Clear();
	g_OrigVals.Clear();
	g_HaveOrigSky = false;

	int first = -1, e = -1;
	while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
	{
		if (e == ours)
			continue;
		Remember(e);
		if (first == -1)
			first = e;
	}

	// Start from what the admin sees now, so the first change blends from the map's own look.
	bool got = false;
	if (admin > 0 && IsClientInGame(admin))
	{
		DetectPlayer(admin);
		if (g_HasPlayerCtrl)
		{
			int c = GetEntPropEnt(admin, Prop_Send, PLAYER_CTRL_PROP);
			if (c != -1 && c != ours && IsValidEntity(c))
			{
				ReadCtrl(c, g_Cur);
				got = true;
			}
		}
	}
	if (!got && first != -1)
	{
		ReadCtrl(first, g_Cur);
		got = true;
	}
	if (!got)
	{
		g_Cur.Defaults();
		g_Cur.enable = false;
	}
	g_Lerping = false;
	g_Active = true;
	g_Version++;
	if (g_Mode == MODE_INPUTS)
		LogError("Fallback inputs mode: \"sm_fog reset\" can't restore the map's exact fog values");
}

void Restore()
{
	int ours = OurCtrl(false);
	g_Active = false;
	g_Lerping = false;
	g_Version++;

	FogVals v;
	if (g_Mode == MODE_PROPS)
	{
		for (int i = 0; i < g_OrigRefs.Length; i++)
		{
			int ent = EntRefToEntIndex(g_OrigRefs.Get(i));
			if (ent == INVALID_ENT_REFERENCE)
				continue;
			g_OrigVals.GetArray(i, v, sizeof(v));
			WriteCtrl(ent, v);
		}
	}
	if (ours != -1)
	{
		v = g_Cur;
		v.enable = false;
		WriteCtrl(ours, v);
	}
	if (g_HaveOrigSky)
	{
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i))
				WriteFog(i, true, g_OrigSky);
	}
	g_OrigRefs.Clear();
	g_OrigVals.Clear();
	g_HaveOrigSky = false;
	g_LastPreset[0] = '\0';
}

void ApplyAll()
{
	int ours = OurCtrl(true);
	if (ours == -1)
		return;

	int count = 0, e = -1;
	while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
	{
		if (e == ours)
			continue;
		Remember(e);   // a controller the map spawned after the takeover: remember it before overwriting
		WriteCtrl(e, g_Cur);
		count++;
	}
	WriteCtrl(ours, g_Cur);

	bool sky = SkyOn();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		FixPlayer(i, ours, count);
		if (sky)
		{
			if (!g_HaveOrigSky)
			{
				ReadFog(i, true, g_OrigSky);   // all players share the sky_camera's values
				g_HaveOrigSky = true;
			}
			WriteFog(i, true, g_Cur);
		}
	}
}

// Move to `to` over `fade` seconds. Flags and farz switch at once; distances, density and colours blend.
void SetTarget(FogVals to, float fade)
{
	if (fade <= 0.0)
	{
		g_Cur = to;
		g_Lerping = false;
	}
	else
	{
		g_From = g_Cur;
		g_To = to;
		g_T0 = GetEngineTime();
		g_T1 = g_T0 + fade;
		g_NextLerpApply = 0.0;
		g_Lerping = true;
		g_Cur.enable = to.enable;
		g_Cur.blend = to.blend;
		g_Cur.farz = to.farz;
	}
	g_Version++;
	ApplyAll();
}

float Mix(float a, float b, float f)
{
	return a + (b - a) * f;
}

void StepLerp(float now)
{
	float f = (now - g_T0) / (g_T1 - g_T0);
	g_Version++;
	if (f >= 1.0)
	{
		g_Cur = g_To;
		g_Lerping = false;
		return;
	}
	f = f * f * (3.0 - 2.0 * f);   // ease in/out
	g_Cur.startDist = Mix(g_From.startDist, g_To.startDist, f);
	g_Cur.endDist = Mix(g_From.endDist, g_To.endDist, f);
	g_Cur.density = Mix(g_From.density, g_To.density, f);
	for (int i = 0; i < 3; i++)
	{
		g_Cur.c1[i] = Mix(g_From.c1[i], g_To.c1[i], f);
		g_Cur.c2[i] = Mix(g_From.c2[i], g_To.c2[i], f);
	}
}

// The value a new change builds on: where a running fade is heading, else what's shown.
void CurrentTarget(FogVals out)
{
	if (g_Lerping)
		out = g_To;
	else
		out = g_Cur;
}

// ---------------------------------------------------------------- presets

bool KvFloat(const char[] key, float &out)
{
	char s[32];
	g_Config.GetString(key, s, sizeof(s), "");
	if (s[0] == '\0')
		return false;
	out = StringToFloat(s);
	return true;
}

bool KvColor(const char[] key, float c[3])
{
	char s[32], parts[3][8];
	g_Config.GetString(key, s, sizeof(s), "");
	if (ExplodeString(s, " ", parts, sizeof(parts), sizeof(parts[])) != 3)
		return false;
	for (int i = 0; i < 3; i++)
		c[i] = float(StringToInt(parts[i]));
	return true;
}

bool ApplyPreset(int client, const char[] name, float fade, bool quiet)
{
	if (g_Config == null)
		return false;
	g_Config.Rewind();
	if (!g_Config.JumpToKey("Presets") || !g_Config.JumpToKey(name))
	{
		g_Config.Rewind();
		return false;
	}

	TakeOver(client);
	FogVals to;
	CurrentTarget(to);
	to.enable = g_Config.GetNum("enable", 1) != 0;
	float f;
	if (KvFloat("start", f)) to.startDist = f;
	if (KvFloat("end", f)) to.endDist = f;
	if (KvFloat("density", f)) to.density = f;
	if (KvFloat("farz", f)) to.farz = f <= 0.0 ? -1.0 : f;
	if (KvFloat("blend", f)) to.blend = f >= 0.5;
	float c[3];
	if (KvColor("color", c))
	{
		to.c1 = c;
		to.c2 = c;
	}
	if (KvColor("color2", c))
		to.c2 = c;
	g_Config.Rewind();
	strcopy(g_LastPreset, sizeof(g_LastPreset), name);
	g_PresetEdited = false;

	SetTarget(to, fade);
	if (quiet)
		LogMessage("Map preset \"%s\" applied", name);
	else
		Announce(client, "set the fog preset '%s'", name);
	return true;
}

// ---------------------------------------------------------------- chat

void Reply(int client, const char[] fmt, any ...)
{
	char buf[256];
	VFormat(buf, sizeof(buf), fmt, 3);
	if (client == 0 || GetCmdReplySource() == SM_REPLY_TO_CONSOLE)
		ReplyToCommand(client, "[Fog] %s", buf);
	else
		ReplyToCommand(client, FOG_TAG ... "%s", buf);
}

void Announce(int client, const char[] fmt, any ...)
{
	char buf[192];
	VFormat(buf, sizeof(buf), fmt, 3);
	if (g_cvAnnounce.BoolValue)
		PrintToChatAll(FOG_TAG ... "%N %s", client, buf);
	else
		Reply(client, "%s", buf);
	LogAction(client, -1, "\"%L\" %s", client, buf);
}

// Player-typed number in [lo, hi]; the whole argument must be a number ("1,5" or "8x" are rejected).
bool ArgFloat(int i, float lo, float hi, float &out)
{
	if (GetCmdArgs() < i)
		return false;
	char s[32];
	GetCmdArg(i, s, sizeof(s));
	if (s[0] == '\0')
		return false;
	float v;
	if (StringToFloatEx(s, v) != strlen(s))
		return false;
	if (v < lo || v > hi)
		return false;
	out = v;
	return true;
}

// Optional trailing fade time; false = given but invalid.
bool ArgFade(int i, float &out)
{
	if (GetCmdArgs() < i)
	{
		out = FadeDefault();
		return true;
	}
	return ArgFloat(i, 0.0, 120.0, out);
}

char g_ColorNames[][] =
{
	"white", "grey", "gray", "black", "red", "darkred", "green", "darkgreen", "blue", "darkblue",
	"yellow", "orange", "purple", "pink", "cyan", "brown", "gold"
};

int g_ColorValues[][3] =
{
	{255, 255, 255}, {128, 128, 128}, {128, 128, 128}, {0, 0, 0}, {200, 30, 30}, {90, 10, 10},
	{40, 170, 60}, {20, 70, 30}, {40, 70, 200}, {10, 20, 70}, {230, 210, 60}, {230, 120, 20},
	{110, 30, 160}, {255, 130, 190}, {40, 200, 220}, {110, 70, 35}, {210, 170, 60}
};

// A colour from the arguments starting at i: "r g b", one number (grey), a name, or hex (#ff8800).
// Returns how many arguments it used, 0 if it isn't a colour.
int ArgColor(int i, float c[3])
{
	float v[3];
	if (ArgFloat(i, 0.0, 255.0, v[0]) && ArgFloat(i + 1, 0.0, 255.0, v[1]) && ArgFloat(i + 2, 0.0, 255.0, v[2]))
	{
		for (int k = 0; k < 3; k++)
			c[k] = float(RoundToNearest(v[k]));
		return 3;
	}
	if (GetCmdArgs() < i)
		return 0;
	if (ArgFloat(i, 0.0, 255.0, v[0]))
	{
		c[0] = float(RoundToNearest(v[0]));
		c[1] = c[0];
		c[2] = c[0];
		return 1;
	}

	char s[32];
	GetCmdArg(i, s, sizeof(s));
	StringToLower(s);
	int start = s[0] == '#' ? 1 : 0, hex;
	if (strlen(s[start]) == 6 && StringToIntEx(s[start], hex, 16) == 6)
	{
		c[0] = float((hex >> 16) & 255);
		c[1] = float((hex >> 8) & 255);
		c[2] = float(hex & 255);
		return 1;
	}
	for (int n = 0; n < sizeof(g_ColorNames); n++)
	{
		if (StrEqual(s, g_ColorNames[n]))
		{
			for (int k = 0; k < 3; k++)
				c[k] = float(g_ColorValues[n][k]);
			return 1;
		}
	}
	return 0;
}

void ColorUsage(int client, const char[] cmd)
{
	Reply(client, "Usage: !fog %s <r g b | 0-255 for grey | name | #hex> [seconds]", cmd);
	Reply(client, "e.g. !fog %s 255 120 0   !fog %s 200   !fog %s red 5   !fog %s #ff8800", cmd, cmd, cmd, cmd);
	Reply(client, "Names: white, grey, black, red, darkred, green, darkgreen, blue, darkblue, yellow, orange, purple, pink, cyan, brown, gold");
}

void ColorStr(const float c[3], char[] out, int len)
{
	Format(out, len, "%d %d %d", RoundToNearest(c[0]), RoundToNearest(c[1]), RoundToNearest(c[2]));
}

int CountMapCtrls()
{
	int ours = EntRefToEntIndex(g_OurRef), n = 0, e = -1;
	while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
		if (e != ours)
			n++;
	return n;
}

void Help(int client)
{
	Reply(client, "!fog status | on | off | reset");
	Reply(client, "!fog start <n> | end <n> | range <start> <end>");
	Reply(client, "!fog color <r g b | grey 0-255 | name | #hex> | color2 <same>  (color2 shows only with blend 1)");
	Reply(client, "!fog density <0-1> | farz <n, -1 = off> | blend <0|1>");
	Reply(client, "!fog preset <name> | presets | fade <sec> | sky <on|off>");
	Reply(client, "Add seconds at the end of a change to blend it in, e.g. !fog end 800 5");
}

// One line saying whether the fog is on, shown when someone types just !fog.
void StateLine(int client)
{
	if (!g_Active)
	{
		Reply(client, "Fog override: OFF (map's own fog, %d controller(s))", CountMapCtrls());
		return;
	}
	FogVals v;
	CurrentTarget(v);
	if (!v.enable)
	{
		Reply(client, "Fog override: ON - fog turned OFF");
		return;
	}
	char preset[80];
	if (g_LastPreset[0] != '\0')
		Format(preset, sizeof(preset), " | preset %s%s", g_LastPreset, g_PresetEdited ? " (edited)" : "");
	float c[3];
	char cs[16];
	c = v.c1;
	ColorStr(c, cs, sizeof(cs));
	Reply(client, "Fog override: ON - fog ON | %d to %d | colour %s%s",
		RoundToNearest(v.startDist), RoundToNearest(v.endDist), cs, preset);
}

void Status(int client)
{
	int n = CountMapCtrls();
	if (!g_Active)
	{
		Reply(client, "Map default fog (no override). Map fog controllers: %d", n);
		return;
	}
	FogVals v;
	CurrentTarget(v);
	char c1[16], c2[16];
	float c[3];
	c = v.c1;
	ColorStr(c, c1, sizeof(c1));
	c = v.c2;
	ColorStr(c, c2, sizeof(c2));
	Reply(client, "Override %s | start %d end %d | color %s / %s", v.enable ? "ON" : "OFF",
		RoundToNearest(v.startDist), RoundToNearest(v.endDist), c1, c2);
	Reply(client, "density %.2f | farz %d | blend %d | fade %.1fs | skybox %s | map controllers %d",
		v.density, RoundToNearest(v.farz), v.blend ? 1 : 0, FadeDefault(), SkyOn() ? "on" : "off", n);
}

public Action Cmd_Fog(int client, int args)
{
	if (!HasAccess(client))
	{
		Reply(client, "You don't have access to the fog commands.");
		return Plugin_Handled;
	}

	char sub[32];
	if (args < 1)
		strcopy(sub, sizeof(sub), "help");
	else
		GetCmdArg(1, sub, sizeof(sub));
	StringToLower(sub);

	// ---- commands that don't change the fog
	if (StrEqual(sub, "help"))
	{
		StateLine(client);
		Help(client);
		return Plugin_Handled;
	}
	if (StrEqual(sub, "status"))
	{
		Status(client);
		return Plugin_Handled;
	}
	if (StrEqual(sub, "presets"))
	{
		// Many presets: one chat line per ~150 characters so nothing gets cut off.
		char names[192], name[32];
		int count = 0;
		if (g_Config != null)
		{
			g_Config.Rewind();
			if (g_Config.JumpToKey("Presets") && g_Config.GotoFirstSubKey())
			{
				do
				{
					g_Config.GetSectionName(name, sizeof(name));
					if (strlen(names) + strlen(name) > 150)
					{
						Reply(client, "%s", names);
						names[0] = '\0';
					}
					Format(names, sizeof(names), "%s%s%s", names, names[0] == '\0' ? "" : ", ", name);
					count++;
				}
				while (g_Config.GotoNextKey());
			}
			g_Config.Rewind();
		}
		if (count == 0)
			Reply(client, "Presets: (none - check configs/eventmodes/dynamicfog.cfg)");
		else
			Reply(client, "%s  (%d presets)", names, count);
		return Plugin_Handled;
	}
	if (StrEqual(sub, "fade"))
	{
		float t;
		if (!ArgFloat(2, 0.0, 120.0, t))
			Reply(client, "Usage: !fog fade <seconds 0-120>");
		else
		{
			g_Fade = t;
			Reply(client, "Changes now blend over %.1fs (until map change)", t);
		}
		return Plugin_Handled;
	}
	if (StrEqual(sub, "reset"))
	{
		if (!g_Active)
			Reply(client, "The fog is already the map's own.");
		else
		{
			Restore();
			Announce(client, "reset the fog to the map default");
		}
		return Plugin_Handled;
	}
	if (StrEqual(sub, "sky"))
	{
		char on[8];
		GetCmdArg(2, on, sizeof(on));
		StringToLower(on);
		if (!StrEqual(on, "on") && !StrEqual(on, "off"))
		{
			Reply(client, "Usage: !fog sky <on|off>");
			return Plugin_Handled;
		}
		g_SkyOverride = StrEqual(on, "on") ? 1 : 0;
		if (g_SkyOverride == 0 && g_HaveOrigSky)
		{
			for (int i = 1; i <= MaxClients; i++)
				if (IsClientInGame(i) && !IsFakeClient(i))
					WriteFog(i, true, g_OrigSky);
		}
		Reply(client, "Skybox fog override %s (until map change)", on);
		return Plugin_Handled;
	}
	if (StrEqual(sub, "preset"))
	{
		char name[64];
		float fade;
		if (args < 2)
			Reply(client, "Usage: !fog preset <name> [seconds]  (!fog presets lists them)");
		else if (!ArgFade(3, fade))
			Reply(client, "Bad fade time (0-120 seconds).");
		else
		{
			GetCmdArg(2, name, sizeof(name));
			StringToLower(name);
			if (!ApplyPreset(client, name, fade, false))
				Reply(client, "No preset '%s'. !fog presets lists them.", name);
		}
		return Plugin_Handled;
	}

	// ---- commands that change the fog: check the arguments, take over, then build the new target
	FogVals to;
	float fade = FadeDefault(), v, v2;
	float c[3];
	char msg[96], cs[16];
	bool ok = true;

	if (!g_Active)
	{
		// TakeOver needs to happen before CurrentTarget reads g_Cur, but not for typos.
		if (!StrEqual(sub, "on") && !StrEqual(sub, "off") && !StrEqual(sub, "start") && !StrEqual(sub, "end")
			&& !StrEqual(sub, "range") && !StrEqual(sub, "dist") && !StrEqual(sub, "color") && !StrEqual(sub, "colour")
			&& !StrEqual(sub, "color2") && !StrEqual(sub, "colour2") && !StrEqual(sub, "density")
			&& !StrEqual(sub, "farz") && !StrEqual(sub, "blend"))
		{
			Reply(client, "Unknown command '%s'. Type !fog for help.", sub);
			return Plugin_Handled;
		}
		TakeOver(client);
	}
	CurrentTarget(to);

	if (StrEqual(sub, "on"))
	{
		to.enable = true;
		fade = 0.0;
		strcopy(msg, sizeof(msg), "turned the fog on");
	}
	else if (StrEqual(sub, "off"))
	{
		to.enable = false;
		fade = 0.0;
		strcopy(msg, sizeof(msg), "turned the fog off");
	}
	else if (StrEqual(sub, "start"))
	{
		if ((ok = ArgFloat(2, -50000.0, 50000.0, v) && ArgFade(3, fade)))
		{
			to.startDist = v;
			to.enable = true;
			Format(msg, sizeof(msg), "set the fog start to %d", RoundToNearest(v));
		}
		else
			Reply(client, "Usage: !fog start <distance> [seconds]");
	}
	else if (StrEqual(sub, "end"))
	{
		if ((ok = ArgFloat(2, -50000.0, 100000.0, v) && ArgFade(3, fade)))
		{
			to.endDist = v;
			to.enable = true;
			Format(msg, sizeof(msg), "set the fog end to %d", RoundToNearest(v));
		}
		else
			Reply(client, "Usage: !fog end <distance> [seconds]");
	}
	else if (StrEqual(sub, "range") || StrEqual(sub, "dist"))
	{
		if ((ok = ArgFloat(2, -50000.0, 50000.0, v) && ArgFloat(3, -50000.0, 100000.0, v2) && ArgFade(4, fade)))
		{
			to.startDist = v;
			to.endDist = v2;
			to.enable = true;
			Format(msg, sizeof(msg), "set the fog to %d - %d", RoundToNearest(v), RoundToNearest(v2));
		}
		else
			Reply(client, "Usage: !fog range <start> <end> [seconds]");
	}
	else if (StrEqual(sub, "color") || StrEqual(sub, "colour"))
	{
		int used = ArgColor(2, c);
		if ((ok = used > 0 && ArgFade(2 + used, fade)))
		{
			to.c1 = c;
			to.c2 = c;
			to.enable = true;
			ColorStr(c, cs, sizeof(cs));
			Format(msg, sizeof(msg), "set the fog colour to %s", cs);
		}
		else
			ColorUsage(client, "color");
	}
	else if (StrEqual(sub, "color2") || StrEqual(sub, "colour2"))
	{
		int used = ArgColor(2, c);
		if ((ok = used > 0 && ArgFade(2 + used, fade)))
		{
			to.c2 = c;
			to.enable = true;
			ColorStr(c, cs, sizeof(cs));
			Format(msg, sizeof(msg), "set the secondary fog colour to %s", cs);
		}
		else
			ColorUsage(client, "color2");
	}
	else if (StrEqual(sub, "density"))
	{
		if ((ok = ArgFloat(2, 0.0, 1.0, v) && ArgFade(3, fade)))
		{
			to.density = v;
			to.enable = true;
			Format(msg, sizeof(msg), "set the fog density to %.2f", v);
		}
		else
			Reply(client, "Usage: !fog density <0-1> [seconds]");
	}
	else if (StrEqual(sub, "farz"))
	{
		if ((ok = ArgFloat(2, -1.0, 100000.0, v)))
		{
			to.farz = v <= 0.0 ? -1.0 : v;
			fade = 0.0;
			if (to.farz < 0.0)
				strcopy(msg, sizeof(msg), "turned the far clip off");
			else
				Format(msg, sizeof(msg), "set the far clip to %d", RoundToNearest(v));
		}
		else
			Reply(client, "Usage: !fog farz <distance, -1 = off>");
	}
	else if (StrEqual(sub, "blend"))
	{
		if ((ok = ArgFloat(2, 0.0, 1.0, v)))
		{
			to.blend = v >= 0.5;
			fade = 0.0;
			Format(msg, sizeof(msg), "set fog blend %d", to.blend ? 1 : 0);
		}
		else
			Reply(client, "Usage: !fog blend <0|1>");
	}
	else
	{
		Reply(client, "Unknown command '%s'. Type !fog for help.", sub);
		return Plugin_Handled;
	}

	if (!ok)
		return Plugin_Handled;
	if (to.enable && to.startDist >= to.endDist)
	{
		Reply(client, "The start (%d) must be below the end (%d).", RoundToNearest(to.startDist), RoundToNearest(to.endDist));
		return Plugin_Handled;
	}
	g_PresetEdited = true;
	SetTarget(to, fade);
	Announce(client, "%s", msg);
	return Plugin_Handled;
}

// ---------------------------------------------------------------- menu page

float g_FadeSteps[] = { 0.0, 1.0, 2.0, 5.0, 10.0, 20.0 };

bool FogIsOn()
{
	if (!g_Active)
		return false;
	FogVals v;
	CurrentTarget(v);
	return v.enable;
}

void RestoreSkies()
{
	if (!g_HaveOrigSky)
		return;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			WriteFog(i, true, g_OrigSky);
}

void FogMenu(int client)
{
	Menu menu = new Menu(FogMenuHandler);
	char title[192], line[64];
	if (!g_Active)
		strcopy(title, sizeof(title), "Fog - the map's own fog");
	else
	{
		FogVals v;
		CurrentTarget(v);
		if (!v.enable)
			strcopy(title, sizeof(title), "Fog - turned OFF");
		else
			Format(title, sizeof(title), "Fog - ON, %d to %d", RoundToNearest(v.startDist), RoundToNearest(v.endDist));
		if (g_LastPreset[0] != '\0')
			Format(title, sizeof(title), "%s\nPreset: %s%s", title, g_LastPreset, g_PresetEdited ? " (edited)" : "");
	}
	Format(title, sizeof(title), "%s\nFine-tune with !fog in chat\n ", title);
	menu.SetTitle(title);

	bool on = FogIsOn();
	menu.AddItem("toggle", on ? "Turn fog OFF" : "Turn fog ON");
	menu.AddItem("presets", "Presets...");
	menu.AddItem("thicker", "Thicker (fog closer)", on ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("thinner", "Thinner (fog further)", on ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Fade time: %.0fs", FadeDefault());
	menu.AddItem("fade", line);
	Format(line, sizeof(line), "Skybox fog: %s", SkyOn() ? "ON" : "OFF");
	menu.AddItem("sky", line);
	menu.AddItem("reset", "Back to the map's own fog", g_Active ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

// Scale the fog distances: k < 1 pulls the fog in, k > 1 pushes it out.
void FogScale(int client, float k)
{
	TakeOver(client);
	FogVals to;
	CurrentTarget(to);
	to.endDist *= k;
	if (to.startDist > 0.0)
		to.startDist *= k;
	if (to.endDist < to.startDist + 50.0)
		to.endDist = to.startDist + 50.0;
	to.enable = true;
	g_PresetEdited = true;
	SetTarget(to, FadeDefault());
	Announce(client, "made the fog %s (%d to %d)", k < 1.0 ? "thicker" : "thinner",
		RoundToNearest(to.startDist), RoundToNearest(to.endDist));
}

public int FogMenuHandler(Menu menu, MenuAction action, int client, int item)
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
			TakeOver(client);
			FogVals to;
			CurrentTarget(to);
			to.enable = !to.enable;
			if (to.enable && to.startDist >= to.endDist)
				to.Defaults();
			g_PresetEdited = true;
			SetTarget(to, 0.0);
			Announce(client, to.enable ? "turned the fog on" : "turned the fog off");
		}
		else if (StrEqual(info, "presets"))
		{
			PresetMenu(client, 0);
			return 0;
		}
		else if (StrEqual(info, "thicker"))
			FogScale(client, 0.75);
		else if (StrEqual(info, "thinner"))
			FogScale(client, 1.33);
		else if (StrEqual(info, "fade"))
		{
			float cur = FadeDefault(), next = g_FadeSteps[0];
			for (int i = 0; i < sizeof(g_FadeSteps); i++)
			{
				if (g_FadeSteps[i] > cur + 0.05)
				{
					next = g_FadeSteps[i];
					break;
				}
			}
			g_Fade = next;
		}
		else if (StrEqual(info, "sky"))
		{
			g_SkyOverride = SkyOn() ? 0 : 1;
			if (g_SkyOverride == 0)
				RestoreSkies();
		}
		else if (StrEqual(info, "reset") && g_Active)
		{
			Restore();
			Announce(client, "reset the fog to the map default");
		}
		FogMenu(client);
	}
	return 0;
}

void PresetMenu(int client, int firstItem)
{
	Menu menu = new Menu(PresetMenuHandler);
	menu.SetTitle("Fog presets\n(blends in over the fade time)\n ");
	char name[32], line[48];
	if (g_Config != null)
	{
		g_Config.Rewind();
		if (g_Config.JumpToKey("Presets") && g_Config.GotoFirstSubKey())
		{
			do
			{
				g_Config.GetSectionName(name, sizeof(name));
				if (g_Active && StrEqual(name, g_LastPreset, false) && !g_PresetEdited)
					Format(line, sizeof(line), "%s  (current)", name);
				else
					strcopy(line, sizeof(line), name);
				menu.AddItem(name, line);
			}
			while (g_Config.GotoNextKey());
		}
		g_Config.Rewind();
	}
	if (menu.ItemCount == 0)
		menu.AddItem("", "No presets - check configs/eventmodes/dynamicfog.cfg", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int PresetMenuHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		FogMenu(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char name[32];
		menu.GetItem(item, name, sizeof(name));
		if (!ApplyPreset(client, name, FadeDefault(), false))
			PrintToChat(client, FOG_TAG ... "Preset '%s' is gone - was the config changed?", name);
		PresetMenu(client, GetMenuSelectionPosition());   // stay on the same page
	}
	return 0;
}

/*
    (). FunModes V2:

    @file           Fog.sp
    @Usage          Functions for the Fog mode.
                    Admin-controlled fog on any map: every env_fog_controller on the map (plus one of our own
                    for maps without fog) and the 3D skybox fog show the admins' values, re-applied so the map
                    logic can't undo them. Presets are in configs/FunModes/Fog.cfg (a "MapPresets" section can
                    give a map its own preset), changes blend in over time and turning the mode off gives the
                    map its own fog back. Fine-tuning with sm_fog (!fog) in chat.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Fog

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Fog"

static int g_iFogIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iFogIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define FOG_CONVAR_TOGGLE   0
#define FOG_CONVAR_FADE     1
#define FOG_CONVAR_SKYBOX   2
#define FOG_CONVAR_ANNOUNCE 3
#define FOG_CONVAR_INTERVAL 4
#define FOG_CONVAR_PRESET   5

#define FOG_OUR_NAME         "fogadmin_ctrl"
#define FOG_PLAYER_CTRL_PROP "m_PlayerFog.m_hCtrl"

bool g_bFog_Enabled;
float g_fFog_Fade;
bool g_bFog_Skybox;
bool g_bFog_Announce;
float g_fFog_Interval;
char g_sFog_Preset[sizeof(FM_ConVar::currentValue)];

enum
{
	FOG_F_ENABLE = 0,
	FOG_F_BLEND,
	FOG_F_FARZ,
	FOG_F_START,
	FOG_F_END,
	FOG_F_DENSITY,
	FOG_F_C1,
	FOG_F_C2,
	FOG_F_COUNT
}

char g_sFog_CtrlProp[FOG_F_COUNT][] =
{
	"m_fog.enable", "m_fog.blend", "m_fog.farz", "m_fog.start", "m_fog.end",
	"m_fog.maxdensity", "m_fog.colorPrimary", "m_fog.colorSecondary"
};

char g_sFog_SkyProp[FOG_F_COUNT][] =
{
	"m_skybox3d.fog.enable", "m_skybox3d.fog.blend", "", "m_skybox3d.fog.start", "m_skybox3d.fog.end",
	"m_skybox3d.fog.maxdensity", "m_skybox3d.fog.colorPrimary", "m_skybox3d.fog.colorSecondary"
};

enum
{
	FOG_MODE_UNKNOWN = 0,
	FOG_MODE_PROPS,    // netprops: exact values, smooth fades, exact reset
	FOG_MODE_INPUTS    // fallback: entity inputs, can't read values back (reset can't restore the map's own)
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

bool g_bFog_Active;              // admin override on?
bool g_bFog_Lerping;
float g_fFog_FadeOverride = -1.0;        // "sm_fog fade" for this map; -1 = use sm_dynamicfog_fade
int g_iFog_SkyOverride = -1;     // "sm_fog sky" for this map; -1 = use sm_dynamicfog_skybox
FogVals g_Fog_Cur;              // values shown right now
FogVals g_Fog_From;
FogVals g_Fog_To;
float g_fFog_T0;
float g_fFog_T1;
float g_fFog_NextLerpApply;

ArrayList g_aFog_OrigRefs;       // map controllers as they were before the takeover (entity refs) ...
ArrayList g_aFog_OrigVals;       // ... and their values, same order
FogVals g_Fog_OrigSky;          // skybox fog before the takeover
bool g_bFog_HaveOrigSky;

int g_iFog_OurRef = INVALID_ENT_REFERENCE;
Handle g_hFog_Timer;

int g_iFog_Mode = FOG_MODE_UNKNOWN;
bool g_bFog_HasCtrl[FOG_F_COUNT];
bool g_bFog_HasSky[FOG_F_COUNT];
bool g_bFog_HasPlayerCtrl;
bool g_bFog_PlayerProbed;
int g_iFog_Version;              // bumped on every change (inputs mode sends only on change)
int g_iFog_SentVersion[2049];

KeyValues g_hFog_Config;
char g_sFog_ConfigProblem[128];   // why there are no presets, shown by !fog presets
char g_sFog_PendingPreset[64];
char g_sFog_LastPreset[64];      // last preset applied, shown by !fog
bool g_bFog_PresetEdited;        // changed by hand since then
float g_fFog_PendingAt;

// Safety net at map start: our controller should be gone with the old map's entities. If one is still
// there, point anyone on it back to nothing, switch it off and remove it.
void Fog_RemoveLeftoverCtrl()
{
	// Players in game = the plugin was reloaded during the map, not a map start: they can still be linked
	// to our controller, so it's kept (Fog_OurCtrl finds it again) and only switched off, never killed
	bool reload = false;
	for (int i = 1; i <= MaxClients && !reload; i++)
		reload = IsClientInGame(i);

	char name[64];
	int e = -1;
	while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
	{
		GetEntPropString(e, Prop_Data, "m_iName", name, sizeof(name));
		if (!StrEqual(name, FOG_OUR_NAME))
			continue;

		AcceptEntityInput(e, "TurnOff");
		if (reload)
		{
			LogMessage("Kept the %s from before the plugin reload", FOG_OUR_NAME);
			continue;
		}

		// Nobody may point at it once it's gone
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && HasEntProp(i, Prop_Send, FOG_PLAYER_CTRL_PROP) && GetEntPropEnt(i, Prop_Send, FOG_PLAYER_CTRL_PROP) == e)
				SetEntPropEnt(i, Prop_Send, FOG_PLAYER_CTRL_PROP, -1);
		}

		AcceptEntityInput(e, "Kill");
		LogMessage("Removed a leftover %s at map start", FOG_OUR_NAME);
	}
}

void Fog_ResetState()
{
	g_bFog_Active = false;
	g_bFog_Lerping = false;
	g_fFog_FadeOverride = -1.0;
	g_iFog_SkyOverride = -1;
	g_aFog_OrigRefs.Clear();
	g_aFog_OrigVals.Clear();
	g_bFog_HaveOrigSky = false;
	g_iFog_OurRef = INVALID_ENT_REFERENCE;
	g_sFog_PendingPreset[0] = '\0';
	g_sFog_LastPreset[0] = '\0';
	g_iFog_Version++;
}

float Fog_FadeDefault()
{
	return g_fFog_FadeOverride >= 0.0 ? g_fFog_FadeOverride : g_fFog_Fade;
}

bool Fog_SkyOn()
{
	return g_iFog_SkyOverride >= 0 ? g_iFog_SkyOverride == 1 : g_bFog_Skybox;
}

// ---------------------------------------------------------------- timers / frames

Action Fog_EnforceTimer(Handle timer)
{
	if (g_sFog_PendingPreset[0] != '\0' && GetGameTime() >= g_fFog_PendingAt)
	{
		char name[64];
		strcopy(name, sizeof(name), g_sFog_PendingPreset);
		g_sFog_PendingPreset[0] = '\0';
		if (!Fog_ApplyPreset(0, name, 0.0, true))
			LogError("MapPresets: no preset \"%s\"", name);
	}
	if (g_bFog_Active && !g_bFog_Lerping)
		Fog_ApplyAll();
	return Plugin_Continue;
}

public void OnGameFrame()
{
	if (!g_bFog_Lerping || !g_bFog_Active)
		return;
	float now = GetEngineTime();
	if (now < g_fFog_NextLerpApply)
		return;
	g_fFog_NextLerpApply = now + 0.03;
	Fog_StepLerp(now);
	Fog_ApplyAll();
}

// ---------------------------------------------------------------- values

int Fog_PackColor(const float c[3])
{
	int r = RoundToNearest(c[0]) & 255, g = RoundToNearest(c[1]) & 255, b = RoundToNearest(c[2]) & 255;
	return r | (g << 8) | (b << 16) | (255 << 24);
}

void Fog_UnpackColor(int i, float c[3])
{
	c[0] = float(i & 255);
	c[1] = float((i >> 8) & 255);
	c[2] = float((i >> 16) & 255);
}

bool Fog_PropName(bool sky, int f, char[] name, int len)
{
	if (sky)
	{
		if (!g_bFog_HasSky[f])
			return false;
		strcopy(name, len, g_sFog_SkyProp[f]);
	}
	else
	{
		if (!g_bFog_HasCtrl[f])
			return false;
		strcopy(name, len, g_sFog_CtrlProp[f]);
	}
	return true;
}

void Fog_ReadFog(int ent, bool sky, FogVals v)
{
	v.Defaults();
	char n[64];
	if (Fog_PropName(sky, FOG_F_ENABLE, n, sizeof(n))) v.enable = GetEntProp(ent, Prop_Send, n) != 0;
	if (Fog_PropName(sky, FOG_F_BLEND, n, sizeof(n))) v.blend = GetEntProp(ent, Prop_Send, n) != 0;
	if (Fog_PropName(sky, FOG_F_FARZ, n, sizeof(n))) v.farz = GetEntPropFloat(ent, Prop_Send, n);
	if (Fog_PropName(sky, FOG_F_START, n, sizeof(n))) v.startDist = GetEntPropFloat(ent, Prop_Send, n);
	if (Fog_PropName(sky, FOG_F_END, n, sizeof(n))) v.endDist = GetEntPropFloat(ent, Prop_Send, n);
	if (Fog_PropName(sky, FOG_F_DENSITY, n, sizeof(n))) v.density = GetEntPropFloat(ent, Prop_Send, n);
	float c[3];
	if (Fog_PropName(sky, FOG_F_C1, n, sizeof(n)))
	{
		Fog_UnpackColor(GetEntProp(ent, Prop_Send, n), c);
		v.c1 = c;
	}
	if (Fog_PropName(sky, FOG_F_C2, n, sizeof(n)))
	{
		Fog_UnpackColor(GetEntProp(ent, Prop_Send, n), c);
		v.c2 = c;
	}
}

// Only writes what differs, so unchanged entities aren't flagged for networking.
void Fog_SetIntIfChanged(int ent, const char[] prop, int value)
{
	if (GetEntProp(ent, Prop_Send, prop) != value)
		SetEntProp(ent, Prop_Send, prop, value);
}

void Fog_SetFloatIfChanged(int ent, const char[] prop, float value)
{
	if (GetEntPropFloat(ent, Prop_Send, prop) != value)
		SetEntPropFloat(ent, Prop_Send, prop, value);
}

void Fog_WriteFog(int ent, bool sky, FogVals v)
{
	char n[64];
	if (Fog_PropName(sky, FOG_F_ENABLE, n, sizeof(n))) Fog_SetIntIfChanged(ent, n, v.enable ? 1 : 0);
	if (Fog_PropName(sky, FOG_F_BLEND, n, sizeof(n))) Fog_SetIntIfChanged(ent, n, v.blend ? 1 : 0);
	if (Fog_PropName(sky, FOG_F_FARZ, n, sizeof(n))) Fog_SetFloatIfChanged(ent, n, v.farz);
	if (Fog_PropName(sky, FOG_F_START, n, sizeof(n))) Fog_SetFloatIfChanged(ent, n, v.startDist);
	if (Fog_PropName(sky, FOG_F_END, n, sizeof(n))) Fog_SetFloatIfChanged(ent, n, v.endDist);
	if (Fog_PropName(sky, FOG_F_DENSITY, n, sizeof(n))) Fog_SetFloatIfChanged(ent, n, v.density);
	float c[3];
	if (Fog_PropName(sky, FOG_F_C1, n, sizeof(n)))
	{
		c = v.c1;
		Fog_SetIntIfChanged(ent, n, Fog_PackColor(c));
	}
	if (Fog_PropName(sky, FOG_F_C2, n, sizeof(n)))
	{
		c = v.c2;
		Fog_SetIntIfChanged(ent, n, Fog_PackColor(c));
	}
}

// ---------------------------------------------------------------- entities

void Fog_Detect(int ctrl)
{
	if (g_iFog_Mode != FOG_MODE_UNKNOWN)
		return;
	int found = 0;
	for (int f = 0; f < FOG_F_COUNT; f++)
	{
		g_bFog_HasCtrl[f] = HasEntProp(ctrl, Prop_Send, g_sFog_CtrlProp[f]);
		if (g_bFog_HasCtrl[f])
			found++;
	}
	g_iFog_Mode = (g_bFog_HasCtrl[FOG_F_START] && g_bFog_HasCtrl[FOG_F_END] && g_bFog_HasCtrl[FOG_F_C1]) ? FOG_MODE_PROPS : FOG_MODE_INPUTS;
	LogMessage("Fog controller props found: %d/%d, mode: %s", found, FOG_F_COUNT, g_iFog_Mode == FOG_MODE_PROPS ? "props" : "inputs (fallback)");
}

// Player props are probed on the first player we touch.
void Fog_DetectPlayer(int client)
{
	if (g_bFog_PlayerProbed)
		return;
	g_bFog_PlayerProbed = true;
	int found = 0;
	for (int f = 0; f < FOG_F_COUNT; f++)
	{
		g_bFog_HasSky[f] = g_sFog_SkyProp[f][0] != '\0' && HasEntProp(client, Prop_Send, g_sFog_SkyProp[f]);
		if (g_bFog_HasSky[f])
			found++;
	}
	g_bFog_HasPlayerCtrl = HasEntProp(client, Prop_Send, FOG_PLAYER_CTRL_PROP);
	LogMessage("Skybox fog props found: %d, player fog controller prop: %s", found, g_bFog_HasPlayerCtrl ? "yes" : "no");
}

int Fog_OurCtrl(bool create)
{
	int ent = EntRefToEntIndex(g_iFog_OurRef);
	if (ent == INVALID_ENT_REFERENCE)
	{
		// Fog controllers survive round restarts in CS:S: find ours before making another one.
		ent = -1;
		char name[64];
		int e = -1;
		while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
		{
			GetEntPropString(e, Prop_Data, "m_iName", name, sizeof(name));
			if (StrEqual(name, FOG_OUR_NAME))
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
				DispatchKeyValue(ent, "targetname", FOG_OUR_NAME);
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
		g_iFog_OurRef = ent == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(ent);
	}
	if (ent != -1)
		Fog_Detect(ent);
	return ent;
}

void Fog_ReadCtrl(int ent, FogVals v)
{
	if (g_iFog_Mode == FOG_MODE_PROPS)
		Fog_ReadFog(ent, false, v);
	else
		v.Defaults();   // inputs mode can't read values back
}

void Fog_WriteCtrl(int ent, FogVals v)
{
	if (g_iFog_Mode == FOG_MODE_PROPS)
	{
		Fog_WriteFog(ent, false, v);
		return;
	}
	// Fallback: inputs, only when something changed. Variant floats/colours add nothing to the string pool.
	if (g_iFog_SentVersion[ent] == g_iFog_Version)
		return;
	g_iFog_SentVersion[ent] = g_iFog_Version;
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

void Fog_Remember(int ent)
{
	int ref = EntIndexToEntRef(ent);
	if (g_aFog_OrigRefs.FindValue(ref) != -1)
		return;
	FogVals v;
	Fog_ReadCtrl(ent, v);
	g_aFog_OrigRefs.Push(ref);
	g_aFog_OrigVals.PushArray(v, sizeof(v));
}

// A player with no fog controller (map without fog) gets ours. Players on a map controller stay there:
// every map controller carries the override too.
void Fog_FixPlayer(int client, int ours, int mapCount)
{
	Fog_DetectPlayer(client);
	if (g_bFog_HasPlayerCtrl)
	{
		int c = GetEntPropEnt(client, Prop_Send, FOG_PLAYER_CTRL_PROP);
		if (c == -1 || !IsValidEntity(c))
			SetEntPropEnt(client, Prop_Send, FOG_PLAYER_CTRL_PROP, ours);
	}
	else if (mapCount == 0)
	{
		SetVariantString(FOG_OUR_NAME);
		AcceptEntityInput(client, "SetFogController");
	}
}

// ---------------------------------------------------------------- override

void Fog_TakeOver(int admin)
{
	if (g_bFog_Active)
		return;
	int ours = Fog_OurCtrl(true);
	g_aFog_OrigRefs.Clear();
	g_aFog_OrigVals.Clear();
	g_bFog_HaveOrigSky = false;

	int first = -1, e = -1;
	while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
	{
		if (e == ours)
			continue;
		Fog_Remember(e);
		if (first == -1)
			first = e;
	}

	// Start from what the admin sees now, so the first change blends from the map's own look.
	bool got = false;
	if (admin > 0 && IsClientInGame(admin))
	{
		Fog_DetectPlayer(admin);
		if (g_bFog_HasPlayerCtrl)
		{
			int c = GetEntPropEnt(admin, Prop_Send, FOG_PLAYER_CTRL_PROP);
			if (c != -1 && c != ours && IsValidEntity(c))
			{
				Fog_ReadCtrl(c, g_Fog_Cur);
				got = true;
			}
		}
	}
	if (!got && first != -1)
	{
		Fog_ReadCtrl(first, g_Fog_Cur);
		got = true;
	}
	if (!got)
	{
		g_Fog_Cur.Defaults();
		g_Fog_Cur.enable = false;
	}
	g_bFog_Lerping = false;
	g_bFog_Active = true;
	g_iFog_Version++;
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, true, THIS_MODE_INFO.index);

	// The engine points a spawning player at the map's master controller (or none): they are fixed up on spawn
	FunModes_HookEvent(g_bEvent_PlayerSpawn, "player_spawn", Event_PlayerSpawn);
	if (g_iFog_Mode == FOG_MODE_INPUTS)
		LogError("Fallback inputs mode: \"sm_fog reset\" can't restore the map's exact fog values");
}

void Fog_Restore()
{
	int ours = Fog_OurCtrl(false);
	g_bFog_Active = false;
	g_bFog_Lerping = false;
	g_iFog_Version++;
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);

	FogVals v;
	if (g_iFog_Mode == FOG_MODE_PROPS)
	{
		for (int i = 0; i < g_aFog_OrigRefs.Length; i++)
		{
			int ent = EntRefToEntIndex(g_aFog_OrigRefs.Get(i));
			if (ent == INVALID_ENT_REFERENCE)
				continue;
			g_aFog_OrigVals.GetArray(i, v, sizeof(v));
			Fog_WriteCtrl(ent, v);
		}
	}
	if (ours != -1)
	{
		v = g_Fog_Cur;
		v.enable = false;
		Fog_WriteCtrl(ours, v);
	}
	if (g_bFog_HaveOrigSky)
	{
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i))
				Fog_WriteFog(i, true, g_Fog_OrigSky);
	}
	g_aFog_OrigRefs.Clear();
	g_aFog_OrigVals.Clear();
	g_bFog_HaveOrigSky = false;
	g_sFog_LastPreset[0] = '\0';
}

void Fog_ApplyAll()
{
	int ours = Fog_OurCtrl(true);
	if (ours == -1)
		return;

	int count = 0, e = -1;
	while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
	{
		if (e == ours)
			continue;
		Fog_Remember(e);   // a controller the map spawned after the takeover: remember it before overwriting
		Fog_WriteCtrl(e, g_Fog_Cur);
		count++;
	}
	Fog_WriteCtrl(ours, g_Fog_Cur);

	bool sky = Fog_SkyOn();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		Fog_FixPlayer(i, ours, count);
		if (sky)
		{
			if (!g_bFog_HaveOrigSky)
			{
				Fog_ReadFog(i, true, g_Fog_OrigSky);   // all players share the sky_camera's values
				g_bFog_HaveOrigSky = true;
			}
			Fog_WriteFog(i, true, g_Fog_Cur);
		}
	}
}

// Move to `to` over `fade` seconds. Flags and farz switch at once; distances, density and colours blend.
void Fog_SetTarget(FogVals to, float fade)
{
	if (fade <= 0.0)
	{
		g_Fog_Cur = to;
		g_bFog_Lerping = false;
	}
	else
	{
		g_Fog_From = g_Fog_Cur;
		g_Fog_To = to;
		g_fFog_T0 = GetEngineTime();
		g_fFog_T1 = g_fFog_T0 + fade;
		g_fFog_NextLerpApply = 0.0;
		g_bFog_Lerping = true;
		g_Fog_Cur.enable = to.enable;
		g_Fog_Cur.blend = to.blend;
		g_Fog_Cur.farz = to.farz;
	}
	g_iFog_Version++;
	Fog_ApplyAll();
}

float Fog_Mix(float a, float b, float f)
{
	return a + (b - a) * f;
}

void Fog_StepLerp(float now)
{
	float f = (now - g_fFog_T0) / (g_fFog_T1 - g_fFog_T0);
	g_iFog_Version++;
	if (f >= 1.0)
	{
		g_Fog_Cur = g_Fog_To;
		g_bFog_Lerping = false;
		return;
	}
	f = f * f * (3.0 - 2.0 * f);   // ease in/out
	g_Fog_Cur.startDist = Fog_Mix(g_Fog_From.startDist, g_Fog_To.startDist, f);
	g_Fog_Cur.endDist = Fog_Mix(g_Fog_From.endDist, g_Fog_To.endDist, f);
	g_Fog_Cur.density = Fog_Mix(g_Fog_From.density, g_Fog_To.density, f);
	for (int i = 0; i < 3; i++)
	{
		g_Fog_Cur.c1[i] = Fog_Mix(g_Fog_From.c1[i], g_Fog_To.c1[i], f);
		g_Fog_Cur.c2[i] = Fog_Mix(g_Fog_From.c2[i], g_Fog_To.c2[i], f);
	}
}

// The value a new change builds on: where a running fade is heading, else what's shown.
void Fog_CurrentTarget(FogVals out)
{
	if (g_bFog_Lerping)
		out = g_Fog_To;
	else
		out = g_Fog_Cur;
}

// ---------------------------------------------------------------- presets

bool Fog_KvFloat(const char[] key, float &out)
{
	char s[32];
	g_hFog_Config.GetString(key, s, sizeof(s), "");
	if (s[0] == '\0')
		return false;
	out = StringToFloat(s);
	return true;
}

bool Fog_KvColor(const char[] key, float c[3])
{
	char s[32], parts[3][8];
	g_hFog_Config.GetString(key, s, sizeof(s), "");
	if (ExplodeString(s, " ", parts, sizeof(parts), sizeof(parts[])) != 3)
		return false;
	for (int i = 0; i < 3; i++)
		c[i] = float(StringToInt(parts[i]));
	return true;
}

bool Fog_ApplyPreset(int client, const char[] name, float fade, bool quiet)
{
	if (!Fog_HaveConfig())
		return false;
	g_hFog_Config.Rewind();
	if (!g_hFog_Config.JumpToKey("Presets") || !g_hFog_Config.JumpToKey(name))
	{
		g_hFog_Config.Rewind();
		return false;
	}

	Fog_TakeOver(client);
	FogVals to;
	Fog_CurrentTarget(to);
	to.enable = g_hFog_Config.GetNum("enable", 1) != 0;
	float f;
	if (Fog_KvFloat("start", f)) to.startDist = f;
	if (Fog_KvFloat("end", f)) to.endDist = f;
	if (Fog_KvFloat("density", f)) to.density = f;
	if (Fog_KvFloat("farz", f)) to.farz = f <= 0.0 ? -1.0 : f;
	if (Fog_KvFloat("blend", f)) to.blend = f >= 0.5;
	float c[3];
	if (Fog_KvColor("color", c))
	{
		to.c1 = c;
		to.c2 = c;
	}
	if (Fog_KvColor("color2", c))
		to.c2 = c;
	g_hFog_Config.Rewind();
	strcopy(g_sFog_LastPreset, sizeof(g_sFog_LastPreset), name);
	g_bFog_PresetEdited = false;

	Fog_SetTarget(to, fade);
	if (quiet)
		LogMessage("Map preset \"%s\" applied", name);
	else
		Fog_Announce(client, "set the fog preset '%s'", name);
	return true;
}

// ---------------------------------------------------------------- chat

void Fog_Reply(int client, const char[] fmt, any ...)
{
	char buf[256];
	VFormat(buf, sizeof(buf), fmt, 3);
	CReplyToCommand(client, "%s %s", THIS_MODE_INFO.tag, buf);
}

void Fog_Announce(int client, const char[] fmt, any ...)
{
	char buf[192];
	VFormat(buf, sizeof(buf), fmt, 3);
	if (g_bFog_Announce)
		CPrintToChatAll("%s {olive}%N {lightgreen}%s", THIS_MODE_INFO.tag, client, buf);
	else
		Fog_Reply(client, "%s", buf);
	LogAction(client, -1, "\"%L\" %s", client, buf);
}

// Player-typed number in [lo, hi]; the whole argument must be a number ("1,5" or "8x" are rejected).
bool Fog_ArgFloat(int i, float lo, float hi, float &out)
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
bool Fog_ArgFade(int i, float &out)
{
	if (GetCmdArgs() < i)
	{
		out = Fog_FadeDefault();
		return true;
	}
	return Fog_ArgFloat(i, 0.0, 120.0, out);
}

char g_sFog_ColorNames[][] =
{
	"white", "grey", "gray", "black", "red", "darkred", "green", "darkgreen", "blue", "darkblue",
	"yellow", "orange", "purple", "pink", "cyan", "brown", "gold"
};

int g_iFog_ColorValues[][3] =
{
	{255, 255, 255}, {128, 128, 128}, {128, 128, 128}, {0, 0, 0}, {200, 30, 30}, {90, 10, 10},
	{40, 170, 60}, {20, 70, 30}, {40, 70, 200}, {10, 20, 70}, {230, 210, 60}, {230, 120, 20},
	{110, 30, 160}, {255, 130, 190}, {40, 200, 220}, {110, 70, 35}, {210, 170, 60}
};

// A colour from the arguments starting at i: "r g b", one number (grey), a name, or hex (#ff8800).
// Returns how many arguments it used, 0 if it isn't a colour.
int Fog_ArgColor(int i, float c[3])
{
	float v[3];
	if (Fog_ArgFloat(i, 0.0, 255.0, v[0]) && Fog_ArgFloat(i + 1, 0.0, 255.0, v[1]) && Fog_ArgFloat(i + 2, 0.0, 255.0, v[2]))
	{
		for (int k = 0; k < 3; k++)
			c[k] = float(RoundToNearest(v[k]));
		return 3;
	}
	if (GetCmdArgs() < i)
		return 0;
	if (Fog_ArgFloat(i, 0.0, 255.0, v[0]))
	{
		c[0] = float(RoundToNearest(v[0]));
		c[1] = c[0];
		c[2] = c[0];
		return 1;
	}

	char s[32];
	GetCmdArg(i, s, sizeof(s));
	Fog_StringToLower(s);
	int start = s[0] == '#' ? 1 : 0, hex;
	if (strlen(s[start]) == 6 && StringToIntEx(s[start], hex, 16) == 6)
	{
		c[0] = float((hex >> 16) & 255);
		c[1] = float((hex >> 8) & 255);
		c[2] = float(hex & 255);
		return 1;
	}
	for (int n = 0; n < sizeof(g_sFog_ColorNames); n++)
	{
		if (StrEqual(s, g_sFog_ColorNames[n]))
		{
			for (int k = 0; k < 3; k++)
				c[k] = float(g_iFog_ColorValues[n][k]);
			return 1;
		}
	}
	return 0;
}

void Fog_ColorUsage(int client, const char[] cmd)
{
	Fog_Reply(client, "Usage: !fog %s <r g b | 0-255 for grey | name | #hex> [seconds]", cmd);
	Fog_Reply(client, "e.g. !fog %s 255 120 0   !fog %s 200   !fog %s red 5   !fog %s #ff8800", cmd, cmd, cmd, cmd);
	Fog_Reply(client, "Names: white, grey, black, red, darkred, green, darkgreen, blue, darkblue, yellow, orange, purple, pink, cyan, brown, gold");
}

void Fog_ColorStr(const float c[3], char[] out, int len)
{
	Format(out, len, "%d %d %d", RoundToNearest(c[0]), RoundToNearest(c[1]), RoundToNearest(c[2]));
}

int Fog_CountMapCtrls()
{
	int ours = EntRefToEntIndex(g_iFog_OurRef), n = 0, e = -1;
	while ((e = FindEntityByClassname(e, "env_fog_controller")) != -1)
		if (e != ours)
			n++;
	return n;
}

void Fog_Help(int client)
{
	Fog_Reply(client, "!fog status | on | off | reset");
	Fog_Reply(client, "!fog start <n> | end <n> | range <start> <end>");
	Fog_Reply(client, "!fog color <r g b | grey 0-255 | name | #hex> | color2 <same>  (color2 shows only with blend 1)");
	Fog_Reply(client, "!fog density <0-1> | farz <n, -1 = off> | blend <0|1>");
	Fog_Reply(client, "!fog preset <name> | presets | reload | fade <sec> | sky <on|off>");
	Fog_Reply(client, "Add seconds at the end of a change to blend it in, e.g. !fog end 800 5");
}

// One line saying whether the fog is on, shown when someone types just !fog.
void Fog_StateLine(int client)
{
	if (!g_bFog_Active)
	{
		Fog_Reply(client, "Fog override: OFF (map's own fog, %d controller(s))", Fog_CountMapCtrls());
		return;
	}
	FogVals v;
	Fog_CurrentTarget(v);
	if (!v.enable)
	{
		Fog_Reply(client, "Fog override: ON - fog turned OFF");
		return;
	}
	char preset[80];
	if (g_sFog_LastPreset[0] != '\0')
		Format(preset, sizeof(preset), " | preset %s%s", g_sFog_LastPreset, g_bFog_PresetEdited ? " (edited)" : "");
	float c[3];
	char cs[16];
	c = v.c1;
	Fog_ColorStr(c, cs, sizeof(cs));
	Fog_Reply(client, "Fog override: ON - fog ON | %d to %d | colour %s%s",
		RoundToNearest(v.startDist), RoundToNearest(v.endDist), cs, preset);
}

void Fog_Status(int client)
{
	int n = Fog_CountMapCtrls();
	if (!g_bFog_Active)
	{
		Fog_Reply(client, "Map default fog (no override). Map fog controllers: %d", n);
		return;
	}
	FogVals v;
	Fog_CurrentTarget(v);
	char c1[16], c2[16];
	float c[3];
	c = v.c1;
	Fog_ColorStr(c, c1, sizeof(c1));
	c = v.c2;
	Fog_ColorStr(c, c2, sizeof(c2));
	Fog_Reply(client, "Override %s | start %d end %d | color %s / %s", v.enable ? "ON" : "OFF",
		RoundToNearest(v.startDist), RoundToNearest(v.endDist), c1, c2);
	Fog_Reply(client, "density %.2f | farz %d | blend %d | fade %.1fs | skybox %s | map controllers %d",
		v.density, RoundToNearest(v.farz), v.blend ? 1 : 0, Fog_FadeDefault(), Fog_SkyOn() ? "on" : "off", n);
}

Action Cmd_FogCommand(int client, int args)
{
	char sub[32];
	if (args < 1)
		strcopy(sub, sizeof(sub), "help");
	else
		GetCmdArg(1, sub, sizeof(sub));
	Fog_StringToLower(sub);

	// ---- commands that don't change the fog
	if (StrEqual(sub, "help"))
	{
		Fog_StateLine(client);
		Fog_Help(client);
		return Plugin_Handled;
	}
	if (StrEqual(sub, "status"))
	{
		Fog_Status(client);
		return Plugin_Handled;
	}
	if (StrEqual(sub, "reload"))
	{
		if (Fog_LoadConfig())
			Fog_Reply(client, "Fog.cfg reloaded.");
		else
			Fog_Reply(client, "Couldn't load the presets: %s", g_sFog_ConfigProblem);

		return Plugin_Handled;
	}
	if (StrEqual(sub, "presets"))
	{
		// Many presets: one chat line per ~150 characters so nothing gets cut off.
		char names[192], name[32];
		int count = 0;
		if (Fog_HaveConfig())
		{
			g_hFog_Config.Rewind();
			if (g_hFog_Config.JumpToKey("Presets") && g_hFog_Config.GotoFirstSubKey())
			{
				do
				{
					g_hFog_Config.GetSectionName(name, sizeof(name));
					if (strlen(names) + strlen(name) > 150)
					{
						Fog_Reply(client, "%s", names);
						names[0] = '\0';
					}
					Format(names, sizeof(names), "%s%s%s", names, names[0] == '\0' ? "" : ", ", name);
					count++;
				}
				while (g_hFog_Config.GotoNextKey());
			}
			g_hFog_Config.Rewind();
		}
		if (count == 0)
			Fog_Reply(client, "Presets: none - %s", g_sFog_ConfigProblem[0] ? g_sFog_ConfigProblem : "Fog.cfg has no \"Presets\" section");
		else
			Fog_Reply(client, "%s  (%d presets)", names, count);
		return Plugin_Handled;
	}
	if (StrEqual(sub, "fade"))
	{
		float t;
		if (!Fog_ArgFloat(2, 0.0, 120.0, t))
			Fog_Reply(client, "Usage: !fog fade <seconds 0-120>");
		else
		{
			g_fFog_FadeOverride = t;
			Fog_Reply(client, "Changes now blend over %.1fs (until map change)", t);
		}
		return Plugin_Handled;
	}
	if (StrEqual(sub, "reset"))
	{
		if (!g_bFog_Active)
			Fog_Reply(client, "The fog is already the map's own.");
		else
		{
			Fog_Restore();
			Fog_Announce(client, "reset the fog to the map default");
		}
		return Plugin_Handled;
	}
	if (StrEqual(sub, "sky"))
	{
		char on[8];
		GetCmdArg(2, on, sizeof(on));
		Fog_StringToLower(on);
		if (!StrEqual(on, "on") && !StrEqual(on, "off"))
		{
			Fog_Reply(client, "Usage: !fog sky <on|off>");
			return Plugin_Handled;
		}
		g_iFog_SkyOverride = StrEqual(on, "on") ? 1 : 0;
		if (g_iFog_SkyOverride == 0 && g_bFog_HaveOrigSky)
		{
			for (int i = 1; i <= MaxClients; i++)
				if (IsClientInGame(i) && !IsFakeClient(i))
					Fog_WriteFog(i, true, g_Fog_OrigSky);
		}
		Fog_Reply(client, "Skybox fog override %s (until map change)", on);
		return Plugin_Handled;
	}
	if (StrEqual(sub, "preset"))
	{
		char name[64];
		float fade;
		if (args < 2)
			Fog_Reply(client, "Usage: !fog preset <name> [seconds]  (!fog presets lists them)");
		else if (!Fog_ArgFade(3, fade))
			Fog_Reply(client, "Bad fade time (0-120 seconds).");
		else
		{
			GetCmdArg(2, name, sizeof(name));
			Fog_StringToLower(name);
			if (!Fog_ApplyPreset(client, name, fade, false))
				Fog_Reply(client, "No preset '%s'. !fog presets lists them.", name);
		}
		return Plugin_Handled;
	}

	// ---- commands that change the fog: check the arguments, take over, then build the new target
	FogVals to;
	float fade = Fog_FadeDefault(), v, v2;
	float c[3];
	char msg[96], cs[16];
	bool ok = true;

	if (!g_bFog_Active)
	{
		// Fog_TakeOver needs to happen before Fog_CurrentTarget reads g_Fog_Cur, but not for typos.
		if (!StrEqual(sub, "on") && !StrEqual(sub, "off") && !StrEqual(sub, "start") && !StrEqual(sub, "end")
			&& !StrEqual(sub, "range") && !StrEqual(sub, "dist") && !StrEqual(sub, "color") && !StrEqual(sub, "colour")
			&& !StrEqual(sub, "color2") && !StrEqual(sub, "colour2") && !StrEqual(sub, "density")
			&& !StrEqual(sub, "farz") && !StrEqual(sub, "blend"))
		{
			Fog_Reply(client, "Unknown command '%s'. Type !fog for help.", sub);
			return Plugin_Handled;
		}
		Fog_TakeOver(client);
	}
	Fog_CurrentTarget(to);

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
		if ((ok = Fog_ArgFloat(2, -50000.0, 50000.0, v) && Fog_ArgFade(3, fade)))
		{
			to.startDist = v;
			to.enable = true;
			Format(msg, sizeof(msg), "set the fog start to %d", RoundToNearest(v));
		}
		else
			Fog_Reply(client, "Usage: !fog start <distance> [seconds]");
	}
	else if (StrEqual(sub, "end"))
	{
		if ((ok = Fog_ArgFloat(2, -50000.0, 100000.0, v) && Fog_ArgFade(3, fade)))
		{
			to.endDist = v;
			to.enable = true;
			Format(msg, sizeof(msg), "set the fog end to %d", RoundToNearest(v));
		}
		else
			Fog_Reply(client, "Usage: !fog end <distance> [seconds]");
	}
	else if (StrEqual(sub, "range") || StrEqual(sub, "dist"))
	{
		if ((ok = Fog_ArgFloat(2, -50000.0, 50000.0, v) && Fog_ArgFloat(3, -50000.0, 100000.0, v2) && Fog_ArgFade(4, fade)))
		{
			to.startDist = v;
			to.endDist = v2;
			to.enable = true;
			Format(msg, sizeof(msg), "set the fog to %d - %d", RoundToNearest(v), RoundToNearest(v2));
		}
		else
			Fog_Reply(client, "Usage: !fog range <start> <end> [seconds]");
	}
	else if (StrEqual(sub, "color") || StrEqual(sub, "colour"))
	{
		int used = Fog_ArgColor(2, c);
		if ((ok = used > 0 && Fog_ArgFade(2 + used, fade)))
		{
			to.c1 = c;
			to.c2 = c;
			to.enable = true;
			Fog_ColorStr(c, cs, sizeof(cs));
			Format(msg, sizeof(msg), "set the fog colour to %s", cs);
		}
		else
			Fog_ColorUsage(client, "color");
	}
	else if (StrEqual(sub, "color2") || StrEqual(sub, "colour2"))
	{
		int used = Fog_ArgColor(2, c);
		if ((ok = used > 0 && Fog_ArgFade(2 + used, fade)))
		{
			to.c2 = c;
			to.enable = true;
			Fog_ColorStr(c, cs, sizeof(cs));
			Format(msg, sizeof(msg), "set the secondary fog colour to %s", cs);
		}
		else
			Fog_ColorUsage(client, "color2");
	}
	else if (StrEqual(sub, "density"))
	{
		if ((ok = Fog_ArgFloat(2, 0.0, 1.0, v) && Fog_ArgFade(3, fade)))
		{
			to.density = v;
			to.enable = true;
			Format(msg, sizeof(msg), "set the fog density to %.2f", v);
		}
		else
			Fog_Reply(client, "Usage: !fog density <0-1> [seconds]");
	}
	else if (StrEqual(sub, "farz"))
	{
		if ((ok = Fog_ArgFloat(2, -1.0, 100000.0, v)))
		{
			to.farz = v <= 0.0 ? -1.0 : v;
			fade = 0.0;
			if (to.farz < 0.0)
				strcopy(msg, sizeof(msg), "turned the far clip off");
			else
				Format(msg, sizeof(msg), "set the far clip to %d", RoundToNearest(v));
		}
		else
			Fog_Reply(client, "Usage: !fog farz <distance, -1 = off>");
	}
	else if (StrEqual(sub, "blend"))
	{
		if ((ok = Fog_ArgFloat(2, 0.0, 1.0, v)))
		{
			to.blend = v >= 0.5;
			fade = 0.0;
			Format(msg, sizeof(msg), "set fog blend %d", to.blend ? 1 : 0);
		}
		else
			Fog_Reply(client, "Usage: !fog blend <0|1>");
	}
	else
	{
		Fog_Reply(client, "Unknown command '%s'. Type !fog for help.", sub);
		return Plugin_Handled;
	}

	if (!ok)
		return Plugin_Handled;
	if (to.enable && to.startDist >= to.endDist)
	{
		Fog_Reply(client, "The start (%d) must be below the end (%d).", RoundToNearest(to.startDist), RoundToNearest(to.endDist));
		return Plugin_Handled;
	}
	g_bFog_PresetEdited = true;
	Fog_SetTarget(to, fade);
	Fog_Announce(client, "%s", msg);
	return Plugin_Handled;
}

// ---------------------------------------------------------------- menu page

float g_fFog_FadeSteps[] = { 0.0, 1.0, 2.0, 5.0, 10.0, 20.0 };

bool Fog_IsOn()
{
	if (!g_bFog_Active)
		return false;
	FogVals v;
	Fog_CurrentTarget(v);
	return v.enable;
}

void Fog_RestoreSkies()
{
	if (!g_bFog_HaveOrigSky)
		return;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			Fog_WriteFog(i, true, g_Fog_OrigSky);
}

void Fog_Menu(int client)
{
	Menu menu = new Menu(Menu_FogHandler);
	char title[192], line[64];
	if (!g_bFog_Active)
		strcopy(title, sizeof(title), "Fog - the map's own fog");
	else
	{
		FogVals v;
		Fog_CurrentTarget(v);
		if (!v.enable)
			strcopy(title, sizeof(title), "Fog - turned OFF");
		else
			Format(title, sizeof(title), "Fog - ON, %d to %d", RoundToNearest(v.startDist), RoundToNearest(v.endDist));
		if (g_sFog_LastPreset[0] != '\0')
			Format(title, sizeof(title), "%s\nPreset: %s%s", title, g_sFog_LastPreset, g_bFog_PresetEdited ? " (edited)" : "");
	}
	Format(title, sizeof(title), "%s\nFine-tune with !fog in chat\n ", title);
	menu.SetTitle(title);

	bool on = Fog_IsOn();
	menu.AddItem("toggle", on ? "Turn fog OFF" : "Turn fog ON");
	menu.AddItem("presets", "Presets...");
	menu.AddItem("thicker", "Thicker (fog closer)", on ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("thinner", "Thinner (fog further)", on ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Fade time: %.0fs", Fog_FadeDefault());
	menu.AddItem("fade", line);
	Format(line, sizeof(line), "Skybox fog: %s", Fog_SkyOn() ? "ON" : "OFF");
	menu.AddItem("sky", line);
	menu.AddItem("reset", "Back to the map's own fog", g_bFog_Active ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

// Scale the fog distances: k < 1 pulls the fog in, k > 1 pushes it out.
void Fog_Scale(int client, float k)
{
	Fog_TakeOver(client);
	FogVals to;
	Fog_CurrentTarget(to);
	to.endDist *= k;
	if (to.startDist > 0.0)
		to.startDist *= k;
	if (to.endDist < to.startDist + 50.0)
		to.endDist = to.startDist + 50.0;
	to.enable = true;
	g_bFog_PresetEdited = true;
	Fog_SetTarget(to, Fog_FadeDefault());
	Fog_Announce(client, "made the fog %s (%d to %d)", k < 1.0 ? "thicker" : "thinner",
		RoundToNearest(to.startDist), RoundToNearest(to.endDist));
}

int Menu_FogHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		DisplayModeInfo(client, g_iPreviousModeIndex[client]);
	else if (action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "cvars"))
		{
			ShowCvarsInfo(client, THIS_MODE_INFO);
			return 0;
		}
		else if (StrEqual(info, "toggle"))
		{
			Fog_TakeOver(client);
			FogVals to;
			Fog_CurrentTarget(to);
			to.enable = !to.enable;
			if (to.enable && to.startDist >= to.endDist)
				to.Defaults();
			g_bFog_PresetEdited = true;
			Fog_SetTarget(to, 0.0);
			Fog_Announce(client, to.enable ? "turned the fog on" : "turned the fog off");
		}
		else if (StrEqual(info, "presets"))
		{
			Fog_PresetMenu(client, 0);
			return 0;
		}
		else if (StrEqual(info, "thicker"))
			Fog_Scale(client, 0.75);
		else if (StrEqual(info, "thinner"))
			Fog_Scale(client, 1.33);
		else if (StrEqual(info, "fade"))
		{
			float cur = Fog_FadeDefault(), next = g_fFog_FadeSteps[0];
			for (int i = 0; i < sizeof(g_fFog_FadeSteps); i++)
			{
				if (g_fFog_FadeSteps[i] > cur + 0.05)
				{
					next = g_fFog_FadeSteps[i];
					break;
				}
			}
			g_fFog_FadeOverride = next;
		}
		else if (StrEqual(info, "sky"))
		{
			g_iFog_SkyOverride = Fog_SkyOn() ? 0 : 1;
			if (g_iFog_SkyOverride == 0)
				Fog_RestoreSkies();
		}
		else if (StrEqual(info, "reset") && g_bFog_Active)
		{
			Fog_Restore();
			Fog_Announce(client, "reset the fog to the map default");
		}
		Fog_Menu(client);
	}
	return 0;
}

void Fog_PresetMenu(int client, int firstItem)
{
	Menu menu = new Menu(Menu_FogPresets);
	menu.SetTitle("Fog presets\n(blends in over the fade time)\n ");
	char name[32], line[48];
	if (Fog_HaveConfig())
	{
		g_hFog_Config.Rewind();
		if (g_hFog_Config.JumpToKey("Presets") && g_hFog_Config.GotoFirstSubKey())
		{
			do
			{
				g_hFog_Config.GetSectionName(name, sizeof(name));
				if (g_bFog_Active && StrEqual(name, g_sFog_LastPreset, false) && !g_bFog_PresetEdited)
					Format(line, sizeof(line), "%s  (current)", name);
				else
					strcopy(line, sizeof(line), name);
				menu.AddItem(name, line);
			}
			while (g_hFog_Config.GotoNextKey());
		}
		g_hFog_Config.Rewind();
	}
	if (menu.ItemCount == 0)
		menu.AddItem("", "No presets - check configs/FunModes/Fog.cfg", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

int Menu_FogPresets(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		Cmd_FogSettings(client, 0);
	else if (action == MenuAction_Select)
	{
		char name[32];
		menu.GetItem(item, name, sizeof(name));
		if (!Fog_ApplyPreset(client, name, Fog_FadeDefault(), false))
			CPrintToChat(client, "%s Preset '%s' is gone - was the config changed?", THIS_MODE_INFO.tag, name);
		Fog_PresetMenu(client, GetMenuSelectionPosition());   // stay on the same page
	}
	return 0;
}

// ---------------------------------------------------------------- FunModes

public void OnPluginStart_Fog()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	RegAdminCmd("sm_fm_fog", Cmd_FogToggle, ADMFLAG_CONVARS, "Turn the Fog On/Off");
	RegAdminCmd("sm_fogmode", Cmd_FogSettings, ADMFLAG_CONVARS, "Open the Fog Settings Menu");
	RegAdminCmd("sm_fog_start", Cmd_FogStart, ADMFLAG_CONVARS, "Change the fog start distance");
	RegAdminCmd("sm_fog_end", Cmd_FogEnd, ADMFLAG_CONVARS, "Change the fog end distance");
	RegAdminCmd("sm_fog", Cmd_FogCommand, ADMFLAG_CONVARS, "Fog control - sm_fog help");

	DECLARE_FM_CVAR(
		FOG_CONVAR_TOGGLE, "sm_fog_enable",
		"1", "Enable Fog mode",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		FOG_CONVAR_FADE, "sm_fog_fade",
		"1.0", "Default seconds a fog change blends in",
		("0.0,1.0,2.0,5.0,10.0,20.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		FOG_CONVAR_SKYBOX, "sm_fog_skybox",
		"1", "Also override the 3D skybox fog",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		FOG_CONVAR_ANNOUNCE, "sm_fog_announce",
		"1", "Tell everyone in chat when an admin changes the fog",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		FOG_CONVAR_INTERVAL, "sm_fog_interval",
		"0.3", "Seconds between re-applying the fog so the map can't undo it",
		("0.1,0.3,0.5,1.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		FOG_CONVAR_PRESET, "sm_fog_preset",
		"event", "Preset of configs/FunModes/Fog.cfg applied when the mode is turned on (random = a random one)",
		"", CONVAR_STRING
	);

	for (int i = 0; i <= FOG_CONVAR_PRESET; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Fog_OnConVarChange);

	THIS_MODE_INFO.enableIndex = FOG_CONVAR_TOGGLE;

	g_aFog_OrigRefs = new ArrayList();
	g_aFog_OrigVals = new ArrayList(sizeof(FogVals));
}

public void InitCvarsValues_Fog()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_bFog_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, FOG_CONVAR_TOGGLE, Bool);
	g_fFog_Fade = _FUNMODES_CVAR_GET_VALUE(modeIndex, FOG_CONVAR_FADE, Float);
	g_bFog_Skybox = _FUNMODES_CVAR_GET_VALUE(modeIndex, FOG_CONVAR_SKYBOX, Bool);
	g_bFog_Announce = _FUNMODES_CVAR_GET_VALUE(modeIndex, FOG_CONVAR_ANNOUNCE, Bool);
	g_fFog_Interval = _FUNMODES_CVAR_GET_VALUE(modeIndex, FOG_CONVAR_INTERVAL, Float);
	g_sFog_Preset = _FUNMODES_CVAR_GET_VALUE(modeIndex, FOG_CONVAR_PRESET, String);

	// The config is read in OnMapStart (SourceMod calls it on a late load too), or the first time a preset is needed
	Fog_ResetState();
	Fog_StartTimer();
}

void Fog_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case FOG_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (g_bFog_Active && !val)
				Fog_Restore();

			g_bFog_Enabled = val;
		}

		case FOG_CONVAR_FADE:
			g_fFog_Fade = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case FOG_CONVAR_SKYBOX:
		{
			g_bFog_Skybox = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (!Fog_SkyOn())
				Fog_RestoreSkies();
		}

		case FOG_CONVAR_ANNOUNCE:
			g_bFog_Announce = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case FOG_CONVAR_INTERVAL:
		{
			g_fFog_Interval = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);
			Fog_StartTimer();
		}

		case FOG_CONVAR_PRESET:
			g_sFog_Preset = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, String);
	}
}

public void OnMapStart_Fog()
{
	Fog_ResetState();
	Fog_RemoveLeftoverCtrl();
	Fog_LoadConfig();
	Fog_StartTimer();

	// Automatic preset for this map ("MapPresets" in configs/FunModes/Fog.cfg), applied once the entities are up
	if (g_hFog_Config == null)
		return;

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	g_hFog_Config.Rewind();
	if (g_hFog_Config.JumpToKey("MapPresets"))
	{
		g_hFog_Config.GetString(map, g_sFog_PendingPreset, sizeof(g_sFog_PendingPreset), "");
		g_fFog_PendingAt = GetGameTime() + 0.5;
	}

	g_hFog_Config.Rewind();
}

/* The fog never carries over to the next map: switch it off and forget everything now */
public void OnMapEnd_Fog()
{
	if (g_bFog_Active)
		Fog_Restore();

	Fog_ResetState();
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);

	// TIMER_FLAG_NO_MAPCHANGE already killed it
	g_hFog_Timer = null;
}

public void OnPluginEnd_Fog()
{
	if (g_bFog_Active)
		Fog_Restore();
}

public void Event_PlayerSpawn_Fog(int client)
{
	// The engine points a spawning player at the map's master controller (or none): fix them up quickly
	if (g_bFog_Active)
		CreateTimer(0.1, Fog_SpawnedTimer, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action Fog_SpawnedTimer(Handle timer)
{
	if (g_bFog_Active)
		Fog_ApplyAll();

	return Plugin_Stop;
}

void Fog_StartTimer()
{
	delete g_hFog_Timer;
	g_hFog_Timer = CreateTimer(g_fFog_Interval, Fog_EnforceTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool Fog_LoadConfig()
{
	delete g_hFog_Config;
	g_sFog_ConfigProblem[0] = '\0';

	// The old eventmodes location is still read, for servers that only have that one
	static const char files[][] = { "configs/FunModes/Fog.cfg", "configs/eventmodes/dynamicfog.cfg" };

	char path[PLATFORM_MAX_PATH];
	for (int i = 0; i < sizeof(files); i++)
	{
		BuildPath(Path_SM, path, sizeof(path), files[i]);
		if (!FileExists(path))
			continue;

		g_hFog_Config = new KeyValues("DynamicFog");
		if (FunModes_LoadKV(g_hFog_Config, path))
			return true;

		delete g_hFog_Config;
		strcopy(g_sFog_ConfigProblem, sizeof(g_sFog_ConfigProblem), g_sKvError);
		LogError("[FunModes-Fog] Couldn't parse %s", g_sKvError);
	}

	if (!g_sFog_ConfigProblem[0])
	{
		BuildPath(Path_SM, path, sizeof(path), files[0]);
		LogError("[FunModes-Fog] Couldn't find %s - no presets available", path);
		FormatEx(g_sFog_ConfigProblem, sizeof(g_sFog_ConfigProblem), "%s is missing", path);
	}

	return false;
}

/* The presets are there, reading the file again if they aren't yet (uploaded during the map) */
bool Fog_HaveConfig()
{
	return g_hFog_Config != null || Fog_LoadConfig();
}

void Fog_StringToLower(char[] text)
{
	for (int i = 0; text[i] != '\0'; i++)
		text[i] = CharToLower(text[i]);
}

/* A random preset name from the config, false if there are none */
bool Fog_RandomPreset(char[] name, int maxlen)
{
	if (!Fog_HaveConfig())
		return false;

	int count;
	g_hFog_Config.Rewind();
	if (g_hFog_Config.JumpToKey("Presets") && g_hFog_Config.GotoFirstSubKey())
	{
		do
			count++;
		while (g_hFog_Config.GotoNextKey());
	}

	g_hFog_Config.Rewind();
	if (!count)
		return false;

	int pick = GetRandomInt(0, count - 1), index;
	bool found = false;
	if (g_hFog_Config.JumpToKey("Presets") && g_hFog_Config.GotoFirstSubKey())
	{
		do
		{
			if (index++ != pick)
				continue;

			g_hFog_Config.GetSectionName(name, maxlen);
			found = true;
			break;
		} while (g_hFog_Config.GotoNextKey());
	}

	g_hFog_Config.Rewind();
	return found;
}

/* sm_fog_start / sm_fog_end */
void Fog_SetDistance(int client, int args, bool start)
{
	float distance;
	if (args < 1 || !Fog_ArgFloat(1, -50000.0, 100000.0, distance))
	{
		CReplyToCommand(client, "%s Usage: %s <distance>", THIS_MODE_INFO.tag, start ? "sm_fog_start" : "sm_fog_end");
		return;
	}

	Fog_TakeOver(client);

	FogVals to;
	Fog_CurrentTarget(to);
	if (start)
		to.startDist = distance;
	else
		to.endDist = distance;

	to.enable = true;
	if (to.startDist >= to.endDist)
	{
		CReplyToCommand(client, "%s The start (%d) must be below the end (%d).", THIS_MODE_INFO.tag, RoundToNearest(to.startDist), RoundToNearest(to.endDist));
		return;
	}

	g_bFog_PresetEdited = true;
	Fog_SetTarget(to, Fog_FadeDefault());
	Fog_Announce(client, "set the fog %s to %d", start ? "start" : "end", RoundToNearest(distance));
}

public Action Cmd_FogToggle(int client, int args)
{
	if (!g_bFog_Enabled)
	{
		CReplyToCommand(client, "%s Fog is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	THIS_MODE_INFO.byRoulette = false;

	if (g_bFog_Active)
	{
		Fog_Restore();
		CPrintToChatAll("%s Fog is now {olive}Off{lightgreen}, the map has its own fog back!", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	char preset[64];
	strcopy(preset, sizeof(preset), g_sFog_Preset);
	if (strcmp(preset, "random", false) == 0 && !Fog_RandomPreset(preset, sizeof(preset)))
		preset[0] = '\0';

	Fog_StringToLower(preset);
	if (!preset[0] || !Fog_ApplyPreset(client, preset, Fog_FadeDefault(), true))
	{
		// No preset: a thick grey fog
		Fog_TakeOver(client);

		FogVals to;
		to.Defaults();
		to.startDist = 50.0;
		to.endDist = 250.0;
		Fog_SetTarget(to, Fog_FadeDefault());
	}

	CPrintToChatAll("%s Fog is now {olive}On{lightgreen}!", THIS_MODE_INFO.tag);
	return Plugin_Handled;
}

public Action Cmd_FogSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Fog_Menu(client);
	return Plugin_Handled;
}

public Action Cmd_FogStart(int client, int args)
{
	Fog_SetDistance(client, args, true);
	return Plugin_Handled;
}

public Action Cmd_FogEnd(int client, int args)
{
	Fog_SetDistance(client, args, false);
	return Plugin_Handled;
}

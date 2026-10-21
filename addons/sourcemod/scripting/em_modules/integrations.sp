// Optional links to other plugins on a zombie escape server, for eventmodes.sp. None is required: each
// is only used while that plugin is loaded, so eventmodes runs the same without them.
//
//   Zombie Reloaded   instant infection events (who, by whom, mother zombie) and its human/zombie check
//   EntWatch          which weapons are special map items (never stripped, dropped or blocked)
//   DynamicChannels   free on-screen text channels shared with other plugins (no overwriting each other)
//
// The functions are declared here instead of including each plugin's .inc, and marked optional.

#if defined _em_integrations_included
 #endinput
#endif
#define _em_integrations_included

// ---- Zombie Reloaded (library "zombiereloaded")
native bool ZR_IsClientHuman(int client);
native bool ZR_IsClientZombie(int client);

// ---- EntWatch (library "EntWatch")
native bool EntWatch_IsSpecialItem(int entity);
native bool EntWatch_HasSpecialItem(int client);

// ---- DynamicChannels (library "DynamicChannels")
native int GetDynamicChannel(int channel);

bool g_HasZR;
bool g_HasEntWatch;
bool g_HasDynChannels;

ConVar g_cvHudDynamic;

void Integrations_MarkOptional()
{
	MarkNativeAsOptional("ZR_IsClientHuman");
	MarkNativeAsOptional("ZR_IsClientZombie");
	MarkNativeAsOptional("EntWatch_IsSpecialItem");
	MarkNativeAsOptional("EntWatch_HasSpecialItem");
	MarkNativeAsOptional("GetDynamicChannel");
}

void Integrations_PluginStart()
{
	g_cvHudDynamic = CreateConVar("sm_eventmodes_hud_dynamic", "1",
		"Use DynamicChannels for on-screen texts when it's loaded (shares channels with other plugins)", _, true, 0.0, true, 1.0);
	Integrations_Refresh();
}

void Integrations_Refresh()
{
	g_HasZR = LibraryExists("zombiereloaded") && GetFeatureStatus(FeatureType_Native, "ZR_IsClientHuman") == FeatureStatus_Available;
	g_HasEntWatch = LibraryExists("EntWatch") && GetFeatureStatus(FeatureType_Native, "EntWatch_IsSpecialItem") == FeatureStatus_Available;
	g_HasDynChannels = LibraryExists("DynamicChannels") && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;
}

public void OnAllPluginsLoaded()
{
	Integrations_Refresh();
	LogMessage("Links: Zombie Reloaded %s, EntWatch %s, DynamicChannels %s",
		g_HasZR ? "yes" : "no", g_HasEntWatch ? "yes" : "no", g_HasDynChannels ? "yes" : "no");
}

public void OnLibraryAdded(const char[] name)
{
	Integrations_Refresh();
}

public void OnLibraryRemoved(const char[] name)
{
	Integrations_Refresh();
}

// Zombie Reloaded calls this right after anyone is infected.
public void ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
	EM_OnInfected(client, motherInfect);
}

// ---------------------------------------------------------------- shared checks

// A special map item (EntWatch knows best; otherwise any weapon with a name on the map).
bool EM_IsMapItem(int weapon)
{
	if (g_HasEntWatch && EntWatch_IsSpecialItem(weapon))
		return true;
	char name[64];
	GetEntPropString(weapon, Prop_Data, "m_iName", name, sizeof(name));
	return name[0] != '\0';
}

// Carrying a special map item right now (only known with EntWatch).
bool EM_HasMapItem(int client)
{
	return g_HasEntWatch && EntWatch_HasSpecialItem(client);
}

// ---------------------------------------------------------------- on-screen texts

#define EM_MAX_HUDS 32
Handle g_EmHuds[EM_MAX_HUDS];
int g_EmHudCount;

// A text "slot" for one mode. Without DynamicChannels it's a normal HUD synchronizer.
Handle EM_HudSync()
{
	Handle sync = CreateHudSynchronizer();
	if (g_EmHudCount < EM_MAX_HUDS)
		g_EmHuds[g_EmHudCount++] = sync;
	return sync;
}

// Shows a text on the client's screen (after SetHudTextParams). With DynamicChannels each mode's text
// gets a channel that other plugins won't overwrite; otherwise the synchronizer picks one.
void EM_ShowHud(int client, Handle sync, const char[] fmt, any ...)
{
	char text[256];
	SetGlobalTransTarget(client);
	VFormat(text, sizeof(text), fmt, 4);
	if (g_HasDynChannels && g_cvHudDynamic.BoolValue)
	{
		int slot = 0;
		for (int i = 0; i < g_EmHudCount; i++)
			if (g_EmHuds[i] == sync)
				slot = i;
		int channel = GetDynamicChannel(slot % 5);
		if (channel >= 0)
		{
			ShowHudText(client, channel, "%s", text);
			return;
		}
	}
	ShowSyncHudText(client, sync, "%s", text);
}

// Ghost Zombies module of eventmodes.sp.
// modes.sp calls GZ_Check (every 0.2 s), GZ_RoundEnd and GZ_Stop.
//
// Zombies become see-through, flicker in and out of sight, or both. Their weapons (the knife) follow.
// Turning it off (or the round ending) makes them fully visible again.

#if defined _em_ghost_included
 #endinput
#endif
#define _em_ghost_included

#define GZ_TAG "\x07" ... "A0A0A0[Ghost Zombies]\x01 "   // kept apart: \x would eat the hex digits

enum { GZ_SEETHROUGH = 0, GZ_FLICKER, GZ_BOTH, GZ_STYLES }
char g_GzStyleNames[][] = { "see-through", "flickering", "see-through + flickering" };
int g_GzAlphaSteps[] = { 15, 40, 70, 100, 150 };
char g_GzFlickerNames[][] = { "slow", "normal", "fast" };
int g_GzFlickerChance[] = { 4, 10, 20 };   // % chance per 0.2 s to flip visible/hidden

bool g_GzOn;
int g_GzStyle = GZ_SEETHROUGH;
int g_GzAlpha = 70;         // 0 = invisible, 255 = solid
int g_GzFlicker = 1;
bool g_GzHidden[MAXPLAYERS + 1];
bool g_GzTouched[MAXPLAYERS + 1];   // we changed how they're drawn

bool GZ_IsOn()
{
	return g_GzOn;
}

void GZ_SetAlpha(int entity, int alpha)
{
	int r, g, b, a;
	GetEntityRenderColor(entity, r, g, b, a);
	if (alpha >= 255)
		SetEntityRenderMode(entity, RENDER_NORMAL);
	else
		SetEntityRenderMode(entity, RENDER_TRANSALPHA);
	if (a != alpha)
		SetEntityRenderColor(entity, r, g, b, alpha);
}

void GZ_Apply(int client, int alpha)
{
	GZ_SetAlpha(client, alpha);
	for (int slot = 0; slot <= 4; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (weapon != -1)
			GZ_SetAlpha(weapon, alpha);
	}
	g_GzTouched[client] = alpha < 255;
}

void GZ_Restore(int client)
{
	if (g_GzTouched[client] && IsClientInGame(client))
		GZ_Apply(client, 255);
	g_GzTouched[client] = false;
	g_GzHidden[client] = false;
}

void GZ_RestoreAll()
{
	for (int i = 1; i <= MaxClients; i++)
		GZ_Restore(i);
}

void GZ_Stop()
{
	g_GzOn = false;
	GZ_RestoreAll();
}

void GZ_RoundEnd()
{
	GZ_RestoreAll();
}

void GZ_Check()
{
	if (!g_GzOn || !g_RoundLive)
		return;
	bool seeThrough = g_GzStyle != GZ_FLICKER;
	bool flicker = g_GzStyle != GZ_SEETHROUGH;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		if (!IsPlayerAlive(i) || GetClientTeam(i) != CS_TEAM_T)
		{
			GZ_Restore(i);   // died or was cured: back to normal
			continue;
		}
		if (flicker && GetRandomInt(1, 100) <= g_GzFlickerChance[g_GzFlicker])
			g_GzHidden[i] = !g_GzHidden[i];
		int alpha = seeThrough ? g_GzAlpha : 255;
		if (flicker && g_GzHidden[i])
			alpha = 0;
		GZ_Apply(i, alpha);
	}
}

// ---------------------------------------------------------------- menu

void GZMenu(int client)
{
	Menu menu = new Menu(GZHandler);
	char line[64];
	menu.SetTitle(g_GzOn ? "Ghost Zombies - ON\n " : "Ghost Zombies - OFF\n ");
	menu.AddItem("toggle", g_GzOn ? "Turn Ghost Zombies OFF" : "Turn Ghost Zombies ON");
	Format(line, sizeof(line), "Look: %s", g_GzStyleNames[g_GzStyle]);
	menu.AddItem("style", line);
	Format(line, sizeof(line), "See-through amount: %d%% visible", g_GzAlpha * 100 / 255);
	menu.AddItem("alpha", line, g_GzStyle == GZ_FLICKER ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	Format(line, sizeof(line), "Flicker speed: %s", g_GzFlickerNames[g_GzFlicker]);
	menu.AddItem("flicker", line, g_GzStyle == GZ_SEETHROUGH ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int GZHandler(Menu menu, MenuAction action, int client, int item)
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
			if (g_GzOn)
				GZ_Stop();
			else
				g_GzOn = true;
			PrintToChatAll(GZ_TAG ... "%N turned Ghost Zombies %s.", client, g_GzOn ? "ON - watch your back" : "OFF");
			LogAction(client, -1, "\"%L\" turned ghost zombies %s", client, g_GzOn ? "on" : "off");
		}
		else if (StrEqual(info, "style"))
		{
			g_GzStyle = (g_GzStyle + 1) % GZ_STYLES;
			for (int i = 1; i <= MaxClients; i++)
				g_GzHidden[i] = false;
		}
		else if (StrEqual(info, "alpha"))
			g_GzAlpha = NextInt(g_GzAlphaSteps, sizeof(g_GzAlphaSteps), g_GzAlpha);
		else if (StrEqual(info, "flicker"))
			g_GzFlicker = (g_GzFlicker + 1) % sizeof(g_GzFlickerNames);
		GZMenu(client);
	}
	return 0;
}

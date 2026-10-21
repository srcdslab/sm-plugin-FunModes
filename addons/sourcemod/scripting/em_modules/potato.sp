// Hot Potato module of eventmodes.sp.
// eventmodes.sp calls Potato_PluginStart / Potato_MapStart / Potato_ClientPutInServer / Potato_RunCmd;
// modes.sp calls Potato_Check (every 0.2 s), Potato_Tick (every second), Potato_RoundStart / Potato_Stop.
//
// Once the zombies are out, a random human holds the hot potato with a countdown. They pass it by
// knifing another human or pressing E next to one. Whoever holds it at zero explodes, hurting humans
// close by, and a new potato appears a few seconds later. If the holder dies or is infected first,
// the potato jumps to a random human (with at least 10 seconds left).

#if defined _em_potato_included
 #endinput
#endif
#define _em_potato_included

#define PT_TAG           "\x07" ... "FF4040[Hot Potato]\x01 "   // kept apart: \x would eat the hex digits
#define PT_BOOM_SOUND    "weapons/hegrenade/explode3.wav"
#define PT_BLAST_RADIUS  300.0
#define PT_PASS_RANGE    100.0

int g_PtTimes[] = { 15, 20, 30, 45, 60 };
int g_PtBlasts[] = { 0, 25, 50, 100 };
int g_PtColor[4] = { 255, 60, 60, 255 };

bool g_PtOn;
int g_PtTime = 30;          // seconds per potato
int g_PtBlast = 50;         // damage to humans near the explosion
int g_PtHolder;             // userid, 0 = nobody
int g_PtLeft;               // seconds left
float g_PtNextAt;           // after an explosion: when the next potato appears
float g_PtPassReady;        // the holder can't pass it on before this (no instant ping-pong)
int g_PtPrev;               // userid of the last holder ...
float g_PtNoBackUntil;      // ... who can't get it straight back before this
int g_PtLastButtons[MAXPLAYERS + 1];
int g_PtExplosion = -1;
Handle g_HudPotato;

// ---------------------------------------------------------------- lifecycle

void Potato_PluginStart()
{
	g_HudPotato = EM_HudSync();
	for (int i = 1; i <= MaxClients; i++)   // late load
		if (IsClientInGame(i))
			Potato_ClientPutInServer(i);
}

void Potato_MapStart()
{
	PrecacheSound(PT_BOOM_SOUND, true);
	g_PtExplosion = PrecacheModel("sprites/zerogxplode.spr");
}

void Potato_ClientPutInServer(int client)
{
	g_PtLastButtons[client] = 0;
	SDKHook(client, SDKHook_TraceAttack, Potato_TraceAttack);
}

void Potato_Stop()
{
	Potato_Drop();
	g_PtOn = false;
}

void Potato_RoundStart()
{
	Potato_Drop();
	g_PtNextAt = 0.0;
	if (g_PtOn)
		PrintToChatAll(PT_TAG ... "Hot Potato is on: once the zombies come, don't be the one holding it!");
}

// Nobody holds it any more (the holder's red colour goes too).
void Potato_Drop()
{
	int h = GetClientOfUserId(g_PtHolder);
	if (h != 0 && IsClientInGame(h))
		SetEntityRenderColor(h, 255, 255, 255, 255);
	g_PtHolder = 0;
}

// ---------------------------------------------------------------- passing

bool IsPotatoHolder(int client)
{
	return g_PtHolder != 0 && GetClientUserId(client) == g_PtHolder;
}

void GivePotato(int client, int from)
{
	if (client == 0)
		return;
	Potato_Drop();
	g_PtHolder = GetClientUserId(client);
	g_PtPassReady = GetGameTime() + 1.0;
	g_PtPrev = from != 0 ? GetClientUserId(from) : 0;
	g_PtNoBackUntil = GetGameTime() + 3.0;
	SetEntityRenderColor(client, 255, 80, 80, 255);

	if (from != 0)
		PrintToChatAll(PT_TAG ... "%N passed the hot potato to \x07" ... "FF4040%N\x01! (%d s left)", from, client, g_PtLeft);
	else
		PrintToChatAll(PT_TAG ... "\x07" ... "FF4040%N\x01 has the hot potato! %d seconds - knife another human or press E next to one to pass it.",
			client, g_PtLeft);
	PrintCenterText(client, "YOU HAVE THE HOT POTATO! PASS IT ON!");
}

void TryPass(int holder, int target)
{
	if (!g_PtOn || !g_RoundLive || !IsPotatoHolder(holder) || target == holder || !IsHuman(target))
		return;
	float now = GetGameTime();
	if (now < g_PtPassReady)
		return;
	if (g_PtPrev != 0 && GetClientUserId(target) == g_PtPrev && now < g_PtNoBackUntil)
	{
		PrintCenterText(holder, "No pass-backs! Find someone else.");
		return;
	}
	GivePotato(target, holder);
}

// Knife hits between teammates still reach TraceAttack with friendly fire off.
public Action Potato_TraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype,
	int &ammotype, int hitbox, int hitgroup)
{
	if (g_PtOn && attacker >= 1 && attacker <= MaxClients && IsPotatoHolder(attacker) && IsHuman(victim))
	{
		char weapon[32];
		GetClientWeapon(attacker, weapon, sizeof(weapon));
		if (StrEqual(weapon, "weapon_knife"))
			TryPass(attacker, victim);
	}
	return Plugin_Continue;
}

// E next to a human passes it too. Called from eventmodes.sp's OnPlayerRunCmd.
void Potato_RunCmd(int client, int buttons)
{
	bool pressed = (buttons & IN_USE) && !(g_PtLastButtons[client] & IN_USE);
	g_PtLastButtons[client] = buttons;
	if (!pressed || !g_PtOn || !IsPotatoHolder(client))
		return;

	float me[3], pos[3];
	GetClientAbsOrigin(client, me);
	int best = 0;
	float bestDist = PT_PASS_RANGE;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsHuman(i))
			continue;
		GetClientAbsOrigin(i, pos);
		float d = GetVectorDistance(me, pos);
		if (d <= bestDist)
		{
			best = i;
			bestDist = d;
		}
	}
	if (best != 0)
		TryPass(client, best);
}

// ---------------------------------------------------------------- timing

void Potato_Check(bool zombiesNow)
{
	if (!g_PtOn || !g_RoundLive)
		return;

	if (g_PtHolder != 0)
	{
		int h = GetClientOfUserId(g_PtHolder);
		if (h != 0 && IsHuman(h))
			return;
		// The holder died, got infected or left before the countdown ran out: it jumps on.
		if (h != 0)
			PrintToChatAll(PT_TAG ... "%N dropped the hot potato!", h);
		Potato_Drop();
		if (zombiesNow)
		{
			if (g_PtLeft < 10)
				g_PtLeft = 10;
			GivePotato(RandomHuman(h), 0);
		}
		return;
	}

	// A new potato once the zombies are out (and a few seconds after an explosion).
	if (zombiesNow && GetGameTime() >= g_PtNextAt)
	{
		int pick = RandomHuman(0);
		if (pick != 0)
		{
			g_PtLeft = g_PtTime;
			GivePotato(pick, 0);
		}
	}
}

void Potato_Explode(int h)
{
	float pos[3], other[3];
	GetClientAbsOrigin(h, pos);
	Potato_Drop();
	g_PtNextAt = GetGameTime() + 3.0;

	if (g_PtExplosion != -1)
	{
		TE_SetupExplosion(pos, g_PtExplosion, 5.0, 1, 0, RoundToNearest(PT_BLAST_RADIUS), 300);
		TE_SendToAll();
	}
	EmitAmbientSound(PT_BOOM_SOUND, pos, h, SNDLEVEL_RAIDSIREN);
	PrintToChatAll(PT_TAG ... "BOOM! \x07" ... "FF4040%N\x01 was still holding the hot potato!", h);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == h || g_PtBlast <= 0 || !IsHuman(i))
			continue;
		GetClientAbsOrigin(i, other);
		if (GetVectorDistance(pos, other) > PT_BLAST_RADIUS)
			continue;
		int hp = GetClientHealth(i) - g_PtBlast;
		if (hp <= 0)
			ForcePlayerSuicide(i);
		else
			SetEntityHealth(i, hp);
	}
	ForcePlayerSuicide(h);
}

void Potato_Tick()
{
	if (!g_PtOn)
		return;
	int h = GetClientOfUserId(g_PtHolder);
	if (h == 0 || !IsHuman(h))
		return;

	g_PtLeft--;
	Ring(h, g_PtColor, 60.0);
	if (g_PtLeft <= 5)
	{
		float pos[3];
		GetClientAbsOrigin(h, pos);
		EmitAmbientSound(BEACON_SOUND, pos, h, SNDLEVEL_NORMAL, _, _, 150);   // higher, more urgent beep
	}
	if (g_PtLeft <= 0)
	{
		Potato_Explode(h);
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		SetHudTextParams(-1.0, 0.18, 1.1, 255, 60, 60, 255, 0, 0.0, 0.0, 0.0);
		if (i == h)
			EM_ShowHud(i, g_HudPotato, "YOU HAVE THE HOT POTATO! %d s - knife a human or press E next to one", g_PtLeft);
		else
			EM_ShowHud(i, g_HudPotato, "Hot potato: %N - %d s", h, g_PtLeft);
	}
}

// ---------------------------------------------------------------- menu

void PotatoMenu(int client)
{
	Menu menu = new Menu(PotatoHandler);
	char title[128], line[64];
	int h = GetClientOfUserId(g_PtHolder);
	if (!g_PtOn)
		strcopy(title, sizeof(title), "Hot Potato - OFF\n ");
	else if (h == 0)
		strcopy(title, sizeof(title), "Hot Potato - ON\nHolder: chosen when the zombies come\n ");
	else
		Format(title, sizeof(title), "Hot Potato - ON\nHolder: %N (%d s)\n ", h, g_PtLeft);
	menu.SetTitle(title);

	menu.AddItem("toggle", g_PtOn ? "Turn Hot Potato OFF" : "Turn Hot Potato ON");
	menu.AddItem("give", "Give a new potato to a random human", (g_PtOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Countdown: %d s", g_PtTime);
	menu.AddItem("time", line);
	Format(line, sizeof(line), "Blast damage nearby: %d", g_PtBlast);
	menu.AddItem("blast", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int PotatoHandler(Menu menu, MenuAction action, int client, int item)
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
			if (g_PtOn)
				Potato_Stop();
			else
			{
				g_PtOn = true;
				g_PtNextAt = 0.0;
			}
			PrintToChatAll(PT_TAG ... "%N turned Hot Potato %s.", client, g_PtOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned hot potato %s", client, g_PtOn ? "on" : "off");
		}
		else if (StrEqual(info, "give"))
		{
			int pick = RandomHuman(GetClientOfUserId(g_PtHolder));
			if (pick == 0)
				PrintToChat(client, PT_TAG ... "No living human to give it to.");
			else
			{
				g_PtLeft = g_PtTime;
				GivePotato(pick, 0);
			}
		}
		else if (StrEqual(info, "time"))
			g_PtTime = NextInt(g_PtTimes, sizeof(g_PtTimes), g_PtTime);
		else if (StrEqual(info, "blast"))
			g_PtBlast = NextInt(g_PtBlasts, sizeof(g_PtBlasts), g_PtBlast);
		PotatoMenu(client);
	}
	return 0;
}

bool Potato_IsOn()
{
	return g_PtOn;
}

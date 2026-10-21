// Hero module of eventmodes.sp.
// eventmodes.sp calls Hero_PluginStart; modes.sp calls Hero_Check (every 0.2 s), Hero_Tick (every
// second), Hero_RoundStart, Hero_RoundEnd and Hero_Stop; physics.sp asks Hero_SpeedMult.
//
// Once the zombies are out (or a bit later), one random human becomes the hero: big health, extra
// speed, a blue glow and ring, and their name on everyone's screen. If the hero falls: nothing, every
// human loses health, or all humans are slain - depending on the setting.

#if defined _em_hero_included
 #endinput
#endif
#define _em_hero_included

#define HR_TAG "\x07" ... "4080FF[Hero]\x01 "   // kept apart: \x would eat the hex digits

enum { HR_F_NONE = 0, HR_F_HURT, HR_F_SLAY, HR_FALLS }
char g_HrFallNames[][] = { "nothing happens", "every human loses 25 HP", "all humans are slain" };
int g_HrHealthSteps[] = { 150, 200, 300, 500, 1000 };
float g_HrSpeedSteps[] = { 1.0, 1.1, 1.2, 1.3, 1.5 };
int g_HrDelaySteps[] = { 0, 10, 30, 60 };
int g_HrColor[4] = { 64, 128, 255, 255 };

bool g_HrOn;
int g_HrHealth = 300;
float g_HrSpeed = 1.2;
int g_HrDelay = 0;          // seconds after the first zombie
int g_HrFall = HR_F_HURT;

int g_Hero;                 // userid, 0 = none
bool g_HeroDone;            // this round's hero has been picked
float g_HeroAt;
Handle g_HudHero;

void Hero_PluginStart()
{
	g_HudHero = EM_HudSync();
}

bool Hero_IsOn()
{
	return g_HrOn;
}

float Hero_SpeedMult(int client)
{
	if (!g_HrOn || g_Hero == 0 || GetClientUserId(client) != g_Hero || GetClientTeam(client) != CS_TEAM_CT)
		return 1.0;
	return g_HrSpeed;
}

void Hero_Release()
{
	int h = GetClientOfUserId(g_Hero);
	if (h != 0 && IsClientInGame(h))
	{
		int r, g, b, a;
		GetEntityRenderColor(h, r, g, b, a);
		SetEntityRenderColor(h, 255, 255, 255, a);
	}
	g_Hero = 0;
}

void Hero_Stop()
{
	Hero_Release();
	g_HrOn = false;
	g_HeroDone = false;
	g_HeroAt = 0.0;
}

void Hero_RoundStart()
{
	g_Hero = 0;
	g_HeroDone = false;
	g_HeroAt = 0.0;
	if (g_HrOn)
		PrintToChatAll(HR_TAG ... "Hero mode is on: a hero rises when the zombies come - protect them!");
}

void Hero_RoundEnd()
{
	Hero_Release();
}

void Hero_Make(int client)
{
	if (client == 0)
		return;
	Hero_Release();
	g_Hero = GetClientUserId(client);
	g_HeroDone = true;
	if (GetClientHealth(client) < g_HrHealth)
		SetEntityHealth(client, g_HrHealth);
	int r, g, b, a;
	GetEntityRenderColor(client, r, g, b, a);
	SetEntityRenderColor(client, 100, 160, 255, a);
	PrintToChatAll(HR_TAG ... "\x07" ... "4080FF%N\x01 is the HERO! (%d HP, faster)%s", client, g_HrHealth,
		g_HrFall == HR_F_SLAY ? " If the hero falls, every human falls!" : (g_HrFall == HR_F_HURT ? " Keep them alive!" : ""));
	PrintCenterTextAll("%N IS THE HERO!", client);
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 170);
}

void Hero_Fallen(int h)
{
	g_Hero = 0;
	if (g_HrFall == HR_F_SLAY)
	{
		PrintToChatAll(HR_TAG ... "The hero %N has fallen! All humans are slain.", h);
		PrintCenterTextAll("THE HERO HAS FALLEN!");
		SlayHumans();
		return;
	}
	PrintToChatAll(HR_TAG ... "The hero %N has fallen!%s", h, g_HrFall == HR_F_HURT ? " Every human loses 25 HP." : "");
	if (g_HrFall == HR_F_HURT)
		for (int i = 1; i <= MaxClients; i++)
			if (IsHuman(i))
				HurtPlayer(i, 25);
}

void Hero_Check(bool zombiesNow)
{
	if (!g_HrOn || !g_RoundLive)
		return;
	if (g_Hero != 0)
	{
		int h = GetClientOfUserId(g_Hero);
		if (h == 0)
		{
			g_Hero = 0;
			PrintToChatAll(HR_TAG ... "The hero left the server.");
		}
		else if (!IsHuman(h))
		{
			int r, g, b, a;
			GetEntityRenderColor(h, r, g, b, a);
			SetEntityRenderColor(h, 255, 255, 255, a);
			Hero_Fallen(h);
		}
		return;
	}
	if (g_HeroDone || !zombiesNow)
		return;
	float now = GetGameTime();
	if (g_HeroAt == 0.0)
		g_HeroAt = now + float(g_HrDelay);
	if (now >= g_HeroAt)
		Hero_Make(RandomHuman(0));
}

void Hero_Tick()
{
	if (!g_HrOn || g_Hero == 0)
		return;
	int h = GetClientOfUserId(g_Hero);
	if (h == 0 || !IsHuman(h))
		return;
	Ring(h, g_HrColor, 50.0);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		SetHudTextParams(-1.0, 0.26, 1.1, 100, 160, 255, 255, 0, 0.0, 0.0, 0.0);
		if (i == h)
			EM_ShowHud(i, g_HudHero, "YOU ARE THE HERO! (%d HP)", GetClientHealth(h));
		else
			EM_ShowHud(i, g_HudHero, "HERO: %N (%d HP)", h, GetClientHealth(h));
	}
}

// ---------------------------------------------------------------- menu

void HeroMenu(int client)
{
	Menu menu = new Menu(HeroHandler);
	char title[128], line[64];
	int h = GetClientOfUserId(g_Hero);
	if (!g_HrOn)
		strcopy(title, sizeof(title), "Hero - OFF\n ");
	else if (h != 0)
		Format(title, sizeof(title), "Hero - ON\nHero: %N\n ", h);
	else
		strcopy(title, sizeof(title), "Hero - ON\nA hero rises when the zombies come\n ");
	menu.SetTitle(title);
	menu.AddItem("toggle", g_HrOn ? "Turn Hero OFF" : "Turn Hero ON");
	menu.AddItem("now", "Make a random human the hero now", (g_HrOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Hero health: %d", g_HrHealth);
	menu.AddItem("health", line);
	Format(line, sizeof(line), "Hero speed: x%.1f", g_HrSpeed);
	menu.AddItem("speed", line);
	if (g_HrDelay == 0)
		strcopy(line, sizeof(line), "Appears: with the first zombie");
	else
		Format(line, sizeof(line), "Appears: %d s after the first zombie", g_HrDelay);
	menu.AddItem("delay", line);
	Format(line, sizeof(line), "If the hero falls: %s", g_HrFallNames[g_HrFall]);
	menu.AddItem("fall", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int HeroHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_HrOn;
			Hero_Stop();
			g_HrOn = on;
			PrintToChatAll(HR_TAG ... "%N turned Hero mode %s.", client, on ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned hero mode %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
		{
			int pick = RandomHuman(GetClientOfUserId(g_Hero));
			if (pick == 0)
				PrintToChat(client, HR_TAG ... "No living human to pick.");
			else
				Hero_Make(pick);
		}
		else if (StrEqual(info, "health"))
			g_HrHealth = NextInt(g_HrHealthSteps, sizeof(g_HrHealthSteps), g_HrHealth);
		else if (StrEqual(info, "speed"))
			g_HrSpeed = NextStep(g_HrSpeedSteps, sizeof(g_HrSpeedSteps), g_HrSpeed);
		else if (StrEqual(info, "delay"))
			g_HrDelay = NextInt(g_HrDelaySteps, sizeof(g_HrDelaySteps), g_HrDelay);
		else if (StrEqual(info, "fall"))
			g_HrFall = (g_HrFall + 1) % HR_FALLS;
		HeroMenu(client);
	}
	return 0;
}

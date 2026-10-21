// Hallucinations module of eventmodes.sp.
// eventmodes.sp calls HL_MapStart; modes.sp calls HL_Tick (every second), HL_RoundStart and HL_Stop.
//
// Once the zombies are out, every N seconds a few random humans start seeing things: a zombie growl
// right behind them that nobody else hears, a coloured flash, a fake warning, or a fake danger ring
// around their feet. Nothing actually happens - it's all in their head.

#if defined _em_halluc_included
 #endinput
#endif
#define _em_halluc_included

#define HL_TAG "\x07" ... "C080FF[Hallucinations]\x01 "   // kept apart: \x would eat the hex digits

char g_HlSounds[][] =
{
	"npc/zombie/zombie_alert1.wav", "npc/zombie/zombie_alert2.wav", "npc/zombie/zombie_voice_idle1.wav",
	"npc/fast_zombie/fz_scream1.wav", "npc/zombie/zombie_pain1.wav"
};
char g_HlLies[][] =
{
	"A ZOMBIE IS RIGHT BEHIND YOU!", "LOOK OUT!", "Did you hear that?", "RUN!", "Something is watching you...",
	"YOU ARE THE LAST HUMAN", "Your ammo is empty!"
};
int g_HlEverySteps[] = { 10, 15, 20, 30, 45, 60 };
int g_HlCountSteps[] = { 1, 2, 3, 5, 64 };   // 64 = everyone
int g_HlFake[4] = { 255, 30, 30, 255 };

bool g_HlOn;
int g_HlEvery = 20;
int g_HlCount = 2;
bool g_HlSoundsOn = true;
bool g_HlVisualsOn = true;
float g_HlNext;

void HL_MapStart()
{
	for (int i = 0; i < sizeof(g_HlSounds); i++)
		PrecacheSound(g_HlSounds[i], true);
}

bool HL_IsOn()
{
	return g_HlOn;
}

void HL_Stop()
{
	g_HlOn = false;
	g_HlNext = 0.0;
}

void HL_Set(bool on)
{
	HL_Stop();
	g_HlOn = on;
}

void HL_RoundStart()
{
	g_HlNext = 0.0;
	if (g_HlOn)
		PrintToChatAll(HL_TAG ... "Hallucinations are on: don't trust everything you see and hear...");
}

void HL_Trick(int client)
{
	int kind = GetRandomInt(0, 3);
	if (!g_HlSoundsOn && kind == 0)
		kind = 1;
	if (!g_HlVisualsOn && kind != 0)
		kind = g_HlSoundsOn ? 0 : -1;
	switch (kind)
	{
		case 0:
		{
			// A growl from just behind them, only they hear it.
			float pos[3], ang[3], back[3];
			GetClientAbsOrigin(client, pos);
			GetClientEyeAngles(client, ang);
			GetAngleVectors(ang, back, NULL_VECTOR, NULL_VECTOR);
			pos[0] -= back[0] * 80.0;
			pos[1] -= back[1] * 80.0;
			pos[2] += 40.0;
			EmitSoundToClient(client, g_HlSounds[GetRandomInt(0, sizeof(g_HlSounds) - 1)], SOUND_FROM_WORLD, SNDCHAN_AUTO,
				SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, pos);
		}
		case 1:
			ScreenTint(client, GetRandomInt(0, 255), GetRandomInt(0, 80), GetRandomInt(0, 255), 110, 0.2, 1.0);
		case 2:
			PrintCenterText(client, g_HlLies[GetRandomInt(0, sizeof(g_HlLies) - 1)]);
		case 3:
		{
			// A fake danger ring that only they see.
			if (g_BeamSprite != -1)
			{
				float pos[3];
				GetClientAbsOrigin(client, pos);
				pos[2] += 8.0;
				TE_SetupBeamRingPoint(pos, 300.0, 20.0, g_BeamSprite, g_HaloSprite, 0, 15, 1.5, 8.0, 0.0, g_HlFake, 10, 0);
				TE_SendToClient(client);
			}
		}
	}
}

void HL_Wave()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);
	int count = g_HlCount < n ? g_HlCount : n;
	for (int k = 0; k < count; k++)
		if (!IsFakeClient(list[k]))
			HL_Trick(list[k]);
}

void HL_Tick()
{
	if (HazardDue(g_HlOn, g_HlNext, g_HlEvery))
		HL_Wave();
}

// ---------------------------------------------------------------- menu

void HLMenu(int client)
{
	Menu menu = new Menu(HLHandler);
	char line[64];
	menu.SetTitle(g_HlOn ? "Hallucinations - ON\nStarts when the zombies come\n " : "Hallucinations - OFF\n ");
	menu.AddItem("toggle", g_HlOn ? "Turn Hallucinations OFF" : "Turn Hallucinations ON");
	menu.AddItem("now", "Make them see things now", (g_HlOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_HlEvery);
	menu.AddItem("every", line);
	if (g_HlCount >= 64)
		strcopy(line, sizeof(line), "Humans affected: everyone");
	else
		Format(line, sizeof(line), "Humans affected: %d", g_HlCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "Fake zombie sounds: %s", g_HlSoundsOn ? "ON" : "OFF");
	menu.AddItem("sounds", line);
	Format(line, sizeof(line), "Fake flashes, warnings and rings: %s", g_HlVisualsOn ? "ON" : "OFF");
	menu.AddItem("visuals", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int HLHandler(Menu menu, MenuAction action, int client, int item)
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
			HL_Set(!g_HlOn);
			PrintToChatAll(HL_TAG ... "%N turned Hallucinations %s.", client, g_HlOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned hallucinations %s", client, g_HlOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			HL_Wave();
		else if (StrEqual(info, "every"))
			g_HlEvery = NextInt(g_HlEverySteps, sizeof(g_HlEverySteps), g_HlEvery);
		else if (StrEqual(info, "count"))
			g_HlCount = NextInt(g_HlCountSteps, sizeof(g_HlCountSteps), g_HlCount);
		else if (StrEqual(info, "sounds"))
			g_HlSoundsOn = !g_HlSoundsOn;
		else if (StrEqual(info, "visuals"))
			g_HlVisualsOn = !g_HlVisualsOn;
		HLMenu(client);
	}
	return 0;
}

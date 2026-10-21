// Shared by the fog and event-mode modules.

#if defined _em_common_included
 #endinput
#endif
#define _em_common_included

#define ACCESS_CMD     "sm_eventload"   // whoever can use this command can use the fog and event modes
#define ACCESS_DEFAULT ADMFLAG_ROOT     // only used if sm_eventload doesn't exist and has no override

// Used by more than one module, so it has to exist before any of them ("\x07" kept apart: \x eats hex digits).
#define GG_TAG "\x07" ... "C080FF[Gun Game]\x01 "
#define SETTINGS_FILE "configs/eventmodes/settings.cfg"   // saved menu settings (settings.sp)

bool HasAccess(int client)
{
	return client == 0 || CheckCommandAccess(client, ACCESS_CMD, ACCESS_DEFAULT);
}

void StringToLower(char[] s)
{
	for (int i = 0; s[i] != '\0'; i++)
		s[i] = CharToLower(s[i]);
}

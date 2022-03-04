#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>

#pragma semicolon 1
#pragma newdecls required

#define TIMER_DELAY 15

#define MAX_VOTE_MESSAGE_LENGTH 128
#define MAX_ENTITY_NAME_LENGTH 64

#define TEAM_SPEC 1
#define TEAM_SURV 2

#define WEAPON_NAME 1
#define WEAPON_CMD 2


static const char  sWeaponData[][] =
{
	// 							+WEAPON_NAME	+WEAPON_CMD
	"weapon_pistol_magnum", 	"Magnum", 		"sm_magnum",		// Deagle
	"weapon_sniper_scout", 		"Scout", 		"sm_scout"			// Scout
};

int g_iVotingItem = 0;

Menu g_hMenu = null;

Handle g_hVote = null;

bool g_bReadyUpAvailable = false;

bool g_bRoundIsLive = false;

public Plugin myinfo =
{
  name = "Weapon vote",
	author = "TouchMe",
	description = "Issues weapons based on voting results",
	version = "1.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2) {
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

void InitTranslations() 
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/weapon_vote.phrases.txt");

	if (FileExists(sPath)) {
		LoadTranslations("weapon_vote.phrases");
	}
}

public void OnPluginStart()
{
	InitTranslations();

	RegConsoleCmd("sm_wv", Cmd_ShowMenu);

	HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	InitMenu();
}

// ------------------------------------------------------------------------------------- READYUP
public void OnAllPluginsLoaded()
{
	g_bReadyUpAvailable = LibraryExists("readyup");
}

public void OnLibraryRemoved(const char[] sName)
{
	if (StrEqual(sName, "readyup")) g_bReadyUpAvailable = false;
}

public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, "readyup")) {
		g_bReadyUpAvailable = true;
	}
}

/**
  * Глобальное событие, которое вызывается, когда все игроки готовы.
  *
  * @noreturn
  */
public void OnRoundIsLive()
{
	g_hMenu.Cancel();
}

// ------------------------------------------------------------------------------------- EVENT
public Action Event_LeftStartArea(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = true;
		g_hMenu.Cancel();
	}	
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = false;
	}
}

// ------------------------------------------------------------------------------------- CMD
public Action OnClientSayCommand(int iClient, const char[] sSayCmd, const char[] sArgs)
{
	if(iClient != 0 && !IsFakeClient(iClient))
    {
		char sCmd[32];

		for (int item = 0; item < sizeof(sWeaponData); item += 3)
		{
			strcopy(sCmd, sizeof(sCmd), sWeaponData[item + WEAPON_CMD][3]);

			if ((sArgs[0] == '/' || sArgs[0] == '!') && StrContains(sArgs, sCmd) != -1)
			{
				if (CanClientStartVote(iClient)) {
					ForceVote(iClient, item);
				}
				
				return Plugin_Handled;
			}
		}
    }

	return Plugin_Continue;
}

public Action OnClientCommand(int iClient, int sArgs)
{
	if(iClient != 0 && !IsFakeClient(iClient))
    {
		char sCmd[32];
  		GetCmdArg(0, sCmd, sizeof(sCmd));

		for (int item = 0; item < sizeof(sWeaponData); item += 3)
		{
			if (StrEqual(sCmd, sWeaponData[item + WEAPON_CMD]))
			{
				if (CanClientStartVote(iClient)) {
					ForceVote(iClient, item);
				}
				
				return Plugin_Handled;
			}
		}
    }

	return Plugin_Continue;
}

public Action Cmd_ShowMenu(int iClient, int iArgs)
{
	if (!iClient || !CanClientStartVote(iClient)) {
		return Plugin_Handled;
	}

	ShowMenu(iClient);
	return Plugin_Handled;
}

// ------------------------------------------------------------------------------------- MENU
void InitMenu()
{
	g_hMenu = new Menu(HandleClickMenu);

	char sMenuTitle[64];
	Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MENU_TITLE");

	g_hMenu.SetTitle(sMenuTitle);

	for (int item = 0; item < sizeof(sWeaponData); item += 3)
	{
		g_hMenu.AddItem(sWeaponData[item], sWeaponData[item + WEAPON_NAME]);
	}
	
	g_hMenu.ExitButton = true;
}

public void ShowMenu(int iClient)
{
	if (g_bReadyUpAvailable && IsInReady()) {
		ToggleReadyPanel(false, iClient);
	}

	g_hMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int HandleClickMenu(Menu hMenu, MenuAction iAction, int iClient, int iIndex)
{
	switch (iAction) {
		case MenuAction_Select: {
			// Is a new vote allowed?
			if (!IsNewBuiltinVoteAllowed()) {
				CPrintToChat(iClient, "%t", "IF_COULDOWN", CheckBuiltinVoteDelay());
				return 0;
			}

			ForceVote(iClient, iIndex * 3);
		}
		case MenuAction_Cancel: {
			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(true, iClient);
			}
		}
	}

	return 0;
}

// ------------------------------------------------------------------------------------- VOTE
public void ForceVote(int iClient, int iItem) 
{
	// Set Item
	g_iVotingItem = iItem;

	// Get all non-spectating players
	int iNumPlayers;
	int[] iPlayers = new int[MaxClients];

	for (int i = 1; i <= MaxClients; i++) 
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || (GetClientTeam(i) == TEAM_SPEC)) {
			continue;
		}

		iPlayers[iNumPlayers++] = i;
	}

	char sVoteTitle[MAX_VOTE_MESSAGE_LENGTH];
	Format(sVoteTitle, sizeof(sVoteTitle), "%t", "VOTE_TITLE", iClient, sWeaponData[g_iVotingItem + WEAPON_NAME]);

	InitVote(iClient, sVoteTitle);
	ShowVote(iPlayers, iNumPlayers);

	FakeClientCommand(iClient, "Vote Yes");
}

void InitVote(int iInitiator, const char[] sVoteTitle) 
{
	g_hVote = CreateBuiltinVote(HandleActionVote, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
	SetBuiltinVoteInitiator(g_hVote, iInitiator);
	SetBuiltinVoteArgument(g_hVote, sVoteTitle);
	SetBuiltinVoteResultCallback(g_hVote, HandleVoteResult);
}

void ShowVote(int[] iPlayers, int iNumPlayers)
{
	DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, TIMER_DELAY);
}

/**
 * Вызывается, когда завершилось действие в голосовании
 *
 * @param hVote 			Идентификатор, по которому проводится голосование.
 * @param iAction			Действие.
 * @param iParam1			Первый параметр (client).
 * @param iParam2			Второй параметр (item).
 *
 * @noreturn
 */
public void HandleActionVote(Handle hVote, BuiltinVoteAction iAction, int iParam1, int iParam2)
{
	switch (iAction) {
		case BuiltinVoteAction_End: {
			delete hVote;
			g_hVote = null;
		}
		case BuiltinVoteAction_Cancel: {
			DisplayBuiltinVoteFail(hVote, view_as<BuiltinVoteFailReason>(iParam1));
		}
	}
}

/**
  * Обратный вызов, когда голосование закончилось и доступны результаты.
  *
  * @param hVote 			Идентификатор, по которому проводится голосование.
  * @param num_votes 		Общее количество подсчитанных голосов.
  * @param num_clients 		Количество клиентов, которые могли голосовать.
  * @param client_info 		Массив клиентов. Используйте определения VOTEINFO_CLIENT_.
  * @param num_items 		Количество выбранных уникальных элементов.
  * @param item_info 		Массив элементов, отсортированных по количеству.
  *
  * @noreturn
  */
public void HandleVoteResult(Handle hVote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (g_bReadyUpAvailable) {
		ToggleReadyPanel(true);
	}

	if (item_info[0][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES  && item_info[0][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) 
	{
			if (g_bReadyUpAvailable && !IsInReady()) {
				DisplayBuiltinVoteFail(hVote, BuiltinVoteFail_Loses);
				return;
			}

			int initiator = GetBuiltinVoteInitiator(hVote);	

			char sVoteMsg[MAX_VOTE_MESSAGE_LENGTH];
			Format(sVoteMsg, sizeof(sVoteMsg), "%t", "VOTE_PASS", initiator, sWeaponData[g_iVotingItem + WEAPON_NAME]);

			char sWeapon[MAX_ENTITY_NAME_LENGTH];
			strcopy(sWeapon, sizeof(sWeapon), sWeaponData[g_iVotingItem]);

			DisplayBuiltinVotePass(hVote, sVoteMsg);
			

			if (!IsClientInGame(initiator) || !IsPlayerAlive(initiator) || GetClientTeam(initiator) != TEAM_SURV) {
				return;
			}

			GiveClientItem(initiator, sWeapon);
			return;
	}

	// Vote Failed
	DisplayBuiltinVoteFail(hVote, BuiltinVoteFail_Loses);
	return;
}

// ------------------------------------------------------------------------------------- OTHER
bool CanClientStartVote(int iClient) 
{
	if (GetClientTeam(iClient) != TEAM_SURV) {
		// SEND MESSAGE
		return false;
	}

	if (g_bReadyUpAvailable) {
		if (!IsInReady()) {
			CPrintToChat(iClient, "%t", "IF_LEFT_READYUP");
			return false;
		}
	} else {
		if (g_bRoundIsLive) {
			CPrintToChat(iClient, "%t", "IF_ROUND_LIVE");
			return false;
		}
	}

	// Is a new vote allowed?
	if (!IsNewBuiltinVoteAllowed()) {
		CPrintToChat(iClient, "%t", "IF_COULDOWN", CheckBuiltinVoteDelay());
		return false;
	}

	return true;
}

void GiveClientItem(int iClient, const char[] sWeaponName) 
{
#if (SOURCEMOD_V_MINOR == 11)
	GivePlayerItem(iClient, sWeaponName); // Fixed only in the latest version of sourcemod 1.11
#else
	int iEntity = CreateEntityByName(sWeaponName);
	if (iEntity == -1) {
		return;
	}

	DispatchSpawn(iEntity);
	EquipPlayerWeapon(iClient, iEntity);
#endif
}

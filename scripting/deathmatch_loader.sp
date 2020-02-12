#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <csgocolors>
#include <clientprefs>
#include <chat-processor>

#pragma newdecls required

#define PLUGIN_VERSION          "1.0.0"
#define PLUGIN_NAME             "[CS:GO] Custom Deathmatch Loader"
#define PLUGIN_AUTHOR           "de_nerd, Maxximou5"
#define PLUGIN_DESCRIPTION      "Loads Deathmatch configuration files in a per-time basis"
#define PLUGIN_URL              "https://github.com/Maxximou5/csgo-deathmatch/"

#define MAX_MODES               64
#define MAX_MESSAGES            1
#define NEXTMODE_DELAY          5.0
#define SKIP_RATIO              0.5
#define EXTEND_RATIO            0.4
#define EXTEND_DURATION         5

public Plugin myinfo =
{
    name                        = PLUGIN_NAME,
    author                      = PLUGIN_AUTHOR,
    description                 = PLUGIN_DESCRIPTION,
    version                     = PLUGIN_VERSION,
    url                         = PLUGIN_URL
}

ConVar g_hEnabled;

Handle g_hModeTimer = null;
Handle g_hMessageTimer = null;
Handle g_hNextModeTimer = null;

SMCParser g_hConfigParser;

char g_sConfigFile[PLATFORM_MAX_PATH + 1];

// CONFIGS
int g_iCurrentMode;
bool g_bCurrentModeExtended;
int g_iLoadedModes;
bool g_bWantsToSkip[MAXPLAYERS + 1];
bool g_bWantsToExtend[MAXPLAYERS + 1];
int g_iModesDuration[MAX_MODES];
char g_sModesFilename[MAX_MODES][PLATFORM_MAX_PATH];
char g_sChatMessages[][] = {
    "Para o tempo restante nesse modo utilize o comando: {darkred}!timer"
};
int g_iLastModeLoad;
int g_iLastMessage;

public void OnPluginStart()
{
    /* Let's not waste our time here... */
    if (GetEngineVersion() != Engine_CSGO)
        SetFailState("ERROR: This plugin is designed only for CS:GO.")

    CreateConVar("dm_m5_loader_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_hEnabled = CreateConVar("dm_loader_enabled", "1", "Enable/disable executing configs");
    
    RegAdminCmd("dm_reload", Command_ReloadDML, ADMFLAG_CONFIG, "Reloads the deathmatch loader config.");
    RegAdminCmd("sm_next", Command_NextMode, ADMFLAG_CONFIG, "Loads next configuration");
    RegAdminCmd("sm_forceextend", Command_ForceExtend, ADMFLAG_CONFIG, "Extends current mode");

    RegConsoleCmd("sm_timer", Command_Timer, "Prints remaining time for current mode");
    RegConsoleCmd("sm_tempo", Command_Timer, "Prints remaining time for current mode");

    RegConsoleCmd("sm_skip", Command_Skip, "Votes to skip current mode");
    RegConsoleCmd("sm_pular", Command_Skip, "Votes to skip current mode");

    RegConsoleCmd("sm_extend", Command_Extend, "Votes to extend current mode");

    BuildPath(Path_SM, g_sConfigFile, sizeof(g_sConfigFile), "configs/deathmatch/config_loader.ini");
    g_hConfigParser = new SMCParser();
    SMC_SetReaders(g_hConfigParser, ReadConfig_NewSection, ReadConfig_KeyValue, ReadConfig_EndSection);
}

int GetCurrentModeTime()
{
    int now = GetTime();

    return (now - g_iLastModeLoad) / 60;
}

int GetCurrentModeDuration()
{
    return g_iModesDuration[g_iCurrentMode];
}

int GetRemainingTime()
{
    int time = GetCurrentModeTime();
    int duration = GetCurrentModeDuration();

    return duration - time;
}

int GetSkipVotes()
{
    int iCount = 0;

    for (int i = 0; i <= MAXPLAYERS; i++) {
        if (g_bWantsToSkip[i]) iCount++;
    }

    return iCount;
}

int GetExtendVotes()
{
    int iCount = 0;

    for (int i = 0; i <= MAXPLAYERS; i++) {
        if (g_bWantsToExtend[i]) iCount++;
    }

    return iCount;
}

int GetSkipVotesNeeded()
{
    float fClients = float(GetClientCount());

    float fNeeded = fClients * SKIP_RATIO;

    return RoundToCeil(fNeeded);
}

int GetExtendVotesNeeded()
{
    float fClients = float(GetClientCount());

    float fNeeded = fClients * EXTEND_RATIO;

    return RoundToCeil(fNeeded);
}

void ResetSkipVotes()
{
    for (int i = 0; i <= MAXPLAYERS; i++) {
        g_bWantsToSkip[i] = false;
    }
}

void ResetExtendVotes()
{
    for (int i = 0; i <= MAXPLAYERS; i++) {
        g_bWantsToExtend[i] = false;
    }   
}

public void OnMapStart()
{
    ResetSkipVotes();
    ResetExtendVotes();
    ParseConfig();
    ExecMode(0);

    g_hModeTimer = null;
    g_hModeTimer = CreateTimer(60.0, Timer_UpdateMode, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
    g_hMessageTimer = null;
    g_hMessageTimer = CreateTimer(45.0, Timer_ChatMessages, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public void OnMapEnd()
{
    g_hModeTimer = null;
    g_hMessageTimer = null;
}

public Action Command_ForceExtend(int client, int args)
{
    ResetExtendVotes();
    ExtendMode(EXTEND_DURATION);
    CPrintToChatAll("[{green}MULTIMOD{default}] Modo atual estendido por %d minutos...", EXTEND_DURATION);
}

public Action Command_Extend(int client, int args)
{
    if (g_bCurrentModeExtended) {
        CPrintToChat(client, "[{green}MULTIMOD{default}] O modo atual já foi estendido!");

        return Plugin_Handled;
    }

    g_bWantsToExtend[client] = !g_bWantsToExtend[client];

    if(g_bWantsToExtend[client]) {
        CPrintToChat(client, "[{green}MULTIMOD{default}] Você votou para {green}ESTENDER %d minutos {default}o modo atual!", EXTEND_DURATION);
    } else {
        CPrintToChat(client, "[{green}MULTIMOD{default}] Você {darkred}REMOVEU {default}o seu voto de estender o modo atual!");
    }

    int iSkips = GetExtendVotes();
    int iNeeded = GetExtendVotesNeeded();

    if(iSkips < iNeeded) {
        CPrintToChatAll("[{green}MULTIMOD{default}] {green}%d/%d {default}votos para estender por %d minutos o modo atual!", iSkips, iNeeded, EXTEND_DURATION);
    } else {
        CPrintToChatAll("[{green}MULTIMOD{default}] Modo atual estendido por %d minutos...", EXTEND_DURATION);
        ResetExtendVotes();
        ExtendMode(EXTEND_DURATION);
    }


    return Plugin_Handled;
}

public Action Command_Skip(int client, int args)
{
    g_bWantsToSkip[client] = !g_bWantsToSkip[client];

    if(g_bWantsToSkip[client]) {
        CPrintToChat(client, "[{green}MULTIMOD{default}] Você votou para {green}PULAR {default}o modo atual!");
    } else {
        CPrintToChat(client, "[{green}MULTIMOD{default}] Você {darkred}REMOVEU {default}o seu voto de pular o modo atual!");
    }

    int iSkips = GetSkipVotes();
    int iNeeded = GetSkipVotesNeeded();

    if(iSkips < iNeeded) {
        CPrintToChatAll("[{green}MULTIMOD{default}] {green}%d/%d {default}votos para pular para o próximo modo!", iSkips, iNeeded);
    } else {
        CPrintToChatAll("[{green}MULTIMOD{default}] Pulando para o próximo modo de jogo em %d segundos...", RoundFloat(NEXTMODE_DELAY));
        ResetSkipVotes();
        QueueNextMode();
    }

    return Plugin_Handled;
}

public Action Command_Timer(int client, int args)
{
    int remaining = GetRemainingTime();

    CPrintToChat(client, "[{green}MULTIMOD{default}] %d minutos restantes...", remaining);

    return Plugin_Handled;
}

public Action Command_ReloadDML(int client, int args)
{
    if (ParseConfig())
        ReplyToCommand(client, "[DML] - Configuration file has been reloaded.");
    else
        ReplyToCommand(client, "[DML] - Configuration file has failed to reload.");
    return Plugin_Handled;
}

public Action Command_NextMode(int client, int args)
{
    PrintCenterTextAll("Carregando novo modo em %d segundos...", RoundFloat(NEXTMODE_DELAY));
    CPrintToChatAll("[{green}MULTIMOD{default}] Carregando novo modo em %d segundos...", RoundFloat(NEXTMODE_DELAY));
    QueueNextMode();
}

void ExtendMode(int minutes)
{
    g_bCurrentModeExtended = true;
    g_iLastModeLoad += minutes * 60;
}

void QueueNextMode()
{
    g_hNextModeTimer = CreateTimer(NEXTMODE_DELAY, Timer_NextMode, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_NextMode(Handle timer)
{
    NextMode();

    return Plugin_Continue;
}

public Action Timer_ChatMessages(Handle timer)
{
    char buffer[512];
    if (++g_iLastMessage >= MAX_MESSAGES)
        g_iLastMessage = 0;

    Format(buffer, 512, "[{green}MULTIMOD{default}] %s", g_sChatMessages[g_iLastMessage]);

    CPrintToChatAll(buffer);

    return Plugin_Continue;
}

public Action Timer_UpdateMode(Handle timer)
{
    if (!g_hEnabled.BoolValue) {
        g_hModeTimer = null;
        return Plugin_Stop;
    }

    int remaining = GetRemainingTime();

    if (remaining == 0) {
        PrintCenterTextAll("Carregando novo modo...", remaining);
        CPrintToChatAll("[{green}MULTIMOD{default}] Carregando novo modo...", remaining);
    } else if(remaining < 3 || remaining % 5 == 0) {
        PrintCenterTextAll("%d minutos restantes...", remaining);
        CPrintToChatAll("[{green}MULTIMOD{default}] %d minutes restantes...", remaining);
    }

    if (remaining <= 0){
        //PrintToChatAll("Loading next game mode...");
        NextMode();
    }

    return Plugin_Continue;
}

public SMCResult ReadConfig_EndSection(Handle smc) {}

public SMCResult ReadConfig_KeyValue(Handle smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
    if (!key[0]){
        return SMCParse_Continue;
    }

    if (g_iLoadedModes >= MAX_MODES - 1) {
        LogError("Failed to continue loading modes. Reached maximum of %d", MAX_MODES);

        return SMCParse_Continue;
    }

    int duration = StringToInt(value);

    g_iModesDuration[g_iLoadedModes] = duration;
    strcopy(g_sModesFilename[g_iLoadedModes], PLATFORM_MAX_PATH, key);

    g_iLoadedModes++;

    //PrintToChatAll("Loaded mode %s for %d minutes", key, duration);

    return SMCParse_Continue;
}

public SMCResult ReadConfig_NewSection(Handle smc, const char[] name, bool opt_quotes) {}

void NextMode()
{
    g_bCurrentModeExtended = false;
    ExecMode(g_iCurrentMode + 1);
}

void ExecMode(int modeIndex)
{
    // Update current index
    //PrintToChatAll("Execing mode %d", modeIndex);
    g_iCurrentMode = modeIndex;

    // Check if index has overun
    if (g_iCurrentMode >= g_iLoadedModes) {
        //PrintToChatAll("Reseting index since we reached the end %d >= %d", g_iCurrentMode, g_iLoadedModes);
        g_iCurrentMode = 0;
    }

    // Send command to load new config
    //PrintToChatAll("Loading mode %s", g_sModesFilename[g_iCurrentMode]);
    ServerCommand("dm_load %s %s", g_sModesFilename[g_iCurrentMode], "respawn");

    // Update time when current config was loaded
    g_iLastModeLoad = GetTime();
}


bool ParseConfig()
{
    // Sets loaded modes to 0 to allow the parser to overwrite current configs
    g_iLoadedModes = 0;

    if (FileExists(g_sConfigFile))
    {
        SMCError err = g_hConfigParser.ParseFile(g_sConfigFile);
        if (err != SMCError_Okay)
        {
            char sError[64];
            if (g_hConfigParser.GetErrorString(err, sError, sizeof(sError)))
                LogError("[DML] ERROR: %s", sError);
            else
                LogError("[DML] ERROR: Fatal parse error");
            return false;
        }
    }
    else
    {
        SetFailState("[DML] ERROR: %s file is missing or corrupt!", g_sConfigFile);
        return false;
    }
    return true;
}
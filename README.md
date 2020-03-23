# CS:GO Deathmatch Loader

[![Latest compiled version](https://img.shields.io/github/v/release/HugoJF/csgo-deathmatch-loader?style=flat-square)](https://packagist.org/packages/hugojf/csgo-deathmatch-loader)
[![Version](https://img.shields.io/github/license/hugojf/csgo-deathmatch-loader?style=flat-square)](https://packagist.org/packages/hugojf/csgo-deathmatch-loader)
[![Edge build](https://img.shields.io/github/workflow/status/hugojf/csgo-deathmatch-loader/Compile%20Plugin?style=flat-square&label=edge)](https://packagist.org/packages/hugojf/csgo-deathmatch-loader)
[![Release build](https://img.shields.io/github/workflow/status/hugojf/csgo-deathmatch-loader/Publish%20release?style=flat-square&label=release)](https://packagist.org/packages/hugojf/csgo-deathmatch-loader)

This plugin is intended to be used with [Maxximou5/csgo-deathmatch](https://github.com/Maxximou5/csgo-deathmatch) version 3 which provides config loading commands.

## Features
  - Duration based config file;
  - Vote skip;
  - Vote extend.

## Convar
  * dm_loader_enabled - Enable/disable executing configs

## Commands
##### **Bold commands are admin-only.**

General commands
  - **`dm_reload`** - Reloads the deathmatch loader config.

Timer commands
  - `sm_timer` - Prints remaining time for current mode
  - `sm_tempo` - Prints remaining time for current mode

Skip commands
  - **`sm_next`** - Loads next configuration
  - `sm_skip` - Votes to skip current mode
  - `sm_pular` - Votes to skip current mode

Extension
  - **`sm_forceextend`** - Extends current mode
  - `sm_extend` - Votes to extend current mode

## Config

The config for the loader is located at `csgo/addons/sourcemod/configs/deathmatch/config_loader.ini`.

Each line represents a config to be loaded, followed by the duration in minutes it will run.

```
"Config"
{
    "deathmatch_default.ini"        "10"
    "deathmatch_pistol.ini"         "10"
    "deathmatch_awp.ini"            "5"
    "deathmatch_ak47.ini"           "5"
    "deathmatch_desert.ini"         "5"
    "deathmatch_m4s.ini"            "5"
}
```

import dimscord

import asyncdispatch
import std/strutils

import db/init
import bot_main
import db/queries

when is_main_module:
  var db_scheme = check_scheme()
  if db_scheme == "":
    initializeDB()
  db_scheme = check_scheme()
  if db_scheme != "":
    migrateDB(parseInt(db_scheme))
  
  let discord = bot_main.discord

  waitFor discord.startSession(gateway_intents = {giGuilds, giGuildMessages, giDirectMessages, giGuildVoiceStates, giMessageContent, giGuildMembers, giGuildMessageReactions, giMessageContent, giGuildBans, giGuildEmojisAndStickers})
  
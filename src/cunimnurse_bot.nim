import dimscord

import asyncdispatch
import std/strutils

import db/init
import bot_main
import db/queries

when is_main_module:
  var db_scheme = waitFor check_scheme()
  if db_scheme == "":
    waitFor initializeDB()
  db_scheme = waitFor check_scheme()
  if db_scheme != "":
    waitFor migrateDB(parseInt(db_scheme))
  
  let discord = bot_main.discord

  waitFor discord.startSession(gateway_intents = {giGuilds, giGuildMessages, giDirectMessages, giDirectMessageReactions, giGuildVoiceStates, giMessageContent, giGuildMembers, giGuildMessageReactions, giMessageContent, giGuildModeration, giGuildEmojisAndStickers, giGuildIntegrations})
  
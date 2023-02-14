import dimscord

import asyncdispatch

from db/init import initializeDB
import bot_main
import db/queries

when is_main_module:
  if check_scheme() == "":
    initializeDB()

  let discord = bot_main.discord

  waitFor discord.startSession()
  
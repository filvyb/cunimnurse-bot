import dimscord
import dimscmd

import asyncdispatch
import std/strformat
import options
import times

import config
import db/queries as query
import commands/verify

let conf = config.conf

let discord* = newDiscordClient(conf.discord.token)
var cmd = discord.newHandler()

proc reply(m: Message, msg: string): Future[Message] {.async.} =
    result = await discord.api.sendMessage(m.channelId, msg)

proc reply(i: Interaction, msg: string) {.async.} =
    #echo i
    let response = InteractionResponse(
        kind: irtChannelMessageWithSource,
        data: some InteractionApplicationCommandCallbackData(
            content: msg
        )
    )
    await discord.api.createInteractionResponse(i.id, i.token, response)

cmd.addSlash("verify", guildID = conf.discord.guild_id) do (login: string):
  ## UCO
  if i.channel_id.get() == conf.discord.verify_channel:
    var res = query.insert_user(i.member.get().user.id, login, 0)
    if res == false:
      await i.reply(fmt"Uz te tu mame. Kontaktuj adminy pokud nemas pristup")
    else:
      send_verification_mail(login)
      await i.reply(fmt"Email poslan")
  else:
    await i.reply(fmt"Spatny kanal")

cmd.addSlash("ping", guildID = conf.discord.guild_id) do ():
  ## latence
  let before = epochTime() * 1000
  await i.reply("ping?")
  let after = epochTime() * 1000

  #await discord.api.editInteractionResponse(i.application_id, i.token, i.message,)

  await i.reply("Pong trval " & $int(after - before) & "ms | " & $s.latency() & "ms.")

proc onReady(s: Shard, r: Ready) {.event(discord).} =
  await cmd.registerCommands()
  echo "Ready as " & $r.user

proc interactionCreate (s: Shard, i: Interaction) {.event(discord).} =
  discard await cmd.handleInteraction(s, i)

proc messageCreate (s: Shard, msg: Message) {.event(discord).} =
  if msg.author.bot: return
  discard await cmd.handleMessage("$$", s, msg)
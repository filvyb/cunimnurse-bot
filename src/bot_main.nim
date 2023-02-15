import dimscord
import dimscmd

import asyncdispatch
import std/strformat
import options
import times
import std/random
import std/sequtils
import std/sets

import config
import db/queries as query
import commands/verify

let conf = config.conf

let discord* = newDiscordClient(conf.discord.token)
var cmd = discord.newHandler()

proc reply(m: Message, msg: string): Future[Message] {.async.} =
    result = await discord.api.sendMessage(m.channelId, msg)

proc reply(i: Interaction, msg: string) {.async.} =
    let response = InteractionResponse(
        kind: irtChannelMessageWithSource,
        data: some InteractionApplicationCommandCallbackData(
            content: msg
        )
    )
    await discord.api.createInteractionResponse(i.id, i.token, response)

proc sync_roles() {.async.} =
  var discord_roles = await discord.api.getGuildRoles(conf.discord.guild_id)
  var db_roles = query.get_all_roles()
  # populates empty db
  #echo "sync"
  if db_roles.isNone:
    echo "empty db"
    for r in discord_roles:
      var role_name = r.name
      var role_id = r.id
      var role_manag = r.managed
      var power = 1

      if role_id == conf.discord.admin_role:
        power = 3
      elif role_manag:
        power = 3
      elif role_id == conf.discord.moderator_role:
        power = 2
      elif role_name == "@everyone":
        power = 0
      
      echo fmt"Added role {role_id} {role_name} to DB"
      discard insert_role(role_id, role_name, power)

  #db not empty
  #echo db_roles
  if db_roles.isSome:
    echo "not empty db"
    var discord_roles_seq: seq[string]
    var db_roles_seq: seq[string]

    for r in discord_roles:
      discord_roles_seq.add(r.id)

    var discord_roles_set = toHashSet(discord_roles_seq)

    for r in db_roles.get():
      db_roles_seq.add(r[0])

    var db_roles_set = toHashSet(db_roles_seq)

    var db_roles_to_delete = db_roles_set - discord_roles_set

    # first deletes roles tharen't in Discord but in DB
    for r in db_roles_to_delete:
      echo fmt"Deleted role {r} from DB"
      discard query.delete_role(r)

    #db_roles = query.get_all_roles()

    # then deletes roles that are in Discord but not in DB
    for r in discord_roles:
      var role_name = r.name
      var role_id = r.id
      var role_manag = r.managed
      var power = 1

      if not query.get_role_bool(role_id):
        echo fmt"Added role {role_id} {role_name} to DB"
        discard insert_role(role_id, role_name, power)


# User commands, done with slash
cmd.addSlash("verify", guildID = conf.discord.guild_id) do (login: string):
  ## UCO
  if i.channel_id.get() == conf.discord.verify_channel:
    var res = query.insert_user(i.member.get().user.id, login, 0)
    if res == false:
      await i.reply(fmt"Uz te tu mame. Kontaktuj adminy/moderatory pokud nemas pristup")
    else:
      await send_verification_mail(login)
      await i.reply(fmt"Email poslan")
  else:
    await i.reply(fmt"Spatny kanal")

cmd.addSlash("ping", guildID = conf.discord.guild_id) do ():
  ## latence
  let before = epochTime() * 1000
  await i.reply("ping?")
  let after = epochTime() * 1000

  var rep = "Pong trval " & $int(after - before) & "ms | " & $s.latency() & "ms."
  discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original",
      content= some rep)


cmd.addSlash("kasparek", guildID = conf.discord.guild_id) do ():
  ## Zepta se tvoji mami na tvoji velikost
  randomize()
  await i.reply(fmt"{$rand(1..48)}cm")

# Admin and mod commands, done with $$
cmd.addChat("forceverify") do (user: Option[User]):

    if user.isSome():
      var user_id = user.get().id
      var ver_stat = query.get_user_verification_status(user_id)
      if ver_stat == -1:
        randomize()
        var q = query.insert_user(user_id, fmt"forced_{$rand(1..100000)}", 2)
        while q == false:
          randomize()
          q = query.insert_user(user_id, fmt"forced_{$rand(1..100000)}", 2)
        await discord.api.addGuildMemberRole(conf.discord.guild_id, user_id, conf.discord.verified_role)
        discard await msg.reply("Uzivatel byl overen")
      elif ver_stat == 2:
        discard await msg.reply("Uzivatel byl uz overen")
      else:
        discard query.update_verified_status(user_id, 2)
        discard await msg.reply("Uzivatel byl overen")

    else:
        discard await discord.api.sendMessage(msg.channelID, "Uzivatel nenalezen")

proc onReady(s: Shard, r: Ready) {.event(discord).} =
  await cmd.registerCommands()
  await sync_roles()
  echo "Ready as " & $r.user

# Command registration
proc interactionCreate (s: Shard, i: Interaction) {.event(discord).} =
  discard await cmd.handleInteraction(s, i)

proc messageCreate (s: Shard, msg: Message) {.event(discord).} =
  if msg.author.bot: return

  discard await cmd.handleMessage("$$", s, msg)

  let author_id = msg.author.id
  let content = msg.content
  var ch_type = await discord.api.getChannel(msg.channel_id)

  # Handle DMs
  if ch_type[1].isSome:
    #var dm = ch_type[1].get()
    # Checks verification code and assigns verified role
    if check_msg_for_verification_code(content, author_id) == true:
      await discord.api.addGuildMemberRole(conf.discord.guild_id, author_id, conf.discord.verified_role)
      discard query.update_verified_status(author_id, 2)
      discard await msg.reply("Vitej na nasem serveru")

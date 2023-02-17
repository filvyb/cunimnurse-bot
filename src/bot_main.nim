import dimscord
import dimscmd

import asyncdispatch
import std/strformat
import options
import times
import std/random
import std/sequtils
import std/sets
import std/logging

import config
import db/queries as query
import commands/verify
import logging as clogger

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
    #echo "empty db"
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
      
      info(fmt"Added role {role_id} {role_name} to DB")
      discard query.insert_role(role_id, role_name, power)

  #db not empty
  if db_roles.isSome:
    #echo "not empty db"
    var discord_roles_seq: seq[string]
    var db_roles_seq: seq[string]

    for r in discord_roles:
      discord_roles_seq.add(r.id)

    var discord_roles_set = toHashSet(discord_roles_seq)

    for r in db_roles.get():
      db_roles_seq.add(r[0])

    var db_roles_set = toHashSet(db_roles_seq)

    var db_roles_to_delete = db_roles_set - discord_roles_set

    # first deletes roles that aren't in Discord but are in DB
    for r in db_roles_to_delete:
      info(fmt"Deleted role {r} from DB")
      discard query.delete_role(r)

    #db_roles = query.get_all_roles()

    # then adds roles that are in Discord but not in DB
    for r in discord_roles:
      var role_name = r.name
      var role_id = r.id
      var role_manag = r.managed
      var power = 1

      if not query.get_role_bool(role_id):
        info(fmt"Added role {role_id} {role_name} to DB")
        discard query.insert_role(role_id, role_name, power)

  # Syncing user roles
  var guild_members = await discord.api.getGuildMembers(conf.discord.guild_id)
  while guild_members.len mod 1000 == 0:
    var after = guild_members[guild_members.len - 1].user.id
    var tmp = await discord.api.getGuildMembers(conf.discord.guild_id, after=after)
    for x in tmp:
      guild_members.add(x)

  for x in guild_members:
    let user_id = x.user.id
    let user_name = x.user.username
    let user_disc_roles = x.roles
    let tmpq = query.get_all_user_roles(user_id)
    var user_db_roles: seq[string]

    if tmpq.isSome:
      user_db_roles = tmpq.get()

    let user_disc_roles_set = toHashSet(user_disc_roles)
    let user_db_roles_set = toHashSet(user_db_roles)
    
    let to_delete = user_db_roles_set - user_disc_roles_set
    let to_add = user_disc_roles_set - user_db_roles_set

    for r in to_delete:
      info(fmt"Deleted role {r} from user {user_id} {user_name} from DB")
      discard query.delete_role_relation(user_id, r)

    for r in to_add:
      info(fmt"Added role {r} to user {user_id} {user_name} to DB")
      discard query.insert_role_relation(user_id, r)

  #echo guild_members.len

  info("DB synced")


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

cmd.addSlash("resetverify", guildID = conf.discord.guild_id) do ():
  ## Pouzi pokud si pokazil verify
  let user_id = i.member.get().user.id
  if i.channel_id.get() == conf.discord.verify_channel:
    var user_stat = query.get_user_verification_status(user_id)
    if user_stat == 1:
      discard query.delete_user(user_id)
      await i.reply(fmt"Pouzij znovu /verify")
    elif user_stat > 1:
      await i.reply(fmt"Neco se pokazilo. Kontaktuj adminy/moderatory")
    else:
      await i.reply(fmt"Pouzij /verify")
      
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
  if query.get_user_power_level(msg.author.id) <= 2:
    return
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
    discard await msg.reply("Uzivatel nenalezen")

cmd.addChat("change_role_power") do (id: string, power: int):
  if query.get_user_power_level(msg.author.id) <= 2:
    return
  var res = query.update_role_power(id, power)
  discard await msg.reply($res)

cmd.addChat("jail") do (user: Option[User]):
  if query.get_user_power_level(msg.author.id) <= 2:
    return
  if user.isSome():
    let user_id = user.get().id
    discard query.update_verified_status(user_id, 4)
    var empty_role: seq[string]
    await discord.api.editGuildMember(conf.discord.guild_id, user_id, roles = some empty_role)
  else:
    discard await msg.reply("Uzivatel nenalezen")

cmd.addChat("unjail") do (user: Option[User]):
  if query.get_user_power_level(msg.author.id) <= 2:
    return
  if user.isSome():
    let user_id = user.get().id
    discard query.update_verified_status(user_id, 2)
    var roles = @[conf.discord.verified_role]
    await discord.api.editGuildMember(conf.discord.guild_id, user_id, roles = some roles)
  else:
    discard await msg.reply("Uzivatel nenalezen")

proc onReady(s: Shard, r: Ready) {.event(discord).} =
  await cmd.registerCommands()
  await sync_roles()
  info("Ready as " & $r.user)

# Handle on fly role changes
proc guildRoleCreate(s: Shard, g: Guild, r: Role) {.event(discord).} =
  let role_name = r.name
  let role_id = r.id
  info(fmt"Added role {role_id} {role_name} to DB")
  discard query.insert_role(role_id, role_name, 1)

proc guildRoleDelete(s: Shard, g: Guild, r: Role) {.event(discord).} =
  let role_name = r.name
  let role_id = r.id
  info(fmt"Delete role {role_id} {role_name} from DB")
  discard query.delete_role(role_id)

proc guildRoleUpdate(s: Shard, g: Guild, r: Role, o: Option[Role]) {.event(discord).} =
  let role_id = r.id
  let role_name = r.name
  var role_name_old = ""#o.get().name

  if o.isSome:
    role_name_old = o.get().name
  if role_name != role_name_old:
    info(fmt"Renamed role {role_id} {role_name_old} to {role_name}")
    discard query.update_role_name(role_id, role_name)

# Assign role on return
proc guildMemberAdd(s: Shard, g: Guild, m: Member) {.event(discord).} =
  let user_id = m.user.id

  if query.get_user_verification_status(user_id) == 2:
    var roles = @[conf.discord.verified_role]
    await discord.api.editGuildMember(conf.discord.guild_id, user_id, roles = some roles)

proc guildMemberRemove(s: Shard, g: Guild, m: Member) {.event(discord).} =
  let user_id = m.user.id
  let user_name = m.user.username

  info(fmt"Deleted roles from user {user_id} {user_name} from DB")
  discard query.delete_all_user_role_relation(user_id)

# Handle on fly role assignments
proc guildMemberUpdate(s: Shard; g: Guild; m: Member; o: Option[Member]) {.event(discord).} =
  let user_id = m.user.id
  let user_name = m.user.username
  let new_roles_set = toHashSet(m.roles)
  var old_roles_set: HashSet[string]
  var q = query.get_all_user_roles(user_id)

  if q.isSome:
    old_roles_set = toHashSet(q.get())

  let to_delete = old_roles_set - new_roles_set
  let to_add = new_roles_set - old_roles_set

  for r in to_delete:
    info(fmt"Deleted role {r} from user {user_id} {user_name} from DB")
    discard query.delete_role_relation(user_id, r)

  for r in to_add:
    info(fmt"Added role {r} to user {user_id} {user_name} to DB")
    discard query.insert_role_relation(user_id, r)

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

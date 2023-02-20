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
import std/math
import std/os

import config
import db/queries as query
import commands/verify
import logging as clogger

let conf = config.conf

let discord* = newDiscordClient(conf.discord.token)
var cmd = discord.newHandler()

proc figure_channel_users(c: GuildChannel): seq[string] =
  var over_perms = c.permission_overwrites
  var res: seq[string]
  for x, y in over_perms:
    #echo y.repr
    if y.kind == 1 and permViewChannel in y.allow:
      #echo y
      res.add(y.id)
    if y.kind == 0:
      let rol_users = query.get_all_role_users(y.id)
      if rol_users.isSome:
        for u in rol_users.get():
          res.add(u)
  return res

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

proc set_reaction2thread(m: Message, emoji_name: string, thread_id: string, message_id: string) {.async.} =
  let room_id = m.channel_id
  if room_id in conf.discord.thread_react_channels:
    if insert_thread_reaction(emoji_name, room_id, thread_id, message_id):
      await discord.api.addMessageReaction(room_id, message_id, emoji_name)
      #discard await m.reply("Povoleno")
    else:
      discard await m.reply("Nastala chyba")
  #else:
  #  discard await m.reply("Vyber roli reakcemi neni na tomto kanale povolen.")

# Syncs channels and their membership to the db
proc sync_channels() {.async.} =
  let discord_channels = await discord.api.getGuildChannels(conf.discord.guild_id)
  let db_channels = query.get_all_channels()

  if db_channels.isNone:
    info("Channel DB empty")
    for c in discord_channels:
      if c.kind == ctGuildText or c.kind == ctGuildForum:
        if query.insert_channel(c.id, c.name):
          info(fmt"Added channel {c.id} {c.name} to DB")

  if db_channels.isSome:
    info("Channel DB not empty")
    var discord_channels_seq: seq[string]
    var db_channels_seq: seq[string]
    for c in discord_channels:
      if c.kind == ctGuildText or c.kind == ctGuildForum:
        discord_channels_seq.add(c.id)
    for c in db_channels.get():
      db_channels_seq.add(c[0])
    var discord_channels_set = toHashSet(discord_channels_seq)
    var db_channels_set = toHashSet(db_channels_seq)

    let db_chan_to_del = db_channels_set - discord_channels_set
    let disc_chan_to_add = discord_channels_set - db_channels_set

    for c in db_chan_to_del:
      if query.delete_channel(c):
        info(fmt"Deleted channel {c} from DB")

    for c in disc_chan_to_add:
      if query.insert_channel(c):
        info(fmt"Added channel {c} to DB")

  for ch in discord_channels:
    if ch.kind == ctGuildText or ch.kind == ctGuildForum:
      let disc_ch_users_set = toHashSet(figure_channel_users(ch))
      let db_ch_users_seq = query.get_all_channel_users(ch.id)

      if db_ch_users_seq.isNone:
        for u in disc_ch_users_set:
          if query.insert_channel_membership(u, ch.id):
            info(fmt"Added user {u} to channel {ch.id} {ch.name} to DB")
      if db_ch_users_seq.isSome:
        let db_ch_users_set = toHashSet(db_ch_users_seq.get())

        let db_user_to_del = db_ch_users_set - disc_ch_users_set
        let disc_user_to_add = disc_ch_users_set - db_ch_users_set

        for u in db_user_to_del:
          if query.delete_channel_membership(u, ch.id):
            info(fmt"Deleted user {u} from channel {ch.id} {ch.name} from DB")
        
        for u in disc_user_to_add:
          if query.insert_channel_membership(u, ch.id):
            info(fmt"Added user {u} to channel {ch.id} {ch.name} to DB")
  info("DB users synced")

# Syncs roles and their membership to the db
proc sync_roles() {.async.} =
  var discord_roles = await discord.api.getGuildRoles(conf.discord.guild_id)
  var db_roles = query.get_all_roles()
  # populates empty db
  #echo "sync"
  if db_roles.isNone:
    info("Role DB empty")
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
      
      if query.insert_role(role_id, role_name, power):
        info(fmt"Added role {role_id} {role_name} to DB")

  #db not empty
  if db_roles.isSome:
    info("Role DB not empty")
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
      if query.delete_role(r):
        info(fmt"Deleted role {r} from DB")

    # then adds roles that are in Discord but not in DB
    for r in discord_roles:
      var role_name = r.name
      var role_id = r.id
      var power = 1

      if not query.get_role_bool(role_id):
        if query.insert_role(role_id, role_name, power):
          info(fmt"Added role {role_id} {role_name} to DB")

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
      if query.delete_role_relation(user_id, r):
        info(fmt"Deleted role {r} from user {user_id} {user_name} from DB")

    for r in to_add:
      if query.insert_role_relation(user_id, r):
        info(fmt"Added role {r} to user {user_id} {user_name} to DB")

  #echo guild_members.len

  info("DB roles synced")


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
cmd.addChat("help") do ():
  if query.get_user_power_level(msg.author.id) <= 2:
    return
  let text = """
            Pomoc pro adminy:
            $$forceverify <uzivatel>
            $$change_role_power <id role> <sila>
            $$jail <uzivatel>
            $$unjail <uzivatel>
            $$add-role-reaction <emoji> <id role> <id zpravy> (nepodporuje custom emoji)
            $$add-channel-reaction <emoji> <room id> <id zpravy> (pouze na male roomky, nepodporuje custom emoji)
            $$spawn-priv-threads <jmeno vlaken> <pocet>

            Prikazi nemaji moc kontrol tam dobre checkujte co pisete
            """
  discard await msg.reply(text)

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
  if query.get_user_power_level(msg.author.id) <= 3:
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

cmd.addChat("add-role-reaction") do (emoji_name: string, role_id: string, message_id: string):
  if query.get_user_power_level(msg.author.id) <= 2:
    return
  let room_id = msg.channel_id
  if room_id in conf.discord.reaction_channels:
    if query.insert_role_reaction(emoji_name, room_id, role_id, message_id):
      await discord.api.addMessageReaction(room_id, message_id, emoji_name)
      discard await msg.reply("Povoleno")
    else:
      discard await msg.reply("Nastala chyba")
  else:
    discard await msg.reply("Vyber roli reakcemi neni na tomto kanale povolen.")

cmd.addChat("add-channel-reaction") do (emoji_name: string, target_id: string, message_id: string):
  if query.get_user_power_level(msg.author.id) <= 2:
    return
  let room_id = msg.channel_id
  if room_id in conf.discord.reaction_channels:
    if query.insert_chan_reaction(emoji_name, room_id, target_id, message_id):
      await discord.api.addMessageReaction(room_id, message_id, emoji_name)
      discard await msg.reply("Povoleno")
    else:
      discard await msg.reply("Nastala chyba")
  else:
    discard await msg.reply("Vyber roli reakcemi neni na tomto kanale povolen.")

cmd.addChat("spawn-priv-threads") do (thread_name: string, thread_number: int):
  if query.get_user_power_level(msg.author.id) <= 2:
    return
  let room_id = msg.channel_id
  var msg_count = ceilDiv(thread_number, 10)
  var threads_done = 1

  for i in 1..msg_count:
    var msg_text = "Vyber is okruh\n"
    #if msg_count != 1:
    #  msg_text = "-\n"
    let emojis = ["0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣"]

    var react_msg = await discord.api.sendMessage(room_id, msg_text)
    for p in 1..10:
      var full_thread_name = thread_name & " " & $threads_done
      msg_text = msg_text & full_thread_name & " - " & emojis[p - 1] & '\n'
      sleep(250)
      react_msg = await discord.api.editMessage(room_id, react_msg.id, msg_text)
      var thread_obj = await discord.api.startThreadWithoutMessage(room_id, full_thread_name, 10080, some ctGuildPrivateThread, some false)
      sleep(150)
      await set_reaction2thread(msg, emojis[p - 1], thread_obj.id, react_msg.id)
      if threads_done >= thread_number:
        break
      threads_done += 1
      #echo p
    

proc onReady(s: Shard, r: Ready) {.event(discord).} =
  await cmd.registerCommands()
  await sync_roles()
  await sync_channels()
  info("Ready as " & $r.user)

# Handle on fly role changes
proc guildRoleCreate(s: Shard, g: Guild, r: Role) {.event(discord).} =
  let role_name = r.name
  let role_id = r.id
  
  if query.insert_role(role_id, role_name, 1):
    info(fmt"Added role {role_id} {role_name} to DB")

proc guildRoleDelete(s: Shard, g: Guild, r: Role) {.event(discord).} =
  let role_name = r.name
  let role_id = r.id
  
  if query.delete_role(role_id):
    info(fmt"Delete role {role_id} {role_name} from DB")

proc guildRoleUpdate(s: Shard, g: Guild, r: Role, o: Option[Role]) {.event(discord).} =
  let role_id = r.id
  let role_name = r.name
  var role_name_old = ""#o.get().name

  if o.isSome:
    role_name_old = o.get().name
  if role_name != role_name_old:
    if query.update_role_name(role_id, role_name):
      info(fmt"Renamed role {role_id} {role_name_old} to {role_name}")

# Assign role on return
proc guildMemberAdd(s: Shard, g: Guild, m: Member) {.event(discord).} =
  let user_id = m.user.id

  if query.get_user_verification_status(user_id) == 2:
    var roles = @[conf.discord.verified_role]
    await discord.api.editGuildMember(conf.discord.guild_id, user_id, roles = some roles)

# Remove roles on leave
proc guildMemberRemove(s: Shard, g: Guild, m: Member) {.event(discord).} =
  let user_id = m.user.id
  let user_name = m.user.username

  if query.delete_all_user_role_relation(user_id):
    info(fmt"Deleted roles from user {user_id} {user_name} from DB")

# Message reactions
proc messageReactionAdd(s: Shard, m: Message, u: User, e: Emoji, exists: bool) {.event(discord).} =
  if u.bot: return

  let room_id = m.channel_id
  let user_id = u.id
  let msg_id = m.id
  let emoji_name = e.name.get()
  #var member_roles = discord.api.getGuildMember(conf.discord.guild_id, user_id)
  #var member_roles: seq[string]
  #var q = query.get_all_user_roles(user_id)
  #if q.isSome:
  #  member_roles = q.get()

  if room_id in conf.discord.reaction_channels:
    # Assign role
    var role_to_give = query.get_reaction_role(emoji_name, room_id, msg_id)
    if role_to_give != "":
      await discord.api.addGuildMemberRole(conf.discord.guild_id, user_id, role_to_give)
      return

    # Assign channel via permission overwrite
    var channel_to_give = query.get_reaction_chan(emoji_name, room_id, msg_id)
    if channel_to_give != "":
      var the_chan = await discord.api.getChannel(channel_to_give)
      if the_chan[0].isSome:
        var over_perms = the_chan[0].get().permission_overwrites
        if not over_perms.hasKey(user_id):
          over_perms[user_id] = Overwrite()
          over_perms[user_id].id = user_id
          over_perms[user_id].kind = 1
          over_perms[user_id].allow = {permViewChannel}
          over_perms[user_id].deny = {}
        else:
          if over_perms[user_id].kind == 1:
            over_perms[user_id].allow = over_perms[user_id].allow + {permViewChannel}
        var new_over_perms: seq[Overwrite]
        for x, y in over_perms:
          new_over_perms.add(y)
        discard await discord.api.editGuildChannel(channel_to_give, permission_overwrites = some new_over_perms)
      return

  if room_id in conf.discord.thread_react_channels:
    var thread_to_give = query.get_reaction_thread(emoji_name, room_id, msg_id)
    if thread_to_give != "":
      await discord.api.addThreadMember(thread_to_give, user_id)

proc messageReactionRemove(s: Shard, m: Message, u: User, r: Reaction, exists: bool) {.event(discord).} =
  if u.bot: return

  let room_id = m.channel_id
  let user_id = u.id
  let msg_id = m.id
  let emoji_name = r.emoji.name.get()
  var member_roles: seq[string]
  var q = query.get_all_user_roles(user_id)
  if q.isSome:
    member_roles = q.get()

  
  if room_id in conf.discord.reaction_channels:
    # Remove assigned role
    var role_to_del = query.get_reaction_role(emoji_name, room_id, msg_id)
    var new_role_list = filter(member_roles, proc(x: string): bool = x != role_to_del)

    if toHashSet(member_roles) != toHashSet(new_role_list):
      await discord.api.editGuildMember(conf.discord.guild_id, user_id, roles = some new_role_list)
      return

    # Remove assigned channel via permission overwrite
    var channel_to_del = query.get_reaction_chan(emoji_name, room_id, msg_id)
    var the_chan = await discord.api.getChannel(channel_to_del)
    if the_chan[0].isSome:
      var over_perms = the_chan[0].get().permission_overwrites
      if over_perms.hasKey(user_id):
        if over_perms[user_id].kind == 1:
          over_perms[user_id].allow = over_perms[user_id].allow - {permViewChannel}
          if over_perms[user_id].allow.len == 0 and over_perms[user_id].deny.len == 0:
          #  over_perms.del(user_id)
            await discord.api.deleteGuildChannelPermission(channel_to_del, user_id)

      var new_over_perms: seq[Overwrite]
      for x, y in over_perms:
        new_over_perms.add(y)
      discard await discord.api.editGuildChannel(channel_to_del, permission_overwrites = some new_over_perms)
      return

    
  if room_id in conf.discord.thread_react_channels:
    var thread_to_del = query.get_reaction_thread(emoji_name, room_id, msg_id)
    if thread_to_del != "":
      await discord.api.removeThreadMember(thread_to_del, user_id)

# Remove react 2 roles/threads
proc messageDelete(s: Shard, m: Message, exists: bool) {.event(discord).} =
  #if m.author.bot: return

  let room_id = m.channel_id
  let msg_id = m.id

  if room_id in conf.discord.reaction_channels:
    discard query.delete_reaction_message(room_id, msg_id)
    discard query.delete_chan_react_message(room_id, msg_id)
  if room_id in conf.discord.thread_react_channels:
    discard query.delete_reaction2thread_message(room_id, msg_id)

# Delete reaction to enter threads
# threadDelete needs -d:nimOldCaseObjects to compile
proc threadDelete(s: Shard, g: Guild, c: GuildChannel, exists: bool) {.event(discord).} =
  let thread_id = c.id

  if c.kind == ctGuildPrivateThread:
    if query.delete_reaction_thread(thread_id):
      info(fmt"Reactions to thread {thread_id} deleted from DB")

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
    if query.delete_role_relation(user_id, r):
      info(fmt"Deleted role {r} from user {user_id} {user_name} from DB")

  for r in to_add:
    if query.insert_role_relation(user_id, r):
      info(fmt"Added role {r} to user {user_id} {user_name} to DB")

# Channel updates
proc channelCreate(s: Shard, g: Option[Guild], c: Option[GuildChannel], d: Option[DMChannel]) {.event(discord).} =
  if g.isSome:
    if c.isSome:
      if c.get().kind == ctGuildText or c.get().kind == ctGuildForum:
        if query.insert_channel(c.get().id, c.get().name):
          info(fmt"Added channel {c.get().id} {c.get().name} to DB")

proc channelDelete(s: Shard, g: Option[Guild], c: Option[GuildChannel], d: Option[DMChannel]) {.event(discord).} =
  if g.isSome:
    if c.isSome:
      if c.get().kind == ctGuildText or c.get().kind == ctGuildForum:
        if query.delete_channel(c.get().id):
          info(fmt"Deleted channel {c.get().id} {c.get().name} from DB")

# Handles adding users view permission overwrites
proc channelUpdate(s: Shard, g: Guild, c: GuildChannel, o: Option[GuildChannel]) {.event(discord).} =
  if c.kind == ctGuildText or c.kind == ctGuildForum:
    let channel_id = c.id
    let channel_name = c.name
    let disc_users_set = toHashSet(figure_channel_users(c))
    let db_users = query.get_all_channel_users(c.id)

    if db_users.isNone:
      for u in disc_users_set:
        if query.insert_channel_membership(u, channel_id):
          info(fmt"Added user {u} to channel {channel_id} {channel_name} to DB")
    if db_users.isSome:
      let db_ch_users_set = toHashSet(db_users.get())

      let db_user_to_del = db_ch_users_set - disc_users_set
      let disc_user_to_add = disc_users_set - db_ch_users_set

      for u in db_user_to_del:
        if query.delete_channel_membership(u, channel_id):
          info(fmt"Deleted user {u} from channel {channel_id} {channel_name} from DB")
        
      for u in disc_user_to_add:
        if query.insert_channel_membership(u, channel_id):
          info(fmt"Added user {u} to channel {channel_id} {channel_name} to DB")

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

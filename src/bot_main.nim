import dimscord
import dimscmd

import asyncdispatch
import std/strformat
import options
import times
import std/random
import std/sequtils
import std/strutils
import std/sets
import std/logging
import std/os
import std/math
import std/json
import std/unicode

import config
import db/queries as query
import commands/verify
import commands/mason
import commands/jokes
import utils/my_utils
import utils/logging as clogger

let conf = config.conf

var guild_ids: seq[string]

let discord* = newDiscordClient(conf.discord.token)
var cmd* = discord.newHandler()

proc create_room_role(guild_id: string, name: string, category_id: string): Future[(Role, GuildChannel)] {.async.} =
  var myrole = await discord.api.createGuildRole(guild_id, name, permissions = PermObj(allowed: {}, denied: {}))
  discard await discord.api.editGuildRolePosition(guild_id, myrole.id, some 2)
  let perm_over = @[Overwrite(id: myrole.id, kind: 0, allow: {permViewChannel}, deny: {})]
  let new_chan = await discord.api.createGuildChannel(guild_id, name, 0, some category_id, some name, permission_overwrites = some perm_over)
  return (myrole, new_chan)

proc get_verified_role_id(guild_id: string): Future[string] {.async.} =
  var role = query.get_role_id_name(guild_id, conf.discord.verified_role)
  if role.isSome:
    return role.get()
  if role.isNone:
    var disc_roles = await discord.api.getGuildRoles(guild_id)
    for r in disc_roles:
      if r.name.toLower() == conf.discord.verified_role:
        return r.id
  fatal("Couldn't find verified role in guild " & guild_id)
  return ""

proc get_teacher_role_id(guild_id: string): Future[string] {.async.} =
  var role = query.get_role_id_name(guild_id, conf.discord.teacher_role)
  if role.isSome:
    return role.get()
  if role.isNone:
    var disc_roles = await discord.api.getGuildRoles(guild_id)
    for r in disc_roles:
      if r.name.toLower() == conf.discord.teacher_role:
        return r.id
  fatal("Couldn't find teacher role in guild " & guild_id)
  return ""

proc figure_channel_users(c: GuildChannel): seq[string] =
  var over_perms = c.permission_overwrites
  var res: seq[string]
  for x, y in over_perms:
    if y.kind == 1 and permViewChannel in y.allow:
      res.add(y.id)
    if y.kind == 0:
      let rol_users = query.get_all_role_users(c.guild_id, y.id)
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
    if insert_thread_reaction(m.guild_id.get(), emoji_name, room_id, thread_id, message_id):
      await discord.api.addMessageReaction(room_id, message_id, emoji_name)
      info(fmt"Added message reaction in guild {m.guild_id.get()} room {room_id} with emoji {emoji_name} to thread {thread_id} on message {message_id}")
    else:
      discard await m.reply("Nastala chyba")
  #else:
  #  discard await m.reply("Vyber roli reakcemi neni na tomto kanale povolen.")

# Syncs channels and their membership to the db
proc sync_channels(guild_id: string) {.async.} =
  let discord_channels = await discord.api.getGuildChannels(guild_id)
  let db_channels = query.get_all_channels(guild_id)

  if db_channels.isNone:
    info("Channel DB empty")
    for c in discord_channels:
      if c.kind == ctGuildText or c.kind == ctGuildForum:
        if query.insert_channel(guild_id, c.id, c.name):
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
      if query.delete_channel(guild_id, c):
        info(fmt"Deleted channel {c} in guild {guild_id} from DB")

    for c in disc_chan_to_add:
      if query.insert_channel(guild_id, c):
        info(fmt"Added channel {c} in guild {guild_id} to DB")

  for ch in discord_channels:
    if ch.kind == ctGuildText or ch.kind == ctGuildForum:
      let disc_ch_users_set = toHashSet(figure_channel_users(ch))
      let db_ch_users_seq = query.get_all_channel_users(guild_id, ch.id)

      if db_ch_users_seq.isNone:
        for u in disc_ch_users_set:
          if query.insert_channel_membership(guild_id, u, ch.id):
            info(fmt"Added user {u} to channel {ch.id} {ch.name} in guild {guild_id} to DB")
      if db_ch_users_seq.isSome:
        let db_ch_users_set = toHashSet(db_ch_users_seq.get())

        let db_user_to_del = db_ch_users_set - disc_ch_users_set
        let disc_user_to_add = disc_ch_users_set - db_ch_users_set

        for u in db_user_to_del:
          if query.delete_channel_membership(guild_id, u, ch.id):
            info(fmt"Deleted user {u} from channel {ch.id} {ch.name} in guild {guild_id} from DB")
        
        for u in disc_user_to_add:
          if query.insert_channel_membership(guild_id, u, ch.id):
            info(fmt"Added user {u} to channel {ch.id} {ch.name} in guild {guild_id} to DB")
  info("DB users in guild " & guild_id & " synced")

# Syncs roles and their membership to the db
proc sync_roles(guild_id: string) {.async.} =
  var discord_roles = await discord.api.getGuildRoles(guild_id)
  var db_roles = query.get_all_roles(guild_id)
  # populates empty db
  if db_roles.isNone:
    info("Role DB empty")
    for r in discord_roles:
      var role_name = r.name
      var role_id = r.id
      var role_manag = r.managed
      var power = 1

      if role_name.toLower() == conf.discord.admin_role:
        power = 4
      elif role_manag:
        power = 4
      elif role_name.toLower() == conf.discord.moderator_role:
        power = 3
      elif role_name.toLower() == conf.discord.helper_role:
        power = 2
      elif role_name == "@everyone":
        power = 0
      
      if query.insert_role(guild_id, role_id, role_name, power):
        info(fmt"Added role {role_id} {role_name} in guild {guild_id} to DB")

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
      if query.delete_role(guild_id, r):
        info(fmt"Deleted role {r} in guild {guild_id} from DB")

    # then adds roles that are in Discord but not in DB
    for r in discord_roles:
      var role_name = r.name
      var role_id = r.id
      var power = 1

      if not query.get_role_bool(guild_id, role_id):
        if query.insert_role(guild_id, role_id, role_name, power):
          info(fmt"Added role {role_id} {role_name} in guild {guild_id} to DB")

  # Syncing user roles
  var guild_members = await discord.api.getGuildMembers(guild_id)
  while guild_members.len mod 1000 == 0:
    var after = guild_members[guild_members.len - 1].user.id
    var tmp = await discord.api.getGuildMembers(guild_id, after=after)
    for x in tmp:
      guild_members.add(x)

  for x in guild_members:
    let user_id = x.user.id
    let user_name = x.user.username
    let user_disc_roles = x.roles
    let tmpq = query.get_all_user_roles(guild_id, user_id)
    var user_db_roles: seq[string]

    if tmpq.isSome:
      user_db_roles = tmpq.get()

    let user_disc_roles_set = toHashSet(user_disc_roles)
    let user_db_roles_set = toHashSet(user_db_roles)
    
    let to_delete = user_db_roles_set - user_disc_roles_set
    let to_add = user_disc_roles_set - user_db_roles_set

    for r in to_delete:
      if query.delete_role_relation(guild_id, user_id, r):
        info(fmt"Deleted role {r} from user {user_id} {user_name} in guild {guild_id} from DB")

    for r in to_add:
      if query.insert_role_relation(guild_id, user_id, r):
        info(fmt"Added role {r} to user {user_id} {user_name} in {guild_id} to DB")

  info("DB roles in guild " & guild_id & " synced")


# User commands, done with slash
cmd.addSlash("confess") do (confession: string):
  ## Přiznej se
  var int_chan: (Option[GuildChannel], Option[DMChannel])
  try:
    int_chan = await discord.api.getChannel(i.channel_id.get())
  except:
    await i.reply("Funkce přiznání není nastavena")
  if int_chan[1].isSome:
    await i.reply("Přiznání akceptováno")
    let msg_sent = await discord.api.sendMessage(conf.discord.confession_channel, confession)
    let guild_ch = (await discord.api.getChannel(msg_sent.channel_id))[0].get()
    var rep = "https://discord.com/channels/" & guild_ch.guild_id & "/" & msg_sent.channel_id & "/" & msg_sent.id
    discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original",
      content= some rep)
  else:
    await i.reply("Přiznej se v DMs kktko")
    sleep(1400)
    await discord.api.deleteInteractionResponse(i.application_id, i.token, "@original")

cmd.addSlash("flip") do ():
  ## Rub či líc
  randomize()
  let coin = ["Rub", "líc"]
  await i.reply(sample(coin))

cmd.addSlash("verify") do (login: string):
  ## Zadej svoje UČO
  if i.channel_id.get() == conf.discord.verify_channel:
    var res = query.insert_user(i.member.get().user.id, login, 0)
    if res == false:
      await i.reply("Už tě tu máme. Kontaktuj adminy/moderátory pokud nemás přístup")
    else:
      await send_verification_mail(login)
      await i.reply("Email poslán")
  else:
    await i.reply("Špatný kanál")

cmd.addSlash("resetverify") do ():
  ## Použi pokud si pokazil verify
  let user_id = i.member.get().user.id
  if i.channel_id.get() == conf.discord.verify_channel:
    var user_stat = query.get_user_verification_status(user_id)
    if user_stat == 1 or user_stat == 0:
      discard query.delete_user(user_id)
      await i.reply("Můžeš použit znovu /verify")
    elif user_stat > 1:
      await i.reply("Něco se pokazilo. Kontaktuj adminy/moderátory")
    else:
      await i.reply("Použij /verify")
      
  else:
    await i.reply("Špatný kanal")

cmd.addSlash("ping") do ():
  ## latence
  let before = epochTime() * 1000
  await i.reply("ping?")
  let after = epochTime() * 1000

  var rep = "Pong trval " & $int(after - before) & "ms | " & $s.latency() & "ms."
  discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original",
      content= some rep)

cmd.addSlash("kasparek") do ():
  ## Zeptá se tvojí mámi na tvoji velikost
  randomize()
  await i.reply(fmt"{$rand(1..48)}cm")

cmd.addSlash("roll") do (num1: int, num2: int):
  ## Hodit kostkou
  randomize()
  await i.reply(fmt"{$rand(num1..num2)}")

cmd.addSlash("mason") do (numbers: int):
  ## Ty čísla Masone, co znamenají
  if conf.utils.mason == false:
    await i.reply("Mason utekl")
    return
  let chan = await discord.api.getChannel(i.channel_id.get())
  var is_nsfw = false
  if chan[1].isSome:
    is_nsfw = true
  else:
    is_nsfw = chan[0].get().nsfw

  await i.reply("...")
  var num_result = parse_the_numbers(numbers)
  if num_result[0].isNone:
    var rep = "Mason tyhle čísla nezná"
    discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original",
      content= some rep)
  if num_result[0].isSome:
    #let rep = num_result[0].get()["title"]["english"].getStr()
    let name = num_result[0].get()["title"]["pretty"].getStr()
    let author = num_result[0].get(){"artist"}.getStr()
    let group = num_result[0].get(){"group"}.getStr()
    let lang = num_result[0].get(){"language"}.getStr()
    let tags = num_result[0].get()["tags"].getElems()
    var tagstr: seq[string]

    for t in tags:
      tagstr.add(t.getStr())

    var eroembed = Embed()
    eroembed.title = some name
    if is_nsfw:
      eroembed.url = some "https://nhentai.net/g/" & $numbers
    var fields: seq[EmbedField]

    if author != "":
      #eroembed.author = some EmbedAuthor(name: author, url: some "https://nhentai.net/artist/" & author)
      #eroembed.footer = some EmbedFooter(text: author)
      fields.add(EmbedField(name: "Artist", value: author))
    if group != "":
      fields.add(EmbedField(name: "Group", value: group))
    if lang != "":
      fields.add(EmbedField(name: "Language", value: lang))
    if not ("lolicon" in tagstr or "shotacon" in tagstr) or is_nsfw:
      eroembed.image = some EmbedImage(url: num_result[1].get())
    
    var tagfield = EmbedField(name: "Tags", value: "")
    for t in tagstr:
      tagfield.value = tagfield.value & " | " & t
    
    fields.add(tagfield)

    eroembed.fields = some fields

    discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original",
      embeds= @[eroembed])

cmd.addSlash("search create") do (message: string):
  ## Přidej koho/co hledáš
  if i.user.isSome:
    await i.reply("Nelze v DMs")
    return
  let guild_id = i.guild_id.get()
  let channel_id = i.channel_id.get()
  let user_id = i.member.get().user.id
  let last_id = query.get_last_channel_search_id(guild_id, channel_id)
  discard query.insert_search(guild_id, channel_id, user_id, last_id + 1, message)

  await i.reply("Přidáno")

cmd.addSlash("search list") do ():
  ## Vypíše hledání v kanále
  if i.user.isSome:
    await i.reply("Nelze v DMs")
    return
  let guild_id = i.guild_id.get()
  let channel_id = i.channel_id.get()

  var embfields: seq[EmbedField]
  let searches = query.get_channel_searches(guild_id, channel_id)
  if searches.isNone:
    await i.reply("Seznam prázdný")
    return
  for q in searches.get():
    var theuser = await discord.api.getUser(q[0])
    var emb = EmbedField()
    emb.name = fmt"{q[1]} - {theuser.username}#{theuser.discriminator}"
    emb.value = q[2]
    embfields.add(emb)

  let thechan = await discord.api.getChannel(channel_id)

  let finemb = Embed(title: some "Hledání v " & thechan[0].get().name, fields: some embfields)

  let response = InteractionResponse(
      kind: irtChannelMessageWithSource,
      data: some InteractionApplicationCommandCallbackData(
          embeds: @[finemb]
      )
  )
  await discord.api.createInteractionResponse(i.id, i.token, response)

cmd.addSlash("search del") do (id: int):
  ## Odstraní tvoje hledání
  if i.user.isSome:
    await i.reply("Nelze v DMs")
    return
  let guild_id = i.guild_id.get()
  let channel_id = i.channel_id.get()
  let user_id = i.member.get().user.id

  if query.get_search_id_user(guild_id, channel_id, id) != user_id and query.get_user_power_level(guild_id, user_id) <= 1:
    await i.reply("Nemůžeš odstranit cizí příspěvky")
    return

  if query.delete_search(guild_id, channel_id, id):
    await i.reply("Odebráno")
  else:
    await i.reply("ID nenalezeno")

cmd.addSlash("yomamma") do ():
  ## Řekne vtip o tvojí mámě
  var joke = await get_mom_joke()
  await i.reply(joke)

cmd.addSlash("dadjoke") do ():
  ## Řekne dad joke
  var joke = await get_dad_joke()
  await i.reply(joke)

# Admin and mod commands, done with $$
cmd.addChat("help") do ():
  if msg.guild_id.isNone:
    return
  if query.get_user_power_level(msg.guild_id.get(), msg.author.id) <= 2:
    return
  let text = """
            Pomoc pro adminy:
            $$forceverify <uzivatel>
            $$change_role_power <id role> <sila>
            $$jail <uzivatel>
            $$unjail <uzivatel>
            $$add-role-reaction <emoji> <id role> <id zpravy> (nepodporuje custom emoji)
            $$add-channel-reaction <emoji> <room id> <id zpravy> (pouze na mále roomky, nepodporuje custom emoji)
            $$remove-emoji-reaction <emoji> <id zpravy> (nepodporuje custom emoji)
            $$spawn-priv-threads <jmeno vlaken> <pocet>
            $$whois <id uzivatele>
            $$create-room-role <jmeno role/kanalu> <id kategorie> (jmeno bez mezer)
            $$msg-to-room-role-react <id zpravy> <id kategorie>
            $$make-teacher <uzivatel>

            Příkazi nemají moc kontrol tak si dávejte pozor co píšete
            """
  discard await msg.reply(text)

cmd.addChat("forceverify") do (user: Option[User]):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 2:
    return
  if user.isSome():
    var user_id = user.get().id
    var ver_stat = query.get_user_verification_status(user_id)
    if ver_stat == -1:
      randomize()
      var q = query.insert_user(user_id, fmt"forced_{$rand(1..100000)}", 2)
      if q == false:
        discard await msg.reply("Příkaz selhal")
        return
      
      await discord.api.addGuildMemberRole(guild_id, user_id, await get_verified_role_id(guild_id))
      discard await msg.reply("Uživatel byl ověřen")
    elif ver_stat == 2:
      discard await msg.reply("Uzivatel byl uz ověřen")
    else:
      discard query.update_verified_status(user_id, 2)
      discard await msg.reply("Uživatel byl ověřen")

  else:
    discard await msg.reply("Uživatel nenalezen")

cmd.addChat("change_role_power") do (id: string, power: int):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return
  var res = query.update_role_power(guild_id, id, power)
  discard await msg.reply($res)

cmd.addChat("jail") do (user: Option[User]):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 2:
    return
  if user.isSome():
    let user_id = user.get().id
    let q = query.update_verified_status(user_id, 4)
    if q == false:
      discard await msg.reply("Příkaz selhal")
      return
    var empty_role: seq[string]
    for g in guild_ids:
      await discord.api.editGuildMember(g, user_id, roles = some empty_role)
    discard await msg.reply("Uživatel uvězněn")
  else:
    discard await msg.reply("Uživatel nenalezen")

cmd.addChat("unjail") do (user: Option[User]):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 2:
    return
  if user.isSome():
    let user_id = user.get().id
    let q = query.update_verified_status(user_id, 2)
    if q == false:
      discard await msg.reply("Příkaz selhal")
      return
    for g in guild_ids:
      var roles = @[await get_verified_role_id(g)]
      await discord.api.editGuildMember(g, user_id, roles = some roles)
    discard await msg.reply("Uživatel osvobozen")
  else:
    discard await msg.reply("Uživatel nenalezen")

cmd.addChat("make-teacher") do (user: Option[User]):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return
  if user.isSome():
    let user_id = user.get().id
    let q = query.update_user_position(user_id, 3)
    if q == false:
      discard await msg.reply("Příkaz selhal")
      return
    for g in guild_ids:
      await discord.api.addGuildMemberRole(g, user_id, await get_teacher_role_id(g))
    discard await msg.reply("Uživatel nastaven jake učitel")
  else:
    discard await msg.reply("Uživatel nenalezen")

cmd.addChat("add-role-reaction") do (emoji_name: string, role_id: string, message_id: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return
  let room_id = msg.channel_id
  if room_id in conf.discord.reaction_channels:
    if query.insert_role_reaction(guild_id, emoji_name, room_id, role_id, message_id):
      await discord.api.addMessageReaction(room_id, message_id, emoji_name)
      discard await msg.reply("Povoleno")
    else:
      discard await msg.reply("Nastala chyba")
  else:
    discard await msg.reply("Vyběr rolí reakcemi neni na tomto kanále povolen.")

cmd.addChat("add-channel-reaction") do (emoji_name: string, target_id: string, message_id: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return
  let room_id = msg.channel_id
  if room_id in conf.discord.reaction_channels:
    if query.insert_chan_reaction(guild_id, emoji_name, room_id, target_id, message_id):
      await discord.api.addMessageReaction(room_id, message_id, emoji_name)
      discard await msg.reply("Povoleno")
    else:
      discard await msg.reply("Nastala chyba")
  else:
    discard await msg.reply("Výber rolí reakcemi není na tomto kanále povolen.")

cmd.addChat("remove-emoji-reaction") do (emoji_name: string, message_id: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return
  let room_id = msg.channel_id
  if room_id in conf.discord.reaction_channels:
    if query.delete_role_emoji_reaction(guild_id, emoji_name, room_id, message_id):
      await discord.api.deleteMessageReaction(room_id, message_id, emoji_name)
      discard await msg.reply(fmt"{emoji_name} smazáno.")
      return
    if query.delete_chan_emoji_reaction(guild_id, emoji_name, room_id, message_id):
      await discord.api.deleteMessageReaction(room_id, message_id, emoji_name)
      discard await msg.reply(fmt"{emoji_name} smazáno.")
      return
  else:
    discard await msg.reply("Vyběr rolí reakcemi neni na tomto kanále povolen.")

cmd.addChat("spawn-priv-threads") do (thread_name: string, thread_number: int):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return
  let room_id = msg.channel_id
  var msg_count = ceilDiv(thread_number, 10)
  var threads_done = 1

  if not (room_id in conf.discord.thread_react_channels):
    discard await msg.reply("Kanál nemá povolené reakce do vláken")
    return
  
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

cmd.addChat("create-room-role") do (name: string, category_id: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return
  var mytup = await create_room_role(guild_id, name, category_id)
  discard await msg.reply("Vytvoren kanal " & mytup[1].id & " roli " & mytup[0].id)

cmd.addChat("msg-to-room-role-react") do (message_id: string, category_id: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return
  let room_id = msg.channel_id
  if room_id in conf.discord.reaction_channels:
    var lines = (await discord.api.getChannelMessage(room_id, message_id)).content.splitLines()
    for l in lines:
      var spl = l.split('-')
      if spl.len != 2:
        continue
      var role_room_name = spl[0]
      var emoji = spl[1]
      role_room_name = strutils.strip(role_room_name)
      emoji = strutils.strip(emoji)
      var therole = (await create_room_role(guild_id, role_room_name, category_id))[0]
      if query.insert_role_reaction(guild_id, emoji, room_id, therole.id, message_id):
        await discord.api.addMessageReaction(room_id, message_id, emoji)
  else:
    discard await msg.reply("Vyběr rolí reakcemi neni na tomto kanále povolen.")

cmd.addChat("whois") do (user_id: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return

  var user_db = query.get_user(user_id)
  if user_db.isSome:
    var user_db = user_db.get()
    var user = await discord.api.getUser(user_id)
    var embfields = @[EmbedField(name: "ID", value: user_db[0]),
                    EmbedField(name: "Login", value: user_db[1]),
                    EmbedField(name: "Name", value: user_db[2]),
                    EmbedField(name: "Status", value: user_db[4]),
                    EmbedField(name: "Position", value: user_db[5]),
                    EmbedField(name: "Joined", value: user_db[6]),
                    EmbedField(name: "Karma", value: user_db[7])]
    var the_embed = Embed(title: some "whois", description: some user.username & "#" & user.discriminator, fields: some embfields)
      
    discard await discord.api.sendMessage(msg.channel_id, embeds = @[the_embed])
  if user_db.isNone:
    discard await msg.reply("Uživatel nenalezen")

cmd.addChat("reboot") do ():
  if msg.guild_id.isNone:
    return
  if query.get_user_power_level(msg.guild_id.get(), msg.author.id) <= 3:
    return
  info("Admin " & msg.author.id & " killing bot via reboot command")
  quit(99)

cmd.addChat("sync-emojis") do ():
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return

  let guild_emojis = await discord.api.getGuildEmojis(guild_id)
  var guild_emojis_tb = initTable[string, string]()
  for e in guild_emojis:
    guild_emojis_tb[e.name.get()] = e.id.get()
  
  for g in guild_ids:
    if g != guild_id:
      sleep(100)
      let g_emojis = await discord.api.getGuildEmojis(g)
      var g_emojis_tb = initTable[string, string]()
      for e in g_emojis:
        g_emojis_tb[e.name.get()] = e.id.get()

      let emojis_to_del = g_emojis_tb - guild_emojis_tb
      let emojis_to_add = guild_emojis_tb - g_emojis_tb

      var failed_sync = 0

      for e in values(emojis_to_del):
        await discord.api.deleteGuildEmoji(g, e)
      info(fmt"Deleted {emojis_to_del.len} emojis from {g}")

      for e in guild_emojis:
        sleep(200)
        if e.name.get() in emojis_to_add:
          sleep(300)
          var image = await download_emoji(e.id.get(), e.animated.get())
          if image != "":
            var mime = "image/png"
            if e.animated.get():
              mime = "image/gif"

            let data_uri = fmt"data:{mime};base64,{image}"
            try:
              discard await discord.api.createGuildEmoji(g, e.name.get(), data_uri)
            except CatchableError as e:
              failed_sync = failed_sync + 1
              error(e.msg)
      info(fmt"Added {emojis_to_add.len - failed_sync} emojis from {guild_id} to {g}")
  discard await msg.reply("Emoji sync finished")

proc onReady(s: Shard, r: Ready) {.event(discord).} =
  for g in r.guilds:
    if g.unavailable:
      guild_ids.add(g.id)
      await sync_roles(g.id)
      await sync_channels(g.id)

  await cmd.registerCommands()
  
  info("Ready as " & $r.user & " in " & $guild_ids.len & " guilds")

# Handle on fly role changes
proc guildRoleCreate(s: Shard, g: Guild, r: Role) {.event(discord).} =
  let role_name = r.name
  let role_id = r.id
  
  if query.insert_role(g.id, role_id, role_name, 1):
    info(fmt"Added role {role_id} {role_name} in guild {g.id} to DB")

proc guildRoleDelete(s: Shard, g: Guild, r: Role) {.event(discord).} =
  let role_name = r.name
  let role_id = r.id
  
  if query.delete_role(g.id, role_id):
    info(fmt"Delete role {role_id} {role_name} in guild {g.id} from DB")

proc guildRoleUpdate(s: Shard, g: Guild, r: Role, o: Option[Role]) {.event(discord).} =
  let role_id = r.id
  let role_name = r.name
  var role_name_old = ""#o.get().name

  if o.isSome:
    role_name_old = o.get().name
  if role_name != role_name_old:
    if query.update_role_name(g.id, role_id, role_name):
      info(fmt"Renamed role {role_id} {role_name_old} to {role_name} in guild {g.id}")

# Assign role on return
proc guildMemberAdd(s: Shard, g: Guild, m: Member) {.event(discord).} =
  let user_id = m.user.id

  if query.get_user_verification_status(user_id) == 2:
    let ver_role = await get_verified_role_id(g.id)
    var roles = @[ver_role]
    await discord.api.editGuildMember(g.id, user_id, roles = some roles)

# Remove roles on leave
proc guildMemberRemove(s: Shard, g: Guild, m: Member) {.event(discord).} =
  let user_id = m.user.id
  let user_name = m.user.username

  if query.delete_all_user_role_relation(g.id, user_id):
    info(fmt"Deleted roles from user {user_id} {user_name} in guild {g.id} from DB")

# Message reactions
proc messageReactionAdd(s: Shard, m: Message, u: User, e: Emoji, exists: bool) {.event(discord).} =
  if u.bot: return

  let room_id = m.channel_id
  let user_id = u.id
  let msg_id = m.id
  var guild_id = ""
  if m.guild_id.isSome:
    guild_id = m.guild_id.get()
  let emoji_name = e.name.get()

  if room_id in conf.discord.reaction_channels:
    # Assign role
    var role_to_give = query.get_reaction_role(guild_id, emoji_name, room_id, msg_id)
    if role_to_give != "":
      await discord.api.addGuildMemberRole(guild_id, user_id, role_to_give)
      return

    # Assign channel via permission overwrite
    var channel_to_give = query.get_reaction_chan(guild_id, emoji_name, room_id, msg_id)
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

  let channel_obj = await discord.api.getChannel(room_id)
  # Pins and bookmarks
  if channel_obj[0].isSome:
    # Pins
    if emoji_name == "📌":
      let pins = await discord.api.getChannelPins(room_id)
      var pins_seq: seq[string]
      for p in pins:
        pins_seq.add(p.id)
      if msg_id in pins_seq:
        return
      else:
        var reacts = await discord.api.getMessageReactions(room_id, msg_id, "📌")
        if reacts.len >= conf.discord.pin_vote_count:
          await discord.api.addChannelMessagePin(room_id, msg_id)
          await discord.api.deleteMessageReactionEmoji(room_id, msg_id, "📌")
      return

    # Bookmarks
    if emoji_name == "🔖":
      var post_url = "https://discord.com/channels/" & guild_id & "/" & room_id & "/" & msg_id
      var but1 = newButton(
                label = "Původní zpráva!",
                idOrUrl = post_url,
                emoji = Emoji(name: some "🔗"),
                style = Link
            )
      var but2 = newButton(
                label = "Smazat záložku!",
                idOrUrl = "btnBookmarkDel",
                emoji = Emoji(name: some "🗑️"),
                style = Danger
            )
      var row = newActionRow(@[but1, but2])

      var user_dm = await discord.api.createUserDm(user_id)
      let g = await discord.api.getGuild(guild_id)
      var ms = m
      if not exists:
        ms = await discord.api.getChannelMessage(room_id, msg_id)

      var emb = Embed(title: some "Záložka na serveru " & g.name)
      emb.author = some EmbedAuthor(name: $ms.author, url: some avatarUrl(ms.author))
      var embfield = @[EmbedField(name: "Původní zpráva", value: "Empty")]

      if ms.content != "":
        embfield[0].value = ms.content
      embfield &= EmbedField(name: "Channel", value: $channel_obj[0].get())
      emb.fields = some embfield
      for at in ms.attachments:
        if at.content_type.isSome:
          if at.content_type.get() in ["image/jpeg", "image/png", "image/gif", "image/webp"] and emb.image.isNone:
            emb.image = some EmbedImage(url: at.url)

      discard await discord.api.sendMessage(
            user_dm.id,
            components = @[row],
            embeds = @[emb]
        )
      return

    # Repost canceling
    if emoji_name == "❎" and room_id in conf.discord.dedupe_channels:
      var reacts = await discord.api.getMessageReactions(room_id, msg_id, "❎")
      if reacts.len >= conf.discord.pin_vote_count:
        var ms = m
        if not exists:
          ms = await discord.api.getChannelMessage(room_id, msg_id)
        if not ms.author.bot: return
        await discord.api.deleteMessage(room_id, msg_id)
      return

  # Changed order so that people can pin and bookmark in rocnik threads
  if room_id in conf.discord.thread_react_channels:
    var thread_to_give = query.get_reaction_thread(guild_id, emoji_name, room_id, msg_id)
    if thread_to_give != "":
      await discord.api.addThreadMember(thread_to_give, user_id)
    return


proc messageReactionRemove(s: Shard, m: Message, u: User, r: Reaction, exists: bool) {.event(discord).} =
  if u.bot: return

  let room_id = m.channel_id
  let user_id = u.id
  let msg_id = m.id
  let emoji_name = r.emoji.name.get()
  var member_roles: seq[string]
  var guild_id = ""
  if m.guild_id.isSome:
    guild_id = m.guild_id.get()
  var q = query.get_all_user_roles(guild_id, user_id)
  if q.isSome:
    member_roles = q.get()

  
  if room_id in conf.discord.reaction_channels:
    # Remove assigned role
    var role_to_del = query.get_reaction_role(guild_id, emoji_name, room_id, msg_id)
    var new_role_list = filter(member_roles, proc(x: string): bool = x != role_to_del)

    if toHashSet(member_roles) != toHashSet(new_role_list):
      await discord.api.editGuildMember(guild_id, user_id, roles = some new_role_list)
      return

    # Remove assigned channel via permission overwrite
    var channel_to_del = query.get_reaction_chan(guild_id, emoji_name, room_id, msg_id)
    var the_chan = await discord.api.getChannel(channel_to_del)
    if the_chan[0].isSome:
      var over_perms = the_chan[0].get().permission_overwrites
      if over_perms.hasKey(user_id):
        if over_perms[user_id].kind == 1:
          over_perms[user_id].allow = over_perms[user_id].allow - {permViewChannel}
          if over_perms[user_id].allow.len == 0 and over_perms[user_id].deny.len == 0:
          #  over_perms.del(user_id)
            await discord.api.deleteGuildChannelPermission(channel_to_del, user_id)
            return

      var new_over_perms: seq[Overwrite]
      for x, y in over_perms:
        new_over_perms.add(y)
      discard await discord.api.editGuildChannel(channel_to_del, permission_overwrites = some new_over_perms)
      return

  if room_id in conf.discord.thread_react_channels:
    var thread_to_del = query.get_reaction_thread(guild_id, emoji_name, room_id, msg_id)
    if thread_to_del != "":
      await discord.api.removeThreadMember(thread_to_del, user_id)


# Remove react 2 roles/threads
proc messageDelete(s: Shard, m: Message, exists: bool) {.event(discord).} =
  #if m.author.bot: return

  let room_id = m.channel_id
  let msg_id = m.id
  var guild_id = ""
  if m.guild_id.isSome:
    guild_id = m.guild_id.get()

  if room_id in conf.discord.reaction_channels:
    discard query.delete_reaction_message(guild_id, room_id, msg_id)
    discard query.delete_chan_react_message(guild_id, room_id, msg_id)
  if room_id in conf.discord.thread_react_channels:
    discard query.delete_reaction2thread_message(guild_id, room_id, msg_id)

# Delete reaction to enter threads
proc threadDelete(s: Shard, g: Guild, c: GuildChannel, exists: bool) {.event(discord).} =
  let thread_id = c.id
  if c.kind == ctGuildPrivateThread:
    if query.delete_reaction_thread(g.id, thread_id):
      info(fmt"Reactions to thread {thread_id} deleted from DB")

# Handle on fly role assignments
proc guildMemberUpdate(s: Shard; g: Guild; m: Member; o: Option[Member]) {.event(discord).} =
  let user_id = m.user.id
  let user_name = m.user.username
  let new_roles_set = toHashSet(m.roles)
  var old_roles_set: HashSet[string]
  var q = query.get_all_user_roles(g.id, user_id)

  if q.isSome:
    old_roles_set = toHashSet(q.get())

  let to_delete = old_roles_set - new_roles_set
  let to_add = new_roles_set - old_roles_set

  for r in to_delete:
    if query.delete_role_relation(g.id, user_id, r):
      info(fmt"Deleted role {r} from user {user_id} {user_name} in guild {g.id} from DB")

  for r in to_add:
    if query.insert_role_relation(g.id, user_id, r):
      info(fmt"Added role {r} to user {user_id} {user_name} in guild {g.id} to DB")

# Channel updates
proc channelCreate(s: Shard, g: Option[Guild], c: Option[GuildChannel], d: Option[DMChannel]) {.event(discord).} =
  if g.isSome:
    if c.isSome:
      if c.get().kind == ctGuildText or c.get().kind == ctGuildForum:
        if query.insert_channel(g.get().id, c.get().id, c.get().name):
          info(fmt"Added channel {c.get().id} {c.get().name} in guild {g.get().id} to DB")

proc channelDelete(s: Shard, g: Option[Guild], c: Option[GuildChannel], d: Option[DMChannel]) {.event(discord).} =
  if g.isSome:
    if c.isSome:
      if c.get().kind == ctGuildText or c.get().kind == ctGuildForum:
        if query.delete_channel(g.get().id, c.get().id):
          info(fmt"Deleted channel {c.get().id} {c.get().name} in guild {g.get().id} from DB")

# Handles adding users view permission overwrites
proc channelUpdate(s: Shard, g: Guild, c: GuildChannel, o: Option[GuildChannel]) {.event(discord).} =
  if c.kind == ctGuildText or c.kind == ctGuildForum:
    let channel_id = c.id
    let channel_name = c.name
    let disc_users_set = toHashSet(figure_channel_users(c))
    let db_users = query.get_all_channel_users(g.id, c.id)

    if db_users.isNone:
      for u in disc_users_set:
        if query.insert_channel_membership(g.id, u, channel_id):
          info(fmt"Added user {u} to channel {channel_id} {channel_name} in guild {g.id} to DB")
    if db_users.isSome:
      let db_ch_users_set = toHashSet(db_users.get())

      let db_user_to_del = db_ch_users_set - disc_users_set
      let disc_user_to_add = disc_users_set - db_ch_users_set

      for u in db_user_to_del:
        if query.delete_channel_membership(g.id, u, channel_id):
          info(fmt"Deleted user {u} from channel {channel_id} {channel_name} in guild {g.id} from DB")
        
      for u in disc_user_to_add:
        if query.insert_channel_membership(g.id, u, channel_id):
          info(fmt"Added user {u} to channel {channel_id} {channel_name} in guild {g.id} to DB")

# Handle bans
proc guildBanAdd(s: Shard, g: Guild, u: User) {.event(discord).} =
  discard query.update_verified_status(u.id, 3)
  var main_ban = await discord.api.getGuildBan(g.id, u.id)
  var reason = "No reason given"
  if main_ban.reason.isSome:
    reason = main_ban.reason.get()
  for gid in guild_ids:
    if gid != g.id:
      try:
        await discord.api.createGuildBan(gid, u.id, reason = reason)
      except CatchableError as e:
        error(e.msg)

proc guildBanRemove(s: Shard, g: Guild, u: User) {.event(discord).} =
  discard query.delete_user(u.id)
  for gid in guild_ids:
    if gid != g.id:
      try:
        await discord.api.removeGuildBan(gid, u.id)
      except CatchableError as e:
        error(e.msg)

# Interaction handling
proc interactionCreate(s: Shard, i: Interaction) {.event(discord).} =
  let guild_id = i.guild_id
  let data = i.data.get()
  # Command handling
  if i.kind == itApplicationCommand:
    discard await cmd.handleInteraction(s, i)
    return

  # Bookmark delete handling
  if data.custom_id == "btnBookmarkDel":
    await discord.api.deleteMessage(i.channel_id.get(), i.message.get().id)

proc messageCreate(s: Shard, msg: Message) {.event(discord).} =
  if msg.author.bot: return

  discard await cmd.handleMessage("$$", s, msg)

  let author_id = msg.author.id
  let content = msg.content
  let room_id = msg.channel_id
  let msg_id = msg.id
  var guild_id = ""
  if msg.guild_id.isSome:
    guild_id = msg.guild_id.get()
  var ch_type = await discord.api.getChannel(room_id)

  # Handle DMs
  if ch_type[1].isSome:
    #var dm = ch_type[1].get()
    # Checks verification code and assigns verified role
    if check_msg_for_verification_code(content, author_id) == true:
      discard query.update_verified_status(author_id, 2)
      for g in guild_ids:
        let ver_role = await get_verified_role_id(g)
        await discord.api.addGuildMemberRole(g, author_id, ver_role)
      discard await msg.reply("Vítej na našem serveru")

  if ch_type[0].isSome:
    if room_id in conf.discord.dedupe_channels:
      for a in msg.attachments:
        var dedupe_res = await dedupe_media(guild_id, room_id, msg_id, a)
        if dedupe_res[0] == true:
          var msg_med_ids = dedupe_res[2].split("|")
          var flagged_msg = await discord.api.getChannelMessage(room_id, msg_med_ids[0])
          var med_url = ""
          for f in flagged_msg.attachments:
            if f.url.rfind(msg_med_ids[1]) >= 0:
              med_url = f.url
          var imgemb = EmbedImage(url: med_url)
          var msg_url = "https://discord.com/channels/" & guild_id & "/" & room_id & "/" & msg_med_ids[0]
          var desc = fmt"Tento meme se shoduje ze {dedupe_res[1]}% s jiným. Pokud tak není klikněte na ❎"
          var emb = Embed(title: some "Repost", description: some desc, image: some imgemb)
          var sent_msg = await discord.api.sendMessage(room_id, content = msg_url, embeds = @[emb], message_reference = some MessageReference(channel_id: some room_id, message_id: some msg_id))
          await discord.api.addMessageReaction(room_id, sent_msg.id, "❎")

proc messageDelete(s: Shard, m: Message, exists: bool) {.event(discord).} =
  let room_id = m.channel_id
  let msg_id = m.id
  var guild_id = ""
  if m.guild_id.isSome:
    guild_id = m.guild_id.get()
  var ch_type = await discord.api.getChannel(room_id)

  if ch_type[0].isSome:
    if room_id in conf.discord.dedupe_channels:
      discard query.delete_media_message(guild_id, room_id, msg_id)

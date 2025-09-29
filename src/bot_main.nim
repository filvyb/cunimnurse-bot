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
import std/math
import std/json
import std/unicode
import std/tables

import config
import db/queries as query
import commands/verify
import commands/mason
import commands/jokes
import commands/pingetter
import commands/info
import utils/my_utils
import utils/media_dedupe
import utils/logging as clogger
import utils/data_structs

let conf = config.conf

var guild_ids: seq[string]

## TableRef[channel_id, (seq[message_id], zip_url)]
var pin_cache = newTable[string, (seq[string], string)]()

let discord* = newDiscordClient(conf.discord.token)
var cmd* = discord.newHandler()

proc create_room_role(guild_id: string, name: string, category_id: string): Future[(Role, GuildChannel)] {.async.} =
  var myrole = await discord.api.createGuildRole(guild_id, name)
  discard await discord.api.editGuildRolePosition(guild_id, myrole.id, some 2)
  let perm_over = @[Overwrite(id: myrole.id, kind: otRole, allow: {permViewChannel}, deny: {})]
  let new_chan = await discord.api.createGuildChannel(guild_id, name, 0, some category_id, some name, permission_overwrites = some perm_over)
  return (myrole, new_chan)

proc get_role_id_by_name(guild_id, role_name: string): Future[string] {.async.} =
  var role = query.get_role_id_name(guild_id, role_name)
  if role.isSome:
    return role.get()
  if role.isNone:
    var disc_roles = await discord.api.getGuildRoles(guild_id)
    for r in disc_roles:
      if r.name.toLower() == role_name:
        return r.id
  fatal("Couldn't find " & role_name & " role in guild " & guild_id)
  return ""

proc figure_channel_users(c: GuildChannel): seq[string] =
  var over_perms = c.permission_overwrites
  var res: seq[string]
  for x, y in over_perms:
    if y.kind == otMember and permViewChannel in y.allow:
      res.add(y.id)
    if y.kind == otRole:
      let rol_users = query.get_all_role_users(c.guild_id, y.id)
      if rol_users.isSome:
        for u in rol_users.get():
          res.add(u)
  return res

proc give_user_sis_role(user: DbUser): Future[bool] {.async.} =
  var role2give = find_role_name4user(user)
  if role2give == "":
    return false

  for g in guild_ids:
    let role_id = await get_role_id_by_name(g, role2give)
    if role_id == "":
      continue

    if not query.exists_role_relation(g, user.id, (await get_role_id_by_name(g, conf.discord.verified_role))):
      continue
    try:
      await discord.api.addGuildMemberRole(g, user.id, role_id)
    except CatchableError as e:
      error(fmt"Failed giving user {user.id} in guild {g} role {role2give}: {e.msg} {$e.trace}" )
      continue
  
  return true

proc give_user_sis_role(user_id: string): Future[bool] {.async.} =
  var user = query.get_user(user_id)
  if user.isNone:
    return false

  return await give_user_sis_role(user.get())

proc give_all_users_sis_role(): Future[(int, int)] {.async.} =
  var users = query.get_verified_users()
  if users.isNone:
    return (0,0)

  var f = 0

  for us in users.get():
    var user = us

    if "forced" in user.login:
      f += 1
      continue
    if user.study_type == "":
      if not (await parse_sis_for_user(user, true)):
        error("Failed parsing SIS for user " & user.id)
        f += 1
        continue
      else:
        user = query.get_user(user.id).get()

    if not await give_user_sis_role(user):
      f += 1
    
  return (f, users.get().len)


proc reply(m: Message, msg: string): Future[Message] {.async.} =
    result = await discord.api.sendMessage(m.channelId, msg)

proc reply(i: Interaction, msg: string) {.async.} =
  let response = InteractionResponse(
      kind: irtChannelMessageWithSource,
      data: some InteractionCallbackDataMessage(
          content: msg
      )
  )
  await discord.api.createInteractionResponse(i.id, i.token, response)

proc reply_priv(i: Interaction, msg: string) {.async.} =
  await discord.api.interactionResponseMessage(i.id, i.token,
        kind = irtChannelMessageWithSource,
        response = InteractionCallbackDataMessage(
            flags: {mfEphemeral},
            content: msg
        )
    )

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
    await i.reply_priv("Funkce přiznání není nastavena")
  
  await i.reply_priv("Přiznání akceptováno")
  let msg_sent = await discord.api.sendMessage(conf.discord.confession_channel, confession)
  let guild_ch = (await discord.api.getChannel(msg_sent.channel_id))[0].get()
  var rep = "https://discord.com/channels/" & guild_ch.guild_id & "/" & msg_sent.channel_id & "/" & msg_sent.id
  discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original",
      content= some rep)

cmd.addSlash("flip") do ():
  ## Rub či líc
  randomize()
  let coin = ["Rub", "líc"]
  await i.reply(sample(coin))

cmd.addSlash("verify") do (login: string):
  ## Zadej svůj CAS login
  var user_id = i.member.get().user.id
  if i.channel_id.get() == conf.discord.verify_channel:
    if conf.email.use_mail:
      var res = query.insert_user(user_id, login, 0)
      
      if res == false:
        await i.reply_priv("Už tě tu máme. Zkus /resetverify a popřípadě kontaktuj adminy/moderátory pokud nemás přístup")
      else:
        await i.reply_priv("...")
        var email_sent = await send_verification_mail(login)
        if email_sent:
          discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original", 
                                                            some "Email poslán")
        else:
          discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original", 
                                                            some "Nastala chyba při posílání emailu")
    else:
      discard query.insert_user(user_id, login, 0)

      await i.reply_priv("Kód a instrukce poslány do DMs")
      var code = get_verification_code(user_id)
      try:
        var user_dm = await discord.api.createUserDm(user_id)
        var text = code
        discard await discord.api.sendMessage(user_dm.id, text)
      except CatchableError as e:
        error("Couldn't send DMs with code " & e.msg)
  else:
    await i.reply_priv("Špatný kanál")

cmd.addSlash("resetverify") do ():
  ## Použi pokud si pokazil verify
  let user_id = i.member.get().user.id
  if i.channel_id.get() == conf.discord.verify_channel:
    var user_stat = query.get_user_verification_status(user_id)
    if user_stat == 1 or user_stat == 0:
      discard query.delete_user(user_id)
      await i.reply_priv("Můžeš použit znovu /verify")
    elif user_stat > 1:
      await i.reply("Něco se pokazilo. Kontaktuj adminy/moderátory")
    else:
      await i.reply_priv("Použij /verify")
      
  else:
    await i.reply_priv("Špatný kanal")

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
  var num_result = await parse_the_numbers(numbers)
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
      data: some InteractionCallbackDataMessage(
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
  var joke = "..."
  await i.reply(joke)
  joke = await get_mom_joke()
  discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original",
                                                    some joke)

cmd.addSlash("dadjoke") do ():
  ## Řekne dad joke
  var joke = "..."
  await i.reply(joke)
  joke = await get_dad_joke()
  discard await discord.api.editInteractionResponse(i.application_id, i.token, "@original",
                                                    some joke)

cmd.addSlash("zip-pins") do ():
  ## Pošle všechny piny do DM
  if i.user.isSome:
    await i.reply_priv("Nelze v DMs")
    return
  let guild_id = i.guild_id.get()
  let channel_id = i.channel_id.get()
  let user_id = i.member.get().user.id

  await i.reply_priv("Stahují se piny")

  var pin_sum = await sum_channel_pins(discord, guild_id, channel_id, pin_cache, true, false)
  var ch_url = "https://discord.com/channels/" & guild_id & "/" & channel_id

  var but1 = newButton(
                label = "Odkaz na kanál!",
                idOrUrl = ch_url,
                emoji = Emoji(name: some "🔗"),
                style = Link
            )
  var but2 = newButton(
                label = "Smazat shrnutí!",
                idOrUrl = "btnBookmarkDel",
                emoji = Emoji(name: some "🗑️"),
                style = Danger
            )
  var row = newActionRow(@[but1, but2])

  var user_dm = await discord.api.createUserDm(user_id)

  let channel_obj = await discord.api.getChannel(channel_id)

  var emb = Embed(description: some pin_sum[0])
  var embfield = @[EmbedField(name: "Channel", value: $channel_obj[0].get()), EmbedField(name: "Link", value: pin_sum[1])]
  emb.fields = some embfield

  discard await discord.api.sendMessage(
            user_dm.id,
            #content = pin_sum[1],
            components = @[row],
            embeds = @[emb]
        )
  return

cmd.addSlash("pocasi") do (place: Option[string]):
  ## Vypíše počasí v daném městě. Výchozí je Praha
  var location = "Praha"
  if place.isSome:
    location = place.get()
  
  var res = await get_weather(location)

  if res[0] == 200:
    let response = InteractionResponse(
      kind: irtChannelMessageWithSource,
      data: some InteractionCallbackDataMessage(
          embeds: @[res[1]]
      )
    )
    await discord.api.createInteractionResponse(i.id, i.token, response)
  elif res[0] == 401:
    error("Open Weather invalid token")
    await i.reply("F token, Valve plz fix")
  elif res[0] == 404:
    await i.reply("Město nenalezeno")
  else:
    error("Open Weather unknown error, status code " & $res[0])
    await i.reply("Neznámá chyba, Valve plz fix")


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
            $$get-rooms-in-config
            $$sum-pins
            $$create-role-everywhere <jmeno role> <pozice role> <hex rgb barva>
            $$remove-role-everywhere <jmeno role>
            $$sync-sis-roles

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

    if ver_stat < 2:
      var ver_role = await get_role_id_by_name(guild_id, conf.discord.verified_role)
      
      await discord.api.addGuildMemberRole(guild_id, user_id, ver_role)

      randomize()
      discard query.delete_user(user_id)
      var q = query.insert_user(user_id, fmt"forced_{$rand(1..100000)}", 2)
      if q == false:
        discard await msg.reply("Příkaz selhal")
        return

      discard await msg.reply("Uživatel byl ověřen")
    else:
      discard await msg.reply("Uzivatel byl uz ověřen")

  else:
    discard await msg.reply("Uživatel nenalezen")

cmd.addChat("forceverify-id") do (user_id: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 2:
    return
  if user_id != "":
    var ver_stat = query.get_user_verification_status(user_id)

    if ver_stat < 2:
      var ver_role = await get_role_id_by_name(guild_id, conf.discord.verified_role)
      
      await discord.api.addGuildMemberRole(guild_id, user_id, ver_role)

      randomize()
      discard query.delete_user(user_id)
      var q = query.insert_user(user_id, fmt"forced_{$rand(1..100000)}", 2)
      if q == false:
        discard await msg.reply("Příkaz selhal")
        return

      discard await msg.reply("Uživatel byl ověřen")
    else:
      discard await msg.reply("Uzivatel byl uz ověřen")

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
      var roles = @[await get_role_id_by_name(g, conf.discord.verified_role)]
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
      await discord.api.addGuildMemberRole(g, user_id, await get_role_id_by_name(g, conf.discord.teacher_role))
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
    var msg_text = "Vyber is kruh\n"
    #if msg_count != 1:
    #  msg_text = "-\n"
    let emojis = ["0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣"]

    var react_msg = await discord.api.sendMessage(room_id, msg_text)
    for p in 1..10:
      var full_thread_name = thread_name & " " & $threads_done
      msg_text = msg_text & full_thread_name & " - " & emojis[p - 1] & '\n'
      await sleepAsync(250)
      react_msg = await discord.api.editMessage(room_id, react_msg.id, msg_text)
      await sleepAsync(100)
      var thread_obj = await discord.api.startThreadWithoutMessage(room_id, full_thread_name, 10080, some ctGuildPrivateThread, some false)
      await sleepAsync(150)
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
    var count = 0
    for l in lines:
      if count >= 20:
        break
      var spl = l.rsplit('-', 1)
      if spl.len != 2:
        continue
      var role_room_name = spl[0]
      var emoji = spl[1]
      role_room_name = strutils.strip(role_room_name)
      emoji = strutils.strip(emoji)
      var therole = (await create_room_role(guild_id, role_room_name, category_id))[0]
      if query.insert_role_reaction(guild_id, emoji, room_id, therole.id, message_id):
        await discord.api.addMessageReaction(room_id, message_id, emoji)
      count = count + 1
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
    var embfields = @[EmbedField(name: "ID", value: user_db.id),
                    EmbedField(name: "Login", value: user_db.login),
                    EmbedField(name: "Name", value: user_db.name),
                    EmbedField(name: "Status", value: $user_db.status),
                    EmbedField(name: "Position", value: $user_db.uni_pos),
                    EmbedField(name: "Joined", value: $user_db.joined),
                    EmbedField(name: "Karma", value: $user_db.karma),
                    EmbedField(name: "Faculty", value: $user_db.faculty),
                    EmbedField(name: "Type of study", value: user_db.study_type),
                    EmbedField(name: "Branch of study", value: user_db.study_branch),
                    EmbedField(name: "Year", value: $user_db.year),
                    EmbedField(name: "Circle", value: $user_db.circle)]
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
      await sleepAsync(120)
      let g_emojis = await discord.api.getGuildEmojis(g)
      var g_emojis_tb = initTable[string, string]()
      for e in g_emojis:
        g_emojis_tb[e.name.get()] = e.id.get()

      let emojis_to_del = g_emojis_tb - guild_emojis_tb
      let emojis_to_add = guild_emojis_tb - g_emojis_tb

      var failed_sync = 0

      for e in values(emojis_to_del):
        await discord.api.deleteGuildEmoji(g, e)
        await sleepAsync(100)
      info(fmt"Deleted {emojis_to_del.len} emojis from {g}")

      for e in guild_emojis:
        await sleepAsync(200)
        if e.name.get() in emojis_to_add:
          await sleepAsync(300)
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

cmd.addChat("get-rooms-in-config") do ():
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 2:
    return

  var final_str = "Reaction channels\n"

  for i in conf.discord.reaction_channels:
    if "id" in i:
      continue
    try:
      var chan = (await discord.api.getChannel(i))[0].get()
      var guild = await discord.api.getGuild(chan.guild_id)

      final_str &= fmt"ID: {chan.id} Name: {chan.name} Server: {guild.name}"
      final_str &= '\n'
    except CatchableError as e:
      error("get-rooms-in-config failed getting channel: " & e.msg)
      continue
    

  final_str &= "Thread react channels\n"
  await sleepAsync(100)

  for i in conf.discord.thread_react_channels:
    if "id" in i:
      continue
    try:
      var chan = (await discord.api.getChannel(i))[0].get()
      var guild = await discord.api.getGuild(chan.guild_id)
      
      final_str &= fmt"ID: {chan.id} Name: {chan.name} Server: {guild.name}"
      final_str &= '\n'
    except CatchableError as e:
      error("get-rooms-in-config failed getting channel: " & e.msg)
      continue

  final_str &= "Dedupe channels\n"
  await sleepAsync(100)

  for i in conf.discord.dedupe_channels:
    if "id" in i:
      continue
    try:
      var chan = (await discord.api.getChannel(i))[0].get()
      var guild = await discord.api.getGuild(chan.guild_id)
      
      final_str &= fmt"ID: {chan.id} Name: {chan.name} Server: {guild.name}"
      final_str &= '\n'
    except CatchableError as e:
      error("get-rooms-in-config failed getting channel: " & e.msg)
      continue
  
  final_str &= "Categories to summarize\n"
  await sleepAsync(100)

  for i in conf.discord.pin_categories2sum:
    if "id" in i:
      continue
    try:
      var chan = (await discord.api.getChannel(i))[0].get()
      var guild = await discord.api.getGuild(chan.guild_id)
      
      final_str &= fmt"ID: {chan.id} Name: {chan.name} Server: {guild.name}"
      final_str &= '\n'
    except CatchableError as e:
      error("get-rooms-in-config failed getting channel: " & e.msg)
      continue
  
  final_str &= "Cultured channels\n"
  await sleepAsync(100)

  for i in conf.discord.cultured_channels:
    if "id" in i:
      continue
    try:
      var chan = (await discord.api.getChannel(i))[0].get()
      var guild = await discord.api.getGuild(chan.guild_id)

      final_str &= fmt"ID: {chan.id} Name: {chan.name} Server: {guild.name}"
      final_str &= '\n'
    except CatchableError as e:
      error("get-rooms-in-config failed getting channel: " & e.msg)
      continue
  
  if final_str.len < 2000:
    discard await msg.reply(final_str)
  else:
    var fil = @[DiscordFile(name: "rooms-in-config.txt", body: final_str)]
    discard await discord.api.sendMessage(msg.channel_id, files=fil)

cmd.addChat("sum-pins") do ():
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 2:
    return

  let room_id = msg.channel_id

  var pin_sum = await sum_channel_pins(discord, guild_id, room_id, pin_cache, false, true)

  var fil = @[DiscordFile(name: pin_sum[2] & "_piny.md", body: pin_sum[0])]

  if conf.utils.md2pdf:
    var pdf_path = await convert_md2pdf(pin_sum[0])
    if pdf_path != "":
      fil &= DiscordFile(name: pin_sum[2] & "-piny.pdf", body: readFile(pdf_path))

  discard await discord.api.sendMessage(msg.channel_id, files=fil)

cmd.addChat("create-role-everywhere") do (role_name: string, role_position: int, role_color: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return

  var f = 0
  for g in guild_ids:
    await sleepAsync(100)
    try:
      var role_position = role_position
      if role_position < 0:
        var roles = query.get_all_roles(g).get()
        role_position = roles.len + role_position

      var role = await discord.api.createGuildRole(g, role_name, color = parseHexInt(role_color))
      discard await discord.api.editGuildRolePosition(g, role.id, some role_position)
    except CatchableError as e:
      error("create-role-everywhere failed creating role: " & e.msg)
      discard msg.reply("Failed creating role in " & g)
      f += 1
      continue
  if f == 0:
    discard msg.reply("Role created")
  else:
    discard msg.reply("Role created in " & $(guild_ids.len - f) & " out of " & $guild_ids.len & " servers")

cmd.addChat("remove-role-everywhere") do (role_name: string):
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return

  var f = 0
  for g in guild_ids:
    await sleepAsync(100)
    try:
      var role = await get_role_id_by_name(g, role_name)
      await discord.api.deleteGuildRole(g, role)
    except CatchableError as e:
      error("remove-role-everywhere failed deleting role: " & e.msg)
      discard msg.reply("Failed deleting role in " & g)
      f += 1
      continue
  if f == 0:
    discard msg.reply("Role deleted")
  else:
    discard msg.reply("Role deleted in " & $(guild_ids.len - f) & " out of " & $guild_ids.len & " servers")

cmd.addChat("sync-sis-roles") do ():
  if msg.guild_id.isNone:
    return
  let guild_id = msg.guild_id.get()
  if query.get_user_power_level(guild_id, msg.author.id) <= 3:
    return

  var sync_res = await give_all_users_sis_role()
  if sync_res == (0,0):
    discard await msg.reply("Syncing roles failed")
  elif sync_res[0] == 0:
    discard await msg.reply("Syncing roles with SIS done")
  else:
    discard await msg.reply("Syncing roles with SIS done, " & $sync_res[0] & " users failed out of " & $sync_res[1])
  

proc onReady(s: Shard, r: Ready) {.event(discord).} =
  for g in r.guilds:
    if g.unavailable:
      guild_ids.add(g.id)
      await sync_roles(g.id)
      await sync_channels(g.id)

  await cmd.registerCommands()

  const buildInfo = "Commit " & staticExec("git rev-parse --short HEAD")

  await s.updateStatus(activity = some ActivityStatus(
        name: "Custom Status",
        state: some buildInfo,
        kind: atCustom
    ))
  
  info("Ready as " & $r.user & " in " & $guild_ids.len & " guilds running " & buildInfo)

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
    let ver_role = await get_role_id_by_name(g.id, conf.discord.verified_role)
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
      try:
        await discord.api.addGuildMemberRole(guild_id, user_id, role_to_give)
      except CatchableError as e:
        error(fmt"Failed giving user {user_id} in guild {guild_id} role {role_to_give}: {e.msg} {$e.trace}" )
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
          over_perms[user_id].kind = otMember
          over_perms[user_id].allow = {permViewChannel}
          over_perms[user_id].deny = {}
        else:
          if over_perms[user_id].kind == otMember:
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
        if over_perms[user_id].kind == otMember:
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


# Delete reaction to enter threads
proc threadDelete(s: Shard, g: Guild, c: GuildChannel, exists: bool) {.event(discord).} =
  let thread_id = c.id
  if c.kind == ctGuildPrivateThread:
    if c.parent_id.isNone:
      return
    
    let thread_q = query.get_react_msg_by_thread(g.id, c.parent_id.get(), thread_id)
    if thread_q.isNone:
      return
    try:
      await discord.api.deleteMessageReactionEmoji(c.parent_id.get(), thread_q.get()[0], thread_q.get()[1])
      await sleepAsync(50)
    except CatchableError as e:
      error(e.msg)
    if query.delete_reaction_thread(g.id, thread_id):
      info(fmt"Reactions to thread {thread_id} deleted from DB")
      return


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

# Invalidates pin cache
proc channelPinsUpdate(s: Shard, cid: string, g: Option[Guild], last_pin: Option[string])  {.event(discord).} =
  #echo pin_cache
  pin_cache.del(cid)
  #echo pin_cache

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
    if (await check_msg_for_verification_code(content, author_id)) == true:
      discard query.update_verified_status(author_id, 2)
      for g in guild_ids:
        let ver_role = await get_role_id_by_name(g, conf.discord.verified_role)
        try:
          await discord.api.addGuildMemberRole(g, author_id, ver_role)
        except CatchableError as e:
          error(fmt"Failed giving user {author_id} in guild {g} role {ver_role}: {e.msg} {$e.trace}" )
      discard await give_user_sis_role(author_id)
      discard await msg.reply("Vítej na našem serveru")

  if ch_type[0].isSome:
    # Handle media in dedupe channels
    if room_id in conf.discord.dedupe_channels:
      for em in msg.embeds:
        var att = embed_to_attachment(em)
        if att.isSome:
          msg.attachments &= att.get()
      for a in msg.attachments:
        var dedupe_res = await dedupe_media(guild_id, room_id, msg_id, a)
        if dedupe_res[0] == true:
          var msg_med_ids = dedupe_res[2].split("|")
          var flagged_msg = await discord.api.getChannelMessage(room_id, msg_med_ids[0])
          var med_url = ""
          for em in flagged_msg.embeds:
            var att = embed_to_attachment(em)
            if att.isSome:
              flagged_msg.attachments &= att.get()
          for f in flagged_msg.attachments:
            if f.url.rfind(msg_med_ids[1]) >= 0:
              med_url = f.url
          var imgemb = EmbedImage(url: med_url)
          var msg_url = "https://discord.com/channels/" & guild_id & "/" & room_id & "/" & msg_med_ids[0]
          var desc = fmt"Tento meme se shoduje ze {dedupe_res[1]}% s jiným. Pokud tak není klikněte na ❎"
          var emb = Embed(title: some "Repost", description: some desc, image: some imgemb, footer: some EmbedFooter(text: msg_id))
          var sent_msg = await discord.api.sendMessage(room_id, content = msg_url, embeds = @[emb], message_reference = some MessageReference(channel_id: some room_id, message_id: some msg_id))
          await discord.api.addMessageReaction(room_id, sent_msg.id, "❎")
    if room_id in conf.discord.cultured_channels:
      echo "cultured"

proc messageDelete(s: Shard, m: Message, exists: bool) {.event(discord).} =
  let room_id = m.channel_id
  let msg_id = m.id
  var guild_id = ""
  if m.guild_id.isSome:
    guild_id = m.guild_id.get()
  var ch_type = await discord.api.getChannel(room_id)

  if ch_type[0].isSome:
    # Handle removal of media in dedupe channels
    if room_id in conf.discord.dedupe_channels:
      discard query.delete_media_message(guild_id, room_id, msg_id)

      # Scan messages for repost embeds
      let messages = await discord.api.getChannelMessages(room_id, after = msg_id)

      for ms in messages:
        if not ms.author.bot: continue
        try:
          if ms.embeds.len == 1:
            let emb_msg_id = ms.embeds[0].footer.get().text
            if emb_msg_id == msg_id:
              await discord.api.deleteMessage(room_id, ms.id)
              break
        except: # Naughty
          continue

    # Remove react 2 roles/threads
    if room_id in conf.discord.reaction_channels:
      discard query.delete_reaction_message(guild_id, room_id, msg_id)
      discard query.delete_chan_react_message(guild_id, room_id, msg_id)
    
    if room_id in conf.discord.thread_react_channels:
      var threads = query.get_threads_by_message(guild_id, room_id, msg_id)
      if threads.isNone:
        return
      discard query.delete_reaction2thread_message(guild_id, room_id, msg_id)
      for thread_id in threads.get():
        await discord.api.deleteChannel(thread_id)
        await sleepAsync(100)

import smtp
import std/strutils
import std/random
import std/strformat
import asyncdispatch
import std/logging
import std/httpclient
import std/options

import ../config
import ../db/queries
import ../utils/my_utils
import ../utils/data_structs

import ../utils/logging as clogger

var conf = conf.email

proc gen_random_code(len: int): string =
  randomize()
  let chars = {'a'..'z','A'..'Z', '0'..'9'}# or {' '..'~'} for all ascii
  var code = newString(len)
  for i in 0..<len:
    code[i] = sample(chars)

proc get_verification_code*(login: string): string =
  result = get_user_verification_code(login)
  if result == "":
    var code = gen_random_code(10)

    discard insert_code(login, code)
    discard update_verified_status_login(login, 1)
    result = $code

proc send_verification_mail*(login: string): Future[bool] {.async} =
  var code = gen_random_code(10)

  discard insert_code(login, code)
  discard update_verified_status_login(login, 1)

  var headers = [("From", conf.user)]#, ("MIME-Version", "1.0"), ("Content-Type", "plain/text")]

  var msg = createMessage("Kod pro LF1 Discord",
                        fmt"Ahoj. Zde je tvůj ověřovací kód: {code}. Napiš ho botovi do DM ve formátu: !overit <kod>  (bez zobáčků)",
                        @[fmt"{login}@{conf.verify_domain}"], @[""], headers)
  try:
    let smtpConn = newAsyncSmtp(useSsl = conf.ssl)
    await smtpConn.connect(conf.address, Port conf.port)
    await smtpConn.auth(conf.user.split('@')[0], conf.password)
    await smtpConn.sendmail(conf.user, @[fmt"{login}@{conf.verify_domain}"], $msg)
    await smtpConn.close()
    return true
  except CatchableError as e:
    error("Email not sent" & e.msg & '\n' & $e.trace)
    return false

proc parse_sis_for_user(author_id: string): Future[bool] {.async} =
  var dbuser = get_user(author_id)
  var login: string
  if dbuser.isNone:
    return false
  login = dbuser.get().login
  var facult = $ord(dbuser.get().faculty)
  var url_base = "https://is.cuni.cz/studium"
  var search_url = fmt"{url_base}/kdojekdo/index.php?do=hledani&koho=s&fakulta={facult}&prijmeni=&jmeno=&login=&sidos={login}&r_zacatek=Z&sustav=&sobor_mode=text&sims_mode=text&sdruh=&svyjazyk=&pocet=50&vyhledej=Vyhledej"
  #echo search_url

  var wclient = newAsyncHttpClient()
  var content: string
  try:
    content = await wclient.getContent(search_url)
  except CatchableError as e:
    error("Couldn't download sis search page " & e.msg)
    return false

  #echo content
  var user_url = extractBetween(content, "</a></td><td><a href=", "class=\"link3\"")
  user_url = url_base & extractBetween(user_url, "\"..", "\"").replace("&amp;", "&")
  #echo user_url

  var user_page: string
  try:
    user_page = await wclient.getContent(user_url)
  except CatchableError as e:
    error("Couldn't download sis search page " & e.msg)
    return false

  var user_page_table = extractBetween(user_page, "\"tab2\"><tr>", "</table>")
  #echo user_page_table

  var code = extractBetween(extractBetween(user_page_table, "Pokoj:</th>", "/td>"), "<td>", "<")
  if code != get_user_verification_code(author_id):
    return false

  var uco = extractBetween(extractBetween(user_page_table, "(UKČO):</th>", "/td>"), "<td>", "<")
  if uco != login:
    return false

  var surname = extractBetween(extractBetween(user_page_table, "Příjmení:</th>", "/td>"), "<td>", "<")

  var name = extractBetween(extractBetween(user_page_table, "Jméno:</th>", "/td>"), "<td>", "<")

  var study_type = extractBetween(extractBetween(user_page_table, "Druh studia:</th>", "/td>"), "<td>", "<")

  var study_branch = extractBetween(extractBetween(user_page_table, "Studijní obor:</th>", "/td>"), "<td>", "<")

  var year: int
  var circle: int
  var facultynew: Faculty

  try:
    year = parseInt(extractBetween(extractBetween(user_page_table, "Ročník:</th>", "/td>"), "<td>", "<"))
    circle = parseInt(extractBetween(extractBetween(user_page_table, "Studijní skupina:</th>", "/td>"), "<td>", "<"))
    facultynew = parseEnum[Faculty](extractBetween(extractBetween(user_page_table, "Fakulta:</th>", "/td>"), "<td valign=\"top\">", "<"))
  except CatchableError as e:
    error("Failed parsing", e.msg)

  if not update_user_info(author_id, fmt"{name} {surname}", facultynew, study_type, study_branch, year, circle):
    return false

  return true

proc check_msg_for_verification_code*(msg: string, author_id: string): Future[bool] {.async} =
  var str = msg.split(' ')
  if str[0] == "!overit":
    if not conf.use_mail:
      return await parse_sis_for_user(author_id)
    if str.len == 2:
      var db_code = get_user_verification_code(author_id)
      var ver_stat = get_user_verification_status(author_id)
      if db_code == str[1] and ver_stat == 1:
        return true
  return false

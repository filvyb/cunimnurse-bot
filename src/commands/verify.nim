import std/smtp
import std/strutils
import std/random
import std/strformat
import asyncdispatch

import ../config
import ../db/queries

var conf = conf.email

proc send_verification_mail*(login: string) {.async} =
  randomize()
  let chars = {'a'..'z','A'..'Z'}# or {' '..'~'} for all ascii
  var code = newString(12)
  for i in 0..<12:
    code[i] = sample(chars)

  discard insert_code(login, code)
  discard update_verified_status(login, 1)

  var headers = [("From", conf.user)]#, ("MIME-Version", "1.0"), ("Content-Type", "plain/text")]

  var msg = createMessage("Kod pro 1LF Discord",
                        fmt"Ahoj. Zde je tvuj overovaci kod: {code}. Napis mi ho do DM ve formatu: !overit <kod>  (bez zobacku)",
                        @[fmt"{login}@cuni.cz"], @[""], headers)
  let smtpConn = newAsyncSmtp(useSsl = conf.ssl)
  await smtpConn.connect(conf.address, Port conf.port)
  await smtpConn.auth(conf.user.split('@')[0], conf.password)
  await smtpConn.sendmail(conf.user, @[fmt"{login}@cuni.cz"], $msg)
  await smtpConn.close()

proc check_msg_for_verification_code*(msg: string, author_id: string): bool =
  var str = msg.split(' ')
  if str.len == 2 and str[0] == "!overit":
    var db_code = get_user_verification_code(author_id)
    var ver_stat = get_user_verification_status(author_id)
    if db_code == str[1] and ver_stat == 1:
      return true
  return false

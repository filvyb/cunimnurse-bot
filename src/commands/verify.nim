import std/smtp
import std/strutils
import std/sequtils
import std/random
import std/strformat

import ../config
import ../db/queries

var conf = conf.email

proc send_verification_mail*(login: string) =
  let chars = {'a'..'z','A'..'Z'}# or {' '..'~'} for all ascii
  var code = newString(8)
  for i in 0..<8:
    code[i] = sample(chars)

  discard insert_code(login, code)
  discard update_verified_status(login, 1)

  var msg = createMessage("Hello from Nim's SMTP",
                        fmt"Hello!.\n Is this awesome or what? Your code is {code}",
                        @[fmt"{login}@cuni.cz"])
  let smtpConn = newSmtp(useSsl = conf.ssl, debug=true)
  smtpConn.connect(conf.address, conf.port)
  smtpConn.auth(conf.user.split('@')[0], conf.password)
  smtpConn.sendmail(conf.user, @[fmt"{login}@cuni.cz"], $msg)
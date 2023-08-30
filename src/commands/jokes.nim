import std/httpclient
import std/asyncdispatch
import std/logging
import std/json
import std/strformat
import std/strutils

import ../utils/logging as clogger

proc get_mom_joke*(): Future[string] {.async.} =
  var client = newAsyncHttpClient()
  var resp: AsyncResponse
  try:
    resp = await client.request("https://api.yomomma.info/")
  except CatchableError as e:
    error(fmt"Getting yo mama joke failed, error {e.msg}")
    return "Yo mama so fat, and old, that when God said “Let there be light,” he was just asking her to move out of the way."
  if resp.status == "200 OK":
    let thejoke = await resp.bodyStream.read()
    if thejoke[0] == true:
      let jokeson = parseJson(thejoke[1])
      return jokeson["joke"].getStr()
  else:
    error(fmt"Getting yo mama joke failed, error {resp.status}")
    return "Yo mama so fat, and old, that when God said “Let there be light,” he was just asking her to move out of the way."

proc get_dad_joke*(): Future[string] {.async.} =
  var client = newAsyncHttpClient()
  var resp: AsyncResponse
  try:
    client.headers = newHttpHeaders({ "Accept": "application/json", "User-Agent": "Discord bot (https://github.com/filvyb/cunimnurse-bot)" })
    resp = await client.request("https://icanhazdadjoke.com/")
  except CatchableError as e:
    error(fmt"Getting dad joke failed, error {e.msg}")
    return "Dad died because he couldn't remember his blood type. I will never forget his last words. Be positive."
  let thejoke = await resp.bodyStream.read()
  echo resp.repr
  if thejoke[0] == true:
    let jokeson = parseJson(thejoke[1])
    return jokeson["joke"].getStr()
  else:
    error(fmt"Getting dad joke failed, error {resp.status}")
    return "Dad died because he couldn't remember his blood type. I will never forget his last words. Be positive."

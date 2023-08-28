from dimscord import Embed, EmbedThumbnail, EmbedField

import asyncdispatch
import std/strformat
import std/httpclient
import std/strutils
import std/logging
import std/json
import std/options

import ../config
import ../utils/logging as clogger

let conf = config.conf

proc get_weather*(place: string): Future[(int, Embed)] {.async.} =
  if '&' in place:
    return (1, Embed())

  var url = fmt"http://api.openweathermap.org/data/2.5/weather?q={place}&units=metric&lang=cz&appid={conf.utils.openweather_token}"

  var client = newAsyncHttpClient()
  var response = await client.post(url)

  var o = await readAll(response.bodyStream)

  if o.len == 0:
    warn("Couldn't get weather request body")
    return (0, Embed())

  var s = cast[int](response.code())

  if s == 200:
    let p = parseJson(o)
    var desc = "Aktuální počasí v městě " & p["name"].getStr() & ", " & p["sys"]["country"].getStr()
    var emb = Embed(title: some "Počasí", description: some desc)
    emb.thumbnail = some EmbedThumbnail(url: "http://openweathermap.org/img/w/" & p["weather"][0]["icon"].getStr() & ".png")

    var weather = p["weather"][0]["main"].getStr() & " (" & p["weather"][0]["description"].getStr() & ")"
    var temp = $p["main"]["temp"].getFloat() & "°C"
    var feels_temp = $p["main"]["feels_like"].getFloat() & "°C"
    var humidity = $p["main"]["humidity"].getInt() & "%"
    var wind = $p["wind"]["speed"].getFloat() & "m/s"
    var clouds = $p["clouds"]["all"].getInt() & "%"
    var visibility: string
    if p.hasKey("visibility"):
      visibility = $(p["visibility"].getInt() / 1000) & "km"
    else:
      visibility = "bez dat"

    var fields: seq[EmbedField]
    fields &= EmbedField(name: "Počasí", value: weather)
    fields &= EmbedField(name: "Teplota", value: temp, inline: some true)
    fields &= EmbedField(name: "Pocitová teplota", value: feels_temp, inline: some true)
    fields &= EmbedField(name: "Vlhkost", value: humidity, inline: some true)
    fields &= EmbedField(name: "Vítr", value: wind, inline: some true)
    fields &= EmbedField(name: "Oblačnost", value: clouds, inline: some true)
    fields &= EmbedField(name: "Viditelnost", value: visibility, inline: some true)
    emb.fields = some fields

    return (s, emb)
  else:
    return (s, Embed())
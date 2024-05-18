from dimscord import Attachment
import dhash
import asynctools

import options
import std/asyncdispatch
import std/logging
import std/strformat
import std/strutils
import std/httpclient

import ../db/queries
import ../utils/logging as clogger

proc dedupe_media*(guild_id, channel_id, message_id: string, attach: Attachment): Future[(bool, int, string)] {.async.} =
  var file_path: string

  if attach.content_type.isSome:
    let ext = attach.url.rsplit(".", 1)[1]
    file_path = "/tmp/" & attach.id & "." & ext
    if attach.content_type.get() in ["image/jpeg", "image/png"]:
      try:
        var client = newAsyncHttpClient()
        await client.downloadFile(attach.url, file_path)

      except CatchableError as e:
        error(e.msg)
        return (false, 0, "")
    if attach.content_type.get() in ["video/mp4", "video/ogg", "video/webm", "image/gif", "image/webp"]:
      try:
        var client = newAsyncHttpClient()
        await client.downloadFile(attach.url, file_path)


        var ffmpeg_out_tmp = await execProcess(fmt"ffmpeg -i {file_path} -vf 'blackdetect=d=0.05:pix_th=0.67' -an -f null - 2>&1 | grep blackdetect")
        var ffmpeg_out = (ffmpeg_out_tmp.output, ffmpeg_out_tmp.exitcode)

        var cut_time = ""

        if ffmpeg_out[1] == 0:
          var ffmpeg_out_split = ffmpeg_out[0].split({'\n', '\r'})
          
          if ffmpeg_out_split.len != 1:
            var start_time = ffmpeg_out_split[1].splitWhitespace()[3].split({':'})[1]
            if start_time == "0":
              cut_time &= "-ss "
              cut_time &= ffmpeg_out_split[1].splitWhitespace()[4].split({':'})[1] & " "

        var ffmpeg_thumb_out_tmp = await execProcess(fmt"ffmpeg -i {file_path} {cut_time}-frames:v 1 /tmp/{attach.id}.png -y")
        var ffmpeg_thumb_out = (ffmpeg_thumb_out_tmp.output, ffmpeg_thumb_out_tmp.exitcode)

        if ffmpeg_thumb_out[1] != 0:
          return (false, 0, "")

        file_path = "/tmp/" & attach.id & ".png"

      except CatchableError as e:
        error(e.msg)
        return (false, 0, "")
  else:
    return (false, 0, "")

  let grays = get_grays(file_path, 16, 16)
  let query_res = get_media_distance(guild_id, channel_id, grays)

  discard insert_media(guild_id, channel_id, message_id, attach.id, grays)

  if query_res.isNone:
    return (false, 0, "")


  var duplicate_med = query_res.get()[0] & "|" & query_res.get()[1]

  let distance = parseFloat(query_res.get()[2])

  # 800 is randomly selected, but in my testing should be about 25% difference
  if distance < 800:
    return (true, int((1 - distance / 3200) * 100), duplicate_med)
  return (false, 0, "")

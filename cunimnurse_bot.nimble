# Package

version       = "0.1.0"
author        = "Filip Vybihal"
description   = " Discord bot for 1LFCUNI written in Nim "
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["cunimnurse_bot"]


# Dependencies

requires "nim >= 1.6.10"
requires "parsetoml >= 0.7.0"
requires "https://github.com/krisppurg/dimscord#b2f9f19"
requires "https://github.com/ire4ever1190/dimscmd#99a5151"

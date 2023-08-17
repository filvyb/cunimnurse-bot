# Package

version       = "0.2.0"
author        = "Filip Vybihal"
description   = " Discord bot for 1LFCUNI written in Nim "
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["cunimnurse_bot"]


# Dependencies

requires "nim >= 2.0.0"
requires "parsetoml >= 0.7.1"
requires "dimscord#head"
requires "dimscmd >= 1.4.0"
requires "dhash >= 2.1.1"
requires "asyncthreadpool#head"
requires "zip#head"
requires "smtp"
requires "dbconnector"
requires "asynctools#head"

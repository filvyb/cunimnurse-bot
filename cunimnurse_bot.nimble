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
requires "dimscord#0ba8315"
requires "dimscmd >= 1.4.1"
requires "dhash >= 2.1.1"
requires "stdx >= 0.2.3"
requires "zip#06f5b0a"
requires "smtp#8013aa199dedd04905d46acf3484a232378de518"
requires "asynctools#a1a17d0"
requires "https://github.com/filvyb/pg#c53addc"

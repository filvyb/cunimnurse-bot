import std/times

type
  VerStatus* = enum
    unverified = 0
    pending = 1
    verified = 2
    banned = 3
    jailed = 4
  UserPower* = enum
    unverified = 0
    verified = 1
    helper = 2
    moderator = 3
    admin = 4
  Faculty* = enum
    unknown = (0, "Unknown")
    lf1 = (11110, "1. lékařská fakulta")
  DbUser* = object
    id*: string
    login*: string
    name*: string
    code*: string
    status*: VerStatus
    uni_pos*: int
    joined*: DateTime
    karma*: int64
    faculty*: Faculty
    study_type*: string
    study_branch*: string
    year*: int
    circle*: int

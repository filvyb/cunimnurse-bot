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
    ## Coresponds to the faculty code in https://is.cuni.cz/studium/kdojekdo/index.php?do=hledani
    unknown = (0, "Unknown")
    uk = (11000, "UNIVERZITA KARLOVA")
    lf1 = (11110, "1. lékařská fakulta")
    lf3 = (11120, "3. lékařská fakulta") # who designed this?
    lf2 = (11130, "2. lékařská fakulta")
    lfp = (11140, "Lékařská fakulta v Plzni")
    lfhk = (11150, "Lékařská fakulta v Hradci Králové")
    fmf = (11160, "Farmaceutická fakulta v Hradci Králové")
    ff = (11210, "Filozofická fakulta")
    pf = (11220, "Právnická fakulta")
    fsv = (11230, "Fakulta sociálních věd")
    fhs = (11240, "Fakulta humanitních studií")
    ktf = (11260, "Katolická teologická fakulta")
    etf = (11270, "Evangelická teologická fakulta")
    htf = (11280, "Husitská teologická fakulta")
    pvf = (11310, "Přírodovědecká fakulta")
    matfyz = (11320, "Matematicko-fyzikální fakulta")
    pedf = (11410, "Pedagogická fakulta")
    fs = (11510, "Fakulta tělesné výchovy a sportu")
    uduk = (11610, "Ústav dějin University Karlovy a archiv Univerzity Karlovy")
    cts = (11620, "Centrum pro teoretická studia")
    cpevds = (11640, "Centrum pro ekonomický výzkum a doktorské studium")
    ujop = (11670, "Ústav jazykové a odborné přípravy")
    uknih = (11680, "Ustřední knihovna")
    czp = (11690, "Centrum pro otázky životního prostředí")
    cpppt = (11710, "Centrum pro přenos poznatků do praxe a technologií")
    rekt = (11901, "Rektorát Univerzity Karlovy")

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

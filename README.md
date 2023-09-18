# cunimnurse-bot
Discord bot for 1LFCUNI written in Nim

## Features
- Multi-server
- Email domain verification (verification shared among all joined servers)
- Reaction to get role or channel access
- Create threads with prefix and access them with a reaction
- Syncs bans between servers
- Vote to add message to pins
- Bookmarks
- Media deduping
- Pin summary

## Usage
### Prerequisites:
* Postgresql (tested on 15, but should run on 10+)
* [pgvector](https://github.com/pgvector/pgvector)
* [Nim Lang](https://nim-lang.org/install.html) 2.0.0
* OpenSSL
* FFmpeg
* grep
* ziplib
* Optional: Python3 with [undetected-chromedriver](https://github.com/ultrafunkamsterdam/undetected-chromedriver)

### Build or install
Clone the repo
```bash
git clone https://github.com/filvyb/cunimnurse-bot.git
cd cunimnurse-bot
```
You can build it with
```bash
nimble build -d:discordCompress -d:release
```
or build and immidietly install it with
```bash
nimble install -d:discordCompress -d:release
```

### Running
Config path defaults to `config.toml`. To use a different path set the path as an argument.

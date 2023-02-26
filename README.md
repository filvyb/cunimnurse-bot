# cunimnurse-bot
Discord bot for 1LFCUNI written in Nim

## Usage
### Prerequisites:
* Postgresql
* [Nim Lang](https://nim-lang.org/install.html) 1.6.10 or higher (should work with lower versions but I'm not testing it)
* OpenSSL
* Optional: Python3 with [undetected-chromedriver](https://github.com/ultrafunkamsterdam/undetected-chromedriver)

### Build or install
Clone the repo
```bash
git clone https://github.com/filvyb/cunimnurse-bot.git
cd cunimnurse-bot
```
You can build it with
```bash
nimble build -d:ssl -d:discordCompress -d:release
```
or build and immidietly install it with
```bash
nimble install -d:ssl -d:discordCompress -d:release
```

### Running
Config path defaults to `config.toml`. To use a different path set the path as an argument.
# cunimnurse-bot
Discord bot for 1LFCUNI written in Nim

## Usage
### Prerequisites:
* Postgresql (tested on 15, but should run on 10+)
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


#### Multi-server setup
This bot is meant for a single server, however due to needs of LF1 CUNI Discord and my laziness to rewrite the bot to support multiple servers I've came up with this solution. 

The verification information can be shared accross from a master server to other server with PostgreSQL's logical replication. Each server still runs it's own bot, but config option `slave = true` must be set when initiating databases of the slave bots.

1. Set `wal_level = logical` in `postgresql.conf` 
2. Initialize all your databases
3. Give your Postgres user replication permission with `alter role <role> replication;`
4. Create publication on your master database with `create publication <publication_name> for table verification;`
5. Optional: If all your databases run on a single cluster you need to create publication slots on your master database for each slave database with `select pg_create_logical_replication_slot('<slot_name>', 'pgoutput');`
6. On each slave database subscribe to your created publication `create subscription <subscribtion_name> connection 'dbname=<master_database> host=<host> port=5432 user=<user> password=<password>' publication <publication_name>;`. Add ` with (slot_name=<slot_name>, create_slot=false)` if you did step 5.

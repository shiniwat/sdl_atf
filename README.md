# Automated Test Framework (ATF)

## Dependencies:
Library                | License
---------------------- | -------------
**Lua libs**           |
liblua5.2              | MIT
json4lua               | MIT
lua-stdlib             | MIT
lua-lpeg               |
**Qt libs**            |
Qt5.3 WebSockets       | LGPL 2.1
Qt5.3 Network          | LGPL 2.1
Qt5.3 Core             | LGPL 2.1
Qt5.3 Test             | LGPL 2.1
**Other libs**         |
lpthread               | LGPL
OpenSSL (ssl, crypto)  | OpenSSL License
libxml2                | MIT
ldoc                   | MIT/X11

## Get source code:
```
git clone https://github.com/smartdevicelink/sdl_atf
cd sdl_atf
git submodule init
git submodule update
```
## Compilation:
**1** Install 3d-parties developers libraries
```
sudo apt-get install liblua5.2-dev libxml2-dev lua-lpeg-dev
sudo apt-get install openssl
```

**2** Install Qt5.3+

[Download Qt5.3+](https://download.qt.io/archive/qt/5.3/5.3.1/)
```
sudo chmod +x some-qt-build.run
./some-qt-build.run
```

**3** Build ATF
- Create build directory and get into it
- Run `cmake <path_to_sources>`
- Run `make`

## Configuration of ATF
ATF configuration is setting up in `modules/configuration` folder.
- `base_config.lua` : base configuration parameters (reporting, paths to SDL e.t.c)
- `connection_config.lua` : configuration parameters related to all connections (mobile, hmi, remote)
- `security_config.lua` : configuration parameters related to security layer of connection
- `app_config.lua` : predefined applications parameters
Each folder in this folder represents values of `--config` option for ATF run: `local`, `remote_linux`, `remote_qnx`
They can override one or more described configuration files.

## Run:
```
./start.sh [--config=<config_name>] [options] [script file name]
```

where <config_name> is one of the following values: `local`, `remote_linux`, `remote_qnx`

## Documentation generation
### Download and install [ldoc](stevedonovan.github.io/ldoc/manual/doc.md.html)
```
sudo apt install luarocks
sudo luarocks install luasec
sudo luarocks install penlight
sudo luarocks install ldoc
sudo luarocks install discount
```
### Generate ATF documentation
```
cd sdl_atf
ldoc -c docs/config.ld .
```
### Open documentation
```chromium-browser docs/html/index.html```

### Useful options:
#### Path to SDL
You can setup path to SDL via command line with ```--sdl-core``` option.

**Example :**
```
./start.sh --sdl-core=/home/user/development/sdl/build/bin ./test_scripts/ActivationDuringActiveState.lua
```

Or via config file(```modules/base_config.lua```) with config parameter

**Example :**
*ATF config : modules/config.lua :*
```
config.pathToSDL = "home/user/development/sdl/build/bin"
```
Usage example:
```
./start.sh -clocal_config.lua ATF_script.lua
```

#### Connect ATF to already started SDL
ATF is able to connect to already started SDL.
Note that you should be sure that:
 - ATF is configured not to start SDL
 - SDL is configured not to start HMI
 - mobile and HMI sockets options match each other in SDL and ATF configs.

**Example :**

*ATF config : modules/base_config.lua :*
```
config.autorunSDL = false
config.hmiUrl = "ws://localhost"
config.hmiPort = 8087
config.mobileHost = "localhost"
config.mobilePort = 12345
```

*SDL config : smartDeviceLink.ini :*
```
[HMI]
; Open the $LinkToWebHMI in chromium browser
LaunchHMI = false
; WebSocket connection address and port
ServerAddress = 127.0.0.1
ServerPort = 8087
[TransportManager]
; Listening port form incoming TCP mobile connection
TCPAdapterPort = 12345
```
## Run tests
``` make test```

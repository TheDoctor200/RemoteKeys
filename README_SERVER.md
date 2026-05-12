# RemoteKeys Server - Companion Application

A native macOS companion app for the RemoteKeys iOS application. This app provides a WebSocket server that allows you to control your Mac via keyboard, mouse, trackpad, and terminal commands from your iPhone.

## Features

- 🎮 **One-Click Server Control**: Simple on/off toggle to start/stop the WebSocket server
- ⚡ **Auto-Launch on Startup**: Optional automatic server startup when Mac boots
- 🔌 **Full Protocol Support**: Handles keyboard input, mouse movement, trackpad gestures, terminal commands
- 📊 **Device Monitoring**: Reports CPU usage, battery level, and Mac name
- 🛡️ **Accessibility Permissions**: Smart prompting for required macOS permissions
- 📝 **Activity Logs**: View recent server events and status

## Installation

### Prerequisites

- macOS 11.0 or later
- Python 3.8+ installed (via Homebrew, official installer, or pyenv)
- Xcode 13+ (to build the Swift app from source)

### Step 1: Install Python Dependencies

```bash
pip3 install -r requirements.txt
```

Or individually:
```bash
pip3 install websockets>=10.0 pyobjc>=9.0 psutil>=5.8
```

To use the lightweight Python control app:
```bash
pip3 install flet>=0.24.0
```

### Step 2: Build the macOS App

Open `RemoteKeysServer.xcodeproj` in Xcode (you'll need to create this via Xcode, or use the command line):

```bash
# Create Xcode project from command line (alternative to manual creation)
xcodebuild -scheme RemoteKeysServer -configuration Release
```

Or in Xcode:
1. Open `RemoteKeysServer.xcodeproj`
2. Select "RemoteKeysServer" scheme
3. Select "My Mac" as the build destination
4. Press Cmd+B to build

### Step 3: Grant Accessibility Permissions

The app will prompt you to grant accessibility permissions on first run. You can also manually grant them:

1. Open System Settings → Privacy & Security → Accessibility
2. Add "RemoteKeysServer" or "Xcode" (if running from Xcode) to the list

## Usage

### Starting the Server

1. Launch the **RemoteKeysServer** app
2. Click the **Start** button
3. The status indicator will turn green when the server is running
4. Open the RemoteKeys iOS app and connect to `localhost:8765`

### Auto-Launch Configuration

Enable the "Auto-start on Mac startup" toggle in the app settings. The server will automatically start when you boot your Mac.

### Manual Server Usage (Optional)

You can also run the Python server directly in a terminal:

```bash
python3 websocket_server_macos.py
```

The server will listen on `ws://0.0.0.0:8765` by default.

You can override bind host/port at runtime:

```bash
REK_HOST=0.0.0.0 REK_PORT=8765 python3 websocket_server_macos.py
```

### Python GUI Control App (Flet)

Run the small control window that auto-starts the server and lets you change host/port live:

```bash
python3 server_control_flet.py
```

The app shows your current local IP, active endpoint, and streams server logs.

## Protocol

The server implements the RemoteKeys WebSocket protocol, supporting:

### Client → Server Messages

- **Keyboard Input**: `{"type": "key", "keyCode": int, "modifiers": int, "keyType": "keyDown|keyUp"}`
- **Mouse Movement**: `{"type": "move", "dx": int, "dy": int}`
- **Mouse Click**: `{"type": "click", "button": "left|right|middle", "clickType": "single|double"}`
- **Scrolling**: `{"type": "scroll", "dx": int, "dy": int}`
- **Terminal**: `{"type": "terminal", "command": "shell command"}`
- **Trackpad Mode**: `{"type": "trackpad", "mode": "cursor|scroll"}`
- **Ping**: `{"type": "ping"}`

### Server → Client Messages

- **Device Info**: `{"type": "info", "mac_name": str, "cpu_usage": float, "battery_percentage": float}`
- **Terminal Output**: `{"type": "output", "output": str, "lines": [str]}`
- **Pong**: `{"type": "pong"}`

## Troubleshooting

### Server won't start

1. Check the activity logs in the app for error messages
2. Verify Python is installed: `python3 --version`
3. Verify dependencies are installed: `pip3 list | grep websockets`
4. Try running the server manually: `python3 websocket_server.py`

### Accessibility permissions denied

The app needs accessibility permissions to control your keyboard and mouse. Grant them in System Settings → Privacy & Security → Accessibility.

### iOS app can't connect

1. Make sure both devices are on the same Wi-Fi network
2. Verify the port number matches (default is 8765)
3. Check firewall settings aren't blocking port 8765
4. Try connecting to `ws://192.168.x.x:8765` instead of localhost if using a different device

### Process hangs when stopping

The app sends a graceful termination signal. If the server doesn't respond after 2 seconds, it will be forcefully terminated.

## Architecture

- **Python Backend** (`websocket_server.py`): 
  - WebSocket server using `websockets` library
  - macOS system integration via `PyObjC`
  - Handles all RemoteKeys protocol messages
  
- **Swift Frontend** (`RemoteKeysServer`):
  - Native macOS app with SwiftUI UI
  - Process management via `Foundation.Process`
  - Launch-on-login via `launchd`
  - Accessibility permission handling

## Development

### Running from Xcode

1. Open `RemoteKeysServer.xcodeproj`
2. Make sure `websocket_server.py` is in the project root
3. Press Cmd+R to run

### Modifying the Server

Edit `websocket_server.py` to add new message types or system interactions. All changes are reflected immediately when you restart the server.

### Modifying the UI

Edit files in `RemoteKeysServer/`:
- `ContentView.swift` - Main UI layout
- `ServerManager.swift` - Server control logic
- `LaunchAtLoginManager.swift` - Auto-launch logic

## Uninstallation

1. Delete the RemoteKeysServer app from Applications
2. (Optional) Remove launch agent: `rm ~/Library/LaunchAgents/com.remotekeys.server.plist`
3. (Optional) Uninstall Python dependencies: `pip3 uninstall websockets pyobjc psutil`

## License

Same license as RemoteKeys iOS app

## Support

For issues with the iOS app or protocol, see the main RemoteKeys repository.

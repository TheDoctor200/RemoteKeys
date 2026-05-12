# RemoteKeys Server - Project Structure & Files

## Created Files Overview

### 🐍 Python WebSocket Server
```
websocket_server.py          [Main server - listens on port 8765]
│
├─ System Controller
│  ├─ Keyboard events (PyObjC → Core Graphics)
│  ├─ Mouse movement & clicks
│  ├─ Scroll wheel events
│  └─ Terminal command execution
│
├─ Device Monitoring
│  ├─ CPU usage (psutil)
│  ├─ Battery level (psutil)
│  └─ Mac hostname
│
└─ Protocol Handler
   ├─ Incoming: key, move, scroll, click, terminal, trackpad, ping
   └─ Outgoing: info, output, pong
```

**Features:**
- ✅ Full RemoteKeys protocol support
- ✅ Graceful shutdown with signal handling
- ✅ Fallback when macOS libraries missing
- ✅ Terminal output buffering (200 line limit)
- ✅ Ping/pong latency measurement
- ✅ Comprehensive logging

**Dependencies:**
- `websockets>=10.0` - WebSocket protocol
- `pyobjc>=9.0` - macOS system APIs
- `psutil>=5.8` - System monitoring

---

### 🍎 macOS Swift App
```
RemoteKeysServer/
│
├─ RemoteKeysServer.swift       [App entry point]
│
├─ ContentView.swift            [User Interface]
│  ├─ Start/Stop button
│  ├─ Server status indicator
│  ├─ Port configuration
│  ├─ Auto-launch toggle
│  ├─ Accessibility permission warning
│  └─ Activity log viewer
│
├─ ServerManager.swift          [Process Control]
│  ├─ Start/stop server
│  ├─ Monitor process status
│  ├─ Find Python executable
│  ├─ Locate server script
│  ├─ Log management
│  └─ Permission checking
│
├─ LaunchAtLoginManager.swift   [Startup Automation]
│  ├─ Create launchd plist
│  ├─ Register with launchd
│  ├─ Enable/disable auto-launch
│  └─ Check auto-launch status
│
├─ AccessibilityPermissions.swift [Permission Handling]
│  ├─ Check permission status
│  ├─ Request permissions
│  └─ Open System Settings
│
└─ Info.plist                   [Configuration]
   ├─ Bundle identifier
   ├─ Accessibility usage description
   ├─ Local network usage
   └─ Deployment target
```

**Features:**
- ✅ One-click server control
- ✅ Real-time status monitoring
- ✅ Auto-launch configuration
- ✅ Activity logging
- ✅ Accessibility permission handling
- ✅ Graceful process termination
- ✅ Settings persistence

**Architecture:**
- SwiftUI for UI
- @StateObject for state management
- @EnvironmentObject for dependency injection
- Process management via Foundation.Process
- Asynchronous logging with DispatchQueue

---

### 📦 Configuration Files

**requirements.txt**
```
websockets>=10.0
pyobjc>=9.0
psutil>=5.8
```
Python package dependencies

**Info.plist**
- Bundle ID: `com.remotekeys.server`
- Minimum macOS: 11.0
- Accessibility description
- Local network usage description

---

### 📚 Documentation

**README_SERVER.md**
- Complete feature overview
- Installation instructions
- Usage guide
- Protocol documentation
- Troubleshooting
- Architecture explanation
- Development notes

**QUICKSTART.md**
- 5-minute setup guide
- File structure explanation
- Quick troubleshooting
- Testing instructions
- Next steps

**PROJECT_STRUCTURE.md** (this file)
- Overview of all components
- File purposes
- Architecture summary

---

### 🔧 Setup Tools

**setup.sh**
```bash
./setup.sh
```
Automated setup that:
1. Checks Python installation
2. Installs pip dependencies
3. Tests server startup
4. Guides Xcode project creation

**setup_xcode_project.sh**
- Optional advanced setup
- Project creation helpers

---

## Communication Flow

```
iOS RemoteKeys App
       ↓ (WebSocket)
    localhost:8765
       ↓
Python websocket_server.py
       ├─ Parses JSON messages
       ├─ Executes system commands (PyObjC)
       ├─ Monitors device (psutil)
       └─ Sends responses
       ↑
macOS RemoteKeysServer App
  (starts/stops server process)
```

## File Locations

```
~/Desktop/RemoteKeys/
├── websocket_server.py              ← Main server
├── requirements.txt                 ← Python deps
├── setup.sh                         ← Setup script
├── setup_xcode_project.sh          ← Xcode helper
├── RemoteKeysServer/                ← Swift app folder
│   ├── RemoteKeysServer.swift
│   ├── ContentView.swift
│   ├── ServerManager.swift
│   ├── LaunchAtLoginManager.swift
│   ├── AccessibilityPermissions.swift
│   └── Info.plist
├── RemoteKeysServer.xcodeproj/      ← Created by Xcode
├── README_SERVER.md                 ← Full docs
├── QUICKSTART.md                    ← Quick guide
└── PROJECT_STRUCTURE.md             ← This file
```

## Dependencies & Requirements

**macOS:**
- macOS 11.0 or later
- Python 3.8+
- Xcode 13+ (to build the app)

**Python Libraries:**
- websockets (async WebSocket)
- pyobjc (macOS API access)
- psutil (system monitoring)

**macOS Permissions:**
- Accessibility - Required for keyboard/mouse control
- Local Network - Required to connect from iOS

## Build & Run

1. **Create Xcode Project:**
   - Use Xcode GUI (recommended)
   - Or run: `./setup.sh`

2. **Build:**
   - Cmd+B in Xcode

3. **Run:**
   - Cmd+R in Xcode

4. **Test:**
   - Click Start button
   - Check status turns green
   - Connect from iOS app

## Debugging

**Server not starting:**
1. Check activity logs in app
2. Verify Python: `python3 --version`
3. Verify deps: `pip3 list | grep websockets`
4. Run manually: `python3 websocket_server.py`

**Permission issues:**
1. Grant accessibility in System Settings
2. Grant network access if prompted

**Port conflicts:**
1. Check what's using 8765: `lsof -i :8765`
2. Change port in app settings

## Code Statistics

- **Python:** ~400 lines (websocket_server.py)
- **Swift:** ~500 lines across 5 files
- **Config:** 3 files (Info.plist, requirements.txt, setup scripts)
- **Docs:** 3 guides (README, QUICKSTART, this file)

**Total:** ~900 lines of code + documentation

## Key Design Decisions

1. **Python for Server:** Easy to maintain, good library support, PyObjC for macOS
2. **Swift for UI:** Native macOS app, matches iOS RemoteKeys style
3. **Process-based:** Server runs as separate Python process, managed by Swift app
4. **Graceful Shutdown:** 2-second grace period before force-kill
5. **LaunchAgent:** Auto-launch via launchd, not app login items
6. **Error Handling:** Graceful fallbacks when libraries unavailable
7. **Logging:** In-app activity log + stderr for debugging

## Security Notes

- No authentication in v1 (local network only)
- Requires accessibility permissions from user
- Server listens on 0.0.0.0 but only reachable on local Wi-Fi
- Consider firewall rules for multi-user Macs

## Future Enhancements

- [ ] Authentication/encryption
- [ ] Multi-client support
- [ ] Custom port configuration
- [ ] Server status dashboard
- [ ] Performance monitoring
- [ ] Plugin system for custom commands
- [ ] Voice control integration
- [ ] Gesture recording/playback

---

**Created:** May 1, 2026
**Version:** 1.0
**Status:** ✅ Implementation Complete - Ready for Xcode Project Creation

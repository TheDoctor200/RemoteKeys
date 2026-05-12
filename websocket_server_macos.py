#!/usr/bin/env python3
"""
RemoteKeys WebSocket Server
Companion server for the RemoteKeys macOS app.
Listens on ws://localhost:8765 and handles keyboard, mouse, trackpad, and terminal commands.
"""

import asyncio
import json
import subprocess
import sys
import signal
import threading
import logging
import os
import uuid
import socket
from datetime import datetime
from pathlib import Path

import websockets
import time

# Try to import macOS-specific libraries; fall back gracefully if not available
HAS_QUARTZ = False
HAS_PSUTIL = False

try:
    import Quartz
    from Cocoa import NSScreen, NSWorkspace
    from Foundation import NSBundle
    HAS_QUARTZ = True
except ImportError as e:
    print(f"Warning: PyObjC not installed. Keyboard/mouse control will not work.")
    print(f"Install with: pip3 install pyobjc")

try:
    import psutil
    HAS_PSUTIL = True
    psutil.cpu_percent(interval=None)
except ImportError as e:
    print(f"Warning: psutil not installed. System monitoring will be limited.")
    print(f"Install with: pip3 install psutil")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
    ]
)
logger = logging.getLogger(__name__)
# Reduce verbosity of websockets library
logging.getLogger('websockets').setLevel(logging.WARNING)

# Global state
connected_clients = set()
terminal_output_buffer = []
MAX_TERMINAL_LINES = 200
current_trackpad_mode = "cursor"  # cursor or scroll
# Cached device info updated in background to avoid blocking the event loop
cached_device_info = {}
_cached_info_lock = threading.Lock()
_device_info_updater_started = False
_drag_state = {
    "active": False,
    "button": "left",
}
terminal_session = None

# Per-client device-info cadence state to avoid repeatedly sending name/power payloads.
INFO_THROTTLE_SECONDS = float(os.environ.get("REK_INFO_THROTTLE_SECONDS", "20"))

# Per-client event aggregation buffers to reduce high-frequency event handling
per_client_buffers = {}
# Flush interval in seconds for aggregated events (20ms default).
# Aggressive flushing interval for low-latency input aggregation.
# Can be overridden with env var REK_FLUSH_INTERVAL (seconds, e.g. 0.002 for 2ms)
try:
    FLUSH_INTERVAL = float(os.environ.get("REK_FLUSH_INTERVAL", "0.002"))
except Exception:
    FLUSH_INTERVAL = 0.002
# Simple mapping of common key names to macOS virtual key codes (CGKeyCode)
# Covers letters, numbers, common punctuation, arrows and special keys used by RemoteKeys
KEYCODE_MAP = {
    'a': 0, 's': 1, 'd': 2, 'f': 3, 'h': 4, 'g': 5, 'z': 6, 'x': 7, 'c': 8, 'v': 9,
    'b': 11, 'q': 12, 'w': 13, 'e': 14, 'r': 15, 'y': 16, 't': 17,
    '1': 18, '2': 19, '3': 20, '4': 21, '6': 22, '5': 23, 'equals': 24, '9': 25, '7': 26,
    'minus': 27, '8': 28, '0': 29, 'o': 31, 'u': 32, 'i': 34, 'p': 35, 'l': 37, 'j': 38,
    'k': 40, 'semicolon': 41, 'backslash': 42, 'comma': 43, 'slash': 44, 'n': 45, 'm': 46, 'period': 47,
    'grave': 50,
    'return': 36, 'enter': 36, 'tab': 48, 'space': 49, 'delete': 51, 'backspace': 51, 'escape': 53,
    'left': 123, 'right': 124, 'down': 125, 'up': 126,
}


def key_name_to_keycode(name: str):
    if not name:
        return None
    n = str(name).lower()
    if n in KEYCODE_MAP:
        return KEYCODE_MAP[n]
    # Common synonyms and literal key names from the client.
    synonyms = {
        '\\n': KEYCODE_MAP.get('return'),
        'del': KEYCODE_MAP.get('delete'),
        'delete': KEYCODE_MAP.get('delete'),
        'backspace': KEYCODE_MAP.get('backspace'),
    }
    if n in synonyms:
        return synonyms[n]
    return None


def _update_cached_device_info(cpu_only: bool = False):
    """Compute device info quickly and store into cached_device_info.
    If cpu_only is True, only update CPU usage to allow faster cycles.
    """
    mac_name = "Unknown"
    try:
        mac_name = socket.gethostname().split('.')[0]
    except Exception:
        pass

    # Preserve previous values for fields that are updated less frequently.
    with _cached_info_lock:
        prev = dict(cached_device_info)

    cpu_usage = prev.get("cpu_usage", 0)
    battery_percentage = prev.get("battery_percentage")
    if HAS_PSUTIL:
        try:
            # non-blocking CPU percent
            cpu_usage = psutil.cpu_percent(interval=None)
        except Exception:
            cpu_usage = 0

        if not cpu_only:
            try:
                battery = psutil.sensors_battery()
                battery_percentage = battery.percent if battery else None
            except Exception:
                battery_percentage = None

    info = {
        "mac_name": mac_name,
        "name": mac_name,
        "cpu_usage": cpu_usage,
        "cpu": cpu_usage,
        "battery_percentage": battery_percentage,
        "battery": (battery_percentage / 100) if battery_percentage is not None else None,
    }

    with _cached_info_lock:
        cached_device_info.clear()
        cached_device_info.update(info)


def start_device_info_updater(cpu_interval: float = 2.0, battery_interval: float = 30.0):
    """Start a background thread that updates cached device info.
    cpu_interval: seconds between CPU updates
    battery_interval: seconds between battery updates
    """
    global _device_info_updater_started
    if _device_info_updater_started:
        return
    _device_info_updater_started = True

    def _updater():
        # Seed a fast CPU read
        if HAS_PSUTIL:
            try:
                psutil.cpu_percent(interval=None)
            except Exception:
                pass

        last_battery = 0.0
        while True:
            # Update CPU quickly
            _update_cached_device_info(cpu_only=True)
            time.sleep(cpu_interval)

            # Update battery less frequently
            last_battery += cpu_interval
            if last_battery >= battery_interval:
                _update_cached_device_info(cpu_only=False)
                last_battery = 0.0

    t = threading.Thread(target=_updater, daemon=True, name="device-info-updater")
    t.start()


def get_local_ip():
    """Detect the local IP address used for outgoing connections."""
    try:
        # Connect to a public DNS server to determine which local IP would be used.
        # This doesn't send data, just determines the local interface.
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        # Fallback to localhost if detection fails
        return "127.0.0.1"


def get_runtime_server_bind():
    """Return host/port from env with safe defaults and validation."""
    # Always bind to 0.0.0.0 (all interfaces) for websockets.serve()
    # Display IP is handled separately
    host = os.environ.get("REK_HOST", "0.0.0.0").strip() or "0.0.0.0"
    
    raw_port = os.environ.get("REK_PORT", "8765")
    try:
        port = int(raw_port)
        if port < 1 or port > 65535:
            raise ValueError
    except Exception:
        logger.warning(f"Invalid REK_PORT={raw_port!r}; falling back to 8765")
        port = 8765
    return host, port


def modifiers_to_bitmask(mods):
    """Convert modifier list or int to bitmask: Shift=1, Control=2, Option=4, Command=8"""
    if mods is None:
        return 0
    if isinstance(mods, int):
        return mods
    mask = 0
    # support list like ['shift','ctrl'] or []
    if isinstance(mods, (list, tuple)):
        for m in mods:
            mm = str(m).lower()
            if mm in ('shift',):
                mask |= 1
            elif mm in ('control', 'ctrl'):
                mask |= 2
            elif mm in ('option', 'alt', 'alternate'):
                mask |= 4
            elif mm in ('command', 'cmd', 'meta'):
                mask |= 8
    else:
        try:
            mask = int(mods)
        except Exception:
            mask = 0
    return mask


def build_device_info_payload(include_name: bool = False):
    """Build a device-info payload. Name can be sent once, while stats are throttled."""
    info = SystemController.get_device_info()
    payload = {"type": "info"}
    if include_name:
        if "name" in info:
            payload["name"] = info.get("name")
        elif "mac_name" in info:
            payload["name"] = info.get("mac_name")
    if "cpu" in info:
        payload["cpu"] = info.get("cpu")
    elif "cpu_usage" in info:
        payload["cpu"] = info.get("cpu_usage")
    if "battery" in info:
        payload["battery"] = info.get("battery")
    elif "battery_percentage" in info:
        payload["battery"] = info.get("battery_percentage")
    return payload


class SystemController:
    """Handles all system-level interactions on macOS."""

    @staticmethod
    def handle_key(key_code: int, modifiers: int, key_type: str = "keyDown"):
        """
        Send a keyboard event.
        key_code: Virtual key code (0-127)
        modifiers: Bitmask of modifiers (Shift=1, Control=2, Option=4, Command=8)
        key_type: "keyDown" or "keyUp"
        """
        if not HAS_QUARTZ:
            logger.warning("PyObjC not available for keyboard input")
            return

        try:
            # Create keyboard event (key down or up)
            is_down = (key_type == "keyDown")
            event = Quartz.CGEventCreateKeyboardEvent(
                None, key_code, is_down
            )

            # Apply modifiers
            if modifiers:
                # Convert to CGEventFlags
                flags = 0
                if modifiers & 1:  # Shift
                    flags |= Quartz.kCGEventFlagMaskShift
                if modifiers & 2:  # Control
                    flags |= Quartz.kCGEventFlagMaskControl
                if modifiers & 4:  # Option
                    flags |= Quartz.kCGEventFlagMaskAlternate
                if modifiers & 8:  # Command
                    flags |= Quartz.kCGEventFlagMaskCommand

                Quartz.CGEventSetFlags(event, flags)

            # Post the event
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

            # If a keyDown was requested but no explicit keyUp will be sent by client,
            # send a matching keyUp shortly after so the keystroke is completed.
            if is_down:
                # Create and post keyUp
                time.sleep(0.004)
                up_event = Quartz.CGEventCreateKeyboardEvent(None, key_code, False)
                if modifiers:
                    Quartz.CGEventSetFlags(up_event, flags)
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, up_event)
        except Exception as e:
            logger.error(f"Error sending keyboard event: {e}")

    @staticmethod
    def handle_move(dx: int, dy: int):
        """Move the mouse cursor by (dx, dy)."""
        if not HAS_QUARTZ:
            logger.warning("PyObjC not available for mouse movement")
            return

        try:
            # Get current mouse position
            event = Quartz.CGEventCreate(None)
            current_pos = Quartz.CGEventGetLocation(event)
            
            # Calculate new position
            new_x = current_pos.x + dx
            new_y = current_pos.y + dy
            
            # Create and post mouse move event
            move_event = Quartz.CGEventCreateMouseEvent(
                None,
                Quartz.kCGEventMouseMoved,
                Quartz.CGPointMake(new_x, new_y),
                Quartz.kCGMouseButtonLeft
            )
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, move_event)
        except Exception as e:
            logger.error(f"Error moving mouse: {e}")

    @staticmethod
    def handle_drag(dx: int, dy: int, button: str = "left"):
        """Drag the mouse while holding the specified button.
        The first drag event starts the press; subsequent drag events move it.
        """
        if not HAS_QUARTZ:
            logger.warning("PyObjC not available for dragging")
            return

        try:
            event = Quartz.CGEventCreate(None)
            current_pos = Quartz.CGEventGetLocation(event)
            new_x = current_pos.x + dx
            new_y = current_pos.y + dy

            button_map = {
                "left": Quartz.kCGMouseButtonLeft,
                "right": Quartz.kCGMouseButtonRight,
                "middle": Quartz.kCGMouseButtonCenter,
            }
            button_code = button_map.get(button, Quartz.kCGMouseButtonLeft)

            global _drag_state
            if not _drag_state["active"]:
                if button == "left":
                    down_event_type = Quartz.kCGEventLeftMouseDown
                elif button == "right":
                    down_event_type = Quartz.kCGEventRightMouseDown
                else:
                    down_event_type = Quartz.kCGEventOtherMouseDown

                down_event = Quartz.CGEventCreateMouseEvent(None, down_event_type, current_pos, button_code)
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, down_event)
                _drag_state["active"] = True
                _drag_state["button"] = button
            if button == "left":
                drag_event_type = Quartz.kCGEventLeftMouseDragged
            elif button == "right":
                drag_event_type = Quartz.kCGEventRightMouseDragged
            else:
                drag_event_type = Quartz.kCGEventOtherMouseDragged
            drag_event = Quartz.CGEventCreateMouseEvent(
                None,
                drag_event_type,
                Quartz.CGPointMake(new_x, new_y),
                button_code,
            )
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, drag_event)
        except Exception as e:
            logger.error(f"Error dragging mouse: {e}")

    @staticmethod
    def release_drag(button: str = "left"):
        """Release a previously started drag."""
        if not HAS_QUARTZ:
            return

        try:
            event = Quartz.CGEventCreate(None)
            pos = Quartz.CGEventGetLocation(event)
            button_map = {
                "left": Quartz.kCGMouseButtonLeft,
                "right": Quartz.kCGMouseButtonRight,
                "middle": Quartz.kCGMouseButtonCenter,
            }
            button_code = button_map.get(button, Quartz.kCGMouseButtonLeft)
            if button == "left":
                up_event_type = Quartz.kCGEventLeftMouseUp
            elif button == "right":
                up_event_type = Quartz.kCGEventRightMouseUp
            else:
                up_event_type = Quartz.kCGEventOtherMouseUp

            up_event = Quartz.CGEventCreateMouseEvent(None, up_event_type, pos, button_code)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, up_event)

            global _drag_state
            _drag_state["active"] = False
            _drag_state["button"] = "left"
        except Exception as e:
            logger.error(f"Error releasing drag: {e}")

    @staticmethod
    def handle_scroll(dx: int, dy: int):
        """Scroll the screen."""
        if not HAS_QUARTZ:
            logger.warning("PyObjC not available for scrolling")
            return

        try:
            # Scroll wheel events: positive = down/right, negative = up/left
            if dy != 0:
                scroll_event = Quartz.CGEventCreateScrollWheelEvent(
                    None,
                    Quartz.kCGScrollEventUnitLine,
                    2,  # 2 axes (vertical and horizontal)
                    int(dy * -1),  # Vertical scroll (inverted for natural scrolling)
                    int(dx)        # Horizontal scroll
                )
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, scroll_event)
        except Exception as e:
            logger.error(f"Error scrolling: {e}")

    @staticmethod
    def handle_click(button: str = "left", click_type: str = "single"):
        """
        Perform a mouse click.
        button: "left", "right", or "middle"
        click_type: "single" or "double"
        """
        if not HAS_QUARTZ:
            logger.warning("PyObjC not available for mouse clicks")
            return

        try:
            # Get current mouse position
            event = Quartz.CGEventCreate(None)
            pos = Quartz.CGEventGetLocation(event)
            
            # Map button name to CGMouseButton
            button_map = {
                "left": Quartz.kCGMouseButtonLeft,
                "right": Quartz.kCGMouseButtonRight,
                "middle": Quartz.kCGMouseButtonCenter,
            }
            button_code = button_map.get(button, Quartz.kCGMouseButtonLeft)
            
            # Map click type to event type
            if button == "left":
                down_event_type = Quartz.kCGEventLeftMouseDown
                up_event_type = Quartz.kCGEventLeftMouseUp
            elif button == "right":
                down_event_type = Quartz.kCGEventRightMouseDown
                up_event_type = Quartz.kCGEventRightMouseUp
            else:
                down_event_type = Quartz.kCGEventOtherMouseDown
                up_event_type = Quartz.kCGEventOtherMouseUp
            
            # Perform click(s)
            num_clicks = 2 if click_type == "double" else 1
            
            for _ in range(num_clicks):
                down = Quartz.CGEventCreateMouseEvent(
                    None, down_event_type, pos, button_code
                )
                up = Quartz.CGEventCreateMouseEvent(
                    None, up_event_type, pos, button_code
                )
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
                Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)
                
                if click_type == "double":
                    time.sleep(0.05)  # Small delay between double-click
        except Exception as e:
            logger.error(f"Error clicking mouse: {e}")

    @staticmethod
    async def execute_terminal_command(command: str, websocket=None):
        """Execute a shell command in a persistent shell session and stream output."""
        return await terminal_session.run_command(command, websocket)

    @staticmethod
    def get_device_info():
        """Gather device information."""
        # Return a thread-safe copy of the latest cached device info.
        with _cached_info_lock:
            return dict(cached_device_info)


async def _run_controller_action(func, *args):
    """Run a blocking controller action off the asyncio event loop."""
    return await asyncio.to_thread(func, *args)


async def _client_action_worker(websocket, action_queue):
    """Process controller actions sequentially without blocking receive handling."""
    while websocket in connected_clients:
        action = await action_queue.get()
        try:
            kind = action[0]
            if kind == "move":
                await _run_controller_action(SystemController.handle_move, action[1], action[2])
            elif kind == "drag":
                await _run_controller_action(SystemController.handle_drag, action[1], action[2], action[3])
            elif kind == "scroll":
                await _run_controller_action(SystemController.handle_scroll, action[1], action[2])
            elif kind == "key":
                await _run_controller_action(SystemController.handle_key, action[1], action[2], action[3])
            elif kind == "release_drag":
                await _run_controller_action(SystemController.release_drag, action[1])
            elif kind == "click":
                await _run_controller_action(SystemController.handle_click, action[1], action[2])
            elif kind == "terminal":
                # Run terminal command in a detached task so command streaming
                # doesn't block movement/input actions for this client.
                asyncio.create_task(SystemController.execute_terminal_command(action[1], websocket))
        except Exception as e:
            logger.error(f"Controller worker failed for {websocket.remote_address}: {e}")
        finally:
            action_queue.task_done()


def _enqueue_client_action(action_queue, action):
    try:
        action_queue.put_nowait(action)
    except asyncio.QueueFull:
        logger.warning("Client action queue full; dropping oldest action to keep UI responsive")
        try:
            action_queue.get_nowait()
            action_queue.task_done()
        except Exception:
            pass
        try:
            action_queue.put_nowait(action)
        except Exception:
            pass


class TerminalSession:
    """Persistent shell session that streams command output and keeps state between commands."""

    def __init__(self):
        self.process = None
        self.lock = asyncio.Lock()
        self.ready = False

    async def ensure_started(self):
        if self.process and self.process.returncode is None:
            return

        env = os.environ.copy()
        env.setdefault("TERM", "dumb")
        env.setdefault("PS1", "")
        env.setdefault("PROMPT", "")
        env.setdefault("RPROMPT", "")

        self.process = await asyncio.create_subprocess_exec(
            "/bin/zsh",
            "-f",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env=env,
        )
        self.ready = True

    async def run_command(self, command: str, websocket=None):
        await self.ensure_started()

        async with self.lock:
            marker = f"__REK_DONE_{uuid.uuid4().hex}__"
            wrapped_command = f"{command}\nprintf '\\n{marker}:%s\\n' $?\n"

            assert self.process is not None and self.process.stdin is not None and self.process.stdout is not None
            self.process.stdin.write(wrapped_command.encode("utf-8"))
            await self.process.stdin.drain()

            collected_lines = []
            while True:
                raw_line = await self.process.stdout.readline()
                if not raw_line:
                    break

                line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
                if line.startswith(marker + ":"):
                    break

                collected_lines.append(line)
                terminal_output_buffer.append(line)
                if len(terminal_output_buffer) > MAX_TERMINAL_LINES:
                    terminal_output_buffer.pop(0)

                if websocket is not None:
                    # If this websocket has a per-client buffer, append into it
                    # and let the flusher send batched output. Otherwise, send
                    # immediate single-line updates (best-effort compatibility).
                    try:
                        buf = per_client_buffers.get(websocket)
                        if buf is not None:
                            lock = buf.get("lock")
                            if lock is not None:
                                async with lock:
                                    buf.setdefault("terminal", []).append(line)
                            else:
                                buf.setdefault("terminal", []).append(line)
                        else:
                            response = {"type": "output", "line": line}
                            await websocket.send(json.dumps(response))
                    except Exception:
                        # Fallback to direct send if buffering fails
                        try:
                            response = {"type": "output", "line": line}
                            await websocket.send(json.dumps(response))
                        except Exception:
                            pass

            return "\n".join(collected_lines) + ("\n" if collected_lines else "")


terminal_session = TerminalSession()


async def handle_client(websocket):
    """Handle a connected WebSocket client."""
    client_id = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
    connected_clients.add(websocket)
    logger.info(f"Client connected: {client_id}")

    # Initialize per-client aggregation buffer and start flusher
    per_client_buffers[websocket] = {
        "move": {"dx": 0, "dy": 0},
        "drag": {"dx": 0, "dy": 0, "button": "left"},
        "scroll": {"dx": 0, "dy": 0},
        "actions": asyncio.Queue(maxsize=256),
        "lock": asyncio.Lock(),
        "terminal": [],
        "mode": "cursor",
        "flusher": None,
        "worker": None,
        "info_sent": False,
        "last_info_sent_at": 0.0,
    }
    async def _client_flusher(ws):
        # Periodically flush aggregated events for this client
        while ws in connected_clients:
            await asyncio.sleep(FLUSH_INTERVAL)
            buf = per_client_buffers.get(ws)
            if not buf:
                continue
            batched_terminal_lines = None
            async with buf["lock"]:
                m = buf["move"]
                if m["dx"] != 0 or m["dy"] != 0:
                    dx, dy = int(m["dx"]), int(m["dy"])
                    m["dx"] = 0
                    m["dy"] = 0
                    _enqueue_client_action(buf["actions"], ("move", dx, dy))

                d = buf["drag"]
                if d.get("dx", 0) != 0 or d.get("dy", 0) != 0:
                    dx, dy = int(d.get("dx", 0)), int(d.get("dy", 0))
                    button = d.get("button", "left")
                    d["dx"] = 0
                    d["dy"] = 0
                    _enqueue_client_action(buf["actions"], ("drag", dx, dy, button))

                s = buf["scroll"]
                if s["dx"] != 0 or s["dy"] != 0:
                    dx, dy = int(s["dx"]), int(s["dy"])
                    s["dx"] = 0
                    s["dy"] = 0
                    _enqueue_client_action(buf["actions"], ("scroll", dx, dy))

                # Batch terminal output to avoid many small websocket frames
                try:
                    tbuf = buf.get("terminal")
                    if tbuf:
                        batched_terminal_lines = list(tbuf)
                        if batched_terminal_lines:
                            tbuf.clear()
                except Exception:
                    # Best-effort; don't let terminal batching break the flusher
                    pass

            if batched_terminal_lines:
                try:
                    payload = {"type": "output_batch", "lines": batched_terminal_lines}
                    await ws.send(json.dumps(payload))
                except Exception:
                    pass

    per_client_buffers[websocket]["worker"] = asyncio.create_task(
        _client_action_worker(websocket, per_client_buffers[websocket]["actions"])
    )

    per_client_buffers[websocket]["flusher"] = asyncio.create_task(_client_flusher(websocket))

    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                message_type = data.get("type")
                
                if message_type == "key":
                    key_code = data.get("keyCode")
                    modifiers = data.get("modifiers", 0)
                    key_type = data.get("keyType", "keyDown")

                    # Support alternate field names and validate
                    if key_code is None:
                        key_code = data.get("keycode") or data.get("key") or data.get("code")

                    # Prefer semantic key-name mapping for string payloads.
                    key_code_int = None
                    if isinstance(key_code, str):
                        key_code_int = key_name_to_keycode(key_code)

                    if key_code_int is None and key_code is not None:
                        try:
                            key_code_int = int(key_code)
                        except Exception:
                            key_code_int = None

                    # Normalize modifiers which may come as list, tuple, or int
                    modifiers_int = modifiers_to_bitmask(modifiers)

                    if key_code_int is None:
                        logger.warning(f"Invalid keyCode/modifiers in message: {data}")
                    else:
                        _enqueue_client_action(per_client_buffers[websocket]["actions"], ("key", key_code_int, modifiers_int, key_type))
                    
                elif message_type == "move":
                    dx = int(data.get("dx", 0))
                    dy = int(data.get("dy", 0))
                    buf = per_client_buffers.get(websocket)
                    if buf is not None:
                        async with buf["lock"]:
                            buf["move"]["dx"] += dx
                            buf["move"]["dy"] += dy
                    else:
                        _enqueue_client_action(per_client_buffers[websocket]["actions"], ("move", dx, dy))

                elif message_type == "drag":
                    dx = int(data.get("dx", 0))
                    dy = int(data.get("dy", 0))
                    button = data.get("button", "left")
                    buf = per_client_buffers.get(websocket)
                    if buf is not None:
                        async with buf["lock"]:
                            buf["drag"]["dx"] += dx
                            buf["drag"]["dy"] += dy
                            buf["drag"]["button"] = button
                    else:
                        _enqueue_client_action(per_client_buffers[websocket]["actions"], ("drag", dx, dy, button))

                elif message_type in ("drop", "dragEnd"):
                    button = data.get("button", "left")
                    # Release immediately so UI feels responsive
                    _enqueue_client_action(per_client_buffers[websocket]["actions"], ("release_drag", button))
                    
                elif message_type == "scroll":
                    dx = int(data.get("dx", 0))
                    dy = int(data.get("dy", 0))
                    buf = per_client_buffers.get(websocket)
                    if buf is not None:
                        async with buf["lock"]:
                            buf["scroll"]["dx"] += dx
                            buf["scroll"]["dy"] += dy
                    else:
                        _enqueue_client_action(per_client_buffers[websocket]["actions"], ("scroll", dx, dy))
                    
                elif message_type == "click":
                    button = data.get("button", "left")
                    click_type = data.get("clickType", "single")
                    _enqueue_client_action(per_client_buffers[websocket]["actions"], ("click", button, click_type))

                elif message_type == "dblclick":
                    button = data.get("button", "left")
                    _enqueue_client_action(per_client_buffers[websocket]["actions"], ("click", button, "double"))
                    
                elif message_type == "trackpad":
                    # Trackpad can be cursor or scroll mode
                    mode = data.get("mode", "cursor")
                    global current_trackpad_mode
                    current_trackpad_mode = mode
                    buf = per_client_buffers.get(websocket)
                    if buf is not None:
                        async with buf["lock"]:
                            buf["mode"] = mode
                    
                elif message_type == "terminal":
                    command = data.get("command", "")
                    if command:
                        _enqueue_client_action(per_client_buffers[websocket]["actions"], ("terminal", command))
                
                elif message_type == "ping":
                    # Respond to ping with pong
                    response = {"type": "pong"}
                    await websocket.send(json.dumps(response))

                    # Send device name once, then throttle CPU/battery updates.
                    buf = per_client_buffers.get(websocket)
                    if buf is not None:
                        now = time.monotonic()
                        should_send_info = (not buf["info_sent"]) or ((now - buf["last_info_sent_at"]) >= INFO_THROTTLE_SECONDS)
                        if should_send_info:
                            info = build_device_info_payload(include_name=not buf["info_sent"])
                            await websocket.send(json.dumps(info))
                            buf["info_sent"] = True
                            buf["last_info_sent_at"] = now

                logger.debug(f"Processed message from {client_id}: {message_type}")
                
            except json.JSONDecodeError:
                logger.error(f"Invalid JSON from {client_id}")
            except Exception as e:
                logger.error(f"Error processing message from {client_id}: {e}")

    except websockets.exceptions.ConnectionClosed:
        logger.info(f"Client disconnected: {client_id}")
    except Exception as e:
        logger.error(f"Unexpected error in handle_client for {client_id}: {e}", exc_info=True)
        connected_clients.discard(websocket)
        # Cancel and remove per-client buffer and flusher task to avoid leaks
        buf = per_client_buffers.pop(websocket, None)
        if buf is not None:
            fl = buf.get("flusher")
            if fl is not None:
                fl.cancel()
                try:
                    await fl
                except asyncio.CancelledError:
                    pass
            worker = buf.get("worker")
            if worker is not None:
                worker.cancel()
                try:
                    await worker
                except asyncio.CancelledError:
                    pass


async def start_server(host: str = "0.0.0.0", port: int = 8765):
    """Start the WebSocket server."""
    logger.info(f"Starting WebSocket server on {host}:{port}")
    
    def _configure_socket(sock):
        """Configure socket for low latency."""
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        except (OSError, AttributeError):
            pass

    async with websockets.serve(
        handle_client,
        host,
        port,
        compression=None,
        max_queue=64,
        ping_interval=20,
        ping_timeout=20,
        close_timeout=1,
        reuse_address=True,
        reuse_port=True,
    ) as server:
        # Configure listening sockets
        for sock in server.sockets or []:
            _configure_socket(sock)
        
        logger.info(f"WebSocket server running on ws://{host}:{port}")
        try:
            await asyncio.Future()  # Run forever
        except KeyboardInterrupt:
            logger.info("Server shutting down...")


def signal_handler(sig, frame):
    """Handle shutdown signals gracefully."""
    try:
        signal_name = signal.Signals(sig).name
    except Exception:
        signal_name = str(sig)
    logger.info(f"Received {signal_name}; shutting down gracefully...")
    sys.exit(0)


def main():
    """Main entry point."""
    # Log what's available
    logger.info("=" * 60)
    logger.info("RemoteKeys WebSocket Server")
    logger.info("=" * 60)
    logger.info(f"PyObjC (keyboard/mouse):  {'✓ Available' if HAS_QUARTZ else '✗ Not installed'}")
    logger.info(f"psutil (system monitor):  {'✓ Available' if HAS_PSUTIL else '✗ Not installed'}")
    
    if not HAS_QUARTZ or not HAS_PSUTIL:
        logger.warning("")
        logger.warning("To enable all features, install missing packages:")
        if not HAS_QUARTZ:
            logger.warning("  pip install pyobjc")
        if not HAS_PSUTIL:
            logger.warning("  pip install psutil")
        logger.warning("")
    
    logger.info("=" * 60)

    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    host, port = get_runtime_server_bind()
    logger.info(f"Server bind configured as {host}:{port}")
    
    # Get local IP for display purposes
    local_ip = get_local_ip()
    logger.info(f"Server accessible at ws://{local_ip}:{port}")

    # Start device info updater in background
    start_device_info_updater()
    
    # Run server (signal handler will call sys.exit(0) on SIGINT/SIGTERM)
    try:
        asyncio.run(start_server(host=host, port=port))
    except Exception as e:
        logger.error(f"Server error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

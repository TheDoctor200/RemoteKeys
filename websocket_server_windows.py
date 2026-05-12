#!/usr/bin/env python3
"""
RemoteKeys WebSocket Server (Windows)
Companion server for the RemoteKeys app.
Listens on ws://localhost:8765 and handles keyboard, mouse, trackpad, and terminal commands.
"""

import asyncio
import ctypes
import json
import logging
import os
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid

import websockets

# Optional system monitoring dependency
HAS_PSUTIL = False
try:
	import psutil

	HAS_PSUTIL = True
	psutil.cpu_percent(interval=None)
except ImportError:
	print("Warning: psutil not installed. System monitoring will be limited.")
	print("Install with: pip install psutil")

# Configure logging
logging.basicConfig(
	level=logging.INFO,
	format="%(asctime)s [%(levelname)s] %(message)s",
	handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)
logging.getLogger("websockets").setLevel(logging.WARNING)

# Win32 constants
KEYEVENTF_KEYUP = 0x0002
MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_WHEEL = 0x0800
MOUSEEVENTF_HWHEEL = 0x01000
WHEEL_DELTA = 120

VK_SHIFT = 0x10
VK_CONTROL = 0x11
VK_MENU = 0x12  # Alt
VK_LWIN = 0x5B

user32 = ctypes.windll.user32

# Global state
connected_clients = set()
terminal_output_buffer = []
MAX_TERMINAL_LINES = 200
current_trackpad_mode = "cursor"
cached_device_info = {}
_cached_info_lock = threading.Lock()
_device_info_updater_started = False
_drag_state = {
	"active": False,
	"button": "left",
}

INFO_THROTTLE_SECONDS = float(os.environ.get("REK_INFO_THROTTLE_SECONDS", "20"))
TERMINAL_MODE = os.environ.get("REK_TERMINAL_MODE", "auto").strip().lower() or "auto"

per_client_buffers = {}
try:
	FLUSH_INTERVAL = float(os.environ.get("REK_FLUSH_INTERVAL", "0.002"))
except Exception:
	FLUSH_INTERVAL = 0.002

# Key map for common keys from RemoteKeys payloads
KEYCODE_MAP = {
	"a": 0x41,
	"b": 0x42,
	"c": 0x43,
	"d": 0x44,
	"e": 0x45,
	"f": 0x46,
	"g": 0x47,
	"h": 0x48,
	"i": 0x49,
	"j": 0x4A,
	"k": 0x4B,
	"l": 0x4C,
	"m": 0x4D,
	"n": 0x4E,
	"o": 0x4F,
	"p": 0x50,
	"q": 0x51,
	"r": 0x52,
	"s": 0x53,
	"t": 0x54,
	"u": 0x55,
	"v": 0x56,
	"w": 0x57,
	"x": 0x58,
	"y": 0x59,
	"z": 0x5A,
	"0": 0x30,
	"1": 0x31,
	"2": 0x32,
	"3": 0x33,
	"4": 0x34,
	"5": 0x35,
	"6": 0x36,
	"7": 0x37,
	"8": 0x38,
	"9": 0x39,
	"return": 0x0D,
	"enter": 0x0D,
	"tab": 0x09,
	"space": 0x20,
	"delete": 0x2E,
	"backspace": 0x08,
	"escape": 0x1B,
	"left": 0x25,
	"up": 0x26,
	"right": 0x27,
	"down": 0x28,
	"minus": 0xBD,
	"equals": 0xBB,
	"comma": 0xBC,
	"period": 0xBE,
	"slash": 0xBF,
	"semicolon": 0xBA,
	"backslash": 0xDC,
	"grave": 0xC0,
}


def key_name_to_keycode(name: str):
	if not name:
		return None
	n = str(name).lower()
	if n in KEYCODE_MAP:
		return KEYCODE_MAP[n]
	synonyms = {
		"\\n": KEYCODE_MAP.get("return"),
		"del": KEYCODE_MAP.get("delete"),
		"delete": KEYCODE_MAP.get("delete"),
		"backspace": KEYCODE_MAP.get("backspace"),
	}
	return synonyms.get(n)


def modifiers_to_bitmask(mods):
	"""Convert modifier list or int to bitmask: Shift=1, Control=2, Option/Alt=4, Command/Win=8."""
	if mods is None:
		return 0
	if isinstance(mods, int):
		return mods
	mask = 0
	if isinstance(mods, (list, tuple)):
		for m in mods:
			mm = str(m).lower()
			if mm == "shift":
				mask |= 1
			elif mm in ("control", "ctrl"):
				mask |= 2
			elif mm in ("option", "alt", "alternate"):
				mask |= 4
			elif mm in ("command", "cmd", "meta", "win", "windows"):
				mask |= 8
	else:
		try:
			mask = int(mods)
		except Exception:
			mask = 0
	return mask


def _update_cached_device_info(cpu_only: bool = False):
	host_name = "Unknown"
	try:
		host_name = socket.gethostname().split(".")[0]
	except Exception:
		pass

	with _cached_info_lock:
		prev = dict(cached_device_info)

	cpu_usage = prev.get("cpu_usage", 0)
	battery_percentage = prev.get("battery_percentage")
	if HAS_PSUTIL:
		try:
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
		"name": host_name,
		"cpu_usage": cpu_usage,
		"cpu": cpu_usage,
		"battery_percentage": battery_percentage,
		"battery": (battery_percentage / 100.0) if battery_percentage is not None else None,
	}

	with _cached_info_lock:
		cached_device_info.clear()
		cached_device_info.update(info)


def start_device_info_updater(cpu_interval: float = 2.0, battery_interval: float = 30.0):
	global _device_info_updater_started
	if _device_info_updater_started:
		return
	_device_info_updater_started = True

	def _updater():
		if HAS_PSUTIL:
			try:
				psutil.cpu_percent(interval=None)
			except Exception:
				pass

		last_battery = 0.0
		while True:
			_update_cached_device_info(cpu_only=True)
			time.sleep(cpu_interval)
			last_battery += cpu_interval
			if last_battery >= battery_interval:
				_update_cached_device_info(cpu_only=False)
				last_battery = 0.0

	threading.Thread(target=_updater, daemon=True, name="device-info-updater").start()


def build_device_info_payload(include_name: bool = False):
	info = SystemController.get_device_info()
	payload = {"type": "info"}
	if include_name and "name" in info:
		payload["name"] = info.get("name")
	if "cpu" in info:
		payload["cpu"] = info.get("cpu")
	elif "cpu_usage" in info:
		payload["cpu"] = info.get("cpu_usage")
	if "battery" in info:
		payload["battery"] = info.get("battery")
	elif "battery_percentage" in info:
		payload["battery"] = info.get("battery_percentage")
	return payload


def get_local_ip():
	try:
		s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
		s.connect(("8.8.8.8", 80))
		ip = s.getsockname()[0]
		s.close()
		return ip
	except Exception:
		return "127.0.0.1"


def get_runtime_server_bind():
	host = os.environ.get("REK_HOST", "0.0.0.0").strip() or "0.0.0.0"
	raw_port = os.environ.get("REK_PORT", "8765")
	try:
		port = int(raw_port)
		if port < 1 or port > 65535:
			raise ValueError
	except Exception:
		logger.warning("Invalid REK_PORT=%r; falling back to 8765", raw_port)
		port = 8765
	return host, port


def _press_key(vk_code: int):
	user32.keybd_event(vk_code, 0, 0, 0)


def _release_key(vk_code: int):
	user32.keybd_event(vk_code, 0, KEYEVENTF_KEYUP, 0)


def _apply_modifiers_down(modifiers: int):
	if modifiers & 1:
		_press_key(VK_SHIFT)
	if modifiers & 2:
		_press_key(VK_CONTROL)
	if modifiers & 4:
		_press_key(VK_MENU)
	if modifiers & 8:
		_press_key(VK_LWIN)


def _apply_modifiers_up(modifiers: int):
	if modifiers & 8:
		_release_key(VK_LWIN)
	if modifiers & 4:
		_release_key(VK_MENU)
	if modifiers & 2:
		_release_key(VK_CONTROL)
	if modifiers & 1:
		_release_key(VK_SHIFT)


async def run_command_in_windows_terminal(command: str):
	"""Open cmd.exe window and execute the command."""

	def _spawn():
		return subprocess.run(
			["cmd.exe", "/c", "start", "", "cmd.exe", "/k", command],
			capture_output=True,
			text=True,
			check=False,
		)

	result = await asyncio.to_thread(_spawn)
	if result.returncode == 0:
		return True, "Opened cmd and dispatched command"
	err = (result.stderr or result.stdout or "Unknown error").strip()
	return False, f"Failed to open cmd: {err}"


class TerminalSession:
	"""Fallback persistent shell session used when terminal app mode is unavailable."""

	def __init__(self):
		self.process = None
		self.lock = asyncio.Lock()

	async def ensure_started(self):
		if self.process and self.process.returncode is None:
			return

		env = os.environ.copy()
		self.process = await asyncio.create_subprocess_exec(
			"cmd.exe",
			"/Q",
			"/K",
			stdin=asyncio.subprocess.PIPE,
			stdout=asyncio.subprocess.PIPE,
			stderr=asyncio.subprocess.STDOUT,
			env=env,
		)

	async def run_command(self, command: str, on_line=None):
		await self.ensure_started()

		async with self.lock:
			marker = f"__REK_DONE_{uuid.uuid4().hex}__"
			wrapped_command = f"{command}\r\necho {marker}:%errorlevel%\r\n"

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

				# Ignore echoed command line noise for cleaner output.
				if line.lower().startswith(command.lower()):
					continue

				collected_lines.append(line)
				if on_line is not None:
					await on_line(line)

			return "\n".join(collected_lines) + ("\n" if collected_lines else "")


terminal_session = TerminalSession()


async def _emit_terminal_line(websocket, line: str):
	terminal_output_buffer.append(line)
	if len(terminal_output_buffer) > MAX_TERMINAL_LINES:
		terminal_output_buffer.pop(0)

	if websocket is None:
		return

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
			await websocket.send(json.dumps({"type": "output", "line": line}))
	except Exception:
		try:
			await websocket.send(json.dumps({"type": "output", "line": line}))
		except Exception:
			pass


class SystemController:
	"""Handles system-level interactions on Windows."""

	@staticmethod
	def handle_key(key_code: int, modifiers: int, key_type: str = "keyDown"):
		try:
			_apply_modifiers_down(modifiers)
			is_down = key_type == "keyDown"
			if is_down:
				_press_key(key_code)
				time.sleep(0.004)
				_release_key(key_code)
			else:
				_release_key(key_code)
			_apply_modifiers_up(modifiers)
		except Exception as exc:
			logger.error("Error sending keyboard event: %s", exc)

	@staticmethod
	def handle_move(dx: int, dy: int):
		try:
			user32.mouse_event(MOUSEEVENTF_MOVE, int(dx), int(dy), 0, 0)
		except Exception as exc:
			logger.error("Error moving mouse: %s", exc)

	@staticmethod
	def handle_drag(dx: int, dy: int, button: str = "left"):
		try:
			global _drag_state
			if not _drag_state["active"]:
				if button == "right":
					user32.mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0)
				elif button == "middle":
					user32.mouse_event(MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, 0)
				else:
					user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
				_drag_state["active"] = True
				_drag_state["button"] = button

			user32.mouse_event(MOUSEEVENTF_MOVE, int(dx), int(dy), 0, 0)
		except Exception as exc:
			logger.error("Error dragging mouse: %s", exc)

	@staticmethod
	def release_drag(button: str = "left"):
		try:
			global _drag_state
			btn = button or _drag_state.get("button", "left")
			if btn == "right":
				user32.mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0)
			elif btn == "middle":
				user32.mouse_event(MOUSEEVENTF_MIDDLEUP, 0, 0, 0, 0)
			else:
				user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
			_drag_state["active"] = False
			_drag_state["button"] = "left"
		except Exception as exc:
			logger.error("Error releasing drag: %s", exc)

	@staticmethod
	def handle_scroll(dx: int, dy: int):
		try:
			if dy:
				user32.mouse_event(MOUSEEVENTF_WHEEL, 0, 0, int(dy) * WHEEL_DELTA, 0)
			if dx:
				user32.mouse_event(MOUSEEVENTF_HWHEEL, 0, 0, int(dx) * WHEEL_DELTA, 0)
		except Exception as exc:
			logger.error("Error scrolling: %s", exc)

	@staticmethod
	def handle_click(button: str = "left", click_type: str = "single"):
		try:
			num_clicks = 2 if click_type == "double" else 1
			for _ in range(num_clicks):
				if button == "right":
					user32.mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0)
					user32.mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0)
				elif button == "middle":
					user32.mouse_event(MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, 0)
					user32.mouse_event(MOUSEEVENTF_MIDDLEUP, 0, 0, 0, 0)
				else:
					user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
					user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
				if click_type == "double":
					time.sleep(0.05)
		except Exception as exc:
			logger.error("Error clicking mouse: %s", exc)

	@staticmethod
	async def execute_terminal_command(command: str, websocket=None):
		mode = TERMINAL_MODE

		if mode in ("app", "auto"):
			ok, message = await run_command_in_windows_terminal(command)
			await _emit_terminal_line(websocket, f"[terminal] {message}")
			if ok or mode == "app":
				return ""

		async def _on_line(line: str):
			await _emit_terminal_line(websocket, line)

		return await terminal_session.run_command(command, on_line=_on_line)

	@staticmethod
	def get_device_info():
		with _cached_info_lock:
			return dict(cached_device_info)


async def _run_controller_action(func, *args):
	return await asyncio.to_thread(func, *args)


def _enqueue_client_action(action_queue, action):
	try:
		action_queue.put_nowait(action)
	except asyncio.QueueFull:
		logger.warning("Client action queue full; dropping oldest action")
		try:
			action_queue.get_nowait()
			action_queue.task_done()
		except Exception:
			pass
		try:
			action_queue.put_nowait(action)
		except Exception:
			pass


async def _client_action_worker(websocket, action_queue):
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
				asyncio.create_task(SystemController.execute_terminal_command(action[1], websocket))
		except Exception as exc:
			logger.error("Controller worker failed for %s: %s", websocket.remote_address, exc)
		finally:
			action_queue.task_done()


async def handle_client(websocket):
	client_id = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
	connected_clients.add(websocket)
	logger.info("Client connected: %s", client_id)

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
		while ws in connected_clients:
			await asyncio.sleep(FLUSH_INTERVAL)
			buf = per_client_buffers.get(ws)
			if not buf:
				continue

			batched_terminal_lines = None
			async with buf["lock"]:
				m = buf["move"]
				if m["dx"] or m["dy"]:
					dx, dy = int(m["dx"]), int(m["dy"])
					m["dx"] = 0
					m["dy"] = 0
					_enqueue_client_action(buf["actions"], ("move", dx, dy))

				d = buf["drag"]
				if d.get("dx", 0) or d.get("dy", 0):
					dx, dy = int(d.get("dx", 0)), int(d.get("dy", 0))
					button = d.get("button", "left")
					d["dx"] = 0
					d["dy"] = 0
					_enqueue_client_action(buf["actions"], ("drag", dx, dy, button))

				s = buf["scroll"]
				if s["dx"] or s["dy"]:
					dx, dy = int(s["dx"]), int(s["dy"])
					s["dx"] = 0
					s["dy"] = 0
					_enqueue_client_action(buf["actions"], ("scroll", dx, dy))

				tbuf = buf.get("terminal")
				if tbuf:
					batched_terminal_lines = list(tbuf)
					if batched_terminal_lines:
						tbuf.clear()

			if batched_terminal_lines:
				try:
					await ws.send(json.dumps({"type": "output", "lines": batched_terminal_lines}))
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

					if key_code is None:
						key_code = data.get("keycode") or data.get("key") or data.get("code")

					key_code_int = None
					if isinstance(key_code, str):
						key_code_int = key_name_to_keycode(key_code)
					if key_code_int is None and key_code is not None:
						try:
							key_code_int = int(key_code)
						except Exception:
							key_code_int = None

					modifiers_int = modifiers_to_bitmask(modifiers)
					if key_code_int is None:
						logger.warning("Invalid key payload: %s", data)
					else:
						_enqueue_client_action(
							per_client_buffers[websocket]["actions"],
							("key", key_code_int, modifiers_int, key_type),
						)

				elif message_type == "move":
					dx = int(data.get("dx", 0))
					dy = int(data.get("dy", 0))
					buf = per_client_buffers.get(websocket)
					if buf is not None:
						async with buf["lock"]:
							buf["move"]["dx"] += dx
							buf["move"]["dy"] += dy

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

				elif message_type in ("drop", "dragEnd"):
					button = data.get("button", "left")
					_enqueue_client_action(per_client_buffers[websocket]["actions"], ("release_drag", button))

				elif message_type == "scroll":
					dx = int(data.get("dx", 0))
					dy = int(data.get("dy", 0))
					buf = per_client_buffers.get(websocket)
					if buf is not None:
						async with buf["lock"]:
							buf["scroll"]["dx"] += dx
							buf["scroll"]["dy"] += dy

				elif message_type == "click":
					button = data.get("button", "left")
					click_type = data.get("clickType", "single")
					_enqueue_client_action(per_client_buffers[websocket]["actions"], ("click", button, click_type))

				elif message_type == "dblclick":
					button = data.get("button", "left")
					_enqueue_client_action(per_client_buffers[websocket]["actions"], ("click", button, "double"))

				elif message_type == "trackpad":
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
					await websocket.send(json.dumps({"type": "pong"}))
					buf = per_client_buffers.get(websocket)
					if buf is not None:
						now = time.monotonic()
						should_send = (not buf["info_sent"]) or (
							(now - buf["last_info_sent_at"]) >= INFO_THROTTLE_SECONDS
						)
						if should_send:
							info = build_device_info_payload(include_name=not buf["info_sent"])
							await websocket.send(json.dumps(info))
							buf["info_sent"] = True
							buf["last_info_sent_at"] = now

			except json.JSONDecodeError:
				logger.error("Invalid JSON from %s", client_id)
			except Exception as exc:
				logger.error("Error processing message from %s: %s", client_id, exc)

	except websockets.exceptions.ConnectionClosed:
		logger.info("Client disconnected: %s", client_id)
	except Exception as exc:
		logger.error("Unexpected error in handle_client for %s: %s", client_id, exc, exc_info=True)
	finally:
		connected_clients.discard(websocket)
		buf = per_client_buffers.pop(websocket, None)
		if buf is not None:
			flusher = buf.get("flusher")
			worker = buf.get("worker")
			if flusher is not None:
				flusher.cancel()
				try:
					await flusher
				except asyncio.CancelledError:
					pass
			if worker is not None:
				worker.cancel()
				try:
					await worker
				except asyncio.CancelledError:
					pass


async def start_server(host: str = "0.0.0.0", port: int = 8765):
	logger.info("Starting WebSocket server on %s:%s", host, port)

	def _configure_socket(sock):
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
		for sock in server.sockets or []:
			_configure_socket(sock)
		logger.info("WebSocket server running on ws://%s:%s", host, port)
		await asyncio.Future()


def signal_handler(sig, frame):
	try:
		signal_name = signal.Signals(sig).name
	except Exception:
		signal_name = str(sig)
	logger.info("Received %s; shutting down gracefully...", signal_name)
	sys.exit(0)


def main():
	logger.info("=" * 60)
	logger.info("RemoteKeys WebSocket Server (Windows)")
	logger.info("=" * 60)
	logger.info("psutil (system monitor):  %s", "Available" if HAS_PSUTIL else "Not installed")
	logger.info("Terminal mode: %s", TERMINAL_MODE)
	if not HAS_PSUTIL:
		logger.warning("Install optional monitoring dependency: pip install psutil")
	logger.info("=" * 60)

	signal.signal(signal.SIGINT, signal_handler)
	signal.signal(signal.SIGTERM, signal_handler)

	host, port = get_runtime_server_bind()
	logger.info("Server bind configured as %s:%s", host, port)
	logger.info("Server accessible at ws://%s:%s", get_local_ip(), port)

	start_device_info_updater()

	try:
		asyncio.run(start_server(host=host, port=port))
	except KeyboardInterrupt:
		logger.info("Server stopped")
	except Exception as exc:
		logger.error("Server error: %s", exc)
		sys.exit(1)


if __name__ == "__main__":
	if os.name != "nt":
		print("This server is Windows-only. Use websocket_server_macos.py on macOS.")
		sys.exit(1)
	main()

#!/usr/bin/env python3
"""Comprehensive latency diagnostic tool."""
import asyncio
import json
import websockets
import time
import statistics

async def diagnostic_test():
    """Run comprehensive diagnostics."""
    uri = "ws://192.168.178.118:8765/remote"
    
    print("=" * 60)
    print("RemoteKeys Server Latency Diagnostic")
    print("=" * 60)
    
    try:
        async with websockets.connect(uri, ping_interval=None, ping_timeout=None) as websocket:
            print("\n✓ Connected to server\n")
            
            # Test 1: Ping/Pong latency
            print("Test 1: Ping/Pong Latency")
            print("-" * 40)
            latencies = []
            for _ in range(10):
                start = time.monotonic()
                await websocket.send(json.dumps({"type": "ping"}))
                response = await websocket.recv()
                latency = (time.monotonic() - start) * 1000
                latencies.append(latency)
            print(f"  Min:    {min(latencies):.3f}ms")
            print(f"  Max:    {max(latencies):.3f}ms")
            print(f"  Mean:   {statistics.mean(latencies):.3f}ms")
            print(f"  Median: {statistics.median(latencies):.3f}ms\n")
            
            # Test 2: Keyboard event send latency
            print("Test 2: Keyboard Event Send Latency")
            print("-" * 40)
            latencies = []
            for i in range(10):
                start = time.monotonic()
                await websocket.send(json.dumps({
                    "type": "key",
                    "key": "a",
                    "keyCode": 0,
                    "modifiers": 0,
                    "keyType": "keyDown"
                }))
                latency = (time.monotonic() - start) * 1000
                latencies.append(latency)
                await asyncio.sleep(0.05)
            print(f"  Min:    {min(latencies):.3f}ms")
            print(f"  Max:    {max(latencies):.3f}ms")
            print(f"  Mean:   {statistics.mean(latencies):.3f}ms")
            print(f"  Median: {statistics.median(latencies):.3f}ms\n")
            
            # Test 3: Move event send latency
            print("Test 3: Mouse Move Event Send Latency")
            print("-" * 40)
            latencies = []
            for i in range(10):
                start = time.monotonic()
                await websocket.send(json.dumps({
                    "type": "move",
                    "dx": 10,
                    "dy": 10
                }))
                latency = (time.monotonic() - start) * 1000
                latencies.append(latency)
                await asyncio.sleep(0.02)
            print(f"  Min:    {min(latencies):.3f}ms")
            print(f"  Max:    {max(latencies):.3f}ms")
            print(f"  Mean:   {statistics.mean(latencies):.3f}ms")
            print(f"  Median: {statistics.median(latencies):.3f}ms\n")
            
            print("=" * 60)
            print("Interpretation:")
            print("- Ping/pong <1ms: Server is responsive ✓")
            print("- Event send <1ms: WebSocket is fast ✓")
            print("- If latency is high, issue is in:")
            print("  1. Network latency between devices")
            print("  2. iOS app event generation")
            print("  3. macOS Quartz action execution")
            print("=" * 60)
            
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(diagnostic_test())

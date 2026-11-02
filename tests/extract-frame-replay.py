#!/usr/bin/env python3
# Writes frame_replay.vectors from hive-node's docs/spec/vectors/hive-v1.json: the frame_replay
# group (wire-protocol.md 6.6, D-075), one frame per line as "<iv hex> <play|drop> <name>". The IV
# is the 12 bytes before a frame's 2-byte trailer. Usage: extract-frame-replay.py hive-v1.json
import hashlib
import json
import sys

raw = open(sys.argv[1], "rb").read()
group = json.loads(raw)["frame_replay"]
assert group["suite"] == "hive-frame/2" and group["media"] == "audio", group["suite"]
print(f"# hive-node docs/spec/vectors/hive-v1.json sha256 {hashlib.sha256(raw).hexdigest()}")
print(f"# frame_replay: {group['suite']} {group['media']}, window {group['window_ticks']} ticks")
for frame in group["frames"]:
    data = bytes.fromhex(frame["frame_hex"])
    assert data[-2] == 12, frame["name"]
    iv = data[-14:-2]
    assert int.from_bytes(iv[0:4], "big") == frame["ssrc"], frame["name"]
    assert int.from_bytes(iv[4:8], "big") == frame["iv_timestamp"], frame["name"]
    print(f"{iv.hex()} {frame['verdict']} {frame['name']}")

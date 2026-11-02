// Checks the replay guard that patches/webrtc-a545de4.patch adds to WebRTC
// (api/crypto/frame_replay_guard.h; SEC PR-01, hive-node wire-protocol.md 6.6 "Replay", D-075)
// against hive-node's frame_replay vectors and the spec's bounds. Built by
// tests/run-source-patch-tests.sh against the patched upstream tree; needs only a C++20 compiler.
#include "api/crypto/frame_replay_guard.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

using webrtc::FrameReplayGuard;

namespace {

int failures = 0;

void Check(bool ok, const std::string& what) {
  if (!ok) {
    ++failures;
    std::cout << "FAIL " << what << "\n";
  }
}

std::vector<uint8_t> Iv(uint32_t ssrc, uint32_t ts, uint32_t tail) {
  std::vector<uint8_t> iv(12);
  for (int i = 0; i < 4; ++i) {
    iv[i] = static_cast<uint8_t>(ssrc >> (24 - 8 * i));
    iv[4 + i] = static_cast<uint8_t>(ts >> (24 - 8 * i));
    iv[8 + i] = static_cast<uint8_t>(tail >> (24 - 8 * i));
  }
  return iv;
}

std::vector<uint8_t> Hex(const std::string& hex) {
  std::vector<uint8_t> out;
  for (size_t i = 0; i + 1 < hex.size(); i += 2) {
    out.push_back(static_cast<uint8_t>(std::stoul(hex.substr(i, 2), nullptr, 16)));
  }
  return out;
}

// hive-node's frame_replay group, in order, under one key.
void Vectors(const char* path) {
  std::ifstream in(path);
  Check(in.good(), std::string("open ") + path);
  FrameReplayGuard guard;
  std::string line;
  int frames = 0, drops = 0;
  int64_t now_ms = 0;
  while (std::getline(in, line)) {
    if (line.empty() || line[0] == '#') continue;
    std::istringstream fields(line);
    std::string iv_hex, verdict;
    fields >> iv_hex >> verdict;
    std::string name;
    std::getline(fields, name);
    std::vector<uint8_t> iv = Hex(iv_hex);
    Check(iv.size() == 12, "12-byte IV:" + name);
    now_ms += 20;
    const bool play = guard.Accept(iv, FrameReplayGuard::kAudioWindowTicks, now_ms);
    Check(play == (verdict == "play"), "vector" + name + ": want " + verdict);
    ++frames;
    if (verdict == "drop") ++drops;
  }
  Check(frames == 15 && drops == 5, "15 frames, 5 drops");
}

// A replay inside the window is caught by the IV memory, a late new frame plays.
void InsideWindow() {
  FrameReplayGuard guard;
  const uint32_t w = FrameReplayGuard::kVideoWindowTicks;
  Check(guard.Accept(Iv(7, 90000, 1), w, 0), "video first frame");
  std::vector<uint8_t> short_iv(8, 0);
  Check(!guard.Accept(short_iv, w, 0), "an IV that is not 12 bytes is refused");
  Check(guard.Accept(Iv(7, 93000, 2), w, 33), "video next frame");
  Check(!guard.Accept(Iv(7, 90000, 1), w, 66), "video replay inside the window");
  Check(guard.Accept(Iv(7, 91500, 9), w, 99), "video late new frame");
  Check(guard.Accept(Iv(7, 93000 + w, 3), w, 120), "exactly the window ahead");
  Check(guard.Accept(Iv(7, 93000, 77), w, 140), "exactly the window behind plays");
  Check(!guard.Accept(Iv(7, 92999, 78), w, 160), "one tick more than the window behind");
}

// The memory per ssrc holds only the IVs within the window.
void MemoryBounded() {
  FrameReplayGuard guard;
  const uint32_t w = FrameReplayGuard::kAudioWindowTicks;
  for (uint32_t i = 0; i < 1000; ++i) {
    Check(guard.Accept(Iv(1, 1000 + i * 960, i), w, i * 20), "steady audio plays");
  }
  Check(guard.remembered(1) == 101, "2 s of 20 ms audio frames remembered, got " +
                                        std::to_string(guard.remembered(1)));
}

// At most 16 ssrcs; a 17th replaces the one heard from longest ago.
void SsrcCap() {
  FrameReplayGuard guard;
  const uint32_t w = FrameReplayGuard::kAudioWindowTicks;
  for (uint32_t s = 1; s <= 16; ++s) guard.Accept(Iv(s, 5000, 0), w, 0);
  guard.Accept(Iv(1, 6000, 1), w, 1);  // ssrc 1 heard again; 2 is now the oldest
  Check(guard.ssrc_count() == 16, "16 ssrcs");
  Check(guard.Accept(Iv(17, 5000, 0), w, 2), "a 17th ssrc plays");
  Check(guard.ssrc_count() == 16, "still 16 ssrcs");
  Check(guard.remembered(2) == 0, "ssrc 2 (oldest) replaced");
  Check(!guard.Accept(Iv(1, 6000, 1), w, 3), "ssrc 1 kept its memory");
}

// An ssrc whose every frame is refused as window-behind for 2 s is reset.
void ResetAfterTwoSeconds() {
  FrameReplayGuard guard;
  const uint32_t w = FrameReplayGuard::kAudioWindowTicks;
  Check(guard.Accept(Iv(3, 1000000, 0), w, 0), "before the jump");
  int64_t t = 20;
  uint32_t ts = 1000;  // the sender's clock jumped back by far more than the window
  for (; t < 2020; t += 20, ts += 960) {
    Check(!guard.Accept(Iv(3, ts, 1), w, t), "window-behind for under 2 s is dropped");
  }
  Check(guard.Accept(Iv(3, ts, 1), w, t), "after 2 s of window-behind drops, reset");
  Check(guard.Accept(Iv(3, ts + 960, 2), w, t + 20), "and plays on");
  Check(!guard.Accept(Iv(3, ts, 1), w, t + 40), "the new state refuses a repeat");

  // A frame that plays in between ends the run of drops.
  FrameReplayGuard g2;
  g2.Accept(Iv(4, 1000000, 0), w, 0);
  Check(!g2.Accept(Iv(4, 10, 1), w, 10), "behind");
  Check(g2.Accept(Iv(4, 1000960, 2), w, 1000), "a live frame");
  Check(!g2.Accept(Iv(4, 20, 3), w, 2100), "behind again starts a new run");
  Check(!g2.Accept(Iv(4, 30, 4), w, 4000), "the run resets after 2 s, not before");
  Check(g2.Accept(Iv(4, 40, 5), w, 4200), "reset once the new run passed 2 s");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: frame_replay_guard_test frame_replay.vectors\n";
    return 2;
  }
  Vectors(argv[1]);
  InsideWindow();
  MemoryBounded();
  SsrcCap();
  ResetAfterTwoSeconds();
  std::cout << (failures == 0 ? "frame_replay_guard_test: all passed\n"
                              : "frame_replay_guard_test: FAILED\n");
  return failures == 0 ? 0 : 1;
}

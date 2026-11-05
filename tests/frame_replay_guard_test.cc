// Checks the replay guard that patches/webrtc-a545de4.patch adds to WebRTC
// (api/crypto/frame_replay_guard.h; SEC PR-01, hive-node wire-protocol.md 6.6 "Replay", D-075)
// against hive-node's frame_replay vectors, which live outside the WebRTC tree. The bounds, the
// no-reset rule (D-086) and the key-index report have their own tests inside the patch
// (api/crypto/frame_replay_guard_unittest.cc). Built by CI's source-patch job against the
// patched upstream tree; needs only a C++20 compiler.
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
  while (std::getline(in, line)) {
    if (line.empty() || line[0] == '#') continue;
    std::istringstream fields(line);
    std::string iv_hex, verdict;
    fields >> iv_hex >> verdict;
    std::string name;
    std::getline(fields, name);
    std::vector<uint8_t> iv = Hex(iv_hex);
    Check(iv.size() == 12, "12-byte IV:" + name);
    const bool play = guard.Accept(iv, FrameReplayGuard::kAudioWindowTicks);
    Check(play == (verdict == "play"), "vector" + name + ": want " + verdict);
    ++frames;
    if (verdict == "drop") ++drops;
  }
  Check(frames == 15 && drops == 5, "15 frames, 5 drops");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: frame_replay_guard_test frame_replay.vectors\n";
    return 2;
  }
  Vectors(argv[1]);
  std::cout << (failures == 0 ? "frame_replay_guard_test: all passed\n"
                              : "frame_replay_guard_test: FAILED\n");
  return failures == 0 ? 0 : 1;
}

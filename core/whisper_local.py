"""Local Whisper ASR benchmark tool.

Tests local faster-whisper against cloud ASR providers to help decide
which to use as main/fallback for each network environment.

Usage:
    python -m core.whisper_local benchmark test.wav
    python -m core.whisper_local install
"""

from __future__ import annotations

import sys
import time
from pathlib import Path


def install_whisper():
    """Guide user through local Whisper setup."""
    print("=== Local Whisper Setup ===\n")
    print("1. Install faster-whisper:")
    print("   pip install 'voxlog[local]'\n")
    print("2. First run will download the model (~3GB for large-v3).")
    print("   Smaller options: medium (~1.5GB), small (~500MB), base (~150MB)\n")
    print("3. Test with:")
    print("   python -m core.whisper_local benchmark your_audio.wav\n")
    print("Models ranked by Chinese-English quality:")
    print("   large-v3  — best quality, needs 4GB+ RAM, ~2-5s/utterance")
    print("   medium    — good quality, 2GB RAM, ~1-3s/utterance")
    print("   small     — ok quality, 1GB RAM, ~0.5-1.5s/utterance")
    print("   base      — fast but weak on Chinese, <1s/utterance")


def benchmark(audio_path: str, model_size: str = "large-v3"):
    """Benchmark local Whisper on a WAV file."""
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        print("faster-whisper not installed. Run: pip install 'voxlog[local]'")
        return

    path = Path(audio_path)
    if not path.exists():
        print(f"File not found: {audio_path}")
        return

    print(f"Loading model: {model_size}...")
    start = time.monotonic()
    model = WhisperModel(model_size, device="auto", compute_type="auto")
    load_time = time.monotonic() - start
    print(f"Model loaded in {load_time:.1f}s\n")

    print(f"Transcribing: {audio_path}")
    start = time.monotonic()
    segments, info = model.transcribe(str(path), language=None)
    text_parts = []
    for segment in segments:
        text_parts.append(segment.text.strip())

    transcribe_time = time.monotonic() - start
    text = " ".join(text_parts)

    print(f"\n--- Result ---")
    print(f"Text: {text}")
    print(f"Language: {info.language} (prob: {info.language_probability:.2f})")
    print(f"Duration: {info.duration:.1f}s audio")
    print(f"Latency: {transcribe_time:.2f}s ({transcribe_time/max(info.duration, 0.1):.1f}x realtime)")
    print(f"Model: {model_size}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python -m core.whisper_local install")
        print("  python -m core.whisper_local benchmark <wav_file> [model_size]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "install":
        install_whisper()
    elif cmd == "benchmark":
        audio = sys.argv[2] if len(sys.argv) > 2 else None
        model = sys.argv[3] if len(sys.argv) > 3 else "large-v3"
        if not audio:
            print("Usage: python -m core.whisper_local benchmark <wav_file> [model_size]")
        else:
            benchmark(audio, model)

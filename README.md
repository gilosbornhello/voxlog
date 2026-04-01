# VoxLog

Your mouth doesn't have a save button. VoxLog gives it one.

Press a hotkey, speak, and the text is pasted into any app. Every word you've ever
spoken is saved, searchable, and exportable to your knowledge base.

Built for developers who think out loud.

## What it does

- **Press and speak** — global hotkey triggers recording, release to stop
- **Text appears** — ASR transcribes, LLM polishes, text pastes into your current app
- **Everything is saved** — every spoken word archived locally in SQLite
- **Search your voice** — find anything you've ever said
- **Export to Obsidian** — daily Markdown logs for your knowledge base

## What makes it different

| | VoxLog | WisprFlow / Typeless | Omi / Limitless |
|---|--------|---------------------|-----------------|
| Trigger | Active (you press) | Active | Passive (always on) |
| Archive | Yes, local | No | Yes, cloud |
| Hardware | None | None | Wearable pendant |
| Privacy | Local-first | Cloud | Cloud / self-host |
| Open source | MIT | No | Omi: yes |

VoxLog is the only tool that combines **active voice input** with **permanent local archive**.

## Architecture

```
SwiftUI macOS App
  └── spawns Python subprocess (localhost HTTP)
        ├── ASR Router (Qwen / OpenAI Whisper / local Whisper)
        ├── Dictionary (personal term corrections)
        ├── LLM Polish (Qwen-turbo / Ollama)
        └── Archive (SQLite, local)
```

## Quick start

```bash
# Clone
git clone https://github.com/osborn/voxlog.git
cd voxlog

# Install Python dependencies
pip install -e ".[dev]"

# For local Whisper + Ollama (optional)
pip install -e ".[local]"

# Configure API keys
cp .env.example ~/.voxlog/.env
# Edit ~/.voxlog/.env with your API keys

# Run the server
voxlog-server

# Then open the macOS app in Xcode
open macos/VoxLog.xcodeproj
```

## Configuration

VoxLog supports two network environments:

- **Home** (US network exit): Qwen ASR + OpenAI Whisper fallback + OpenAI GPT polish
- **Office** (China domestic): Qwen ASR domestic + local Whisper fallback + Qwen-turbo polish

Switch environments in the menu bar app settings.

## API keys

Create `~/.voxlog/.env`:

```
DASHSCOPE_API_KEY=sk-xxx        # Alibaba Qwen ASR + LLM
OPENAI_API_KEY=sk-xxx           # OpenAI Whisper + GPT (fallback)
VOXLOG_API_TOKEN=your-secret    # localhost server auth token
```

## License

MIT

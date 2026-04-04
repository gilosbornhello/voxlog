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
Tauri desktop shell
  ├── local backend (FastAPI)
  ├── local TS bridge (Fastify)
  ├── local gateway
  ├── SQLite archive + FTS5 search
  └── digest + export integrations
```

## Quick start

```bash
git clone https://github.com/osborn/voxlog.git
cd voxlog

# Build a local alpha DMG for your machine
npm run build:alpha
```

Release builds are published as two separate macOS DMGs:

- `VoxLog-Alpha-arm64.dmg`
- `VoxLog-Alpha-intel.dmg`

Both DMGs include the desktop app, bundled Node runtime, frozen backend binary,
gateway binary, launch agents, and installer scripts.

## Installation

1. Download the DMG that matches your Mac.
2. Open the DMG.
3. Double-click `Install VoxLog.command`.
4. Open `VoxLog.app` from `/Applications`.

## Configuration

VoxLog supports two network environments:

- **Home** (US network exit): Qwen ASR + OpenAI Whisper fallback + OpenAI GPT polish
- **Office** (China domestic): Qwen ASR domestic + local Whisper fallback + Qwen-turbo polish

Switch environments in the menu bar app settings.

## API keys

Create `~/.voxlog/.env`:

```
DASHSCOPE_API_KEY=sk-xxx
OPENAI_API_KEY=sk-xxx
SILICONFLOW_API_KEY=sk-xxx
VOXLOG_API_TOKEN=your-secret
```

## GitHub releases

Push a tag like `v0.1.0` and GitHub Actions will build and upload:

- `VoxLog-Alpha-arm64.dmg` on Apple Silicon runners
- `VoxLog-Alpha-intel.dmg` on Intel runners

## License

MIT

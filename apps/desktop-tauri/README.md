# VoxLog Desktop Tauri

Phase 0 skeleton for the VoxLog desktop shell.

This app is the future desktop entrypoint that will replace the current
SwiftUI/Python localhost shell with a Rust/Tauri shell plus a thin backend
bridge to the existing VoxLog runtime.

## Phase 0 scope

- Global hotkey and permission shell
- Audio session lifecycle events
- Recent utterance contract bridge
- Output/undo command bridge
- Event contract types shared with the Python runtime

## Not in this folder yet

- Full UI
- whisper.cpp binding
- Real audio capture
- Real paste/direct typing implementation

Those pieces should be added behind the command and contract boundaries that
are already scaffolded here.

## Layout

```text
apps/desktop-tauri/
├── package.json          # frontend shell placeholder
├── src/                  # frontend placeholder
└── src-tauri/
    ├── Cargo.toml
    ├── tauri.conf.json
    └── src/
        ├── commands.rs
        ├── contracts.rs
        ├── bridge.rs
        ├── state.rs
        ├── lib.rs
        └── main.rs
```

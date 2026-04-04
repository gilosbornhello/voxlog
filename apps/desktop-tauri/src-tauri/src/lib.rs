mod bridge;
mod commands;
mod contracts;
mod state;

use contracts::GlobalHotkeyEvent;
use tauri::Emitter;
use tauri_plugin_global_shortcut::{Builder as GlobalShortcutBuilder, ShortcutState};
use state::AppState;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(AppState::default())
        .plugin(
            GlobalShortcutBuilder::new()
                .with_handler(|app, shortcut, event| {
                    let phase = match event.state() {
                        ShortcutState::Pressed => "pressed",
                        ShortcutState::Released => "released",
                    };
                    let _ = app.emit(
                        "voxlog2://global-hotkey",
                        GlobalHotkeyEvent {
                            accelerator: shortcut.to_string(),
                            phase: phase.to_string(),
                        },
                    );
                })
                .build(),
        )
        .invoke_handler(tauri::generate_handler![
            commands::get_backend_base_url,
            commands::set_backend_base_url,
            commands::get_hotkey_config,
            commands::set_hotkey_config,
            commands::get_app_settings,
            commands::save_app_settings,
            commands::test_provider_settings,
            commands::preview_local_transcript,
            commands::preview_output_policy,
            commands::get_session_digest,
            commands::get_daily_digest,
            commands::get_project_digest,
            commands::rebuild_digest,
            commands::export_digest_to_obsidian,
            commands::export_digest_to_ai_mate_memory,
            commands::get_backend_health,
            commands::get_history,
            commands::get_agent_history,
            commands::get_agents,
            commands::get_recent_utterance,
            commands::dismiss_recent_utterance,
            commands::retry_recent_utterance,
            commands::set_recent_mode,
            commands::add_recent_dictionary_term,
            commands::undo_output,
            commands::upload_voice,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run VoxLog2 Desktop Tauri shell");
}

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

#[derive(Debug, Clone)]
pub struct AppConfig {
    pub backend_base_url: String,
    pub api_token: Option<String>,
    pub local_stt_model: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            backend_base_url: "http://127.0.0.1:7901".to_string(),
            api_token: None,
            local_stt_model: "base.en-q5_1".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct StoredSettings {
    pub backend_base_url: String,
    pub active_profile: String,
    pub digest_enhancement_enabled: bool,
    pub digest_enhancement_provider: String,
    pub obsidian_vault_dir: String,
    pub ai_mate_memory_dir: String,
    pub onboarding_completed: bool,
    pub hotkey_accelerator: String,
    pub hotkey_enabled: bool,
    pub never_archive_apps: Vec<String>,
    pub fast_path_only_apps: Vec<String>,
    pub disable_direct_typing_apps: Vec<String>,
}

impl Default for StoredSettings {
    fn default() -> Self {
        Self {
            backend_base_url: "http://127.0.0.1:7901".to_string(),
            active_profile: "home".to_string(),
            digest_enhancement_enabled: true,
            digest_enhancement_provider: "auto".to_string(),
            obsidian_vault_dir: String::new(),
            ai_mate_memory_dir: String::new(),
            onboarding_completed: false,
            hotkey_accelerator: "CommandOrControl+Shift+Space".to_string(),
            hotkey_enabled: false,
            never_archive_apps: vec!["1password".to_string(), "keychain access".to_string()],
            fast_path_only_apps: vec!["cursor".to_string(), "claude".to_string()],
            disable_direct_typing_apps: vec!["terminal".to_string(), "iterm".to_string(), "warp".to_string()],
        }
    }
}

#[derive(Debug, Clone)]
pub struct HotkeyState {
    pub accelerator: String,
    pub enabled: bool,
    pub registered: bool,
}

impl Default for HotkeyState {
    fn default() -> Self {
        Self {
            accelerator: "CommandOrControl+Shift+Space".to_string(),
            enabled: false,
            registered: false,
        }
    }
}

pub struct AppState {
    pub config: Mutex<AppConfig>,
    pub hotkey: Mutex<HotkeyState>,
    pub stored_settings: Mutex<StoredSettings>,
}

impl Default for AppState {
    fn default() -> Self {
        let stored_settings = load_stored_settings().unwrap_or_default();
        Self {
            config: Mutex::new(AppConfig {
                backend_base_url: stored_settings.backend_base_url.clone(),
                api_token: None,
                local_stt_model: "base.en-q5_1".to_string(),
            }),
            hotkey: Mutex::new(HotkeyState {
                accelerator: stored_settings.hotkey_accelerator.clone(),
                enabled: stored_settings.hotkey_enabled,
                registered: false,
            }),
            stored_settings: Mutex::new(stored_settings),
        }
    }
}

pub fn settings_file_path() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".to_string()))
        .join(".voxlog2")
        .join("desktop-settings.json")
}

pub fn load_stored_settings() -> Result<StoredSettings, String> {
    let path = settings_file_path();
    if !path.exists() {
        return Ok(StoredSettings::default());
    }
    let text = fs::read_to_string(&path).map_err(|err| err.to_string())?;
    serde_json::from_str(&text).map_err(|err| err.to_string())
}

pub fn save_stored_settings(settings: &StoredSettings) -> Result<(), String> {
    let path = settings_file_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let text = serde_json::to_string_pretty(settings).map_err(|err| err.to_string())?;
    fs::write(path, text).map_err(|err| err.to_string())
}

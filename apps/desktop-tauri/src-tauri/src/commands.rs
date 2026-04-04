use tauri::{AppHandle, State};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut};

use crate::bridge;
use crate::contracts::{
    AppRuleSet,
    AppSettingsInput,
    AppSettingsSnapshot,
    AgentSummary,
    AIMateMemoryExportInput,
    AIMateMemoryExportResponse,
    DigestRebuildInput,
    FastPathResponse,
    HotkeyConfig,
    HealthResponse,
    HistoryItem,
    LocalTranscriptPreview,
    OutputPolicyPreview,
    ObsidianExportInput,
    ObsidianExportResponse,
    ProviderFlags,
    ProviderConnectivityResponse,
    ProviderSettingsResponse,
    RecentDictionaryResponse,
    RecentDismissResponse,
    RecentEnvelope,
    RecentModeResponse,
    RecentRetryResponse,
    SessionDigest,
    UndoOutputResponse,
};
use crate::state::{save_stored_settings, AppState, StoredSettings};
use voxlog_input_output::{decide_output_policy, OutputPolicyRequest, OutputStrategy, RiskLevel};
use voxlog_stt_whispercpp::{AudioPreviewRequest, WhisperCppConfig, WhisperCppEngine};

const KEYRING_SERVICE: &str = "com.voxlog2.desktop";

fn parse_risk_level(value: &str) -> RiskLevel {
    match value.trim().to_ascii_lowercase().as_str() {
        "high" => RiskLevel::High,
        "medium" => RiskLevel::Medium,
        _ => RiskLevel::Low,
    }
}

fn keyring_get(name: &str) -> Option<String> {
    keyring::Entry::new(KEYRING_SERVICE, name)
        .ok()
        .and_then(|entry| entry.get_password().ok())
}

fn keyring_set(name: &str, value: Option<String>) -> Result<(), String> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, name).map_err(|err| err.to_string())?;
    match value {
        Some(secret) if !secret.trim().is_empty() => entry
            .set_password(secret.trim())
            .map_err(|err| err.to_string()),
        Some(_) => entry.delete_credential().map_err(|err| err.to_string()).or(Ok(())),
        None => Ok(()),
    }
}

fn settings_snapshot(
    config: &crate::state::AppConfig,
    stored: &StoredSettings,
    hotkey: &crate::state::HotkeyState,
    provider: Option<ProviderSettingsResponse>,
) -> AppSettingsSnapshot {
    let provider_flags = provider
        .as_ref()
        .map(|payload| ProviderFlags {
            dashscope_us: payload.providers.dashscope_us.configured,
            dashscope_cn: payload.providers.dashscope_cn.configured,
            openai: payload.providers.openai.configured,
            siliconflow: payload.providers.siliconflow.configured,
        })
        .unwrap_or_default();

    let profiles = provider.map(|payload| payload.profiles).unwrap_or_default();

    AppSettingsSnapshot {
        backend_base_url: config.backend_base_url.clone(),
        backend_api_token_present: config.api_token.as_ref().is_some_and(|value| !value.is_empty()),
        active_profile: stored.active_profile.clone(),
        digest_enhancement_enabled: stored.digest_enhancement_enabled,
        digest_enhancement_provider: stored.digest_enhancement_provider.clone(),
        obsidian_vault_dir: stored.obsidian_vault_dir.clone(),
        ai_mate_memory_dir: stored.ai_mate_memory_dir.clone(),
        onboarding_completed: stored.onboarding_completed,
        hotkey_accelerator: hotkey.accelerator.clone(),
        hotkey_enabled: hotkey.enabled,
        app_rules: AppRuleSet {
            never_archive_apps: stored.never_archive_apps.clone(),
            fast_path_only_apps: stored.fast_path_only_apps.clone(),
            disable_direct_typing_apps: stored.disable_direct_typing_apps.clone(),
        },
        provider_flags,
        profiles,
    }
}

fn apply_hotkey_state(
    app: &AppHandle,
    hotkey: &mut crate::state::HotkeyState,
    accelerator: &str,
    enabled: bool,
) -> Result<(), String> {
    let parsed = accelerator
        .parse::<Shortcut>()
        .map_err(|err| format!("invalid accelerator: {err}"))?;

    if hotkey.registered {
        let current = hotkey
            .accelerator
            .parse::<Shortcut>()
            .map_err(|err| format!("invalid current accelerator: {err}"))?;
        app.global_shortcut()
            .unregister(current)
            .map_err(|err| err.to_string())?;
        hotkey.registered = false;
    }

    hotkey.accelerator = accelerator.trim().to_string();
    hotkey.enabled = enabled;

    if hotkey.enabled {
        app.global_shortcut()
            .register(parsed)
            .map_err(|err| err.to_string())?;
        hotkey.registered = true;
    }

    Ok(())
}

#[tauri::command]
pub async fn get_backend_base_url(state: State<'_, AppState>) -> Result<String, String> {
    let config = state
        .config
        .lock()
        .map_err(|_| "state lock failed".to_string())?
        .clone();
    Ok(config.backend_base_url)
}

#[tauri::command]
pub async fn get_hotkey_config(state: State<'_, AppState>) -> Result<HotkeyConfig, String> {
    let hotkey = state
        .hotkey
        .lock()
        .map_err(|_| "state lock failed".to_string())?
        .clone();
    Ok(HotkeyConfig {
        accelerator: hotkey.accelerator,
        enabled: hotkey.enabled,
        registered: hotkey.registered,
    })
}

#[tauri::command]
pub async fn get_app_settings(state: State<'_, AppState>) -> Result<AppSettingsSnapshot, String> {
    {
        let mut config = state
            .config
            .lock()
            .map_err(|_| "state lock failed".to_string())?;
        config.api_token = keyring_get("backend_api_token");
    }

    let provider_payload = {
        let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
        bridge::get_json::<ProviderSettingsResponse>(&config, "/v1/settings/providers")
            .await
            .ok()
    };

    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    let stored = state
        .stored_settings
        .lock()
        .map_err(|_| "state lock failed".to_string())?
        .clone();
    let hotkey = state.hotkey.lock().map_err(|_| "state lock failed".to_string())?.clone();

    Ok(settings_snapshot(&config, &stored, &hotkey, provider_payload))
}

#[tauri::command]
pub async fn save_app_settings(
    input: AppSettingsInput,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<AppSettingsSnapshot, String> {
    keyring_set("backend_api_token", input.backend_api_token.clone())?;
    keyring_set("dashscope_key_us", input.dashscope_key_us.clone())?;
    keyring_set("dashscope_key_cn", input.dashscope_key_cn.clone())?;
    keyring_set("openai_key", input.openai_key.clone())?;
    keyring_set("siliconflow_key", input.siliconflow_key.clone())?;

    {
        let mut stored = state
            .stored_settings
            .lock()
            .map_err(|_| "state lock failed".to_string())?;
        stored.backend_base_url = input.backend_base_url.trim().trim_end_matches('/').to_string();
        stored.active_profile = input.active_profile.trim().to_string();
        stored.digest_enhancement_enabled = input.digest_enhancement_enabled;
        stored.digest_enhancement_provider = input.digest_enhancement_provider.trim().to_string();
        stored.obsidian_vault_dir = input.obsidian_vault_dir.trim().to_string();
        stored.ai_mate_memory_dir = input.ai_mate_memory_dir.trim().to_string();
        stored.onboarding_completed = input.onboarding_completed;
        stored.hotkey_accelerator = input.hotkey_accelerator.trim().to_string();
        stored.hotkey_enabled = input.hotkey_enabled;
        stored.never_archive_apps = input.app_rules.never_archive_apps.clone();
        stored.fast_path_only_apps = input.app_rules.fast_path_only_apps.clone();
        stored.disable_direct_typing_apps = input.app_rules.disable_direct_typing_apps.clone();
        save_stored_settings(&stored)?;
    }

    {
        let mut config = state
            .config
            .lock()
            .map_err(|_| "state lock failed".to_string())?;
        config.backend_base_url = input.backend_base_url.trim().trim_end_matches('/').to_string();
        config.api_token = keyring_get("backend_api_token");
    }

    {
        let mut hotkey = state
            .hotkey
            .lock()
            .map_err(|_| "state lock failed".to_string())?;
        apply_hotkey_state(&app, &mut hotkey, &input.hotkey_accelerator, input.hotkey_enabled)?;
    }

    let provider_payload = {
        let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
        let body = serde_json::json!({
            "active_profile": input.active_profile,
            "digest_enhancement_enabled": input.digest_enhancement_enabled,
            "digest_enhancement_provider": input.digest_enhancement_provider,
            "dashscope_key_us": keyring_get("dashscope_key_us"),
            "dashscope_key_cn": keyring_get("dashscope_key_cn"),
            "openai_key": keyring_get("openai_key"),
            "siliconflow_key": keyring_get("siliconflow_key"),
        });
        bridge::post_json::<ProviderSettingsResponse, _>(&config, "/v1/settings/providers", &body)
            .await
            .ok()
    };

    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    let stored = state
        .stored_settings
        .lock()
        .map_err(|_| "state lock failed".to_string())?
        .clone();

    let hotkey = state.hotkey.lock().map_err(|_| "state lock failed".to_string())?.clone();

    Ok(settings_snapshot(&config, &stored, &hotkey, provider_payload))
}

#[tauri::command]
pub async fn test_provider_settings(
    state: State<'_, AppState>,
) -> Result<ProviderConnectivityResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::get_json(&config, "/v1/settings/providers/test")
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn preview_local_transcript(
    duration_ms: u64,
    mime_type: String,
    target_app: String,
    session_id: String,
    state: State<'_, AppState>,
) -> Result<LocalTranscriptPreview, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    let engine = WhisperCppEngine::new(WhisperCppConfig {
        model: config.local_stt_model,
        language_hint: "auto".to_string(),
        max_partial_chars: 96,
    });
    let preview = engine.preview(&AudioPreviewRequest {
        mime_type,
        duration_ms,
        target_app,
        session_id,
    });
    Ok(LocalTranscriptPreview {
        provider: preview.provider,
        model: preview.model,
        partial_text: preview.partial_text,
        final_hint: preview.final_hint,
        confidence_hint: preview.confidence_hint,
        segment_count: preview.segment_count,
    })
}

#[tauri::command]
pub async fn preview_output_policy(
    target_app: String,
    risk_level: String,
    requested_mode: String,
    app_rules: AppRuleSet,
) -> Result<OutputPolicyPreview, String> {
    let decision = decide_output_policy(&OutputPolicyRequest {
        target_app,
        requested_mode,
        risk_level: parse_risk_level(&risk_level),
        never_archive_apps: app_rules.never_archive_apps,
        fast_path_only_apps: app_rules.fast_path_only_apps,
        disable_direct_typing_apps: app_rules.disable_direct_typing_apps,
    });
    Ok(OutputPolicyPreview {
        strategy: match decision.strategy {
            OutputStrategy::Paste => "paste".to_string(),
            OutputStrategy::DirectTyping => "direct_typing".to_string(),
            OutputStrategy::PreviewOnly => "preview_only".to_string(),
        },
        should_confirm: decision.should_confirm,
        should_archive: decision.should_archive,
        reason: decision.reason,
    })
}

#[tauri::command]
pub async fn get_session_digest(
    session_id: String,
    state: State<'_, AppState>,
) -> Result<SessionDigest, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    let path = format!("/v1/digests/session?session_id={}", urlencoding::encode(&session_id));
    bridge::get_json(&config, &path)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn get_daily_digest(
    date: String,
    state: State<'_, AppState>,
) -> Result<SessionDigest, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    let path = format!("/v1/digests/daily?date={}", urlencoding::encode(&date));
    bridge::get_json(&config, &path)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn get_project_digest(
    project_key: String,
    state: State<'_, AppState>,
) -> Result<SessionDigest, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    let path = format!("/v1/digests/project?project_key={}", urlencoding::encode(&project_key));
    bridge::get_json(&config, &path)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn rebuild_digest(
    input: DigestRebuildInput,
    state: State<'_, AppState>,
) -> Result<SessionDigest, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_json(&config, "/v1/digests/rebuild", &input)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn export_digest_to_obsidian(
    input: ObsidianExportInput,
    state: State<'_, AppState>,
) -> Result<ObsidianExportResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_json(&config, "/v1/integrations/obsidian/export", &input)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn export_digest_to_ai_mate_memory(
    input: AIMateMemoryExportInput,
    state: State<'_, AppState>,
) -> Result<AIMateMemoryExportResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_json(&config, "/v1/integrations/ai-mate-memory/export", &input)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn set_hotkey_config(
    accelerator: String,
    enabled: bool,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<HotkeyConfig, String> {
    let mut hotkey = state
        .hotkey
        .lock()
        .map_err(|_| "state lock failed".to_string())?;
    apply_hotkey_state(&app, &mut hotkey, &accelerator, enabled)?;

    Ok(HotkeyConfig {
        accelerator: hotkey.accelerator.clone(),
        enabled: hotkey.enabled,
        registered: hotkey.registered,
    })
}

#[tauri::command]
pub async fn set_backend_base_url(
    backend_base_url: String,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let mut config = state
        .config
        .lock()
        .map_err(|_| "state lock failed".to_string())?;
    config.backend_base_url = backend_base_url.trim().trim_end_matches('/').to_string();
    Ok(config.backend_base_url.clone())
}

#[tauri::command]
pub async fn get_recent_utterance(state: State<'_, AppState>) -> Result<RecentEnvelope, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::get_json(&config, "/v1/recent")
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn get_backend_health(state: State<'_, AppState>) -> Result<HealthResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::get_json(&config, "/health")
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn get_history(
    q: String,
    limit: i32,
    state: State<'_, AppState>,
) -> Result<Vec<HistoryItem>, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    let path = format!("/v1/history?q={}&limit={}", urlencoding::encode(&q), limit.max(1));
    bridge::get_json(&config, &path)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn get_agent_history(
    agent: String,
    limit: i32,
    state: State<'_, AppState>,
) -> Result<Vec<HistoryItem>, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    let path = format!(
        "/v1/history/agent?agent={}&limit={}",
        urlencoding::encode(&agent),
        limit.max(1)
    );
    bridge::get_json(&config, &path)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn get_agents(state: State<'_, AppState>) -> Result<Vec<AgentSummary>, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::get_json(&config, "/v1/agents")
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn dismiss_recent_utterance(
    utterance_id: String,
    state: State<'_, AppState>,
) -> Result<RecentDismissResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_form(
        &config,
        "/v1/recent/dismiss",
        &[("utterance_id", utterance_id)],
    )
    .await
    .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn undo_output(
    output_id: String,
    state: State<'_, AppState>,
) -> Result<UndoOutputResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_form(&config, "/v1/output/undo", &[("output_id", output_id)])
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn retry_recent_utterance(
    utterance_id: String,
    provider: String,
    state: State<'_, AppState>,
) -> Result<RecentRetryResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_form(
        &config,
        "/v1/recent/retry",
        &[("utterance_id", utterance_id), ("provider", provider)],
    )
    .await
    .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn set_recent_mode(
    utterance_id: String,
    mode: String,
    state: State<'_, AppState>,
) -> Result<RecentModeResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_form(
        &config,
        "/v1/recent/mode",
        &[("utterance_id", utterance_id), ("mode", mode)],
    )
    .await
    .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn add_recent_dictionary_term(
    utterance_id: String,
    wrong: String,
    right: String,
    state: State<'_, AppState>,
) -> Result<RecentDictionaryResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_form(
        &config,
        "/v1/recent/dictionary",
        &[("utterance_id", utterance_id), ("wrong", wrong), ("right", right)],
    )
    .await
    .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn upload_voice(
    audio_base64: String,
    mime_type: String,
    source: String,
    target_app: String,
    session_id: String,
    mode: String,
    state: State<'_, AppState>,
) -> Result<FastPathResponse, String> {
    let config = state.config.lock().map_err(|_| "state lock failed".to_string())?.clone();
    bridge::post_voice_upload(
        &config,
        &audio_base64,
        &mime_type,
        &source,
        &target_app,
        &session_id,
        &mode,
    )
    .await
    .map_err(|err| err.to_string())
}

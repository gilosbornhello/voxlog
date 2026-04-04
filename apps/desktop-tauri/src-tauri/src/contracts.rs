use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordMode {
    Normal,
    Private,
    Ephemeral,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TargetRiskLevel {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OutputMode {
    Paste,
    DirectTyping,
    PreviewOnly,
    None,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FastPathStatus {
    Ok,
    NeedsReview,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FastPathResponse {
    pub id: String,
    pub status: FastPathStatus,
    pub raw_text: String,
    pub display_text: String,
    pub stt_provider: String,
    pub stt_model: String,
    pub target_app: String,
    pub target_risk_level: TargetRiskLevel,
    pub should_autopaste: bool,
    pub needs_review: bool,
    pub confidence: f32,
    pub dictionary_applied: Vec<DictionaryReplacement>,
    pub latency_ms: i32,
    pub session_id: String,
    pub utterance_id: String,
    pub output_id: String,
    pub output_mode: OutputMode,
    pub archive_status: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DictionaryReplacement {
    pub from: String,
    pub to: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecentUtterance {
    pub id: String,
    pub utterance_id: String,
    pub session_id: String,
    pub output_id: String,
    pub status: FastPathStatus,
    pub raw_text: String,
    pub display_text: String,
    pub target_app: String,
    pub target_risk_level: TargetRiskLevel,
    pub recording_mode: RecordMode,
    pub output_mode: OutputMode,
    pub archive_status: String,
    pub confidence: f32,
    pub stt_provider: String,
    pub stt_model: String,
    pub dictionary_applied: Vec<DictionaryReplacement>,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecentEnvelope {
    pub recent: Option<RecentUtterance>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UndoOutputResponse {
    pub output_id: String,
    pub utterance_id: String,
    pub accepted: bool,
    pub archive_recalled: bool,
    pub ui_undo_required: bool,
    pub mode: RecordMode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecentModeResponse {
    pub utterance_id: String,
    pub mode: RecordMode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecentDismissResponse {
    pub utterance_id: String,
    pub dismissed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DictionaryPayload {
    pub version: Option<i32>,
    pub corrections: HashMap<String, String>,
    pub preserve: Vec<String>,
    pub format_rules: Option<DictionaryFormatRules>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DictionaryFormatRules {
    pub cn_en_space: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecentDictionaryResponse {
    pub utterance_id: String,
    pub wrong: String,
    pub right: String,
    pub dictionary: DictionaryPayload,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecentRetryResponse {
    pub id: String,
    pub utterance_id: String,
    pub session_id: String,
    pub output_id: String,
    pub status: FastPathStatus,
    pub raw_text: String,
    pub display_text: String,
    pub target_app: String,
    pub target_risk_level: TargetRiskLevel,
    pub recording_mode: RecordMode,
    pub output_mode: OutputMode,
    pub archive_status: String,
    pub confidence: f32,
    pub stt_provider: String,
    pub stt_model: String,
    pub dictionary_applied: Vec<DictionaryReplacement>,
    pub expires_at: i64,
    pub retried_from: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HotkeyConfig {
    pub accelerator: String,
    pub enabled: bool,
    pub registered: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GlobalHotkeyEvent {
    pub accelerator: String,
    pub phase: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub service: Option<String>,
    pub version: Option<String>,
    pub profile: Option<String>,
    pub python_backend_base_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryItem {
    pub id: String,
    pub created_at: String,
    pub utterance_id: String,
    pub output_id: String,
    pub session_id: String,
    pub raw_text: String,
    pub display_text: String,
    pub polished_text: String,
    pub stt_provider: String,
    pub stt_model: String,
    pub llm_provider: String,
    pub latency_ms: i32,
    pub target_app: String,
    pub target_risk_level: TargetRiskLevel,
    pub role: String,
    pub recording_mode: RecordMode,
    pub output_mode: OutputMode,
    pub confidence: f32,
    pub archive_status: String,
    pub agent: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentSummary {
    pub agent: String,
    pub count: i32,
    pub last_active: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProviderFlags {
    pub dashscope_us: bool,
    pub dashscope_cn: bool,
    pub openai: bool,
    pub siliconflow: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderProfile {
    pub name: String,
    pub stt_main: String,
    pub stt_fallback: String,
    pub llm_main: String,
    pub llm_fallback: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettingsSnapshot {
    pub backend_base_url: String,
    pub backend_api_token_present: bool,
    pub active_profile: String,
    pub digest_enhancement_enabled: bool,
    pub digest_enhancement_provider: String,
    pub obsidian_vault_dir: String,
    pub ai_mate_memory_dir: String,
    pub onboarding_completed: bool,
    pub hotkey_accelerator: String,
    pub hotkey_enabled: bool,
    pub app_rules: AppRuleSet,
    pub provider_flags: ProviderFlags,
    pub profiles: Vec<ProviderProfile>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppSettingsInput {
    pub backend_base_url: String,
    pub backend_api_token: Option<String>,
    pub active_profile: String,
    pub digest_enhancement_enabled: bool,
    pub digest_enhancement_provider: String,
    pub obsidian_vault_dir: String,
    pub ai_mate_memory_dir: String,
    pub onboarding_completed: bool,
    pub hotkey_accelerator: String,
    pub hotkey_enabled: bool,
    pub app_rules: AppRuleSet,
    pub dashscope_key_us: Option<String>,
    pub dashscope_key_cn: Option<String>,
    pub openai_key: Option<String>,
    pub siliconflow_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppRuleSet {
    pub never_archive_apps: Vec<String>,
    pub fast_path_only_apps: Vec<String>,
    pub disable_direct_typing_apps: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderSettingsResponse {
    pub providers: ProviderSettingsProviders,
    pub active_profile: String,
    pub profiles: Vec<ProviderProfile>,
    pub backend_auth_required: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConnectivityCheck {
    pub key: String,
    pub label: String,
    pub status: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConnectivityResponse {
    pub ready: bool,
    pub active_profile: String,
    pub recommended_stt_provider: String,
    pub backend_url_reachable: bool,
    pub configured_provider_count: i32,
    pub checks: Vec<ProviderConnectivityCheck>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderSettingsProviders {
    pub dashscope_us: ProviderConfigured,
    pub dashscope_cn: ProviderConfigured,
    pub openai: ProviderConfigured,
    pub siliconflow: ProviderConfigured,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConfigured {
    pub configured: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalTranscriptPreview {
    pub provider: String,
    pub model: String,
    pub partial_text: String,
    pub final_hint: String,
    pub confidence_hint: f32,
    pub segment_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutputPolicyPreview {
    pub strategy: String,
    pub should_confirm: bool,
    pub should_archive: bool,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionDigest {
    pub id: String,
    pub digest_type: String,
    pub session_id: String,
    pub digest_date: String,
    pub project_key: String,
    pub source_event_id: String,
    pub created_at: String,
    pub updated_at: String,
    pub summary: String,
    pub intent: String,
    pub suggested_tags: Vec<String>,
    pub mentioned_entities: Vec<String>,
    pub enhanced: bool,
    pub enhancer_provider: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DigestRebuildInput {
    pub scope: String,
    pub session_id: Option<String>,
    pub date: Option<String>,
    pub project_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObsidianExportInput {
    pub scope: String,
    pub vault_dir: String,
    pub session_id: Option<String>,
    pub date: Option<String>,
    pub project_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObsidianExportResponse {
    pub ok: bool,
    pub vault_path: String,
    pub note_path: String,
    pub bytes_written: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIMateMemoryExportInput {
    pub scope: String,
    pub base_dir: String,
    pub session_id: Option<String>,
    pub date: Option<String>,
    pub project_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIMateMemoryExportResponse {
    pub ok: bool,
    pub base_path: String,
    pub record_path: String,
    pub bytes_written: i32,
}

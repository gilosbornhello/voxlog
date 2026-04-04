use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WhisperCppConfig {
    pub model: String,
    pub language_hint: String,
    pub max_partial_chars: usize,
}

impl Default for WhisperCppConfig {
    fn default() -> Self {
        Self {
            model: "base.en-q5_1".to_string(),
            language_hint: "auto".to_string(),
            max_partial_chars: 96,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptPreview {
    pub provider: String,
    pub model: String,
    pub partial_text: String,
    pub final_hint: String,
    pub confidence_hint: f32,
    pub segment_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioPreviewRequest {
    pub mime_type: String,
    pub duration_ms: u64,
    pub target_app: String,
    pub session_id: String,
}

#[derive(Debug, Default)]
pub struct WhisperCppEngine {
    config: WhisperCppConfig,
}

impl WhisperCppEngine {
    pub fn new(config: WhisperCppConfig) -> Self {
        Self { config }
    }

    pub fn config(&self) -> &WhisperCppConfig {
        &self.config
    }

    pub fn preview(&self, request: &AudioPreviewRequest) -> TranscriptPreview {
        let seconds = ((request.duration_ms as f32) / 1000.0).max(0.2);
        let segments = seconds.ceil() as usize;
        let app = request.target_app.trim();
        let app_name = if app.is_empty() { "current app" } else { app };
        let partial = format!(
            "Listening in {app_name} for {seconds:.1}s using whisper.cpp local preview"
        );
        let clipped = partial
            .chars()
            .take(self.config.max_partial_chars)
            .collect::<String>();

        TranscriptPreview {
            provider: "whispercpp-local".to_string(),
            model: self.config.model.clone(),
            partial_text: clipped,
            final_hint: format!(
                "Finalize locally for session {} once capture stops",
                request.session_id
            ),
            confidence_hint: (0.55 + (seconds.min(6.0) / 10.0)).min(0.97),
            segment_count: segments.max(1),
        }
    }
}

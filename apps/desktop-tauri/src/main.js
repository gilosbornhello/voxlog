const isTauri =
  typeof window !== "undefined" &&
  window.__TAURI__ &&
  typeof window.__TAURI__.core?.invoke === "function";

const invoke = async (command, args = {}) => {
  if (!isTauri) {
    throw new Error("Tauri runtime not available");
  }
  return window.__TAURI__.core.invoke(command, args);
};

const listen = async (event, handler) => {
  if (!isTauri || typeof window.__TAURI__.event?.listen !== "function") {
    return () => {};
  }
  return window.__TAURI__.event.listen(event, handler);
};

const storage = {
  get(key, fallback = "") {
    try {
      const value = window.localStorage.getItem(key);
      return value ?? fallback;
    } catch {
      return fallback;
    }
  },
  set(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // ignore storage failures
    }
  },
  getBool(key, fallback = false) {
    const value = storage.get(key, fallback ? "true" : "false");
    return value === "true";
  },
};

const STORAGE_KEYS = {
  backendUrl: "voxlog2.backendUrl",
  hotkeyAccelerator: "voxlog2.hotkeyAccelerator",
  hotkeyEnabled: "voxlog2.hotkeyEnabled",
  targetApp: "voxlog2.targetApp",
  targetRisk: "voxlog2.targetRisk",
  sessionId: "voxlog2.sessionId",
  recordMode: "voxlog2.recordMode",
  retryProvider: "voxlog2.retryProvider",
  historyQuery: "voxlog2.historyQuery",
  historyAgent: "voxlog2.historyAgent",
  historySession: "voxlog2.historySession",
  historyCurrentOnly: "voxlog2.historyCurrentOnly",
};

const elements = {
  backendUrl: document.querySelector("#backend-url"),
  saveBackend: document.querySelector("#save-backend"),
  saveSettings: document.querySelector("#save-settings"),
  syncSettings: document.querySelector("#sync-settings"),
  testSettings: document.querySelector("#test-settings"),
  rebuildDigest: document.querySelector("#rebuild-digest"),
  exportObsidian: document.querySelector("#export-obsidian"),
  exportAiMateMemory: document.querySelector("#export-ai-mate-memory"),
  completeOnboarding: document.querySelector("#complete-onboarding"),
  hotkeyAccelerator: document.querySelector("#hotkey-accelerator"),
  hotkeyEnabled: document.querySelector("#hotkey-enabled"),
  saveHotkey: document.querySelector("#save-hotkey"),
  refreshRecent: document.querySelector("#refresh-recent"),
  refreshHealth: document.querySelector("#refresh-health"),
  refreshDigest: document.querySelector("#refresh-digest"),
  refreshHistory: document.querySelector("#refresh-history"),
  dismissRecent: document.querySelector("#dismiss-recent"),
  undoOutput: document.querySelector("#undo-output"),
  retryRecent: document.querySelector("#retry-recent"),
  applyRecentMode: document.querySelector("#apply-recent-mode"),
  addDictionary: document.querySelector("#add-dictionary"),
  refreshPermissions: document.querySelector("#refresh-permissions"),
  startRecording: document.querySelector("#start-recording"),
  stopRecording: document.querySelector("#stop-recording"),
  newSession: document.querySelector("#new-session"),
  targetApp: document.querySelector("#target-app"),
  targetRisk: document.querySelector("#target-risk"),
  backendApiToken: document.querySelector("#backend-api-token"),
  activeProfile: document.querySelector("#active-profile"),
  profileSummary: document.querySelector("#profile-summary"),
  providerRecommendation: document.querySelector("#provider-recommendation"),
  neverArchiveApps: document.querySelector("#never-archive-apps"),
  fastPathOnlyApps: document.querySelector("#fast-path-only-apps"),
  disableDirectTypingApps: document.querySelector("#disable-direct-typing-apps"),
  dashscopeKeyUs: document.querySelector("#dashscope-key-us"),
  dashscopeKeyCn: document.querySelector("#dashscope-key-cn"),
  openaiKey: document.querySelector("#openai-key"),
  siliconflowKey: document.querySelector("#siliconflow-key"),
  digestEnhancementEnabled: document.querySelector("#digest-enhancement-enabled"),
  digestEnhancementProvider: document.querySelector("#digest-enhancement-provider"),
  obsidianVaultDir: document.querySelector("#obsidian-vault-dir"),
  aiMateMemoryDir: document.querySelector("#ai-mate-memory-dir"),
  sessionId: document.querySelector("#session-id"),
  recordMode: document.querySelector("#record-mode"),
  retryProvider: document.querySelector("#retry-provider"),
  historyQuery: document.querySelector("#history-query"),
  historyAgent: document.querySelector("#history-agent"),
  historySession: document.querySelector("#history-session"),
  useCurrentSession: document.querySelector("#use-current-session"),
  historyCurrentOnly: document.querySelector("#history-current-only"),
  recentModeSelect: document.querySelector("#recent-mode-select"),
  dictionaryWrong: document.querySelector("#dictionary-wrong"),
  dictionaryRight: document.querySelector("#dictionary-right"),
  hotkeyStatus: document.querySelector("#hotkey-status"),
  providerStatus: document.querySelector("#provider-status"),
  settingsStatus: document.querySelector("#settings-status"),
  onboardingStatus: document.querySelector("#onboarding-status"),
  bridgeStatus: document.querySelector("#bridge-status"),
  permissionStatus: document.querySelector("#permission-status"),
  recordingStatus: document.querySelector("#recording-status"),
  transcriptStatus: document.querySelector("#transcript-status"),
  digestStatus: document.querySelector("#digest-status"),
  digestType: document.querySelector("#digest-type"),
  digestDate: document.querySelector("#digest-date"),
  digestProjectKey: document.querySelector("#digest-project-key"),
  recentStatus: document.querySelector("#recent-status"),
  historyStatus: document.querySelector("#history-status"),
  recentEmpty: document.querySelector("#recent-empty"),
  onboardingPanel: document.querySelector("#onboarding-panel"),
  recentCard: document.querySelector("#recent-card"),
  historyEmpty: document.querySelector("#history-empty"),
  historyList: document.querySelector("#history-list"),
  recentApp: document.querySelector("#recent-app"),
  recentRisk: document.querySelector("#recent-risk"),
  recentProvider: document.querySelector("#recent-provider"),
  recentConfidence: document.querySelector("#recent-confidence"),
  recentDisplay: document.querySelector("#recent-display"),
  recentRaw: document.querySelector("#recent-raw"),
  recentIds: document.querySelector("#recent-ids"),
  transcriptProvider: document.querySelector("#transcript-provider"),
  transcriptModel: document.querySelector("#transcript-model"),
  transcriptSegments: document.querySelector("#transcript-segments"),
  partialTranscript: document.querySelector("#partial-transcript"),
  finalTranscript: document.querySelector("#final-transcript"),
  outputPolicyStrategy: document.querySelector("#output-policy-strategy"),
  outputPolicyReason: document.querySelector("#output-policy-reason"),
  digestSummary: document.querySelector("#digest-summary"),
  digestIntent: document.querySelector("#digest-intent"),
  digestTags: document.querySelector("#digest-tags"),
  digestEntities: document.querySelector("#digest-entities"),
  digestEnhancer: document.querySelector("#digest-enhancer"),
  digestRebuiltAt: document.querySelector("#digest-rebuilt-at"),
  digestExportStatus: document.querySelector("#digest-export-status"),
  aiMateExportStatus: document.querySelector("#ai-mate-export-status"),
  policyPreviewCard: document.querySelector("#policy-preview-card"),
  policyPreviewStatus: document.querySelector("#policy-preview-status"),
  policyPreviewText: document.querySelector("#policy-preview-text"),
  policyPreviewSend: document.querySelector("#policy-preview-send"),
  policyPreviewCancel: document.querySelector("#policy-preview-cancel"),
  activityLog: document.querySelector("#activity-log"),
  providerFlags: document.querySelector("#provider-flags"),
  settingsChecks: document.querySelector("#settings-checks"),
  onboardingChecks: document.querySelector("#onboarding-checks"),
};

let currentRecent = null;
let currentSettingsSnapshot = null;
let currentConnectivity = null;
let mediaRecorder = null;
let mediaChunks = [];
let mediaStream = null;
let isRecording = false;
let globalHotkeyUnlisten = null;
let microphonePermissionStatus = null;
let healthPollTimer = null;
let recentPollTimer = null;
let historyPollTimer = null;
let recordingStartedAt = 0;
let previewPollTimer = null;
let currentOutputPolicy = null;
let pendingUploadPayload = null;

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function parseRuleList(value) {
  return String(value || "")
    .split("\n")
    .map((item) => item.trim())
    .filter(Boolean);
}

function joinRuleList(items) {
  return (items || []).join("\n");
}

function log(message, data) {
  const stamp = new Date().toLocaleTimeString();
  const line = data ? `[${stamp}] ${message} ${JSON.stringify(data)}` : `[${stamp}] ${message}`;
  elements.activityLog.textContent = `${line}\n${elements.activityLog.textContent}`.trim();
}

function setBadge(node, label, kind = "neutral") {
  node.textContent = label;
  node.className = `badge ${kind}`;
}

function renderRecent(recent) {
  currentRecent = recent;
  if (!recent) {
    elements.recentEmpty.classList.remove("hidden");
    elements.recentCard.classList.add("hidden");
    setBadge(elements.recentStatus, "Waiting", "neutral");
    return;
  }

  elements.recentEmpty.classList.add("hidden");
  elements.recentCard.classList.remove("hidden");
  elements.recentApp.textContent = recent.target_app || "Unknown";
  elements.recentRisk.textContent = recent.target_risk_level;
  elements.recentProvider.textContent = `${recent.stt_provider} / ${recent.stt_model}`;
  elements.recentConfidence.textContent = recent.confidence.toFixed(2);
  elements.recentDisplay.textContent = recent.display_text || "(empty)";
  elements.recentRaw.textContent = recent.raw_text || "(empty)";
  elements.recentIds.textContent = `${recent.utterance_id} / ${recent.output_id}`;
  elements.recentModeSelect.value = recent.recording_mode;
  if (!elements.dictionaryWrong.value.trim()) {
    elements.dictionaryWrong.value = recent.raw_text || "";
  }
  setBadge(
    elements.recentStatus,
    recent.status === "needs_review" ? "Needs Review" : "Ready",
    recent.status === "needs_review" ? "warn" : "live",
  );
}

function renderHistory(items) {
  elements.historyList.innerHTML = "";
  if (!items.length) {
    elements.historyEmpty.classList.remove("hidden");
    elements.historyList.classList.add("hidden");
    setBadge(elements.historyStatus, "Empty", "neutral");
    return;
  }

  elements.historyEmpty.classList.add("hidden");
  elements.historyList.classList.remove("hidden");
  setBadge(elements.historyStatus, `${items.length} Items`, "live");

  for (const item of items) {
    const card = document.createElement("article");
    card.className = "history-item";
    card.innerHTML = `
      <div class="history-item-header">
        <strong>${item.target_app || "Unknown"}</strong>
        <div class="history-item-meta">
          <span>${item.agent || "no-agent"}</span>
          <span>${item.recording_mode}</span>
          <span>${item.stt_provider}</span>
          <span>${item.confidence.toFixed(2)}</span>
        </div>
      </div>
      <div class="history-item-text">${item.display_text || "(empty)"}</div>
      <div class="history-item-meta">
        <span>${item.created_at}</span>
        <span>${item.utterance_id}</span>
      </div>
      <div class="history-item-actions">
        <button class="button mini secondary" data-action="load">Load</button>
        <button class="button mini secondary" data-action="session">Use Session</button>
        <button class="button mini secondary" data-action="copy">Copy IDs</button>
      </div>
    `;
    card.addEventListener("click", (event) => {
      const action = event.target?.dataset?.action;
      if (!action) {
        applyHistoryItem(item);
        return;
      }
      event.stopPropagation();
      if (action === "load") {
        applyHistoryItem(item);
        return;
      }
      if (action === "session") {
        elements.historySession.value = item.session_id || "";
        elements.historyCurrentOnly.checked = false;
        persistPreferences();
        refreshHistory({ silent: true });
        log("Applied history session filter.", { session_id: item.session_id });
        return;
      }
      if (action === "copy") {
        const text = `${item.utterance_id} ${item.output_id} ${item.session_id}`.trim();
        navigator.clipboard?.writeText(text).then(
          () => log("Copied history ids.", { utterance_id: item.utterance_id, output_id: item.output_id }),
          () => log("Clipboard copy failed.", { utterance_id: item.utterance_id }),
        );
      }
    });
    elements.historyList.append(card);
  }
}

function setRecordingState(label, kind = "neutral") {
  setBadge(elements.recordingStatus, label, kind);
}

function setTranscriptState(label, kind = "neutral") {
  setBadge(elements.transcriptStatus, label, kind);
}

function setDigestState(label, kind = "neutral") {
  setBadge(elements.digestStatus, label, kind);
}

function setHotkeyState(label, kind = "neutral") {
  setBadge(elements.hotkeyStatus, label, kind);
}

function setPermissionState(label, kind = "neutral") {
  setBadge(elements.permissionStatus, label, kind);
}

function setBridgeState(label, kind = "neutral") {
  setBadge(elements.bridgeStatus, label, kind);
}

function setHistoryState(label, kind = "neutral") {
  setBadge(elements.historyStatus, label, kind);
}

function setProviderState(label, kind = "neutral") {
  setBadge(elements.providerStatus, label, kind);
}

function setSettingsState(label, kind = "neutral") {
  setBadge(elements.settingsStatus, label, kind);
}

function setOnboardingState(label, kind = "neutral") {
  setBadge(elements.onboardingStatus, label, kind);
}

function renderProviderFlags(flags) {
  elements.providerFlags.innerHTML = "";
  const items = [
    ["dashscope-us", flags.dashscope_us],
    ["dashscope-cn", flags.dashscope_cn],
    ["openai", flags.openai],
    ["siliconflow", flags.siliconflow],
  ];
  for (const [label, configured] of items) {
    const pill = document.createElement("span");
    pill.textContent = configured ? `${label}: stored` : `${label}: missing`;
    elements.providerFlags.append(pill);
  }
}

function renderProfileOptions(snapshot) {
  const profiles = snapshot?.profiles || [];
  const currentValue = snapshot?.active_profile || elements.activeProfile.value || "home";
  if (!profiles.length) {
    elements.activeProfile.innerHTML = '<option value="home">home</option>';
    elements.activeProfile.value = currentValue;
    return;
  }

  elements.activeProfile.innerHTML = "";
  for (const profile of profiles) {
    const option = document.createElement("option");
    option.value = profile.name;
    option.textContent = profile.name;
    elements.activeProfile.append(option);
  }
  if ([...elements.activeProfile.options].some((option) => option.value === currentValue)) {
    elements.activeProfile.value = currentValue;
  }
}

function renderProfileSummary(snapshot) {
  const profiles = snapshot?.profiles || [];
  const selected = profiles.find((profile) => profile.name === elements.activeProfile.value);
  if (!selected) {
    elements.profileSummary.innerHTML = "Select a profile to inspect its STT and LLM routing.";
    return;
  }

  elements.profileSummary.innerHTML = `
    <div class="summary-grid">
      <div>
        <span class="label">Profile</span>
        <strong>${escapeHtml(selected.name)}</strong>
      </div>
      <div>
        <span class="label">STT Main</span>
        <strong>${escapeHtml(selected.stt_main)}</strong>
      </div>
      <div>
        <span class="label">STT Fallback</span>
        <strong>${escapeHtml(selected.stt_fallback)}</strong>
      </div>
      <div>
        <span class="label">LLM Main</span>
        <strong>${escapeHtml(selected.llm_main)}</strong>
      </div>
      <div>
        <span class="label">LLM Fallback</span>
        <strong>${escapeHtml(selected.llm_fallback)}</strong>
      </div>
    </div>
    <div class="route-hint">
      <span class="badge neutral">STT ${escapeHtml(selected.stt_main)}</span>
      <span class="badge neutral">Fallback ${escapeHtml(selected.stt_fallback)}</span>
    </div>
  `;
}

function renderProviderRecommendation(connectivity) {
  if (!connectivity) {
    elements.providerRecommendation.textContent =
      "Connection test will recommend the best STT route for this profile.";
    return;
  }

  const kind = connectivity.ready ? "live" : "warn";
  const count = connectivity.configured_provider_count;
  elements.providerRecommendation.innerHTML = `
    <div class="summary-grid">
      <div>
        <span class="label">Recommended STT</span>
        <strong>${escapeHtml(connectivity.recommended_stt_provider)}</strong>
      </div>
      <div>
        <span class="label">Configured Keys</span>
        <strong>${count}</strong>
      </div>
    </div>
    <div class="route-hint">
      <span class="badge ${kind}">${connectivity.ready ? "Ready" : "Fallback Likely"}</span>
      <span class="badge neutral">${escapeHtml(connectivity.active_profile)}</span>
    </div>
  `;
}

function renderTranscriptPreview(preview) {
  if (!preview) {
    elements.transcriptProvider.textContent = "whispercpp-local";
    elements.transcriptModel.textContent = "base.en-q5_1";
    elements.transcriptSegments.textContent = "0";
    elements.partialTranscript.textContent = "(waiting)";
    elements.finalTranscript.textContent = "(waiting)";
    setTranscriptState("Idle", "neutral");
    return;
  }

  elements.transcriptProvider.textContent = preview.provider;
  elements.transcriptModel.textContent = preview.model;
  elements.transcriptSegments.textContent = String(preview.segment_count);
  elements.partialTranscript.textContent = preview.partial_text || "(waiting)";
  elements.finalTranscript.textContent = preview.final_hint || "(waiting)";
  setTranscriptState("Previewing", "warn");
}

function renderOutputPolicy(policy) {
  currentOutputPolicy = policy;
  if (!policy) {
    elements.outputPolicyStrategy.textContent = "paste";
    elements.outputPolicyReason.textContent = "Low-risk targets will prefer fast paste.";
    return;
  }
  elements.outputPolicyStrategy.textContent = policy.strategy;
  elements.outputPolicyReason.textContent = policy.reason;
}

function renderSessionDigest(digest) {
  if (!digest) {
    elements.digestSummary.textContent = "(waiting)";
    elements.digestIntent.textContent = "(waiting)";
    elements.digestTags.textContent = "(waiting)";
    elements.digestEntities.textContent = "(waiting)";
    elements.digestEnhancer.textContent = "(waiting)";
    elements.digestRebuiltAt.textContent = "(waiting)";
    elements.digestExportStatus.textContent = "(waiting)";
    elements.aiMateExportStatus.textContent = "(waiting)";
    setDigestState("Idle", "neutral");
    return;
  }

  elements.digestSummary.textContent = digest.summary || "(empty)";
  elements.digestIntent.textContent = digest.intent || "(empty)";
  elements.digestTags.textContent = (digest.suggested_tags || []).join(", ") || "(empty)";
  elements.digestEntities.textContent = (digest.mentioned_entities || []).join(", ") || "(empty)";
  elements.digestEnhancer.textContent = digest.enhanced
    ? `LLM: ${digest.enhancer_provider || "unknown"}`
    : `Heuristic: ${digest.enhancer_provider || "heuristic"}`;
  elements.digestRebuiltAt.textContent = digest.updated_at
    ? new Date(digest.updated_at).toLocaleString()
    : "(unknown)";
  elements.digestExportStatus.textContent = "(ready)";
  elements.aiMateExportStatus.textContent = "(ready)";
  if (digest.digest_type === "daily_digest") {
    setDigestState("Daily Ready", "live");
    return;
  }
  if (digest.digest_type === "project_digest") {
    setDigestState("Project Ready", "live");
    return;
  }
  setDigestState("Session Ready", "live");
}

function showPolicyPreview(text) {
  elements.policyPreviewText.textContent = text || "(empty)";
  elements.policyPreviewCard.classList.remove("hidden");
  setBadge(elements.policyPreviewStatus, "Pending", "warn");
}

function hidePolicyPreview() {
  elements.policyPreviewCard.classList.add("hidden");
  elements.policyPreviewText.textContent = "";
  pendingUploadPayload = null;
}

function readinessKind(status) {
  if (status === "ok") {
    return "live";
  }
  if (status === "warn") {
    return "warn";
  }
  return "danger";
}

function renderSettingsChecks(payload) {
  if (!payload?.checks?.length) {
    elements.settingsChecks.innerHTML = "";
    elements.settingsChecks.classList.add("hidden");
    return;
  }

  elements.settingsChecks.innerHTML = "";
  elements.settingsChecks.classList.remove("hidden");

  for (const check of payload.checks) {
    const card = document.createElement("article");
    card.className = "settings-check";
    card.innerHTML = `
      <div class="settings-check-head">
        <strong>${check.label}</strong>
        <span class="badge ${readinessKind(check.status)}">${check.status}</span>
      </div>
      <p>${check.message}</p>
    `;
    elements.settingsChecks.append(card);
  }
}

function renderOnboardingChecks(snapshot, connectivity) {
  if (snapshot) {
    currentSettingsSnapshot = snapshot;
  }
  if (connectivity !== undefined) {
    currentConnectivity = connectivity;
  }

  const resolvedSnapshot = currentSettingsSnapshot;
  const resolvedConnectivity = currentConnectivity;
  const hasBackend = Boolean(resolvedSnapshot?.backend_base_url?.trim());
  const hasProvider = Boolean(resolvedConnectivity?.configured_provider_count || 0);
  const connectionReady = Boolean(resolvedConnectivity?.backend_url_reachable);
  const micGranted = elements.permissionStatus.textContent.includes("Granted");
  const checks = [
    {
      label: "Backend URL",
      status: hasBackend ? "ok" : "warn",
      message: hasBackend ? "Desktop shell has a backend URL configured." : "Set the backend base URL first.",
    },
    {
      label: "Provider Key",
      status: hasProvider ? "ok" : "fail",
      message: hasProvider ? "At least one provider key is stored securely." : "Add one provider key in Provider Settings.",
    },
    {
      label: "Connection Test",
      status: connectionReady ? "ok" : "warn",
      message: connectionReady ? "Backend bridge test passed." : "Run Test Connection after saving your settings.",
    },
    {
      label: "Microphone Permission",
      status: micGranted ? "ok" : "warn",
      message: micGranted ? "Microphone permission granted." : "Refresh mic permission and allow access before recording.",
    },
  ];

  elements.onboardingChecks.innerHTML = "";
  for (const check of checks) {
    const card = document.createElement("article");
    card.className = `settings-check${check.status === "ok" ? "" : " todo"}`;
    card.innerHTML = `
      <div class="settings-check-head">
        <strong>${check.label}</strong>
        <span class="badge ${readinessKind(check.status)}">${check.status}</span>
      </div>
      <p>${check.message}</p>
    `;
    elements.onboardingChecks.append(card);
  }
}

function canCompleteOnboarding(snapshot, connectivity) {
  const resolvedSnapshot = snapshot ?? currentSettingsSnapshot;
  const resolvedConnectivity = connectivity ?? currentConnectivity;
  const hasBackend = Boolean(resolvedSnapshot?.backend_base_url?.trim());
  const hasProvider = Boolean(resolvedConnectivity?.configured_provider_count || 0);
  return hasBackend && hasProvider && Boolean(resolvedConnectivity?.backend_url_reachable);
}

function hydratePreferences() {
  elements.backendUrl.value = storage.get(STORAGE_KEYS.backendUrl, elements.backendUrl.value);
  elements.hotkeyAccelerator.value = storage.get(
    STORAGE_KEYS.hotkeyAccelerator,
    elements.hotkeyAccelerator.value || "CommandOrControl+Shift+Space",
  );
  elements.hotkeyEnabled.checked = storage.getBool(STORAGE_KEYS.hotkeyEnabled, false);
  elements.targetApp.value = storage.get(STORAGE_KEYS.targetApp, elements.targetApp.value || "Cursor");
  elements.targetRisk.value = storage.get(STORAGE_KEYS.targetRisk, elements.targetRisk.value || "low");
  elements.sessionId.value = storage.get(STORAGE_KEYS.sessionId, "");
  elements.recordMode.value = storage.get(STORAGE_KEYS.recordMode, elements.recordMode.value || "normal");
  elements.retryProvider.value = storage.get(STORAGE_KEYS.retryProvider, "");
  elements.historyQuery.value = storage.get(STORAGE_KEYS.historyQuery, "");
  elements.historyAgent.dataset.persistedValue = storage.get(STORAGE_KEYS.historyAgent, "");
  elements.historySession.value = storage.get(STORAGE_KEYS.historySession, "");
  elements.historyCurrentOnly.checked = storage.getBool(STORAGE_KEYS.historyCurrentOnly, false);
  if (!elements.digestDate.value) {
    elements.digestDate.value = new Date().toISOString().slice(0, 10);
  }
  if (!elements.digestProjectKey.value.trim()) {
    elements.digestProjectKey.value = elements.targetApp.value.trim().toLowerCase();
  }
  ensureSessionId();
}

function persistPreferences() {
  storage.set(STORAGE_KEYS.backendUrl, elements.backendUrl.value.trim());
  storage.set(STORAGE_KEYS.hotkeyAccelerator, elements.hotkeyAccelerator.value.trim());
  storage.set(STORAGE_KEYS.hotkeyEnabled, String(elements.hotkeyEnabled.checked));
  storage.set(STORAGE_KEYS.targetApp, elements.targetApp.value.trim());
  storage.set(STORAGE_KEYS.targetRisk, elements.targetRisk.value);
  storage.set(STORAGE_KEYS.sessionId, elements.sessionId.value.trim());
  storage.set(STORAGE_KEYS.recordMode, elements.recordMode.value);
  storage.set(STORAGE_KEYS.retryProvider, elements.retryProvider.value.trim());
  storage.set(STORAGE_KEYS.historyQuery, elements.historyQuery.value.trim());
  storage.set(STORAGE_KEYS.historyAgent, elements.historyAgent.value);
  storage.set(STORAGE_KEYS.historySession, elements.historySession.value.trim());
  storage.set(STORAGE_KEYS.historyCurrentOnly, String(elements.historyCurrentOnly.checked));
}

function getActiveHistorySessionFilter() {
  if (elements.historyCurrentOnly.checked) {
    return elements.sessionId.value.trim();
  }
  return elements.historySession.value.trim();
}

function applyHistoryItem(item) {
  elements.targetApp.value = item.target_app || elements.targetApp.value;
  elements.sessionId.value = item.session_id || elements.sessionId.value;
  elements.recordMode.value = item.recording_mode || elements.recordMode.value;
  elements.historySession.value = item.session_id || elements.historySession.value;
  elements.dictionaryWrong.value = item.raw_text || "";
  elements.dictionaryRight.value = item.display_text || "";
  elements.retryProvider.value = item.stt_provider || "";
  elements.recentApp.textContent = item.target_app || "Unknown";
  elements.recentRisk.textContent = item.target_risk_level;
  elements.recentProvider.textContent = `${item.stt_provider} / ${item.stt_model}`;
  elements.recentConfidence.textContent = Number(item.confidence || 0).toFixed(2);
  elements.recentDisplay.textContent = item.display_text || "(empty)";
  elements.recentRaw.textContent = item.raw_text || "(empty)";
  elements.recentIds.textContent = `${item.utterance_id} / ${item.output_id}`;
  elements.recentEmpty.classList.add("hidden");
  elements.recentCard.classList.remove("hidden");
  setBadge(elements.recentStatus, "Loaded From History", "live");
  persistPreferences();
  log("Applied history item to current panel.", {
    utterance_id: item.utterance_id,
    session_id: item.session_id,
  });
}

function createSessionId() {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  return `voxlog2-${stamp}`;
}

function ensureSessionId() {
  const existing = elements.sessionId.value.trim();
  if (existing) {
    return existing;
  }
  const nextSessionId = createSessionId();
  elements.sessionId.value = nextSessionId;
  storage.set(STORAGE_KEYS.sessionId, nextSessionId);
  return nextSessionId;
}

function handlePermissionState(state) {
  if (state === "granted") {
    setPermissionState("Mic Granted", "live");
    return;
  }
  if (state === "prompt") {
    setPermissionState("Mic Prompt", "warn");
    return;
  }
  if (state === "denied") {
    setPermissionState("Mic Denied", "warn");
    return;
  }
  setPermissionState("Mic Unknown", "neutral");
}

function buildSettingsPayload(options = {}) {
  return {
    backend_base_url: elements.backendUrl.value.trim(),
    backend_api_token: elements.backendApiToken.value.trim() || undefined,
    active_profile: elements.activeProfile.value,
    digest_enhancement_enabled: elements.digestEnhancementEnabled.checked,
    digest_enhancement_provider: elements.digestEnhancementProvider.value,
    obsidian_vault_dir: elements.obsidianVaultDir.value.trim(),
    ai_mate_memory_dir: elements.aiMateMemoryDir.value.trim(),
    onboarding_completed: options.completeOnboarding ?? false,
    hotkey_accelerator: elements.hotkeyAccelerator.value.trim(),
    hotkey_enabled: elements.hotkeyEnabled.checked,
    app_rules: {
      never_archive_apps: parseRuleList(elements.neverArchiveApps.value),
      fast_path_only_apps: parseRuleList(elements.fastPathOnlyApps.value),
      disable_direct_typing_apps: parseRuleList(elements.disableDirectTypingApps.value),
    },
    dashscope_key_us: elements.dashscopeKeyUs.value.trim() || undefined,
    dashscope_key_cn: elements.dashscopeKeyCn.value.trim() || undefined,
    openai_key: elements.openaiKey.value.trim() || undefined,
    siliconflow_key: elements.siliconflowKey.value.trim() || undefined,
  };
}

function renderAppSettings(snapshot) {
  currentSettingsSnapshot = snapshot;
  elements.backendUrl.value = snapshot.backend_base_url || elements.backendUrl.value;
  renderProfileOptions(snapshot);
  elements.activeProfile.value = snapshot.active_profile || "home";
  elements.hotkeyAccelerator.value = snapshot.hotkey_accelerator || elements.hotkeyAccelerator.value;
  elements.hotkeyEnabled.checked = snapshot.hotkey_enabled;
  elements.digestEnhancementEnabled.checked = Boolean(snapshot.digest_enhancement_enabled);
  elements.digestEnhancementProvider.value = snapshot.digest_enhancement_provider || "auto";
  elements.obsidianVaultDir.value = snapshot.obsidian_vault_dir || "";
  elements.aiMateMemoryDir.value = snapshot.ai_mate_memory_dir || "";
  elements.neverArchiveApps.value = joinRuleList(snapshot.app_rules?.never_archive_apps);
  elements.fastPathOnlyApps.value = joinRuleList(snapshot.app_rules?.fast_path_only_apps);
  elements.disableDirectTypingApps.value = joinRuleList(snapshot.app_rules?.disable_direct_typing_apps);
  renderProviderFlags(snapshot.provider_flags);
  renderProfileSummary(snapshot);
  renderProviderRecommendation(currentConnectivity);

  const configuredCount = Object.values(snapshot.provider_flags).filter(Boolean).length;
  setProviderState(`${configuredCount} Ready`, configuredCount > 0 ? "live" : "warn");
  setSettingsState(snapshot.backend_api_token_present ? "Token Stored" : "Local Only", "neutral");

  if (snapshot.onboarding_completed) {
    elements.onboardingPanel.classList.add("hidden");
    setOnboardingState("Complete", "live");
  } else {
    elements.onboardingPanel.classList.remove("hidden");
    setOnboardingState("Setup Needed", "warn");
  }

  elements.backendApiToken.value = "";
  elements.dashscopeKeyUs.value = "";
  elements.dashscopeKeyCn.value = "";
  elements.openaiKey.value = "";
  elements.siliconflowKey.value = "";
  elements.completeOnboarding.disabled = false;
  renderOnboardingChecks(snapshot, null);
}

async function testProviderSettings(options = {}) {
  if (!isTauri) {
    return null;
  }

  try {
    setSettingsState("Testing", "warn");
    const payload = await invoke("test_provider_settings");
    renderSettingsChecks(payload);
    renderOnboardingChecks(null, payload);
    renderProviderRecommendation(payload);
    setProviderState(
      payload.ready ? `${payload.configured_provider_count} Ready` : "Setup Needed",
      payload.ready ? "live" : "warn",
    );
    setSettingsState(payload.ready ? "Connection Ready" : "Needs Setup", payload.ready ? "live" : "warn");
    if (!options.silent) {
      log("Tested provider settings.", payload);
    }
    return payload;
  } catch (error) {
    renderSettingsChecks({
      checks: [
        {
          label: "Backend Bridge",
          status: "fail",
          message: `Connection test failed: ${String(error)}`,
        },
      ],
    });
    setProviderState("Connection Failed", "warn");
    setSettingsState("Test Failed", "warn");
    renderOnboardingChecks(null, null);
    renderProviderRecommendation(null);
    if (!options.silent) {
      log("Failed to test provider settings.", { error: String(error) });
    }
    return null;
  }
}

async function refreshMicrophonePermission() {
  if (!navigator.mediaDevices?.getUserMedia) {
    setPermissionState("Mic Unsupported", "warn");
    log("Media devices API unavailable.");
    return;
  }

  if (!navigator.permissions?.query) {
    setPermissionState("Mic Ready", "neutral");
    log("Permissions API unavailable; mic status will update on capture.");
    return;
  }

  try {
    const status = await navigator.permissions.query({ name: "microphone" });
    microphonePermissionStatus = status;
    handlePermissionState(status.state);
    renderOnboardingChecks(null, null);
    status.onchange = () => {
      handlePermissionState(status.state);
      renderOnboardingChecks(null, null);
    };
    log("Refreshed microphone permission.", { state: status.state });
  } catch (error) {
    setPermissionState("Mic Unknown", "neutral");
    renderOnboardingChecks(null, null);
    log("Failed to query microphone permission.", { error: String(error) });
  }
}

async function bootstrap() {
  hydratePreferences();
  renderTranscriptPreview(null);
  renderOutputPolicy(null);
  renderSessionDigest(null);

  if (!isTauri) {
    setBadge(elements.bridgeStatus, "Browser Mode", "warn");
    log("Tauri runtime not available; commands disabled.");
    return;
  }

  try {
    const url = await invoke("get_backend_base_url");
    if (!storage.get(STORAGE_KEYS.backendUrl)) {
      elements.backendUrl.value = url;
    }
    persistPreferences();
    setBridgeState("Connected", "live");
    log("Loaded backend base URL.", { url: elements.backendUrl.value });
  } catch (error) {
    setBridgeState("Bridge Error", "warn");
    log("Failed to load backend base URL.", { error: String(error) });
  }

  try {
    const settings = await invoke("get_app_settings");
    renderAppSettings(settings);
    if (!storage.get(STORAGE_KEYS.backendUrl)) {
      elements.backendUrl.value = settings.backend_base_url;
    }
    persistPreferences();
    log("Loaded app settings.", settings);
    const connectivity = await testProviderSettings({ silent: true });
    elements.completeOnboarding.disabled = !canCompleteOnboarding(settings, connectivity);
  } catch (error) {
    setSettingsState("Load Failed", "warn");
    setHotkeyState("Hotkey Error", "warn");
    setProviderState("Providers Unknown", "warn");
    log("Failed to load app settings.", { error: String(error) });
  }

  globalHotkeyUnlisten = await listen("voxlog2://global-hotkey", async (event) => {
    const payload = event.payload || {};
    log("Global hotkey event.", payload);
    if (payload.phase === "pressed") {
      setHotkeyState("Hotkey Pressed", "warn");
      await startRecording();
      return;
    }
    if (payload.phase === "released") {
      setHotkeyState("Hotkey Ready", "live");
      await stopRecording();
    }
  });

  await refreshMicrophonePermission();

  if (elements.hotkeyEnabled.checked) {
    await saveHotkeyConfig({ silent: true });
  } else {
    setHotkeyState("Hotkey Off", "neutral");
  }

  await refreshBackendHealth({ silent: true });
  await refreshOutputPolicyPreview();
  await refreshRecent();
  await refreshSessionDigest({ silent: true });
  await refreshAgents();
  await refreshHistory({ silent: true });
  startPolling();
}

async function refreshRecent() {
  if (!isTauri) return;

  try {
    const payload = await invoke("get_recent_utterance");
    renderRecent(payload.recent);
    log("Fetched recent utterance.", { found: Boolean(payload.recent) });
  } catch (error) {
    renderRecent(null);
    setBadge(elements.recentStatus, "Unavailable", "warn");
    log("Failed to fetch recent utterance.", { error: String(error) });
  }
}

async function refreshBackendHealth(options = {}) {
  if (!isTauri) return;

  try {
    const payload = await invoke("get_backend_health");
    const service = payload.service || "backend";
    const version = payload.version || payload.profile || "ok";
    setBridgeState(`${service} ${version}`, "live");
    if (!options.silent) {
      log("Fetched backend health.", payload);
    }
  } catch (error) {
    setBridgeState("Backend Down", "warn");
    if (!options.silent) {
      log("Failed to fetch backend health.", { error: String(error) });
    }
  }
}

async function refreshOutputPolicyPreview() {
  if (!isTauri) {
    return;
  }
  try {
    const policy = await invoke("preview_output_policy", {
      target_app: elements.targetApp.value.trim(),
      risk_level: elements.targetRisk.value,
      requested_mode: "paste",
      app_rules: {
        never_archive_apps: parseRuleList(elements.neverArchiveApps.value),
        fast_path_only_apps: parseRuleList(elements.fastPathOnlyApps.value),
        disable_direct_typing_apps: parseRuleList(elements.disableDirectTypingApps.value),
      },
    });
    renderOutputPolicy(policy);
    if (!policy.should_confirm) {
      hidePolicyPreview();
    }
  } catch (error) {
    log("Failed to preview output policy.", { error: String(error) });
  }
}

async function refreshLocalTranscriptPreview(options = {}) {
  if (!isTauri || !isRecording) {
    return;
  }
  try {
    const durationMs = Math.max(250, Date.now() - recordingStartedAt);
    const preview = await invoke("preview_local_transcript", {
      duration_ms: durationMs,
      mime_type: mediaRecorder?.mimeType || "audio/webm",
      target_app: elements.targetApp.value.trim(),
      session_id: ensureSessionId(),
    });
    renderTranscriptPreview(preview);
    if (!options.silent) {
      log("Updated local transcript preview.", {
        duration_ms: durationMs,
        segment_count: preview.segment_count,
      });
    }
  } catch (error) {
    setTranscriptState("Preview Error", "warn");
    if (!options.silent) {
      log("Failed to preview local transcript.", { error: String(error) });
    }
  }
}

async function refreshSessionDigest(options = {}) {
  if (!isTauri) {
    return;
  }

  const digestType = elements.digestType.value;
  const sessionId = elements.sessionId.value.trim();
  const digestDate = elements.digestDate.value.trim() || new Date().toISOString().slice(0, 10);
  const projectKey = elements.digestProjectKey.value.trim().toLowerCase();
  if (digestType === "session" && !sessionId) {
    renderSessionDigest(null);
    return;
  }
  if (digestType === "project" && !projectKey) {
    renderSessionDigest(null);
    return;
  }

  try {
    setDigestState("Loading", "warn");
    elements.digestExportStatus.textContent = "(waiting)";
    elements.aiMateExportStatus.textContent = "(waiting)";
    const digest =
      digestType === "daily"
        ? await invoke("get_daily_digest", { date: digestDate })
        : digestType === "project"
          ? await invoke("get_project_digest", { project_key: projectKey })
        : await invoke("get_session_digest", { session_id: sessionId });
    renderSessionDigest(digest);
    if (!options.silent) {
      log("Fetched digest.", {
        digest_type: digest.digest_type,
        session_id: sessionId,
        digest_date: digest.digest_date,
        project_key: digest.project_key,
        intent: digest.intent,
      });
    }
  } catch (error) {
    setDigestState("Missing", "warn");
    elements.digestExportStatus.textContent = "(waiting)";
    elements.aiMateExportStatus.textContent = "(waiting)";
    if (!options.silent) {
      log("Digest unavailable.", {
        digest_type: digestType,
        session_id: sessionId,
        digest_date: digestDate,
        project_key: projectKey,
        error: String(error),
      });
    }
  }
}

async function rebuildDigest() {
  if (!isTauri) {
    return;
  }

  const scope = elements.digestType.value;
  const payload = {
    scope,
    session_id: scope === "session" ? elements.sessionId.value.trim() : undefined,
    date: scope === "daily" ? elements.digestDate.value.trim() : undefined,
    project_key: scope === "project" ? elements.digestProjectKey.value.trim().toLowerCase() : undefined,
  };

  try {
    setDigestState("Rebuilding", "warn");
    elements.digestExportStatus.textContent = "(waiting)";
    elements.aiMateExportStatus.textContent = "(waiting)";
    const digest = await invoke("rebuild_digest", { input: payload });
    renderSessionDigest(digest);
    setDigestState("Rebuilt", "live");
    log("Rebuilt digest.", {
      scope,
      session_id: payload.session_id,
      date: payload.date,
      project_key: payload.project_key,
    });
  } catch (error) {
    setDigestState("Rebuild Failed", "warn");
    log("Failed to rebuild digest.", { scope, error: String(error) });
  }
}

async function exportDigestToObsidian() {
  if (!isTauri) {
    return;
  }

  const vaultDir = elements.obsidianVaultDir.value.trim();
  if (!vaultDir) {
    elements.digestExportStatus.textContent = "Set Obsidian vault path first.";
    setDigestState("Export Blocked", "warn");
    return;
  }

  const scope = elements.digestType.value;
  const payload = {
    scope,
    vault_dir: vaultDir,
    session_id: scope === "session" ? elements.sessionId.value.trim() : undefined,
    date: scope === "daily" ? elements.digestDate.value.trim() : undefined,
    project_key: scope === "project" ? elements.digestProjectKey.value.trim().toLowerCase() : undefined,
  };

  try {
    setDigestState("Exporting", "warn");
    const result = await invoke("export_digest_to_obsidian", { input: payload });
    elements.digestExportStatus.textContent = `${result.note_path} (${result.bytes_written} bytes)`;
    setDigestState("Exported", "live");
    log("Exported digest to Obsidian.", result);
  } catch (error) {
    elements.digestExportStatus.textContent = String(error);
    setDigestState("Export Failed", "warn");
    log("Failed to export digest to Obsidian.", { error: String(error) });
  }
}

async function exportDigestToAiMateMemory() {
  if (!isTauri) {
    return;
  }

  const baseDir = elements.aiMateMemoryDir.value.trim();
  if (!baseDir) {
    elements.aiMateExportStatus.textContent = "Set AI Mate Memory path first.";
    setDigestState("Export Blocked", "warn");
    return;
  }

  const scope = elements.digestType.value;
  const payload = {
    scope,
    base_dir: baseDir,
    session_id: scope === "session" ? elements.sessionId.value.trim() : undefined,
    date: scope === "daily" ? elements.digestDate.value.trim() : undefined,
    project_key: scope === "project" ? elements.digestProjectKey.value.trim().toLowerCase() : undefined,
  };

  try {
    setDigestState("Exporting", "warn");
    const result = await invoke("export_digest_to_ai_mate_memory", { input: payload });
    elements.aiMateExportStatus.textContent = `${result.record_path} (${result.bytes_written} bytes)`;
    setDigestState("Exported", "live");
    log("Exported digest to AI Mate Memory.", result);
  } catch (error) {
    elements.aiMateExportStatus.textContent = String(error);
    setDigestState("Export Failed", "warn");
    log("Failed to export digest to AI Mate Memory.", { error: String(error) });
  }
}

function startPolling() {
  if (healthPollTimer) {
    clearInterval(healthPollTimer);
  }
  if (recentPollTimer) {
    clearInterval(recentPollTimer);
  }
  if (historyPollTimer) {
    clearInterval(historyPollTimer);
  }

  healthPollTimer = window.setInterval(() => {
    refreshBackendHealth({ silent: true });
  }, 15000);
  recentPollTimer = window.setInterval(() => {
    if (!isRecording) {
      refreshRecent();
    }
  }, 10000);
  historyPollTimer = window.setInterval(() => {
    if (!isRecording) {
      refreshHistory({ silent: true });
    }
  }, 15000);
}

async function refreshAgents() {
  if (!isTauri) return;

  try {
    const agents = await invoke("get_agents");
    const persistedValue = elements.historyAgent.dataset.persistedValue || "";
    const currentValue = elements.historyAgent.value || persistedValue;
    elements.historyAgent.innerHTML = '<option value="">all agents</option>';
    for (const item of agents) {
      const option = document.createElement("option");
      option.value = item.agent;
      option.textContent = `${item.agent} (${item.count})`;
      elements.historyAgent.append(option);
    }
    if ([...elements.historyAgent.options].some((option) => option.value === currentValue)) {
      elements.historyAgent.value = currentValue;
    }
    elements.historyAgent.dataset.persistedValue = "";
    persistPreferences();
  } catch (error) {
    log("Failed to fetch agent list.", { error: String(error) });
  }
}

async function refreshHistory(options = {}) {
  if (!isTauri) return;

  try {
    setHistoryState("Loading", "warn");
    const query = elements.historyQuery.value.trim();
    const agent = elements.historyAgent.value;
    const sessionFilter = getActiveHistorySessionFilter();
    const rawItems = agent
      ? await invoke("get_agent_history", { agent, limit: 20 })
      : await invoke("get_history", { q: query, limit: 20 });
    const items = sessionFilter
      ? rawItems.filter((item) => item.session_id === sessionFilter)
      : rawItems;
    renderHistory(items);
    if (!options.silent) {
      log("Fetched history items.", { count: items.length, query, agent, sessionFilter });
    }
  } catch (error) {
    setHistoryState("Unavailable", "warn");
    elements.historyEmpty.classList.remove("hidden");
    elements.historyList.classList.add("hidden");
    if (!options.silent) {
      log("Failed to fetch history items.", { error: String(error) });
    }
  }
}

async function saveBackendUrl() {
  if (!isTauri) return;

  try {
    const url = await invoke("set_backend_base_url", {
      backend_base_url: elements.backendUrl.value,
    });
    elements.backendUrl.value = url;
    persistPreferences();
    setBridgeState("Saved", "live");
    log("Updated backend base URL.", { url });
    await refreshBackendHealth({ silent: true });
  } catch (error) {
    setBridgeState("Save Failed", "warn");
    log("Failed to update backend base URL.", { error: String(error) });
  }
}

async function saveAppSettings(options = {}) {
  if (!isTauri) return;

  try {
    setSettingsState("Saving", "warn");
    const snapshot = await invoke("save_app_settings", {
      input: buildSettingsPayload(options),
    });
    renderAppSettings(snapshot);
    persistPreferences();
    setSettingsState("Saved", "live");
    setHotkeyState(snapshot.hotkey_enabled ? "Hotkey Ready" : "Hotkey Off", snapshot.hotkey_enabled ? "live" : "neutral");
    await refreshBackendHealth({ silent: true });
    const connectivity = await testProviderSettings({ silent: true });
    elements.completeOnboarding.disabled = !canCompleteOnboarding(snapshot, connectivity);
    await refreshAgents();
    await refreshHistory({ silent: true });
    log("Saved app settings.", {
      active_profile: snapshot.active_profile,
      onboarding_completed: snapshot.onboarding_completed,
    });
  } catch (error) {
    setSettingsState("Save Failed", "warn");
    log("Failed to save app settings.", { error: String(error) });
  }
}

async function completeOnboarding() {
  const preview = buildSettingsPayload({ completeOnboarding: false });
  if (!preview.backend_base_url.trim()) {
    setOnboardingState("Backend Required", "warn");
    setSettingsState("Add Backend URL", "warn");
    return;
  }
  const saved = await invoke("save_app_settings", {
    input: preview,
  });
  renderAppSettings(saved);
  const connectivity = await testProviderSettings({ silent: false });
  if (!canCompleteOnboarding(saved, connectivity)) {
    setOnboardingState("Add Provider Key", "warn");
    elements.completeOnboarding.disabled = false;
    return;
  }
  await saveAppSettings({ completeOnboarding: true });
  setOnboardingState("Complete", "live");
}

async function saveHotkeyConfig(options = {}) {
  if (!isTauri) return;

  try {
    const response = await invoke("set_hotkey_config", {
      accelerator: elements.hotkeyAccelerator.value.trim(),
      enabled: elements.hotkeyEnabled.checked,
    });
    elements.hotkeyAccelerator.value = response.accelerator;
    elements.hotkeyEnabled.checked = response.enabled;
    persistPreferences();
    setHotkeyState(response.registered ? "Hotkey Ready" : "Hotkey Off", response.registered ? "live" : "neutral");
    if (!options.silent) {
      log("Updated hotkey config.", response);
    }
  } catch (error) {
    setHotkeyState("Hotkey Error", "warn");
    log("Failed to update hotkey config.", { error: String(error) });
  }
}

async function dismissRecent() {
  if (!isTauri || !currentRecent) return;

  try {
    await invoke("dismiss_recent_utterance", {
      utterance_id: currentRecent.utterance_id,
    });
    log("Dismissed recent utterance.", { utterance_id: currentRecent.utterance_id });
    renderRecent(null);
  } catch (error) {
    log("Failed to dismiss recent utterance.", { error: String(error) });
  }
}

async function undoOutput() {
  if (!isTauri || !currentRecent) return;

  try {
    const response = await invoke("undo_output", {
      output_id: currentRecent.output_id,
    });
    log("Undo output requested.", response);
    if (response.ui_undo_required) {
      setBadge(elements.recentStatus, "UI Undo Needed", "warn");
    }
  } catch (error) {
    log("Failed to request output undo.", { error: String(error) });
  }
}

async function retryRecent() {
  if (!isTauri || !currentRecent) return;

  try {
    const response = await invoke("retry_recent_utterance", {
      utterance_id: currentRecent.utterance_id,
      provider: elements.retryProvider.value.trim(),
    });
    log("Retried recent utterance.", {
      utterance_id: response.utterance_id,
      retried_from: response.retried_from,
      provider: response.stt_provider,
    });
    await refreshRecent();
  } catch (error) {
    log("Failed to retry recent utterance.", { error: String(error) });
  }
}

async function applyRecentMode() {
  if (!isTauri || !currentRecent) return;

  try {
    const response = await invoke("set_recent_mode", {
      utterance_id: currentRecent.utterance_id,
      mode: elements.recentModeSelect.value,
    });
    log("Updated recent mode.", response);
    await refreshRecent();
  } catch (error) {
    log("Failed to update recent mode.", { error: String(error) });
  }
}

async function addRecentDictionary() {
  if (!isTauri || !currentRecent) return;

  const wrong = elements.dictionaryWrong.value.trim();
  const right = elements.dictionaryRight.value.trim();
  if (!wrong || !right) {
    log("Dictionary update skipped.", { reason: "wrong/right required" });
    return;
  }

  try {
    const response = await invoke("add_recent_dictionary_term", {
      utterance_id: currentRecent.utterance_id,
      wrong,
      right,
    });
    log("Added recent dictionary mapping.", {
      utterance_id: response.utterance_id,
      wrong: response.wrong,
      right: response.right,
    });
  } catch (error) {
    log("Failed to add recent dictionary mapping.", { error: String(error) });
  }
}

async function ensureMediaRecorder() {
  if (mediaRecorder) {
    return mediaRecorder;
  }

  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  mediaStream = stream;
  handlePermissionState("granted");

  const mimeType = MediaRecorder.isTypeSupported("audio/webm;codecs=opus")
    ? "audio/webm;codecs=opus"
    : "audio/webm";
  mediaRecorder = new MediaRecorder(stream, { mimeType });

  mediaRecorder.addEventListener("dataavailable", (event) => {
    if (event.data && event.data.size > 0) {
      mediaChunks.push(event.data);
    }
  });

  mediaRecorder.addEventListener("start", () => {
    mediaChunks = [];
    isRecording = true;
    recordingStartedAt = Date.now();
    setRecordingState("Recording", "warn");
    setTranscriptState("Previewing", "warn");
    renderTranscriptPreview({
      provider: "whispercpp-local",
      model: "base.en-q5_1",
      partial_text: "Starting local whisper.cpp preview...",
      final_hint: "Finalize locally when capture stops.",
      confidence_hint: 0.5,
      segment_count: 0,
    });
    if (previewPollTimer) {
      clearInterval(previewPollTimer);
    }
    previewPollTimer = window.setInterval(() => {
      refreshLocalTranscriptPreview({ silent: true });
    }, 700);
    log("Recording started.");
  });

  return mediaRecorder;
}

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      const value = reader.result;
      if (typeof value !== "string") {
        reject(new Error("Unexpected FileReader result"));
        return;
      }
      const [, base64] = value.split(",", 2);
      resolve(base64);
    };
    reader.onerror = () => reject(reader.error || new Error("FileReader failed"));
    reader.readAsDataURL(blob);
  });
}

async function uploadCurrentRecording() {
  if (!mediaChunks.length) {
    log("No audio captured; skipping upload.");
    setRecordingState("Idle", "neutral");
    return;
  }

  const blob = new Blob(mediaChunks, { type: mediaRecorder.mimeType || "audio/webm" });
  const audioBase64 = await blobToBase64(blob);
  const sessionId = ensureSessionId();
  const targetApp = elements.targetApp.value.trim();
  const mode = elements.recordMode.value;
  persistPreferences();

  const effectivePolicy = currentOutputPolicy;
  if (effectivePolicy?.should_confirm) {
    pendingUploadPayload = {
      audioBase64,
      mimeType: blob.type || "audio/webm",
      source: "desktop-tauri",
      targetApp,
      sessionId,
      mode,
    };
    setRecordingState("Preview Required", "warn");
    setTranscriptState("Preview Required", "warn");
    showPolicyPreview(elements.finalTranscript.textContent || elements.partialTranscript.textContent);
    log("Preview required before upload.", {
      strategy: effectivePolicy.strategy,
      target_app: targetApp,
      risk: elements.targetRisk.value,
    });
    return;
  }

  await sendVoicePayload({
    audioBase64,
    mimeType: blob.type || "audio/webm",
    source: "desktop-tauri",
    targetApp,
    sessionId,
    mode,
  });
}

async function sendVoicePayload(payload) {
  setRecordingState("Uploading", "warn");

  const response = await invoke("upload_voice", {
    audio_base64: payload.audioBase64,
    mime_type: payload.mimeType,
    source: payload.source,
    target_app: payload.targetApp,
    session_id: payload.sessionId,
    mode: payload.mode,
  });

  log("Uploaded utterance to backend.", {
    id: response.id,
    utterance_id: response.utterance_id,
    latency_ms: response.latency_ms,
  });

  setRecordingState("Uploaded", "live");
  setTranscriptState("Final", "live");
  elements.partialTranscript.textContent = response.raw_text || "(empty)";
  elements.finalTranscript.textContent = response.display_text || "(empty)";
  elements.transcriptProvider.textContent = response.stt_provider || "whispercpp-local";
  elements.transcriptModel.textContent = response.stt_model || "base.en-q5_1";
  hidePolicyPreview();
  await refreshRecent();
  await refreshSessionDigest({ silent: true });
}

async function startRecording() {
  if (!isTauri) {
    log("Recording unavailable outside Tauri runtime.");
    return;
  }
  if (isRecording) {
    return;
  }

  try {
    const recorder = await ensureMediaRecorder();
    recorder.start();
  } catch (error) {
    handlePermissionState("denied");
    setRecordingState("Mic Error", "warn");
    log("Failed to start recording.", { error: String(error) });
  }
}

async function stopRecording() {
  if (!mediaRecorder || !isRecording) {
    return;
  }

  if (previewPollTimer) {
    clearInterval(previewPollTimer);
    previewPollTimer = null;
  }

  const recorder = mediaRecorder;
  const finished = new Promise((resolve, reject) => {
    recorder.addEventListener(
      "stop",
      async () => {
        try {
          isRecording = false;
          await uploadCurrentRecording();
          resolve();
        } catch (error) {
          setRecordingState("Upload Failed", "warn");
          log("Failed to upload recording.", { error: String(error) });
          reject(error);
        }
      },
      { once: true },
    );
  });

  recorder.stop();
  return finished;
}

async function confirmPolicyPreview() {
  if (!pendingUploadPayload) {
    return;
  }
  try {
    setBadge(elements.policyPreviewStatus, "Sending", "warn");
    await sendVoicePayload(pendingUploadPayload);
    setBadge(elements.policyPreviewStatus, "Sent", "live");
  } catch (error) {
    setBadge(elements.policyPreviewStatus, "Failed", "warn");
    setRecordingState("Upload Failed", "warn");
    log("Failed to send preview payload.", { error: String(error) });
  }
}

function cancelPolicyPreview() {
  hidePolicyPreview();
  setRecordingState("Cancelled", "neutral");
  setTranscriptState("Preview Cancelled", "warn");
  log("Cancelled preview-gated output.");
}

function shouldIgnoreSpaceHotkey(event) {
  const tagName = event.target?.tagName;
  return tagName === "INPUT" || tagName === "TEXTAREA" || tagName === "SELECT";
}

function resetSession() {
  const nextSessionId = createSessionId();
  elements.sessionId.value = nextSessionId;
  persistPreferences();
  log("Created new session.", { session_id: nextSessionId });
}

window.addEventListener("keydown", (event) => {
  if (event.code !== "Space" || event.repeat || shouldIgnoreSpaceHotkey(event)) {
    return;
  }
  event.preventDefault();
  startRecording();
});

window.addEventListener("keyup", (event) => {
  if (event.code !== "Space" || shouldIgnoreSpaceHotkey(event)) {
    return;
  }
  event.preventDefault();
  stopRecording();
});

elements.saveBackend.addEventListener("click", saveBackendUrl);
elements.saveSettings.addEventListener("click", () => saveAppSettings({ completeOnboarding: false }));
elements.syncSettings.addEventListener("click", () => saveAppSettings({ completeOnboarding: false }));
elements.testSettings.addEventListener("click", () => testProviderSettings());
elements.rebuildDigest.addEventListener("click", rebuildDigest);
elements.exportObsidian.addEventListener("click", exportDigestToObsidian);
elements.exportAiMateMemory.addEventListener("click", exportDigestToAiMateMemory);
elements.completeOnboarding.addEventListener("click", completeOnboarding);
elements.saveHotkey.addEventListener("click", saveHotkeyConfig);
elements.refreshPermissions.addEventListener("click", refreshMicrophonePermission);
elements.refreshRecent.addEventListener("click", refreshRecent);
elements.refreshHealth.addEventListener("click", () => refreshBackendHealth());
elements.refreshDigest.addEventListener("click", () => refreshSessionDigest());
elements.refreshHistory.addEventListener("click", () => refreshHistory());
elements.dismissRecent.addEventListener("click", dismissRecent);
elements.undoOutput.addEventListener("click", undoOutput);
elements.retryRecent.addEventListener("click", retryRecent);
elements.applyRecentMode.addEventListener("click", applyRecentMode);
elements.addDictionary.addEventListener("click", addRecentDictionary);
elements.startRecording.addEventListener("click", startRecording);
elements.stopRecording.addEventListener("click", stopRecording);
elements.newSession.addEventListener("click", resetSession);
elements.activeProfile.addEventListener("change", () => {
  renderProfileSummary(currentSettingsSnapshot);
});
elements.backendUrl.addEventListener("change", persistPreferences);
elements.hotkeyAccelerator.addEventListener("change", persistPreferences);
elements.hotkeyEnabled.addEventListener("change", persistPreferences);
elements.targetApp.addEventListener("change", persistPreferences);
elements.targetApp.addEventListener("change", () => {
  if (!elements.digestProjectKey.value.trim()) {
    elements.digestProjectKey.value = elements.targetApp.value.trim().toLowerCase();
  }
});
elements.targetApp.addEventListener("change", refreshOutputPolicyPreview);
elements.targetRisk.addEventListener("change", () => {
  persistPreferences();
  refreshOutputPolicyPreview();
});
elements.neverArchiveApps.addEventListener("change", refreshOutputPolicyPreview);
elements.fastPathOnlyApps.addEventListener("change", refreshOutputPolicyPreview);
elements.disableDirectTypingApps.addEventListener("change", refreshOutputPolicyPreview);
elements.policyPreviewSend.addEventListener("click", confirmPolicyPreview);
elements.policyPreviewCancel.addEventListener("click", cancelPolicyPreview);
elements.sessionId.addEventListener("change", persistPreferences);
elements.sessionId.addEventListener("change", () => refreshSessionDigest({ silent: true }));
elements.digestType.addEventListener("change", () => refreshSessionDigest({ silent: true }));
elements.digestDate.addEventListener("change", () => refreshSessionDigest({ silent: true }));
elements.digestProjectKey.addEventListener("change", () => refreshSessionDigest({ silent: true }));
elements.recordMode.addEventListener("change", persistPreferences);
elements.retryProvider.addEventListener("change", persistPreferences);
elements.historyQuery.addEventListener("change", () => {
  persistPreferences();
  refreshHistory();
});
elements.historyQuery.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    persistPreferences();
    refreshHistory();
  }
});
elements.historyAgent.addEventListener("change", () => {
  persistPreferences();
  refreshHistory();
});
elements.historySession.addEventListener("change", () => {
  persistPreferences();
  refreshHistory();
});
elements.historyCurrentOnly.addEventListener("change", () => {
  if (elements.historyCurrentOnly.checked) {
    elements.historySession.value = elements.sessionId.value.trim();
  }
  persistPreferences();
  refreshHistory();
});
elements.useCurrentSession.addEventListener("click", () => {
  elements.historySession.value = elements.sessionId.value.trim();
  elements.historyCurrentOnly.checked = false;
  persistPreferences();
  refreshHistory();
});
window.addEventListener("beforeunload", () => {
  if (globalHotkeyUnlisten) {
    Promise.resolve(globalHotkeyUnlisten()).catch(() => {});
  }
  if (healthPollTimer) {
    clearInterval(healthPollTimer);
  }
  if (recentPollTimer) {
    clearInterval(recentPollTimer);
  }
  if (historyPollTimer) {
    clearInterval(historyPollTimer);
  }
  if (previewPollTimer) {
    clearInterval(previewPollTimer);
  }
});

bootstrap();

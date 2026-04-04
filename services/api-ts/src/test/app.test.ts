import assert from "node:assert/strict";
import test from "node:test";

import type { BackendClient } from "../lib/backend-client.js";
import { createApp } from "../app.js";

function createMockClient(): BackendClient {
  return {
    async fetchFromPython(path) {
      if (path === "/v1/voice") {
        return new Response(
          JSON.stringify({
            id: "evt-voice",
            status: "ok",
            raw_text: "voice raw",
            display_text: "voice display",
            polished_text: "voice display",
            stt_provider: "whispercpp-local",
            stt_model: "base.en",
            target_app: "Cursor",
            target_risk_level: "low",
            should_autopaste: true,
            needs_review: false,
            confidence: 0.93,
            dictionary_applied: [],
            latency_ms: 450,
            session_id: "sess-voice",
            utterance_id: "utt-voice",
            output_id: "out-voice",
            output_mode: "paste",
            archive_status: "queued",
            created_at: "2026-04-03T00:00:00Z"
          })
        );
      }
      if (path === "/v1/voice/text") {
        return new Response(
          JSON.stringify({
            id: "evt-text",
            status: "ok",
            raw_text: "gateway text raw",
            display_text: "gateway text display",
            polished_text: "gateway text display",
            stt_provider: "gateway-text",
            stt_model: "text-v1",
            target_app: "Feishu",
            target_risk_level: "low",
            should_autopaste: true,
            needs_review: false,
            confidence: 0.98,
            dictionary_applied: [],
            latency_ms: 12,
            session_id: "sess-text",
            utterance_id: "utt-text",
            output_id: "out-text",
            output_mode: "paste",
            archive_status: "queued",
            created_at: "2026-04-03T00:00:00Z"
          })
        );
      }
      return new Response(JSON.stringify({}));
    },
    async getJsonFromPython<T = unknown>(path: string): Promise<T> {
      if (path === "/v1/recent") {
        return {
          recent: {
            id: "evt-1",
            utterance_id: "utt-1",
            session_id: "sess-1",
            output_id: "out-1",
            status: "ok",
            raw_text: "hello",
            display_text: "hello",
            target_app: "Cursor",
            target_risk_level: "low",
            recording_mode: "normal",
            output_mode: "paste",
            archive_status: "raw_only",
            confidence: 0.9,
            stt_provider: "whispercpp-local",
            stt_model: "base.en",
            dictionary_applied: [],
            expires_at: Date.now()
          }
        } as T;
      }
      if (path.startsWith("/v1/history")) {
        return [
          {
            id: "evt-2",
            created_at: "2026-04-03T00:00:00Z",
            utterance_id: "utt-2",
            output_id: "out-2",
            session_id: "sess-2",
            raw_text: "history raw",
            display_text: "history display",
            polished_text: "history display",
            stt_provider: "qwen-us",
            stt_model: "qwen3-asr-flash-us",
            llm_provider: "none",
            latency_ms: 1200,
            target_app: "Cursor",
            target_risk_level: "low",
            role: "me",
            recording_mode: "normal",
            output_mode: "paste",
            confidence: 0.88,
            archive_status: "queued",
            agent: "claude-code"
          }
        ] as T;
      }
      if (path === "/v1/agents") {
        return [
          {
            agent: "claude-code",
            count: 3,
            last_active: "2026-04-03T00:00:00Z"
          }
        ] as T;
      }
      if (path === "/v1/dictionary") {
        return {
          version: 1,
          corrections: { hello: "Hello" },
          preserve: ["Hello"],
          format_rules: { cn_en_space: true }
        } as T;
      }
      if (path === "/v1/settings/providers") {
        return {
          providers: {
            dashscope_us: { configured: true },
            dashscope_cn: { configured: false },
            openai: { configured: true },
            siliconflow: { configured: false }
          },
          active_profile: "home",
          digest_enhancement_enabled: true,
          digest_enhancement_provider: "auto",
          profiles: [
            {
              name: "home",
              stt_main: "qwen-us",
              stt_fallback: "openai-whisper",
              llm_main: "openai-gpt",
              llm_fallback: "qwen-turbo"
            }
          ],
          backend_auth_required: false
        } as T;
      }
      if (path === "/v1/settings/providers/test") {
        return {
          ready: true,
          active_profile: "home",
          recommended_stt_provider: "qwen-us",
          backend_url_reachable: true,
          configured_provider_count: 2,
          checks: [
            {
              key: "backend",
              label: "Backend Bridge",
              status: "ok",
              message: "TS service can reach the configured backend."
            },
            {
              key: "providers",
              label: "Provider Keys",
              status: "ok",
              message: "2 provider keys are configured."
            }
          ]
        } as T;
      }
      if (path === "/v1/stats") {
        return {
          count: 42,
          profile: "home"
        } as T;
      }
      if (path.startsWith("/v1/digests/session")) {
        return {
          id: "session:sess-1",
          digest_type: "session_digest",
          session_id: "sess-1",
          digest_date: "",
          project_key: "",
          source_event_id: "evt-1",
          created_at: "2026-04-03T00:00:00Z",
          updated_at: "2026-04-03T00:05:00Z",
          summary: "Discussed session digest rollout.",
          intent: "planning",
          suggested_tags: ["app:cursor", "session:sess-1"],
          mentioned_entities: ["digest", "cursor"],
          enhanced: false,
          enhancer_provider: "heuristic"
        } as T;
      }
      if (path.startsWith("/v1/digests/daily")) {
        return {
          id: "daily:2026-04-03",
          digest_type: "daily_digest",
          session_id: "",
          digest_date: "2026-04-03",
          project_key: "",
          source_event_id: "evt-2",
          created_at: "2026-04-03T00:00:00Z",
          updated_at: "2026-04-03T10:05:00Z",
          summary: "Rolled out digest work and reviewed Cursor session activity.",
          intent: "planning",
          suggested_tags: ["day:2026-04-03", "app:cursor"],
          mentioned_entities: ["digest", "cursor", "rollout"],
          enhanced: false,
          enhancer_provider: "heuristic"
        } as T;
      }
      if (path.startsWith("/v1/digests/project")) {
        return {
          id: "project:cursor",
          digest_type: "project_digest",
          session_id: "",
          digest_date: "",
          project_key: "cursor",
          source_event_id: "evt-3",
          created_at: "2026-04-03T00:00:00Z",
          updated_at: "2026-04-03T10:15:00Z",
          summary: "Cursor project focused on digest rollout, FTS fixes, and policy previews.",
          intent: "planning",
          suggested_tags: ["project:cursor", "entity:digest"],
          mentioned_entities: ["digest", "cursor", "policy"],
          enhanced: false,
          enhancer_provider: "heuristic"
        } as T;
      }
      return {} as T;
    },
    async parsePythonJson<T = unknown>(response: Response): Promise<T> {
      return response.json() as Promise<T>;
    },
    async postFormToPython<T = unknown>(path: string, form: Record<string, string>): Promise<T> {
      if (path === "/v1/recent/mode") {
        return {
          utterance_id: form.utterance_id,
          mode: form.mode
        } as T;
      }
      if (path === "/v1/output/undo") {
        return {
          output_id: form.output_id,
          utterance_id: "utt-1",
          accepted: true,
          archive_recalled: true,
          ui_undo_required: true,
          mode: "normal"
        } as T;
      }
      if (path === "/v1/recent/dismiss") {
        return {
          utterance_id: form.utterance_id,
          dismissed: true
        } as T;
      }
      if (path === "/v1/recent/dictionary") {
        return {
          utterance_id: form.utterance_id,
          wrong: form.wrong,
          right: form.right,
          dictionary: {
            version: 1,
            corrections: { [form.wrong]: form.right },
            preserve: [form.right],
            format_rules: { cn_en_space: true }
          }
        } as T;
      }
      if (path === "/v1/recent/retry") {
        return {
          id: "evt-3",
          utterance_id: "utt-3",
          session_id: "sess-1",
          output_id: "out-3",
          status: "ok",
          raw_text: "retry",
          display_text: "retry",
          target_app: "Cursor",
          target_risk_level: "low",
          recording_mode: "normal",
          output_mode: "paste",
          archive_status: "queued",
          confidence: 0.91,
          stt_provider: "whispercpp-local",
          stt_model: "base.en",
          dictionary_applied: [],
          expires_at: Date.now(),
          retried_from: form.utterance_id
        } as T;
      }
      return {} as T;
    },
    async postJsonToPython<T = unknown>(_path: string, body: unknown): Promise<T> {
      const mutation = body as { action: string; wrong: string; right?: string };
      if (_path === "/v1/settings/providers") {
        const payload = body as {
          active_profile?: string;
          dashscope_key_us?: string;
          openai_key?: string;
        };
        return {
          providers: {
            dashscope_us: { configured: Boolean(payload.dashscope_key_us) },
            dashscope_cn: { configured: false },
            openai: { configured: Boolean(payload.openai_key) },
            siliconflow: { configured: false }
          },
          active_profile: payload.active_profile || "home",
          digest_enhancement_enabled: true,
          digest_enhancement_provider: "auto",
          profiles: [
            {
              name: payload.active_profile || "home",
              stt_main: "qwen-us",
              stt_fallback: "openai-whisper",
              llm_main: "openai-gpt",
              llm_fallback: "qwen-turbo"
            }
          ],
          backend_auth_required: false
        } as T;
      }
      if (_path === "/v1/digests/rebuild") {
        const payload = body as { scope?: string; session_id?: string; date?: string; project_key?: string };
        if (payload.scope === "daily") {
          return {
            id: "daily:2026-04-03",
            digest_type: "daily_digest",
            session_id: "",
            digest_date: payload.date || "2026-04-03",
            project_key: "",
            source_event_id: "evt-2",
            created_at: "2026-04-03T00:00:00Z",
            updated_at: "2026-04-03T10:05:00Z",
            summary: "Rebuilt daily digest.",
            intent: "planning",
            suggested_tags: ["day:2026-04-03", "app:cursor"],
            mentioned_entities: ["digest", "cursor"],
            enhanced: false,
            enhancer_provider: "heuristic"
          } as T;
        }
        if (payload.scope === "project") {
          return {
            id: "project:cursor",
            digest_type: "project_digest",
            session_id: "",
            digest_date: "",
            project_key: payload.project_key || "cursor",
            source_event_id: "evt-3",
            created_at: "2026-04-03T00:00:00Z",
            updated_at: "2026-04-03T10:15:00Z",
            summary: "Rebuilt project digest.",
            intent: "planning",
            suggested_tags: ["project:cursor"],
            mentioned_entities: ["cursor"],
            enhanced: false,
            enhancer_provider: "heuristic"
          } as T;
        }
        return {
          id: "session:sess-1",
          digest_type: "session_digest",
          session_id: payload.session_id || "sess-1",
          digest_date: "",
          project_key: "",
          source_event_id: "evt-1",
          created_at: "2026-04-03T00:00:00Z",
          updated_at: "2026-04-03T10:05:00Z",
          summary: "Rebuilt session digest.",
          intent: "planning",
          suggested_tags: ["app:cursor"],
          mentioned_entities: ["cursor"],
          enhanced: false,
          enhancer_provider: "heuristic"
        } as T;
      }
      if (_path === "/v1/integrations/obsidian/export") {
        const payload = body as { vault_dir?: string; project_key?: string };
        return {
          ok: true,
          vault_path: payload.vault_dir || "/tmp/Vault",
          note_path: `${payload.vault_dir || "/tmp/Vault"}/VoxLog/Projects/${payload.project_key || "cursor"}.md`,
          bytes_written: 128
        } as T;
      }
      if (_path === "/v1/integrations/ai-mate-memory/export") {
        const payload = body as { base_dir?: string; project_key?: string };
        return {
          ok: true,
          base_path: payload.base_dir || "/tmp/ai-mate-memory",
          record_path: `${payload.base_dir || "/tmp/ai-mate-memory"}/voxlog/projects/${payload.project_key || "cursor"}-20260404T000000Z.json`,
          bytes_written: 256
        } as T;
      }
      if (_path === "/v1/voice/text") {
        return {
          id: "evt-text",
          status: "ok",
          raw_text: "gateway text raw",
          display_text: "gateway text display",
          polished_text: "gateway text display",
          stt_provider: "gateway-text",
          stt_model: "text-v1",
          target_app: "Feishu",
          target_risk_level: "low",
          should_autopaste: true,
          needs_review: false,
          confidence: 0.98,
          dictionary_applied: [],
          latency_ms: 12,
          session_id: "sess-text",
          utterance_id: "utt-text",
          output_id: "out-text",
          output_mode: "paste",
          archive_status: "queued",
          created_at: "2026-04-03T00:00:00Z"
        } as T;
      }
      return {
        version: 1,
        corrections: mutation.action === "add" ? { [mutation.wrong]: mutation.right ?? "" } : {},
        preserve: mutation.right ? [mutation.right] : [],
        format_rules: { cn_en_space: true }
      } as T;
    }
  };
}

test("GET /health returns service metadata", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/health"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().status, "ok");
  assert.equal(response.json().service, "api-ts");

  await app.close();
});

test("GET /v1/recent proxies and validates recent payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/v1/recent"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().recent.utterance_id, "utt-1");

  await app.close();
});

test("POST /v1/recent/mode proxies form payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/recent/mode",
    headers: {
      "content-type": "application/x-www-form-urlencoded"
    },
    payload: "utterance_id=utt-123&mode=private"
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    utterance_id: "utt-123",
    mode: "private"
  });

  await app.close();
});

test("GET /v1/history proxies query search", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/v1/history?q=history&limit=5"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json()[0].display_text, "history display");

  await app.close();
});

test("GET /v1/agents returns validated agent list", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/v1/agents"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json()[0].agent, "claude-code");

  await app.close();
});

test("POST /v1/dictionary validates mutation payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/dictionary",
    headers: {
      "content-type": "application/json"
    },
    payload: JSON.stringify({
      action: "add",
      wrong: "hello",
      right: "Hello"
    })
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().corrections.hello, "Hello");

  await app.close();
});

test("POST /v1/output/undo validates undo payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/output/undo",
    headers: {
      "content-type": "application/x-www-form-urlencoded"
    },
    payload: "output_id=out-123"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().accepted, true);
  assert.equal(response.json().output_id, "out-123");

  await app.close();
});

test("POST /v1/recent/retry returns validated retry payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/recent/retry",
    headers: {
      "content-type": "application/x-www-form-urlencoded"
    },
    payload: "utterance_id=utt-1&provider="
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().retried_from, "utt-1");
  assert.equal(response.json().utterance_id, "utt-3");

  await app.close();
});

test("POST /v1/voice validates multipart passthrough payload", async () => {
  const app = await createApp(createMockClient());
  const boundary = "----voxlog-test-boundary";
  const payload = Buffer.concat([
    Buffer.from(
      `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="audio"; filename="utterance.wav"\r\n` +
        `Content-Type: audio/wav\r\n\r\n`
    ),
    Buffer.from("fake-audio"),
    Buffer.from(
      `\r\n--${boundary}\r\n` +
        `Content-Disposition: form-data; name="source"\r\n\r\n` +
        `desktop-tauri\r\n` +
        `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="target_app"\r\n\r\n` +
        `Cursor\r\n` +
        `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="session_id"\r\n\r\n` +
        `sess-voice\r\n` +
        `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="mode"\r\n\r\n` +
        `normal\r\n` +
        `--${boundary}--\r\n`
    )
  ]);
  const response = await app.inject({
    method: "POST",
    url: "/v1/voice",
    headers: {
      "content-type": `multipart/form-data; boundary=${boundary}`
    },
    payload
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().utterance_id, "utt-voice");
  assert.equal(response.json().display_text, "voice display");

  await app.close();
});

test("POST /v1/voice/text validates JSON passthrough payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/voice/text",
    headers: {
      "content-type": "application/json"
    },
    payload: JSON.stringify({
      text: "gateway text raw",
      source: "feishu-bot",
      target_app: "Feishu",
      session_id: "sess-text",
      mode: "normal",
      role: "other"
    })
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().utterance_id, "utt-text");
  assert.equal(response.json().stt_provider, "gateway-text");

  await app.close();
});

test("GET /v1/settings/providers returns provider settings", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/v1/settings/providers"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().providers.dashscope_us.configured, true);
  assert.equal(response.json().active_profile, "home");

  await app.close();
});

test("POST /v1/settings/providers updates provider settings", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/settings/providers",
    headers: {
      "content-type": "application/json"
    },
    payload: JSON.stringify({
      active_profile: "home",
      dashscope_key_us: "test-key",
      openai_key: "openai-key"
    })
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().providers.dashscope_us.configured, true);
  assert.equal(response.json().providers.openai.configured, true);

  await app.close();
});

test("GET /v1/settings/providers/test returns provider connectivity", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/v1/settings/providers/test"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().ready, true);
  assert.equal(response.json().configured_provider_count, 2);
  assert.equal(response.json().checks[0].key, "backend");

  await app.close();
});

test("GET /v1/digests/session returns validated session digest", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/v1/digests/session?session_id=sess-1"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().digest_type, "session_digest");
  assert.equal(response.json().session_id, "sess-1");

  await app.close();
});

test("GET /v1/digests/daily returns validated daily digest", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/v1/digests/daily?date=2026-04-03"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().digest_type, "daily_digest");
  assert.equal(response.json().digest_date, "2026-04-03");

  await app.close();
});

test("GET /v1/digests/project returns validated project digest", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "GET",
    url: "/v1/digests/project?project_key=cursor"
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().digest_type, "project_digest");
  assert.equal(response.json().project_key, "cursor");

  await app.close();
});

test("POST /v1/digests/rebuild returns rebuilt digest payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/digests/rebuild",
    headers: {
      "content-type": "application/json"
    },
    payload: JSON.stringify({
      scope: "session",
      session_id: "sess-1"
    })
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().digest_type, "session_digest");
  assert.equal(response.json().summary, "Rebuilt session digest.");

  await app.close();
});

test("POST /v1/digests/rebuild returns rebuilt daily digest payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/digests/rebuild",
    headers: {
      "content-type": "application/json"
    },
    payload: JSON.stringify({
      scope: "daily",
      date: "2026-04-03"
    })
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().digest_type, "daily_digest");
  assert.equal(response.json().summary, "Rebuilt daily digest.");

  await app.close();
});

test("POST /v1/digests/rebuild returns rebuilt project digest payload", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/digests/rebuild",
    headers: {
      "content-type": "application/json"
    },
    payload: JSON.stringify({
      scope: "project",
      project_key: "cursor"
    })
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().digest_type, "project_digest");
  assert.equal(response.json().summary, "Rebuilt project digest.");

  await app.close();
});

test("POST /v1/integrations/obsidian/export returns export metadata", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/integrations/obsidian/export",
    headers: {
      "content-type": "application/json"
    },
    payload: JSON.stringify({
      scope: "project",
      project_key: "cursor",
      vault_dir: "/tmp/Vault"
    })
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().ok, true);
  assert.match(response.json().note_path, /cursor\.md$/);

  await app.close();
});

test("POST /v1/integrations/ai-mate-memory/export returns export metadata", async () => {
  const app = await createApp(createMockClient());
  const response = await app.inject({
    method: "POST",
    url: "/v1/integrations/ai-mate-memory/export",
    headers: {
      "content-type": "application/json"
    },
    payload: JSON.stringify({
      scope: "project",
      project_key: "cursor",
      base_dir: "/tmp/ai-mate-memory"
    })
  });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().ok, true);
  assert.match(response.json().record_path, /cursor-.*\.json$/);

  await app.close();
});

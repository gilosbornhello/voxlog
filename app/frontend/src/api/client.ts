/**
 * VoxLog API client — talks to the Python backend on localhost.
 */

const BASE = 'http://127.0.0.1:7890'
const TOKEN = 'voxlog-dev-token'

const headers = () => ({
  'Authorization': `Bearer ${TOKEN}`,
})

export interface Message {
  id: string
  created_at: string
  raw_text: string
  display_text: string
  polished_text: string
  stt_provider: string
  latency_ms: number
  target_app: string
  role: 'me' | 'other'
  agent: string
  recording_mode?: string
}

export interface AgentInfo {
  agent: string
  count: number
  last_active: string
}

// --- Health ---

export async function checkHealth(): Promise<{ status: string; version: string }> {
  const r = await fetch(`${BASE}/health`)
  return r.json()
}

// --- Voice (fast path) ---

export async function sendVoice(audio: Blob, agent: string): Promise<Message> {
  const form = new FormData()
  form.append('audio', audio, 'recording.wav')
  form.append('source', 'desktop')
  form.append('env', 'auto')
  form.append('agent', agent)
  form.append('target_app', 'VoxLog')

  const r = await fetch(`${BASE}/v1/voice`, {
    method: 'POST',
    headers: headers(),
    body: form,
  })
  if (!r.ok) throw new Error(`Voice failed: ${r.status}`)
  return r.json()
}

// --- Save text ---

export async function saveText(text: string, agent: string): Promise<Message> {
  const form = new URLSearchParams()
  form.append('text', text)
  form.append('source', 'paste')
  form.append('agent', agent)
  form.append('target_app', 'paste')

  const r = await fetch(`${BASE}/v1/save`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form.toString(),
  })
  if (!r.ok) throw new Error(`Save failed: ${r.status}`)
  return r.json()
}

// --- History ---

export async function getAgents(): Promise<AgentInfo[]> {
  const r = await fetch(`${BASE}/v1/agents`, { headers: headers() })
  return r.json()
}

export async function getHistory(agent: string, limit = 200): Promise<Message[]> {
  const r = await fetch(
    `${BASE}/v1/history/agent?agent=${encodeURIComponent(agent)}&limit=${limit}`,
    { headers: headers() }
  )
  return r.json()
}

export async function searchHistory(q: string, limit = 50): Promise<Message[]> {
  const r = await fetch(
    `${BASE}/v1/history?q=${encodeURIComponent(q)}&limit=${limit}`,
    { headers: headers() }
  )
  return r.json()
}

// --- Recall ---

export async function recallMessage(id: string): Promise<boolean> {
  const r = await fetch(`${BASE}/v1/history/${id}`, {
    method: 'DELETE',
    headers: headers(),
  })
  return r.ok
}

// --- ASR switch ---

export async function switchASR(model: string): Promise<{ model: string }> {
  const form = new URLSearchParams()
  form.append('model', model)
  const r = await fetch(`${BASE}/v1/asr/switch`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form.toString(),
  })
  return r.json()
}

// --- Detect network ---

export async function detectEnv(): Promise<{ env: string; route: Record<string, string> }> {
  const r = await fetch(`${BASE}/v1/detect`, { headers: headers() })
  return r.json()
}

// --- Dictionary ---

export async function getDictionary(): Promise<Record<string, unknown>> {
  const r = await fetch(`${BASE}/v1/dictionary`, { headers: headers() })
  return r.json()
}

export async function addDictTerm(wrong: string, right: string): Promise<void> {
  await fetch(`${BASE}/v1/dictionary`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'add', wrong, right }),
  })
}

export async function deleteDictTerm(wrong: string): Promise<void> {
  await fetch(`${BASE}/v1/dictionary`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'delete', wrong }),
  })
}

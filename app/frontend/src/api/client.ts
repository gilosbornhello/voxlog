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

// --- Agent CRUD ---

export interface AgentFull {
  id: string
  name: string
  emoji: string
  agent_type: string
  parent_id: string
  external_system?: string
  external_agent_ref?: string
  binding_status?: string
  can_accept_tasks?: boolean
  is_archived?: boolean
}

export async function getAllAgents(): Promise<AgentFull[]> {
  const r = await fetch(`${BASE}/v1/agents/all`, { headers: headers() })
  return r.json()
}

export async function createAgent(name: string, emoji: string, parentId = ''): Promise<AgentFull> {
  const r = await fetch(`${BASE}/v1/agents/create`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, emoji, parent_id: parentId }),
  })
  return r.json()
}

export async function deleteAgent(id: string): Promise<void> {
  await fetch(`${BASE}/v1/agents/${id}`, { method: 'DELETE', headers: headers() })
}

export async function bindAgent(id: string, ref: string): Promise<void> {
  await fetch(`${BASE}/v1/agents/${id}/bind`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ external_system: 'xiaolongxia_local', external_agent_ref: ref, can_accept_tasks: true }),
  })
}

// --- Groups ---

export interface GroupInfo {
  id: string
  title: string
  emoji: string
  member_agent_ids: string[]
}

export async function getGroups(): Promise<GroupInfo[]> {
  const r = await fetch(`${BASE}/v1/groups`, { headers: headers() })
  return r.json()
}

export async function createGroup(title: string, emoji: string, members: string[]): Promise<GroupInfo> {
  const r = await fetch(`${BASE}/v1/groups/create`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, emoji, members }),
  })
  return r.json()
}

export async function deleteGroup(id: string): Promise<void> {
  await fetch(`${BASE}/v1/groups/${id}`, { method: 'DELETE', headers: headers() })
}

// --- Tasks ---

export interface TaskInfo {
  id: string
  title: string
  description: string
  assigned_context_id: string
  status: string
  priority: string
  source_message_id: string
  created_at: string
}

export async function getTasks(agent?: string, status?: string): Promise<TaskInfo[]> {
  const params = new URLSearchParams()
  if (agent) params.set('agent', agent)
  if (status) params.set('status', status)
  const r = await fetch(`${BASE}/v1/tasks?${params}`, { headers: headers() })
  return r.json()
}

export async function createTask(title: string, assignedTo: string, messageId?: string, description?: string): Promise<TaskInfo> {
  const r = await fetch(`${BASE}/v1/tasks/create`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, assigned_to: assignedTo, source_message_id: messageId || '', description: description || '' }),
  })
  return r.json()
}

export async function updateTaskStatus(id: string, status: string): Promise<void> {
  await fetch(`${BASE}/v1/tasks/${id}/status`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ status }),
  })
}

// --- Identity ---

export async function getIdentity(): Promise<{ self_id: string; display_name: string; role: string }> {
  const r = await fetch(`${BASE}/v1/identity`, { headers: headers() })
  return r.json()
}

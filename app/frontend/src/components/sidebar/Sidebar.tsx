import { useState, useEffect } from 'react'
import { getAllAgents, getAgents, getGroups, createAgent, deleteAgent, createGroup, type AgentFull, type GroupInfo } from '../../api/client'
import styles from './Sidebar.module.css'

const DEFAULT_AGENTS: AgentFull[] = [
  { id: 'claude-code', name: 'Claude Code', emoji: '👨‍💻', agent_type: 'system_default', parent_id: '' },
  { id: 'claude-code/office-hours', name: 'Office Hours', emoji: '🧑‍💼', agent_type: 'system_default', parent_id: 'claude-code' },
  { id: 'claude-code/ceo-review', name: 'CEO Review', emoji: '👔', agent_type: 'system_default', parent_id: 'claude-code' },
  { id: 'claude-code/eng-review', name: 'Eng Review', emoji: '🔧', agent_type: 'system_default', parent_id: 'claude-code' },
  { id: 'claude-code/design-review', name: 'Design Review', emoji: '🎨', agent_type: 'system_default', parent_id: 'claude-code' },
  { id: 'claude-mac', name: 'Claude for Mac', emoji: '🖥️', agent_type: 'system_default', parent_id: '' },
  { id: 'claude-mac/chat', name: 'Chat', emoji: '💬', agent_type: 'system_default', parent_id: 'claude-mac' },
  { id: 'claude-mac/cowork', name: 'Co-work', emoji: '🤝', agent_type: 'system_default', parent_id: 'claude-mac' },
  { id: 'openclaw', name: 'OpenClaw', emoji: '🦞', agent_type: 'system_default', parent_id: '' },
  { id: 'osborn', name: 'Osborn', emoji: '🧠', agent_type: 'system_default', parent_id: '' },
  { id: 'general', name: 'General', emoji: '📝', agent_type: 'system_default', parent_id: '' },
]

interface SidebarProps {
  selectedAgent: string
  onSelectAgent: (id: string) => void
}

export function Sidebar({ selectedAgent, onSelectAgent }: SidebarProps) {
  const [agents, setAgents] = useState<AgentFull[]>(DEFAULT_AGENTS)
  const [groups, setGroups] = useState<GroupInfo[]>([])
  const [counts, setCounts] = useState<Record<string, number>>({})
  const [showAdd, setShowAdd] = useState(false)
  const [addType, setAddType] = useState<'agent' | 'group'>('agent')
  const [newName, setNewName] = useState('')
  const [newEmoji, setNewEmoji] = useState('🤖')

  useEffect(() => {
    // Load agents
    getAllAgents().then(data => { if (data.length > 0) setAgents(data) }).catch(() => {})
    // Load groups
    getGroups().then(setGroups).catch(() => {})
    // Load counts
    getAgents().then(data => {
      const c: Record<string, number> = {}
      for (const a of data) c[a.agent] = a.count
      setCounts(c)
    }).catch(() => {})
  }, [selectedAgent])

  const topLevel = agents.filter(a => !a.parent_id)
  const subAgents = (pid: string) => agents.filter(a => a.parent_id === pid)

  const handleAdd = async () => {
    if (!newName.trim()) return
    if (addType === 'agent') {
      const created = await createAgent(newName, newEmoji || '🤖')
      setAgents(prev => [...prev, created])
    } else {
      const created = await createGroup(newName, newEmoji || '👥', [])
      setGroups(prev => [...prev, created])
    }
    setNewName(''); setNewEmoji('🤖'); setShowAdd(false)
  }

  const handleDelete = async (id: string, type: 'agent' | 'group') => {
    if (type === 'agent') {
      await deleteAgent(id)
      setAgents(prev => prev.filter(a => a.id !== id))
    }
    // TODO: deleteGroup
  }

  return (
    <div className={styles.sidebar}>
      {/* Gilbert identity */}
      <div className={styles.identity}>
        <span className={styles.identityAvatar}>👤</span>
        <span className={styles.identityName}>Gilbert</span>
      </div>

      <div className={styles.header}>
        <span className={styles.title}>Agents</span>
        <button className={styles.addBtn} onClick={() => { setShowAdd(!showAdd); setAddType('agent') }}>+</button>
      </div>

      {showAdd && (
        <div className={styles.addForm}>
          <select className={styles.typeSelect} value={addType} onChange={e => setAddType(e.target.value as any)}>
            <option value="agent">Agent</option>
            <option value="group">Group</option>
          </select>
          <input className={styles.emojiInput} value={newEmoji} onChange={e => setNewEmoji(e.target.value)} maxLength={2} />
          <input className={styles.nameInput} value={newName} onChange={e => setNewName(e.target.value)} placeholder="Name" onKeyDown={e => e.key === 'Enter' && handleAdd()} />
          <button className={styles.addConfirm} onClick={handleAdd}>Add</button>
        </div>
      )}

      <div className={styles.list}>
        {/* Agents */}
        {topLevel.map(agent => (
          <div key={agent.id}>
            <div
              className={`${styles.agentRow} ${selectedAgent === agent.id ? styles.selected : ''}`}
              onClick={() => onSelectAgent(agent.id)}
              onContextMenu={e => {
                e.preventDefault()
                if (agent.agent_type === 'user_created' && confirm(`Delete ${agent.name}?`)) handleDelete(agent.id, 'agent')
              }}
            >
              <span className={styles.avatar}>{agent.emoji}</span>
              <div className={styles.agentInfo}>
                <span className={styles.agentName}>{agent.name}</span>
                {(counts[agent.id] || 0) > 0 && <span className={styles.agentCount}>{counts[agent.id]} msgs</span>}
              </div>
              {agent.binding_status === 'bound' && <span className={styles.boundBadge} title="Bound to 小龙虾">🔗</span>}
            </div>
            {subAgents(agent.id).map(sub => (
              <div
                key={sub.id}
                className={`${styles.agentRow} ${styles.indent} ${selectedAgent === sub.id ? styles.selected : ''}`}
                onClick={() => onSelectAgent(sub.id)}
              >
                <span className={`${styles.avatar} ${styles.avatarSmall}`}>{sub.emoji}</span>
                <span className={styles.agentName}>{sub.name}</span>
              </div>
            ))}
          </div>
        ))}

        {/* Groups section */}
        {groups.length > 0 && (
          <>
            <div className={styles.sectionHeader}>Groups</div>
            {groups.map(group => (
              <div
                key={group.id}
                className={`${styles.agentRow} ${selectedAgent === group.id ? styles.selected : ''}`}
                onClick={() => onSelectAgent(group.id)}
              >
                <span className={styles.avatar}>{group.emoji}</span>
                <div className={styles.agentInfo}>
                  <span className={styles.agentName}>{group.title}</span>
                  <span className={styles.agentCount}>{group.member_agent_ids.length} members</span>
                </div>
              </div>
            ))}
          </>
        )}
      </div>

      <div className={styles.footer}>
        <button className={styles.footerBtn} title="Sync Obsidian" onClick={() => fetch('http://127.0.0.1:7890/v1/sync-obsidian', { method: 'POST', headers: { 'Authorization': 'Bearer voxlog-dev-token' } }).then(() => alert('Synced!')).catch(() => {})}>🔄</button>
        <button className={styles.footerBtn} title="Dictionary">📖</button>
        <button className={styles.footerBtn} title="Settings">⚙️</button>
      </div>
    </div>
  )
}

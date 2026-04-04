import { useState, useEffect } from 'react'
import { getAgents } from '../../api/client'
import styles from './Sidebar.module.css'

interface Agent {
  id: string
  name: string
  emoji: string
  parent: string
  count: number
  type: 'system_default' | 'user_created' | 'group'
}

const DEFAULT_AGENTS: Agent[] = [
  { id: 'claude-code', name: 'Claude Code', emoji: '👨‍💻', parent: '', count: 0, type: 'system_default' },
  { id: 'claude-code/office-hours', name: 'Office Hours', emoji: '🧑‍💼', parent: 'claude-code', count: 0, type: 'system_default' },
  { id: 'claude-code/ceo-review', name: 'CEO Review', emoji: '👔', parent: 'claude-code', count: 0, type: 'system_default' },
  { id: 'claude-code/eng-review', name: 'Eng Review', emoji: '🔧', parent: 'claude-code', count: 0, type: 'system_default' },
  { id: 'claude-code/design-review', name: 'Design Review', emoji: '🎨', parent: 'claude-code', count: 0, type: 'system_default' },
  { id: 'claude-mac', name: 'Claude for Mac', emoji: '🖥️', parent: '', count: 0, type: 'system_default' },
  { id: 'claude-mac/chat', name: 'Chat', emoji: '💬', parent: 'claude-mac', count: 0, type: 'system_default' },
  { id: 'claude-mac/cowork', name: 'Co-work', emoji: '🤝', parent: 'claude-mac', count: 0, type: 'system_default' },
  { id: 'openclaw', name: 'OpenClaw', emoji: '🦞', parent: '', count: 0, type: 'system_default' },
  { id: 'osborn', name: 'Osborn', emoji: '🧠', parent: '', count: 0, type: 'system_default' },
  { id: 'general', name: 'General', emoji: '📝', parent: '', count: 0, type: 'system_default' },
]

interface SidebarProps {
  selectedAgent: string
  onSelectAgent: (id: string) => void
}

export function Sidebar({ selectedAgent, onSelectAgent }: SidebarProps) {
  const [agents, setAgents] = useState<Agent[]>(DEFAULT_AGENTS)
  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState('')
  const [newEmoji, setNewEmoji] = useState('🤖')

  // Load agent counts from backend
  useEffect(() => {
    getAgents().then(apiAgents => {
      setAgents(prev => {
        const updated = [...prev]
        for (const a of apiAgents) {
          const idx = updated.findIndex(x => x.id === a.agent)
          if (idx >= 0) {
            updated[idx] = { ...updated[idx], count: a.count }
          }
        }
        return updated
      })
    }).catch(() => {}) // silently fail if backend not ready
  }, [selectedAgent])

  const topLevel = agents.filter(a => a.parent === '')
  const subAgents = (parentId: string) => agents.filter(a => a.parent === parentId)

  const handleAdd = () => {
    if (!newName.trim()) return
    const id = newName.toLowerCase().replace(/\s+/g, '-')
    const emoji = newEmoji || '🤖'
    setAgents(prev => [...prev, { id, name: newName, emoji, parent: '', count: 0, type: 'user_created' }])
    setNewName('')
    setNewEmoji('🤖')
    setShowAdd(false)
  }

  return (
    <div className={styles.sidebar}>
      <div className={styles.header}>
        <span className={styles.title}>Agents</span>
        <button className={styles.addBtn} onClick={() => setShowAdd(!showAdd)}>+</button>
      </div>

      {showAdd && (
        <div className={styles.addForm}>
          <input className={styles.emojiInput} value={newEmoji} onChange={e => setNewEmoji(e.target.value)} maxLength={2} />
          <input className={styles.nameInput} value={newName} onChange={e => setNewName(e.target.value)} placeholder="Name" onKeyDown={e => e.key === 'Enter' && handleAdd()} />
          <button className={styles.addConfirm} onClick={handleAdd}>Add</button>
        </div>
      )}

      <div className={styles.list}>
        {topLevel.map(agent => (
          <div key={agent.id}>
            <div
              className={`${styles.agentRow} ${selectedAgent === agent.id ? styles.selected : ''}`}
              onClick={() => onSelectAgent(agent.id)}
            >
              <span className={styles.avatar}>{agent.emoji}</span>
              <div className={styles.agentInfo}>
                <span className={styles.agentName}>{agent.name}</span>
                {agent.count > 0 && <span className={styles.agentCount}>{agent.count} messages</span>}
              </div>
            </div>
            {subAgents(agent.id).map(sub => (
              <div
                key={sub.id}
                className={`${styles.agentRow} ${styles.indent} ${selectedAgent === sub.id ? styles.selected : ''}`}
                onClick={() => onSelectAgent(sub.id)}
              >
                <span className={`${styles.avatar} ${styles.avatarSmall}`}>{sub.emoji}</span>
                <div className={styles.agentInfo}>
                  <span className={styles.agentName}>{sub.name}</span>
                </div>
                {sub.count > 0 && <span className={styles.badge}>{sub.count}</span>}
              </div>
            ))}
          </div>
        ))}
      </div>

      <div className={styles.footer}>
        <button className={styles.footerBtn} title="Sync Obsidian">🔄 Sync</button>
        <button className={styles.footerBtn} title="Dictionary">📖 Dict</button>
        <button className={styles.footerBtn} title="Settings">⚙️</button>
      </div>
    </div>
  )
}

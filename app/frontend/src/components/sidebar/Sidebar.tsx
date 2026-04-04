import { useState } from 'react'
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
  { id: 'general', name: 'General', emoji: '📝', parent: '', count: 0, type: 'system_default' },
]

interface SidebarProps {
  selectedAgent: string
  onSelectAgent: (id: string) => void
}

export function Sidebar({ selectedAgent, onSelectAgent }: SidebarProps) {
  const [agents] = useState<Agent[]>(DEFAULT_AGENTS)
  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState('')
  const [newEmoji, setNewEmoji] = useState('🤖')

  const topLevel = agents.filter(a => a.parent === '')
  const subAgents = (parentId: string) => agents.filter(a => a.parent === parentId)

  const handleAdd = () => {
    if (!newName.trim()) return
    // TODO: add agent via API
    setNewName('')
    setNewEmoji('🤖')
    setShowAdd(false)
  }

  return (
    <div className={styles.sidebar}>
      {/* Header */}
      <div className={styles.header}>
        <span className={styles.title}>Agents</span>
        <button className={styles.addBtn} onClick={() => setShowAdd(!showAdd)}>+</button>
      </div>

      {/* Add form */}
      {showAdd && (
        <div className={styles.addForm}>
          <input
            className={styles.emojiInput}
            value={newEmoji}
            onChange={e => setNewEmoji(e.target.value)}
            maxLength={2}
          />
          <input
            className={styles.nameInput}
            value={newName}
            onChange={e => setNewName(e.target.value)}
            placeholder="Name"
          />
          <button className={styles.addConfirm} onClick={handleAdd}>Add</button>
        </div>
      )}

      {/* Agent list */}
      <div className={styles.list}>
        {topLevel.map(agent => (
          <div key={agent.id}>
            <AgentRow
              agent={agent}
              selected={agent.id === selectedAgent}
              onClick={() => onSelectAgent(agent.id)}
            />
            {subAgents(agent.id).map(sub => (
              <AgentRow
                key={sub.id}
                agent={sub}
                selected={sub.id === selectedAgent}
                onClick={() => onSelectAgent(sub.id)}
                indent
              />
            ))}
          </div>
        ))}
      </div>

      {/* Bottom toolbar */}
      <div className={styles.footer}>
        <button className={styles.footerBtn} title="Sync Obsidian">🔄 Sync</button>
        <button className={styles.footerBtn} title="Dictionary">📖 Dict</button>
        <button className={styles.footerBtn} title="Settings">⚙️</button>
      </div>
    </div>
  )
}

function AgentRow({ agent, selected, onClick, indent }: {
  agent: Agent
  selected: boolean
  onClick: () => void
  indent?: boolean
}) {
  return (
    <div
      className={`${styles.agentRow} ${selected ? styles.selected : ''} ${indent ? styles.indent : ''}`}
      onClick={onClick}
    >
      <span className={`${styles.avatar} ${indent ? styles.avatarSmall : ''}`}>
        {agent.emoji}
      </span>
      <div className={styles.agentInfo}>
        <span className={styles.agentName}>{agent.name}</span>
        {agent.count > 0 && !indent && (
          <span className={styles.agentCount}>{agent.count} messages</span>
        )}
      </div>
      {agent.count > 0 && indent && (
        <span className={styles.badge}>{agent.count}</span>
      )}
    </div>
  )
}

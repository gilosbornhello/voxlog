import styles from './Toolbar.module.css'

interface ToolbarProps {
  title: string
  showSidebar: boolean
  showPreview: boolean
  onToggleSidebar: () => void
  onTogglePreview: () => void
}

export function Toolbar({ title, showSidebar: _showSidebar, showPreview, onToggleSidebar, onTogglePreview }: ToolbarProps) {
  return (
    <div className={styles.toolbar}>
      <button className={styles.iconBtn} onClick={onToggleSidebar} title="Toggle sidebar">
        ☰
      </button>
      <span className={styles.title}>{formatTitle(title)}</span>
      <div className={styles.spacer} />

      {/* Three-dot menu */}
      <button className={styles.iconBtn} title="Menu">⋯</button>

      <button
        className={`${styles.iconBtn} ${showPreview ? styles.active : ''}`}
        onClick={onTogglePreview}
        title="Toggle preview"
      >
        ▫
      </button>
    </div>
  )
}

function formatTitle(agentId: string): string {
  const names: Record<string, string> = {
    'claude-code': 'Claude Code',
    'claude-code/office-hours': 'Office Hours',
    'claude-code/ceo-review': 'CEO Review',
    'claude-code/eng-review': 'Eng Review',
    'claude-code/design-review': 'Design Review',
    'claude-mac': 'Claude for Mac',
    'claude-mac/chat': 'Chat',
    'claude-mac/cowork': 'Co-work',
    'openclaw': 'OpenClaw',
    'general': 'General',
  }
  return names[agentId] || agentId
}

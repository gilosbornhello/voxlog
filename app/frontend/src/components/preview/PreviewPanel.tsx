import { useState, useEffect } from 'react'
import styles from './PreviewPanel.module.css'

interface PreviewPanelProps {
  filePath: string
  onClose: () => void
}

export function PreviewPanel({ filePath, onClose }: PreviewPanelProps) {
  const [content, setContent] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!filePath) return
    setLoading(true)
    // TODO: read file via Tauri API or backend
    setContent(`# Preview\n\nFile: ${filePath}\n\n(Content loading not yet connected)`)
    setLoading(false)
  }, [filePath])

  const fileName = filePath.split('/').pop() || ''

  return (
    <div className={styles.panel}>
      {/* Header */}
      <div className={styles.header}>
        <span className={styles.icon}>📄</span>
        <span className={styles.fileName}>{fileName}</span>
        <div className={styles.spacer} />
        <button className={styles.btn} title="Copy path">📋</button>
        <button className={styles.btn} title="Open in Finder">📂</button>
        <button className={styles.btn} onClick={onClose}>✕</button>
      </div>

      {/* Path */}
      <div className={styles.path}>{filePath}</div>

      {/* Content */}
      <div className={styles.content}>
        {loading ? (
          <div className={styles.loading}>Loading...</div>
        ) : (
          <div className={styles.markdown}>{content}</div>
        )}
      </div>
    </div>
  )
}

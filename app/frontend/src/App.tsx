import { useState } from 'react'
import { Sidebar } from './components/sidebar/Sidebar'
import { ChatArea } from './components/chat/ChatArea'
import { PreviewPanel } from './components/preview/PreviewPanel'
import { InputBar } from './components/input/InputBar'
import { Toolbar } from './components/common/Toolbar'
import styles from './App.module.css'

export default function App() {
  const [showSidebar, setShowSidebar] = useState(true)
  const [showPreview, setShowPreview] = useState(false)
  const [previewPath, setPreviewPath] = useState('')
  const [selectedAgent, setSelectedAgent] = useState('claude-code')

  const handleFileTap = (path: string) => {
    setPreviewPath(path)
    setShowPreview(true)
  }

  return (
    <div className={styles.layout}>
      {showSidebar && (
        <>
          <Sidebar
            selectedAgent={selectedAgent}
            onSelectAgent={setSelectedAgent}
          />
          <div className={styles.divider} />
        </>
      )}

      <div className={styles.center}>
        <Toolbar
          title={selectedAgent}
          showSidebar={showSidebar}
          showPreview={showPreview}
          onToggleSidebar={() => setShowSidebar(!showSidebar)}
          onTogglePreview={() => setShowPreview(!showPreview)}
        />
        <div className={styles.dividerH} />
        <ChatArea agent={selectedAgent} onFileTap={handleFileTap} />
        <div className={styles.dividerH} />
        <InputBar agent={selectedAgent} />
      </div>

      {showPreview && (
        <>
          <div className={styles.divider} />
          <PreviewPanel
            filePath={previewPath}
            onClose={() => setShowPreview(false)}
          />
        </>
      )}
    </div>
  )
}

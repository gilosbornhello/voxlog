import { useState } from 'react'
import styles from './InputBar.module.css'

interface InputBarProps {
  agent: string
}

export function InputBar({ agent: _agent }: InputBarProps) {
  const [text, setText] = useState('')
  const [isRecording, setIsRecording] = useState(false)
  const [isProcessing, setIsProcessing] = useState(false)

  const handleMicClick = () => {
    if (isRecording) {
      // Stop and transcribe
      setIsRecording(false)
      setIsProcessing(true)
      // TODO: stop recording, send to fast path
      setTimeout(() => setIsProcessing(false), 2000)
    } else {
      setIsRecording(true)
      // TODO: start recording
    }
  }

  const handleSend = () => {
    if (!text.trim()) return
    // TODO: save text via API
    setText('')
  }

  const handleFileAdd = () => {
    // TODO: open file picker
  }

  if (isRecording) {
    return (
      <div className={styles.recordingBar}>
        <button className={styles.cancelBtn} onClick={() => setIsRecording(false)}>✕</button>
        <div className={styles.listening}>
          <span className={styles.pulse} />
          <span>Listening...</span>
        </div>
        <button className={styles.sendBtn} onClick={handleMicClick}>↑</button>
      </div>
    )
  }

  if (isProcessing) {
    return (
      <div className={styles.processingBar}>
        <span className={styles.spinner}>⟳</span>
        <span>Transcribing...</span>
      </div>
    )
  }

  return (
    <div className={styles.inputBar}>
      {/* + Add file */}
      <button className={styles.addBtn} onClick={handleFileAdd} title="Add files or photos">
        ⊕
      </button>

      {/* Text input */}
      <textarea
        className={styles.textInput}
        value={text}
        onChange={e => setText(e.target.value)}
        placeholder="Paste AI response..."
        rows={1}
        onKeyDown={e => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault()
            handleSend()
          }
        }}
      />

      {/* ASR model selector */}
      <button className={styles.modelBtn} title="Switch ASR model">
        ASR
      </button>

      {/* Mic or Send */}
      {text.trim() ? (
        <button className={styles.sendBtn} onClick={handleSend} title="Send">↑</button>
      ) : (
        <button className={styles.micBtn} onClick={handleMicClick} title="Record voice">
          🎤
        </button>
      )}
    </div>
  )
}

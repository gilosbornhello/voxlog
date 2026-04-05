import { useState, useCallback } from 'react'
import { invoke } from '@tauri-apps/api/core'
import { saveText, switchASR, type Message } from '../../api/client'
import styles from './InputBar.module.css'

interface InputBarProps {
  agent: string
}

export function InputBar({ agent }: InputBarProps) {
  const [text, setText] = useState('')
  const [isRecording, setIsRecording] = useState(false)
  const [isProcessing, setIsProcessing] = useState(false)
  const [error, setError] = useState('')
  const [currentASR, setCurrentASR] = useState('Auto')
  const [showASRMenu, setShowASRMenu] = useState(false)

  const addMessage = (msg: Message) => {
    const fn = (window as any).__voxlog_addMessage
    if (fn) fn(msg)
  }

  const startRecording = useCallback(async () => {
    setError('')
    try {
      await invoke('start_recording')
      setIsRecording(true)
    } catch (err: any) {
      setError(`Record error: ${err}`)
    }
  }, [])

  const stopAndTranscribe = useCallback(async () => {
    setIsRecording(false)
    setIsProcessing(true)
    setError('')

    try {
      // Stop recording — returns WAV path
      const wavPath = await invoke<string>('stop_recording')

      // Send to API via Rust (bypasses webview restrictions)
      const resultJson = await invoke<string>('send_recording_to_api', {
        wavPath,
        agent,
      })

      const result = JSON.parse(resultJson) as Message
      addMessage(result)
    } catch (err: any) {
      setError(`Transcribe error: ${err}`)
    }

    setIsProcessing(false)
  }, [agent])

  const cancelRecording = useCallback(async () => {
    setIsRecording(false)
    try { await invoke('stop_recording') } catch {}
  }, [])

  const handleSend = async () => {
    if (!text.trim()) return
    const t = text
    setText('')
    setError('')
    try {
      const result = await saveText(t, agent)
      addMessage(result)
    } catch (err: any) {
      setError(`Send failed: ${err.message || err}`)
    }
  }

  const handleASRSwitch = async (model: string, label: string) => {
    setCurrentASR(label)
    setShowASRMenu(false)
    await switchASR(model).catch(() => {})
  }

  if (isRecording) {
    return (
      <div className={styles.recordingBar}>
        <button className={styles.cancelBtn} onClick={cancelRecording}>✕</button>
        <div className={styles.listening}>
          <span className={styles.pulse} />
          <span>Listening...</span>
        </div>
        <button className={styles.sendBtn} onClick={stopAndTranscribe}>↑</button>
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
      {error && <div className={styles.error}>{error}</div>}
      <div className={styles.inputRow}>
        <button className={styles.addBtn} title="Add files">⊕</button>

        <textarea
          className={styles.textInput}
          value={text}
          onChange={e => setText(e.target.value)}
          placeholder="Paste AI response..."
          rows={1}
          onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend() } }}
        />

        <div className={styles.asrWrap}>
          <button className={styles.modelBtn} onClick={() => setShowASRMenu(!showASRMenu)}>
            {currentASR}
          </button>
          {showASRMenu && (
            <div className={styles.asrMenu}>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('auto', 'Auto')}>🔄 Auto</div>
              <div className={styles.asrSep} />
              <div className={styles.asrItem} onClick={() => handleASRSwitch('qwen-us', 'Qwen US')}>🇺🇸 Qwen US</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('qwen-cn', 'Qwen CN')}>🇨🇳 Qwen CN</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('openai', 'Whisper')}>🌐 Whisper</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('siliconflow', 'SenseVoice')}>🇨🇳 SenseVoice</div>
              <div className={styles.asrSep} />
              <div className={styles.asrItem} onClick={() => handleASRSwitch('local', 'Local')}>💻 whisper.cpp</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('local-tiny', 'Local⚡')}>💻 tiny</div>
            </div>
          )}
        </div>

        {text.trim() ? (
          <button className={styles.sendBtn} onClick={handleSend} title="Send">↑</button>
        ) : (
          <button className={styles.micBtn} onClick={startRecording} title="Record voice">🎤</button>
        )}
      </div>
    </div>
  )
}

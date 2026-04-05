import { useState, useRef, useCallback } from 'react'
import { sendVoice, saveText, switchASR, type Message } from '../../api/client'
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

  // Refs for recording state (closures can't see useState updates)
  const recordingRef = useRef(false)
  const streamRef = useRef<MediaStream | null>(null)
  const audioCtxRef = useRef<AudioContext | null>(null)
  const pcmChunks = useRef<Float32Array[]>([])

  const addMessage = (msg: Message) => {
    const fn = (window as any).__voxlog_addMessage
    if (fn) fn(msg)
  }

  const startRecording = useCallback(async () => {
    setError('')
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1,
          sampleRate: 16000,
          echoCancellation: true,
          noiseSuppression: true,
        }
      })

      streamRef.current = stream
      pcmChunks.current = []

      const ctx = new AudioContext({ sampleRate: 16000 })
      audioCtxRef.current = ctx
      const source = ctx.createMediaStreamSource(stream)
      const processor = ctx.createScriptProcessor(4096, 1, 1)

      processor.onaudioprocess = (e: AudioProcessingEvent) => {
        if (recordingRef.current) {
          const data = e.inputBuffer.getChannelData(0)
          pcmChunks.current.push(new Float32Array(data))
        }
      }

      source.connect(processor)
      processor.connect(ctx.destination)

      recordingRef.current = true
      setIsRecording(true)
      console.log('[VoxLog] Recording started')
    } catch (err: any) {
      console.error('[VoxLog] Mic error:', err)
      setError(`Mic error: ${err.message || err}`)
    }
  }, [])

  const stopAndTranscribe = useCallback(async () => {
    console.log('[VoxLog] Stopping recording...')
    recordingRef.current = false
    setIsRecording(false)
    setIsProcessing(true)
    setError('')

    // Stop media
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(t => t.stop())
      streamRef.current = null
    }
    if (audioCtxRef.current) {
      try { await audioCtxRef.current.close() } catch {}
      audioCtxRef.current = null
    }

    // Convert PCM Float32 → Int16 → WAV
    const chunks = pcmChunks.current
    pcmChunks.current = []

    if (chunks.length === 0) {
      setError('No audio captured')
      setIsProcessing(false)
      return
    }

    const totalLen = chunks.reduce((a, c) => a + c.length, 0)
    console.log(`[VoxLog] Audio: ${totalLen} samples = ${(totalLen / 16000).toFixed(1)}s`)

    const pcm16 = new Int16Array(totalLen)
    let offset = 0
    for (const chunk of chunks) {
      for (let i = 0; i < chunk.length; i++) {
        const s = Math.max(-1, Math.min(1, chunk[i]))
        pcm16[offset++] = s < 0 ? s * 0x8000 : s * 0x7FFF
      }
    }

    const wavBlob = int16ToWav(pcm16, 16000)
    console.log(`[VoxLog] WAV: ${wavBlob.size} bytes`)

    try {
      const result = await sendVoice(wavBlob, agent)
      console.log('[VoxLog] Transcribed:', result)
      addMessage(result)
      setError('')
    } catch (err: any) {
      console.error('[VoxLog] Transcribe error:', err)
      setError(`Transcribe failed: ${err.message || err}`)
    }

    setIsProcessing(false)
  }, [agent])

  const cancelRecording = useCallback(() => {
    recordingRef.current = false
    setIsRecording(false)
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(t => t.stop())
      streamRef.current = null
    }
    if (audioCtxRef.current) {
      try { audioCtxRef.current.close() } catch {}
      audioCtxRef.current = null
    }
    pcmChunks.current = []
    console.log('[VoxLog] Recording cancelled')
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

  // === Recording UI ===
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

  // === Normal UI ===
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
              <div className={styles.asrItem} onClick={() => handleASRSwitch('auto', 'Auto')}>🔄 Auto-detect</div>
              <div className={styles.asrSep} />
              <div className={styles.asrItem} onClick={() => handleASRSwitch('qwen-us', 'Qwen US')}>🇺🇸 Qwen ASR (US)</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('qwen-cn', 'Qwen CN')}>🇨🇳 Qwen ASR (CN)</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('openai', 'Whisper')}>🌐 OpenAI Whisper</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('siliconflow', 'SenseVoice')}>🇨🇳 SiliconFlow</div>
              <div className={styles.asrSep} />
              <div className={styles.asrItem} onClick={() => handleASRSwitch('local', 'Local')}>💻 whisper.cpp base</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('local-tiny', 'Local⚡')}>💻 whisper.cpp tiny</div>
              <div className={styles.asrItem} onClick={() => handleASRSwitch('qwen-local', 'Qwen 0.6B')}>🧠 Qwen3 0.6B (local)</div>
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

function int16ToWav(pcm: Int16Array, sampleRate: number): Blob {
  const dataLen = pcm.length * 2
  const buf = new ArrayBuffer(44 + dataLen)
  const v = new DataView(buf)
  const w = (o: number, s: string) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)) }
  w(0, 'RIFF'); v.setUint32(4, 36 + dataLen, true); w(8, 'WAVE'); w(12, 'fmt ')
  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true)
  v.setUint32(24, sampleRate, true); v.setUint32(28, sampleRate * 2, true)
  v.setUint16(32, 2, true); v.setUint16(34, 16, true); w(36, 'data'); v.setUint32(40, dataLen, true)
  for (let i = 0; i < pcm.length; i++) v.setInt16(44 + i * 2, pcm[i], true)
  return new Blob([buf], { type: 'audio/wav' })
}

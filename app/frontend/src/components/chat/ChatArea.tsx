import { useState, useRef, useEffect } from 'react'
import { getHistory, recallMessage, type Message } from '../../api/client'
import styles from './ChatArea.module.css'

interface ChatAreaProps {
  agent: string
  onFileTap: (path: string) => void
}

export function ChatArea({ agent, onFileTap }: ChatAreaProps) {
  const [messages, setMessages] = useState<Message[]>([])
  const [loading, setLoading] = useState(true)
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    setLoading(true)
    getHistory(agent)
      .then(data => { setMessages(data.reverse()); setLoading(false) })
      .catch(() => { setMessages([]); setLoading(false) })
  }, [agent])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages.length])

  // Allow InputBar to push new messages
  useEffect(() => {
    (window as any).__voxlog_addMessage = (msg: Message) => {
      setMessages(prev => [...prev, msg])
    }
  }, [])

  if (loading) return <div className={styles.empty}><span className={styles.emptyHint}>Loading...</span></div>

  if (messages.length === 0) {
    return (
      <div className={styles.empty}>
        <span className={styles.emptyIcon}>🎤</span>
        <p className={styles.emptyTitle}>Your mouth has a save button</p>
        <p className={styles.emptyHint}>Click the mic to start recording</p>
      </div>
    )
  }

  return (
    <div className={styles.chatArea}>
      {messages.map(msg => {
        const text = msg.polished_text || msg.display_text || msg.raw_text
        const isMe = msg.role === 'me'
        const time = msg.created_at?.slice(11, 16) || ''
        const filePaths = (text.match(/[~\/][\/\w.-]+\.(?:md|pdf|png|jpg|txt)/g) || [])

        return (
          <BubbleRow key={msg.id} isMe={isMe}>
            <Bubble
              text={text}
              isMe={isMe}
              time={time}
              latency={msg.latency_ms}
              filePaths={filePaths}
              onFileTap={onFileTap}
              onRecall={() => recallMessage(msg.id).then(ok => {
                if (ok) setMessages(prev => prev.filter(m => m.id !== msg.id))
              })}
              canRecall={Date.now() - new Date(msg.created_at).getTime() < 120000}
            />
          </BubbleRow>
        )
      })}
      <div ref={bottomRef} />
    </div>
  )
}

function BubbleRow({ isMe, children }: { isMe: boolean; children: React.ReactNode }) {
  return (
    <div className={`${styles.bubbleRow} ${isMe ? styles.me : styles.other}`}>
      {isMe && <div className={styles.spacer} />}
      {children}
      {!isMe && <div className={styles.spacer} />}
    </div>
  )
}

function Bubble({ text, isMe, time, latency, filePaths, onFileTap, onRecall, canRecall }: {
  text: string; isMe: boolean; time: string; latency: number
  filePaths: string[]; onFileTap: (p: string) => void
  onRecall: () => void; canRecall: boolean
}) {
  const [hovered, setHovered] = useState(false)
  const [copied, setCopied] = useState(false)

  return (
    <div className={styles.bubbleWrap} onMouseEnter={() => setHovered(true)} onMouseLeave={() => setHovered(false)}>
      <div className={`${styles.bubble} ${isMe ? styles.bubbleMe : styles.bubbleOther}`}>
        <p className={styles.text}>{text}</p>
        {filePaths.map(p => (
          <button key={p} className={styles.fileLink} onClick={() => onFileTap(p)}>📄 {p.split('/').pop()}</button>
        ))}
        {hovered && (
          <div className={styles.actions}>
            <button className={styles.actionBtn} onClick={() => { navigator.clipboard.writeText(text); setCopied(true); setTimeout(() => setCopied(false), 1500) }}>
              {copied ? '✓' : '📋'}
            </button>
            {canRecall && <button className={styles.actionBtn} onClick={onRecall} style={{color:'var(--red)'}}>↩</button>}
          </div>
        )}
      </div>
      <div className={styles.meta}>
        {!isMe && <span>👤</span>}
        <span>{time}</span>
        {latency > 0 && <span>· {latency}ms</span>}
        {isMe && <span>🎤</span>}
      </div>
    </div>
  )
}

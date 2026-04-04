import { useState, useRef, useEffect } from 'react'
import styles from './ChatArea.module.css'

interface Message {
  id: string
  text: string
  time: string
  role: 'me' | 'other'
  latencyMs: number
  createdAt: string
}

interface ChatAreaProps {
  agent: string
  onFileTap: (path: string) => void
}

export function ChatArea({ agent: _agent, onFileTap }: ChatAreaProps) {
  const [messages, _setMessages] = useState<Message[]>([])
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    // TODO: load messages from API
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages.length])

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
      {messages.map(msg => (
        <ChatBubble
          key={msg.id}
          message={msg}
          onFileTap={onFileTap}
        />
      ))}
      <div ref={bottomRef} />
    </div>
  )
}

function ChatBubble({ message, onFileTap }: { message: Message; onFileTap: (p: string) => void }) {
  const [hovered, setHovered] = useState(false)
  const [copied, setCopied] = useState(false)
  const isMe = message.role === 'me'

  // Detect file paths in text
  const filePaths = extractFilePaths(message.text)

  const handleCopy = () => {
    navigator.clipboard.writeText(message.text)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <div
      className={`${styles.bubbleRow} ${isMe ? styles.me : styles.other}`}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {isMe && <div className={styles.spacer} />}

      <div className={styles.bubbleWrap}>
        <div className={`${styles.bubble} ${isMe ? styles.bubbleMe : styles.bubbleOther}`}>
          <p className={styles.text}>{message.text}</p>

          {/* File links */}
          {filePaths.map(path => (
            <button
              key={path}
              className={styles.fileLink}
              onClick={() => onFileTap(path)}
            >
              📄 {path.split('/').pop()}
            </button>
          ))}

          {/* Hover actions */}
          {hovered && (
            <div className={styles.actions}>
              <button className={styles.actionBtn} title="Forward">↗</button>
              <button className={styles.actionBtn} onClick={handleCopy} title="Copy">
                {copied ? '✓' : '📋'}
              </button>
            </div>
          )}
        </div>

        <div className={styles.meta}>
          {!isMe && <span>👤</span>}
          <span>{message.time}</span>
          {message.latencyMs > 0 && <span>· {message.latencyMs}ms</span>}
          {isMe && <span>🎤</span>}
        </div>
      </div>

      {!isMe && <div className={styles.spacer} />}
    </div>
  )
}

function extractFilePaths(text: string): string[] {
  const pattern = /[~\/][\/\w.-]+\.(?:md|pdf|png|jpg|jpeg|txt)/g
  return [...new Set(text.match(pattern) || [])]
}

use std::process::Command;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::Manager;

struct ServerProcess(Mutex<Option<std::process::Child>>);
static RECORDING: AtomicBool = AtomicBool::new(false);

#[tauri::command]
fn start_recording() -> Result<String, String> {
    if RECORDING.load(Ordering::SeqCst) {
        return Err("Already recording".to_string());
    }
    RECORDING.store(true, Ordering::SeqCst);

    // Use Python to record audio via sounddevice
    let home = std::env::var("HOME").unwrap_or_default();
    let venv_python = format!("{}/voxlog/.venv/bin/python", home);
    let python = if std::path::Path::new(&venv_python).exists() { venv_python } else { "python3".to_string() };

    let wav_path = format!("{}/.voxlog2/recording.wav", home);
    std::fs::create_dir_all(format!("{}/.voxlog2", home)).ok();

    // Start recording in background — writes to a temp file
    // The recording will be stopped by stop_recording command
    let script = format!(
        r#"
import sounddevice as sd
import numpy as np
import struct, time, os, signal

RATE = 16000
CHANNELS = 1
wav_path = "{}"
pid_path = wav_path + ".pid"

# Write PID so stop_recording can find us
with open(pid_path, "w") as f:
    f.write(str(os.getpid()))

frames = []
def callback(indata, frame_count, time_info, status):
    frames.append(indata.copy())

with sd.InputStream(samplerate=RATE, channels=CHANNELS, dtype='int16', callback=callback):
    try:
        while True:
            time.sleep(0.1)
    except (KeyboardInterrupt, SystemExit):
        pass

# Write WAV
pcm = np.concatenate(frames) if frames else np.array([], dtype=np.int16)
data = pcm.tobytes()
header = bytearray(44)
header[0:4] = b'RIFF'
struct.pack_into('<I', header, 4, len(data) + 36)
header[8:12] = b'WAVE'
header[12:16] = b'fmt '
struct.pack_into('<I', header, 16, 16)
struct.pack_into('<H', header, 20, 1)
struct.pack_into('<H', header, 22, CHANNELS)
struct.pack_into('<I', header, 24, RATE)
struct.pack_into('<I', header, 28, RATE * CHANNELS * 2)
struct.pack_into('<H', header, 32, CHANNELS * 2)
struct.pack_into('<H', header, 34, 16)
header[36:40] = b'data'
struct.pack_into('<I', header, 40, len(data))
with open(wav_path, 'wb') as f:
    f.write(bytes(header) + data)
os.remove(pid_path)
"#,
        wav_path
    );

    std::thread::spawn(move || {
        let _ = Command::new(&python)
            .args(["-c", &script])
            .spawn();
    });

    // Give it a moment to start
    std::thread::sleep(std::time::Duration::from_millis(300));
    Ok(wav_path)
}

#[tauri::command]
fn stop_recording() -> Result<String, String> {
    RECORDING.store(false, Ordering::SeqCst);

    let home = std::env::var("HOME").unwrap_or_default();
    let pid_path = format!("{}/.voxlog2/recording.wav.pid", home);
    let wav_path = format!("{}/.voxlog2/recording.wav", home);

    // Kill the recording process
    if let Ok(pid_str) = std::fs::read_to_string(&pid_path) {
        if let Ok(pid) = pid_str.trim().parse::<i32>() {
            unsafe { libc::kill(pid, libc::SIGINT); }
            // Wait for WAV to be written
            std::thread::sleep(std::time::Duration::from_millis(500));
        }
    }

    if std::path::Path::new(&wav_path).exists() {
        Ok(wav_path)
    } else {
        Err("No recording found".to_string())
    }
}

#[tauri::command]
fn send_recording_to_api(wav_path: String, agent: String) -> Result<String, String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let venv_python = format!("{}/voxlog/.venv/bin/python", home);
    let python = if std::path::Path::new(&venv_python).exists() { venv_python } else { "python3".to_string() };

    // Use Python to send WAV to API
    let script = format!(
        r#"
import httpx, json
wav_path = "{}"
agent = "{}"
with open(wav_path, 'rb') as f:
    audio = f.read()
resp = httpx.post(
    'http://127.0.0.1:7890/v1/voice',
    headers={{'Authorization': 'Bearer voxlog-dev-token'}},
    files={{'audio': ('recording.wav', audio, 'audio/wav')}},
    data={{'source': 'desktop', 'env': 'auto', 'agent': agent, 'target_app': 'VoxLog V3'}},
    timeout=30.0,
)
print(resp.text)
"#,
        wav_path, agent
    );

    let output = Command::new(&python)
        .args(["-c", &script])
        .current_dir(format!("{}/voxlog", home))
        .env("PYTHONPATH", format!("{}/voxlog", home))
        .output()
        .map_err(|e| format!("Failed to run: {}", e))?;

    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        // Clean up WAV file
        std::fs::remove_file(&wav_path).ok();
        Ok(stdout)
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        Err(format!("API call failed: {}", stderr))
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

            // Auto-start Python backend
            let server_child = start_backend();
            app.manage(ServerProcess(Mutex::new(server_child)));

            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_title("VoxLog V3");
                let _ = window.set_min_size(Some(tauri::LogicalSize::new(500.0, 400.0)));
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![start_recording, stop_recording, send_recording_to_api])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                if let Some(state) = window.try_state::<ServerProcess>() {
                    if let Ok(mut guard) = state.0.lock() {
                        if let Some(ref mut child) = *guard {
                            let _ = child.kill();
                        }
                    }
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn start_backend() -> Option<std::process::Child> {
    if check_health() {
        return None;
    }

    let home = std::env::var("HOME").unwrap_or_default();
    let voxlog_dir = format!("{}/voxlog", home);
    let venv_python = format!("{}/.venv/bin/python", voxlog_dir);
    let python = if std::path::Path::new(&venv_python).exists() { venv_python } else { "python3".to_string() };

    let mut envs: Vec<(String, String)> = Vec::new();
    for env_path in [format!("{}/.voxlog2/.env", home), format!("{}/.voxlog/.env", home)] {
        if let Ok(content) = std::fs::read_to_string(&env_path) {
            for line in content.lines() {
                if let Some((k, v)) = line.split_once('=') {
                    envs.push((k.trim().to_string(), v.trim().to_string()));
                }
            }
            if !envs.is_empty() { break; }
        }
    }

    let mut cmd = Command::new(&python);
    cmd.args(["-m", "uvicorn", "apps.desktop.server:app", "--host", "127.0.0.1", "--port", "7890", "--log-level", "info"])
       .current_dir(&voxlog_dir)
       .env("PYTHONPATH", &voxlog_dir);
    for (k, v) in &envs { cmd.env(k, v); }

    match cmd.spawn() {
        Ok(child) => {
            for _ in 0..15 {
                std::thread::sleep(std::time::Duration::from_millis(500));
                if check_health() { return Some(child); }
            }
            Some(child)
        }
        Err(_) => None,
    }
}

fn check_health() -> bool {
    std::net::TcpStream::connect_timeout(
        &"127.0.0.1:7890".parse().unwrap(),
        std::time::Duration::from_millis(500),
    ).is_ok()
}

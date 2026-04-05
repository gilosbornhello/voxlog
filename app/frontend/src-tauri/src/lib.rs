use std::process::Command;
use std::sync::Mutex;
use tauri::Manager;

struct ServerProcess(Mutex<Option<std::process::Child>>);

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

            // Set window properties
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_title("VoxLog V3");
                let _ = window.set_min_size(Some(tauri::LogicalSize::new(500.0, 400.0)));
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                // Kill backend when app closes
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
    // Check if backend already running
    if check_health() {
        println!("[VoxLog] Backend already running on :7890");
        return None;
    }

    let home = std::env::var("HOME").unwrap_or_default();
    let voxlog_dir = format!("{}/voxlog", home);
    let venv_python = format!("{}/.venv/bin/python", voxlog_dir);

    // Try venv python first, then system python
    let python = if std::path::Path::new(&venv_python).exists() {
        venv_python
    } else {
        "python3".to_string()
    };

    // Source .env
    let env_path = format!("{}/.voxlog2/.env", home);
    let mut envs: Vec<(String, String)> = Vec::new();
    if let Ok(content) = std::fs::read_to_string(&env_path) {
        for line in content.lines() {
            if let Some((k, v)) = line.split_once('=') {
                envs.push((k.trim().to_string(), v.trim().to_string()));
            }
        }
    }

    // Also try ~/.voxlog/.env (v1 compat)
    let env_path_v1 = format!("{}/.voxlog/.env", home);
    if envs.is_empty() {
        if let Ok(content) = std::fs::read_to_string(&env_path_v1) {
            for line in content.lines() {
                if let Some((k, v)) = line.split_once('=') {
                    envs.push((k.trim().to_string(), v.trim().to_string()));
                }
            }
        }
    }

    let mut cmd = Command::new(&python);
    cmd.args(["-m", "uvicorn", "apps.desktop.server:app",
              "--host", "127.0.0.1", "--port", "7890", "--log-level", "info"])
       .current_dir(&voxlog_dir)
       .env("PYTHONPATH", &voxlog_dir);

    for (k, v) in &envs {
        cmd.env(k, v);
    }

    // Redirect output to log
    let log_dir = format!("{}/.voxlog2/logs", home);
    let _ = std::fs::create_dir_all(&log_dir);

    match cmd.spawn() {
        Ok(child) => {
            println!("[VoxLog] Backend started (PID: {})", child.id());

            // Wait for health
            for _ in 0..15 {
                std::thread::sleep(std::time::Duration::from_millis(500));
                if check_health() {
                    println!("[VoxLog] Backend healthy");
                    return Some(child);
                }
            }
            println!("[VoxLog] Backend started but health check timed out");
            Some(child)
        }
        Err(e) => {
            eprintln!("[VoxLog] Failed to start backend: {}", e);
            None
        }
    }
}

fn check_health() -> bool {
    match std::net::TcpStream::connect_timeout(
        &"127.0.0.1:7890".parse().unwrap(),
        std::time::Duration::from_millis(500),
    ) {
        Ok(_) => true,
        Err(_) => false,
    }
}

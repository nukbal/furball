use tauri::Manager;
use std::sync::OnceLock;

// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
mod config;
mod process;

static APP_HANDLE: OnceLock<tauri::AppHandle> = OnceLock::new();

pub fn app_handle<'a>() -> &'a tauri::AppHandle {
  APP_HANDLE.get().unwrap()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .setup(|app| {
      APP_HANDLE.set(app.app_handle().to_owned()).unwrap();

      #[cfg(debug_assertions)]
      {
        let window = app.get_webview_window("main").unwrap();
        window.open_devtools();
      }
      Ok(())
    })
    .plugin(tauri_plugin_shell::init())
    .plugin(tauri_plugin_dialog::init())
    .plugin(tauri_plugin_opener::init())
    .invoke_handler(tauri::generate_handler![
      process::file_meta,
      process::process_files,
    ])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}

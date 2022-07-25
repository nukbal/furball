#![cfg_attr(
  all(not(debug_assertions), target_os = "windows"),
  windows_subsystem = "windows"
)]

use tauri::Manager;

mod process;
mod config;

fn main() {
  ffmpeg::init().unwrap();
  let mut builder = tauri::Builder::default();

  #[cfg(target_os = "windows")] {
    builder = builder.setup(|app| {
      let window = app.get_window("main").unwrap();
      window_shadows::set_shadow(&window, true).expect("Unsupported platform!");
      Ok(())
    });
  }

  #[cfg(target_os = "macos")] {
    builder = builder.menu(tauri::Menu::os_default("furball"));
  }

  builder = builder.setup(|handle| {
    handle.manage(config::init());

    #[cfg(debug_assertions)] {
      let window = handle.get_window("main").unwrap();
      window.open_devtools();
    }

    Ok(())
  });

  builder = builder.invoke_handler(tauri::generate_handler![
    process::file_meta,
    process::process_files,
    config::write_config,
  ]);

  builder.run(tauri::generate_context!())
    .expect("error while running application");
}

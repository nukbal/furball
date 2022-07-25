use serde::{Deserialize, Serialize};
use tauri::{State};
use std::sync::{Arc, Mutex};

#[derive(Serialize, Deserialize, PartialEq, Default, Debug, Clone)]
#[serde(rename_all = "lowercase")]
pub enum ProcessMode {
  Overwrite,
  #[default]
  Path,
}

#[derive(Serialize, Deserialize, PartialEq, Default, Debug, Clone)]
#[serde(rename_all = "lowercase")]
pub enum DirMode {
  #[default]
  None,
  Pdf,
  Zip,
}

#[derive(Serialize, Deserialize, PartialEq, Default, Debug, Clone)]
#[serde(rename_all = "lowercase")]
pub enum GifMode {
  #[default]
  Mp4,
  Webp,
}

#[derive(Serialize, Deserialize, Default, Debug, Clone)]
pub struct Config {
  // general
  pub mode: ProcessMode,
  pub path: String,
  pub suffix: String,

  // images
  pub preserve: bool,
  pub width: f32,
  pub quality: f32,
  pub gif: GifMode,

  // dir
  pub dir_mode: DirMode,
}

pub type ConfigConnect = Arc<Mutex<Config>>;

pub fn init() -> ConfigConnect {
  let config = Config {
    path: tauri::api::path::download_dir().unwrap().to_str().unwrap().to_string(),
    width: 1440.0,
    quality: 88.0,

    ..Default::default()
  };
  Arc::new(Mutex::new(config))
}

#[tauri::command]
pub fn write_config(value: String, state: State<ConfigConnect>) {
  state.lock().unwrap().write(value).expect("failed to write config");
}

impl Config {
  fn write(&mut self, value: String) -> Result<(), String> {
    let config: Config = serde_json::from_str(&value).unwrap();
    self.mode = config.mode;
    self.path = config.path;
    self.suffix = config.suffix;
    self.preserve = config.preserve;
    self.width = config.width;
    self.quality = config.quality;
    self.gif = config.gif;
    self.dir_mode = config.dir_mode;

    let cache_path = tauri::api::path::local_data_dir().unwrap().join(".doujin_conf.json");
    std::fs::write(cache_path, value).expect("failed to write config");

    Ok(())
  }
}

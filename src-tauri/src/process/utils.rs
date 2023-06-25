use std::path::{Path, PathBuf};

use super::inspect::FileMeta;

pub fn get_cache_dir() -> Result<PathBuf, String> {
  let cache_dir = tauri::api::path::cache_dir().unwrap().join("com.nukbal.furball");
  let is_exists = Path::new(&cache_dir).is_dir();
  if !is_exists {
    match std::fs::create_dir(cache_dir.clone()) {
      Err(err) => return Err(format!("failed to create cache dir: {:?}", err).to_string()),
      _ => (),
    }
  }
  Ok(cache_dir)
}

pub fn is_dir_only_image(files: Vec<FileMeta>) -> bool {
  let mut result = true;

  for file in files {
    if file.is_dir {
      result = false;
      break;
    }
    if file.mime_type.starts_with("image") == false {
      result = false;
      break;
    }
  }

  result
}

pub fn is_dir_only_media(files: Vec<FileMeta>) -> bool {
  let mut result = true;

  for file in files {
    if file.is_dir {
      result = false;
      break;
    }
    if file.mime_type.starts_with("image") == false
      && file.mime_type.starts_with("video") == false {
      result = false;
      break;
    }
  }

  result
}

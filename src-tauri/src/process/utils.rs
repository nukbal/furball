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

pub fn is_dir_only_image(files: &Vec<FileMeta>) -> bool {
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

pub fn get_file_type(path: &Path) -> Option<String> {
  let Ok(infer_type) = infer::get_from_path(path) else {
    return None;
  };

  let Some(file_type) = infer_type else {
    if path.extension().unwrap_or_default() == "tga" {
      return Some("image/x-tga".to_owned());
    } else {
      return None;
    }
  };

  let mime_type = file_type.mime_type();
  if 
    (mime_type.starts_with("image") && mime_type != "image/vnd.adobe.photoshop")
    || mime_type.starts_with("video")
    // || file_type.mime_type() == "application/vnd.rar"
    || mime_type == "application/zip"
    || mime_type == "application/pdf"
  {
    return Some(mime_type.to_owned());
  }

  None
}

use super::images::thumbnail_from_buf;

pub fn thumbnail(file_path: String) -> Result<String, String> {
  let out_path = tauri::api::path::cache_dir().unwrap().join("__furball_video_thumb.png");

  let _output = match tauri::api::process::Command::new_sidecar("ffmpeg").unwrap()
    .args([
      "-i",
      &file_path,
      "-vframes",
      "1",
      out_path.to_str().unwrap(),
    ]).output() {
      Ok(out) => out,
      Err(err) => return Err(format!("Error executing FFmpeg. \n{:?}", err).to_string()),
    };

  let thumb = image::open(&out_path).unwrap();
  let b64 = thumbnail_from_buf(thumb.to_rgb8().to_vec(), thumb.width(), thumb.height())?;

  std::fs::remove_file(out_path).unwrap();

  Ok(b64)
}


#[derive(Debug, Clone)]
pub struct VideoConfig {
  pub path: String,
  pub suffix: String,
  pub base_path: String,
  pub quality: f32,
  pub overwrite: bool,
}

pub fn compress(config: VideoConfig) -> Result<(), String> {
  Ok(())
}

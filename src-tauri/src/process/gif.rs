use std::path::Path;

use nanoid::nanoid;

use crate::config::{Config, GifMode};

pub fn convert(file_path: String, config: Config) -> Result<(), String> {
  let dir_path = super::videos::frames(file_path.clone())?;

  let job_id = nanoid!(15, &nanoid::alphabet::SAFE);
  let from_path = dir_path.clone();
  let from_path_no_ext = from_path.with_extension("");
  let filename = from_path_no_ext.file_name().unwrap().to_str().unwrap();
  let out_path = super::utils::get_cache_dir().unwrap().join(job_id);

  if out_path.is_dir() {
    std::fs::remove_dir_all(&out_path).expect("unable to pre-clear output path");
  } else if out_path.is_file() {
    std::fs::remove_file(&out_path).expect("unable to pre-clear output path");
  }

  std::fs::create_dir(&out_path).expect("unable to create output dir");

  let output = match tauri::api::process::Command::new_sidecar("realesrgan")
    .expect("failed to create `realesrgan` binary command")
    .args(["-i", &from_path.to_str().unwrap(), "-o", &out_path.to_str().unwrap(), "-n", "realesr-animevideov3", "-s", "4"])
    .output() {
      Ok(out) => out,
      Err(err) => return Err(format!("Error executing RealESRGAN Upscaler. \n{:?}", err).to_string()),
    };

  let generated = std::fs::read_dir(&out_path).expect("unable to read output dir");
  if generated.count() == 0 {
    return Err(format!("file does not generated: {:?}", output).to_string());
  }

  let base_path = Path::new(&config.path);
  let target_ext = match config.gif {
    GifMode::Gif => "gif",
    GifMode::Mp4 => "mp4",
    GifMode::Webp => "webp",
  };
  let target_path = base_path.join(format!("out_{}.{}", filename, target_ext));

  let _vid_out = match tauri::api::process::Command::new_sidecar("ffmpeg")
    .expect("failed to create `ffmpeg` binary command")
    .args([
      "-i", out_path.clone().join("frame-%d.png").to_str().unwrap(),
      target_path.to_str().unwrap(),
    ])
    .output() {
      Ok(out) => out,
      Err(err) => return Err(format!("Error executing FFmpeg. \n{:?}", err).to_string()),
    };

  std::fs::remove_dir_all(dir_path).expect("failed to clean cache after converting gif");
  std::fs::remove_dir_all(out_path).expect("failed to clean cache after converting gif");

  Ok(())
}

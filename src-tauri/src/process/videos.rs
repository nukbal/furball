use std::path::{Path, PathBuf};

use crate::config::Config;
use super::images::thumbnail_from_buf;
use super::external::{ffmpeg, upsacler};

pub fn thumbnail(file_path: &String) -> Result<String, String> {

  let Ok(out) = std::process::Command::from(ffmpeg()?)
    .args([
      "-i", file_path,
      "-f", "image2pipe",
      "-pix_fmt", "rgb24",
      "-an", "-sn", "-nostats",
      "-vframes", "1",
      "-"
    ])
    .output() else {
      return Err("error to process video".to_owned());
    };

  let thumb = super::images::open_buffer(&out.stdout).unwrap();
  let b64 = thumbnail_from_buf(thumb.to_rgb8().to_vec(), thumb.width(), thumb.height())?;

  Ok(b64)
}

pub fn frames(file_path: String) -> Result<PathBuf, String> {
  let input_path = Path::new(&file_path);
  let filename = input_path.file_name().unwrap();
  let out_path = super::utils::get_cache_dir().unwrap().join(filename);

  if out_path.is_dir() {
    std::fs::remove_dir_all(&out_path).expect("unable to pre-clear output path");
  } else if out_path.is_file() {
    std::fs::remove_file(&out_path).expect("unable to pre-clear output path");
  }
  std::fs::create_dir(&out_path).expect("unable to create dir");

  let _output = match ffmpeg()?
    .args(["-i", &file_path, "-vsync", "0", out_path.clone().join("frame-%d.jpg").to_str().unwrap()])
    .output() {
      Ok(out) => out,
      Err(err) => return Err(format!("Error executing FFmpeg. \n{:?}", err).to_string()),
    };

  Ok(out_path)
}

pub fn upscale(file_path: String, config: Config) -> Result<(), String> {
  let dir_path = frames(file_path.clone())?;
  let from_path = dir_path.clone();
  let filename = from_path.file_name().unwrap().to_str().unwrap();
  let out_path = super::utils::get_cache_dir().unwrap().join(format!("out_{}", filename));

  let output = match upsacler()?
    .args([
      "-i", &from_path.to_str().unwrap(),
      "-o", &from_path.to_str().unwrap(),
      "-n", "realesr-animevideov3",
      "-s", "2",
      "-f", "jpg",
    ])
    .output() {
      Ok(out) => out,
      Err(err) => return Err(format!("Error executing RealESRGAN Upscaler. \n{:?}", err).to_string()),
    };

  if !out_path.is_file() {
    println!("file does not generated: {:?}", output);
    std::fs::remove_dir_all(dir_path).expect("failed to clean cache after converting video");
    return Err(format!("file does not generated: {:?}", output).to_string());
  }

  let _output = match ffmpeg()?
    .args([
      "-i", dir_path.clone().join("frame-%d.jpg").to_str().unwrap(),
      "-i", &file_path,
      "-map 0:v:0 -map 1:a:0 -c:a copy -c:v libx264 -r 23.98 -pix_fmt yuv420p",
      "-o", &config.path,
    ])
    .output() {
      Ok(out) => out,
      Err(err) => {
        std::fs::remove_dir_all(dir_path).expect("failed to clean cache after converting video");
        return Err(format!("Error executing FFmpeg. \n{:?}", err).to_string());
      },
    };
  
  std::fs::remove_dir_all(dir_path).expect("failed to clean cache after converting video");
  Ok(())
}

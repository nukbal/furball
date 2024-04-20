use tauri::api::process::Command;

pub fn upsacler() -> Result<Command, String> {
  match Command::new_sidecar("realesrgan") {
    Ok(cmd) => Ok(cmd),
    _ => return Err("failed to create `realesrgan` binary command".to_owned()),
  }
}


pub fn ffmpeg() -> Result<Command, String> {
  match Command::new_sidecar("ffmpeg") {
    Ok(cmd) => Ok(cmd),
    _ => return Err("failed to create `ffmpeg` binary command".to_owned()),
  }
}

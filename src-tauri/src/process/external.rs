use std::ffi::OsStr;

use tauri_plugin_shell::ShellExt;
use tauri_plugin_shell::process::Output;

pub async fn upsacler<I, S>(args: I) -> Result<Output, String> where
  I: IntoIterator<Item = S>,
  S: AsRef<OsStr>,
{
  let app = crate::app_handle();
  let Ok(cmd) = app.shell().sidecar("realesrgan") else {
    return Err("failed to create `realesrgan` binary command".to_string());
  };
  let out = cmd.args(args).output().await;
  match out {
    Ok(out) => Ok(out),
    Err(e) => Err(format!("{:?}", e).to_string()),
  }
}

pub async fn ffmpeg<I, S>(args: I) -> Result<Output, String> where
I: IntoIterator<Item = S>,
S: AsRef<OsStr>,
{
  let app = crate::app_handle();
  let Ok(cmd) = app.shell().sidecar("ffmpeg") else {
    return Err("failed to create `ffmpeg` binary command".to_string());
  };
  let out = cmd.args(args).output().await;
  match out {
    Ok(out) => Ok(out),
    Err(e) => Err(format!("{:?}", e).to_string()),
  }
}

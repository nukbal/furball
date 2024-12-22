use images::ImageConfig;
use std::path::Path;

mod bundle;
mod external;
mod gif;
mod images;
mod inspect;
mod utils;
mod videos;

use crate::config::{Config, DirMode, ProcessMode};

#[tauri::command]
pub async fn process_files(
  filenames: Vec<String>,
  conf: Config,
) -> Result<(), String> {
  let mut handles = vec![];

  for filename in filenames {
    let Ok(meta) = inspect::inspect_file(filename.clone(), false).await else {
      continue;
    };
    let cfg = conf.clone();

    match meta.mime_type.as_str() {
      "dir" => {
        let files = meta
          .files
          .iter()
          .map(|item| item.path.clone())
          .collect::<Vec<String>>();

        if utils::is_dir_only_image(&meta.files) {
          match cfg.dir_mode {
            DirMode::Pdf => {
              handles.push(tauri::async_runtime::spawn(async move {
                let path = Path::new(&meta.path);
                bundle::to_pdf(path, files, &cfg).await
              }));
              continue;
            }
            DirMode::Zip => {
              handles.push(tauri::async_runtime::spawn(async move {
                let path = Path::new(&meta.path);
                bundle::zip(path, files, &cfg).await
              }));
              continue;
            }
            _ => (),
          }
        }

        for nest_file in meta.files {
          let c = cfg.clone();
          if !nest_file.is_dir && nest_file.files.len() == 0 {
            handles.push(tauri::async_runtime::spawn(async move {
              let nest_path = Path::new(&nest_file.path);
              process_file(&nest_path, c).await
            }));
          } else {
            for d_nest in nest_file.files {
              // igrnoe tripple nested directory
              if d_nest.is_dir {
                continue;
              }
              let cc = c.clone();
              handles.push(tauri::async_runtime::spawn(async move {
                let cur_path = Path::new(&d_nest.path);
                process_file(&cur_path, cc).await
              }));
            }
          }
        }
      }
      "application/zip" => {
        let zip_path = Path::new(&filename).to_path_buf();
        handles.push(tauri::async_runtime::spawn(async move {
          let path = Path::new(&meta.path);
          bundle::zip_to(path, zip_path, &cfg).await
        }));
      }
      "application/pdf" => {
        handles.push(tauri::async_runtime::spawn(async move {
          let file_path = Path::new(&filename);
          bundle::optimize_pdf(file_path, cfg).await
        }));
      },
      _ => {
        handles.push(tauri::async_runtime::spawn(async move {
          let file_path = Path::new(&filename);
          process_file(file_path, cfg).await
        }))
      }
    }
  }

  let futures = futures::future::join_all(handles).await;

  for fut in futures {
    match fut {
      Ok(_) => continue,
      Err(e) => {
        return Err(e.to_string());
      }
    }
  }

  Ok(())
}

async fn process_file(path: &Path, config: Config) -> Result<(), String> {
  let path_str = path.to_str().unwrap().to_string();

  let Some(mime_type) = utils::get_file_type(&path) else {
    return Err(format!("file {:?} is not supported", path).to_string());
  };

  if mime_type.starts_with("image") && !mime_type.contains("gif") {
    images::optimize_and_save(ImageConfig {
      path: path_str,
      base_path: config.path,
      quality: config.quality,
      suffix: config.suffix,
      width: config.width,
      mode: config.image_mode,
      overwrite: config.mode == ProcessMode::Overwrite,
      ai: config.ai,
    }).await?;
    return Ok(());
  }

  if mime_type.contains("gif") {
    let conf = config.clone();
    gif::convert(path_str, conf).await?;
    return Ok(());
  }

  if mime_type.starts_with("video") {
    let conf = config.clone();
    videos::upscale(path_str, conf).await?;
    return Ok(());
  }

  Err("error on processing".to_string())
}

#[tauri::command]
pub async fn file_meta(paths: Vec<String>) -> Result<String, String> {
  inspect::file_meta(paths).await
}

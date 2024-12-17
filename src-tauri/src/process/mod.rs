use images::ImageConfig;
use std::path::Path;
use tokio::task::JoinHandle;

mod images;
mod gif;
mod videos;
mod inspect;
mod bundle;
mod utils;
mod external;

use crate::config::{Config, ProcessMode, DirMode};

#[tauri::command]
pub async fn process_files(filenames: Vec<String>, conf: Config, window: tauri::Window) -> Result<(), String> {
  let mut handles = vec![];

  for filename in filenames {
    let Ok(meta) = inspect::inspect_file(filename.clone(), false) else {
      continue;
    };
    let cfg = conf.clone();
    let win = window.clone();

    match meta.mime_type.as_str() {
      "dir" => {
        let files = meta.files.iter().map(|item| item.path.clone()).collect::<Vec<String>>();

        if utils::is_dir_only_image(&meta.files) {
          match cfg.dir_mode {
            DirMode::Pdf => {
              handles.push(tokio::spawn(async move {
                let path = Path::new(&meta.path);
                bundle::to_pdf(path, files, &cfg, &win).await
              }));
              continue;
            },
            DirMode::Zip => {
              handles.push(tokio::spawn(async move {
                let path = Path::new(&meta.path);
                bundle::zip(path, files, &cfg).await
              }));
              continue;
            },
            _ => (),
          }
        }

        for nest_file in meta.files {
          let c = cfg.clone();
          let nest_path = Path::new(&nest_file.path);
          if !nest_file.is_dir && nest_file.files.len() == 0 {
            let Ok(handle) = process_file(&nest_path, c, &win) else {
              continue;
            };
            handles.push(handle);
          } else {
            for d_nest in nest_file.files {
              // igrnoe tripple nested directory
              if d_nest.is_dir {
                continue;
              }
              let cc = c.clone();
              let cur_path = Path::new(&d_nest.path);
              let Ok(handle) = process_file(&cur_path, cc, &win) else {
                continue;
              };
              handles.push(handle);
            }
          }
        }
      },
      "application/zip" => {
        let zip_path = Path::new(&filename).to_path_buf();
        handles.push(tokio::spawn(async move {
          let path = Path::new(&meta.path);
          bundle::zip_to(path, zip_path, &cfg, &win).await
        }));
      },
      _ => {
        let path = Path::new(&meta.path);
        match process_file(path, cfg, &win) {
          Ok(handle) => handles.push(handle),
          Err(_err) => continue,
        }
      },
    }
  }

  let futures = futures::future::join_all(handles).await;

  for fut in futures {
    match fut {
      Ok(_) => continue,
      Err(e) => {
        return Err(e.to_string());
      },
    }
  }

  Ok(())
}

fn process_file(path: &Path, config: Config, window: &tauri::Window) -> Result<JoinHandle<Result<(), String>>, String> {
  let path_str = path.to_str().unwrap().to_string();

  let Some(mime_type) = utils::get_file_type(&path) else {
    return Err(format!("file {:?} is not supported", path).to_string());
  };

  if mime_type.starts_with("image") && !mime_type.contains("gif") {
    return Ok(tokio::spawn(async move {
      images::optimize_and_save(ImageConfig {
        path: path_str,
        base_path: config.path,
        quality: config.quality,
        suffix: config.suffix,
        width: config.width,
        mode: config.image_mode,
        overwrite: config.mode == ProcessMode::Overwrite,
        ai: config.ai,
      })
    }));
  }

  if mime_type.contains("gif") {
    let conf = config.clone();
    return Ok(tokio::spawn(async move {
      gif::convert(path_str, conf)
    }));
  }

  if mime_type.starts_with("video") {
    let conf = config.clone();
    return Ok(tokio::spawn(async move {
      videos::upscale(path_str, conf)
    }));
  }

  if mime_type == "application/pdf" {
    let conf = config.clone();
    let file_path = path_str.clone();
    let win = window.clone();

    return Ok(tokio::spawn(async move {
      let path = Path::new(&file_path);
      bundle::optimize_pdf(path, conf, &win).await
    }));
  }

  Err("error on processing".to_string())
}

#[tauri::command]
pub async fn file_meta(paths: Vec<String>) -> Result<String, String> {
  inspect::file_meta(paths).await
}

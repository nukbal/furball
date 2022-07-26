use tauri::State;
use images::ImageConfig;
use std::path::Path;
use tokio::task::JoinHandle;

mod images;
mod videos;
mod inspect;
mod bundle;
mod utils;

use crate::config::{Config, ConfigConnect};
use crate::config::{ProcessMode, DirMode};

#[tauri::command]
pub async fn process_files(filenames: Vec<String>, state: State<'_, ConfigConnect>) -> Result<(), String> {
  let mut handles = vec![];

  for filename in filenames {
    let meta = inspect::inspect_file(filename.clone(), false).unwrap();
    
    match meta.mime_type.as_str() {
      "dir" => {
        let dir_conf = state.inner().lock().unwrap().clone();
        let files = meta.files.iter().map(|item| item.path.clone()).collect::<Vec<String>>();

        if dir_conf.dir_mode == DirMode::Pdf && utils::is_dir_only_image(meta.files.clone()) {
          handles.push(tokio::spawn(async move {
            let path = Path::new(&meta.path);
            bundle::to_pdf(path, files, dir_conf).await;
            Ok(())
          }));
          continue;
        }

        if dir_conf.dir_mode == DirMode::Zip && utils::is_dir_only_media(meta.files.clone()) {
          handles.push(tokio::spawn(async move {
            let path = Path::new(&meta.path);
            bundle::zip(path, files, dir_conf).await
          }));
          continue;
        }

        for nest_file in meta.files {
          let nest_path = Path::new(&nest_file.path);
          if !nest_file.is_dir && nest_file.files.len() == 0 {
            match process_file(&nest_path, state.inner().lock().unwrap().clone()) {
              Ok(handle) => handles.push(handle),
              Err(_err) => continue,
            }
          } else {
            for d_nest in nest_file.files {
              // igrnoe tripple nested directory
              if d_nest.is_dir {
                continue;
              }
              let cur_path = Path::new(&d_nest.path);
              match process_file(&cur_path, state.inner().lock().unwrap().clone()) {
                Ok(handle) => handles.push(handle),
                Err(_err) => continue,
              }
            }
          }
        }
      },
      _ => {
        let path = Path::new(&meta.path);
        match process_file(path, state.inner().lock().unwrap().clone()) {
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

fn process_file(path: &Path, config: Config) -> Result<JoinHandle<Result<(), String>>, String> {
  let path_str = path.to_str().unwrap().to_string();
  match infer::get_from_path(&path) {
    Ok(nest_infer) => match nest_infer {
      Some(file) if file.mime_type().starts_with("image") => {
        Ok(tokio::spawn(async move {
          images::optimize_and_save(ImageConfig {
            path: path_str,
            base_path: config.path,
            quality: config.quality,
            suffix: config.suffix,
            width: if config.preserve { 0.0 } else { config.width },
            overwrite: config.mode == ProcessMode::Overwrite,
          })
        }))
      },
      Some(file) if file.mime_type().starts_with("video") => {
        Ok(tokio::spawn(async move {
          // videos::compress(path_str);
          Ok(())
        }))
      },
      _ => return Err("file is not supported".to_string()),
    },
    Err(_err) => return Err("error on processing".to_string()),
  }
}

#[tauri::command]
pub async fn file_meta(paths: Vec<String>) -> Result<String, String> {
  match inspect::file_meta(paths).await {
    Ok(buf) => Ok(buf),
    Err(_) => Err("failed to inspect".to_string()),
  }
}

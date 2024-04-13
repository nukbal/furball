use serde::{Deserialize, Serialize};
use std::{io::Read, path::Path};

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
pub struct FileMeta {
  pub path: String,
  filename: String,
  pub is_dir: bool,
  pub mime_type: String,
  thumbnail: Option<String>,
  pub files: Vec<FileMeta>,
  size: u64,
}

pub async fn file_meta(paths: Vec<String>) -> Result<String, String> {
  let mut handles = vec![];

  for path in paths {
    handles.push(tokio::spawn(async move {
      inspect_file(path, true)
    }));
  }

  let res = futures::future::join_all(handles).await;
  let mut result = vec![];

  for handle in res {
    match handle {
      Ok(val) => match val {
        Ok(file) => if file.mime_type != "" { result.push(file); },
        Err(e) => { return Err(e.to_string()); },
      },
      Err(e) => { return Err(e.to_string()); },
    }
  }

  Ok(serde_json::to_string(&result).unwrap())
}

pub fn inspect_file(path: String, thunbnail_requierd: bool) -> Result<FileMeta, String> {
  let meta = std::fs::metadata(&path).unwrap();
  let p = std::path::Path::new(&path);
  let filename = p.file_name().unwrap().to_string_lossy().to_string();

  let mime_type = if meta.is_dir() {
    "dir".to_string()
  } else {
    let Some(kind) = get_file_type(&p) else {
      return Err("unknown type".to_string());
    };
    kind.mime_type().to_string()
  };

  let mut file = FileMeta {
    path: path.clone(),
    filename,
    mime_type,
    is_dir: meta.is_dir(),
    size: meta.len(),
    ..Default::default()
  };
  
  match file.mime_type.as_str() {
    x if x.starts_with("image") => {
      if thunbnail_requierd {
        let str = crate::process::images::thumbnail(&file.path)?;
        file.thumbnail = Some(str);
      }
    },
    x if x.starts_with("video") => {
      if thunbnail_requierd {
        let str = crate::process::videos::thumbnail(&file.path)?;
        file.thumbnail = Some(str);
      }
    },
    // x if x == "application/vnd.rar" || x == "application/zip" => {},
    x if x == "application/pdf" => {
      if thunbnail_requierd {
        let str = crate::process::bundle::thumbnail_pdf(&file.path)?;
        file.thumbnail = Some(str);
      }
    },
    x if x == "application/zip" => {
      let zip_file = std::fs::File::open(&file.path).unwrap();
      let mut archive = zip::ZipArchive::new(zip_file).unwrap();

      file.is_dir = true;

      for i in 0..archive.len() {
        let f = archive.by_index(i).unwrap();
        if f.is_dir() { continue; }

        let name = match f.enclosed_name() {
          Some(n) => n.to_owned(),
          _ => continue,
        };

        let mut fpath = file.path.clone();
        let filename = name.display().to_string();

        fpath.push_str(&filename);
    
        file.files.push(FileMeta {
          path: fpath,
          filename: filename,
          size: f.size(),
          ..Default::default()
        });
      }

      file.files.sort_by(|a, b| {
        if a.is_dir && !b.is_dir {
          return std::cmp::Ordering::Less;
        }
        if b.is_dir && !a.is_dir {
          return std::cmp::Ordering::Greater;
        }
        alphanumeric_sort::compare_path(&a.path, &b.path)
      });
    
      if thunbnail_requierd {
        let mut img_buf: Vec<u8> = vec![];
        let mut f = archive.by_name(file.files[0].filename.as_str()).unwrap();

        f.read_to_end(&mut img_buf).unwrap();

        if let Ok(img) = image::load_from_memory(&img_buf) {
          let width = img.width();
          let height = img.height();
          let buf = img.into_rgb8().into_vec();

          if let Ok(b64) = super::images::thumbnail_from_buf(buf, width, height) {
            file.thumbnail = Some(b64);
          }
        }
      }
    },
    "dir" => {
      let dir_paths = std::fs::read_dir(&file.path).unwrap();
      for file_path in dir_paths {
        let nest_path = file_path.as_ref().unwrap().path();

        if (nest_path.is_dir() && thunbnail_requierd) || get_file_type(nest_path.as_path()).is_some() {
          let nested_file = inspect_file(nest_path.to_str().unwrap().to_string(), false).unwrap();
          if nested_file.mime_type != "" {
            file.files.push(nested_file);
          }
        }
      }
      file.files.sort_by(|a, b| {
        if a.is_dir && !b.is_dir {
          return std::cmp::Ordering::Less;
        }
        if b.is_dir && !a.is_dir {
          return std::cmp::Ordering::Greater;
        }
        alphanumeric_sort::compare_path(&a.path, &b.path)
      });
  
      if file.files.len() > 0 && file.files[0].is_dir == false && thunbnail_requierd {
        let first_path = p.join(&file.files[0].path);
        let first_kind = infer::get_from_path(&first_path)
          .expect("file read successfully")
          .expect("file type is unknown");
  
        file.thumbnail = generate_thumbnail(
          &first_path.to_str().unwrap().to_string(),
          first_kind.mime_type(),
        ).unwrap();
      }
      // exclude empty dir
      if file.files.len() == 0 {
        file.mime_type = "".to_string();
      }
    },
    _ => (),
  }

  Ok(file)
}

fn get_file_type(path: &Path) -> Option<infer::Type> {
  match infer::get_from_path(path) {
    Ok(infer_type) => match infer_type {
      Some(file_type) if (
        (file_type.mime_type().starts_with("image") && file_type.mime_type() != "image/vnd.adobe.photoshop")
        || file_type.mime_type().starts_with("video")
        // || file_type.mime_type() == "application/vnd.rar"
        || file_type.mime_type() == "application/zip"
        || file_type.mime_type() == "application/pdf"
      ) => Some(file_type),
      _ => None,
    },
    Err(_) => None,
  }
}

fn generate_thumbnail(path: &String, mime: &str) -> Result<Option<String>, String> {
  let mut data: Option<String> = None;
  if mime.starts_with("image") {
    let str = crate::process::images::thumbnail(path)?;
    data = Some(str);
  } else if mime.starts_with("video") {
    let str = crate::process::videos::thumbnail(path)?;
    data = Some(str);
  }

  Ok(data)
}

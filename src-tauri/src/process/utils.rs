use super::inspect::FileMeta;

pub fn is_dir_only_image(files: Vec<FileMeta>) -> bool {
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

pub fn is_dir_only_media(files: Vec<FileMeta>) -> bool {
  let mut result = true;

  for file in files {
    if file.is_dir {
      result = false;
      break;
    }
    if file.mime_type.starts_with("image") == false
      && file.mime_type.starts_with("video") == false {
      result = false;
      break;
    }
  }

  result
}

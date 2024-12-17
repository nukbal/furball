use std::{fs::File, io::{BufReader, BufWriter, Read, Write}, path::Path};
use std::path::PathBuf;
use std::string::String;
use printpdf::{
  PdfDocument, ImageXObject, Image, Px, ColorSpace, ColorBits, ImageFilter,
  ImageTransform,
};
use pdf::file::FileOptions;
use pdf::object::*;

use super::images::{ImageConfig, optimize_image, optimize_image_buf};
use crate::config::{Config, ProcessMode};

pub async fn zip(dir_path: &Path, files: Vec<String>, config: &Config) -> Result<(), String> {
  let mut handles = vec![];

  for file_name in files {
    let conf = config.clone();
    handles.push(tokio::spawn(async move {
      let path = Path::new(&file_name);
      let name = path.file_name().unwrap().to_str().unwrap();
  
      match infer::get_from_path(&path) {
        Ok(inter_type) => match inter_type {
          Some(file) if file.mime_type().starts_with("image") => {
            let (buf, _, _) = optimize_image(&ImageConfig {
              path: file_name.clone(),
              base_path: conf.path,
              overwrite: conf.mode == ProcessMode::Overwrite,
              quality: conf.quality,
              suffix: conf.suffix,
              width: conf.width,
              mode: conf.image_mode,
              ai: conf.ai,
            }).unwrap();
  
            Some((buf, name.to_string()))
          },
          Some(file) if file.mime_type().starts_with("video") => {
            // TODO: add video compression
            let f = BufReader::new(File::open(&path).unwrap());
            Some((f.buffer().to_vec(), name.to_string()))
          },
          _ => None,
        },
        Err(_) => None,
      }
    }));
  }

  let mut buffers = vec![];
  for buf in futures::future::join_all(handles).await {
    let val = buf.unwrap();
    if val.is_some() {
      buffers.push(val.unwrap());
    }
  }

  let dir_name = dir_path.file_name().unwrap().to_str().unwrap().to_string();
  let file_path = match config.mode {
    ProcessMode::Overwrite => dir_path.with_extension("zip"),
    ProcessMode::Path => Path::new(&config.path).join(format!("{}.zip", dir_name)),
  };
  let file = File::create(&file_path).unwrap();
  let mut zip = zip::ZipWriter::new(file);
  for (buf, name) in buffers {
    zip.start_file(name.clone(), Default::default())
      .expect(&format!("start_file: {}", name));
    zip.write_all(&buf)
      .expect(&format!("write_all: {}", name));
  }

  zip.finish().expect("unable to zip");
  Ok(())
}

fn save_to_pdf(name: String, file_path: PathBuf, buffers: Vec<(Vec<u8>, u32, u32)>) -> Result<(), String> {
  let doc = PdfDocument::empty(name.as_str());

  for (buf, width, height) in buffers {
    let (page, layer) = doc.add_page(
      Px(width as usize).into_pt(300.0).into(),
      Px(height as usize).into_pt(300.0).into(),
      "",
    );

    let image = Image::from(ImageXObject {
      width: Px(width as usize),
      height: Px(height as usize),
      color_space: ColorSpace::Rgb,
      bits_per_component: ColorBits::Bit8,
      interpolate: false,
      image_data: buf,
      image_filter: Some(ImageFilter::DCT),
      clipping_bbox: None,
      smask: None,
    });

    image.add_to_layer(doc.get_page(page).get_layer(layer), ImageTransform {
      ..Default::default()
    });
  }

  doc.save(&mut BufWriter::new(File::create(&file_path).unwrap())).unwrap();
  Ok(())
}

pub async fn to_pdf(dir_path: &Path, files: Vec<String>, config: &Config, window: &tauri::Window) -> Result<(), String> {
  let dir_name = dir_path.file_name().unwrap().to_str().unwrap().to_string();

  let mut handles = vec![];

  for file_name in files {
    let conf = config.clone();
    let win = window.clone();
    handles.push(tokio::spawn(async move {
      let img = optimize_image(&ImageConfig {
        path: file_name,
        base_path: conf.path.clone(),
        overwrite: conf.mode == ProcessMode::Overwrite,
        quality: conf.quality,
        suffix: conf.suffix.clone(),
        width: conf.width,
        mode: conf.image_mode,
        ai: conf.ai,
      }).unwrap();
      win.emit("progress", "done").unwrap();
      img
    }));
  }

  let mut buffers = vec![];
  for buf in futures::future::join_all(handles).await {
    buffers.push(buf.unwrap());
  }

  let file_path = match config.mode {
    ProcessMode::Overwrite => dir_path.with_extension("pdf"),
    ProcessMode::Path => Path::new(&config.path).join(format!("{}.pdf", dir_name)),
  };

  save_to_pdf(dir_name, file_path, buffers)
}

pub async fn zip_to(dir_path: &Path, file_path: PathBuf, config: &Config, window: &tauri::Window) -> Result<(), String> {
  let dir_name = dir_path.with_extension("").file_name().unwrap().to_str().unwrap().to_string();
  let file = std::fs::File::open(&file_path).unwrap();

  let mut archive = zip::ZipArchive::new(file).unwrap();
  let mut handles = vec![];
  let mut images: Vec<(String, Vec<u8>)> = vec![];

  for i in 0..archive.len() {
    let mut f = archive.by_index(i).unwrap();
    if f.is_dir() { continue; }

    let mut buf = vec![];
    f.read_to_end(&mut buf).unwrap();
    if !infer::is_image(&buf) { continue; }

    images.push((f.name().to_owned(), buf));
  }

  images.sort_by(|(a, _), (b, _)| {
    alphanumeric_sort::compare_str(a.clone(), b.clone())
  });

  for (_, buf) in images {
    let conf = config.clone();
    let win = window.clone();

    handles.push(tokio::spawn(async move {
      let img = super::images::optimize_image_buf(buf, &ImageConfig {
        path: "".to_string(),
        base_path: conf.path.clone(),
        overwrite: conf.mode == ProcessMode::Overwrite,
        quality: conf.quality,
        suffix: conf.suffix.clone(),
        width: conf.width,
        mode: conf.image_mode,
        ai: conf.ai,
      }).unwrap();
      win.emit("progress", "done").unwrap();
      img
    }));
  }

  let mut buffers = vec![];
  for buf in futures::future::join_all(handles).await {
    buffers.push(buf.unwrap());
  }

  let target_path = match config.mode {
    ProcessMode::Overwrite => dir_path.with_extension("pdf"),
    ProcessMode::Path => Path::new(&config.path).join(format!("{}.pdf", dir_name)),
  };

  save_to_pdf(dir_name, target_path, buffers)
}

pub fn thumbnail_pdf(filepath: &String) -> Result<String, String> {
  let option = pdf::object::ParseOptions {
    allow_error_in_option: true,
    allow_invalid_ops: false,
    allow_missing_endobj: false,
    allow_xref_error: false,
  };

  let file = match FileOptions::cached().parse_options(option).open(filepath) {
    Ok(f) => f,
    _ => { return Err("invalid pdf file".to_owned()); },
  };

  let resolver = file.resolver();

  if let Some(page) = file.pages().next() {
    let p = page.unwrap();
    let resources = p.resources().unwrap();
    let mut img_buf = None;
    let mut width = 0;
    let mut height = 0;

    for (_, &r) in resources.xobjects.iter() {
      let obj = resolver.get(r).unwrap();
      let img = match *obj {
        XObject::Image(ref im) => im,
        _ => continue,
      };

      let Ok(data) = img.image_data(&resolver) else {
        continue;
      };
      img_buf = Some(data.to_vec());
      width = img.width;
      height = img.height;

      break;
    }

    if let Some(buf) = img_buf {
      let b64 = super::images::thumbnail_from_buf(buf, width, height).expect("failed to generate thumbnail from pdf");
      return Ok(b64);
    }
  }

  Err("no images found".to_owned())
}

pub async fn optimize_pdf(filepath: &Path, config: Config, window: &tauri::Window) -> Result<(), String> {
  let option = pdf::object::ParseOptions {
    allow_error_in_option: true,
    allow_invalid_ops: false,
    allow_missing_endobj: false,
    allow_xref_error: false,
  };

  let file = FileOptions::cached().parse_options(option).open(&filepath).unwrap();
  let resolver = file.resolver();

  let mut images: Vec<_> = vec![];
  let mut handles = vec![];

  for page in file.pages() {
    let p = page.unwrap();
    let resources = p.resources().unwrap();
    images.extend(resources.xobjects.iter().map(|(_name, &r)| resolver.get(r).unwrap())
        .filter(|o| matches!(**o, XObject::Image(_)))
    );
  }

  for (_, o) in images.iter().enumerate() {
    let img = match **o {
      XObject::Image(ref im) => im,
      _ => continue
    };

    let data = img.image_data(&resolver).expect("failed to read image_data from pdf");
    let conf = config.clone();
    let win = window.clone();
    let buf = data.to_vec();

    handles.push(tokio::spawn(async move {
      let img = optimize_image_buf(buf, &ImageConfig {
        path: "".to_string(),
        base_path: conf.path.clone(),
        overwrite: conf.mode == ProcessMode::Overwrite,
        quality: conf.quality,
        suffix: conf.suffix.clone(),
        width: conf.width,
        mode: conf.image_mode,
        ai: conf.ai,
      }).unwrap();
      win.emit("progress", "done").unwrap();
      img
    }));
  }

  let mut buffers = vec![];
  for buf in futures::future::join_all(handles).await {
    buffers.push(buf.unwrap());
  }

  let dir_name = filepath.file_name().unwrap().to_str().unwrap().to_string();
  let file_path = match config.mode {
    ProcessMode::Overwrite => filepath.with_extension("pdf"),
    ProcessMode::Path => Path::new(&config.path).join(format!("{}.pdf", dir_name)),
  };

  save_to_pdf(dir_name, file_path, buffers)
}

use std::{path::Path, io::{BufWriter, Write, BufReader}, fs::File};
use std::path::PathBuf;
use std::string::String;
use printpdf::{
  PdfDocument, ImageXObject, Image, Px, ColorSpace, ColorBits, ImageFilter,
  ImageTransform,
};
use nanoid::nanoid;

use pdf::file::FileOptions;
use pdf::object::*;
use pdf::enc::StreamFilter;

use super::images::{ImageConfig, optimize_image};
use crate::config::{Config, ProcessMode};

pub async fn zip(dir_path: &Path, files: Vec<String>, config: Config) -> Result<(), String> {
  let mut handles = vec![];

  for file_name in files {
    let conf = config.clone();
    handles.push(tokio::spawn(async move {
      let path = Path::new(&file_name);
      let name = path.file_name().unwrap().to_str().unwrap();
  
      match infer::get_from_path(&path) {
        Ok(inter_type) => match inter_type {
          Some(file) if file.mime_type().starts_with("image") => {
            let (buf, _, _) = optimize_image(ImageConfig {
              path: file_name.clone(),
              base_path: conf.path.clone(),
              overwrite: conf.mode == ProcessMode::Overwrite,
              quality: conf.quality,
              suffix: conf.suffix.clone(),
              width: if conf.preserve { 0.0 } else { conf.width },
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
    });

    image.add_to_layer(doc.get_page(page).get_layer(layer), ImageTransform {
      ..Default::default()
    });
  }

  doc.save(&mut BufWriter::new(File::create(&file_path).unwrap())).unwrap();
  Ok(())
}

pub async fn to_pdf(dir_path: &Path, files: Vec<String>, config: Config, window: &tauri::Window) -> Result<(), String> {
  let dir_name = dir_path.file_name().unwrap().to_str().unwrap().to_string();

  let mut handles = vec![];

  for file_name in files {
    let conf = config.clone();
    let win = window.clone();
    handles.push(tokio::spawn(async move {
      let img = optimize_image(ImageConfig {
        path: file_name,
        base_path: conf.path.clone(),
        overwrite: conf.mode == ProcessMode::Overwrite,
        quality: conf.quality,
        suffix: conf.suffix.clone(),
        width: if conf.preserve { 0.0 } else { conf.width },
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

pub fn thumbnail_pdf(filepath: String) -> Result<String, String> {
  let file = FileOptions::cached().open(&filepath).expect("invalid pdf file");

  if let Some(page) = file.pages().next() {
    let p = page.unwrap();
    let resources = p.resources().unwrap();
    let mut img_buf = None;
    let mut width = 0;
    let mut height = 0;

    for (_, &r) in resources.xobjects.iter() {
      let obj = file.get(r).unwrap();
      let img = match *obj {
        XObject::Image(ref im) => im,
        _ => continue,
      };

      let data = img.image_data(&file).expect("failed to read raw_image_data from pdf");
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
  let file = FileOptions::cached().open(&filepath).unwrap();
  let mut images: Vec<_> = vec![];
  let mut handles = vec![];

  for page in file.pages() {
    let p = page.unwrap();
    let resources = p.resources().unwrap();
    images.extend(resources.xobjects.iter().map(|(_name, &r)| file.get(r).unwrap())
        .filter(|o| matches!(**o, XObject::Image(_)))
    );
  }

  for (_, o) in images.iter().enumerate() {
    let img = match **o {
      XObject::Image(ref im) => im,
      _ => continue
    };

    let (data, filter) = img.raw_image_data(&file).expect("failed to read raw_image_data from pdf");
    let ext = match filter {
      Some(StreamFilter::DCTDecode(_)) => "jpeg",
      Some(StreamFilter::JBIG2Decode) => "jbig2",
      Some(StreamFilter::JPXDecode) => "jp2k",
      _ => continue,
    };

    let conf = config.clone();
    let win = window.clone();

    let job_id = nanoid!(15, &nanoid::alphabet::SAFE);
    let out_path = super::utils::get_cache_dir().unwrap().join(format!("{}.{}", job_id, ext));

    std::fs::write(&out_path, data).unwrap();

    handles.push(tokio::spawn(async move {
      let img = optimize_image(ImageConfig {
        path: out_path.to_str().unwrap().to_owned(),
        base_path: conf.path.clone(),
        overwrite: conf.mode == ProcessMode::Overwrite,
        quality: conf.quality,
        suffix: conf.suffix.clone(),
        width: if conf.preserve { 0.0 } else { conf.width },
        ai: conf.ai,
      }).unwrap();
      win.emit("progress", "done").unwrap();
      std::fs::remove_file(&out_path).unwrap();
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

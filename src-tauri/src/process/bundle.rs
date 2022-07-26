use std::{path::Path, io::{BufWriter, Write, BufReader}, fs::File, char};
use printpdf::{
  PdfDocument, ImageXObject, Image, Px, ColorSpace, ColorBits, ImageFilter,
  ImageTransform,
};

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

pub async fn to_pdf(dir_path: &Path, files: Vec<String>, config: Config) -> usize {
  let dir_name = dir_path.file_name().unwrap().to_str().unwrap().to_string();
  let title = to_utf16(&dir_name);
  let mut handles = vec![];

  for file_name in files {
    let conf = config.clone();
    handles.push(tokio::spawn(async move {
      optimize_image(ImageConfig {
        path: file_name,
        base_path: conf.path.clone(),
        overwrite: conf.mode == ProcessMode::Overwrite,
        quality: conf.quality,
        suffix: conf.suffix.clone(),
        width: if conf.preserve { 0.0 } else { conf.width },
      }).unwrap()
    }));
  }

  let mut buffers = vec![];
  for buf in futures::future::join_all(handles).await {
    buffers.push(buf.unwrap());
  }

  let doc = PdfDocument::empty(title);
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

  let file_path = match config.mode {
    ProcessMode::Overwrite => dir_path.with_extension("pdf"),
    ProcessMode::Path => Path::new(&config.path).join(format!("{}.pdf", dir_name)),
  };

  doc.save(&mut BufWriter::new(File::create(&file_path).unwrap())).unwrap();
  std::fs::read(&file_path).unwrap().len()
}

fn to_utf16(name: &String) -> String {
  let mut source = name.encode_utf16().collect::<Vec<u16>>();
  source.push(0);

  let decoded = char::decode_utf16(source.iter().cloned());
  let mut buf = String::with_capacity(name.len());
  for r in decoded {
    buf.push(r.unwrap_or(char::REPLACEMENT_CHARACTER));
  }

  buf
}

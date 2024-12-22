use base64::{engine::general_purpose, Engine as _};
use fast_image_resize::{self as fr, images::Image, PixelType};
use image::DynamicImage;
use mozjpeg::{ColorSpace, Compress, ScanMode};
use nanoid::nanoid;
use std::path::Path;

use crate::config::ImageMode;

#[derive(Debug)]
pub struct ImageConfig {
  pub path: String,
  pub suffix: String,
  pub base_path: String,
  pub quality: f32,
  pub width: f32,
  pub mode: ImageMode,
  pub overwrite: bool,
  pub ai: bool,
}

#[derive(Debug)]
pub struct ImageBuf {
  pub buf: Vec<u8>,
  pub width: u32,
  pub height: u32,
  pub pixel: PixelType,
}

pub fn open_buffer(buf: &[u8]) -> Result<ImageBuf, String> {
  let img = read_from_buf(buf)?;
  Ok(ImageBuf {
    buf: img.to_rgb8().to_vec(),
    width: img.width(),
    height: img.height(),
    pixel: PixelType::U8x3,
  })
}

pub fn open_image(path: &Path) -> Result<ImageBuf, String> {
  if let Ok(img) = image::open(path) {
    return Ok(ImageBuf {
      buf: img.to_rgb8().to_vec(),
      width: img.width(),
      height: img.height(),
      pixel: PixelType::U8x3,
    });
  };

  let file_name = path.file_name().unwrap().to_string_lossy();
  let Ok(buf) = std::fs::read(path) else {
    return Err(format!("unable to open file [{}]", file_name).to_string());
  };

  open_buffer(&buf)
}

pub fn thumbnail_from_buf(img: ImageBuf) -> Result<String, String> {
  let resized = resize(img, 250.0)?;
  let optimized = compress_jpg(resized, 65.0)?;
  Ok(general_purpose::STANDARD.encode(&optimized))
}

pub fn thumbnail(file_path: &String) -> Result<String, String> {
  let img = open_image(&Path::new(file_path))?;
  thumbnail_from_buf(img)
}

pub async fn optimize_and_save(config: ImageConfig) -> Result<(), String> {
  let path = Path::new(&config.path);
  let filename = path
    .with_extension("")
    .file_name()
    .unwrap()
    .to_string_lossy()
    .to_string();

  let img = optimize_image(&config).await?;

  let base_path = if config.overwrite {
    path.parent().unwrap().to_path_buf()
  } else {
    Path::new(&config.base_path).to_path_buf()
  };

  let target_file = base_path.join(format!("{}{}.{}", filename, config.suffix, "jpg"));
  std::fs::write(target_file, &img.buf).expect("failed to write file");

  Ok(())
}

async fn process_image(img: ImageBuf, config: &ImageConfig) -> Result<ImageBuf, String> {
  let target_width = config.width as u32;
  let width = img.width;

  if &config.mode == &ImageMode::Resize && config.ai && width < target_width {
    let scale = if width * 2 <= target_width { 2 } else { 4 };
    match upscale_image(&config.path, scale).await {
      Ok(next) => Ok(optimize(
        next,
        config.quality,
        config.width,
        &ImageMode::Resize,
      )?),
      Err(_) => Ok(optimize(
        img,
        config.quality,
        config.width,
        &ImageMode::Resize,
      )?),
    }
  } else {
    Ok(optimize(img, config.quality, config.width, &config.mode)?)
  }
}

pub async fn optimize_image(config: &ImageConfig) -> Result<ImageBuf, String> {
  let img = open_image(&Path::new(&config.path))?;
  process_image(img, config).await
}

pub async fn optimize_image_buf(buf: Vec<u8>, config: &ImageConfig) -> Result<ImageBuf, String> {
  let img = open_buffer(&buf)?;
  process_image(img, config).await
}

pub async fn optimize_image_buf_size(img: ImageBuf, config: &ImageConfig) -> Result<ImageBuf, String> {
  process_image(img, config).await
}

pub fn optimize(
  img: ImageBuf,
  quality: f32,
  target_width: f32,
  mode: &ImageMode,
) -> Result<ImageBuf, String> {
  let mut res = ImageBuf {
    width: img.width,
    height: img.height,
    buf: Vec::new(),
    pixel: img.pixel,
  };

  if mode == &ImageMode::Resize || (mode == &ImageMode::Shrink && img.width > target_width as u32) {
    let next: ImageBuf = resize(img, target_width)?;
    res.width = next.width;
    res.height = next.height;
    res.buf = compress_jpg(next, quality)?;
  } else {
    res.buf = compress_jpg(img, quality)?;
  }
  Ok(res)
}

fn resize(img: ImageBuf, target_width: f32) -> Result<ImageBuf, String> {
  let ratio = img.height as f32 / img.width as f32;

  let (w, h) = if img.width > img.height {
    ((target_width / ratio) as u32, target_width as u32)
  } else {
    (target_width as u32, (target_width * ratio) as u32)
  };

  let from = match Image::from_vec_u8(img.width, img.height, img.buf, img.pixel) {
    Ok(o) => o,
    Err(e) => return Err(format!("unable to read image file {:?}", e).to_string()),
  };
  let mut target = Image::new(w, h, img.pixel);
  let mut resizer = fr::Resizer::new();

  if let Err(err) = resizer.resize(&from, &mut target, None) {
    return Err(format!("failed to resize image: {:?}", err));
  };
  Ok(ImageBuf {
    buf: target.buffer().to_vec(),
    width: target.width(),
    height: target.height(),
    pixel: target.pixel_type(),
  })
}

fn compress_jpg(img: ImageBuf, qulity: f32) -> Result<Vec<u8>, String> {
  let cs = match img.pixel {
    PixelType::U8 => ColorSpace::JCS_GRAYSCALE,
    _ => ColorSpace::JCS_RGB,
  };
  let mut comp = Compress::new(cs);

  comp.set_scan_optimization_mode(ScanMode::AllComponentsTogether);
  comp.set_quality(qulity);
  comp.set_size(img.width as usize, img.height as usize);

  let Ok(mut comp) = comp.start_compress(Vec::new()) else {
    return Err("failed to start compress".to_string());
  };

  if let Err(err) = comp.write_scanlines(&img.buf) {
    return Err(format!("failed to compress buffer: {:?}", err).to_string());
  };

  let Ok(buf) = comp.finish() else {
    return Err("failed to compress".to_string());
  };

  Ok(buf)
}

pub async fn upscale_image(path: &String, scale: u8) -> Result<ImageBuf, String> {
  let cache_dir = super::utils::get_cache_dir().unwrap();
  let job_id = nanoid!(15, &nanoid::alphabet::SAFE);
  let out_path = cache_dir.join(format!("upscale_{}.webp", job_id));

  let output = super::external::upsacler([
    "-i",
    &path,
    "-o",
    out_path.to_str().unwrap(),
    "-n",
    "realesr-animevideov3",
    "-s",
    &format!("{}", scale),
  ]).await?;

  if !out_path.is_file() {
    return Err(format!("file does not generated: {:?}", output).to_string());
  }

  let img = open_image(&out_path)?;

  // remove cache
  std::fs::remove_file(&out_path).unwrap();

  Ok(img)
}

fn read_from_buf(raw: &[u8]) -> Result<DynamicImage, String> {
  if let Ok(img) = image::load_from_memory(raw) {
    return Ok(img);
  };

  if let Ok(format) = image::guess_format(raw) {
    return match image::load_from_memory_with_format(raw, format) {
      Ok(img) => Ok(img),
      Err(e) => Err(format!("unable to decode image buffer: {:?}", e).to_string()),
    };
  };

  Err("failed to guess format on reading buffer".to_string())
}

use std::path::Path;
use image::DynamicImage;
use mozjpeg::{Compress, ColorSpace, ScanMode};
use std::num::NonZeroU32;
use fast_image_resize as fr;
use base64::{Engine as _, engine::general_purpose};
use nanoid::nanoid;

use crate::config::{ImageMode};

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

pub fn open_buffer(buf: &[u8]) -> Result<DynamicImage, String> {
  let Ok(format) = image::guess_format(buf) else {
    return match image::load_from_memory_with_format(buf, image::ImageFormat::Tga) {
      Ok(img) => Ok(img),
      Err(err) => Err(format!("{:?}", err).to_string()),
    };
  };

  match image::load_from_memory_with_format(buf, format) {
    Ok(img) => Ok(img),
    Err(err) => Err(format!("{:?}", err).to_string()),
  }
}

pub fn open_image(path: &Path) -> Result<DynamicImage, String> {
  let file_name = path.file_name().unwrap().to_string_lossy();

  let buf = match std::fs::read(path) {
    Ok(f) => f,
    _ => return Err(format!("unable to open file [{}]", file_name).to_owned()),
  };

  open_buffer(&buf)
}

pub fn thumbnail(file_path: &String) -> Result<String, String> {
  let img = open_image(&Path::new(file_path))?;
  let resized = resize(&img, 250.0)?;
  let compressed = compress_image(resized, 45.0)?;
  let buf = general_purpose::STANDARD.encode(&compressed);

  Ok(buf)
}

pub fn thumbnail_from_buf(buf: Vec<u8>, width: u32, height: u32) -> Result<String, String> {
  let ratio = height as f32 / width as f32;

  let src_image = fr::Image::from_vec_u8(
    NonZeroU32::new(width).unwrap(),
    NonZeroU32::new(height).unwrap(),
    buf,
    fr::PixelType::U8x3,
  ).unwrap();

  let target_height = (ratio * 250.0) as u32;
  let dst_width = NonZeroU32::new(250).unwrap();
  let dst_height = NonZeroU32::new(target_height).unwrap();
  let mut dst_image = fr::Image::new(
      dst_width,
      dst_height,
      src_image.pixel_type(),
  );
  let mut dst_view = dst_image.view_mut();
  let mut resizer = fr::Resizer::new(fr::ResizeAlg::Convolution(fr::FilterType::Lanczos3));
  resizer.resize(&src_image.view(), &mut dst_view).unwrap();

  let optimized = compress_buf(dst_image.buffer().to_vec(), 250, target_height as usize, 65.0)?;
  Ok(general_purpose::STANDARD.encode(&optimized))
}

pub fn optimize_and_save(config: ImageConfig) -> Result<(), String> {
  let path = Path::new(&config.path);
  let filename = path.with_extension("").file_name().unwrap().to_string_lossy().to_string();

  let (buf, _, _) = optimize_image(&config)?;

  let base_path = if config.overwrite {
    path.parent().unwrap().to_path_buf()
  } else {
    Path::new(&config.base_path).to_path_buf()
  };

  let target_file = base_path.join(format!("{}{}.{}", filename, config.suffix, "jpg"));
  std::fs::write(target_file, &buf).expect("failed to write file");

  Ok(())
}

pub fn optimize_image(config: &ImageConfig) -> Result<(Vec<u8>, u32, u32), String> {
  let img = open_image(&Path::new(&config.path))?;
  let target_width = config.width as u32;

  if &config.mode == &ImageMode::Resize && config.ai && img.width() < target_width {
    let scale = if img.width() * 2 <= target_width { 2 } else { 4 };
    match upscale_image(&config.path, scale) {
      Ok(upscaled) => Ok(optimize(upscaled, config.quality, config.width, &config.mode)?),
      Err(_) => Ok(optimize(img, config.quality, config.width, &config.mode)?),
    }
  } else {
    Ok(optimize(img, config.quality, config.width, &config.mode)?)
  }
}

pub fn optimize_image_buf(buf: Vec<u8>, config: &ImageConfig) -> Result<(Vec<u8>, u32, u32), String> {
  let img = open_buffer(&buf)?;
  let target_width = config.width as u32;

  if &config.mode == &ImageMode::Resize && config.ai && img.width() < target_width {
    let scale = if img.width() * 2 <= target_width { 2 } else { 4 };
    match upscale_image(&config.path, scale) {
      Ok(upscaled) => Ok(optimize(upscaled, config.quality, config.width, &ImageMode::Resize)?),
      Err(_) => Ok(optimize(img, config.quality, config.width, &ImageMode::Resize)?),
    }
  } else {
    Ok(optimize(img, config.quality, config.width, &config.mode)?)
  }
}

pub fn optimize(img: DynamicImage, quality: f32, width: f32, mode: &ImageMode) -> Result<(Vec<u8>, u32, u32), String> {
  let before_width = img.width() as f32;

  if mode == &ImageMode::Resize || (mode == &ImageMode::Shrink && before_width > width) {
    let next = resize(&img, width)?;
    let w = next.width();
    let h = next.height();
    let image = compress_image(next, quality)?;
  
    Ok((image, w, h))
  } else {
    let w = img.width();
    let h = img.height();
    let image = compress_image(img, quality)?;
    Ok((image, w, h))
  }
}

fn resize_image(image: &DynamicImage, width: u32, height: u32) -> DynamicImage {
  if width > image.width() {
    // TODO: find way to upscale with super resoluation solution
    image.resize(width, height, image::imageops::FilterType::Lanczos3)
  } else {
    image.resize(width, height, image::imageops::FilterType::Lanczos3)
  }
}

fn resize(img: &DynamicImage, target_width: f32) -> Result<DynamicImage, String> {
  let width = img.width() as f32;
  let height = img.height() as f32;
  let ratio = height / width;

  let image = if width > height {
    let target_height = (target_width / ratio) as u32;
    resize_image(img, target_height, target_width as u32)
  } else {
    let target_height = (target_width * ratio) as u32;
    resize_image(img, target_width as u32, target_height)
  };

  Ok(image)
}

fn compress_buf(data: Vec<u8>, width: usize, height: usize, qulity: f32) -> Result<Vec<u8>, String> {
  let mut comp = Compress::new(ColorSpace::JCS_RGB);

  comp.set_scan_optimization_mode(ScanMode::AllComponentsTogether);
  comp.set_quality(qulity);
  comp.set_size(width, height);

  let mut comp = comp.start_compress(Vec::new()).expect("failed to start compress");
  comp.write_scanlines(&data).expect("failed to write data");

  Ok(comp.finish().expect("failed to compress"))
}

fn compress_image(img: DynamicImage, quality: f32) -> Result<Vec<u8>, String> {
  let data = img.to_rgb8().to_vec();
  let width = img.width() as usize;
  let height = img.height() as usize;

  compress_buf(data, width, height, quality)
}

pub fn upscale_image(path: &String, scale: u8) -> Result<DynamicImage, String> {
  let cache_dir = super::utils::get_cache_dir().unwrap();
  let job_id = nanoid!(15, &nanoid::alphabet::SAFE);
  let out_path = cache_dir.join(format!("upscale_{}.webp", job_id));

  let output = match super::external::upsacler()?
    .args([
      "-i", &path,
      "-o", out_path.to_str().unwrap(),
      "-n", "realesr-animevideov3",
      "-s", &format!("{}", scale),
    ])
    .output() {
      Ok(out) => out,
      Err(err) => return Err(format!("Error executing RealESRGAN Upscaler. \n{:?}", err).to_string()),
    };

  if !out_path.is_file() {
    println!("file does not generated: {:?}", output);
    return Err(format!("file does not generated: {:?}", output).to_string());
  }

  let img = open_image(&out_path).unwrap();

  // remove cache
  std::fs::remove_file(out_path).unwrap();

  Ok(img)
}

use std::{path::Path};
use image::{DynamicImage};
use mozjpeg::{Compress, ColorSpace, ScanMode};
use std::num::NonZeroU32;
use fast_image_resize as fr;

#[derive(Debug, Clone)]
pub struct ImageConfig {
  pub path: String,
  pub suffix: String,
  pub base_path: String,
  pub quality: f32,
  pub width: f32,
  pub overwrite: bool,
}

pub fn thumbnail(file_path: String) -> Result<String, String> {
  let path = Path::new(&file_path);
  let img = image::open(path).unwrap();
  let resized = resize(&img, 250.0)?;
  let compressed = compress_image(resized, 45.0)?;
  let b64 = base64::encode(&compressed);

  Ok(b64)
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
  Ok(base64::encode(&optimized))
}

pub fn optimize_and_save(config: ImageConfig) -> Result<(), String> {
  let path = Path::new(&config.path);
  let img = image::open(path).unwrap();
  let filename = path.with_extension("").file_name().unwrap().to_string_lossy().to_string();

  let (data, _, _) = optimize(img, config.quality, config.width)?;

  let base_path = if config.overwrite {
    path.parent().unwrap().to_path_buf()
  } else {
    Path::new(&config.base_path).to_path_buf()
  };

  let target_file = base_path.join(format!("{}{}.{}", filename, config.suffix, "jpg"));
  std::fs::write(target_file, &data).expect("failed to write file");

  Ok(())
}

pub fn optimize_image(config: ImageConfig) -> Result<(Vec<u8>, u32, u32), String> {
  let path = Path::new(&config.path);
  let img = image::open(path).unwrap();
  let res = optimize(img, config.quality, config.width)?;
  Ok(res)
}

fn optimize(img: DynamicImage, quality: f32, width: f32) -> Result<(Vec<u8>, u32, u32), String> {
  if width == 0.0 {
    let width = img.width();
    let height = img.height();
    let image = compress_image(img, quality)?;
  
    Ok((image, width, height))
  } else {
    let img = resize(&img, width)?;
    let width = img.width();
    let height = img.height();
    let image = compress_image(img, quality)?;
  
    Ok((image, width, height))
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
    let target_height = (target_width * 2.0 * ratio) as u32;
    resize_image(img, (target_width * 2.0) as u32, target_height)
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
  comp.set_mem_dest();
  comp.start_compress();

  comp.write_scanlines(&data);

  comp.finish_compress();
  let compressed = comp.data_to_vec().expect("failed to compress");
  Ok(compressed)
}

fn compress_image(img: DynamicImage, quality: f32) -> Result<Vec<u8>, String> {
  let data = img.to_rgb8().to_vec();
  let width = img.width() as usize;
  let height = img.height() as usize;

  compress_buf(data, width, height, quality)
}

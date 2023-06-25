use std::{path::Path};
use image::{DynamicImage};
use mozjpeg::{Compress, ColorSpace, ScanMode};
use std::num::NonZeroU32;
use fast_image_resize as fr;
use base64::{Engine as _, engine::{general_purpose}};
use nanoid::nanoid;


#[derive(Debug, Clone)]
pub struct ImageConfig {
  pub path: String,
  pub suffix: String,
  pub base_path: String,
  pub quality: f32,
  pub width: f32,
  pub overwrite: bool,
  pub ai: bool,
}

fn open_image(path: &Path) -> Result<DynamicImage, String> {
  let file_name = path.file_name().unwrap().to_string_lossy();
  match image::open(path) {
    Ok(buf) => Ok(buf),
    Err(err) => return Err(format!("{}: {}", file_name, err).to_string()),
  }
}

pub fn thumbnail(file_path: String) -> Result<String, String> {
  let path = Path::new(&file_path);
  let img = open_image(&path)?;
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

  let (buf, _, _) = optimize_image(config.clone())?;

  let base_path = if config.overwrite {
    path.parent().unwrap().to_path_buf()
  } else {
    Path::new(&config.base_path).to_path_buf()
  };

  let target_file = base_path.join(format!("{}{}.{}", filename, config.suffix, "jpg"));
  std::fs::write(target_file, &buf).expect("failed to write file");

  Ok(())
}

pub fn optimize_image(config: ImageConfig) -> Result<(Vec<u8>, u32, u32), String> {
  let path = Path::new(&config.path);
  let img = open_image(&path)?;
  let target_width = config.width.clone() as u32;
  if img.width() < target_width && target_width > 0 && config.ai {
    let scale = if img.width() * 2 <= target_width { 2 } else { 4 };
    let upscaled_img = upscale_image(&config.path, scale)?;
    Ok(optimize(upscaled_img, config.quality, config.width)?)
  } else {
    Ok(optimize(img, config.quality, config.width)?)
  }
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

fn upscale_image(path: &String, scale: u8) -> Result<DynamicImage, String> {
  let cache_dir = super::utils::get_cache_dir().unwrap();
  let job_id = nanoid!(15, &nanoid::alphabet::SAFE);
  let out_path = cache_dir.join(format!("upscale_{}.png", job_id));

  let _output = match tauri::api::process::Command::new_sidecar("upscale")
    .expect("failed to create `upscale` binary command")
    .args(["-i", &path, "-o", out_path.to_str().unwrap(), "-n", "realesr-animevideov3", "-s", &scale.to_string()])
    .output() {
      Ok(out) => out,
      Err(err) => return Err(format!("Error executing RealESRGAN Upscaler. \n{:?}", err).to_string()),
    };

  if !out_path.is_file() {
    return Err("file does not generated".to_string());
  }

  let img = open_image(&out_path);

  // remove cache
  std::fs::remove_file(out_path).unwrap();

  Ok(img.unwrap())
}

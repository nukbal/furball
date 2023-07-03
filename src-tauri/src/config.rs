use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, PartialEq, Default, Debug, Clone)]
#[serde(rename_all = "lowercase")]
pub enum ProcessMode {
  Overwrite,
  #[default]
  Path,
}

#[derive(Serialize, Deserialize, PartialEq, Default, Debug, Clone)]
#[serde(rename_all = "lowercase")]
pub enum DirMode {
  #[default]
  None,
  Pdf,
  Zip,
}

#[derive(Serialize, Deserialize, PartialEq, Default, Debug, Clone)]
#[serde(rename_all = "lowercase")]
pub enum GifMode {
  #[default]
  Gif,
  Mp4,
  Webp,
}

#[derive(Serialize, Deserialize, Default, Debug, Clone)]
pub struct Config {
  // general
  pub mode: ProcessMode,
  pub path: String,
  pub suffix: String,

  // images
  pub preserve: bool,
  pub width: f32,
  pub quality: f32,
  pub gif: GifMode,
  pub ai: bool,

  // dir
  pub dir_mode: DirMode,
}

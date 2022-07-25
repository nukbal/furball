use std::collections::HashMap;

use ffmpeg::software::scaling::flag::Flags;
use ffmpeg::software::scaling::context::Context;
use ffmpeg::format::Pixel;
use ffmpeg::util::frame::video::Video;
use ffmpeg::{codec, format, media, Rational, encoder};
use ffmpeg::ffi::AV_TIME_BASE;

use super::images::thumbnail_from_buf;

pub fn thumbnail(file_path: String) -> Result<String, String> {
  let path = std::path::Path::new(&file_path);
  let mut input = format::input(&path).unwrap();

  let stream = input.streams().best(media::Type::Video).expect("unable to read video stream");
  let stream_index = stream.index();

  let context_decoder = codec::context::Context::from_parameters(stream.parameters()).unwrap();
  let mut video = context_decoder.decoder().video().unwrap();
  let mut scaler = Context::get(
    video.format(),
    video.width(),
    video.height(),
    Pixel::RGB24,
    video.width()/2,
    video.height()/2,
    Flags::BILINEAR,
  ).unwrap();

  let start = input.duration() / 125;
  if start > (AV_TIME_BASE as i64) {
    input.seek(start, start..).expect("seek");
  }

  for (stm, packet) in input.packets() {
    if stm.index() != stream_index {
      continue;
    }
    if let Err(err) = video.send_packet(&packet) {
      println!("failed to send packet: {}", err);
      continue;
    }
    break;
  }

  if video.has_b_frames() {
    video.send_eof().expect("send_eof");
  }

  let mut output = Video::empty();
  while video.receive_frame(&mut output).is_ok() {
    let mut rgb_frame = Video::empty();

    if let Err(err) = scaler.run(&output, &mut rgb_frame) {
      println!("failed to scale input frame: {}", err);
      continue;
    }

    unsafe {
      if rgb_frame.is_empty() == false {
        output = rgb_frame;
        break;
      }
    }
  }

  unsafe {
    if output.is_empty() {
      return Err("unable to retrive video thumbnail".to_string());
    }
  }

  let mut buf: Vec<u8> = vec![];
  let data = output.data(0);
  let stride = output.stride(0);
  let byte_width: usize = 3 * output.width() as usize;
  let height: usize = output.height() as usize;

  for line in 0..height {
    let begin = line * stride;
    let end = begin + byte_width;
    buf.extend(&data[begin..end]);
  }

  let b64 = thumbnail_from_buf(buf, output.width(), output.height())?;
  Ok(b64)
}


#[derive(Debug, Clone)]
pub struct VideoConfig {
  pub path: String,
  pub suffix: String,
  pub base_path: String,
  pub quality: f32,
  pub overwrite: bool,
}

pub fn compress(config: VideoConfig) -> Result<(), String> {
  // println!("compress video: {:?}", config);
  // let path = std::path::Path::new(&config.path);
  // let filename = path.with_extension("").file_name().unwrap().to_string_lossy().to_string();

  // let output_path = if config.overwrite {
  //   path.parent().unwrap().join(format!("{}{}.mp4", &filename, config.suffix).to_string())
  // } else {
  //   tauri::api::path::download_dir().unwrap()
  //     .join(format!("{}{}.mp4", &filename, config.suffix).to_string())
  // };

  // let mut ictx = format::input(&config.path).unwrap();
  // let mut octx = format::output(&output_path).unwrap();

  // format::context::input::dump(&ictx, 0, Some(&config.path));

  // let video_stream_index = ictx.streams()
  //   .best(media::Type::Video).map(|stream| stream.index()).unwrap();

  // let mut stream_mapping: Vec<isize> = vec![0; ictx.nb_streams() as _];
  // let mut ist_time_bases = vec![Rational(0, 0); ictx.nb_streams() as _];
  // let mut ost_time_bases = vec![Rational(0, 0); ictx.nb_streams() as _];
  // let mut transcoders = HashMap::new();
  // let mut ost_index = 0;

  // for (ist_index, ist) in ictx.streams().enumerate() {
  //   let ist_medium = ist.parameters().medium();
  //   if ist_medium != media::Type::Audio
  //     && ist_medium != media::Type::Video
  //     && ist_medium != media::Type::Subtitle
  //   {
  //     stream_mapping[ist_index] = -1;
  //     continue;
  //   }
  //   stream_mapping[ist_index] = ost_index;
  //   ist_time_bases[ist_index] = ist.time_base();
  //   if ist_medium == media::Type::Video {
  //     let trans = Transcoder::new(
  //         &ist,
  //         &mut octx,
  //         ost_index as _,
  //         x264_opts.to_owned(),
  //         Some(ist_index) == best_video_stream_index,
  //     );
  //     transcoders.insert(ist_index, trans).unwrap();
  //   } else {

  //   }
  // }

  // let global_header = octx.format().flags().contains(format::Flags::GLOBAL_HEADER);
  // let decoder = ffmpeg::codec::context::Context::from_parameters(ist.parameters())?
  //     .decoder()
  //     .video()?;
  // let mut ost = octx.add_stream(encoder::find(codec::Id::H264))?;
  // let mut encoder = codec::context::Context::from_parameters(ost.parameters())?
  //     .encoder()
  //     .video()?;
  Ok(())
}

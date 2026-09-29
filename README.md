# Furball

hobby app for compressing and organizing images, videos, PDFs and archives with SDL3 and Clay.

```sh
zig build run
zig build -Doptimize=ReleaseSmall
zig build package -Doptimize=ReleaseSafe
```

## Features
- image compression
- image pdf archiving
- zip archiving
- super resolution (Real-ESRGAN, PiperSR)
- zip detection
- pdf detection
- pdf image conversion

## Credits

- [stb](https://github.com/nothings/stb)
- [miniz](https://github.com/richgel999/miniz)
- [pdfio](https://github.com/michaelrsweet/pdfio)
- [mozjpeg](https://github.com/mozilla/mozjpeg)
- [FFmpeg](https://ffmpeg.org)
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) AnimeVideo x2/x4 models converted to Core ML during dependency installation
- [PiperSR](https://modelpiper.com/) Core ML model (CC BY 4.0)
- [Pretendard](https://github.com/orioncactus/pretendard)

# Furball

hobby app for compressing and organizing images, videos, PDFs and archives with SDL3 and Clay.

## Build

```sh
zig build run
zig build -Doptimize=ReleaseSmall
zig build package -Doptimize=ReleaseSafe
```

## Features
- image compression
- image pdf archiving
- zip archiving
- super resolution
- zip detection
- pdf detection
- pdf image conversion

## Credits

- [stb](https://github.com/nothings/stb)
- [miniz](https://github.com/richgel999/miniz)
- [pdfio](https://github.com/michaelrsweet/pdfio)
- [mozjpeg](https://github.com/mozilla/mozjpeg)
- [FFmpeg](https://ffmpeg.org)
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN), [ncnn](https://github.com/Tencent/ncnn)
- [Pretendard](https://github.com/orioncactus/pretendard)

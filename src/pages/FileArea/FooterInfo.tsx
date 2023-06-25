import { createMemo } from 'solid-js';

import config from 'models/config';
import file from 'models/file';

export default function FooterInfo() {
  const configInfo = createMemo(() => {
    const mode = file().mode;
    const isImg = mode.includes('image');
    const isVideo = mode.includes('video');
    const isFolder = mode.includes('dir');

    return [
      `덮어쓰기: ${config.mode === 'overwrite' ? '○' : '×'}`,
      `저장장소: ${config.path}`,
      config.suffix ? `접미사: ${config.suffix}` : '',

      // 이미지의 경우
      ...(isImg ? [
        `이미지 퀄리티: ${config.quality}`,
        config.preserve ? `이미지 크기 유지` : `리사이징: ${config.width}px`,
        `GIF 변환: ${config.gif}`,
        `AI 스케일링: ${config.ai ? '○' : '×'}`
      ] : []),

      ...(isFolder ? [
        `폴더 처리: ${config.dir_mode === 'none' ? '개별처리' : `${config.dir_mode.toUpperCase()} 변환`}`,
      ] : []),
    ].filter(Boolean).join(', ')
  });

  return (
    <abbr
      class="absolute left-3 right-8 bottom-2 text-xs text-gray-600 whitespace-nowrap break-words overflow-hidden text-ellipsis no-underline cursor-default"
      data-tauri-drag-region
      title={configInfo()}
    >
      {configInfo()}
    </abbr>
  );
}

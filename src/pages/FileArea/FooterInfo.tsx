import { createMemo } from 'solid-js';

import config, { type ConfigType } from 'models/config';
import file from 'models/file';

export default function FooterInfo() {
  const configInfo = createMemo(() => {
    const mode = file().mode;
    const isImg = mode.includes('image');
    const isVideo = mode.includes('video');
    const isFolder = mode.includes('dir');

    return [
      config.mode === 'overwrite' ? '덮어쓰기' : '파일유지',
      `저장장소: ${config.path}`,
      config.suffix ? `접미사: ${config.suffix}` : '',

      // 이미지의 경우
      ...(isImg ? [
        `퀄리티: ${config.quality}`,
        getImageModeText(config),
        `GIF -> ${config.gif}`,
      ] : []),

      ...(isFolder ? [
        config.dir_mode === 'none' ? '파일개별처리' : `${config.dir_mode.toUpperCase()} 변환`,
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

function getImageModeText(conf: ConfigType) {
  if (conf.image_mode === 'resize') {
    return `${conf.ai ? 'AI' : ''}리사이즈: ${conf.width}px`;
  }
  if (conf.image_mode === 'shrink') return `축소: 최대${conf.width}px`;
  return '압축만';
}

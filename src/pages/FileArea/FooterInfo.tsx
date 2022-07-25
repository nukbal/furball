import { useCallback, useMemo } from 'react';
import styled from 'styled-components';

import { useConfig } from '../../models/config';
import { useFile } from '../../models/file';

import s from '../../styles/static';

export default function FooterInfo() {
  const mode = useFile(useCallback(({ mode }) => ({
    img: mode.includes('image'),
    vid: mode.includes('video'),
    dir: mode.includes('dir'),
  }), []));
  const config = useConfig();

  const configInfo = useMemo(() => [
    `덮어쓰기: ${config.mode === 'overwrite' ? 'O' : 'X'}`,
    `저장장소: ${config.path}`,
    config.suffix ? `접미사: ${config.suffix}` : '',

    // 이미지의 경우
    ...(mode.img ? [
      `이미지 퀄리티: ${config.quality}`,
      config.preserve ? `이미지 크기 유지` : `리사이징: ${config.width}px`,
      `GIF 변환: ${config.gif}`,
    ] : []),

    ...(mode.dir ? [
      `폴더 처리: ${config.dir_mode === 'none' ? '개별처리' : `${config.dir_mode.toUpperCase()} 변환`}`,
    ] : []),
  ].filter(Boolean).join(', '), [mode, config]);

  return <Footer data-tauri-drag-region>{configInfo}</Footer>;
}

const Footer = styled.footer`
  position: absolute;
  left: ${s.size['8']};
  right: ${s.size['8']};
  bottom: ${s.size['4']};
  font-size: 0.875rem;
  color: ${({ theme }) => theme.gray400};

  pointer-events: none;
  white-space: pre-wrap;
  word-break: break-word;
`;

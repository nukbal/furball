import { useCallback, useEffect, useState } from 'react';
import styled from 'styled-components';
import { appWindow } from '@tauri-apps/api/window';
import { UnlistenFn } from '@tauri-apps/api/event';

import Button from '../components/Button';
import CloseIcon from '../components/Icons/Close';

import s from '../styles/static';
import getFileMeta from '../utils/getFileMeta';
import file, { setFileData, reset, useFile } from '../models/file';

import EmptyStatus from './EmptyStatus';
import FileArea from './FileArea';
import Credit from './Credit';

export default function App() {
  const status = useFile(({ status }) => status);

  useEffect(() => {
    let unsub: UnlistenFn;
    appWindow.onFileDropEvent((e) => {
      if (e.payload.type === 'drop') {
        const paths = e.payload.paths;
        reset({ paths, status: 'loading' });
        getFileMeta(paths)
          .then((res) => {
            if (res.length) {
              setFileData(res);
            } else {
              reset();
            }
          }).catch((e) => {
            reset();
          });
      } else {
        file.setState({ status: e.payload.type });
      }
    }).then((cb) => {
      unsub = cb;
    });
    return () => unsub?.();
  }, []);

  return (
    <Container data-tauri-drag-region>
      {status !== 'drop' && <EmptyStatus />}
      {status === 'drop' && <FileArea />}
      <Close onClick={() => appWindow.close()}>
        <CloseIcon />
      </Close>
      <Credit />
    </Container>
  );
}

const Container = styled.div`
  position: relative;
  display: flex;
  flex-direction: column;
  flex: 1;
  padding: ${s.size['6']};
`;

const Close = styled(Button)`
  position: absolute;
  right: ${s.size['4']};
  top: ${s.size['4']};

  padding: ${s.size['1']} ${s.size['1.5']};
  color: ${({ theme }) => theme.gray800};

  svg {
    width: ${s.size['8']};
    height: ${s.size['8']};
  }

  &:hover {
    background: ${({ theme }) => theme.gray300};
  }
  &:active, &:focus {
    background: ${({ theme }) => theme.gray100};
  }
`;

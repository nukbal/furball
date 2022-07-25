import { useCallback } from 'react';
import styled from 'styled-components';
import { open } from '@tauri-apps/api/dialog';
import { downloadDir } from '@tauri-apps/api/path';

import Button from '../components/Button';
import Spinner from '../components/Spinner';
import s from '../styles/static';
import file, { reset, setFileData, useFile } from '../models/file';

import getFileMeta from '../utils/getFileMeta';
import { VALID_IMAGE_EXT, VALID_VIDEO_EXT } from '../const';

export default function EmptyStatus() {
  const status = useFile(useCallback(({ status }) => status, []));

  const handleSelect = useCallback(async () => {
    try {
      const downloadPath = await downloadDir();
      const filePaths = await open({
        defaultPath: downloadPath,
        multiple: true,
        // directory: true,
        filters: [
          { name: 'Image', extensions: VALID_IMAGE_EXT },
          { name: 'Video', extensions: VALID_VIDEO_EXT },
        ],
      });
      if (filePaths !== null) {
        const paths = Array.isArray(filePaths) ? filePaths : [filePaths];
        file.setState({ status: 'loading', paths });
        const res = await getFileMeta(paths);
        setFileData(res);
      } else {
        reset();
      }
    } catch (e) {
      console.log(e);
      reset();
    }
  }, []);

  return (
    <Container data-tauri-drag-region>
      {status !== 'loading' ? (
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          {status === 'hover' ? (
            <path strokeLinecap="round" strokeLinejoin="round" d="M5 19a2 2 0 01-2-2V7a2 2 0 012-2h4l2 2h4a2 2 0 012 2v1M5 19h14a2 2 0 002-2v-5a2 2 0 00-2-2H9a2 2 0 00-2 2v5a2 2 0 01-2 2z" />
          ) : (
            <path strokeLinecap="round" strokeLinejoin="round" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
          )}
        </svg>
      ) : (
        <Spinner size={32} />
      )}
      {status === 'hover' ? <p>내려놓아주세요 :)</p> : null}
      {status === 'loading' ? <p style={{ marginTop: '0.5rem' }}>파일을 보고있어요...</p> : null}
      {status === 'cancel' ? (
        <>
          <p>
            이미지, 동영상, 폴더 등<br />
            처리하고싶은 파일을 끌어다주세요
          </p>
          <OrArea>
            <span>혹은</span>
          </OrArea>
          <SelectButton onClick={handleSelect}>
            파일 고르기
          </SelectButton>
        </>
      ) : null}
    </Container>
  );
}

const Container = styled.div`
  position: absolute;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  flex: 1;
  background: ${({ theme }) => theme.gray200};
  border: 4px dashed ${({ theme }) => theme.gray500};
  border-radius: ${s.radius['2xl']};
  z-index: 10;

  top: ${s.size['14']};
  left: ${s.size['14']};
  right: ${s.size['14']};
  bottom: ${s.size['14']};

  p {
    margin: 0;
    font-size: ${s.size['6']};
    line-height: 1.25;
    text-align: center;
    pointer-events: none;
  }

  svg {
    width: ${s.size['20']};
    height: ${s.size['20']};
    margin-bottom: ${s.size['2.5']};
    pointer-events: none;
  }
`;

const OrArea = styled.section`
  position: relative;
  text-align: center;
  border-bottom: 1px solid currentColor;
  line-height: 0.1em;
  width: ${s.size['44']};
  margin: ${s.size['8']} 0;
  color: ${({ theme }) => theme.gray700};
  pointer-events: none;

  span {
    padding: 0 ${s.size['5']};
    font-size: ${s.size['5']};
    background: ${({ theme }) => theme.gray200};
  }
`;

const SelectButton = styled(Button)`
  font-weight: 500;
  font-size: ${s.size['6']};
  min-width: ${s.size['44']};
  min-height: ${s.size['16']};
  background: ${({ theme }) => theme.blue500};

  &:hover {
    background: ${({ theme }) => theme.blue600};
  }

  &:focus, &:active {
    background: ${({ theme }) => theme.blue400};
  }
`;

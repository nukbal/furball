import React, { useCallback, useState } from 'react'
import styled from 'styled-components';
import { invoke } from '@tauri-apps/api/tauri';

import Button from '../../components/Button';
import Spinner from '../../components/Spinner';
import Modal from '../../components/Modal';
import RefreshIcon from '../../components/Icons/Refresh';
import CloseIcon from '../../components/Icons/Close';
import ConfigIcon from '../../components/Icons/Config';

import s from '../../styles/static';
import file, { reset } from '../../models/file';
import * as proc from '../../utils/process';
import SwapIcon from '../../components/Icons/Swap';

import ProcessConfig from './ProcessConfig';
import Preview from './Preview';
import FileList from './FileList';
import FileHeader from './FileHeader';
import FooterInfo from './FooterInfo';

export default function FileStatus() {
  const [status, setStatus] = useState('none');
  const [isOpen, setOpen] = useState(false);

  const handleProcess = useCallback(async () => {
    const paths = file.getState().paths;

    setStatus('loading');
    try {
      await proc.processImage(paths);

      setStatus('done');
    } catch (e) {
      console.log(e);
      setStatus('error');
    }
  }, []);

  return (
    <Container data-tauri-drag-region>
      <FileHeader />
      <Content data-tauri-drag-region>
        <Preview />
        <InfoArea data-tauri-drag-region>
          <FileList />
          <footer data-tauri-drag-region>
            <ButtonArea disabled={status === 'loading'}>
              <Button onClick={handleProcess} disabled={status === 'loading'}>
                {React.createElement(
                  status === 'loading' ? Spinner : SwapIcon,
                  { style: { marginRight: s.size['4'], marginLeft: `-${s.size['0.5']}` } },
                )}
                <span>{status === 'loading' ? '처리중...' : '처리하기'}</span>
              </Button>
              <hr />
              <Button aria-label="설정하기" onClick={() => setOpen(true)} disabled={status === 'loading'}>
                {isOpen ? <CloseIcon /> : <ConfigIcon />}
              </Button>
            </ButtonArea>
            <Reset onClick={() => reset()}>
              <RefreshIcon />
            </Reset>
          </footer>
        </InfoArea>
      </Content>
      <Modal open={isOpen} onClose={() => setOpen(false)}>
        <ProcessConfig onClose={() => setOpen(false)} />
      </Modal>
      <FooterInfo />
    </Container>
  );
}

const Container = styled.div`
  display: flex;
  flex-direction: column;
  flex: 1;
`;

const Content = styled.div`
  display: flex;
  align-items: flex-start;
  padding-top: ${s.size['10']};
  flex: 1;
`;

const InfoArea = styled.div`
  flex: auto;

  footer {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
  }
`;

const ButtonArea = styled.div<{ disabled?: boolean; }>`
  display: inline-flex;
  align-items: center;
  border: 1px solid ${({ theme, disabled }) => (disabled ? theme.gray200 : theme.green500)};
  border-radius: ${s.radius['lg']};
  background: ${({ theme, disabled }) => (disabled ? theme.gray200 : theme.green500)};
  user-select: none;

  hr {
    width: 0;
    height: ${s.size['8']};
    border: 0.5px solid currentColor;
  }

  button {
    min-height: ${s.size['16']};
    font-size: ${s.size['6']};

    svg {
      width: ${s.size['6']};
      height: ${s.size['6']};
    }

    &:hover {
      background: ${({ theme }) => theme.green600};
    }

    &:active, &:focus {
      background: ${({ theme }) => theme.green400};
    }

    &:not(:last-child) {
      border-top-right-radius: 0;
      border-bottom-right-radius: 0;
    }

    &:not(:first-child) {
      border-top-left-radius: 0;
      border-bottom-left-radius: 0;
    }
  }
`;

const Reset = styled(Button)`
  padding: ${s.size['2']} ${s.size['2.5']};
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


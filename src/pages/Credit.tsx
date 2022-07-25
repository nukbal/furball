import { useCallback, useEffect, useRef, useState } from 'react';
import styled from 'styled-components';
import { getVersion, getName } from '@tauri-apps/api/app';

import Button from '../components/Button';
import CloseIcon from '../components/Icons/Close';
import s from '../styles/static';

export default function Author() {
  const [show, setShow] = useState(false);
  const [names, setNames] = useState(['', '']);
  const timeout = useRef<number | null>(null);
  const clicked = useRef(0);

  useEffect(() => {
    Promise.all([getName(), getVersion()])
      .then((value) => {
        setNames(value);
      });
  }, []);

  const handleClick = useCallback(() => {
    if (timeout.current !== null) {
      clearTimeout(timeout.current);
      timeout.current = null;
    }
    clicked.current += 1;
    if (clicked.current >= 10) {
      setShow(true);
      clicked.current = 0;
    } else {
      timeout.current = window.setTimeout(() => {
        clicked.current = 0;
      }, 500);
    }
  }, []);

  return (
    <>
      <AuthorButton onClick={handleClick}>
        <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M18.364 5.636l-3.536 3.536m0 5.656l3.536 3.536M9.172 9.172L5.636 5.636m3.536 9.192l-3.536 3.536M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-5 0a4 4 0 11-8 0 4 4 0 018 0z" />
        </svg>
      </AuthorButton>
      {show ? (
        <InfoArea data-tauri-drag-region>
          <h3>{names[0]}: v{names[1]}</h3>
          <p>제작자: nukbal</p>
          <img src={image} />
          <CloseButon onClick={() => setShow(false)}>
            <CloseIcon />
          </CloseButon>
        </InfoArea>
      ) : null}
    </>
  );
}

const AuthorButton = styled(Button)`
  position: absolute;
  bottom: ${s.size['2']};
  right: ${s.size['2']};
  padding: ${s.size['2']};
  opacity: 0.25;

  svg {
    width: ${s.size['5']};
    height: ${s.size['5']};
    color: ${({ theme }) => theme.gray400};
  }

  &:hover {
    background: transparent;
  }
`;

const InfoArea = styled.div`
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  overflow-y: auto;
  padding: ${s.size['4']};
  background: ${({ theme }) => theme.gray200};
  color: ${({ theme }) => theme.gray800};
  z-index: 10;

  img {
    width: ${s.size['64']};
    height: ${s.size['64']};
    user-select: none;
    pointer-events: none;
  }
`;

const CloseButon = styled(Button)`
  position: absolute;
  top: ${s.size['4']};
  right: ${s.size['4']};
  padding: ${s.size['1']} ${s.size['1.5']};

  svg {
    width: ${s.size['8']};
    height: ${s.size['8']};
  }
`;

const image = 'data:image/jpeg;base64,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';

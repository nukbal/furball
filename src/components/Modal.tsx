import React from 'react';
import styled, { css } from 'styled-components';
import { Transition } from 'react-transition-group';

import s from '../styles/static';

import Portal from './Portal';

interface Props {
  children: React.ReactNode;
  open: boolean;
  onClose: () => void;
}

export default function Modal({ children, open, onClose }: Props) {
  return (
    <Portal>
      <Transition in={open} timeout={200} mountOnEnter unmountOnExit>
        {(state) => (
          <Wrapper role="dialog">
            <BackDrop className={state} onClick={onClose} />
            <Container data-tauri-drag-region>
              <Panel className={state} role="document">
                {children}
              </Panel>
            </Container>
          </Wrapper>
        )}
      </Transition>
    </Portal>
  );
}

const inset = css`
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
`;

const BackDrop = styled.div`
  ${inset}
  background: rgba(0,0,0,0.25);
  user-select: none;
  will-change: opacity;
  opacity: 0;

  &.entered, &.entering {
    transition: opacity 250ms ease-out;
  }

  &.exited, &.exiting {
    transition: opacity 200ms ease-in;
  }

  &.entering, &.exiting, &.exited {
    opacity: 0;
  }

  &.entered {
    opacity: 1;
  }
`;

const Wrapper = styled.div`
  ${inset}
  user-select: none;
`;

const Container = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  padding: ${s.size['4']};
  user-select: none;
  overflow-y: auto;
`;

const Panel = styled.div`
  position: relative;
  width: 100%;
  min-height: calc(100vh - 5rem);
  max-height: calc(100vh - 5rem);
  padding: ${s.size['6']};
  overflow: hidden;
  border-radius: ${s.radius['2xl']};
  background: ${({ theme }) => theme.gray200};
  user-select: none;
  will-change: transform, opacity;

  &.entered, &.entering {
    transition: opacity, transform 250ms ease-out;
  }

  &.exited, &.exiting {
    transition: opacity, transform 200ms ease-in;
  }

  &.entering, &.exiting, &.exited {
    opacity: 0;
    transform: translateY(-0.825rem);
  }

  &.entered {
    opacity: 1;
    transform: translateY(0);
  }
`;

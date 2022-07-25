import styled from 'styled-components';

import s from '../styles/static';
import { transition } from '../styles/mixins';

export default styled.button`
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: none;
  outline: none;
  padding: ${s.size['3']} ${s.size['4']};
  color: ${({ theme }) => theme.gray800};
  border-radius: ${s.radius['lg']};
  cursor: pointer;

  transition: background-color 350ms ${transition.cubicBezier};

  &:hover {
    background: ${({ theme }) => theme.gray500};
  }

  &:focus, &:active {
    background: ${({ theme }) => theme.gray300};
  }

  &:disabled, &:disabled:hover {
    cursor: default;
    background: ${({ theme }) => theme.gray200};
  }
`;

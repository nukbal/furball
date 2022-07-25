import styled from 'styled-components';
import { transparentize } from 'polished';

import s from '../../styles/static';
import { transition, shadow } from '../../styles/mixins';

const Field = styled.div.attrs({ 'data-tauri-drag-region': true })`
  display: flex;
  align-items: flex-start;
  flex-direction: column;
  margin: ${s.size['4']} 0;
  flex: 1;

  & > h5 {
    display: block;
    font-weight: 500;
    font-size: 1.25rem;
    color: ${({ theme }) => theme.gray700};
    padding: 0;
    margin: 0;
    cursor: auto;
  }

  h5 small {
    font-size: 0.875rem;
    padding-left: ${s.size['2']};
  }

  input + small {
    font-weight: 500;
    font-size: 1rem;
    padding-left: ${s.size['2']};
  }

  input[type="number"], input[type="text"] {
    display: block;
    border-radius: ${s.radius['md']};
    padding: ${s.size['2']} ${s.size['4']};
    color: ${({ theme }) => theme.gray800};
    background-color: ${({ theme }) => theme.gray100};
    border: 1px solid ${({ theme }) => theme.gray300};
    transition: box-shadow 250ms ${transition.cubicBezier};
    margin: ${s.size['2']} 0;
    box-shadow: none;
    outline: none;

    &:hover, &:focus {
      border-color: ${({ theme }) => theme.blue500};
    }

    &:focus {
      box-shadow: 0 4px 6px -1px ${({ theme }) => transparentize(0.9, theme.blue500)};
    }
  }

  input[type='number'] {
    -moz-appearance:textfield;
  }

  input::-webkit-outer-spin-button,
  input::-webkit-inner-spin-button {
    -webkit-appearance: none;
  }
`;

export const HorizontalField = styled.div.attrs({ 'data-tauri-drag-region': true })`
  display: flex;
  align-items: center;
  justify-content: space-between;

  ${Field} + ${Field} {
    align-self: flex-start;
    margin-left: ${s.size['6']};
  }

  label + label {
    margin-left: ${s.size['2']};
  }
`;

export default Field;

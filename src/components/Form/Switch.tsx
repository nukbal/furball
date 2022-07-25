import styled from 'styled-components';

import s from '../../styles/static';

interface Props {
  name?: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}

export default function Switch({ name, checked, onChange }: Props) {
  return (
    <Input>
      <input type="checkbox" name={name} checked={checked} onChange={() => onChange(!checked)} />
      <Switcher aria-hidden="true" className={checked ? 'active' : ''}>
        <span />
      </Switcher>
    </Input>
  );
}

const Input = styled.label`
  position: relative;
  display: inline-block;
  border-radius: 2.25rem;
  border: none;
  transition: background-color 200ms ease-in-out;
  line-height: 0;
  cursor: pointer;
  margin: ${s.size['2']} 0;

  input {
    position: absolute;
    top: 0;
    left: 0;
    width: 1px;
    height: 1px;
    border: none;
    overflow: hidden;
    clip: rect(0px, 0px, 0px, 0px);
  }
`;

const Switcher = styled.span`
  display: inline-flex;
  align-items: center;
  justify-content: flex-start;
  width: 4rem;
  border-radius: 2rem;
  padding: 0.325rem;
  cursor: pointer;
  transition: background-color 200ms ease-in-out;
  background: ${({ theme }) => theme.gray400};

  span {
    display: block;
    width: 2rem;
    height: 2rem;
    border-radius: 2rem;
    pointer-events: none;
    background: #EFEFEF;
    transform: translateX(0);
    transition: transform 200ms ease-in-out;
  }

  &.active {
    background: ${({ theme }) => theme.green400};
  }

  &.active span {
    transform: translateX(2rem);
  }
`;

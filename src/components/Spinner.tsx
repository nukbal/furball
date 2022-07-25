import { SVGAttributes } from 'react';
import styled, { keyframes } from 'styled-components';

import s from '../styles/static';

type SizeKeys = keyof typeof s.size;

interface Props extends SVGAttributes<SVGElement> {
  size?: SizeKeys;
}

export default function Spinner({ size = 8, ...rest }: Props) {
  return (
    <Container xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" size={size} {...rest}>
      <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
    </Container>
  );
}

const spin = keyframes`
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
`;

const Container = styled.svg<{ size: SizeKeys }>`
  animation: ${spin} 1s linear infinite;
  color: ${({ theme }) => theme.gray800};

  height: ${({ size }) => s.size[size]};
  width: ${({ size }) => s.size[size]};

  circle {
    opacity: 0.25;
  }

  path {
    opacity: 0.75;
  }
`;

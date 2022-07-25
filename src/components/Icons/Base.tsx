import { SVGAttributes } from 'react';

interface Props extends SVGAttributes<SVGElement> {
  path: string;
}

export default function IconPage({ path, ...rest }: Props) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} {...rest}>
      <path strokeLinecap="round" strokeLinejoin="round" d={path} />
    </svg>
  );
}

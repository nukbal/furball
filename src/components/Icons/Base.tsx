import { splitProps } from 'solid-js';

interface Props extends SVGProps {
  path: string;
}

export default function IconPage(p: Props) {
  const [local, others] = splitProps(p, ['path']);
  return (
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width={2} {...others}>
      <path stroke-linecap="round" stroke-linejoin="round" d={local.path} />
    </svg>
  );
}

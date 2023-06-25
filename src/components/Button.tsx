import { JSX, splitProps, createMemo } from 'solid-js';
import type { Config } from 'tailwindcss';

interface Props extends JSX.HTMLAttributes<HTMLButtonElement> {
}

export default function Button(props: Props) {
  const [local, rest] = splitProps(props, ['class']);
  const className = createMemo(() => {
    return [
      'p-1',
      'rounded-lg',
      'hover:bg-gray-300',
      'dark:hover:bg-gray-700',
      local.class,
    ].filter(Boolean).join(' ');
  });

  return <button class={className()} {...rest}/>;
}

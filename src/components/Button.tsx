import { JSX, splitProps, createMemo } from 'solid-js';

interface Props extends JSX.HTMLAttributes<HTMLButtonElement> {
  color?: 'gray' | 'sky' | 'indigo';
}

export default function Button(props: Props) {
  const [local, rest] = splitProps(props, ['class', 'color']);
  const className = createMemo(() => {
    return [
      'p-1',
      'rounded-lg',
      `hover:bg-${local.color || 'gray'}-300`,
      `dark:hover:bg-${local.color || 'gray'}-700`,
      local.color ? `bg-${local.color}-500` : '',
      local.class,
    ].filter(Boolean).join(' ');
  });

  return <button class={className()} {...rest}/>;
}

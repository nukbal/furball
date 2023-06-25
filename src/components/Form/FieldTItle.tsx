import { splitProps } from 'solid-js';
import type { JSX } from 'solid-js';

interface Props extends Omit<JSX.HTMLAttributes<HTMLHeadingElement>, 'children'> {
  label: string;
}

export default function FieldTitle(props: Props) {
  const [local, rest] = splitProps(props, ['label', 'class'])
  return <h3 class={`text-gray-800 font-medium text-lg ${local.class}`} {...rest}>{local.label}</h3>;
}

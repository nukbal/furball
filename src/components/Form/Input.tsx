import { splitProps, type JSX } from 'solid-js';

export default function Input(props: JSX.InputHTMLAttributes<HTMLInputElement>) {
  const [local, rest] = splitProps(props, ['class']);
  return (
    <input
      class={`px-3 py-1 rounded-lg outline-none bg-gary-200 text-gray-700 ring-sky-500 caret-sky-500 focus:ring-2 dark:text-gray-300 dark:bg-gray-700 ${local.class || ''}`}
      {...rest}
    />
  );
}

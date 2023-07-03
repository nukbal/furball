import { Show } from 'solid-js';

interface RadioProps {
  class?: string;
  label: string;
  active: boolean;
  onChange: () => void;
  help?: string;
}

export default function RadioButton(props: RadioProps) {
  const className = () => {
    const defaultClass = 'relative flex flex-col flex-1 items-start p-3 rounded border border-gray-500';
    return [
      defaultClass,
      props.active ? 'bg-sky-700 border-sky-500 bg-opacity-25' : 'hover:bg-gray-600',
      props.class,
    ].filter(Boolean).join(' ');
  };
  return (
    <button class={className()} onClick={props.onChange} aria-label={props.label}>
      <span class="font-medium">{props.label}</span>
      <Show when={props.help}>
        <small class="mt-2 text-sm">{props.help}</small>
      </Show>
      <div
        class="absolute flex items-center justify-center top-3.5 right-3 rounded-full w-5 h-5 border-gray-500 border"
        classList={{ 'border-sky-500 bg-sky-500': props.active }}
      >
        <Show when={props.active}><i class="w-2.5 h-2.5 bg-gray-200 rounded-full dark:bg-gray-700" /></Show>
      </div>
    </button>
  );
}

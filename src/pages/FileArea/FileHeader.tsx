import { Show } from 'solid-js';
import file from 'models/file';

export default function FileHeader() {
  const filename = () => file().data.get(file().paths[0])?.filename ?? '';
  const size = () => file().data.size > 1 ? ` (+${file().data.size - 1})` : null;

  return (
    <header class="flex item-center pointer-events-none p-2 pl-4 mb-2" data-tauri-drag-region>
      <span class="block overflow-hidden text-ellipsis whitespace-nowrap" style={{ 'max-width': '425px' }}>
        {filename()}
      </span>
      <Show when={size()}>
        <span class="ml-1">{size()}</span>
      </Show>
    </header>
  );
}

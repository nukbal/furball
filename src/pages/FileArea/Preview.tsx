import { Show, createMemo } from 'solid-js';

import FileIcon from 'components/Icons/File';
import file from 'models/file';

export default function Preview() {
  const thumb = createMemo(() => {
    const firstPath = file().paths[0];
    if (!firstPath) return null;

    const fileData = file().data;
    const parent = fileData.get(firstPath);
    if (parent?.thumbnail) return parent?.thumbnail || null;
    if (parent?.is_dir) {
      const child = fileData.get(parent?.files[0]);
      return child?.thumbnail || null;
    }
  });

  return (
    <figure class="flex flex-1 items-center justify-center w-32 h-full mr-2 mb-2 pointer-events-none">
      <Show when={thumb()} fallback={<FileIcon class="w-24 h-24 mt-6" />}>
        <img
          class="object-contain object-center max-h-full max-w-full rounded-lg m-auto"
          src={`data:image/jpeg;base64,${thumb()}`}
          style={{ 'max-height': '240px' }}
        />
      </Show>
    </figure>
  );
}

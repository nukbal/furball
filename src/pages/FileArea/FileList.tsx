import { Show, For, Switch, Match, createMemo } from 'solid-js';

import FolderIcon from 'components/Icons/Folder';
import FilmIcon from 'components/Icons/Film';
import PhotoIcon from 'components/Icons/Photo';

import file, { fileData } from 'models/file';
import nonNullable from 'utils/nonNullable';
import parseFileSize from 'utils/parseFileSize';
import { Dynamic } from 'solid-js/web';

interface ItemProps {
  path: string;
  nest?: number;
}

function FileItem(p: ItemProps) {
  const target = () => file().data.get(p.path);
  const files = () => target()?.files ?? [];
  const nestedPadding = () => {
    if (p.nest === 1) return 'pl-4';
    if (p.nest === 2) return 'pl-8';
    return '';
  };
  const maxWidth = () => `${258 - (12 * (p.nest || 0))}px`;

  return (
    <Show when={target()}>
      {(data) => (
        <>
          <li class="flex items-center justify-between py-1 even:bg-gray-300 dark:even:bg-gray-600">
            <div class={`flex items-center ${nestedPadding()}`}>
              <MineIcon mineType={data().mime_type} />
              <abbr
                class="inline-block whitespace-nowrap overflow-hidden text-ellipsis no-underline leading-1"
                title={p.path}
                style={{ 'max-width': maxWidth() }}
              >
                {data().filename}
              </abbr>
            </div>
            <small class="leading-none">{data().is_dir ? data().files.length : parseFileSize(data().size)}</small>
          </li>
          <For each={files()}>
            {(item) => <FileItem path={item} nest={(p.nest ?? 0) + 1} />}
          </For>
        </>
      )}
    </Show>
  );
}

export default function FileList() {
  return (
    <>
      <ul class="flex-auto overflow-y-auto" style={{ 'max-height': '176px', 'min-height': '176px' }}>
        <For each={file().paths}>
          {(path) => <FileItem path={path} />}
        </For>
      </ul>
      <div class="flex justify-between items-center">
        <small>총 {file().data.size}개</small>
        <small>{parseFileSize(file().totalSize)}</small>
      </div>
    </>
  );
}

function MineIcon(p: { mineType: string; }) {
  const icon = () => {
    if (p.mineType === 'dir') return FolderIcon;
    if (p.mineType.startsWith('video')) return FilmIcon;
    return PhotoIcon;
  };
  return <Dynamic component={icon()} class="inline-block w-5 h-5 mr-1" />;
}

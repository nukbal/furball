import { onMount, onCleanup, Switch, Match } from 'solid-js';
import { message } from '@tauri-apps/plugin-dialog';
import { type UnlistenFn, listen } from '@tauri-apps/api/event';

import Spinner from 'components/Spinner';
import IconBase from 'components/Icons/Base';
import { setFileData } from 'models/file';
import mode, { setPageMode } from 'models/mode';

import getFileMeta from '../utils/getFileMeta';

interface DragDropEvent {
  paths: string[];
  position: { x: number; y: number; };
  id: number;
}

export default function DropArea() {
  let list: UnlistenFn[] = [];

  onMount(async () => {
    list.push(await listen('tauri://drag-enter', () => setPageMode('hover')));
    list.push(await listen('tauri://drag-leave', () => setPageMode('cancel')));
    list.push(await listen<DragDropEvent>('tauri://drag-drop', async (e) => {
      setPageMode('loading');
      try {
        const res = await getFileMeta(e.payload.paths)
        if (res.length) {
          setFileData(res);
        }
      } catch (e: any) {
        message(e, { kind: 'error', title: '에러' });
      }
      setPageMode('cancel');
    }));
  });

  onCleanup(() => {
    list.forEach((callback) => callback());
  });

  return (
    <Switch>
      <Match when={mode() === 'hover'}>
        <div class="absolute inset-0 z-10 rounded-xl bg-gray-200 dark:bg-gray-800" data-tauri-drag-region>
          <div class="absolute inset-10 flex items-center justify-center flex-col bg-slate-300 dark:bg-slate-700 border-gray-500 border-dashed border-4 rounded-xl p-4 text-center">
            <IconBase
              class="h-12 w-12 pointer-events-none"
              path="M5 19a2 2 0 01-2-2V7a2 2 0 012-2h4l2 2h4a2 2 0 012 2v1M5 19h14a2 2 0 002-2v-5a2 2 0 00-2-2H9a2 2 0 00-2 2v5a2 2 0 01-2 2z"
            />
            <p>내려놓아주세요 :)</p>
          </div>
        </div>
      </Match>
      <Match when={mode() === 'loading'}>
        <div class="absolute inset-0 z-10 rounded-xl bg-gray-200 dark:bg-gray-800" data-tauri-drag-region>
          <div class="absolute inset-10 flex items-center justify-center flex-col bg-slate-300 dark:bg-slate-700 border-gray-500 border-dashed border-4 rounded-xl p-4 text-center">
            <Spinner class="h-12 w-12 text-sky-300" />
            <p class="mt-2">파일을 보고있어요...</p>
          </div>
        </div>
      </Match>
    </Switch>
  );
}

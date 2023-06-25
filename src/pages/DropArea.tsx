import { onMount, onCleanup, Switch, Match } from 'solid-js';
import { message } from '@tauri-apps/api/dialog';
import { UnlistenFn } from '@tauri-apps/api/event';
import { appWindow } from '@tauri-apps/api/window';

import Spinner from 'components/Spinner';
import IconBase from 'components/Icons/Base';
import { setFileData } from 'models/file';
import mode, { setPageMode } from 'models/mode';

import getFileMeta from '../utils/getFileMeta';

export default function DropArea() {
  let unsub: UnlistenFn;

  onMount(() => {
    appWindow.onFileDropEvent((e) => {
      if (e.payload.type === 'drop') {
        const paths = e.payload.paths;
        setPageMode('loading');
        getFileMeta(paths)
          .then((res) => {
            if (res.length) {
              setFileData(res);
            }
            setPageMode('cancel');
          }).catch((e) => {
            message(e, { type: 'error', title: '에러' });
            setPageMode('cancel');
          });
      } else {
        setPageMode(e.payload.type);
      }
    }).then((cb) => {
      unsub = cb;
    });
  });

  onCleanup(() => {
    unsub?.();
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

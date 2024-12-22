import { createSignal, onCleanup, onMount } from 'solid-js';
import { Dynamic } from 'solid-js/web';
import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event'
import { message } from '@tauri-apps/plugin-dialog';

import Spinner from 'components/Spinner';
import RefreshIcon from 'components/Icons/Refresh';
import SwapIcon from 'components/Icons/Swap';

import file, { reset } from 'models/file';
import { type ConfigType, setConfig } from 'models/config';

type ProcessStatusType = 'none' | 'loading' | 'error';

interface Props {
  config: ConfigType;
}

export default function FileFooter({ config }: Props) {
  const [status, setStatus] = createSignal<ProcessStatusType>('none');
  const [prog, setProg] = createSignal(0);
  const [total, setTotal] = createSignal(0);
  let unsub: UnlistenFn;

  onMount(() => {
    listen('progress', () => {
      setProg((prev) => prev + 1);
    }).then((cb) => {
      unsub = cb;
    });
  });

  onMount(() => {
    let t = 0
    file().data.forEach((f) => {
      if (f.is_dir) {
        t += f.files.length;
      } else if (f.mime_type === 'application/pdf') {
        t += f.len;
      } else {
        t += 1;
      }
    });
    setTotal(t);
  });

  onCleanup(() => {
    unsub?.();
  });

  const handleProcess = async () => {
    setStatus('loading');
    setProg(0);
    setConfig(config);

    try {
      await invoke('process_files', { filenames: file().paths, conf: config });
      setStatus('none');
    } catch (e: any) {
      message(e ?? 'error', { kind: 'error', title: '에러' });
      setStatus('error');
    }
    setProg(0);
  };

  const isLoading = () => status() === 'loading';

  const processMessage = () => {
    if (isLoading()) {
      if (prog() > 0) {
        const percent = Math.round((prog() / total()) * 100);
        return `${percent}%`;
      }
      return '처리중...';
    }
    return '처리하기';
  };

  return (
    <footer class="flex items-center justify-between px-4 pt-2" data-tauri-drag-region>
      <button class="p-2 rounded-lg hover:bg-gray-300 dark:hover:bg-gray-700" onClick={() => reset()} disabled={isLoading()}>
        <RefreshIcon class="w-6 h-6" />
      </button>
      <button
      class="flex items-center rounded-lg bg-sky-500 py-2 px-5 text-white hover:bg-sky-700 disabled:bg-gray-500"
      onClick={handleProcess}
      disabled={isLoading()}
      >
        <Dynamic component={isLoading() ? Spinner : SwapIcon} class="mr-2 w-6 h-6" />
        <span>{processMessage()}</span>
      </button>
    </footer>
  );
}

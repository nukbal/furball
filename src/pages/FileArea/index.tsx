import { createSignal } from 'solid-js';
import { Dynamic } from 'solid-js/web';
import { invoke } from '@tauri-apps/api/tauri';
import { message } from '@tauri-apps/api/dialog';

import Spinner from 'components/Spinner';
import RefreshIcon from 'components/Icons/Refresh';
import ConfigIcon from 'components/Icons/Config';

import file, { reset } from 'models/file';
import config from 'models/config';
import { setPageMode } from 'models/mode';
import SwapIcon from 'components/Icons/Swap';

import Preview from './Preview';
import FileList from './FileList';
import FileHeader from './FileHeader';
import FooterInfo from './FooterInfo';

type ProcessStatusType = 'none' | 'loading' | 'error';

export default function FileStatus() {
  const [status, setStatus] = createSignal<ProcessStatusType>('none');

  const handleProcess = async () => {
    setStatus('loading');
    try {
      await invoke('process_files', { filenames: file().paths, conf: config });
      setStatus('none');
    } catch (e: any) {
      message(e ?? 'error', { type: 'error', title: '에러' });
      setStatus('error');
    }
  };

  const navigateConfig = () => setPageMode('config');

  const isLoading = () => status() === 'loading';

  return (
    <>
      <FileHeader />
      <div class="flex items-start px-2" data-tauri-drag-region>
        <Preview />
        <div class="flex-auto px-2" style={{ 'max-width': '65%' }} data-tauri-drag-region>
          <FileList />
          <footer class="flex items-center justify-between" data-tauri-drag-region>
            <div class="inline-flex items-center select-none rounded-lg space-x-px">
              <button
                class="flex items-center w-26 rounded-s-lg bg-sky-500 py-2 px-3 text-white hover:bg-sky-700"
                onClick={handleProcess}
                disabled={isLoading()}
              >
                <Dynamic
                  component={isLoading() ? Spinner : SwapIcon}
                  class="mr-2 w-6 h-6"
                />
                <span>{isLoading() ? '처리중...' : '처리하기'}</span>
              </button>
              <button class="p-2 bg-emerald-500 hover:bg-emerald-700 rounded-r-lg" aria-label="설정하기" onClick={navigateConfig} disabled={isLoading()}>
                <ConfigIcon class="w-6 h-6 text-white" />
              </button>
            </div>
            <button class="p-2 rounded-lg hover:bg-gray-300 dark:hover:bg-gray-700" onClick={() => reset()}>
              <RefreshIcon class="w-6 h-6" />
            </button>
          </footer>
        </div>
      </div>
      <FooterInfo />
    </>
  );
}

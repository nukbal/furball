import { Switch, Match, createEffect, Show } from 'solid-js';
import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window';

import CloseIcon from 'components/Icons/Close';
import Button from 'components/Button';
import mode from 'models/mode';
import file from 'models/file';
import isDarkMode from 'models/dark';

import EmptyStatus from './EmptyStatus';
import FileArea from './FileArea';
import Credit, { CreditButton } from './Credit';
import DropArea from './DropArea';

export default function App() {
  const window = getCurrentWindow();

  createEffect(() => {
    if (!isDarkMode()) {
      document.documentElement.classList.remove('dark');
    } else {
      document.documentElement.classList.add('dark');
    }
  });

  createEffect(() => {
    const val = page();
    if (val === 'file') {
      window.setSize(new LogicalSize(880, 650));
    } else {
      window.setSize(new LogicalSize(580, 325));
    }
  });

  const page = () => {
    const val = mode();
    if (file().data.size > 0 && val !== 'credit') return 'file';
    if (val === 'hover' || val === 'loading') return 'cancel';
    return val;
  };

  return (
    <div class="relative min-w-full min-h-full rounded-xl bg-gray-200 dark:text-gray-300 dark:bg-gray-800" data-tauri-drag-region>
      <Switch>
        <Match when={page() === 'cancel'}>
          <EmptyStatus />
        </Match>
        <Match when={page() === 'file'}>
          <FileArea />
        </Match>
        <Match when={page() === 'credit'}>
          <Credit />
        </Match>
      </Switch>
      <DropArea />
      <Button class="absolute right-2 top-2" onClick={window.close}>
        <CloseIcon class="h-6 w-6" />
      </Button>
      <Show when={page() !== 'file'}>
        <CreditButton />
      </Show>
    </div>
  );
}

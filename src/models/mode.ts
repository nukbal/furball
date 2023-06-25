import { createSignal } from 'solid-js';

type AppPages = 'cancel' | 'loading' | 'hover' | 'config' | 'credit';

const [mode, setMode] = createSignal<AppPages>('cancel');

export default mode;

export function setPageMode(mode: AppPages) {
  setMode(mode);
}

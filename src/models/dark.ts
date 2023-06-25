import { createSignal } from 'solid-js';

const STORAGE_KEY = 'dark';
const COLOR_SCHEME_QUERY = '(prefers-color-scheme: dark)';
const IS_SSR = typeof window === 'undefined';

function getCurrentModeStatus() {
  if (IS_SSR) return false;
  const status = window.localStorage.getItem(STORAGE_KEY);

  if (status) return status === '1';
  return window.matchMedia?.(COLOR_SCHEME_QUERY).matches || false;
}

const [isDarkMode, setDarkMode] = createSignal(getCurrentModeStatus());

export default isDarkMode;

export function toggleDarkMode() {
  const value = isDarkMode();
  window.localStorage.setItem(STORAGE_KEY, value ? '0' : '1');
  setDarkMode(!value);
}

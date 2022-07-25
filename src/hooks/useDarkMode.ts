import { useCallback } from 'react';
import create from 'zustand';

const STORAGE_KEY = 'dark';
const COLOR_SCHEME_QUERY = '(prefers-color-scheme: dark)';
const IS_SSR = typeof window === 'undefined';

function getCurrentModeStatus() {
  if (IS_SSR) return false;
  const status = window.localStorage.getItem(STORAGE_KEY);

  if (status) return status === '1';
  return window.matchMedia?.(COLOR_SCHEME_QUERY).matches || false;
}

interface DarkModeState {
  isDarkMode: boolean;
}
const useStore = create<DarkModeState>(() => ({ isDarkMode: getCurrentModeStatus() }));
function selectDarkModeState(state: DarkModeState) {
  return state.isDarkMode;
}

export function toggleDarkMode() {
  useStore.setState((state) => {
    window.localStorage.setItem(STORAGE_KEY, state.isDarkMode ? '0' : '1');
    return { isDarkMode: !state.isDarkMode };
  });
}

export default function useDarkMode() {
  const isDarkMode = useStore(selectDarkModeState);
  return {
    isDarkMode,
    toggle: useCallback(() => toggleDarkMode(), []),
  };
}

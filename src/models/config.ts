import { createStore } from 'solid-js/store';
import { downloadDir } from '@tauri-apps/api/path';

export interface ConfigType {
  // general
  mode: 'overwrite' | 'path';
  path: string;
  suffix: string;

  // images
  preserve: boolean;
  width: number;
  quality: number;
  gif: 'webp' | 'mp4';
  ai: boolean;

  dir_mode: 'none' | 'pdf' | 'zip';
}

export const defaultValues = {
  mode: 'path',
  path: '',
  suffix: '',

  preserve: false,
  width: 1440,
  quality: 88,
  gif: 'mp4',
  ai: true,

  dir_mode: 'none',
} as ConfigType;

function parseCacheString(str: string | null) {
  const json = str ? JSON.parse(str) : {};
  const res = { ...defaultValues } as ConfigType;
  const validKeys = Object.keys(defaultValues);
  validKeys.forEach((key) => {
    const value = json[key];
    // @ts-ignore
    res[key] = value !== undefined ? value : res[key];
  });
  return res;
}

const [state, setState] = createStore<ConfigType>(defaultValues);

export default state;

export async function bootstrap() {
  const cache = localStorage.getItem('config');
  if (cache) {
    setState(parseCacheString(cache));
  } else {
    setState('path', await downloadDir());
  }
}

export function get() {
  return state;
}

export async function setConfig(value: ConfigType) {
  localStorage.setItem('config', JSON.stringify(value));
  setState(value);
}

import { downloadDir } from '@tauri-apps/api/path';
import { invoke } from '@tauri-apps/api/tauri';
import create from 'zustand';

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

  dir_mode: 'none',
} as ConfigType;

export const useConfig = create<ConfigType>(() => defaultValues);

function parseCacheString(str: string | null) {
  const json = str ? JSON.parse(str) : {};
  const res = {} as ConfigType;
  const validKeys = Object.keys(defaultValues) as (keyof ConfigType)[];
  validKeys.forEach((key) => {
    const value = json[key];
    // @ts-ignore
    res[key] = value !== undefined ? value : defaultValues[key];
  });
  return res;
}

export async function bootstrap() {
  defaultValues.path = await downloadDir();
  const cache = localStorage.getItem('config');
  useConfig.setState(parseCacheString(cache));
  if (cache) {
    await invoke('write_config', { value: cache });
  }
}

export function get() {
  return useConfig.getState();
}

export async function setConfig(value: ConfigType) {
  useConfig.setState(value);

  const str = JSON.stringify(value);
  localStorage.setItem('config', str);
  await invoke('write_config', { value: str });
}

import { invoke } from '@tauri-apps/api/core';

export async function processImage(filenames: string[]) {
  const res = await invoke('process_files', { filenames });
  return res;
}

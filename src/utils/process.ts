import { invoke } from '@tauri-apps/api/tauri';

export async function processImage(filenames: string[]) {
  const res = await invoke('process_files', { filenames });
  return res;
}

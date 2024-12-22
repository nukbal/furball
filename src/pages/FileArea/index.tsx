import { createStore } from 'solid-js/store';

import config from 'models/config';

import Preview from './Preview';
import FileList from './FileList';
import FileHeader from './FileHeader';
import ConfigArea from './Config';
import FileFooter from './Footer';

export default function FileStatus() {
  const [form, setForm] = createStore(config);

  return (
    <>
      <FileHeader />
      <div class="flex items-start px-2" data-tauri-drag-region>
        <Preview />
        <div class="flex-auto px-2" data-tauri-drag-region>
          <FileList />
        </div>
      </div>
      <ConfigArea form={form} onChange={setForm} />
      <FileFooter config={form} />
    </>
  );
}

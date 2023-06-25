import { open, message } from '@tauri-apps/api/dialog';
import { downloadDir } from '@tauri-apps/api/path';

import IconBase from 'components/Icons/Base';
import Button from 'components/Button';
import { setFileData } from 'models/file';
import mode, { setPageMode } from 'models/mode';

import getFileMeta from '../utils/getFileMeta';
import { VALID_IMAGE_EXT, VALID_VIDEO_EXT } from '../const';

export default function EmptyStatus() {
  const handleSelect = async () => {
    try {
      const downloadPath = await downloadDir();
      const filePaths = await open({
        defaultPath: downloadPath,
        multiple: true,
        // directory: true,
        filters: [
          { name: 'Image', extensions: VALID_IMAGE_EXT },
          { name: 'Video', extensions: VALID_VIDEO_EXT },
        ],
      });
      if (filePaths !== null) {
        const paths = Array.isArray(filePaths) ? filePaths : [filePaths];
        setPageMode('loading');
        const res = await getFileMeta(paths);
        setFileData(res);
      }
      setPageMode('cancel');
    } catch (e: any) {
      message(e.message);
      setPageMode('cancel');
    }
  };

  return (
    <div class="absolute inset-10 flex items-center justify-center flex-col bg-slate-300 dark:bg-slate-700 border-gray-500 border-dashed border-4 rounded-xl p-4 text-center" data-tauri-drag-region>
      <IconBase
        class="h-12 w-12 pointer-events-none"
        path="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"
      />
      <p>
        이미지, 동영상, 폴더 등<br />
        처리하고싶은 파일을 끌어다주세요
      </p>
      <section class="border-b border-gray-500 my-4 text-sm w-5/6" style={{ 'line-height': '0.1em' }}>
        <span class="px-5 bg-gray-300 dark:bg-gray-700">혹은</span>
      </section>
      <Button class="px-4 py-2 text-white bg-sky-500 hover:!bg-sky-700" onClick={handleSelect}>
        파일 고르기
      </Button>
    </div>
  );
}

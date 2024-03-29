import type { SetStoreFunction } from 'solid-js/store';
import { open } from '@tauri-apps/api/dialog';

import Field, { HorizontalField } from 'components/Form/Field';
import Button from 'components/Button';
import Radio from 'components/Form/Radio';

import type { ConfigType } from 'models/config';

interface Props {
  value: ConfigType;
  onChange: SetStoreFunction<ConfigType>;
}

export default function GeneralConfig({ value, onChange }: Props) {
  const handleChangeDir = async () => {
    const res = await open({ directory: true, multiple: false });
    if (res) {
      onChange('path', Array.isArray(res) ? res[0] : res);
    }
  };

  return (
    <div data-tauri-drag-region>
      <Field label="가능하면 덮어쓰기" help="작업한 파일이 같은이름의 같은확장자일시, 덮어씁니다.">
        <HorizontalField class="space-x-1 w-4/5">
          <Radio label="유지하기" active={value.mode === 'path'} onChange={() => onChange('mode', 'path')} />
          <Radio label="덮어쓰기" active={value.mode === 'overwrite'} onChange={() => onChange('mode', 'overwrite')} />
        </HorizontalField>
      </Field>
      <Field label="저장 장소" help="폴더처리등 새로운 파일이 생성되는 경우에도">
        <HorizontalField>
          <span>{value.path}</span>
          <Button class="px-3 py-1.5" color="sky" onClick={handleChangeDir}>폴더 바꾸기</Button>
        </HorizontalField>
      </Field>
      <Field label="처리후 파일 접미사" help="[파일이름_접미사.ext] 같은 형태로 접미사를 지정합니다.">
        <span>{value.suffix}</span>
      </Field>
    </div>
  );
}

import type { SetStoreFunction } from 'solid-js/store';

import Field from 'components/Form/Field';
import Radio from 'components/Form/Radio';
import type { ConfigType } from 'models/config';

interface Props {
  value: ConfigType;
  onChange: SetStoreFunction<ConfigType>;
}

export default function DirConfig(props: Props) {

  return (
    <div>
      <Field label="폴더 처리 방식">
        <div class="space-y-2">
          <Radio
            class="w-4/5"
            label="개별처리"
            help="폴더 내부의 파일을 개별처리합니다."
            active={props.value.dir_mode === 'none'}
            onChange={() => props.onChange('dir_mode', 'none')}
          />
          <Radio
            class="w-4/5"
            label="PDF생성"
            help="해당 폴더가 이미지만 포함할 경우, pdf로 생성합니다."
            active={props.value.dir_mode === 'pdf'}
            onChange={() => props.onChange('dir_mode', 'pdf')}
          />
          <Radio
            class="w-4/5"
            label="압축하기"
            help="해당 폴더의 미디어파일을 zip파일로 압축합니다."
            active={props.value.dir_mode === 'zip'}
            onChange={() => props.onChange('dir_mode', 'zip')}
          />
        </div>
      </Field>
    </div>
  );
}

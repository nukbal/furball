import type { SetStoreFunction } from 'solid-js/store';

import Field from 'components/Form/Field';
import type { ConfigType } from 'models/config';

interface Props {
  value: ConfigType;
  onChange: SetStoreFunction<ConfigType>;
}

export default function DirConfig(props: Props) {

  return (
    <div>
      <Field label="폴더 처리 방식">
        <div class="space-y-1">
          <RadioButton
            label="개별처리"
            help="폴더 내부의 파일을 개별처리합니다."
            active={props.value.dir_mode === 'none'}
            onChange={() => props.onChange('dir_mode', 'none')}
          />
          <RadioButton
            label="PDF생성"
            help="해당 폴더가 이미지만 포함할 경우, pdf로 생성합니다."
            active={props.value.dir_mode === 'pdf'}
            onChange={() => props.onChange('dir_mode', 'pdf')}
          />
          <RadioButton
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

interface RadioProps {
  label: string;
  help: string;
  active: boolean;
  onChange: () => void;
}

function RadioButton(props: RadioProps) {
  const className = () => {
    const defaultClass = 'flex flex-col items-start p-4 w-full max-w-64 rounded border-sky-700';
    return [defaultClass, props.active ? 'bg-sky-700' : 'hover:bg-gray-600'].join(' ');
  };
  return (
    <button class={className()} onClick={props.onChange}>
      <span>{props.label}</span>
      <small class="mt-2 text-sm">{props.help}</small>
    </button>
  );
}

// const RadioButton = styled(Radio)`
//   display: flex;
//   flex-direction: column;
//   align-items: flex-start;
//   padding: ${s.size['4']};
//   width: 100%;
//   max-width: 25rem;
  
//   small {
//     margin-top: ${s.size['2']};
//   }
// `;

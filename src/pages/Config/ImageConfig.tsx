import { Show } from 'solid-js';
import type { SetStoreFunction } from 'solid-js/store';

import Field, { HorizontalField } from 'components/Form/Field';
import Input from 'components/Form/Input';
import Switch from 'components/Form/Switch';
// import Radio from 'components/Form/Radio';

import type { ConfigType } from 'models/config';

interface Props {
  value: ConfigType;
  onChange: SetStoreFunction<ConfigType>;
}

export default function ImageConfig(props: Props) {
  return (
    <div>
      <Field label="압축방식">
        <span>MozJpeg</span>
      </Field>
      <Field label="압축 퀄리티" sub="(0-100)">
        <Input
          type="number"
          value={props.value.quality}
          onChange={(e) => {
            const val = parseInt(e.target.value, 10);
            if (Number.isNaN(val)) return;
            props.onChange('quality', val);
          }}
        />
      </Field>
      <Field label="원본 크기 보존하기" help="원본크가 그대로 압축만 진행합니다">
        <span>{props.value.preserve ? 'O' : 'X'}</span>
      </Field>
      <Show when={!props.value.preserve}>
        <Field label="목표 너비" help="가로 비율이 더 큰 이미지는 세로기준으로 조절합니다">
          <Input
            type="number"
            value={props.value.width}
            onChange={(e) => {
              const val = parseInt(e.target.value, 10);
              if (Number.isNaN(val)) return;
              props.onChange('width', val);
            }}
          />
        </Field>
        <Field label="AI업스케일링" help="해당 이미지가 목표너비보다 작을경우, ai 스케일링을 시도합니다">
          <Switch checked={props.value.ai} onChange={(val) => props.onChange('ai', val)} />
        </Field>
      </Show>
      <Field label="GIF 처리방식">
        <span>{props.value.gif}</span>
      </Field>
    </div>
  );
}

import { Show } from 'solid-js';
import type { SetStoreFunction } from 'solid-js/store';

import Field, { HorizontalField } from 'components/Form/Field';
import Input from 'components/Form/Input';
import Switch from 'components/Form/Switch';
import Radio from 'components/Form/Radio';

import type { ConfigType } from 'models/config';

interface Props {
  value: ConfigType;
  onChange: SetStoreFunction<ConfigType>;
}

export default function ImageConfig(props: Props) {
  const image_help = () => {
    if (props.value.image_mode === 'resize') return '지정한 사이즈로 일괄처리합니다';
    if (props.value.image_mode === 'shrink') return '이미지가 지정한 사이즈보다 클 경우에만 처리합니다 작은사이즈는 압축처리만 진행합니다';
    return '원본크기를 유지하면서 압축만 진행합니다';
  };

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
      <Field label="원본 크기 보존하기">
        <HorizontalField class="space-x-1">
          <Radio label="보존하기" active={props.value.image_mode === 'preserve'} onChange={() => props.onChange('image_mode', 'preserve')} />
          <Radio label="크기 지정하기" active={props.value.image_mode === 'resize'} onChange={() => props.onChange('image_mode', 'resize')} />
          <Radio label="사이즈 줄이기" active={props.value.image_mode === 'shrink'} onChange={() => props.onChange('image_mode', 'shrink')} />
        </HorizontalField>
        <small class="block text-xs ml-1 mt-2 text-gray-400">{image_help()}</small>
        <Show when={props.value.image_mode === 'resize' || props.value.image_mode === 'shrink'}>
          <div class="bg-gray-600 bg-opacity-10 rounded-lg p-4 mt-2">
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
            <Show when={props.value.image_mode === 'resize'}>
              <Field class="-mb-1" label="AI업스케일링" help="해당 이미지가 목표너비보다 작을경우, ai 스케일링을 시도합니다">
                <Switch checked={props.value.ai} onChange={(val) => props.onChange('ai', val)} />
              </Field>
            </Show>
          </div>
        </Show>
      </Field>
      <Field label="GIF 처리방식">
        <HorizontalField class="space-x-1">
          <Radio label="GIF" active={props.value.gif === 'gif'} onChange={() => props.onChange('gif', 'gif')} />
          <Radio label="MP4" active={props.value.gif === 'mp4'} onChange={() => props.onChange('gif', 'mp4')} />
          <Radio label="WEBP" active={props.value.gif === 'webp'} onChange={() => props.onChange('gif', 'webp')} />
        </HorizontalField>
      </Field>
    </div>
  );
}

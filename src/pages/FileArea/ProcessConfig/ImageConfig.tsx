import { Tab } from '@headlessui/react';
import { useFormContext, Controller } from 'react-hook-form';

import Field, { HorizontalField } from '../../../components/Form/Field';
import Switch from '../../../components/Form/Switch';
import Radio from '../../../components/Form/Radio';

export default function GeneralConfig() {
  const { control, watch } = useFormContext();

  const preserved = watch('preserve');

  return (
    <Tab.Panel>
      <HorizontalField>
        <Field>
          <h5>압축방식</h5>
          <span>MozJpeg</span>
        </Field>
        <Field>
          <h5>
            압축 퀄리티
            <small>(0-100)</small>
          </h5>
          <Controller
            name="quality"
            control={control}
            render={({ field }) => (
              <input type="number" {...field} />
            )}
          />
        </Field>
      </HorizontalField>
      <HorizontalField>
        <Field>
          <h5>원본 크기 보존하기</h5>
          <Controller
            name="preserve"
            control={control}
            render={({ field }) => (
              <Switch
                checked={field.value}
                onChange={field.onChange}
              />
            )}
          />
          <small>원본크가 그대로 압축만 진행합니다</small>
        </Field>
        {!preserved && (
          <Field>
            <h5>
              목표 너비
            </h5>
            <HorizontalField>
              <Controller
                name="width"
                control={control}
                render={({ field }) => (
                  <input type="number" {...field} />
                )}
              />
              <small>px</small>
            </HorizontalField>
            <small>가로 비율이 더 큰 이미지는 세로기준으로 조절합니다.</small>
          </Field>
        )}
      </HorizontalField>
      <Field>
        <h5>GIF 처리방식</h5>
        <Controller
          name="gif"
          control={control}
          render={({ field: { name, onChange, value } }) => (
            <HorizontalField>
              <Radio name={name} value="webp" onChange={onChange} checked={value === 'webp'}>
                webp
              </Radio>
              <Radio name={name} value="mp4" onChange={onChange} checked={value === 'mp4'}>
                mp4
              </Radio>
            </HorizontalField>
          )}
        />
      </Field>
    </Tab.Panel>
  );
}

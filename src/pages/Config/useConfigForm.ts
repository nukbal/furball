import { useForm } from 'react-hook-form';
import { yupResolver } from '@hookform/resolvers/yup';
import * as y from 'yup';

import * as config from '../../models/config';

const schema = y.object({
  mode: y.string().oneOf(['overwrite', 'path']),
  path: y.string(),
  suffix: y.string(),

  preserve: y.boolean(),
  width: y.number(),
  quality: y.number().min(0).max(100),
  gif: y.string().oneOf(['mp4', 'webp']),

  dir_mode: y.string().oneOf(['none', 'pdf', 'zip']),
});
const resolver = yupResolver(schema);

export default function useConfigForm() {
  return useForm<config.ConfigType>({
    resolver,
    defaultValues: config.get(),
  });
}

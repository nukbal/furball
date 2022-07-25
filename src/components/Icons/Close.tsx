import { SVGAttributes } from 'react';

import BaseIcon from './Base';

export default function CloseIcon(props: SVGAttributes<SVGElement>) {
  return <BaseIcon path="M6 18L18 6M6 6l12 12" {...props} />
}

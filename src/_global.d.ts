
declare type SVGProps = import('solid-js').JSX.SvgSVGAttributes<SVGSVGElement>;

declare interface InnerFileType {
  path: string;
  filename: string;
  is_dir: boolean;
  mime_type: string;
  status: 'loading' | 'done' | 'error';
  files: InnerFileType[];
  thumbnail: string | null;
  size: number;
}

declare interface FileType {
  path: string;
  filename: string;
  is_dir: boolean;
  mime_type: string;
  status: 'loading' | 'done' | 'error';
  files: string[];
  thumbnail: string | null;
  size: number;
}

declare type StatusType = 'cancel' | 'hover' | 'drop' | 'error' | 'loading';

declare type TWColorType = 'gray' | 'yellow' | 'green' | 'blue' | 'indigo' | 'purple' | 'pink' | 'sky';

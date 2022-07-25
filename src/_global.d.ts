declare interface AppTheme {
  isDark: boolean;
  gray50: string;
  gray75: string;
  gray100: string;
  gray200: string;
  gray300: string;
  gray400: string;
  gray500: string;
  gray600: string;
  gray700: string;
  gray800: string;
  gray900: string;

  blue400: string;
  blue500: string;
  blue600: string;
  blue700: string;

  red400: string;
  red500: string;
  red600: string;
  red700: string;

  orange400: string;
  orange500: string;
  orange600: string;
  orange700: string;

  green400: string;
  green500: string;
  green600: string;
  green700: string;
}

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

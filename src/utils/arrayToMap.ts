

export default function arrayToMap<T>(arr: T[], key: keyof T) {
  // @ts-ignore
  return arr.reduce((acc, cur) => ({ ...acc, [cur[key]]: cur }), {}) as { [key: string]: T };
}

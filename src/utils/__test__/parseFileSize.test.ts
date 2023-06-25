import { expect, it, describe } from 'bun:test';

import parseFileSize from '../parseFileSize';

describe('parseFileSize', () => {
  it('KB', () => {
    const unit = 1024;
    expect(parseFileSize(0.9 * unit)).toBe('0.9 KB');
    expect(parseFileSize(unit)).toBe('1 KB');
    expect(parseFileSize(4 * unit)).toBe('4 KB');
    expect(parseFileSize(8 * unit)).toBe('8 KB');
  });
  
  it('MB', () => {
    const unit = 1024 * 1024;
    expect(parseFileSize(0.5 * unit)).toBe('512 KB');
    expect(parseFileSize(1.2 * unit)).toBe('1.2 MB');
    expect(parseFileSize(4.5 * unit)).toBe('4.5 MB');
    expect(parseFileSize(125 * unit)).toBe('125 MB');
  });
  
  it('GB', () => {
    const unit = 1024 * 1024 * 1024;
    expect(parseFileSize(0.5 * unit)).toBe('512 MB');
    expect(parseFileSize(1.2 * unit)).toBe('1.2 GB');
    expect(parseFileSize(4.5 * unit)).toBe('4.5 GB');
    expect(parseFileSize(125 * unit)).toBe('125 GB');
  });
});

import { HOME_URL, SEARCH_URL } from '../constants/AppConstants';

export function normalizeAddress(input: string): string {
  const value: string = input.trim();
  if (value.length === 0) {
    return HOME_URL;
  }
  if (value.includes('://')) {
    return value;
  }
  if (value.includes('.') && !value.includes(' ')) {
    return `https://${value}`;
  }
  return `${SEARCH_URL}${encodeURIComponent(value)}`;
}

export function displayHost(url: string): string {
  const match: RegExpMatchArray | null = url.match(/^[a-z]+:\/\/([^/]+)/i);
  return match === null ? url : match[1];
}

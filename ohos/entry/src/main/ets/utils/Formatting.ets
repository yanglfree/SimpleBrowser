const WEEKDAYS: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];

/** `YYYY-MM-DD` in local time — the key for a day of blocking statistics. */
export function dayKey(date: Date): string {
  const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
  const day: string = `${date.getDate()}`.padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

export function todayKey(): string {
  return dayKey(new Date());
}

/** Keys for today and the six days before it, newest first. */
export function recentDayKeys(days: number): string[] {
  const keys: string[] = [];
  const now: number = Date.now();
  for (let index = 0; index < days; index++) {
    keys.push(dayKey(new Date(now - index * 86400000)));
  }
  return keys;
}

/** e.g. `8月5日 星期三` */
export function formatDate(date: Date): string {
  return `${date.getMonth() + 1}月${date.getDate()}日 ${WEEKDAYS[date.getDay()]}`;
}

/** Picks the start-page greeting resource for the current hour. */
export function greetingResource(hour: number): Resource {
  if (hour < 5) {
    return $r('app.string.greeting_night');
  }
  if (hour < 11) {
    return $r('app.string.greeting_morning');
  }
  if (hour < 13) {
    return $r('app.string.greeting_noon');
  }
  if (hour < 18) {
    return $r('app.string.greeting_afternoon');
  }
  if (hour < 23) {
    return $r('app.string.greeting_evening');
  }
  return $r('app.string.greeting_night');
}

/** Thousands separators, so `1284` reads as `1,284` like the design. */
export function groupNumber(value: number): string {
  const digits: string = `${Math.max(0, Math.round(value))}`;
  let out: string = '';
  for (let index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 === 0) {
      out += ',';
    }
    out += digits.charAt(index);
  }
  return out;
}

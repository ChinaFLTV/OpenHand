type ClassNameValue = string | null | undefined | false;

export function classNames(...values: ClassNameValue[]): string {
  return values
    .flatMap((value) => (value ? value.trim().split(/\s+/) : []))
    .filter(Boolean)
    .join(' ');
}

declare module "asserts" {
export function assertEquals<T = any>(a: T, b: T): void;
export function assertNotEquals<T = any>(a: T, b: T): void;
export function assertThrows(fn: () => any): void;
}
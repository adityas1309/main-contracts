declare module "clarinet" {
export interface Account { address: string; balance?: bigint; }


export interface ReceiptResult {
expectOk(): any;
expectErr(): any;
expectBool(b?: boolean): any;
expectUint(): number;
expectSome(): any;
expectNone(): any;
expectTuple(): any;
}


export interface BlockReceipt {
result: ReceiptResult;
}


export interface Block {
receipts: BlockReceipt[];
}


export interface Chain {
mineBlock(txs: any[]): Block;
getMapEntry(contract: string, map: string, key: any): any;
callReadOnlyFn(contract: string, fn: string, args: any[], sender: string): any;
getAssetsMap(): Map<string, Map<string, bigint>>;
}


export const Clarinet: {
test(opts: { name: string; fn: (chain: Chain, accounts: Map<string, Account>) => Promise<void> | void }): void;
};


export const Tx: {
contractCall(contract: string, fn: string, args: any[], sender: string): any;
};


export const types: {
principal(addr: string): any;
ascii(s: string): any;
utf8(s: string): any;
uint(n: number): any;
bool(b: boolean): any;
none(): any;
};


export type ChainType = Chain;
}
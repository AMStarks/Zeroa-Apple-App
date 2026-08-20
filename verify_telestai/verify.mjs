import bip39 from 'bip39';
import BIP32Factory from 'bip32';
import * as ecc from 'tiny-secp256k1';
import bs58check from 'bs58check';
import crypto from 'crypto';

const bip32 = BIP32Factory(ecc);
const mnemonic = process.argv.slice(2).join(' ').trim();
if (!mnemonic) { console.error('Provide mnemonic as argument'); process.exit(1); }
const seed = await bip39.mnemonicToSeed(mnemonic, '');
const root = bip32.fromSeed(seed);
const node = root.derivePath("m/44'/175'/0'/0/0");
const pubkey = node.publicKey;
const sha256 = crypto.createHash('sha256').update(pubkey).digest();
const ripemd160 = crypto.createHash('ripemd160').update(sha256).digest();
const version = Buffer.from([0x3C]);
const payload = Buffer.concat([version, ripemd160]);
const address = bs58check.encode(payload);
console.log(JSON.stringify({ address }, null, 2));

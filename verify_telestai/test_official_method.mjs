import bip39 from 'bip39';
import BIP32Factory from 'bip32';
import * as ecc from 'tiny-secp256k1';
import bs58check from 'bs58check';
import crypto from 'crypto';

const bip32 = BIP32Factory(ecc);
const mnemonic = process.argv.slice(2).join(' ').trim() || 'heart nephew reason atom march glue';

console.log('Testing with OFFICIAL Telestai method:');
console.log('Mnemonic:', mnemonic);
console.log('Target address: ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ\n');

(async () => {
    const seed = await bip39.mnemonicToSeed(mnemonic, '');
    const root = bip32.fromSeed(seed);
    
    // OFFICIAL Telestai method from telestai-key package:
    // - BIP44 coin type: 10117 (NOT 175 or 19165!)
    // - Version byte: 0x42
    // - Path: m/44'/10117'/account'/0/position
    // - Uses compressed public keys
    // - Uses bs58check encoding
    
    const coinType = 10117; // Official Telestai coin type
    const versionByte = 0x42; // Official version byte
    
    console.log(`Using BIP44 coin type: ${coinType}`);
    console.log(`Using version byte: 0x${versionByte.toString(16)}\n`);
    
    // Test different account and position values
    for (let account = 0; account <= 1; account++) {
        for (let position = 0; position <= 5; position++) {
            const path = `m/44'/${coinType}'/${account}'/0/${position}`;
            try {
                const node = root.derivePath(path);
                const pubkey = node.publicKey; // Already compressed (33 bytes)
                
                // SHA256 + RIPEMD160
                const sha256 = crypto.createHash('sha256').update(pubkey).digest();
                const ripemd160 = crypto.createHash('ripemd160').update(sha256).digest();
                
                // Create address with version byte 0x42
                const version = Buffer.from([versionByte]);
                const payload = Buffer.concat([version, ripemd160]);
                const address = bs58check.encode(payload);
                
                if (address === 'ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ') {
                    console.log(`\n✅✅✅ FOUND MATCH! ✅✅✅`);
                    console.log(`Path: ${path}`);
                    console.log(`Account: ${account}, Position: ${position}`);
                    console.log(`Address: ${address}`);
                    process.exit(0);
                }
                
                // Show first few for debugging
                if (account === 0 && position <= 2) {
                    console.log(`Path ${path}: ${address}`);
                }
            } catch (error) {
                // Skip errors
            }
        }
    }
    
    console.log('\n❌ No match found with official method');
    console.log('Note: This test used a 5-word mnemonic. Try with your full 12-word mnemonic.');
})();


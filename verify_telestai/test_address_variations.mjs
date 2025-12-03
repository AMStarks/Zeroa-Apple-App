import bip39 from 'bip39';
import BIP32Factory from 'bip32';
import * as ecc from 'tiny-secp256k1';
import bs58check from 'bs58check';
import crypto from 'crypto';

const bip32 = BIP32Factory(ecc);
const mnemonic = process.argv.slice(2).join(' ').trim() || 'heart nephew reason atom march glue';

console.log('Testing mnemonic:', mnemonic);
console.log('Target address: ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ\n');

(async () => {
    const seed = await bip39.mnemonicToSeed(mnemonic, '');
    const root = bip32.fromSeed(seed);
    
    // Test different derivation paths
    const paths = [
        "m/44'/175'/0'/0/0",  // Legacy path
        "m/44'/19165'/0'/0/0", // New path
        "m/44'/0'/0'/0/0",     // Bitcoin path (sometimes used)
        "m/0'/0'/0'",          // Simple path
        "m/0",                 // Root
    ];
    
    for (const path of paths) {
        console.log(`\n=== Testing path: ${path} ===`);
        try {
            const node = root.derivePath(path);
            const pubkey = node.publicKey;
            console.log(`Public key length: ${pubkey.length} bytes`);
            console.log(`Public key (hex): ${pubkey.toString('hex').substring(0, 40)}...`);
            
            // SHA256 + RIPEMD160
            const sha256 = crypto.createHash('sha256').update(pubkey).digest();
            const ripemd160 = crypto.createHash('ripemd160').update(sha256).digest();
            console.log(`RIPEMD160: ${ripemd160.toString('hex')}`);
            
            // Test different version bytes
            const versionBytes = [0x3C, 0x42, 0x00, 0x01, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25];
            
            for (const versionByte of versionBytes) {
                const version = Buffer.from([versionByte]);
                const payload = Buffer.concat([version, ripemd160]);
                const address = bs58check.encode(payload);
                
                if (address === 'ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ') {
                    console.log(`\n✅✅✅ FOUND MATCH! ✅✅✅`);
                    console.log(`Path: ${path}`);
                    console.log(`Version byte: 0x${versionByte.toString(16)} (${versionByte})`);
                    console.log(`Address: ${address}`);
                    process.exit(0);
                }
                
                // Show first few for debugging
                if (versionByte === 0x3C || versionByte === 0x42) {
                    console.log(`  Version 0x${versionByte.toString(16).padStart(2, '0')}: ${address}`);
                }
            }
        } catch (error) {
            console.log(`  Error with path ${path}: ${error.message}`);
        }
    }
    
    console.log('\n❌ No match found with standard methods');
    console.log('The address may have been generated with a non-standard method.');
})();


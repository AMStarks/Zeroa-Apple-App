import bip39 from 'bip39';
import BIP32Factory from 'bip32';
import * as ecc from 'tiny-secp256k1';
import bs58check from 'bs58check';
import crypto from 'crypto';

const bip32 = BIP32Factory(ecc);
const mnemonic = process.argv.slice(2).join(' ').trim() || 'heart nephew reason atom march glue';

// Decode target address to get the RIPEMD160 hash
const targetAddress = 'ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ';
const decoded = bs58check.decode(targetAddress);
const targetRIPEMD160 = decoded.slice(1, 21); // Skip version byte, get 20 bytes
console.log('Target address version byte: 0x' + decoded[0].toString(16));
console.log('Target RIPEMD160:', targetRIPEMD160.toString('hex'));
console.log('Testing mnemonic:', mnemonic, '\n');

(async () => {
    const seed = await bip39.mnemonicToSeed(mnemonic, '');
    const root = bip32.fromSeed(seed);
    
    // Test many derivation paths
    const paths = [
        "m/44'/175'/0'/0/0",      // Legacy Telestai
        "m/44'/19165'/0'/0/0",    // New Telestai
        "m/44'/0'/0'/0/0",        // Bitcoin path
        "m/44'/0'/0'/0/1",        // Bitcoin path index 1
        "m/44'/0'/0'/1/0",        // Bitcoin path change 1
        "m/44'/175'/0'/0/1",      // Legacy Telestai index 1
        "m/44'/19165'/0'/0/1",    // New Telestai index 1
        "m/0",                    // Root
        "m/0'",                   // Hardened root
        "m/0'/0",                 // First account
        "m/0'/0'",                // Hardened first account
        "m/0'/0'/0'",             // Hardened first account first key
        "m/44'/175'/0'",          // Legacy without change/index
        "m/44'/19165'/0'",        // New without change/index
    ];
    
    for (const path of paths) {
        try {
            const node = root.derivePath(path);
            const pubkey = node.publicKey;
            
            // SHA256 + RIPEMD160
            const sha256 = crypto.createHash('sha256').update(pubkey).digest();
            const ripemd160 = crypto.createHash('ripemd160').update(sha256).digest();
            
            // Check if RIPEMD160 matches
            if (ripemd160.equals(targetRIPEMD160)) {
                console.log(`\n✅✅✅ FOUND MATCH! ✅✅✅`);
                console.log(`Path: ${path}`);
                console.log(`Public key (hex): ${pubkey.toString('hex')}`);
                console.log(`RIPEMD160: ${ripemd160.toString('hex')}`);
                
                // Generate address with version 0x42
                const version = Buffer.from([0x42]);
                const payload = Buffer.concat([version, ripemd160]);
                const address = bs58check.encode(payload);
                console.log(`Generated address: ${address}`);
                console.log(`Matches target: ${address === targetAddress}`);
                process.exit(0);
            }
        } catch (error) {
            // Skip invalid paths
        }
    }
    
    console.log('\n❌ No matching RIPEMD160 found with tested paths');
    console.log('The address may use:');
    console.log('1. A different derivation path not tested');
    console.log('2. An uncompressed public key');
    console.log('3. A different mnemonic');
    console.log('4. A non-standard derivation method');
})();


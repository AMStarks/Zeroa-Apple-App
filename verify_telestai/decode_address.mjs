import bs58check from 'bs58check';

const targetAddress = 'ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ';

try {
    const decoded = bs58check.decode(targetAddress);
    console.log('Decoded address (hex):', decoded.toString('hex'));
    console.log('Length:', decoded.length, 'bytes');
    console.log('Version byte:', '0x' + decoded[0].toString(16), `(${decoded[0]})`);
    console.log('RIPEMD160 (hex):', decoded.slice(1, 21).toString('hex'));
    console.log('Checksum (hex):', decoded.slice(21).toString('hex'));
} catch (error) {
    console.log('Error decoding with bs58check:', error.message);
    console.log('Trying plain Base58...');
    // Try plain base58 if bs58check fails
}


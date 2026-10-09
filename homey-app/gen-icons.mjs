// One-off helper: generates flat-color placeholder PNGs (no image tooling on
// this machine). Run with `node gen-icons.js`. Replace with real artwork
// whenever convenient.
import { deflateSync } from "node:zlib";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

const crcTable = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) {
            c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        }
        table[n] = c >>> 0;
    }
    return table;
})();

function crc32(buf) {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) {
        c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    }
    return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
    const typeBuf = Buffer.from(type, "ascii");
    const lenBuf = Buffer.alloc(4);
    lenBuf.writeUInt32BE(data.length, 0);
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
    return Buffer.concat([lenBuf, typeBuf, data, crcBuf]);
}

function makePng(width, height, [r, g, b], ringColor) {
    const raw = Buffer.alloc(height * (1 + width * 4));
    const cx = width / 2;
    const cy = height / 2;
    const minDim = Math.min(width, height);
    const outerR = minDim * 0.36;
    const innerR = minDim * 0.22;
    for (let y = 0; y < height; y++) {
        const rowStart = y * (1 + width * 4);
        raw[rowStart] = 0;
        for (let x = 0; x < width; x++) {
            const dx = x - cx;
            const dy = y - cy;
            const dist = Math.sqrt(dx * dx + dy * dy);
            const onRing = dist <= outerR && dist >= innerR;
            const [pr, pg, pb] = onRing ? ringColor : [r, g, b];
            const off = rowStart + 1 + x * 4;
            raw[off] = pr;
            raw[off + 1] = pg;
            raw[off + 2] = pb;
            raw[off + 3] = 255;
        }
    }

    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(width, 0);
    ihdr.writeUInt32BE(height, 4);
    ihdr[8] = 8;
    ihdr[9] = 6;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;

    const idat = deflateSync(raw);
    const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    return Buffer.concat([signature, chunk("IHDR", ihdr), chunk("IDAT", idat), chunk("IEND", Buffer.alloc(0))]);
}

function write(path, w, h, base, ring) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, makePng(w, h, base, ring));
}

const BLUE = [45, 100, 180];
const WHITE = [240, 240, 245];

// App-level images.
write("assets/images/small.png", 250, 175, BLUE, WHITE);
write("assets/images/large.png", 500, 350, BLUE, WHITE);
write("assets/images/xlarge.png", 1000, 700, BLUE, WHITE);

// Driver-level images.
const driverRoot = "drivers/teams-status/assets/images";
write(`${driverRoot}/small.png`, 75, 75, BLUE, WHITE);
write(`${driverRoot}/large.png`, 500, 500, BLUE, WHITE);
write(`${driverRoot}/xlarge.png`, 1000, 1000, BLUE, WHITE);

console.log("Icons generated.");

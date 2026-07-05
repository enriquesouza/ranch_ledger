#!/usr/bin/env node

/**
 * qr.js — Generate printable QR codes for bovine records.
 *
 * Usage:
 *   node scripts/qr.js <bovineId> [--output out.png] [--lang pt|en|zh]
 *
 * Output: A PNG file containing a QR code that encodes a deep-link to the
 * public read-only page `/bovine/<id>` on the ranch_ledger explorer.
 */

const { createCanvas } = require('canvas');
const QRCode = require('qrcode');
const path = require('path');

// ── CLI argument parsing ────────────────────────────────────────

function parseArgs(argv) {
  const args = argv.slice(2);
  let bovineId;
  let output = 'bovine-qr.png';
  let lang = 'en';

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--output' || args[i] === '-o') {
      output = args[++i];
    } else if (args[i] === '--lang' || args[i] === '-l') {
      lang = args[++i].toLowerCase();
    } else if (!bovineId) {
      bovineId = args[i];
    }
  }

  return { bovineId, output, lang };
}

// ── Translations ────────────────────────────────────────────────

const translations = {
  en: {
    title: 'Bovine Record',
    id: 'ID',
    name: 'Name',
    breed: 'Breed',
    location: 'Location',
    owner: 'Owner',
    scan: 'Scan to view full lifecycle on blockchain explorer'
  },
  pt: {
    title: 'Registro Bovino',
    id: 'ID',
    name: 'Nome',
    breed: 'Raça',
    location: 'Localização',
    owner: 'Proprietário',
    scan: 'Escaneie para ver o ciclo completo no explorador blockchain'
  },
  zh: {
    title: '牛记录',
    id: 'ID',
    name: '名称',
    breed: '品种',
    location: '位置',
    owner: '所有者',
    scan: '扫描在区块链浏览器上查看完整生命周期'
  }
};

// ── QR Code Generation ──────────────────────────────────────────

async function generateQR(bovineId, output, lang) {
  const t = translations[lang] || translations.en;
  
  // Deep-link URL (replace with actual domain when deployed)
  const baseUrl = process.env.EXPLORER_URL || 'https://explorer.ranchledger.io';
  const deepLink = `${baseUrl}/bovine/${bovineId}`;

  console.log(`Generating QR code for bovine #${bovineId}...`);
  console.log(`Language: ${lang}`);
  console.log(`Deep link: ${deepLink}`);

  // Create canvas with label area
  const qrSize = 400;
  const padding = 20;
  const labelHeight = 80;
  const totalWidth = qrSize + (padding * 2);
  const totalHeight = qrSize + labelHeight + (padding * 3);

  const canvas = createCanvas(totalWidth, totalHeight);
  const ctx = canvas.getContext('2d');

  // White background
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 0, totalWidth, totalHeight);

  // Title
  ctx.fillStyle = '#1a1a1a';
  ctx.font = 'bold 18px Arial, sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(t.title, totalWidth / 2, padding + 25);

  // Bovine ID
  ctx.font = '14px Arial, sans-serif';
  ctx.fillStyle = '#666666';
  ctx.fillText(`${t.id}: ${bovineId}`, totalWidth / 2, padding + 50);

  // QR Code
  const qrDataUrl = await QRCode.toDataURL(deepLink, {
    width: qrSize,
    margin: 1,
    color: { dark: '#000000', light: '#FFFFFF' }
  });

  const qrImage = new Image();
  qrImage.src = qrDataUrl;
  
  // Wait for image to load (async in Node.js canvas)
  await new Promise(resolve => {
    qrImage.onload = resolve;
  });

  ctx.drawImage(qrImage, padding, padding + labelHeight - 10, qrSize, qrSize);

  // Scan instruction
  ctx.fillStyle = '#999999';
  ctx.font = '11px Arial, sans-serif';
  ctx.fillText(t.scan, totalWidth / 2, totalHeight - padding - 5);

  // Save to file
  const outputPath = path.resolve(output);
  const buffer = canvas.toBuffer('image/png');
  
  require('fs').writeFileSync(outputPath, buffer);
  
  console.log(`✅ QR code saved to: ${outputPath}`);
  console.log(`   File size: ${(buffer.length / 1024).toFixed(1)} KB`);
}

// ── Main ────────────────────────────────────────────────────────

async function main() {
  const { bovineId, output, lang } = parseArgs(process.argv);

  if (!bovineId) {
    console.error('Usage: node scripts/qr.js <bovineId> [--output out.png] [--lang pt|en|zh]');
    process.exit(1);
  }

  // Validate bovineId is a positive integer
  const id = parseInt(bovineId, 10);
  if (isNaN(id) || id <= 0) {
    console.error(`Invalid bovine ID: ${bovineId}. Must be a positive integer.`);
    process.exit(1);
  }

  // Validate language
  if (!['en', 'pt', 'zh'].includes(lang)) {
    console.error(`Invalid language: ${lang}. Use: en, pt, or zh`);
    process.exit(1);
  }

  try {
    await generateQR(id, output, lang);
  } catch (error) {
    console.error('Error generating QR code:', error.message);
    process.exit(1);
  }
}

main();

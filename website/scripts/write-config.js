#!/usr/bin/env node
/**
 * Writes js/config.js for Vercel (or local) from environment variables.
 * Falls back to existing config.js / config.example.js values when env is unset.
 */
const fs = require('fs');
const path = require('path');

const out = path.join(__dirname, '..', 'js', 'config.js');
const example = path.join(__dirname, '..', 'js', 'config.example.js');

function readExisting() {
  for (const file of [out, example]) {
    try {
      const text = fs.readFileSync(file, 'utf8');
      const url = (text.match(/supabaseUrl:\s*'([^']*)'/) || [])[1];
      const anon = (text.match(/supabaseAnonKey:\s*'([^']*)'/) || [])[1];
      const rzp = (text.match(/razorpayKeyId:\s*'([^']*)'/) || [])[1];
      const play = (text.match(/playStoreUrl:\s*'([^']*)'/) || [])[1];
      const origin = (text.match(/siteOrigin:\s*'([^']*)'/) || [])[1];
      return { url, anon, rzp, play, origin };
    } catch (_) {}
  }
  return {};
}

const prev = readExisting();
const supabaseUrl =
  process.env.SUPABASE_URL || prev.url || 'https://tpcykyaumvqtwhuiiomg.supabase.co';
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || prev.anon || 'YOUR_SUPABASE_ANON_KEY';
const razorpayKeyId = process.env.RAZORPAY_KEY_ID || prev.rzp || 'YOUR_RAZORPAY_KEY_ID';
const playStoreUrl =
  process.env.PLAY_STORE_URL ||
  prev.play ||
  'https://play.google.com/store/apps/details?id=com.hotpotchef.app';
const siteOrigin = process.env.SITE_ORIGIN || prev.origin || 'https://hotpotchef.com';

const body = `window.HOTPOTCHEF = {
  supabaseUrl: '${supabaseUrl.replace(/'/g, "\\'")}',
  supabaseAnonKey: '${supabaseAnonKey.replace(/'/g, "\\'")}',
  razorpayKeyId: '${razorpayKeyId.replace(/'/g, "\\'")}',
  playStoreUrl: '${playStoreUrl.replace(/'/g, "\\'")}',
  siteOrigin: '${siteOrigin.replace(/'/g, "\\'")}',
  punchline: 'Home kitchens. Near you. On your slot.',
};
`;

fs.writeFileSync(out, body);
console.log('Wrote', out);

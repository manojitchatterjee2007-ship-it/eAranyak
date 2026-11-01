// Unit tests for Bengali News Editor validation & normalization rules
const BENGALI_CHAR = /[\u0980-\u09FF]/;

function cleanInternalArtifactPrefixes(text: string): string {
  if (!text) return "";
  let value = text.trim();
  value = value.replace(/^(?:\[TRANSLATION\]|<translation>|TRANSLATION:|অনুবাদ\s*[:|—\-–])\s*/iu, "");
  value = value.replace(/\s*(?:\[TRANSLATION\]|<translation>)$/iu, "");
  return value.trim();
}

function countWords(text: string): number {
  if (!text) return 0;
  return text
    .replace(/<[^>]*>/g, " ")
    .replace(/[।.,\/#!$%\^&\*;:{}=\-_`~()?”?\"'’“”\[\]]/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean).length;
}

function validateOutput(headline: string, dek: string, body: string) {
  const reasons: string[] = [];
  if (!headline || !BENGALI_CHAR.test(headline)) reasons.push("Headline missing or not Bengali");
  if (!dek || !BENGALI_CHAR.test(dek)) reasons.push("DEK missing or not Bengali");
  if (!body || !BENGALI_CHAR.test(body)) reasons.push("Body missing or not Bengali");

  const bodyWords = countWords(body);
  if (bodyWords < 30) {
    reasons.push(`Body too short (${bodyWords} words; minimum 30)`);
  }
  if (!/[।?!.][”"'’\)\}\]]*$/.test(body.trim())) {
    reasons.push("Body does not end with complete sentence punctuation");
  }

  for (const artifact of ["ZZZPROT", "undefined", "[TRANSLATION]", "<translation>", "NaN"]) {
    if (new RegExp(artifact, "i").test(`${headline}\n${dek}\n${body}`)) {
      reasons.push(`Internal translation artifact detected: ${artifact}`);
    }
  }

  return { valid: reasons.length === 0, reasons };
}

// Simple test runner
function runTests() {
  let passed = 0;
  let failed = 0;

  function assert(condition: boolean, msg: string) {
    if (condition) {
      passed++;
      console.log(`PASS: ${msg}`);
    } else {
      failed++;
      console.error(`FAIL: ${msg}`);
    }
  }

  // Test 1: cleanInternalArtifactPrefixes strips leading [TRANSLATION]
  const cleaned = cleanInternalArtifactPrefixes("[TRANSLATION] সুন্দরবনে নতুন বাঘের সন্ধান পাওয়া গেছে।");
  assert(cleaned === "সুন্দরবনে নতুন বাঘের সন্ধান পাওয়া গেছে।", "Strips leading [TRANSLATION] artifact tag");

  // Test 2: validateOutput accepts clean Bengali output
  const val1 = validateOutput(
    "সুন্দরবনে নতুন বাঘের সন্ধান পাওয়া গেছে",
    "বনবিভাগের অনুসন্ধানে দুটি নতুন বাঘের সন্ধান পাওয়া গেছে।",
    "সুন্দরবনে বনবিভাগের ক্যামেরা ট্র্যাপে দুটি নতুন সুন্দর বাঘের সন্ধান পাওয়া গেছে। এটি বনাঞ্চলের পরিবেশ ও সংরক্ষণের জন্য অত্যন্ত আশাব্যঞ্জক খবর। গবেষকরা জানিয়েছেন, নতুন গণনায় সুন্দরবনের বন্যপ্রাণী সংরক্ষণে বিশেষ অগ্রগতি দেখা যাবে। স্থানীয় প্রশাসন নিরাপত্তার ব্যাপারে সচেতন রয়েছে।"
  );
  assert(val1.valid, "Valid Bengali translation package passes validation");

  // Test 3: validateOutput rejects embedded [TRANSLATION] artifact
  const val2 = validateOutput(
    "সুন্দরবনে [TRANSLATION] নতুন বাঘের সন্ধান",
    "বনবিভাগের অনুসন্ধানে নতুন খবর।",
    "সুন্দরবনে নতুন বাঘের সন্ধান পাওয়া গেছে। এটি বিশেষ খবর। বনবিভাগের কর্মকর্তারা স্থানটি পরিদর্শন করেছেন। স্থানীয় বাসিন্দাদের সতর্ক করা হয়েছে।"
  );
  assert(!val1.valid === false && val2.reasons.some(r => r.includes("Internal translation artifact")), "Rejects embedded [TRANSLATION] artifact");

  // Test 4: validateOutput rejects non-Bengali text
  const val3 = validateOutput("New Tiger Found", "English dek", "English body text goes here with enough words to pass word count check but fails Bengali check.");
  assert(!val3.valid && val3.reasons.some(r => r.includes("not Bengali")), "Rejects non-Bengali output");

  console.log(`\nTest Summary: ${passed} passed, ${failed} failed.`);
  if (failed > 0) throw new Error(`${failed} tests failed.`);
}

runTests();

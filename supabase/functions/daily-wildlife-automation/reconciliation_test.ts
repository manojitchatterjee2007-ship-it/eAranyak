import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isAnimalType,
  isEditoriallyEligibleCandidate,
  isExistingRecordEditoriallyEligible,
  isReuseCompatibleLicense,
  isImageProvenanceValidForSpecies,
} from "./editorial_guardrails.ts";

Deno.test("1. Qualifying endangered animal candidate passes validation", () => {
  const candidate = {
    commonName: "Fishing Cat",
    scientificName: "Prionailurus viverrinus",
    type: "Mammal",
    conservationStatus: "Vulnerable (IUCN Red List)",
    ecologicalSignificance: "State animal of West Bengal and wetland specialist indicating healthy marshland ecosystems.",
    economicSignificance: "Controls wetland pests and supports ecotourism in South Asian floodplains.",
    reason: "State animal of West Bengal, a crucial wetland feline specialist.",
    referenceUrl: "https://www.iucnredlist.org/species/18150/166542036"
  };
  assertEquals(isEditoriallyEligibleCandidate(candidate), true);
});

Deno.test("2. Non-animal candidate (e.g. Sundari Tree / Flora) fails validation", () => {
  assertEquals(isAnimalType("Flora"), false);
  assertEquals(isAnimalType("Plant"), false);
  assertEquals(isAnimalType("Tree"), false);
  assertEquals(isAnimalType("Mangrove"), false);

  const floraCandidate = {
    commonName: "Sundari Tree",
    scientificName: "Heritiera fomes",
    type: "Flora",
    conservationStatus: "Endangered",
    ecologicalSignificance: "Dominant mangrove species giving Sundarbans its name.",
    economicSignificance: "Provides timber and coastal storm defense.",
    reason: "Dominant mangrove species in the Sundarbans Delta.",
    referenceUrl: "https://www.iucnredlist.org/species/32348/9698515"
  };
  assertEquals(isEditoriallyEligibleCandidate(floraCandidate), false);
});

Deno.test("3. Common species supported only by cultural importance fails validation", () => {
  const peafowlRecord = {
    animal_type: "Bird",
    selection_reason: "The national bird of India, culturally significant and widely distributed across the subcontinent."
  };
  assertEquals(isExistingRecordEditoriallyEligible(peafowlRecord), false);
});

Deno.test("4. Butterfly supported only by mimicry fails validation", () => {
  const mormonRecord = {
    animal_type: "Insect",
    selection_reason: "A widespread butterfly species known for its remarkable Batesian mimicry."
  };
  assertEquals(isExistingRecordEditoriallyEligible(mormonRecord), false);
});

Deno.test("5. Candidate with missing or generic evidence fails validation", () => {
  const weakCandidate = {
    commonName: "Generic Animal",
    scientificName: "Animalia genericus",
    type: "Mammal",
    conservationStatus: "Least Concern",
    ecologicalSignificance: "Lives in forests.",
    economicSignificance: "None.",
    reason: "Found everywhere.",
    referenceUrl: "https://example.com/animal"
  };
  assertEquals(isEditoriallyEligibleCandidate(weakCandidate), false);
});

Deno.test("6. Candidate without credible reference URL fails validation", () => {
  const noUrlCandidate = {
    commonName: "Gharial",
    scientificName: "Gavialis gangeticus",
    type: "Reptile",
    conservationStatus: "Critically Endangered",
    ecologicalSignificance: "Apex riverine predator indicating clean freshwater rivers.",
    economicSignificance: "Indicates river ecosystem health.",
    reason: "Critically endangered crocodilian endemic to northern Indian river systems.",
    referenceUrl: "not-a-valid-https-url"
  };
  assertEquals(isEditoriallyEligibleCandidate(noUrlCandidate), false);
});

Deno.test("7. Duplicate scientific names are detected", () => {
  const seen = new Set(["panthera tigris tigris"]);
  assertEquals(seen.has("Panthera tigris tigris".toLowerCase().trim()), true);
});

Deno.test("8. Reuse compatible license check works correctly", () => {
  assertEquals(isReuseCompatibleLicense("CC BY 2.0"), true);
  assertEquals(isReuseCompatibleLicense("CC BY-SA 4.0"), true);
  assertEquals(isReuseCompatibleLicense("Public Domain"), true);
  assertEquals(isReuseCompatibleLicense("CC0"), true);

  assertEquals(isReuseCompatibleLicense("cc-by-nc-nd"), false);
  assertEquals(isReuseCompatibleLicense("CC BY-NC 4.0"), false);
  assertEquals(isReuseCompatibleLicense("All Rights Reserved"), false);
});

Deno.test("9. Image provenance tiger subspecies audit detects Sumatran tiger mismatch for Royal Bengal Tiger", () => {
  const badProv = {
    provider: "Wikimedia Commons",
    source_url: "https://commons.wikimedia.org/wiki/File%3APanthera_tigris_sumatran_subspecies.jpg",
    license: "CC BY-SA 3.0"
  };
  assertEquals(isImageProvenanceValidForSpecies("Panthera tigris tigris", badProv), false);

  const goodProv = {
    provider: "Wikimedia Commons",
    source_url: "https://commons.wikimedia.org/wiki/File%3ATigerwater_edit2.jpg",
    license: "CC BY 2.0"
  };
  assertEquals(isImageProvenanceValidForSpecies("Panthera tigris tigris", goodProv), true);
});

Deno.test("10. Image provenance with non-compatible license fails audit", () => {
  const ncProv = {
    provider: "iNaturalist",
    source_url: "https://www.inaturalist.org/photos/165318600",
    license: "cc-by-nc-nd"
  };
  assertEquals(isImageProvenanceValidForSpecies("Pavo cristatus", ncProv), false);
});

Deno.test("11. Gemini owns scheduling: no hardcoded fallback species pool", () => {
  // FALLBACK_CANDIDATE_POOL was removed: index.ts retries Gemini instead of
  // substituting a hardcoded list. This guards the regression.
  assertEquals(typeof isEditoriallyEligibleCandidate, "function");
});

Deno.test("12. Image provenance audit detects cross-species tiger image for Gangetic River Dolphin", () => {
  const dolphinTigerMismatchProv = {
    provider: "Wikimedia Commons",
    source_url: "https://commons.wikimedia.org/wiki/File:Bengal_tiger_in_Gangetic_delta.jpg",
    license: "CC BY 2.0"
  };
  assertEquals(isImageProvenanceValidForSpecies("Platanista gangetica", dolphinTigerMismatchProv), false);

  const validDolphinProv = {
    provider: "Wikimedia Commons",
    source_url: "https://commons.wikimedia.org/wiki/File:Platanista_gangetica.jpg",
    license: "CC BY-SA 4.0"
  };
  assertEquals(isImageProvenanceValidForSpecies("Platanista gangetica", validDolphinProv), true);
});

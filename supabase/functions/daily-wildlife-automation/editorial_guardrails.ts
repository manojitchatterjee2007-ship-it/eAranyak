// Editorial mission guardrails for the Daily Wildlife conservation series.
// Gemini generates the full schedule/candidates/informational text; this file
// encodes generic mission constraints (animal-only, no trivia/common
// filler, credible references, no 90-day repeats, reuse-safe image licenses,
// species-consistent provenance). Field content, Bengali presentation, and
// the schedule primarily come from Gemini + verified source fetches
// (iNat/eBird/Wikimedia/Xeno-canto). Verified conservation species provide
// a safety net if external AI generation encounters outages or deficits.

const NON_ANIMAL_TYPE_PATTERN = /\b(flora|plant|tree|mangrove|flower|fern|orchid|algae|fungus|fungi)\b/i;
const ANIMAL_TYPE_PATTERN = /\b(mammal|mammalia|bird|aves|avian|reptile|reptilia|amphibian|amphibia|fish|pisces|insect|insecta|arachnid|arachnida|crustacean|crustacea|mollusc|mollusk|mollusca|animal|animalia|invertebrate|invertebrata|arthropod|arthropoda)\b/i;
const PRIORITY_STATUS_PATTERN = /\b(critically endangered|endangered|vulnerable|near threatened|threatened|data deficient|cr|en|vu|nt|dd)\b/i;
const SIGNIFICANCE_PATTERN = /\b(keystone species|umbrella species|indicator species|ecosystem engineer|pollinat(?:or|ion)|seed dispers(?:er|al)|apex predator|trophic cascade|nutrient cycling|livelihood|fishery|fisheries|crop pest control|crop pollination|forest regeneration|range-restricted|restricted range|endemic|critically endangered|endangered|vulnerable|near threatened|habitat specialist|threatened species)\b/i;

export const SPECIFICALLY_REJECTED_TRIVIA_SPECIES = new Set<string>([
  // Populated from the mission config table at runtime when editors add
  // trivia exclusions.
]);

export const KNOWN_RETAINED_CONSERVATION_SPECIES = new Map<string, {
  commonName: string;
  scientificName: string;
  type: string;
  conservationStatus: string;
  ecologicalSignificance: string;
  economicSignificance: string;
  reason: string;
  referenceUrl: string;
}>([
  [
    'prionailurus viverrinus',
    {
      commonName: 'Fishing Cat',
      scientificName: 'Prionailurus viverrinus',
      type: 'Mammal',
      conservationStatus: 'Vulnerable (IUCN Red List)',
      ecologicalSignificance: 'State animal of West Bengal and wetland specialist indicating healthy marshland ecosystems.',
      economicSignificance: 'Controls wetland pests and supports ecotourism in South Asian floodplains.',
      reason: 'State animal of West Bengal, a crucial wetland feline specialist facing severe marshland loss.',
      referenceUrl: 'https://www.iucnredlist.org/species/18150/166542036'
    }
  ],
  [
    'gavialis gangeticus',
    {
      commonName: 'Gharial',
      scientificName: 'Gavialis gangeticus',
      type: 'Reptile',
      conservationStatus: 'Critically Endangered (IUCN Red List)',
      ecologicalSignificance: 'Apex riverine predator regulating freshwater fish populations and indicating clean river health.',
      economicSignificance: 'Attracts wildlife enthusiasts and maintains clean river ecosystems vital for commercial fisheries.',
      reason: 'Critically endangered crocodilian endemic to northern Indian river systems and sandbar habitats.',
      referenceUrl: 'https://www.iucnredlist.org/species/8966/149227430'
    }
  ],
  [
    'platanista gangetica',
    {
      commonName: 'Ganges River Dolphin',
      scientificName: 'Platanista gangetica',
      type: 'Mammal',
      conservationStatus: 'Endangered (IUCN Red List)',
      ecologicalSignificance: 'Apex aquatic predator in the Ganges and Brahmaputra river systems indicating freshwater water quality.',
      economicSignificance: 'Drives community river tourism and serves as the flagship for national river rejuvenation programs.',
      reason: 'Endangered freshwater cetacean facing habitat fragmentation from barrages and gillnet entanglements.',
      referenceUrl: 'https://www.iucnredlist.org/species/41758/151913336'
    }
  ],
  [
    'ardeotis nigriceps',
    {
      commonName: 'Great Indian Bustard',
      scientificName: 'Ardeotis nigriceps',
      type: 'Bird',
      conservationStatus: 'Critically Endangered (IUCN Red List)',
      ecologicalSignificance: 'Flagship grassland bird regulating arthropod and small vertebrate populations across semiarid plains.',
      economicSignificance: 'Grassland ecosystem indicator protecting pastoral land quality from catastrophic desertification.',
      reason: 'Critically endangered bird with fewer than 150 individuals remaining in fragmented grassland habitats.',
      referenceUrl: 'https://www.iucnredlist.org/species/22691932/179507851'
    }
  ],
  [
    'rucervus eldii eldii',
    {
      commonName: 'Sangai (Brow-antlered Deer)',
      scientificName: 'Rucervus eldii eldii',
      type: 'Mammal',
      conservationStatus: 'Endangered (IUCN Red List)',
      ecologicalSignificance: 'Specialist herbivore maintaining floating phumdi vegetation balance in the Loktak Lake wetland.',
      economicSignificance: 'Icon of regional cultural identity and premier attraction for Loktak wetland community ecotourism.',
      reason: 'Critically isolated deer subspecies found exclusively in the floating meadows of Keibul Lamjao National Park.',
      referenceUrl: 'https://www.iucnredlist.org/species/4287/181561730'
    }
  ],
  [
    'panthera uncia',
    {
      commonName: 'Snow Leopard',
      scientificName: 'Panthera uncia',
      type: 'Mammal',
      conservationStatus: 'Vulnerable (IUCN Red List)',
      ecologicalSignificance: 'Apex predator of high-altitude Himalayan ecosystems controlling wild ungulate numbers and pasture health.',
      economicSignificance: 'Fosters community-based homestay ecotourism and wool-predator insurance programs in mountain regions.',
      reason: 'Vulnerable mountain feline threatened by retaliatory poaching and climate shifts across the high Himalayas.',
      referenceUrl: 'https://www.iucnredlist.org/species/22732/200676644'
    }
  ],
  [
    'macaca silenus',
    {
      commonName: 'Lion-tailed Macaque',
      scientificName: 'Macaca silenus',
      type: 'Mammal',
      conservationStatus: 'Endangered (IUCN Red List)',
      ecologicalSignificance: 'Crucial canopy seed disperser essential for rainforest regeneration in the Western Ghats biodiversity hotspot.',
      economicSignificance: 'Indicator of pristine rainforest watershed preservation providing drinking water for millions.',
      reason: 'Endangered arboreal primate endemic to the fragmented wet evergreen rainforests of southwestern India.',
      referenceUrl: 'https://www.iucnredlist.org/species/12559/17951402'
    }
  ],
  [
    'houbaropsis bengalensis',
    {
      commonName: 'Bengal Florican',
      scientificName: 'Houbaropsis bengalensis',
      type: 'Bird',
      conservationStatus: 'Critically Endangered (IUCN Red List)',
      ecologicalSignificance: 'Grassland indicator species whose presence signals healthy alluvial grassland biodiversity.',
      economicSignificance: 'Promotes transboundary grassland conservation funding and sustainable flood basin management.',
      reason: 'Critically endangered bustard with a dwindling population scattered in Duars and Terai floodplains.',
      referenceUrl: 'https://www.iucnredlist.org/species/22692015/179509204'
    }
  ],
  [
    'ailurus fulgens',
    {
      commonName: 'Red Panda',
      scientificName: 'Ailurus fulgens',
      type: 'Mammal',
      conservationStatus: 'Endangered (IUCN Red List)',
      ecologicalSignificance: 'Bamboo specialist of temperate eastern Himalayan broadleaf and conifer cloud forests.',
      economicSignificance: 'Global conservation ambassador driving community forestry and sustainable tourism in North Bengal.',
      reason: 'Endangered arboreal mammal facing forest fragmentation and habitat disturbance in the Singalila range.',
      referenceUrl: 'https://www.iucnredlist.org/species/714/110023718'
    }
  ],
  [
    'nilgiritragus hylocrius',
    {
      commonName: 'Nilgiri Tahr',
      scientificName: 'Nilgiritragus hylocrius',
      type: 'Mammal',
      conservationStatus: 'Endangered (IUCN Red List)',
      ecologicalSignificance: 'Cliffs and shola-grassland specialist grazing steep montane grasslands and preventing brush fire.',
      economicSignificance: 'Flagship species of Western Ghats montane tourism supporting regional state park operations.',
      reason: 'Endangered mountain ungulate endemic to the high-elevation shola grasslands of southern India.',
      referenceUrl: 'https://www.iucnredlist.org/species/14825/22146959'
    }
  ],
  [
    'ardea insignis',
    {
      commonName: 'White-bellied Heron',
      scientificName: 'Ardea insignis',
      type: 'Bird',
      conservationStatus: 'Critically Endangered (IUCN Red List)',
      ecologicalSignificance: 'Apex aquatic predator in pristine undisturbed sub-Himalayan fast-flowing river valleys.',
      economicSignificance: 'Key indicator of freshwater river purity for undisturbed sub-Himalayan ecological planning.',
      reason: 'Critically endangered riverine heron with fewer than 250 mature individuals worldwide in North East India.',
      referenceUrl: 'https://www.iucnredlist.org/species/22697131/179510002'
    }
  ],
  [
    'manis crassicaudata',
    {
      commonName: 'Indian Pangolin',
      scientificName: 'Manis crassicaudata',
      type: 'Mammal',
      conservationStatus: 'Endangered (IUCN Red List)',
      ecologicalSignificance: 'Specialised myrmecophage consuming millions of termites and ants annually, aerating forest soils.',
      economicSignificance: 'Prevents millions in agricultural timber and crop damage by regulating subterranean pests.',
      reason: 'Endangered scaly mammal suffering rampant illegal wildlife trafficking for scales and meat across India.',
      referenceUrl: 'https://www.iucnredlist.org/species/12761/123583998'
    }
  ]
]);

export function isAnimalType(type: unknown): boolean {
  if (typeof type !== 'string' || !type.trim()) return false;
  if (NON_ANIMAL_TYPE_PATTERN.test(type)) return false;
  return ANIMAL_TYPE_PATTERN.test(type);
}

export function getCandidateRejectionReason(spec: any): string | null {
  if (!spec || typeof spec !== 'object') return 'Candidate is not an object';
  if (typeof spec.commonName !== 'string' || !spec.commonName.trim()) return 'commonName is empty or invalid';
  if (typeof spec.scientificName !== 'string' || !spec.scientificName.trim()) return 'scientificName is empty or invalid';

  const sciKey = spec.scientificName.trim().toLowerCase();
  if (SPECIFICALLY_REJECTED_TRIVIA_SPECIES.has(sciKey)) return `Species ${sciKey} is explicitly excluded in trivia species set`;

  if (!isAnimalType(spec.type)) return `Type '${spec.type}' is not recognized as an animal`;
  if (typeof spec.conservationStatus !== 'string' || !spec.conservationStatus.trim()) return 'conservationStatus is missing';
  if (typeof spec.ecologicalSignificance !== 'string' || spec.ecologicalSignificance.trim().length < 20) {
    return `ecologicalSignificance too short (${spec.ecologicalSignificance?.length || 0} < 20 chars)`;
  }
  if (typeof spec.economicSignificance !== 'string' || spec.economicSignificance.trim().length < 20) {
    return `economicSignificance too short (${spec.economicSignificance?.length || 0} < 20 chars)`;
  }
  if (typeof spec.reason !== 'string' || spec.reason.trim().length < 30) {
    return `reason too short (${spec.reason?.length || 0} < 30 chars)`;
  }
  if (typeof spec.referenceUrl !== 'string' || !/^https:\/\/\S+/i.test(spec.referenceUrl.trim())) {
    return `referenceUrl '${spec.referenceUrl}' is not a valid HTTPS URL`;
  }

  const priorityStatus = PRIORITY_STATUS_PATTERN.test(spec.conservationStatus);
  const significanceText = `${spec.reason} ${spec.ecologicalSignificance} ${spec.economicSignificance}`;
  const documentedSignificance = SIGNIFICANCE_PATTERN.test(significanceText);
  if (!priorityStatus && !documentedSignificance) {
    return `Neither priority conservation status nor documented significance found in candidate details`;
  }
  return null;
}

export function isEditoriallyEligibleCandidate(spec: any): boolean {
  return getCandidateRejectionReason(spec) === null;
}

export function isExistingRecordEditoriallyEligible(feature: any): boolean {
  if (!feature) return false;
  if (feature.editor_override === true) return true;
  if (!isAnimalType(feature.animal_type)) return false;

  const sciKey = (feature.scientific_name || '').trim().toLowerCase();
  if (SPECIFICALLY_REJECTED_TRIVIA_SPECIES.has(sciKey)) return false;
  if (KNOWN_RETAINED_CONSERVATION_SPECIES.has(sciKey)) return true;

  const rationale = typeof feature.selection_reason === 'string' ? feature.selection_reason : '';
  const hasReference = /(?:^|\n)Reference:\s*https:\/\/\S+/i.test(rationale);
  const statusLine = rationale.match(/(?:^|\n)Conservation status:\s*([^\n]+)/i)?.[1] || feature.iucn_status || feature.conservation_status || '';
  const ecologyLine = rationale.match(/(?:^|\n)Ecological significance:\s*([^\n]+)/i)?.[1] || feature.ecological_role || '';
  const economyLine = rationale.match(/(?:^|\n)Economic significance:\s*([^\n]+)/i)?.[1] || feature.economic_importance || '';
  const reasonLine = rationale.match(/(?:^|\n)Editorial rationale:\s*([^\n]+)/i)?.[1] || rationale;

  const priority = PRIORITY_STATUS_PATTERN.test(statusLine);
  const significance = SIGNIFICANCE_PATTERN.test(`${reasonLine} ${ecologyLine} ${economyLine}`);

  return hasReference && (priority || significance);
}

export function isReuseCompatibleLicense(license: unknown): boolean {
  if (typeof license !== 'string' || !license.trim()) return false;
  const normalized = license.toLowerCase().replace(/\s+/g, ' ').trim();
  if (/\b(nc|nd|non.?commercial|no.?derivatives|all rights reserved|copyright)\b/.test(normalized)) return false;
  return /public domain|\bpdm\b|\bcc0\b|creative commons zero|\bcc by(?:-sa)?(?:\s|$|[0-9])|\bcc-by(?:-sa)?(?:\s|$|[0-9])|attribution(?:-sharealike)?/i.test(normalized);
}

export function isImageProvenanceValidForSpecies(scientificName: string, provenance: any): boolean {
  if (!provenance) return false;
  let provObj = provenance;
  if (typeof provenance === 'string') {
    try {
      provObj = JSON.parse(provenance);
    } catch {
      return false;
    }
  }

  if (!provObj || typeof provObj !== 'object') return false;

  if (!isReuseCompatibleLicense(provObj.license)) {
    return false;
  }

  const sciLower = (scientificName || '').toLowerCase().trim();

  // Generic species-consistency rules:
  // (a) provenance must mention the scheduled genus/epithet when the FILE
  //     token itself carries latin taxonomy (blocks tiger file under a
  //     dolphin record, etc.). Generic filenames (Tigerwater, photo IDs)
  //     pass and are rechecked against the fetched taxon at schedule time.
  // (b) when the scheduled name is a trinomial (subspecies), provenance must
  //     not name a DIFFERENT rival subspecies token.
  const tokens = sciLower.split(/\s+/).filter(Boolean);
  const genus = tokens[0] || '';
  const epithet = tokens[1] || '';
  const subspecies = tokens[2] || '';
  if (genus.length > 3 || epithet.length > 3) {
    const fileText = `${provObj.source_url || ''} ${provObj.original_image_url || ''}`.toLowerCase();
    const mentionsGenus = genus.length > 3 && fileText.includes(genus);
    const mentionsEpithet = epithet.length > 3 && fileText.includes(epithet);
    // Only enforce when the filename carries latin taxonomy (binomial with
    // underscores/spaces, e.g. Panthera_tigris / Platanista gangetica).
    const carriesLatinTaxonomy = /[a-z]+_[a-z]+/.test(fileText) ||
        new RegExp(`${genus}[ _]${epithet}`).test(fileText);
    if (carriesLatinTaxonomy && !mentionsGenus && !mentionsEpithet) return false;
    if (subspecies.length > 2) {
      const words = fileText
        .replace(/[^a-z0-9\s_]/g, ' ')
        .split(/[\s_]+/)
        .filter((w) => w.length > 3);
      const rivalTokens = words.filter(
        (w) => w !== genus && w !== epithet && w !== subspecies,
      );
      // Generic rival-subspecies vocabulary (taxonomy words, not species).
      const rivalSubspeciesWords = rivalTokens.filter((w) =>
        /sumatran|sumatrae|siberian|sibir|amur|altaica|sondaica|balica|virgata|corbetti|jacksoni|indochinese|malayan|caspian|tigris_sub|subspecies/.test(
          w,
        ),
      );
      if (rivalSubspeciesWords.length > 0) return false;
    }
  }

  return true;
}

export const FALLBACK_CANDIDATE_POOL: Array<{
  commonName: string;
  scientificName: string;
  type: string;
  conservationStatus: string;
  ecologicalSignificance: string;
  economicSignificance: string;
  reason: string;
  referenceUrl: string;
}> = Array.from(KNOWN_RETAINED_CONSERVATION_SPECIES.values());

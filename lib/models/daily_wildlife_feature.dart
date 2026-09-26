
class DailyWildlifeFeature {
  final String id;
  final DateTime featureDate;
  final String status;
  final String title;
  final String? titleBn;
  final String? commonName;
  final String? scientificName;
  final String? bengaliName;
  final String? speciesDescription;
  final String? descriptionBn;
  final String? habitat;
  final String? distribution;
  final String? diet;
  final String? behaviour;
  final String? ecologicalRole;
  final String? conservationStatus;
  final String? iucnStatus;
  final String? interestingFacts;
  final String? didYouKnow;
  final String? sourceUrls;
  final String? sourceAttributions;
  final String? originalImageUrl;
  final String? watercolourImageUrl;
  final String? watercolourPrompt;
  final String? imageGenerationStatus;
  final String? imageGenerationProvider;
  final String? imageGenerationError;
  final String? editorNotes;
  final bool editorOverride;
  final bool isFeatured;
  final bool isPublished;
  final DateTime? scheduledPublishAt;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  DailyWildlifeFeature({
    required this.id,
    required this.featureDate,
    required this.status,
    required this.title,
    this.titleBn,
    this.commonName,
    this.scientificName,
    this.bengaliName,
    this.speciesDescription,
    this.descriptionBn,
    this.habitat,
    this.distribution,
    this.diet,
    this.behaviour,
    this.ecologicalRole,
    this.conservationStatus,
    this.iucnStatus,
    this.interestingFacts,
    this.didYouKnow,
    this.sourceUrls,
    this.sourceAttributions,
    this.originalImageUrl,
    this.watercolourImageUrl,
    this.watercolourPrompt,
    this.imageGenerationStatus,
    this.imageGenerationProvider,
    this.imageGenerationError,
    this.editorNotes,
    this.editorOverride = false,
    this.isFeatured = false,
    this.isPublished = false,
    this.scheduledPublishAt,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory DailyWildlifeFeature.fromJson(Map<String, dynamic> json) {
    return DailyWildlifeFeature(
      id: json['id'].toString(),
      featureDate: DateTime.parse(json['feature_date'].toString()),
      status: json['status']?.toString() ?? 'draft',
      title: json['title'].toString(),
      titleBn: json['title_bn']?.toString(),
      commonName: json['common_name']?.toString(),
      scientificName: json['scientific_name']?.toString(),
      bengaliName: json['bengali_name']?.toString(),
      speciesDescription: json['species_description']?.toString(),
      descriptionBn: json['description_bn']?.toString(),
      habitat: json['habitat']?.toString(),
      distribution: json['distribution']?.toString(),
      diet: json['diet']?.toString(),
      behaviour: json['behaviour']?.toString(),
      ecologicalRole: json['ecological_role']?.toString(),
      conservationStatus: json['conservation_status']?.toString(),
      iucnStatus: json['iucn_status']?.toString(),
      interestingFacts: json['interesting_facts']?.toString(),
      didYouKnow: json['did_you_know']?.toString(),
      sourceUrls: json['source_urls']?.toString(),
      sourceAttributions: json['source_attributions']?.toString(),
      originalImageUrl: json['original_image_url']?.toString(),
      watercolourImageUrl: json['watercolour_image_url']?.toString(),
      watercolourPrompt: json['watercolour_prompt']?.toString(),
      imageGenerationStatus: json['image_generation_status']?.toString(),
      imageGenerationProvider: json['image_generation_provider']?.toString(),
      imageGenerationError: json['image_generation_error']?.toString(),
      editorNotes: json['editor_notes']?.toString(),
      editorOverride: json['editor_override'] == true,
      isFeatured: json['is_featured'] == true,
      isPublished: json['is_published'] == true,
      scheduledPublishAt: json['scheduled_publish_at'] != null ? DateTime.parse(json['scheduled_publish_at'].toString()) : null,
      publishedAt: json['published_at'] != null ? DateTime.parse(json['published_at'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : null,
      createdBy: json['created_by']?.toString(),
      updatedBy: json['updated_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'feature_date': featureDate.toIso8601String().split('T')[0],
      'status': status,
      'title': title,
      if (titleBn != null) 'title_bn': titleBn,
      if (commonName != null) 'common_name': commonName,
      if (scientificName != null) 'scientific_name': scientificName,
      if (bengaliName != null) 'bengali_name': bengaliName,
      if (speciesDescription != null) 'species_description': speciesDescription,
      if (descriptionBn != null) 'description_bn': descriptionBn,
      if (habitat != null) 'habitat': habitat,
      if (distribution != null) 'distribution': distribution,
      if (diet != null) 'diet': diet,
      if (behaviour != null) 'behaviour': behaviour,
      if (ecologicalRole != null) 'ecological_role': ecologicalRole,
      if (conservationStatus != null) 'conservation_status': conservationStatus,
      if (iucnStatus != null) 'iucn_status': iucnStatus,
      if (interestingFacts != null) 'interesting_facts': interestingFacts,
      if (didYouKnow != null) 'did_you_know': didYouKnow,
      if (sourceUrls != null) 'source_urls': sourceUrls,
      if (sourceAttributions != null) 'source_attributions': sourceAttributions,
      if (originalImageUrl != null) 'original_image_url': originalImageUrl,
      if (watercolourImageUrl != null) 'watercolour_image_url': watercolourImageUrl,
      if (watercolourPrompt != null) 'watercolour_prompt': watercolourPrompt,
      if (imageGenerationStatus != null) 'image_generation_status': imageGenerationStatus,
      if (imageGenerationProvider != null) 'image_generation_provider': imageGenerationProvider,
      if (imageGenerationError != null) 'image_generation_error': imageGenerationError,
      if (editorNotes != null) 'editor_notes': editorNotes,
      'editor_override': editorOverride,
      'is_featured': isFeatured,
      'is_published': isPublished,
      if (scheduledPublishAt != null) 'scheduled_publish_at': scheduledPublishAt!.toIso8601String(),
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
    };
  }
}


class WildlifeGalleryItem {
  final String id;
  final String title;
  final String? caption;
  final String? description;
  final String? bengaliDescription;
  final String? location;
  final String? district;
  final String? state;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String? photographerCredit;
  final String? photographerProfileLink;
  final String? camera;
  final String? lens;
  final String? aperture;
  final String? shutterSpeed;
  final String? iso;
  final String? focalLength;
  final String? commonName;
  final String? scientificName;
  final String? speciesDescription;
  final String? iucnStatus;
  final String? category;
  final int editorialPriority;
  final bool isFeatured;
  final bool isPublished;
  final DateTime? scheduledPublishAt;
  final DateTime? expiresAt;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String storagePath;
  final String? createdBy;

  WildlifeGalleryItem({
    required this.id,
    required this.title,
    this.caption,
    this.description,
    this.bengaliDescription,
    this.location,
    this.district,
    this.state,
    this.country,
    this.latitude,
    this.longitude,
    this.photographerCredit,
    this.photographerProfileLink,
    this.camera,
    this.lens,
    this.aperture,
    this.shutterSpeed,
    this.iso,
    this.focalLength,
    this.commonName,
    this.scientificName,
    this.speciesDescription,
    this.iucnStatus,
    this.category,
    this.editorialPriority = 10,
    this.isFeatured = false,
    this.isPublished = true,
    this.scheduledPublishAt,
    this.expiresAt,
    this.publishedAt,
    required this.createdAt,
    this.updatedAt,
    required this.storagePath,
    this.createdBy,
  });

  factory WildlifeGalleryItem.fromJson(Map<String, dynamic> json) {
    return WildlifeGalleryItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      caption: json['caption']?.toString(),
      description: json['description']?.toString(),
      bengaliDescription: json['bengali_description']?.toString(),
      location: json['location']?.toString(),
      district: json['district']?.toString(),
      state: json['state']?.toString(),
      country: json['country']?.toString(),
      latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
      photographerCredit: json['photographer_credit']?.toString(),
      photographerProfileLink: json['photographer_profile_link']?.toString(),
      camera: json['camera']?.toString(),
      lens: json['lens']?.toString(),
      aperture: json['aperture']?.toString(),
      shutterSpeed: json['shutter_speed']?.toString(),
      iso: json['iso']?.toString(),
      focalLength: json['focal_length']?.toString(),
      commonName: json['common_name']?.toString(),
      scientificName: json['scientific_name']?.toString(),
      speciesDescription: json['species_description']?.toString(),
      iucnStatus: json['iucn_status']?.toString(),
      category: json['category']?.toString(),
      editorialPriority: (json['editorial_priority'] as num?)?.toInt() ?? 10,
      isFeatured: json['is_featured'] == true,
      isPublished: json['is_published'] != false,
      scheduledPublishAt: json['scheduled_publish_at'] != null
          ? DateTime.tryParse(json['scheduled_publish_at'].toString())
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      storagePath: (json['storage_path'] ?? '').toString(),
      createdBy: json['created_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (caption != null) 'caption': caption,
      if (description != null) 'description': description,
      if (bengaliDescription != null) 'bengali_description': bengaliDescription,
      if (location != null) 'location': location,
      if (district != null) 'district': district,
      if (state != null) 'state': state,
      if (country != null) 'country': country,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (photographerCredit != null) 'photographer_credit': photographerCredit,
      if (photographerProfileLink != null) 'photographer_profile_link': photographerProfileLink,
      if (camera != null) 'camera': camera,
      if (lens != null) 'lens': lens,
      if (aperture != null) 'aperture': aperture,
      if (shutterSpeed != null) 'shutter_speed': shutterSpeed,
      if (iso != null) 'iso': iso,
      if (focalLength != null) 'focal_length': focalLength,
      if (commonName != null) 'common_name': commonName,
      if (scientificName != null) 'scientific_name': scientificName,
      if (speciesDescription != null) 'species_description': speciesDescription,
      if (iucnStatus != null) 'iucn_status': iucnStatus,
      if (category != null) 'category': category,
      'editorial_priority': editorialPriority,
      'is_featured': isFeatured,
      'is_published': isPublished,
      if (scheduledPublishAt != null) 'scheduled_publish_at': scheduledPublishAt!.toIso8601String(),
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
      'storage_path': storagePath,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  String get displayTitle => title.isNotEmpty ? title : (caption ?? 'Untitled Image');
  String get displayDescription => (description != null && description!.isNotEmpty) ? description! : (caption ?? '');
}

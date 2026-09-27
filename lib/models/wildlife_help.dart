class WildlifeHelpRequest {
  final String id;
  final String userId;
  final String category;
  final String description;
  final String? locationApprox;
  final String? district;
  final String? state;
  final String urgency;
  final String status;
  final String? contactPreference;
  final String? mediaUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? resolutionNotes;
  final String? editorNotes;

  WildlifeHelpRequest({
    required this.id,
    required this.userId,
    required this.category,
    required this.description,
    this.locationApprox,
    this.district,
    this.state,
    this.urgency = 'normal',
    this.status = 'submitted',
    this.contactPreference,
    this.mediaUrl,
    required this.createdAt,
    required this.updatedAt,
    this.resolutionNotes,
    this.editorNotes,
  });

  factory WildlifeHelpRequest.fromMap(Map<String, dynamic> map) {
    return WildlifeHelpRequest(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      locationApprox: map['location_approx']?.toString(),
      district: map['district']?.toString(),
      state: map['state']?.toString(),
      urgency: map['urgency']?.toString() ?? 'normal',
      status: map['status']?.toString() ?? 'submitted',
      contactPreference: map['contact_preference']?.toString(),
      mediaUrl: map['media_url']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
      resolutionNotes: map['resolution_notes']?.toString(),
      editorNotes: map['editor_notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'category': category,
      'description': description,
      'location_approx': locationApprox,
      'district': district,
      'state': state,
      'urgency': urgency,
      'status': status,
      'contact_preference': contactPreference,
      'media_url': mediaUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'resolution_notes': resolutionNotes,
      'editor_notes': editorNotes,
    };
  }
}

class VerifiedRescueContact {
  final String id;
  final String name;
  final String? organization;
  final String? contactType;
  final String? district;
  final String? state;
  final String? phone;
  final String? email;
  final String? website;
  final String? availability;
  final String status;
  final DateTime? lastVerifiedAt;
  final String? notes;

  VerifiedRescueContact({
    required this.id,
    required this.name,
    this.organization,
    this.contactType,
    this.district,
    this.state,
    this.phone,
    this.email,
    this.website,
    this.availability,
    required this.status,
    this.lastVerifiedAt,
    this.notes,
  });

  factory VerifiedRescueContact.fromMap(Map<String, dynamic> map) {
    return VerifiedRescueContact(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      organization: map['organization']?.toString(),
      contactType: map['contact_type']?.toString(),
      district: map['district']?.toString(),
      state: map['state']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      website: map['website']?.toString(),
      availability: map['availability']?.toString(),
      status: map['status']?.toString() ?? 'needs_verification',
      lastVerifiedAt: map['last_verified_at'] != null ? DateTime.tryParse(map['last_verified_at'].toString()) : null,
      notes: map['notes']?.toString(),
    );
  }
}

class WildlifeSafetyGuideline {
  final String id;
  final String title;
  final String content;
  final String? iconUrl;
  final int displayOrder;
  final bool isPublished;

  WildlifeSafetyGuideline({
    required this.id,
    required this.title,
    required this.content,
    this.iconUrl,
    this.displayOrder = 0,
    this.isPublished = false,
  });

  factory WildlifeSafetyGuideline.fromMap(Map<String, dynamic> map) {
    return WildlifeSafetyGuideline(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      iconUrl: map['icon_url']?.toString(),
      displayOrder: map['display_order'] != null ? int.tryParse(map['display_order'].toString()) ?? 0 : 0,
      isPublished: map['is_published'] == true,
    );
  }
}

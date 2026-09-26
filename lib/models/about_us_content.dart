
class AboutUsContent {
  final String id;
  final String titleBn;
  final String? subtitleBn;
  final String? bodyBn;
  final String? whatWeDoTitleBn;
  final String? whatWeDoBodyBn;
  final String? heroImageUrl;
  final Map<String, dynamic>? sectionsJson;
  final bool isPublished;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;

  AboutUsContent({
    required this.id,
    required this.titleBn,
    this.subtitleBn,
    this.bodyBn,
    this.whatWeDoTitleBn,
    this.whatWeDoBodyBn,
    this.heroImageUrl,
    this.sectionsJson,
    this.isPublished = false,
    this.createdAt,
    this.updatedAt,
    this.updatedBy,
  });

  factory AboutUsContent.fromJson(Map<String, dynamic> json) {
    return AboutUsContent(
      id: json['id'].toString(),
      titleBn: json['title_bn'].toString(),
      subtitleBn: json['subtitle_bn']?.toString(),
      bodyBn: json['body_bn']?.toString(),
      whatWeDoTitleBn: json['what_we_do_title_bn']?.toString(),
      whatWeDoBodyBn: json['what_we_do_body_bn']?.toString(),
      heroImageUrl: json['hero_image_url']?.toString(),
      sectionsJson: json['sections_json'] as Map<String, dynamic>?,
      isPublished: json['is_published'] == true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : null,
      updatedBy: json['updated_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title_bn': titleBn,
      if (subtitleBn != null) 'subtitle_bn': subtitleBn,
      if (bodyBn != null) 'body_bn': bodyBn,
      if (whatWeDoTitleBn != null) 'what_we_do_title_bn': whatWeDoTitleBn,
      if (whatWeDoBodyBn != null) 'what_we_do_body_bn': whatWeDoBodyBn,
      if (heroImageUrl != null) 'hero_image_url': heroImageUrl,
      if (sectionsJson != null) 'sections_json': sectionsJson,
      'is_published': isPublished,
    };
  }
}


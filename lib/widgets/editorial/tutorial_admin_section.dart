import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/tutorial.dart';
import '../../services/tutorial_service.dart';
import '../../services/push_notification_service.dart';
import '../scientific_text.dart';

class TutorialAdminSection extends StatefulWidget {
  final VoidCallback onUploadComplete;

  const TutorialAdminSection({
    super.key,
    required this.onUploadComplete,
  });

  @override
  State<TutorialAdminSection> createState() =>
      _TutorialAdminSectionState();
}

class _TutorialAdminSectionState
    extends State<TutorialAdminSection> {
  final TutorialService _tutorialService =
      TutorialService();

  List<Tutorial> _tutorials = [];
  bool _isLoading = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadTutorials();
  }

  Future<void> _loadTutorials() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final list =
          await _tutorialService.fetchAllTutorials(
        filter: _filter,
      );

      if (mounted) {
        setState(() {
          _tutorials = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handlePublishStatusToggle(
    Tutorial tutorial,
  ) async {
    try {
      if (tutorial.isPublished) {
        await _tutorialService.unpublishTutorial(
          tutorial.id,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'টিউটোরিয়াল খসড়া অবস্থায় রাখা হয়েছে / Tutorial unpublished.',
              ),
            ),
          );
        }
      } else {
        await _tutorialService.publishTutorial(
          tutorial.id,
        );

        // Publishing Rule:
        // Send notification ONLY on unpublished -> published.
        await AppNotifier.notify(
          title:
              '📚 নতুন টিউটোরিয়াল প্রকাশিত: ${tutorial.title}',
          body: tutorial.snippet?.isNotEmpty == true
              ? tutorial.snippet!
              : 'বন্যপ্রাণী ও প্রকৃতি বিষয়ক নতুন নির্দেশিকা দেখুন।',
          data: {
            'type': 'tutorial',
            'id': tutorial.id,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'টিউটোরিয়াল সফলভাবে প্রকাশিত হয়েছে! / Tutorial published successfully!',
              ),
            ),
          );
        }
      }

      _loadTutorials();
      widget.onUploadComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error toggling publish: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(
    Tutorial tutorial,
  ) async {
    final bool? confirm =
        await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            const Color(0xFF18221B),
        title: const Text(
          '🗑 Delete Tutorial Record',
          style: TextStyle(
            color: Colors.white,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${tutorial.title}"?\n'
          '(আপনি কি নিশ্চিত যে টিউটোরিয়াল নির্দেশিকাটি স্থায়ীভাবে মুছে ফেলতে চান?)',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.white54,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  Colors.redAccent,
            ),
            onPressed: () =>
                Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _tutorialService.deleteTutorial(
        tutorial.id,
        storagePath: tutorial.storagePath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'টিউটোরিয়ালটি স্থায়ীভাবে মুছে ফেলা হয়েছে / Tutorial deleted.',
            ),
          ),
        );

        _loadTutorials();
        widget.onUploadComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error deleting tutorial: $e',
            ),
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?>
      _importSourceArticle(
    String url,
  ) async {
    final cleanUrl = url.trim();

    if (cleanUrl.isEmpty) {
      throw Exception(
        'Please enter a source article URL.',
      );
    }

    Uri? parsed;

    try {
      parsed = Uri.parse(cleanUrl);
    } catch (_) {
      throw Exception(
        'The source URL is not valid.',
      );
    }

    if (!parsed.hasScheme ||
        !(parsed.scheme == 'http' ||
            parsed.scheme == 'https')) {
      throw Exception(
        'Only HTTP/HTTPS article URLs are supported.',
      );
    }

    final response =
        await Supabase.instance.client.functions
            .invoke(
      'import-tutorial-source',
      body: {
        'url': cleanUrl,
      },
    );

    final dynamic data =
        response.data;

    if (data is! Map) {
      throw Exception(
        'The source importer returned an invalid response.',
      );
    }

    final map =
        Map<String, dynamic>.from(data);

    if (map['success'] != true) {
      final error =
          map['error']?.toString();

      throw Exception(
        error?.isNotEmpty == true
            ? error!
            : 'Unable to import the source article.',
      );
    }

    final article =
        map['article'];

    if (article is! Map) {
      throw Exception(
        'No article data was returned.',
      );
    }

    return Map<String, dynamic>.from(
      article,
    );
  }


  /// Translates an imported source article into Bengali through the
  /// server-side Gemini free-tier tutorial translator.
  ///
  /// The API key never reaches Flutter. The Edge Function also enforces
  /// editor/admin access. Translation is editorial: the result is placed
  /// into the editable fields and is NOT published automatically.
  Future<Map<String, dynamic>> _translateTutorialSource({
    required String title,
    required String description,
    required String articleText,
    required String sourceUrl,
    required List<dynamic> contentBlocks,
  }) async {
    final response =
        await Supabase.instance.client.functions.invoke(
      'translate-tutorial-source',
      body: {
        'title': title,
        'description': description,
        'articleText': articleText,
        'contentBlocks': contentBlocks,
        'sourceUrl': sourceUrl,
      },
    );

    final dynamic data = response.data;

    if (data is! Map) {
      throw Exception(
        'The Bengali tutorial translator returned an invalid response.',
      );
    }

    final map = Map<String, dynamic>.from(data);

    if (map['success'] != true) {
      final error = map['error']?.toString().trim();

      throw Exception(
        error?.isNotEmpty == true
            ? error!
            : 'Bengali translation failed.',
      );
    }

    return map;
  }

  /// Builds a deterministic Pollinations AI image URL for cases where
  /// the source article has no usable image.
  ///
  /// This is intentionally a URL-based fallback so the editor does not
  /// need to upload or manually create an image. The generated image is
  /// clearly marked as AI-generated in image provenance.
  String _buildPollinationsFallbackImageUrl({
    required String title,
    String? category,
  }) {
    final topic = [
      title.trim(),
      if (category != null && category.trim().isNotEmpty)
        category.trim(),
    ].join(' — ');

    final prompt =
        'Create a realistic high-quality wildlife and nature photograph '
        'for an educational eAranyak tutorial about $topic. '
        'Natural outdoor setting, scientifically plausible wildlife, '
        'documentary photography style, no text, no watermark, '
        'no logos, landscape composition.';

    return 'https://image.pollinations.ai/prompt/${Uri.encodeComponent(prompt)}'
        '?width=1280&height=720&nologo=true';
  }

  String? _firstImportedImage(Map<String, dynamic> article) {
    final primary = article['primaryImage']?.toString().trim();
    if (primary != null && primary.isNotEmpty) return primary;

    final images = article['images'];
    if (images is List) {
      for (final item in images) {
        if (item is String) {
          final url = item.trim();
          if (url.isNotEmpty) return url;
        } else if (item is Map) {
          final url = (item['url'] ?? item['src'] ?? '').toString().trim();
          if (url.isNotEmpty) return url;
        }
      }
    }

    final blocks = article['contentBlocks'];
    if (blocks is List) {
      for (final block in blocks) {
        if (block is! Map) continue;
        final type = (block['type'] ?? '').toString().toLowerCase();
        if (type != 'image') continue;
        final url = (block['url'] ?? block['src'] ?? '').toString().trim();
        if (url.isNotEmpty) return url;
      }
    }

    return null;
  }

  List<String> _importedImageUrls(Map<String, dynamic> article) {
    final result = <String>[];
    final seen = <String>{};

    void add(String? value) {
      final url = value?.trim() ?? '';
      if (url.isEmpty || seen.contains(url)) return;
      seen.add(url);
      result.add(url);
    }

    final primary = article['primaryImage']?.toString();
    add(primary);

    final images = article['images'];
    if (images is List) {
      for (final item in images) {
        if (item is String) {
          add(item);
        } else if (item is Map) {
          add((item['url'] ?? item['src'])?.toString());
        }
      }
    }

    final blocks = article['contentBlocks'];
    if (blocks is List) {
      for (final block in blocks) {
        if (block is! Map) continue;
        if ((block['type'] ?? '').toString().toLowerCase() != 'image') {
          continue;
        }
        add((block['url'] ?? block['src'])?.toString());
      }
    }

    return result;
  }

  void _showAddOrEditDialog({
    Tutorial? existingItem,
  }) {
    final isEditing =
        existingItem != null;

    final titleCtrl =
        TextEditingController(
      text: existingItem?.title ?? '',
    );

    final snippetCtrl =
        TextEditingController(
      text: existingItem?.snippet ?? '',
    );

    final descCtrl =
        TextEditingController(
      text: existingItem?.description ?? '',
    );

    final resourceUrlCtrl =
        TextEditingController(
      text: existingItem?.resourceUrl ?? '',
    );

    final durationCtrl =
        TextEditingController(
      text:
          existingItem?.durationMinutes?.toString() ??
              '',
    );

    final categoryCtrl =
        TextEditingController(
      text:
          existingItem?.category ??
              'General',
    );

    final sourceUrlCtrl =
        TextEditingController(
      text:
          existingItem?.sourceUrl ??
              '',
    );

    String resourceType =
        existingItem?.resourceType ??
            'video';

    String difficulty =
        existingItem?.difficulty ??
            'beginner';

    int priority =
        existingItem?.editorialPriority ??
            10;

    bool isFeatured =
        existingItem?.isFeatured ??
            false;

    bool isPublished =
        existingItem?.isPublished ??
            false;

    String? sourceName =
        existingItem?.sourceName;

    String? sourceArticleId =
        existingItem?.sourceArticleId;

    String? translationProvider =
        existingItem?.translationProvider;

    String? imageProvenance =
        existingItem?.imageProvenance;

    PlatformFile? selectedResourceFile;
    PlatformFile? selectedThumbnail;

    bool isUploading = false;
    bool isImportingSource = false;
    bool sourceImported = false;

    // Source-image state is kept separately from resourceUrl.
    // resourceUrl is the article URL; thumbnailUrl is the image URL.
    String? importedPrimaryImage;
    List<String> importedImageUrls = [];

    // Ordered source/translated article blocks. The translated blocks are
    // kept separately from the legacy description field so images, headings,
    // paragraphs and lists can later be persisted in tutorials.content_blocks.
    List<dynamic> translatedContentBlocks = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            final isExternal =
                resourceType ==
                    'external';

            Future<void>
                importArticle() async {
              if (isImportingSource ||
                  isUploading) {
                return;
              }

              final url =
                  sourceUrlCtrl.text
                      .trim();

              if (url.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please enter a source article URL.',
                    ),
                  ),
                );
                return;
              }

              setDialogState(() {
                isImportingSource =
                    true;
              });

              try {
                final article =
                    await _importSourceArticle(
                  url,
                );

                if (article == null) {
                  throw Exception(
                    'No article was returned.',
                  );
                }

                final importedTitle =
                    article['title']
                        ?.toString();

                final importedDescription =
                    article['description']
                        ?.toString();

                final importedText =
                    article['articleText']
                        ?.toString();

                final importedUrl =
                    article['url']
                        ?.toString();

                final importedSourceName =
                    article['sourceName']
                        ?.toString();

                final importedCredit =
                    article['imageCredit']
                        ?.toString();

                final extractedPrimaryImage =
                    _firstImportedImage(article);
                final extractedImages =
                    _importedImageUrls(article);

                // ---------------------------------------------------------
                // BENGALI TRANSLATION
                // ---------------------------------------------------------
                // Translation happens server-side through the dedicated
                // Gemini free-tier tutorial translator. The editor receives
                // Bengali text in the editable fields before saving.
                final rawTitle =
                    importedTitle?.trim() ?? '';
                final rawDescription =
                    importedDescription?.trim() ?? '';
                final rawArticleText =
                    importedText?.trim() ?? '';

                final rawContentBlocks =
                    article['contentBlocks'] is List
                        ? List<dynamic>.from(
                            article['contentBlocks'] as List,
                          )
                        : <dynamic>[];

                final rawSourceUrl =
                    importedUrl?.trim().isNotEmpty == true
                        ? importedUrl!.trim()
                        : url;

                if (rawTitle.isEmpty ||
                    rawArticleText.isEmpty ||
                    rawContentBlocks.isEmpty) {
                  throw Exception(
                    'The source article did not contain enough structured content to translate.',
                  );
                }

                final translated =
                    await _translateTutorialSource(
                  title: rawTitle,
                  description: rawDescription,
                  articleText: rawArticleText,
                  contentBlocks: rawContentBlocks,
                  sourceUrl: rawSourceUrl,
                );

                final translatedTitle =
                    translated['title']?.toString().trim();
                final translatedSnippet =
                    translated['snippet']?.toString().trim();
                final translatedBody =
                    translated['description']?.toString().trim();
                final translatedProvider =
                    translated['provider']?.toString().trim();

                final returnedContentBlocks =
                    translated['contentBlocks'] is List
                        ? List<dynamic>.from(
                            translated['contentBlocks'] as List,
                          )
                        : <dynamic>[];

                if (translatedTitle == null ||
                    translatedTitle.isEmpty ||
                    translatedSnippet == null ||
                    translatedSnippet.isEmpty ||
                    translatedBody == null ||
                    translatedBody.isEmpty ||
                    returnedContentBlocks.isEmpty) {
                  throw Exception(
                    'The Bengali translator returned incomplete structured tutorial content.',
                  );
                }

                setDialogState(() {
                  titleCtrl.text =
                      translatedTitle;

                  snippetCtrl.text =
                      translatedSnippet;

                  descCtrl.text =
                      translatedBody;

                  if (importedUrl
                          ?.trim()
                          .isNotEmpty ==
                      true) {
                    sourceUrlCtrl.text =
                        importedUrl!.trim();
                  }

                  if (importedSourceName
                          ?.trim()
                          .isNotEmpty ==
                      true) {
                    sourceName =
                        importedSourceName!
                            .trim();
                  }

                  resourceType = 'article';

                  // IMPORTANT: resourceUrl is the source ARTICLE URL, not
                  // the image URL. The image is stored in thumbnailUrl
                  // when the tutorial is saved.
                  if (importedUrl?.trim().isNotEmpty == true) {
                    resourceUrlCtrl.text = importedUrl!.trim();
                  }

                  importedPrimaryImage = extractedPrimaryImage;
                  importedImageUrls = extractedImages;

                  // Keep the translated ordered blocks intact for the next
                  // persistence step. The blocks are not flattened into the
                  // description field.
                  translatedContentBlocks = returnedContentBlocks;

                  if (importedPrimaryImage == null ||
                      importedPrimaryImage!.trim().isEmpty) {
                    importedPrimaryImage =
                        _buildPollinationsFallbackImageUrl(
                      title: importedTitle?.trim().isNotEmpty == true
                          ? importedTitle!.trim()
                          : 'Wildlife and Nature Tutorial',
                      category: categoryCtrl.text,
                    );
                    importedImageUrls = [importedPrimaryImage!];
                    imageProvenance = 'Pollinations AI — fallback image';
                  }

                  if (imageProvenance == null ||
                      imageProvenance!.trim().isEmpty) {
                    imageProvenance =
                        importedCredit?.trim().isNotEmpty == true
                            ? importedCredit!.trim()
                            : sourceName;
                  }

                  if (importedPrimaryImage != null &&
                      importedPrimaryImage!.isNotEmpty) {
                    // No manual thumbnail upload is required when the
                    // source already provides an image.
                  }

                  if (imageProvenance == null ||
                      imageProvenance!.trim().isEmpty) {
                    imageProvenance = sourceName;
                  }

                  sourceArticleId =
                      null;

                  translationProvider =
                      translatedProvider?.isNotEmpty == true
                          ? translatedProvider
                          : 'Gemini 2.5 Flash — free tier';

                  sourceImported = true;
                });

                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Source imported and translated into Bengali'
                        '${sourceName != null ? ' from $sourceName' : ''}. '
                        'Please review before saving.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Source import failed: $e',
                      ),
                    ),
                  );
                }
              } finally {
                if (context.mounted) {
                  setDialogState(() {
                    isImportingSource =
                        false;
                  });
                }
              }
            }

            return AlertDialog(
              backgroundColor:
                  const Color(0xFF18221B),
              title: Text(
                isEditing
                    ? '✏️ Edit Tutorial Guide'
                    : '📚 Add New Tutorial Guide',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      // =====================================================
                      // SOURCE ARTICLE IMPORT
                      // =====================================================
                      Container(
                        padding:
                            const EdgeInsets.all(
                          12,
                        ),
                        decoration:
                            BoxDecoration(
                          color:
                              const Color(
                            0xFF0D2818,
                          ),
                          borderRadius:
                              BorderRadius.circular(
                            10,
                          ),
                          border:
                              Border.all(
                            color:
                                const Color(
                              0xFF2E7D32,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            const Text(
                              '🌐 Import From Source Article',
                              style:
                                  TextStyle(
                                color:
                                    Color(
                                  0xFF00E676,
                                ),
                                fontWeight:
                                    FontWeight.bold,
                                fontSize:
                                    15,
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            const Text(
                              'Paste an article URL to import the source article '
                              'and translate it into Bengali. Nothing is published automatically.',
                              style:
                                  TextStyle(
                                color:
                                    Colors.white70,
                                fontSize:
                                    11,
                              ),
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            TextField(
                              controller:
                                  sourceUrlCtrl,
                              enabled:
                                  !isImportingSource &&
                                      !isUploading,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'Source Article URL',
                                hintText:
                                    'https://example.com/article',
                                labelStyle:
                                    TextStyle(
                                  color:
                                      Colors.grey,
                                ),
                                hintStyle:
                                    TextStyle(
                                  color:
                                      Colors.white30,
                                ),
                                border:
                                    OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  style:
                                      ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(
                                      0xFF2E7D32,
                                    ),
                                  ),
                                  onPressed:
                                      isImportingSource ||
                                              isUploading
                                          ? null
                                          : importArticle,
                                  icon:
                                      isImportingSource
                                          ? const SizedBox(
                                              width:
                                                  16,
                                              height:
                                                  16,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth:
                                                    2,
                                                color:
                                                    Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons
                                                  .download_rounded,
                                              color:
                                                  Colors.white,
                                            ),
                                  label:
                                      Text(
                                    isImportingSource
                                        ? 'Importing...'
                                        : 'Import & Translate to Bengali',
                                    style:
                                        const TextStyle(
                                      color:
                                          Colors.white,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: 10,
                                ),
                                if (sourceImported)
                                  const Expanded(
                                    child:
                                        Text(
                                      '✓ Source imported — review and edit before saving.',
                                      style:
                                          TextStyle(
                                        color:
                                            Color(
                                          0xFF81C784,
                                        ),
                                        fontSize:
                                            11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (sourceImported &&
                                importedPrimaryImage != null &&
                                importedPrimaryImage!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: importedPrimaryImage!,
                                  height: 170,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => const SizedBox(
                                    height: 170,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF00E676),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    height: 170,
                                    width: double.infinity,
                                    color: Colors.black26,
                                    alignment: Alignment.center,
                                    child: const Text(
                                      'Image preview unavailable',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                imageProvenance?.contains('Pollinations') == true
                                    ? '🖼️ Pollinations AI fallback image'
                                    : '🖼️ Source image • ${importedImageUrls.length} image(s) detected',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                            ],

                            if (sourceImported &&
                                translatedContentBlocks.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '✓ Structured tutorial: ${translatedContentBlocks.length} blocks '
                                '(text + headings + images + lists)',
                                style: const TextStyle(
                                  color: Color(0xFF81C784),
                                  fontSize: 10,
                                ),
                              ),
                            ],

                            if (sourceName !=
                                    null &&
                                sourceName!
                                    .isNotEmpty) ...[
                              const SizedBox(
                                height: 8,
                              ),
                              Text(
                                'Source: $sourceName',
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white70,
                                  fontSize:
                                      11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      // =====================================================
                      // BASIC TUTORIAL DETAILS
                      // =====================================================
                      TextField(
                        controller:
                            titleCtrl,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Tutorial Title (টিউটোরিয়ালের শিরোনাম) *',
                          labelStyle:
                              TextStyle(
                            color:
                                Colors.grey,
                          ),
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      Row(
                        children: [
                          Expanded(
                            child:
                                DropdownButtonFormField<
                                    String>(
                              initialValue:
                                  resourceType,
                              dropdownColor:
                                  const Color(
                                0xFF18221B,
                              ),
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'Resource Type (ধরণ)',
                                border:
                                    OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value:
                                      'video',
                                  child:
                                      Text(
                                    '📹 Video',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value:
                                      'pdf',
                                  child:
                                      Text(
                                    '📄 PDF',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value:
                                      'article',
                                  child:
                                      Text(
                                    '📝 Article',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value:
                                      'external',
                                  child:
                                      Text(
                                    '🌐 External Link',
                                  ),
                                ),
                              ],
                              onChanged:
                                  (val) {
                                if (val !=
                                    null) {
                                  setDialogState(
                                    () =>
                                        resourceType =
                                            val,
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Expanded(
                            child:
                                DropdownButtonFormField<
                                    String>(
                              initialValue:
                                  difficulty,
                              dropdownColor:
                                  const Color(
                                0xFF18221B,
                              ),
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'Difficulty (কঠিনতা)',
                                border:
                                    OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value:
                                      'beginner',
                                  child:
                                      Text(
                                    '🌱 Beginner',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value:
                                      'intermediate',
                                  child:
                                      Text(
                                    '🌿 Intermediate',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value:
                                      'advanced',
                                  child:
                                      Text(
                                    '🌳 Advanced',
                                  ),
                                ),
                              ],
                              onChanged:
                                  (val) {
                                if (val !=
                                    null) {
                                  setDialogState(
                                    () =>
                                        difficulty =
                                            val,
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      TextField(
                        controller:
                            snippetCtrl,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Short Snippet (সংক্ষিপ্ত বর্ণনা)',
                          labelStyle:
                              TextStyle(
                            color:
                                Colors.grey,
                          ),
                          border:
                              OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      TextField(
                        controller:
                            descCtrl,
                        maxLines: 8,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Full Content / Instructions (বিস্তারিত বিষয়বস্তু)',
                          labelStyle:
                              TextStyle(
                            color:
                                Colors.grey,
                          ),
                          border:
                              OutlineInputBorder(),
                          alignLabelWithHint:
                              true,
                        ),
                      ),

                      if (sourceImported &&
                          translatedContentBlocks.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'The full article structure is retained separately; '
                          'this field remains the legacy summary/description field.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],

                      const SizedBox(
                        height: 12,
                      ),

                      Row(
                        children: [
                          Expanded(
                            child:
                                TextField(
                              controller:
                                  categoryCtrl,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'Category',
                                border:
                                    OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Expanded(
                            child:
                                TextField(
                              controller:
                                  durationCtrl,
                              keyboardType:
                                  TextInputType
                                      .number,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'Duration (Minutes)',
                                border:
                                    OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Expanded(
                            child:
                                DropdownButtonFormField<
                                    int>(
                              initialValue:
                                  priority,
                              dropdownColor:
                                  const Color(
                                0xFF18221B,
                              ),
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'Priority',
                                border:
                                    OutlineInputBorder(),
                              ),
                              items: [
                                1,
                                5,
                                10,
                                20,
                                50,
                                100,
                              ]
                                  .map(
                                    (
                                      p,
                                    ) =>
                                        DropdownMenuItem(
                                      value:
                                          p,
                                      child:
                                          Text(
                                        '$p',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged:
                                  (val) {
                                if (val !=
                                    null) {
                                  setDialogState(
                                    () =>
                                        priority =
                                            val,
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      if (isExternal)
                        TextField(
                          controller:
                              resourceUrlCtrl,
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                          ),
                          decoration:
                              const InputDecoration(
                            labelText:
                                'External Web Resource URL (বাহ্যিক লিংক) *',
                            labelStyle:
                                TextStyle(
                              color:
                                  Colors.grey,
                            ),
                            border:
                                OutlineInputBorder(),
                          ),
                        )
                      else ...[
                        ElevatedButton.icon(
                          style:
                              ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(
                              0xFF2E7D32,
                            ),
                          ),
                          onPressed:
                              isUploading ||
                                      isImportingSource
                                  ? null
                                  : () async {
                                      FileType type =
                                          FileType.any;

                                      List<String>?
                                          exts;

                                      if (resourceType ==
                                          'pdf') {
                                        type =
                                            FileType.custom;
                                        exts =
                                            [
                                          'pdf'
                                        ];
                                      } else if (resourceType ==
                                          'video') {
                                        type =
                                            FileType.video;
                                      }

                                      final picked =
                                          await FilePicker.pickFile(
                                        type:
                                            type,
                                        allowedExtensions:
                                            exts,
                                      );

                                      if (picked !=
                                          null) {
                                        setDialogState(
                                          () =>
                                              selectedResourceFile =
                                                  picked,
                                        );
                                      }
                                    },
                          icon:
                              const Icon(
                            Icons.upload_file,
                            color:
                                Colors.white,
                          ),
                          label:
                              Text(
                            selectedResourceFile !=
                                    null
                                ? 'Selected Resource: ${selectedResourceFile!.name}'
                                : (isEditing
                                    ? 'Replace Resource File (ঐচ্ছিক)'
                                    : 'Select Resource File ($resourceType)'),
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                      ],

                      ElevatedButton.icon(
                        style:
                            ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(
                            0xFF1B5E20,
                          ),
                        ),
                        onPressed:
                            isUploading ||
                                    isImportingSource
                                ? null
                                : () async {
                                    final picked =
                                        await FilePicker.pickFile(
                                      type:
                                          FileType.image,
                                    );

                                    if (picked !=
                                        null) {
                                      setDialogState(
                                        () =>
                                            selectedThumbnail =
                                                picked,
                                      );
                                    }
                                  },
                        icon:
                            const Icon(
                          Icons.image,
                          color:
                              Colors.white,
                        ),
                        label:
                            Text(
                          selectedThumbnail !=
                                  null
                              ? 'Selected Thumbnail: ${selectedThumbnail!.name}'
                              : 'Select Thumbnail Image',
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      if (sourceImported &&
                          sourceName != null)
                        Container(
                          width:
                              double.infinity,
                          padding:
                              const EdgeInsets.all(
                            10,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                Colors.white.withValues(
                              alpha:
                                  0.04,
                            ),
                            borderRadius:
                                BorderRadius.circular(
                              8,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              const Text(
                                '📌 Source Provenance',
                                style:
                                    TextStyle(
                                  color:
                                      Color(
                                    0xFF81C784,
                                  ),
                                  fontWeight:
                                      FontWeight.bold,
                                  fontSize:
                                      12,
                                ),
                              ),
                              const SizedBox(
                                height: 5,
                              ),
                              Text(
                                'Source: $sourceName',
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white70,
                                  fontSize:
                                      11,
                                ),
                              ),
                              if (imageProvenance !=
                                      null &&
                                  imageProvenance!
                                      .isNotEmpty)
                                Text(
                                  'Image credit: $imageProvenance',
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.white54,
                                    fontSize:
                                        11,
                                  ),
                                ),
                            ],
                          ),
                        ),

                      const SizedBox(
                        height: 8,
                      ),

                      SwitchListTile(
                        value:
                            isFeatured,
                        activeTrackColor:
                            const Color(
                          0xFF00E676,
                        ),
                        title:
                            const Text(
                          'Featured Tutorial',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                          ),
                        ),
                        onChanged:
                            (val) =>
                                setDialogState(
                          () =>
                              isFeatured =
                                  val,
                        ),
                      ),

                      SwitchListTile(
                        value:
                            isPublished,
                        activeTrackColor:
                            const Color(
                          0xFF00E676,
                        ),
                        title:
                            const Text(
                          'Publish Immediately',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                          ),
                        ),
                        subtitle:
                            const Text(
                          'Editor-controlled only',
                          style:
                              TextStyle(
                            color:
                                Colors.white38,
                            fontSize:
                                10,
                          ),
                        ),
                        onChanged:
                            (val) =>
                                setDialogState(
                          () =>
                              isPublished =
                                  val,
                        ),
                      ),

                      if (isUploading)
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(
                            vertical:
                                12,
                          ),
                          child:
                              Center(
                            child:
                                Column(
                              children: [
                                CircularProgressIndicator(
                                  color:
                                      Color(
                                    0xFF00E676,
                                  ),
                                ),
                                SizedBox(
                                  height:
                                      8,
                                ),
                                Text(
                                  'Uploading files to tutorials storage...',
                                  style:
                                      TextStyle(
                                    color:
                                        Colors.grey,
                                    fontSize:
                                        12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isUploading ||
                              isImportingSource
                          ? null
                          : () =>
                              Navigator.pop(ctx),
                  child:
                      const Text(
                    'Cancel',
                    style:
                        TextStyle(
                      color:
                          Colors.white54,
                    ),
                  ),
                ),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(
                      0xFF00E676,
                    ),
                  ),
                  onPressed:
                      isUploading ||
                              isImportingSource
                          ? null
                          : () async {
                              if (titleCtrl
                                  .text
                                  .trim()
                                  .isEmpty) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text(
                                      'Please enter a tutorial title',
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (isExternal &&
                                  resourceUrlCtrl
                                      .text
                                      .trim()
                                      .isEmpty &&
                                  existingItem
                                          ?.resourceUrl ==
                                      null) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text(
                                      'Please enter an external resource URL',
                                    ),
                                  ),
                                );
                                return;
                              }

                              setDialogState(
                                () =>
                                    isUploading =
                                        true,
                              );

                              try {
                                String? resourceUrl;

                                if (isExternal) {
                                  resourceUrl = resourceUrlCtrl.text.trim();
                                } else if (resourceType == 'article' &&
                                    sourceImported &&
                                    sourceUrlCtrl.text.trim().isNotEmpty) {
                                  // For imported tutorials the resource is the
                                  // original article URL, never the image URL.
                                  resourceUrl = sourceUrlCtrl.text.trim();
                                } else {
                                  resourceUrl = existingItem?.resourceUrl;
                                }

                                String?
                                    storagePath =
                                    existingItem
                                        ?.storagePath;

                                String?
                                    thumbnailUrl =
                                    existingItem
                                        ?.thumbnailUrl;

                                if (!isExternal &&
                                    selectedResourceFile !=
                                        null) {
                                  final uploadRes =
                                      await _tutorialService
                                          .uploadFile(
                                    file:
                                        selectedResourceFile!,
                                    subFolder:
                                        'resources',
                                    resourceType:
                                        resourceType,
                                  );

                                  resourceUrl =
                                      uploadRes[
                                          'publicUrl'];

                                  storagePath =
                                      uploadRes[
                                          'storagePath'];
                                }

                                if (selectedThumbnail != null) {
                                  final uploadThumbRes =
                                      await _tutorialService.uploadFile(
                                    file: selectedThumbnail!,
                                    subFolder: 'thumbnails',
                                    resourceType: 'image',
                                  );

                                  thumbnailUrl =
                                      uploadThumbRes['publicUrl'];
                                } else if (sourceImported &&
                                    resourceType == 'article') {
                                  // Prefer the fetched source image. If the
                                  // importer found none, use Pollinations AI.
                                  thumbnailUrl = importedPrimaryImage;

                                  if (thumbnailUrl == null ||
                                      thumbnailUrl.trim().isEmpty) {
                                    thumbnailUrl =
                                        _buildPollinationsFallbackImageUrl(
                                      title: titleCtrl.text.trim(),
                                      category: categoryCtrl.text.trim(),
                                    );
                                    imageProvenance =
                                        'Pollinations AI — fallback image';
                                  }
                                }

                                final durationMin =
                                    int.tryParse(
                                  durationCtrl
                                      .text
                                      .trim(),
                                );

                                if (isEditing) {
                                  final updated =
                                      await _tutorialService
                                          .updateTutorial(
                                    id:
                                        existingItem.id,
                                    title:
                                        titleCtrl.text.trim(),
                                    description:
                                        descCtrl.text.trim(),
                                    snippet:
                                        snippetCtrl.text.trim(),
                                    thumbnailUrl:
                                        thumbnailUrl,
                                    resourceUrl:
                                        resourceUrl,
                                    storagePath:
                                        storagePath,
                                    resourceType:
                                        resourceType,
                                    category:
                                        categoryCtrl.text.trim(),
                                    difficulty:
                                        difficulty,
                                    durationMinutes:
                                        durationMin,
                                    priority:
                                        priority,
                                    isFeatured:
                                        isFeatured,
                                    isPublished:
                                        isPublished,
                                    oldStoragePath:
                                        existingItem.storagePath,

                                    sourceUrl:
                                        sourceUrlCtrl.text.trim().isEmpty
                                            ? null
                                            : sourceUrlCtrl.text.trim(),
                                    sourceName:
                                        sourceName,
                                    sourceArticleId:
                                        sourceArticleId,
                                    translationProvider:
                                        translationProvider,
                                    imageProvenance:
                                        imageProvenance,
                                    contentBlocks:
                                        translatedContentBlocks,
                                  );

                                  // Trigger notification ONLY if
                                  // transitioned from draft -> published.
                                  if (!existingItem.isPublished &&
                                      isPublished) {
                                    await AppNotifier.notify(
                                      title:
                                          '📚 নতুন টিউটোরিয়াল প্রকাশিত: ${updated.title}',
                                      body:
                                          updated.snippet?.isNotEmpty ==
                                                  true
                                              ? updated.snippet!
                                              : 'বন্যপ্রাণী ও প্রকৃতি বিষয়ক নতুন নির্দেশিকা দেখুন।',
                                      data: {
                                        'type':
                                            'tutorial',
                                        'id':
                                            updated.id,
                                      },
                                    );
                                  }
                                } else {
                                  final created =
                                      await _tutorialService
                                          .createTutorial(
                                    title:
                                        titleCtrl.text.trim(),
                                    description:
                                        descCtrl.text.trim(),
                                    snippet:
                                        snippetCtrl.text.trim(),
                                    thumbnailUrl:
                                        thumbnailUrl,
                                    resourceUrl:
                                        resourceUrl,
                                    storagePath:
                                        storagePath,
                                    resourceType:
                                        resourceType,
                                    category:
                                        categoryCtrl.text.trim(),
                                    difficulty:
                                        difficulty,
                                    durationMinutes:
                                        durationMin,
                                    priority:
                                        priority,
                                    isFeatured:
                                        isFeatured,
                                    isPublished:
                                        isPublished,

                                    sourceUrl:
                                        sourceUrlCtrl.text.trim().isEmpty
                                            ? null
                                            : sourceUrlCtrl.text.trim(),
                                    sourceName:
                                        sourceName,
                                    sourceArticleId:
                                        sourceArticleId,
                                    translationProvider:
                                        translationProvider,
                                    imageProvenance:
                                        imageProvenance,
                                    contentBlocks:
                                        translatedContentBlocks,
                                  );

                                  // Notification only if the editor
                                  // deliberately created it as published.
                                  if (isPublished) {
                                    await AppNotifier.notify(
                                      title:
                                          '📚 নতুন টিউটোরিয়াল প্রকাশিত: ${created.title}',
                                      body:
                                          created.snippet?.isNotEmpty ==
                                                  true
                                              ? created.snippet!
                                              : 'বন্যপ্রাণী ও প্রকৃতি বিষয়ক নতুন নির্দেশিকা দেখুন।',
                                      data: {
                                        'type':
                                            'tutorial',
                                        'id':
                                            created.id,
                                      },
                                    );
                                  }
                                }

                                if (ctx.mounted) {
                                  Navigator.pop(
                                    ctx,
                                  );
                                }

                                _loadTutorials();
                                widget
                                    .onUploadComplete();
                              } catch (e) {
                                setDialogState(
                                  () =>
                                      isUploading =
                                          false,
                                );

                                if (ctx.mounted) {
                                  ScaffoldMessenger
                                      .of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text(
                                        'Error saving tutorial: $e',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                  child:
                      Text(
                    isEditing
                        ? 'Update'
                        : 'Save',
                    style:
                        const TextStyle(
                      color:
                          Colors.black,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPreviewDialog(
    Tutorial tutorial,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            const Color(0xFF18221B),
        title: Text(
          '📚 ${tutorial.title}',
          style:
              const TextStyle(
            color:
                Colors.white,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                if (tutorial.thumbnailUrl !=
                        null &&
                    tutorial
                        .thumbnailUrl!
                        .isNotEmpty)
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(
                      8,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: tutorial.thumbnailUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const SizedBox(
                        height: 180,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00E676),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => CachedNetworkImage(
                        imageUrl: _buildPollinationsFallbackImageUrl(
                          title: tutorial.title,
                          category: tutorial.category,
                        ),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          height: 180,
                          width: double.infinity,
                          color: Colors.black26,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.white38,
                            size: 42,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(
                  height: 12,
                ),
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFF2E7D32,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          4,
                        ),
                      ),
                      child:
                          Text(
                        'Type: ${tutorial.resourceType.toUpperCase()}',
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize:
                              11,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.amber
                                .withValues(
                          alpha:
                              0.2,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          4,
                        ),
                      ),
                      child:
                          Text(
                        'Level: ${tutorial.difficulty.toUpperCase()}',
                        style:
                            const TextStyle(
                          color:
                              Colors.amber,
                          fontSize:
                              11,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 8,
                ),
                if (tutorial.snippet
                        ?.isNotEmpty ==
                    true)
                  Text(
                    tutorial.snippet!,
                    style:
                        const TextStyle(
                      color:
                          Colors.white70,
                      fontSize:
                          13,
                    ),
                  ),
                if (tutorial.durationMinutes !=
                    null)
                  Text(
                    'Duration: ${tutorial.durationMinutes} mins',
                    style:
                        const TextStyle(
                      color:
                          Colors.grey,
                      fontSize:
                          12,
                    ),
                  ),
                if (tutorial.sourceName
                        ?.isNotEmpty ==
                    true) ...[
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Source: ${tutorial.sourceName}',
                    style:
                        const TextStyle(
                      color:
                          Color(
                        0xFF81C784,
                      ),
                      fontSize:
                          11,
                    ),
                  ),
                ],
                if (tutorial.sourceUrl
                        ?.isNotEmpty ==
                    true) ...[
                  const SizedBox(
                    height: 4,
                  ),
                  SelectableText(
                    'Source URL: ${tutorial.sourceUrl}',
                    style:
                        const TextStyle(
                      color:
                          Colors.lightBlueAccent,
                      fontSize:
                          11,
                    ),
                  ),
                ],
                if (tutorial.translationProvider
                        ?.isNotEmpty ==
                    true)
                  Text(
                    'Translation: ${tutorial.translationProvider}',
                    style:
                        const TextStyle(
                      color:
                          Colors.white54,
                      fontSize:
                          11,
                    ),
                  ),
                if (tutorial.resourceUrl
                        ?.isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    tutorial.resourceType == 'article'
                        ? 'Article URL: ${tutorial.resourceUrl}'
                        : 'Resource: ${tutorial.resourceUrl}',
                    style:
                        const TextStyle(
                      color:
                          Colors.lightBlueAccent,
                      fontSize:
                          11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx),
            child:
                const Text(
              'Close',
              style:
                  TextStyle(
                color:
                    Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const SizedBox(
          height: 28,
        ),
        const Divider(
          color:
              Colors.white24,
        ),
        const SizedBox(
          height: 16,
        ),
        Row(
          mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
          children: [
            const Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  '📚 Tutorial Management — টিউটোরিয়াল ও নির্দেশিকা নিয়ন্ত্রণ',
                  style:
                      TextStyle(
                    fontSize:
                        18,
                    fontWeight:
                        FontWeight.bold,
                    color:
                        Colors.white,
                  ),
                ),
                Text(
                  '(শিক্ষামূলক নির্দেশিকা প্রকাশ, সম্পাদনা ও সংস্থান নিয়ন্ত্রণ — Public UI Coming Soon in Phase 7C)',
                  style:
                      TextStyle(
                    fontSize:
                        11,
                    color:
                        Color(
                      0xFF81C784,
                    ),
                  ),
                ),
              ],
            ),
            IconButton(
              icon:
                  const Icon(
                Icons.refresh,
                color:
                    Color(
                  0xFF00E676,
                ),
              ),
              tooltip:
                  'রিফ্রেশ করুন',
              onPressed:
                  _loadTutorials,
            ),
          ],
        ),
        const SizedBox(
          height: 12,
        ),
        ElevatedButton.icon(
          style:
              ElevatedButton.styleFrom(
            backgroundColor:
                const Color(
              0xFF2E7D32,
            ),
            padding:
                const EdgeInsets
                    .symmetric(
              horizontal:
                  14,
              vertical:
                  10,
            ),
          ),
          onPressed:
              () =>
                  _showAddOrEditDialog(),
          icon:
              const Icon(
            Icons.menu_book,
            size:
                18,
            color:
                Colors.white,
          ),
          label:
              const Text(
            '➕ নতুন টিউটোরিয়াল যোগ করুন',
            style:
                TextStyle(
              color:
                  Colors.white,
              fontWeight:
                  FontWeight.bold,
              fontSize:
                  13,
            ),
          ),
        ),
        const SizedBox(
          height: 12,
        ),

        // Filter chips
        SingleChildScrollView(
          scrollDirection:
              Axis.horizontal,
          child: Row(
            children: [
              {
                'id':
                    'all',
                'label':
                    'সবগুলো'
              },
              {
                'id':
                    'published',
                'label':
                    'প্রকাশিত'
              },
              {
                'id':
                    'draft',
                'label':
                    'খসড়া'
              },
              {
                'id':
                    'video',
                'label':
                    '📹 Video'
              },
              {
                'id':
                    'pdf',
                'label':
                    '📄 PDF'
              },
              {
                'id':
                    'article',
                'label':
                    '📝 Article'
              },
              {
                'id':
                    'external',
                'label':
                    '🌐 External'
              },
            ].map((f) {
              final isSelected =
                  _filter ==
                      f['id'];

              return Padding(
                padding:
                    const EdgeInsets.only(
                  right:
                      8.0,
                ),
                child:
                    ChoiceChip(
                  label:
                      Text(
                    f['label']!,
                    style:
                        TextStyle(
                      color: isSelected
                          ? Colors.black
                          : Colors.white70,
                      fontWeight:
                          isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                      fontSize:
                          12,
                    ),
                  ),
                  selected:
                      isSelected,
                  selectedColor:
                      const Color(
                    0xFF00E676,
                  ),
                  backgroundColor:
                      const Color(
                    0xFF18221B,
                  ),
                  onSelected:
                      (val) {
                    if (val) {
                      setState(
                        () =>
                            _filter =
                                f['id']!,
                      );
                      _loadTutorials();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(
          height: 12,
        ),

        if (_isLoading)
          const Center(
            child:
                CircularProgressIndicator(
              color:
                  Color(
                0xFF00E676,
              ),
            ),
          )
        else if (_tutorials.isEmpty)
          const Padding(
            padding:
                EdgeInsets.symmetric(
              vertical:
                  16.0,
            ),
            child:
                Text(
              'কোনো টিউটোরিয়াল পাওয়া যায়নি।',
              style:
                  TextStyle(
                color:
                    Colors.grey,
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap:
                true,
            physics:
                const NeverScrollableScrollPhysics(),
            itemCount:
                _tutorials.length,
            itemBuilder:
                (context, index) {
              final item =
                  _tutorials[index];

              final statusColor =
                  item.isPublished
                      ? const Color(
                          0xFF00E676,
                        )
                      : Colors.amber;

              final statusText =
                  item.isPublished
                      ? 'প্রকাশিত'
                      : 'খসড়া (Draft)';

              return Card(
                color:
                    const Color(
                  0xFF18221B,
                ),
                margin:
                    const EdgeInsets
                        .only(
                  bottom:
                      12,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius
                          .circular(
                    10,
                  ),
                  side:
                      BorderSide(
                    color:
                        statusColor
                            .withValues(
                      alpha:
                          0.4,
                    ),
                  ),
                ),
                child:
                    Padding(
                  padding:
                      const EdgeInsets
                          .all(
                    12,
                  ),
                  child:
                      Row(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Container(
                        width:
                            80,
                        height:
                            70,
                        decoration:
                            BoxDecoration(
                          color:
                              Colors.black26,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            8,
                          ),
                        ),
                        child: item
                                    .thumbnailUrl !=
                                null &&
                            item
                                .thumbnailUrl!
                                .isNotEmpty
                            ? ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(
                                  8,
                                ),
                                child:
                                    CachedNetworkImage(
                                  imageUrl:
                                      item.thumbnailUrl!,
                                  fit:
                                      BoxFit.cover,
                                ),
                              )
                            : const Icon(
                                Icons
                                    .school_rounded,
                                color:
                                    Color(
                                  0xFF81C784,
                                ),
                                size:
                                    36,
                              ),
                      ),
                      const SizedBox(
                        width:
                            12,
                      ),
                      Expanded(
                        child:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            ScientificText(
                              item.title,
                              style:
                                  const TextStyle(
                                fontSize:
                                    15,
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Colors.white,
                              ),
                            ),
                            if (item.snippet
                                    ?.isNotEmpty ==
                                true) ...[
                              const SizedBox(
                                height:
                                    4,
                              ),
                              Text(
                                item.snippet!,
                                maxLines:
                                    2,
                                overflow:
                                    TextOverflow.ellipsis,
                                style:
                                    const TextStyle(
                                  fontSize:
                                      12,
                                  color:
                                      Colors.white70,
                                ),
                              ),
                            ],
                            const SizedBox(
                              height:
                                  6,
                            ),
                            Wrap(
                              spacing:
                                  6,
                              runSpacing:
                                  4,
                              children: [
                                Container(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                    horizontal:
                                        6,
                                    vertical:
                                        2,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        statusColor.withValues(
                                      alpha:
                                          0.2,
                                    ),
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      4,
                                    ),
                                    border:
                                        Border.all(
                                      color:
                                          statusColor,
                                      width:
                                          0.8,
                                    ),
                                  ),
                                  child:
                                      Text(
                                    statusText,
                                    style:
                                        TextStyle(
                                      fontSize:
                                          10,
                                      fontWeight:
                                          FontWeight.bold,
                                      color:
                                          statusColor,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                    horizontal:
                                        6,
                                    vertical:
                                        2,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        Colors.white12,
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      4,
                                    ),
                                  ),
                                  child:
                                      Text(
                                    'Type: ${item.resourceType.toUpperCase()}',
                                    style:
                                        const TextStyle(
                                      fontSize:
                                          10,
                                      color:
                                          Colors.white70,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                    horizontal:
                                        6,
                                    vertical:
                                        2,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        const Color(
                                      0xFF2E7D32,
                                    ).withValues(
                                      alpha:
                                          0.3,
                                    ),
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      4,
                                    ),
                                  ),
                                  child:
                                      Text(
                                    'Difficulty: ${item.difficulty.toUpperCase()}',
                                    style:
                                        const TextStyle(
                                      fontSize:
                                          10,
                                      color:
                                          Color(
                                        0xFF81C784,
                                      ),
                                    ),
                                  ),
                                ),
                                if (item.sourceName
                                        ?.isNotEmpty ==
                                    true)
                                  Container(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                      horizontal:
                                          6,
                                      vertical:
                                          2,
                                    ),
                                    decoration:
                                        BoxDecoration(
                                      color:
                                          Colors.blue.withValues(
                                        alpha:
                                            0.12,
                                      ),
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        4,
                                      ),
                                    ),
                                    child:
                                        Text(
                                      'Source: ${item.sourceName}',
                                      style:
                                          const TextStyle(
                                        fontSize:
                                            10,
                                        color:
                                            Colors.lightBlueAccent,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(
                              height:
                                  10,
                            ),
                            Wrap(
                              spacing:
                                  6,
                              runSpacing:
                                  6,
                              children: [
                                OutlinedButton.icon(
                                  style:
                                      OutlinedButton.styleFrom(
                                    foregroundColor:
                                        Colors.white,
                                    side:
                                        const BorderSide(
                                      color:
                                          Colors.white38,
                                    ),
                                    visualDensity:
                                        VisualDensity.compact,
                                  ),
                                  onPressed:
                                      () =>
                                          _showPreviewDialog(
                                    item,
                                  ),
                                  icon:
                                      const Icon(
                                    Icons
                                        .visibility,
                                    size:
                                        16,
                                  ),
                                  label:
                                      const Text(
                                    'প্রিভিউ',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style:
                                      OutlinedButton.styleFrom(
                                    foregroundColor:
                                        const Color(
                                      0xFF81C784,
                                    ),
                                    side:
                                        const BorderSide(
                                      color:
                                          Color(
                                        0xFF81C784,
                                      ),
                                    ),
                                    visualDensity:
                                        VisualDensity.compact,
                                  ),
                                  onPressed:
                                      () =>
                                          _showAddOrEditDialog(
                                    existingItem:
                                        item,
                                  ),
                                  icon:
                                      const Icon(
                                    Icons
                                        .edit,
                                    size:
                                        16,
                                  ),
                                  label:
                                      const Text(
                                    'সম্পাদনা',
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style:
                                      ElevatedButton.styleFrom(
                                    backgroundColor:
                                        item.isPublished
                                            ? Colors.orange.shade800
                                            : const Color(
                                                0xFF00E676,
                                              ),
                                    visualDensity:
                                        VisualDensity.compact,
                                  ),
                                  onPressed:
                                      () =>
                                          _handlePublishStatusToggle(
                                    item,
                                  ),
                                  icon:
                                      Icon(
                                    item.isPublished
                                        ? Icons
                                            .visibility_off
                                        : Icons
                                            .publish_rounded,
                                    size:
                                        16,
                                    color:
                                        item.isPublished
                                            ? Colors.white
                                            : Colors.black,
                                  ),
                                  label:
                                      Text(
                                    item.isPublished
                                        ? 'Unpublish'
                                        : '📢 Publish',
                                    style:
                                        TextStyle(
                                      color:
                                          item.isPublished
                                              ? Colors.white
                                              : Colors.black,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon:
                                      const Icon(
                                    Icons
                                        .delete_outline,
                                    color:
                                        Colors.redAccent,
                                    size:
                                        20,
                                  ),
                                  tooltip:
                                      'স্থায়ীভাবে মুছে ফেলুন',
                                  onPressed:
                                      () =>
                                          _handleDelete(
                                    item,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
/// Represents a single custom field the admin has added to the booking form.
class CustomField {
  final String id;
  final String label;
  final String fieldType; // 'text', 'number', 'phone', 'dropdown'
  final bool isRequired;
  final List<String> dropdownOptions; // Only used when fieldType == 'dropdown'

  CustomField({
    required this.id,
    required this.label,
    required this.fieldType,
    this.isRequired = false,
    this.dropdownOptions = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'fieldType': fieldType,
        'isRequired': isRequired,
        'dropdownOptions': dropdownOptions,
      };

  factory CustomField.fromJson(Map<String, dynamic> json) => CustomField(
        id: json['id'],
        label: json['label'],
        fieldType: json['fieldType'],
        isRequired: json['isRequired'] ?? false,
        dropdownOptions: List<String>.from(json['dropdownOptions'] ?? []),
      );
}

/// All admin-configurable settings for the app.
class FormSettings {
  // Purpose options (dynamic radio buttons)
  List<String> purposes;


  // Standard field visibility toggles
  bool showRepresentativeName;
  bool showAddress;
  bool showMobileNumber;
  bool showReference;

  // Reference field mode
  bool referenceAsDropdown; // true = dropdown, false = text
  List<String> referenceOptions; // Options if dropdown mode

  // Custom fields added by admin
  List<CustomField> customFields;

  // Branding
  String organizationName;
  String receiptPrefix;
  int startingReceiptNumber;
  String currencySymbol;
  String logoBase64; // Base64 encoded logo image for receipt
  String rulesAttachmentBase64; // Base64 image to attach as second page of receipt

  FormSettings({
    List<String>? purposes,

    this.showRepresentativeName = true,
    this.showAddress = true,
    this.showMobileNumber = true,
    this.showReference = true,
    this.referenceAsDropdown = false,
    List<String>? referenceOptions,
    List<CustomField>? customFields,
    this.organizationName = 'Qurbani Management',
    this.receiptPrefix = 'RCPT-',
    this.startingReceiptNumber = 1,
    this.currencySymbol = '₹',
    this.logoBase64 = '',
    this.rulesAttachmentBase64 = '',
  })  : purposes = purposes ?? ['Qurbani', 'Aqiqah'],
        referenceOptions = referenceOptions ?? ['Friend', 'Social Media', 'Masjid Announcement', 'Other'],
        customFields = customFields ?? [];

  Map<String, dynamic> toJson() => {
        'purposes': purposes,

        'showRepresentativeName': showRepresentativeName,
        'showAddress': showAddress,
        'showMobileNumber': showMobileNumber,
        'showReference': showReference,
        'referenceAsDropdown': referenceAsDropdown,
        'referenceOptions': referenceOptions,
        'customFields': customFields.map((f) => f.toJson()).toList(),
        'organizationName': organizationName,
        'receiptPrefix': receiptPrefix,
        'startingReceiptNumber': startingReceiptNumber,
        'currencySymbol': currencySymbol,
        'logoBase64': logoBase64,
        'rulesAttachmentBase64': rulesAttachmentBase64,
      };

  factory FormSettings.fromJson(Map<String, dynamic> json) => FormSettings(
        purposes: List<String>.from(json['purposes'] ?? ['Qurbani', 'Aqiqah']),

        showRepresentativeName: json['showRepresentativeName'] ?? true,
        showAddress: json['showAddress'] ?? true,
        showMobileNumber: json['showMobileNumber'] ?? true,
        showReference: json['showReference'] ?? true,
        referenceAsDropdown: json['referenceAsDropdown'] ?? false,
        referenceOptions: List<String>.from(json['referenceOptions'] ?? []),
        customFields: (json['customFields'] as List<dynamic>?)
                ?.map((f) => CustomField.fromJson(f))
                .toList() ??
            [],
        organizationName: json['organizationName'] ?? 'Qurbani Management',
        receiptPrefix: json['receiptPrefix'] ?? 'RCPT-',
        startingReceiptNumber: json['startingReceiptNumber'] ?? 1,
        currencySymbol: json['currencySymbol'] ?? '₹',
        logoBase64: json['logoBase64'] ?? '',
        rulesAttachmentBase64: json['rulesAttachmentBase64'] ?? '',
      );
}

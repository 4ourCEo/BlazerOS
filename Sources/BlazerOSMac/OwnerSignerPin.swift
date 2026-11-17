/// Compile-time owner trust anchor for the signed Mac application.
///
/// Owner-selected stable signing certificate SHA-1. Neither Info.plist nor the
/// embedded manifest is trusted as the source of this value.
enum OwnerSignerPin {
    static let certificateSHA1 = "F807B48EC7FCB1B4AF3E77B1EC20CDA57FAF7819"
}

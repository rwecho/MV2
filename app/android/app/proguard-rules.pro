# MV2 keeps R8 defaults. Flutter's Gradle plugin contributes its own rules
# (build/flutter_assets / flutter_proguard_rules.pro), and the Firebase SDKs
# ship theirs inside the AARs.
#
# Add `-keep` rules here only if a release build loses something that worked in
# debug — prefer fixing it at the source (annotations) over blanket keeps.

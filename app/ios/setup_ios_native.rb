#!/usr/bin/env ruby
# frozen_string_literal: true

# Sets up the native iOS integration in ios/Runner.xcodeproj:
#
#   1. registers `Runner/MV2NativeBridge.swift` as a source of the Runner target
#      (a file dropped into the folder is NOT compiled until it is a member of a
#      target's Sources phase);
#   2. adds (or updates) the `MV2Widget` app-extension target and embeds it.
#
# Xcode's "add a target" wizard is not scriptable, and hand-editing
# project.pbxproj is how projects get corrupted. This uses the same `xcodeproj`
# gem CocoaPods ships, so the result is indistinguishable from the wizard's.
#
# Run once from the repository root:
#
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_1/libexec \
#     /opt/homebrew/opt/ruby/bin/ruby app/ios/setup_ios_native.rb
#
# (Any Ruby with the xcodeproj gem works; `pod` bundles one.)
#
# The script is idempotent: re-running it refreshes build settings rather than
# creating a second target.

require 'xcodeproj'

IOS_DIR = __dir__
PROJECT_PATH = File.join(IOS_DIR, 'Runner.xcodeproj')
TARGET_NAME = 'MV2Widget'
HOST_TARGET = 'Runner'
HOST_BRIDGE_SOURCE = 'MV2NativeBridge.swift'
BUNDLE_ID = 'tech.zb.v2ex.maui.app.widget'
DEVELOPMENT_TEAM = '2VA9TC6SG4'
DEPLOYMENT_TARGET = '17.0'

SOURCES = %w[
  MV2WidgetBundle.swift
  MV2UnreadWidget.swift
  MV2LockScreenWidget.swift
  WidgetSnapshot.swift
].freeze
# Referenced in the navigator but never compiled or copied.
RESOURCES = %w[Info.plist MV2Widget.entitlements].freeze
# Firebase reads this from the **app bundle**, so it must be a member of the
# Runner target's Copy Bundle Resources phase. A plist that only exists on disk
# is invisible to `Firebase.initializeApp()`.
HOST_RESOURCE = 'GoogleService-Info.plist'

project = Xcodeproj::Project.open(PROJECT_PATH)

host = project.targets.find { |target| target.name == HOST_TARGET }
abort("error: #{HOST_TARGET} target not found in #{PROJECT_PATH}") unless host

# --------------------------------------------- app-side bridge source file
host_group = project.main_group.children.find do |child|
  child.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
    (child.name == HOST_TARGET || child.path == HOST_TARGET)
end
abort("error: #{HOST_TARGET} group not found in #{PROJECT_PATH}") if host_group.nil?

bridge = host_group.files.find { |file| file.path == HOST_BRIDGE_SOURCE } ||
         host_group.new_reference(HOST_BRIDGE_SOURCE)
unless host.source_build_phase.files_references.include?(bridge)
  host.add_file_references([bridge])
  puts "added #{HOST_TARGET}/#{HOST_BRIDGE_SOURCE} to the #{HOST_TARGET} target"
end

# ------------------------------------------------- Firebase config resource
if File.exist?(File.join(IOS_DIR, HOST_TARGET, HOST_RESOURCE))
  firebase_config = host_group.files.find { |file| file.path == HOST_RESOURCE } ||
                    host_group.new_reference(HOST_RESOURCE)
  unless host.resources_build_phase.files_references.include?(firebase_config)
    host.add_resources([firebase_config])
    puts "added #{HOST_TARGET}/#{HOST_RESOURCE} to the #{HOST_TARGET} resources"
  end
else
  warn "warning: #{HOST_TARGET}/#{HOST_RESOURCE} not found — push will be " \
       'unavailable until the Firebase iOS config is added'
end

# ------------------------------------------------------- Xcode capabilities
# Xcode records the enabled capabilities here; without them the Signing &
# Capabilities tab shows nothing and a regenerated profile may drop the
# entitlement, even though Runner.entitlements already declares it.
target_attributes = project.root_object.attributes['TargetAttributes'] ||= {}
host_attributes = target_attributes[host.uuid] ||= {}
capabilities = host_attributes['SystemCapabilities'] ||= {}
capabilities['com.apple.Push'] = { 'enabled' => 1 }
capabilities['com.apple.BackgroundModes'] = { 'enabled' => 1 }

group = project.main_group.children.find do |child|
  child.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
    (child.name == TARGET_NAME || child.path == TARGET_NAME)
end
group ||= project.main_group.new_group(TARGET_NAME, TARGET_NAME)
group.set_path(TARGET_NAME) unless group.path == TARGET_NAME

target = project.targets.find { |candidate| candidate.name == TARGET_NAME }
if target.nil?
  target = project.new_target(:app_extension, TARGET_NAME, :ios, DEPLOYMENT_TARGET)
  puts "created target #{TARGET_NAME}"
else
  puts "updating existing target #{TARGET_NAME}"
end

# ------------------------------------------------------------------ sources
source_refs = SOURCES.map do |name|
  group.files.find { |file| file.path == name } || group.new_reference(name)
end
compiled = target.source_build_phase.files_references
target.add_file_references(source_refs.reject { |ref| compiled.include?(ref) })

RESOURCES.each do |name|
  group.new_reference(name) unless group.files.any? { |file| file.path == name }
end

# ----------------------------------------------------------- build settings
# `Flutter/Generated.xcconfig` carries FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER,
# so the extension's version stays in step with pubspec.yaml automatically.
# App Store validation requires the extension and the app to agree on both.
generated = project.files.find { |file| file.path == 'Flutter/Generated.xcconfig' }
abort('error: Flutter/Generated.xcconfig not found — run `flutter pub get` first') if generated.nil?

target.build_configurations.each do |config|
  config.base_configuration_reference = generated
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => "#{TARGET_NAME}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS' => "#{TARGET_NAME}/#{TARGET_NAME}.entitlements",
    'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_TEAM' => DEVELOPMENT_TEAM,
    'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'SKIP_INSTALL' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)',
    'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)',
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@executable_path/../../Frameworks',
    ],
    'SWIFT_EMIT_LOC_STRINGS' => 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
  )
end

# ------------------------------------------------------- embed into the app
embed = host.copy_files_build_phases.find do |phase|
  phase.name == 'Embed Foundation Extensions'
end
embed ||= host.new_copy_files_build_phase('Embed Foundation Extensions')
embed.dst_subfolder_spec = '13' # PlugIns
product = target.product_reference
unless embed.files_references.include?(product)
  build_file = embed.add_file_reference(product)
  build_file.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy] }
end

host.add_dependency(target) unless host.dependencies.any? do |dependency|
  dependency.target == target
end

# --------------------------------------------- Crashlytics dSYM upload (iOS)
# `firebase-ios-sdk` comes in through Swift Package Manager, so the uploader
# lives in the SourcePackages checkout rather than PODS_ROOT.
#
# Deliberately declares **no input paths**: the official recipe lists files
# inside `Runner.app`, which is the same shape that produced the "Cycle inside
# Runner" error above. The script is cheap when there is nothing to upload.
unless host.build_phases.any? do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) &&
    phase.name == 'Upload Crashlytics Symbols'
end
  crashlytics = host.new_shell_script_build_phase('Upload Crashlytics Symbols')
  crashlytics.shell_script =
    '"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"'
  crashlytics.show_env_vars_in_log = '0'
  puts 'added the Crashlytics dSYM upload phase'
end

# Xcode's new build system otherwise reports
#   "Cycle inside Runner; building could produce unreliable results"
# because both the Flutter `Thin Binary` script and the extension-embed phase
# write inside `Runner.app`. The documented Flutter workaround is to run the
# embed phase *before* `Thin Binary`.
thin_binary_index = host.build_phases.index do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) &&
    phase.name == 'Thin Binary'
end
embed_index = host.build_phases.index(embed)
if thin_binary_index && embed_index && embed_index > thin_binary_index
  host.build_phases.move(embed, thin_binary_index)
  puts 'moved "Embed Foundation Extensions" before "Thin Binary"'
end

project.save
puts "saved #{PROJECT_PATH}"
puts "  target      : #{TARGET_NAME} (#{target.product_type})"
puts "  bundle id   : #{BUNDLE_ID}"
puts "  min iOS     : #{DEPLOYMENT_TARGET}"
puts "  embedded in : #{HOST_TARGET}"

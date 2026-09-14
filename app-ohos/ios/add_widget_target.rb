#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds (or updates) the `MV2Widget` app-extension target in ios/Runner.xcodeproj.
#
# Xcode's "add a target" wizard is not scriptable, and hand-editing
# project.pbxproj is how projects get corrupted. This uses the same `xcodeproj`
# gem CocoaPods ships, so the result is indistinguishable from the wizard's.
#
# Run once from the repository root:
#
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_1/libexec \
#     /opt/homebrew/opt/ruby/bin/ruby app/ios/add_widget_target.rb
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

project = Xcodeproj::Project.open(PROJECT_PATH)

host = project.targets.find { |target| target.name == HOST_TARGET }
abort("error: #{HOST_TARGET} target not found in #{PROJECT_PATH}") unless host

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

project.save
puts "saved #{PROJECT_PATH}"
puts "  target      : #{TARGET_NAME} (#{target.product_type})"
puts "  bundle id   : #{BUNDLE_ID}"
puts "  min iOS     : #{DEPLOYMENT_TARGET}"
puts "  embedded in : #{HOST_TARGET}"
